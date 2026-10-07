//! The match score of two records: is it the same spot?
//!
//! The score is a weighted mean of a distance component and a name
//! component (plus the municipality when both records know it), multiplied by
//! the compatibility of the two kinds. Shared or conflicting identifiers then
//! move it, and the decision comes from two thresholds. Every component is
//! kept in [`ScoreComponents`] so a decision can be explained.
//!
//! `schema/conflation-vectors.json` holds the parameters below and test
//! pairs; the device runs the same scoring on them.

use serde::{Deserialize, Serialize};

use super::{
    normalize::{core_tokens, fold, normalize_phone, normalize_website, normalize_wikidata},
    similarity::{token_containment, trigram_similarity, trigrams},
};
use crate::{PlaceKind, geo::Position, record::NormalizedRecord, source::SourceId};

/// At or above this score two records are merged automatically.
pub const MERGE_THRESHOLD: f64 = 0.85;
/// From this score up to [`MERGE_THRESHOLD`] the pair goes to the review queue.
pub const REVIEW_THRESHOLD: f64 = 0.6;

/// Weight of the distance component in the mean.
pub const WEIGHT_DISTANCE: f64 = 0.45;
/// Weight of the name component in the mean.
pub const WEIGHT_NAME: f64 = 0.4;
/// Weight of the municipality component, counted only when both records know
/// their municipality.
pub const WEIGHT_MUNICIPALITY: f64 = 0.1;
/// Name component reported when either record has no name. It is not
/// counted in the mean: a missing name is neither for nor against, and
/// distance, kind and shared identifiers decide.
pub const NAME_UNKNOWN: f64 = 0.5;
/// Largest position uncertainty credited to one record, in metres, so a
/// badly geocoded record cannot make everything around it a candidate.
pub const ACCURACY_CAP_M: f64 = 500.0;
/// Score floor when both records carry the same global identifier (OSM
/// element, Wikidata item), before the kind multiplier.
pub const GLOBAL_ID_FLOOR: f64 = 0.95;
/// Score floor when both records carry the same phone or website and lie
/// within reach of each other, before the kind multiplier.
pub const LOCAL_ID_FLOOR: f64 = 0.9;

/// The distance, in metres, within which two records of these kinds may
/// describe the same spot: how far the point a source picks can sit from
/// another source's point for the same place. A campsite's point may be the
/// reception or the middle of the ground; a car park is small.
#[must_use]
pub const fn kind_radius_m(kind: PlaceKind) -> f64 {
    match kind {
        PlaceKind::Parking | PlaceKind::ServiceArea | PlaceKind::ExtraService => 60.0,
        PlaceKind::PicnicArea | PlaceKind::Nature => 100.0,
        PlaceKind::MotorhomeArea | PlaceKind::RestArea | PlaceKind::OffRoad => 150.0,
        PlaceKind::Homestay => 200.0,
        PlaceKind::Campsite | PlaceKind::Farm => 300.0,
    }
}

/// The largest [`kind_radius_m`]: the database looks for candidates within
/// this distance plus the accuracies.
pub const MAX_KIND_RADIUS_M: f64 = 300.0;

/// How far apart two records sharing an OSM element or a Wikidata item may
/// be, in metres, once both position uncertainties are credited, for the
/// shared identifier to count. Beyond it the identifier is ignored: an item
/// that names a whole lake or town is shared by spots kilometres apart, and
/// the database only scores pairs within [`MAX_KIND_RADIUS_M`] plus the
/// accuracies, so a farther merge could not be found anyway.
pub const GLOBAL_ID_REACH_M: f64 = MAX_KIND_RADIUS_M;

/// How plausible it is that two different kinds describe the same spot
/// (symmetric; a pair of equal kinds is 1, a pair not listed is 0). A
/// motorhome area is often mapped as a car park by one source; a campsite and
/// a car park are never one spot.
pub const KIND_COMPATIBILITY: &[(PlaceKind, PlaceKind, f64)] = &[
    (PlaceKind::MotorhomeArea, PlaceKind::Parking, 0.9),
    (PlaceKind::MotorhomeArea, PlaceKind::ServiceArea, 0.9),
    (PlaceKind::MotorhomeArea, PlaceKind::Campsite, 0.8),
    (PlaceKind::MotorhomeArea, PlaceKind::RestArea, 0.6),
    (PlaceKind::MotorhomeArea, PlaceKind::Farm, 0.6),
    (PlaceKind::ServiceArea, PlaceKind::Parking, 0.7),
    (PlaceKind::ServiceArea, PlaceKind::ExtraService, 0.7),
    (PlaceKind::ServiceArea, PlaceKind::RestArea, 0.6),
    (PlaceKind::ServiceArea, PlaceKind::Campsite, 0.5),
    (PlaceKind::Parking, PlaceKind::RestArea, 0.8),
    (PlaceKind::Parking, PlaceKind::Nature, 0.6),
    (PlaceKind::Parking, PlaceKind::PicnicArea, 0.6),
    (PlaceKind::RestArea, PlaceKind::PicnicArea, 0.8),
    (PlaceKind::Nature, PlaceKind::PicnicArea, 0.6),
    (PlaceKind::Nature, PlaceKind::OffRoad, 0.8),
    (PlaceKind::Farm, PlaceKind::Homestay, 0.8),
    (PlaceKind::Farm, PlaceKind::Campsite, 0.6),
    (PlaceKind::Homestay, PlaceKind::Campsite, 0.4),
];

/// The compatibility of two kinds, from [`KIND_COMPATIBILITY`].
#[must_use]
pub fn kind_compatibility(a: PlaceKind, b: PlaceKind) -> f64 {
    if a == b {
        return 1.0;
    }
    KIND_COMPATIBILITY
        .iter()
        .find(|(x, y, _)| (*x == a && *y == b) || (*x == b && *y == a))
        .map_or(0.0, |(_, _, v)| *v)
}

/// What the matcher decided for a pair.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Decision {
    /// The same spot: merged automatically.
    Merge,
    /// Possibly the same spot: a person decides.
    Review,
    /// Different spots.
    Distinct,
}

impl Decision {
    /// The stable code stored in the database and the test vectors.
    #[must_use]
    pub const fn code(self) -> &'static str {
        match self {
            Self::Merge => "merge",
            Self::Review => "review",
            Self::Distinct => "distinct",
        }
    }
}

/// Which identifier two records shared or contradicted.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum IdentifierKind {
    /// The same OpenStreetMap element.
    Osm,
    /// The same Wikidata item.
    Wikidata,
    /// The same phone number.
    Phone,
    /// The same website.
    Website,
}

/// Why the decision is what it is, beyond the plain score.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Reason {
    /// The score alone decided.
    Score,
    /// A shared identifier raised the score.
    SharedIdentifier,
    /// Both records name a different global identifier: different spots.
    ConflictingIdentifier,
    /// The kinds cannot be the same spot.
    IncompatibleKinds,
    /// Both records come from the same source, which never merges itself:
    /// a high score is a duplicate to report.
    SameSource,
}

impl Reason {
    /// Every reason, for the tests that pin the stored codes.
    pub const ALL: &'static [Self] = &[
        Self::Score,
        Self::SharedIdentifier,
        Self::ConflictingIdentifier,
        Self::IncompatibleKinds,
        Self::SameSource,
    ];

    /// The stable code stored in the database (`match_pairs.reason`), the
    /// same as its serialised form.
    #[must_use]
    pub const fn code(self) -> &'static str {
        match self {
            Self::Score => "score",
            Self::SharedIdentifier => "shared_identifier",
            Self::ConflictingIdentifier => "conflicting_identifier",
            Self::IncompatibleKinds => "incompatible_kinds",
            Self::SameSource => "same_source",
        }
    }
}

/// Every input of a score, kept so a merge can be explained.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ScoreComponents {
    /// Great-circle distance between the two points, metres.
    pub distance_m: f64,
    /// Distance left after crediting both position uncertainties, metres.
    pub effective_distance_m: f64,
    /// Radius of the pair of kinds, metres.
    pub radius_m: f64,
    /// Distance component, 1 on the spot, 0 at the radius and beyond.
    pub distance: f64,
    /// Name component; [`NAME_UNKNOWN`] when a name is missing.
    pub name: f64,
    /// Kind compatibility, the multiplier.
    pub kind: f64,
    /// Same municipality (1) or not (0), absent when either record does not
    /// know it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub municipality: Option<f64>,
    /// Weighted mean before the kind multiplier and the identifiers.
    pub base: f64,
    /// Identifier both records share, if any.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub shared_identifier: Option<IdentifierKind>,
    /// Global identifier the records contradict, if any.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub conflicting_identifier: Option<IdentifierKind>,
}

/// The verdict on a pair.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MatchScore {
    /// Final score in [0, 1].
    pub score: f64,
    /// What to do with the pair.
    pub decision: Decision,
    /// What drove the decision.
    pub reason: Reason,
    /// The inputs.
    pub components: ScoreComponents,
}

/// A record prepared for matching: its comparable values are normalised once,
/// not once per pair.
#[derive(Debug, Clone)]
pub struct MatchCandidate {
    source: SourceId,
    kind: PlaceKind,
    position: Position,
    accuracy_m: f64,
    /// Folded full name; `None` when the record has no name at all.
    folded: Option<String>,
    folded_tokens: Vec<String>,
    folded_trigrams: Vec<[char; 3]>,
    core_tokens: Vec<String>,
    core_trigrams: Vec<[char; 3]>,
    osm: Option<String>,
    wikidata: Option<String>,
    phone: Option<String>,
    website: Option<String>,
    city_code: Option<String>,
    postcode: Option<String>,
}

fn sorted_tokens<'a>(tokens: impl Iterator<Item = &'a str>) -> Vec<String> {
    let mut v: Vec<String> = tokens.map(str::to_owned).collect();
    v.sort_unstable();
    v.dedup();
    v
}

impl MatchCandidate {
    /// Prepares `record` of `source` for matching.
    #[must_use]
    pub fn new(source: &SourceId, record: &NormalizedRecord) -> Self {
        let folded = record.name.as_deref().map(fold).filter(|f| !f.is_empty());
        let (folded_tokens, folded_trigrams, core_tokens_v, core_trigrams) = match &folded {
            Some(f) => {
                let core = core_tokens(f);
                (
                    sorted_tokens(f.split(' ')),
                    trigrams(f),
                    sorted_tokens(core.iter().copied()),
                    trigrams(&core.join(" ")),
                )
            }
            None => Default::default(),
        };
        let accuracy_m = if record.accuracy_m.is_finite() {
            record.accuracy_m.clamp(0.0, ACCURACY_CAP_M)
        } else {
            0.0
        };
        Self {
            source: source.clone(),
            kind: record.kind,
            position: record.position,
            accuracy_m,
            folded,
            folded_tokens,
            folded_trigrams,
            core_tokens: core_tokens_v,
            core_trigrams,
            osm: record
                .osm_ref
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_owned),
            wikidata: record.wikidata.as_deref().and_then(normalize_wikidata),
            phone: record.phone.as_deref().and_then(normalize_phone),
            website: record.website.as_deref().and_then(normalize_website),
            city_code: record.address.city_code.clone().filter(|s| !s.is_empty()),
            postcode: record
                .address
                .postcode
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_owned),
        }
    }

    /// The source of the record.
    #[must_use]
    pub const fn source(&self) -> &SourceId {
        &self.source
    }

    /// Its position.
    #[must_use]
    pub const fn position(&self) -> Position {
        self.position
    }

    /// Its kind.
    #[must_use]
    pub const fn kind(&self) -> PlaceKind {
        self.kind
    }
}

/// Name similarity of two prepared records: on the identifying words when
/// both have some, on the full folded names when either is only generic
/// words ("Camping municipal"), [`NAME_UNKNOWN`] when either has no name.
/// The larger of the trigram similarity and the token containment.
fn name_component(a: &MatchCandidate, b: &MatchCandidate) -> f64 {
    if a.folded.is_none() || b.folded.is_none() {
        return NAME_UNKNOWN;
    }
    let ((ta, ga), (tb, gb)) = if a.core_tokens.is_empty() || b.core_tokens.is_empty() {
        (
            (&a.folded_tokens, &a.folded_trigrams),
            (&b.folded_tokens, &b.folded_trigrams),
        )
    } else {
        (
            (&a.core_tokens, &a.core_trigrams),
            (&b.core_tokens, &b.core_trigrams),
        )
    };
    let ta: Vec<&str> = ta.iter().map(String::as_str).collect();
    let tb: Vec<&str> = tb.iter().map(String::as_str).collect();
    trigram_similarity(ga, gb).max(token_containment(&ta, &tb))
}

fn same(a: Option<&String>, b: Option<&String>) -> Option<bool> {
    Some(a? == b?)
}

/// Scores the pair `a`, `b`. Symmetric: `score(a, b) == score(b, a)`.
#[must_use]
pub fn score(a: &MatchCandidate, b: &MatchCandidate) -> MatchScore {
    let distance_m = a.position.distance_m(b.position);
    let effective_distance_m = (distance_m - (a.accuracy_m + b.accuracy_m)).max(0.0);
    let radius_m = kind_radius_m(a.kind).max(kind_radius_m(b.kind));
    // Quadratic decay: flat near the spot, where sources disagree by a few
    // metres for no reason, steep towards the radius.
    let distance = (1.0 - (effective_distance_m / radius_m).powi(2)).max(0.0);
    let name = name_component(a, b);
    let kind = kind_compatibility(a.kind, b.kind);
    let municipality = same(a.city_code.as_ref(), b.city_code.as_ref())
        .or_else(|| same(a.postcode.as_ref(), b.postcode.as_ref()))
        .map(|eq| if eq { 1.0 } else { 0.0 });

    // A missing name is neutral: it leaves the mean, as an unknown
    // municipality does, so distance, kind and shared identifiers decide.
    // Scored at 0.5 it capped every unnamed car park beside a named spot
    // at review (`tests/extcom_synthetic.rs`).
    let named = a.folded.is_some() && b.folded.is_some();
    let (mut weighted, mut weights) = if named {
        (
            WEIGHT_DISTANCE * distance + WEIGHT_NAME * name,
            WEIGHT_DISTANCE + WEIGHT_NAME,
        )
    } else {
        (WEIGHT_DISTANCE * distance, WEIGHT_DISTANCE)
    };
    if let Some(m) = municipality {
        weighted += WEIGHT_MUNICIPALITY * m;
        weights += WEIGHT_MUNICIPALITY;
    }
    let base = weighted / weights;
    let mut score = base * kind;
    let mut reason = Reason::Score;

    let shared_global = if effective_distance_m > GLOBAL_ID_REACH_M {
        None
    } else if same(a.osm.as_ref(), b.osm.as_ref()) == Some(true) {
        Some(IdentifierKind::Osm)
    } else if same(a.wikidata.as_ref(), b.wikidata.as_ref()) == Some(true) {
        Some(IdentifierKind::Wikidata)
    } else {
        None
    };
    // Every OSM record names its own element, so two OSM records always
    // differ there: a node and a way of one campsite are a duplicate to
    // review, not two spots. The OSM element separates records only when
    // another source cites one.
    let conflicting = if a.source != b.source && same(a.osm.as_ref(), b.osm.as_ref()) == Some(false)
    {
        Some(IdentifierKind::Osm)
    } else if same(a.wikidata.as_ref(), b.wikidata.as_ref()) == Some(false) {
        Some(IdentifierKind::Wikidata)
    } else {
        None
    };
    let shared_local = if distance > 0.0 {
        if same(a.phone.as_ref(), b.phone.as_ref()) == Some(true) {
            Some(IdentifierKind::Phone)
        } else if same(a.website.as_ref(), b.website.as_ref()) == Some(true) {
            Some(IdentifierKind::Website)
        } else {
            None
        }
    } else {
        None
    };
    let mut shared_identifier = None;

    if kind == 0.0 {
        reason = Reason::IncompatibleKinds;
    } else if conflicting.is_some() && shared_global.is_none() {
        // Two different OSM elements or Wikidata items are two things, however
        // close and however alike their names.
        score = 0.0;
        reason = Reason::ConflictingIdentifier;
    } else if let Some(id) = shared_global {
        shared_identifier = Some(id);
        if GLOBAL_ID_FLOOR * kind > score {
            score = GLOBAL_ID_FLOOR * kind;
            reason = Reason::SharedIdentifier;
        }
    } else if let Some(id) = shared_local {
        shared_identifier = Some(id);
        if LOCAL_ID_FLOOR * kind > score {
            score = LOCAL_ID_FLOOR * kind;
            reason = Reason::SharedIdentifier;
        }
    }

    let mut decision = if score >= MERGE_THRESHOLD {
        Decision::Merge
    } else if score >= REVIEW_THRESHOLD {
        Decision::Review
    } else {
        Decision::Distinct
    };
    if a.source == b.source && decision == Decision::Merge {
        decision = Decision::Review;
        reason = Reason::SameSource;
    }

    MatchScore {
        score,
        decision,
        reason,
        components: ScoreComponents {
            distance_m,
            effective_distance_m,
            radius_m,
            distance,
            name,
            kind,
            municipality,
            base,
            shared_identifier,
            conflicting_identifier: conflicting.filter(|_| shared_global.is_none()),
        },
    }
}

#[cfg(test)]
mod tests {
    use proptest::prelude::*;

    use super::*;

    /// A record of `kind` named `name`, `north_m` metres north of a fixed point.
    fn rec(kind: PlaceKind, name: Option<&str>, north_m: f64) -> NormalizedRecord {
        let lat = 47.0 + north_m / 111_195.0;
        let mut r = NormalizedRecord::new(kind, Position::new(lat, 2.0).unwrap());
        r.name = name.map(str::to_owned);
        r
    }

    fn cand(source: &SourceId, r: &NormalizedRecord) -> MatchCandidate {
        MatchCandidate::new(source, r)
    }

    fn pair(a: &NormalizedRecord, b: &NormalizedRecord) -> MatchScore {
        score(&cand(&SourceId::OSM, a), &cand(&SourceId::ATOUT_FRANCE, b))
    }

    #[test]
    fn the_same_campsite_from_two_sources_merges() {
        let a = rec(PlaceKind::Campsite, Some("Camping des Varennes"), 0.0);
        let b = rec(
            PlaceKind::Campsite,
            Some("AGIS - CAMPING DES VARENNES"),
            80.0,
        );
        let s = pair(&a, &b);
        assert_eq!(s.decision, Decision::Merge, "{s:?}");
        assert!((s.components.name - 1.0).abs() < 1e-12);
    }

    #[test]
    fn two_neighbouring_spots_with_other_names_stay_distinct() {
        let a = rec(PlaceKind::Campsite, Some("Camping Les Pins"), 0.0);
        let b = rec(PlaceKind::Campsite, Some("Camping La Mer"), 50.0);
        assert_eq!(pair(&a, &b).decision, Decision::Distinct);
    }

    #[test]
    fn the_distance_decays_to_zero_at_the_kind_radius() {
        let a = rec(PlaceKind::Parking, Some("Parking du Port"), 0.0);
        for (north, expected) in [(0.0, 1.0), (30.0, 0.75), (60.0, 0.0), (500.0, 0.0)] {
            let s = pair(&a, &rec(PlaceKind::Parking, Some("Parking du Port"), north));
            assert!(
                (s.components.distance - expected).abs() < 0.01,
                "{north} m: {:?}",
                s.components
            );
        }
        let far = pair(&a, &rec(PlaceKind::Parking, Some("Parking du Port"), 80.0));
        assert_eq!(
            far.decision,
            Decision::Distinct,
            "a car park 80 m away is another car park"
        );
    }

    #[test]
    fn position_uncertainty_is_credited() {
        let a = rec(PlaceKind::Campsite, Some("Camping du Lac"), 0.0);
        let mut b = rec(PlaceKind::Campsite, Some("Camping du Lac"), 500.0);
        assert_eq!(pair(&a, &b).decision, Decision::Distinct);
        b.accuracy_m = 300.0;
        let s = pair(&a, &b);
        assert!((s.components.effective_distance_m - 200.0).abs() < 1.0);
        assert_eq!(s.decision, Decision::Review, "{s:?}");
        b.accuracy_m = 10_000.0;
        let capped = pair(&a, &b);
        assert!(
            (capped.components.effective_distance_m - 0.0).abs() < 1.0,
            "the cap still covers 500 m"
        );
    }

    #[test]
    fn kinds_gate_the_score() {
        let a = rec(PlaceKind::Campsite, Some("Le Lac"), 0.0);
        let b = rec(PlaceKind::Parking, Some("Le Lac"), 0.0);
        let s = pair(&a, &b);
        assert_eq!(
            (s.decision, s.reason),
            (Decision::Distinct, Reason::IncompatibleKinds)
        );
        assert!(s.score.abs() < f64::EPSILON);

        let c = rec(PlaceKind::MotorhomeArea, Some("Aire du Lac"), 0.0);
        let s = pair(&a, &c);
        assert_eq!(
            s.decision,
            Decision::Review,
            "a campsite and a motorhome area: a person decides"
        );
    }

    #[test]
    fn the_kind_matrix_is_symmetric_and_bounded() {
        for &a in PlaceKind::ALL {
            assert!((kind_compatibility(a, a) - 1.0).abs() < f64::EPSILON);
            for &b in PlaceKind::ALL {
                let v = kind_compatibility(a, b);
                assert!((0.0..=1.0).contains(&v));
                assert!((v - kind_compatibility(b, a)).abs() < f64::EPSILON);
            }
        }
        for (i, (a, b, _)) in KIND_COMPATIBILITY.iter().enumerate() {
            assert_ne!(a, b, "equal kinds are 1 by rule, not by entry");
            for (c, d, _) in &KIND_COMPATIBILITY[i + 1..] {
                assert!(
                    !((a == c && b == d) || (a == d && b == c)),
                    "{a:?}/{b:?} is listed twice: the first entry would silently win"
                );
            }
        }
        assert!(kind_compatibility(PlaceKind::Campsite, PlaceKind::Parking).abs() < f64::EPSILON);
    }

    #[test]
    fn a_missing_name_leaves_the_decision_to_distance_and_kind() {
        let a = rec(PlaceKind::Parking, None, 0.0);
        let b = rec(PlaceKind::Parking, Some("Parking"), 0.0);
        let s = pair(&a, &b);
        assert!((s.components.name - NAME_UNKNOWN).abs() < f64::EPSILON);
        assert_eq!(
            s.decision,
            Decision::Merge,
            "the same point and kind, one name missing: the name neither counts for nor against"
        );
        let other = rec(PlaceKind::Campsite, None, 0.0);
        assert_eq!(
            pair(&a, &other).decision,
            Decision::Distinct,
            "an incompatible kind still keeps two unnamed records apart"
        );
    }

    #[test]
    fn generic_only_names_compare_in_full() {
        let a = rec(PlaceKind::Campsite, Some("Camping municipal"), 0.0);
        let b = rec(PlaceKind::Campsite, Some("CAMPING MUNICIPAL"), 100.0);
        assert_eq!(pair(&a, &b).decision, Decision::Merge);
        let c = rec(PlaceKind::Campsite, Some("Camping de la Gare"), 100.0);
        assert_ne!(pair(&a, &c).decision, Decision::Merge);
    }

    #[test]
    fn a_shared_global_identifier_merges_within_reach_and_a_conflicting_one_separates() {
        let mut a = rec(PlaceKind::MotorhomeArea, Some("Aire A"), 0.0);
        let mut b = rec(PlaceKind::MotorhomeArea, Some("Something else"), 250.0);
        a.wikidata = Some("Q1".into());
        b.wikidata = Some("q1".into());
        let s = pair(&a, &b);
        assert_eq!(
            (s.decision, s.reason),
            (Decision::Merge, Reason::SharedIdentifier)
        );
        assert_eq!(
            s.components.shared_identifier,
            Some(IdentifierKind::Wikidata)
        );

        let mut c = rec(PlaceKind::MotorhomeArea, Some("Aire A"), 0.0);
        c.wikidata = Some("Q2".into());
        let s = pair(&a, &c);
        assert_eq!(
            (s.decision, s.reason),
            (Decision::Distinct, Reason::ConflictingIdentifier)
        );
    }

    #[test]
    fn a_shared_global_identifier_out_of_reach_is_ignored() {
        let mut a = rec(PlaceKind::MotorhomeArea, Some("Aire A"), 0.0);
        let mut far = rec(PlaceKind::MotorhomeArea, Some("Something else"), 2_000.0);
        a.wikidata = Some("Q1".into());
        far.wikidata = Some("Q1".into());
        let s = pair(&a, &far);
        assert_eq!(
            (s.decision, s.components.shared_identifier),
            (Decision::Distinct, None),
            "the database never scores a pair 2 km apart, so the domain must not merge it either"
        );
        // The uncertainties widen the reach exactly as they widen the
        // candidate search: 1290 m apart with 500 m on each side is 290 m.
        far.position = rec(PlaceKind::MotorhomeArea, None, 1_290.0).position;
        far.accuracy_m = ACCURACY_CAP_M;
        a.accuracy_m = ACCURACY_CAP_M;
        let s = pair(&a, &far);
        assert!(s.components.effective_distance_m <= GLOBAL_ID_REACH_M);
        assert_eq!(s.decision, Decision::Merge, "{s:?}");
    }

    #[test]
    fn two_osm_elements_of_one_spot_reach_review() {
        // A campsite mapped as a node and as a way: two OSM records, each
        // naming its own element.
        let mut node = rec(PlaceKind::Campsite, Some("Camping du Gave"), 0.0);
        let mut way = rec(PlaceKind::Campsite, Some("Camping du Gave"), 40.0);
        node.osm_ref = Some("node/1".into());
        way.osm_ref = Some("way/2".into());
        let s = score(&cand(&SourceId::OSM, &node), &cand(&SourceId::OSM, &way));
        assert_eq!(
            (s.decision, s.reason, s.components.conflicting_identifier),
            (Decision::Review, Reason::SameSource, None),
            "an OSM duplicate must reach the review queue"
        );
        // Another source citing a different element still names another spot.
        let mut citing = way.clone();
        citing.osm_ref = Some("way/3".into());
        let s = score(
            &cand(&SourceId::OSM, &node),
            &cand(&SourceId::COMMUNITY, &citing),
        );
        assert_eq!(
            (s.decision, s.reason),
            (Decision::Distinct, Reason::ConflictingIdentifier)
        );
    }

    #[test]
    fn reason_codes_are_their_serialised_form() {
        for r in Reason::ALL {
            assert_eq!(
                serde_json::to_value(r).unwrap(),
                serde_json::Value::from(r.code()),
                "match_pairs.reason stores the code; reading it back must give the same reason"
            );
        }
    }

    #[test]
    fn a_shared_phone_counts_only_within_reach() {
        let mut a = rec(PlaceKind::Campsite, Some("Les Chênes"), 0.0);
        let mut b = rec(PlaceKind::Campsite, Some("Camping municipal"), 150.0);
        a.phone = Some("02 41 00 00 00".into());
        b.phone = Some("+33 2 41 00 00 00".into());
        let near = pair(&a, &b);
        assert_eq!(
            (near.decision, near.reason),
            (Decision::Merge, Reason::SharedIdentifier)
        );
        let far = pair(&a, &{
            let mut f = b.clone();
            f.position = Position::new(47.1, 2.0).unwrap();
            f
        });
        assert_eq!(
            far.decision,
            Decision::Distinct,
            "a chain shares its phone across sites"
        );
    }

    #[test]
    fn a_shared_website_between_kinds_only_reaches_review() {
        // A town site is often the website of both its campsite and its
        // motorhome area.
        let mut a = rec(PlaceKind::Campsite, Some("Camping municipal"), 0.0);
        let mut b = rec(PlaceKind::MotorhomeArea, Some("Aire de la mairie"), 100.0);
        a.website = Some("https://www.mairie-x.fr".into());
        b.website = Some("http://mairie-x.fr/".into());
        assert_eq!(pair(&a, &b).decision, Decision::Review);
    }

    #[test]
    fn the_same_source_never_merges() {
        let a = rec(PlaceKind::Campsite, Some("Camping du Lac"), 0.0);
        let b = rec(PlaceKind::Campsite, Some("Camping du Lac"), 10.0);
        let s = score(&cand(&SourceId::OSM, &a), &cand(&SourceId::OSM, &b));
        assert_eq!(
            (s.decision, s.reason),
            (Decision::Review, Reason::SameSource)
        );
        assert!(
            s.score >= MERGE_THRESHOLD,
            "the score is kept to rank the duplicate report"
        );
    }

    #[test]
    fn the_municipality_counts_when_both_know_it() {
        let mut a = rec(PlaceKind::Campsite, Some("Les Pins"), 0.0);
        let mut b = rec(PlaceKind::Campsite, Some("Les Pins"), 200.0);
        let without = pair(&a, &b).score;
        a.address.postcode = Some("85300".into());
        b.address.postcode = Some("85300".into());
        let same = pair(&a, &b);
        b.address.postcode = Some("85000".into());
        let other = pair(&a, &b);
        assert_eq!(same.components.municipality, Some(1.0));
        assert!(same.score > without && other.score < without);
        a.address.city_code = Some("85171".into());
        b.address.city_code = Some("85171".into());
        assert_eq!(
            pair(&a, &b).components.municipality,
            Some(1.0),
            "the municipality code wins over a differing postcode"
        );
    }

    fn arb_record() -> impl Strategy<Value = NormalizedRecord> {
        (
            proptest::sample::select(PlaceKind::ALL),
            proptest::option::of("[A-Za-zéè' -]{0,20}"),
            -2_000.0..2_000.0f64,
            0.0..400.0f64,
            proptest::option::of("Q[1-3]"),
            proptest::option::of("0[1-2] 00 00 00 0[0-1]"),
        )
            .prop_map(|(kind, name, north, acc, wd, phone)| {
                let mut r = rec(kind, name.as_deref(), north);
                r.accuracy_m = acc;
                r.wikidata = wd;
                r.phone = phone;
                r
            })
    }

    proptest! {
        #[test]
        fn the_score_is_symmetric_and_bounded(a in arb_record(), b in arb_record(), same_source: bool) {
            let sa = SourceId::OSM;
            let sb = if same_source { SourceId::OSM } else { SourceId::ATOUT_FRANCE };
            let ab = score(&cand(&sa, &a), &cand(&sb, &b));
            let ba = score(&cand(&sb, &b), &cand(&sa, &a));
            prop_assert_eq!(ab.score.to_bits(), ba.score.to_bits());
            prop_assert_eq!(ab.decision, ba.decision);
            prop_assert!((0.0..=1.0).contains(&ab.score));
            if same_source {
                prop_assert_ne!(ab.decision, Decision::Merge);
            }
        }
    }
}
