//! One restriction as the graph build writes it and the publication loads
//! it: a line of `restrictions.ndjson.gz` in the graph bundle.
//!
//! The bundle is built on another machine (docs/deploy.md, "Routing"), so
//! the loader reads it as outside input: [`RestrictionRecord::check`] refuses
//! a record that the database's constraints would refuse, or worse, accept
//! with a meaning nobody intended.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use super::{
    polyline,
    restriction::{Certainty, RestrictionFeature, RestrictionKind, RestrictionSource},
};
use crate::Position;

/// Longest geometry accepted, in points: the longest restricted way of
/// France has a few thousand.
pub const MAX_POINTS: usize = 20_000;

/// A restriction with its place and provenance.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RestrictionRecord {
    /// Where it comes from.
    pub source: RestrictionSource,
    /// `way/<id>`, `node/<id>`, `ign/<cleabs>`.
    pub external_id: String,
    /// What it limits.
    pub kind: RestrictionKind,
    /// Metres or tonnes; none for a ban or an unknown clearance.
    pub limit: Option<f64>,
    /// How sure the figure is.
    pub certainty: Certainty,
    /// What the place is.
    pub feature: RestrictionFeature,
    /// The road's name, when the source gives one.
    pub name: Option<String>,
    /// The other source's figure, when two disagree.
    pub other_value: Option<f64>,
    /// The other source, when two disagree.
    pub other_source: Option<RestrictionSource>,
    /// The geometry as a polyline6: one point for a node, a line otherwise.
    pub shape: String,
    /// The date of the data.
    pub observed_at: DateTime<Utc>,
    /// Whether the limit spares the traffic going to a place beyond it
    /// ([`super::Restriction::except_destination`]). Absent from the
    /// bundles built before it existed, which read as `false`.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub except_destination: bool,
    /// Whether the record is a road enclosed behind a "sauf desserte"
    /// zone, not a sign ([`super::Restriction::enclosed`]); it carries
    /// [`Self::except_destination`]. Absent from the bundles built before
    /// it existed, which read as `false`.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub enclosed: bool,
}

/// Why a record was refused.
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
#[non_exhaustive]
pub enum InvalidRecord {
    /// The shape does not decode, is empty or too long.
    #[error("{external_id}: unusable shape")]
    Shape {
        /// The record.
        external_id: String,
    },
    /// The figure does not fit the kind.
    #[error("{external_id}: the figure does not fit a {kind:?}")]
    Limit {
        /// The record.
        external_id: String,
        /// Its kind.
        kind: RestrictionKind,
    },
    /// A text field is empty or too long.
    #[error("{external_id}: a text field is empty or too long")]
    Text {
        /// The record.
        external_id: String,
    },
}

const BANS: [RestrictionKind; 3] = [
    RestrictionKind::MotorhomeBan,
    RestrictionKind::TrailerBan,
    RestrictionKind::CaravanBan,
];

impl RestrictionRecord {
    /// The points of the shape, once the record holds together: the figure
    /// fits the kind and certainty, the texts fit their columns, the shape
    /// decodes into 1 to [`MAX_POINTS`] points.
    ///
    /// # Errors
    ///
    /// [`InvalidRecord`] naming the record and the first problem.
    pub fn check(&self) -> Result<Vec<Position>, InvalidRecord> {
        let id = || self.external_id.clone();
        if self.external_id.is_empty() || self.external_id.len() > 100 {
            return Err(InvalidRecord::Text { external_id: id() });
        }
        if self
            .name
            .as_ref()
            .is_some_and(|n| n.is_empty() || n.chars().count() > 200)
        {
            return Err(InvalidRecord::Text { external_id: id() });
        }
        let figure = |v: Option<f64>| v.is_none_or(|x| x.is_finite() && x > 0.0 && x <= 100.0);
        let limit_fits = if BANS.contains(&self.kind) {
            self.limit.is_none()
        } else if self.certainty == Certainty::Unknown {
            self.kind == RestrictionKind::MaxHeight && self.limit.is_none()
        } else {
            self.limit.is_some()
        };
        let dispute_fits = (self.certainty == Certainty::Disputed)
            == (self.other_value.is_some() && self.other_source.is_some());
        let exception_fits = (!self.except_destination
            || (self.kind.spares_local_access() && self.limit.is_some()))
            && (!self.enclosed || self.except_destination);
        if !(limit_fits
            && dispute_fits
            && exception_fits
            && figure(self.limit)
            && figure(self.other_value))
        {
            return Err(InvalidRecord::Limit {
                external_id: id(),
                kind: self.kind,
            });
        }
        match polyline::decode(&self.shape) {
            Ok(points) if (1..=MAX_POINTS).contains(&points.len()) => Ok(points),
            _ => Err(InvalidRecord::Shape { external_id: id() }),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record() -> RestrictionRecord {
        RestrictionRecord {
            source: RestrictionSource::Osm,
            external_id: "way/52984577".into(),
            kind: RestrictionKind::MaxHeight,
            limit: Some(2.7),
            certainty: Certainty::Known,
            feature: RestrictionFeature::Underpass,
            name: Some("Rue Maurice Utrillo".into()),
            other_value: None,
            other_source: None,
            shape: polyline::encode(&[
                Position::new(45.8466, 1.2852).unwrap(),
                Position::new(45.8462, 1.2855).unwrap(),
            ]),
            observed_at: DateTime::parse_from_rfc3339("2026-10-05T20:20:43Z")
                .unwrap()
                .with_timezone(&Utc),
            except_destination: false,
            enclosed: false,
        }
    }

    #[test]
    fn a_record_reads_back_and_its_codes_are_the_database_s() {
        let r = record();
        let line = serde_json::to_string(&r).unwrap();
        assert!(line.contains(r#""kind":"max_height""#), "{line}");
        assert!(line.contains(r#""feature":"underpass""#));
        assert_eq!(serde_json::from_str::<RestrictionRecord>(&line).unwrap(), r);
        assert_eq!(r.check().unwrap().len(), 2);
        for k in RestrictionKind::ALL {
            assert_eq!(
                serde_json::to_value(k).unwrap(),
                k.code(),
                "serde and SQL share codes"
            );
        }
        for f in RestrictionFeature::ALL {
            assert_eq!(serde_json::to_value(f).unwrap(), f.code());
        }
        for c in Certainty::ALL {
            assert_eq!(serde_json::to_value(c).unwrap(), c.code());
        }
        for s in RestrictionSource::ALL {
            assert_eq!(serde_json::to_value(s).unwrap(), s.code());
        }
    }

    #[test]
    fn a_record_that_does_not_hold_together_is_refused() {
        let ban_with_figure = RestrictionRecord {
            kind: RestrictionKind::MotorhomeBan,
            ..record()
        };
        assert!(matches!(
            ban_with_figure.check(),
            Err(InvalidRecord::Limit { .. })
        ));
        let disputed_alone = RestrictionRecord {
            certainty: Certainty::Disputed,
            ..record()
        };
        assert!(disputed_alone.check().is_err());
        let disputed = RestrictionRecord {
            certainty: Certainty::Disputed,
            other_value: Some(3.1),
            other_source: Some(RestrictionSource::Ign),
            ..record()
        };
        assert!(disputed.check().is_ok());
        let unknown_weight = RestrictionRecord {
            kind: RestrictionKind::MaxWeight,
            certainty: Certainty::Unknown,
            limit: None,
            ..record()
        };
        assert!(unknown_weight.check().is_err());
        let nan = RestrictionRecord {
            limit: Some(f64::NAN),
            ..record()
        };
        assert!(nan.check().is_err());
        let no_shape = RestrictionRecord {
            shape: String::new(),
            ..record()
        };
        assert!(matches!(no_shape.check(), Err(InvalidRecord::Shape { .. })));
        let spared_clearance = RestrictionRecord {
            except_destination: true,
            enclosed: false,
            ..record()
        };
        assert!(
            spared_clearance.check().is_err(),
            "no plate lets a vehicle under a bridge too low for it"
        );
        let spared_weight = RestrictionRecord {
            kind: RestrictionKind::MaxWeight,
            limit: Some(3.5),
            except_destination: true,
            enclosed: false,
            ..record()
        };
        assert!(spared_weight.check().is_ok());
    }

    #[test]
    fn the_local_access_exception_travels_only_when_set() {
        let plain = serde_json::to_string(&record()).unwrap();
        assert!(
            !plain.contains("except_destination"),
            "a bundle without exceptions keeps its old lines: {plain}"
        );
        let old: RestrictionRecord = serde_json::from_str(&plain).unwrap();
        assert!(
            !old.except_destination,
            "an older bundle reads as no exception"
        );
        let spared = RestrictionRecord {
            kind: RestrictionKind::MaxWeight,
            limit: Some(3.5),
            except_destination: true,
            enclosed: false,
            ..record()
        };
        let line = serde_json::to_string(&spared).unwrap();
        assert!(line.contains(r#""except_destination":true"#), "{line}");
        assert_eq!(
            serde_json::from_str::<RestrictionRecord>(&line).unwrap(),
            spared
        );
    }
}
