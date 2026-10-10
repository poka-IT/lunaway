//! Reading Overture's GeoParquet files of places, a row group at a time
//! and only the columns Lunaway reads, with the row API of the `parquet`
//! crate.
//!
//! A file holds about 5 million places in 256 row groups of some 20,000,
//! sorted by place: a row group covers a small area, and its statistics
//! give the box of its places (`bbox.xmin` ... `bbox.ymax`). A group whose
//! box reaches no area of the run is not read at all, so a run of France
//! reads the French part of the four files that cover it.

use std::{collections::BTreeSet, fs::File, path::Path};

use parquet::{
    file::{
        metadata::RowGroupMetaData,
        reader::{FileReader, SerializedFileReader},
        statistics::Statistics,
    },
    record::{Field, Row},
    schema::{parser::parse_message_type, types::Type},
};

use crate::IngestError;

/// The columns read, as the file declares them (a projection must be
/// contained in the file's schema, names and types alike).
const PROJECTION: &str = "
message schema {
  optional binary id (UTF8);
  optional binary geometry;
  optional double confidence;
  optional group websites (LIST) { repeated group list { optional binary element (UTF8); } }
  optional group phones (LIST) { repeated group list { optional binary element (UTF8); } }
  optional group brand {
    optional binary wikidata (UTF8);
    optional group names { optional binary primary (UTF8); }
  }
  optional group addresses (LIST) {
    repeated group list {
      optional group element {
        optional binary freeform (UTF8);
        optional binary locality (UTF8);
        optional binary postcode (UTF8);
        optional binary region (UTF8);
        optional binary country (UTF8);
      }
    }
  }
  optional group names { optional binary primary (UTF8); }
  optional group sources (LIST) {
    repeated group list {
      optional group element {
        optional binary dataset (UTF8);
        optional binary license (UTF8);
        optional binary record_id (UTF8);
        optional binary update_time (UTF8);
      }
    }
  }
  optional binary operating_status (UTF8);
  optional binary basic_category (UTF8);
  optional group taxonomy {
    optional binary primary (UTF8);
    optional group hierarchy (LIST) { repeated group list { optional binary element (UTF8); } }
  }
  optional int32 version;
  optional group bbox {
    optional double xmin;
    optional double xmax;
    optional double ymin;
    optional double ymax;
  }
}";

/// One place as the file gives it, the columns Lunaway reads.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Place {
    /// Overture's identifier (GERS), stable across releases.
    pub id: String,
    /// Longitude, from the point geometry (or the centre of its box).
    pub lon: Option<f64>,
    /// Latitude.
    pub lat: Option<f64>,
    /// How sure Overture is that the place exists, 0 to 1.
    pub confidence: Option<f64>,
    /// Websites.
    pub websites: Vec<String>,
    /// Phone numbers.
    pub phones: Vec<String>,
    /// The brand's name.
    pub brand: Option<String>,
    /// The brand's Wikidata item.
    pub brand_wikidata: Option<String>,
    /// The first address.
    pub address: Option<PlaceAddress>,
    /// The name.
    pub name: Option<String>,
    /// Who said what of the place.
    pub sources: Vec<PlaceSource>,
    /// `open`, `temporarily_closed`, `permanently_closed`, or nothing.
    pub operating_status: Option<String>,
    /// The simple category (about 280 of them).
    pub basic_category: Option<String>,
    /// The taxonomy's leaf.
    pub category: Option<String>,
    /// The taxonomy's path, from the top.
    pub hierarchy: Vec<String>,
    /// How many times Overture changed the place.
    pub version: Option<i32>,
}

/// The first address of a place.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PlaceAddress {
    /// The street and number, as one line.
    pub freeform: Option<String>,
    /// The town.
    pub locality: Option<String>,
    /// The postcode.
    pub postcode: Option<String>,
    /// The region.
    pub region: Option<String>,
    /// The country (ISO 3166-1), as the source gives it.
    pub country: Option<String>,
}

/// One source of a place: a dataset, under its licence.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PlaceSource {
    /// `meta`, `AllThePlaces`, `Foursquare`, `Overture`...
    pub dataset: Option<String>,
    /// Its licence, as an SPDX identifier.
    pub license: Option<String>,
    /// The record's id in the dataset.
    pub record_id: Option<String>,
    /// When the dataset last changed it.
    pub update_time: Option<String>,
}

/// What a read of a file did with its row groups.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct GroupCounts {
    /// Row groups in the file.
    pub groups: usize,
    /// Row groups read: their box reaches an area of the run.
    pub read: usize,
    /// Places in the row groups read.
    pub rows: u64,
}

/// The box of a row group's places, from its statistics, as `[south,
/// west, north, east]`; `None` when the file says nothing of it.
fn group_box(group: &RowGroupMetaData) -> Option<[f64; 4]> {
    let stat = |path: &str, max: bool| -> Option<f64> {
        let column = group
            .columns()
            .iter()
            .find(|c| c.column_path().string() == path)?;
        match column.statistics()? {
            Statistics::Double(s) => {
                if max {
                    s.max_opt().copied()
                } else {
                    s.min_opt().copied()
                }
            }
            _ => None,
        }
        // A statistic that is no number says nothing: the group is read.
        .filter(|v| v.is_finite())
    };
    Some([
        stat("bbox.ymin", false)?,
        stat("bbox.xmin", false)?,
        stat("bbox.ymax", true)?,
        stat("bbox.xmax", true)?,
    ])
}

/// Whether a row group's box reaches one of `areas`, by the boundaries'
/// cells alone ([`lunaway_domain::region::areas_in_box`]): a group read in
/// vain costs a moment, its places are checked one by one; a box unknown
/// is read.
fn reaches(bbox: Option<[f64; 4]>, areas: &BTreeSet<String>) -> bool {
    bbox.is_none_or(|[south, west, north, east]| {
        lunaway_domain::region::areas_in_box(south, west, north, east)
            .iter()
            .any(|a| areas.contains(*a))
    })
}

/// Whether a box `[south, west, north, east]` reaches the land of one of
/// `areas` ([`lunaway_domain::region::box_reaches`]): what decides which
/// files of a release a run downloads.
#[must_use]
pub fn box_reaches(bbox: [f64; 4], areas: &BTreeSet<String>) -> bool {
    let [south, west, north, east] = bbox;
    lunaway_domain::region::box_reaches(south, west, north, east, areas)
}

/// Reads the places of the row groups of `path` whose box reaches one of
/// `areas`, handing them to `sink` one row group at a time. CPU-bound and
/// blocking: run it on a blocking thread.
///
/// # Errors
///
/// [`IngestError::Parquet`] when the file, a row group or a row does not
/// read, and whatever `sink` returns.
pub fn read_places(
    path: &Path,
    areas: &BTreeSet<String>,
    mut sink: impl FnMut(Vec<Place>) -> Result<(), IngestError>,
) -> Result<GroupCounts, IngestError> {
    let err = |source| IngestError::Parquet {
        path: path.to_owned(),
        source,
    };
    let file = File::open(path).map_err(|source| IngestError::Cache {
        path: path.to_owned(),
        source,
    })?;
    let reader = SerializedFileReader::new(file).map_err(err)?;
    let projection: Type = parse_message_type(PROJECTION).map_err(err)?;
    let mut counts = GroupCounts {
        groups: reader.num_row_groups(),
        ..GroupCounts::default()
    };
    for i in 0..reader.num_row_groups() {
        let group = reader.get_row_group(i).map_err(err)?;
        if !reaches(group_box(group.metadata()), areas) {
            continue;
        }
        counts.read += 1;
        let rows = group.get_row_iter(Some(projection.clone())).map_err(err)?;
        // The footer's count, which a broken file may inflate, bounded.
        let mut places = Vec::with_capacity(
            usize::try_from(group.metadata().num_rows())
                .unwrap_or(0)
                .min(65_536),
        );
        for row in rows {
            places.push(place(row.map_err(err)?));
        }
        counts.rows += places.len() as u64;
        sink(places)?;
    }
    Ok(counts)
}

/// A text column, trimmed, `None` when empty.
fn text(field: Field) -> Option<String> {
    match field {
        Field::Str(s) => {
            let t = s.trim();
            if t.is_empty() {
                None
            } else if t.len() == s.len() {
                Some(s)
            } else {
                Some(t.to_owned())
            }
        }
        _ => None,
    }
}

/// The elements of a list column.
fn list(field: Field) -> Vec<Field> {
    match field {
        Field::ListInternal(l) => l.elements().to_vec(),
        _ => Vec::new(),
    }
}

/// The columns of a struct column.
fn group(field: Field) -> Vec<(String, Field)> {
    match field {
        Field::Group(r) => r.into_columns(),
        _ => Vec::new(),
    }
}

fn double(field: &Field) -> Option<f64> {
    match field {
        Field::Double(d) if d.is_finite() => Some(*d),
        _ => None,
    }
}

/// The point of a WKB geometry: byte order, type 1 (a point), x, y.
#[must_use]
pub fn wkb_point(bytes: &[u8]) -> Option<(f64, f64)> {
    let (&order, rest) = bytes.split_first()?;
    let read_u32 = |b: &[u8]| -> Option<u32> {
        let a: [u8; 4] = b.get(..4)?.try_into().ok()?;
        Some(if order == 1 {
            u32::from_le_bytes(a)
        } else {
            u32::from_be_bytes(a)
        })
    };
    let read_f64 = |b: &[u8]| -> Option<f64> {
        let a: [u8; 8] = b.get(..8)?.try_into().ok()?;
        Some(if order == 1 {
            f64::from_le_bytes(a)
        } else {
            f64::from_be_bytes(a)
        })
    };
    if order > 1 || read_u32(rest)? != 1 {
        return None;
    }
    let x = read_f64(rest.get(4..)?)?;
    let y = read_f64(rest.get(12..)?)?;
    (x.is_finite() && y.is_finite()).then_some((x, y))
}

/// A row as a [`Place`].
fn place(row: Row) -> Place {
    let mut p = Place::default();
    let mut bbox: [Option<f64>; 4] = [None; 4];
    let mut point = None;
    for (name, field) in row.into_columns() {
        match name.as_str() {
            "id" => p.id = text(field).unwrap_or_default(),
            "geometry" => {
                if let Field::Bytes(b) = &field {
                    point = wkb_point(b.data());
                }
            }
            "confidence" => p.confidence = double(&field),
            "websites" => p.websites = list(field).into_iter().filter_map(text).collect(),
            "phones" => p.phones = list(field).into_iter().filter_map(text).collect(),
            "brand" => {
                for (k, v) in group(field) {
                    match k.as_str() {
                        "wikidata" => p.brand_wikidata = text(v),
                        "names" => {
                            p.brand = group(v)
                                .into_iter()
                                .find(|(k, _)| k == "primary")
                                .and_then(|(_, v)| text(v));
                        }
                        _ => {}
                    }
                }
            }
            "addresses" => {
                p.address = list(field).into_iter().next().map(|first| {
                    let mut a = PlaceAddress::default();
                    for (k, v) in group(first) {
                        match k.as_str() {
                            "freeform" => a.freeform = text(v),
                            "locality" => a.locality = text(v),
                            "postcode" => a.postcode = text(v),
                            "region" => a.region = text(v),
                            "country" => a.country = text(v),
                            _ => {}
                        }
                    }
                    a
                });
            }
            "names" => {
                p.name = group(field)
                    .into_iter()
                    .find(|(k, _)| k == "primary")
                    .and_then(|(_, v)| text(v));
            }
            "sources" => {
                p.sources = list(field)
                    .into_iter()
                    .map(|s| {
                        let mut out = PlaceSource::default();
                        for (k, v) in group(s) {
                            match k.as_str() {
                                "dataset" => out.dataset = text(v),
                                "license" => out.license = text(v),
                                "record_id" => out.record_id = text(v),
                                "update_time" => out.update_time = text(v),
                                _ => {}
                            }
                        }
                        out
                    })
                    .collect();
            }
            "operating_status" => p.operating_status = text(field),
            "basic_category" => p.basic_category = text(field),
            "taxonomy" => {
                for (k, v) in group(field) {
                    match k.as_str() {
                        "primary" => p.category = text(v),
                        "hierarchy" => {
                            p.hierarchy = list(v).into_iter().filter_map(text).collect();
                        }
                        _ => {}
                    }
                }
            }
            "version" => {
                if let Field::Int(v) = field {
                    p.version = Some(v);
                }
            }
            "bbox" => {
                for (k, v) in group(field) {
                    let slot = match k.as_str() {
                        "xmin" => 0,
                        "xmax" => 1,
                        "ymin" => 2,
                        "ymax" => 3,
                        _ => continue,
                    };
                    bbox[slot] = double(&v);
                }
            }
            _ => {}
        }
    }
    let (lon, lat) = point
        .or_else(|| match bbox {
            [Some(x0), Some(x1), Some(y0), Some(y1)] => Some(((x0 + x1) / 2.0, (y0 + y1) / 2.0)),
            _ => None,
        })
        .unzip();
    p.lon = lon;
    p.lat = lat;
    p
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_wkb_point_reads_in_either_byte_order() {
        let mut le = vec![1, 1, 0, 0, 0];
        le.extend_from_slice(&(-0.0765_f64).to_le_bytes());
        le.extend_from_slice(&47.2598_f64.to_le_bytes());
        assert_eq!(wkb_point(&le), Some((-0.0765, 47.2598)));
        let mut be = vec![0, 0, 0, 0, 1];
        be.extend_from_slice(&2.35_f64.to_be_bytes());
        be.extend_from_slice(&48.85_f64.to_be_bytes());
        assert_eq!(wkb_point(&be), Some((2.35, 48.85)));
        let mut line = vec![1, 2, 0, 0, 0];
        line.extend_from_slice(&[0; 16]);
        assert_eq!(wkb_point(&line), None, "a line is no point");
        assert_eq!(wkb_point(&le[..12]), None, "a cut geometry");
    }

    #[test]
    fn a_row_group_far_from_every_area_is_not_read() {
        let france: BTreeSet<String> = ["FR".to_owned()].into();
        assert!(reaches(Some([47.2, -0.2, 47.3, 0.0]), &france));
        assert!(
            !reaches(Some([40.6, -74.1, 40.9, -73.8]), &france),
            "New York"
        );
        assert!(reaches(None, &france), "a group without statistics is read");
    }
}
