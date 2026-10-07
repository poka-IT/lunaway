//! A Mapbox Vector Tile reader for the tests of the map tiles (the points'
//! and the places' layers): layers, their keys and values, and each
//! feature's tags and points.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::collections::BTreeMap;

use serde_json::{Value, json};

/// The tile `z/x/y` that holds `(lat, lon)`.
pub(crate) fn tile_of(lat: f64, lon: f64, z: u32) -> (u32, u32) {
    let n = f64::from(1u32 << z);
    let x = ((lon + 180.0) / 360.0 * n).floor();
    let r = lat.to_radians();
    let y = ((1.0 - (r.tan() + 1.0 / r.cos()).ln() / std::f64::consts::PI) / 2.0 * n).floor();
    (x as u32, y as u32)
}

fn varint(b: &[u8], i: &mut usize) -> u64 {
    let mut v = 0u64;
    let mut shift = 0;
    loop {
        let byte = b[*i];
        *i += 1;
        v |= u64::from(byte & 0x7f) << shift;
        if byte & 0x80 == 0 {
            return v;
        }
        shift += 7;
    }
}

/// The fields of a message: (field number, wire type, varint or bytes).
fn fields(b: &[u8]) -> Vec<(u64, u64, u64, &[u8])> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < b.len() {
        let key = varint(b, &mut i);
        let (field, wire) = (key >> 3, key & 7);
        match wire {
            0 => out.push((field, wire, varint(b, &mut i), &b[0..0])),
            1 => {
                out.push((
                    field,
                    wire,
                    u64::from_le_bytes(b[i..i + 8].try_into().unwrap()),
                    &b[0..0],
                ));
                i += 8;
            }
            2 => {
                let len = usize::try_from(varint(b, &mut i)).unwrap();
                out.push((field, wire, 0, &b[i..i + len]));
                i += len;
            }
            5 => {
                out.push((
                    field,
                    wire,
                    u64::from(u32::from_le_bytes(b[i..i + 4].try_into().unwrap())),
                    &b[0..0],
                ));
                i += 4;
            }
            w => panic!("wire type {w}"),
        }
    }
    out
}

fn packed(b: &[u8]) -> Vec<u64> {
    let mut i = 0;
    let mut out = Vec::new();
    while i < b.len() {
        out.push(varint(b, &mut i));
    }
    out
}

fn unzigzag(n: u64) -> i64 {
    ((n >> 1) as i64) ^ -((n & 1) as i64)
}

/// A decoded feature: its properties and its points in tile units (one,
/// or several for a MultiPoint).
#[derive(Debug)]
pub(crate) struct Feature {
    pub(crate) props: BTreeMap<String, Value>,
    pub(crate) points: Vec<(i64, i64)>,
}

impl Feature {
    /// The point of a single-point feature.
    pub(crate) fn point(&self) -> (i64, i64) {
        assert_eq!(self.points.len(), 1, "a single point: {self:?}");
        self.points[0]
    }
}

/// The layers of a tile, by name.
pub(crate) fn decode(tile: &[u8]) -> BTreeMap<String, (u64, Vec<Feature>)> {
    let mut layers = BTreeMap::new();
    for (field, _, _, layer) in fields(tile) {
        assert_eq!(field, 3, "a tile holds layers only");
        let lf = fields(layer);
        let name = lf
            .iter()
            .find(|f| f.0 == 1)
            .map(|f| String::from_utf8(f.3.to_vec()).unwrap())
            .unwrap();
        let extent = lf.iter().find(|f| f.0 == 5).map_or(4096, |f| f.2);
        let keys: Vec<String> = lf
            .iter()
            .filter(|f| f.0 == 3)
            .map(|f| String::from_utf8(f.3.to_vec()).unwrap())
            .collect();
        let values: Vec<Value> = lf
            .iter()
            .filter(|f| f.0 == 4)
            .map(|f| {
                let (vf, _, n, bytes) = fields(f.3)[0];
                match vf {
                    1 => Value::String(String::from_utf8(bytes.to_vec()).unwrap()),
                    2 => json!(f32::from_bits(u32::try_from(n).unwrap())),
                    3 => json!(f64::from_bits(n)),
                    4 | 5 => json!(n),
                    6 => json!(unzigzag(n)),
                    7 => Value::Bool(n != 0),
                    other => panic!("value field {other}"),
                }
            })
            .collect();
        let features = lf
            .iter()
            .filter(|f| f.0 == 2)
            .map(|f| {
                let ff = fields(f.3);
                let tags = ff
                    .iter()
                    .find(|x| x.0 == 2)
                    .map(|x| packed(x.3))
                    .unwrap_or_default();
                let geometry = ff.iter().find(|x| x.0 == 4).map(|x| packed(x.3)).unwrap();
                assert_eq!(geometry[0] & 7, 1, "points: one MoveTo");
                let count = usize::try_from(geometry[0] >> 3).unwrap();
                assert_eq!(
                    geometry.len(),
                    1 + 2 * count,
                    "{count} points and nothing else"
                );
                let mut cursor = (0_i64, 0_i64);
                let points = geometry[1..]
                    .chunks(2)
                    .map(|d| {
                        cursor = (cursor.0 + unzigzag(d[0]), cursor.1 + unzigzag(d[1]));
                        cursor
                    })
                    .collect();
                let props = tags
                    .chunks(2)
                    .map(|kv| {
                        (
                            keys[usize::try_from(kv[0]).unwrap()].clone(),
                            values[usize::try_from(kv[1]).unwrap()].clone(),
                        )
                    })
                    .collect();
                Feature { props, points }
            })
            .collect();
        layers.insert(name, (extent, features));
    }
    layers
}
