//! Positions on the Earth and the distances between them.

use serde::{Deserialize, Serialize};

/// Mean Earth radius (IUGG), in metres. The haversine error against the
/// ellipsoid stays under 0.5 %, far below the radii the conflation works with.
pub const EARTH_RADIUS_M: f64 = 6_371_008.8;

/// A coordinate outside the WGS 84 range, or not a finite number.
#[derive(Debug, Clone, Copy, PartialEq, thiserror::Error)]
#[error("invalid position: lat {lat}, lon {lon}")]
pub struct InvalidPosition {
    /// The latitude as received.
    pub lat: f64,
    /// The longitude as received.
    pub lon: f64,
}

/// A WGS 84 point, validated on construction so that no raw pair of floats
/// crosses a boundary unchecked.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(try_from = "RawPosition", into = "RawPosition")]
pub struct Position {
    lat: f64,
    lon: f64,
}

#[derive(Serialize, Deserialize)]
struct RawPosition {
    lat: f64,
    lon: f64,
}

impl TryFrom<RawPosition> for Position {
    type Error = InvalidPosition;

    fn try_from(raw: RawPosition) -> Result<Self, Self::Error> {
        Self::new(raw.lat, raw.lon)
    }
}

impl From<Position> for RawPosition {
    fn from(p: Position) -> Self {
        Self {
            lat: p.lat,
            lon: p.lon,
        }
    }
}

impl Position {
    /// A position, if `lat` is in [-90, 90] and `lon` in [-180, 180].
    ///
    /// # Errors
    ///
    /// [`InvalidPosition`] when a coordinate is out of range or not finite.
    pub fn new(lat: f64, lon: f64) -> Result<Self, InvalidPosition> {
        if lat.is_finite()
            && lon.is_finite()
            && (-90.0..=90.0).contains(&lat)
            && (-180.0..=180.0).contains(&lon)
        {
            Ok(Self { lat, lon })
        } else {
            Err(InvalidPosition { lat, lon })
        }
    }

    /// Latitude in degrees.
    #[must_use]
    pub const fn lat(self) -> f64 {
        self.lat
    }

    /// Longitude in degrees.
    #[must_use]
    pub const fn lon(self) -> f64 {
        self.lon
    }

    /// Great-circle distance to `other`, in metres (haversine on a sphere).
    #[must_use]
    pub fn distance_m(self, other: Self) -> f64 {
        let (phi1, phi2) = (self.lat.to_radians(), other.lat.to_radians());
        let dphi = (other.lat - self.lat).to_radians();
        let dlambda = (other.lon - self.lon).to_radians();
        let h =
            (dphi / 2.0).sin().powi(2) + phi1.cos() * phi2.cos() * (dlambda / 2.0).sin().powi(2);
        // `min` guards asin against a rounding error just above 1.
        2.0 * EARTH_RADIUS_M * h.sqrt().min(1.0).asin()
    }
}

/// A latitude/longitude rectangle, south-west to north-east. It never crosses
/// the antimeridian: `west <= east` is part of its validity.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BBox {
    south: f64,
    west: f64,
    north: f64,
    east: f64,
}

/// Why a bounding box was refused.
#[derive(Debug, Clone, Copy, PartialEq, thiserror::Error)]
#[non_exhaustive]
pub enum InvalidBBox {
    /// A corner is outside the WGS 84 range or not finite.
    #[error("a corner of the box is not a valid position")]
    Corner(#[from] InvalidPosition),
    /// South is above north or west is east of east.
    #[error("the box is inverted (south must be <= north and west <= east)")]
    Inverted,
}

impl BBox {
    /// A box from its four edges, in degrees.
    ///
    /// # Errors
    ///
    /// [`InvalidBBox`] when a corner is invalid or the box is inverted.
    pub fn new(south: f64, west: f64, north: f64, east: f64) -> Result<Self, InvalidBBox> {
        Position::new(south, west)?;
        Position::new(north, east)?;
        if south > north || west > east {
            return Err(InvalidBBox::Inverted);
        }
        Ok(Self {
            south,
            west,
            north,
            east,
        })
    }

    /// Southern edge, degrees of latitude.
    #[must_use]
    pub const fn south(self) -> f64 {
        self.south
    }

    /// Western edge, degrees of longitude.
    #[must_use]
    pub const fn west(self) -> f64 {
        self.west
    }

    /// Northern edge, degrees of latitude.
    #[must_use]
    pub const fn north(self) -> f64 {
        self.north
    }

    /// Eastern edge, degrees of longitude.
    #[must_use]
    pub const fn east(self) -> f64 {
        self.east
    }

    /// Area in square degrees: the unit the API bounds viewports with,
    /// because it is what a client can compute without a projection.
    #[must_use]
    pub fn area_deg2(self) -> f64 {
        (self.north - self.south) * (self.east - self.west)
    }

    /// Whether `p` lies inside the box, edges included.
    #[must_use]
    pub fn contains(self, p: Position) -> bool {
        (self.south..=self.north).contains(&p.lat) && (self.west..=self.east).contains(&p.lon)
    }
}

#[cfg(test)]
mod tests {
    use proptest::prelude::*;

    use super::*;

    #[test]
    fn out_of_range_coordinates_are_refused() {
        assert!(Position::new(90.1, 0.0).is_err());
        assert!(Position::new(0.0, -180.5).is_err());
        assert!(Position::new(f64::NAN, 0.0).is_err());
        assert!(Position::new(f64::INFINITY, 0.0).is_err());
        assert!(Position::new(-90.0, 180.0).is_ok());
    }

    #[test]
    fn a_known_distance_is_measured() {
        // Paris Notre-Dame to the Eiffel Tower: 4.1 km on the map.
        let notre_dame = Position::new(48.852_968, 2.349_902).unwrap();
        let eiffel = Position::new(48.858_370, 2.294_481).unwrap();
        let d = notre_dame.distance_m(eiffel);
        assert!((d - 4_100.0).abs() < 60.0, "got {d}");
    }

    #[test]
    fn one_millidegree_of_latitude_is_about_111_metres() {
        let a = Position::new(45.0, 3.0).unwrap();
        let b = Position::new(45.001, 3.0).unwrap();
        assert!((a.distance_m(b) - 111.2).abs() < 0.5);
    }

    #[test]
    fn serde_refuses_an_invalid_position() {
        let ok: Position = serde_json::from_str(r#"{"lat":1.5,"lon":2.5}"#).unwrap();
        assert_eq!((ok.lat(), ok.lon()), (1.5, 2.5));
        assert!(serde_json::from_str::<Position>(r#"{"lat":100.0,"lon":2.5}"#).is_err());
    }

    #[test]
    fn a_bbox_validates_its_edges() {
        assert_eq!(BBox::new(46.0, 3.0, 45.0, 4.0), Err(InvalidBBox::Inverted));
        assert_eq!(BBox::new(45.0, 4.0, 46.0, 3.0), Err(InvalidBBox::Inverted));
        assert!(matches!(
            BBox::new(45.0, 3.0, 91.0, 4.0),
            Err(InvalidBBox::Corner(_))
        ));
        let b = BBox::new(45.0, 3.0, 46.0, 5.0).unwrap();
        assert!((b.area_deg2() - 2.0).abs() < 1e-12);
        assert!(
            b.contains(Position::new(45.0, 5.0).unwrap()),
            "edges are inside"
        );
        assert!(!b.contains(Position::new(46.1, 4.0).unwrap()));
    }

    fn position() -> impl Strategy<Value = Position> {
        (-90.0..=90.0f64, -180.0..=180.0f64).prop_map(|(lat, lon)| Position::new(lat, lon).unwrap())
    }

    proptest! {
        #[test]
        fn distance_is_a_symmetric_non_negative_measure(a in position(), b in position()) {
            let d = a.distance_m(b);
            prop_assert!(d >= 0.0);
            prop_assert!((d - b.distance_m(a)).abs() < 1e-6);
            prop_assert!(a.distance_m(a) < 1e-6);
            // Half the circumference is the farthest two points can be.
            prop_assert!(d <= std::f64::consts::PI * EARTH_RADIUS_M + 1.0);
        }
    }
}
