//! The encoded polyline format of a route's geometry, at the precision
//! Valhalla uses (`shape_format: polyline6`, six decimals): each coordinate
//! is the difference from the previous one, zig-zag encoded in chunks of
//! five bits offset by 63 (Google's "Encoded Polyline Algorithm Format").

use crate::{InvalidPosition, Position};

/// Decimal places of Valhalla's polyline.
pub const PRECISION: u32 = 6;

/// Why a polyline does not decode.
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
#[non_exhaustive]
pub enum InvalidPolyline {
    /// A byte outside the alphabet, or a value cut short.
    #[error("the polyline is malformed at byte {at}")]
    Malformed {
        /// Offset of the offending byte.
        at: usize,
    },
    /// A decoded point lies outside the WGS 84 range.
    #[error("the polyline holds an invalid point")]
    Position(#[from] InvalidPosition),
}

fn factor() -> f64 {
    f64::from(10u32.pow(PRECISION))
}

/// Decodes a polyline6 into its points.
///
/// # Errors
///
/// [`InvalidPolyline`] when the text is cut short, holds a byte outside the
/// format, or a point outside the WGS 84 range.
pub fn decode(encoded: &str) -> Result<Vec<Position>, InvalidPolyline> {
    let bytes = encoded.as_bytes();
    let mut points = Vec::with_capacity(bytes.len() / 4);
    let (mut lat, mut lon) = (0i64, 0i64);
    let mut i = 0;
    let next = |i: &mut usize| -> Result<i64, InvalidPolyline> {
        let mut result: i64 = 0;
        let mut shift = 0u32;
        loop {
            let at = *i;
            let b = *bytes.get(at).ok_or(InvalidPolyline::Malformed { at })?;
            if !(63..=126).contains(&b) || shift > 60 {
                return Err(InvalidPolyline::Malformed { at });
            }
            let chunk = i64::from(b - 63);
            result |= (chunk & 0x1f) << shift;
            shift += 5;
            *i += 1;
            if chunk < 0x20 {
                break;
            }
        }
        Ok(if result & 1 == 1 {
            !(result >> 1)
        } else {
            result >> 1
        })
    };
    while i < bytes.len() {
        let at = i;
        // Crafted text could overflow the running sums; no real shape does.
        lat = lat
            .checked_add(next(&mut i)?)
            .ok_or(InvalidPolyline::Malformed { at })?;
        lon = lon
            .checked_add(next(&mut i)?)
            .ok_or(InvalidPolyline::Malformed { at })?;
        #[allow(
            clippy::cast_precision_loss,
            reason = "coordinates in millionths of a degree stay far below 2^52"
        )]
        let p = Position::new(lat as f64 / factor(), lon as f64 / factor())?;
        points.push(p);
    }
    Ok(points)
}

/// Encodes points as a polyline6.
#[must_use]
pub fn encode(points: &[Position]) -> String {
    let mut out = String::with_capacity(points.len() * 8);
    let (mut prev_lat, mut prev_lon) = (0i64, 0i64);
    let put = |value: i64, out: &mut String| {
        let mut v = if value < 0 { !(value << 1) } else { value << 1 };
        while v >= 0x20 {
            out.push(char::from(
                u8::try_from((0x20 | (v & 0x1f)) + 63).unwrap_or(b'?'),
            ));
            v >>= 5;
        }
        out.push(char::from(u8::try_from(v + 63).unwrap_or(b'?')));
    };
    for p in points {
        #[allow(
            clippy::cast_possible_truncation,
            reason = "a valid coordinate times 1e6 fits an i64 by far"
        )]
        let (lat, lon) = (
            (p.lat() * factor()).round() as i64,
            (p.lon() * factor()).round() as i64,
        );
        put(lat - prev_lat, &mut out);
        put(lon - prev_lon, &mut out);
        prev_lat = lat;
        prev_lon = lon;
    }
    out
}

#[cfg(test)]
mod tests {
    use proptest::prelude::*;

    use super::*;

    #[test]
    fn a_valhalla_shape_decodes() {
        // The first points of Valhalla's answer for the Utrillo case
        // (data/tmp/nav/case_utrillo.json in the research), re-encoded.
        let points = [
            Position::new(45.847_19, 1.284_76).unwrap(),
            Position::new(45.846_6, 1.285_2).unwrap(),
            Position::new(45.845_1, 1.286_37).unwrap(),
        ];
        let text = encode(&points);
        let back = decode(&text).unwrap();
        assert_eq!(back.len(), 3);
        for (a, b) in points.iter().zip(&back) {
            assert!((a.lat() - b.lat()).abs() < 1e-6 && (a.lon() - b.lon()).abs() < 1e-6);
        }
        // Google's documented example, at precision 5, decodes to these
        // points at precision 6 divided by ten.
        let google = decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@").unwrap();
        assert!((google[0].lat() * 10.0 - 38.5).abs() < 1e-9);
        assert!((google[0].lon() * 10.0 + 120.2).abs() < 1e-9);
    }

    #[test]
    fn a_cut_or_foreign_text_is_refused() {
        assert!(matches!(
            decode("_p~iF~ps|"),
            Err(InvalidPolyline::Malformed { .. })
        ));
        assert!(matches!(
            decode("abc\u{e9}"),
            Err(InvalidPolyline::Malformed { .. })
        ));
        assert_eq!(decode("").unwrap(), Vec::new());
    }

    proptest! {
        #[test]
        fn decoding_any_text_never_panics(s in "[?-~]{0,200}") {
            let _ = decode(&s);
        }

        #[test]
        fn encode_then_decode_returns_the_points(
            raw in proptest::collection::vec((-90.0..=90.0f64, -180.0..=180.0f64), 0..50)
        ) {
            let points: Vec<Position> = raw.iter().map(|(a, b)| Position::new(*a, *b).unwrap()).collect();
            let back = decode(&encode(&points)).unwrap();
            prop_assert_eq!(back.len(), points.len());
            for (a, b) in points.iter().zip(&back) {
                prop_assert!((a.lat() - b.lat()).abs() <= 0.5e-6 + 1e-12);
                prop_assert!((a.lon() - b.lon()).abs() <= 0.5e-6 + 1e-12);
            }
        }
    }
}
