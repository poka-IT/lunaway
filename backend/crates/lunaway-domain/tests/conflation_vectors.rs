//! Replays `schema/conflation-vectors.json`, the cases the Rust and the Dart
//! scorers must both pass, and checks that the file's parameters are the
//! constants this crate uses.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::collections::{BTreeMap, BTreeSet};

use lunaway_domain::{
    NormalizedRecord, PlaceKind, Position, SourceId,
    conflation::{
        Decision, MatchCandidate, normalize,
        score::{self, KIND_COMPATIBILITY, kind_radius_m},
    },
    geo::EARTH_RADIUS_M,
};
use serde::Deserialize;

const PATH: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../../schema/conflation-vectors.json"
);

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Weights {
    distance: f64,
    name: f64,
    municipality: f64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Parameters {
    merge_threshold: f64,
    review_threshold: f64,
    weights: Weights,
    name_unknown: f64,
    accuracy_cap_m: f64,
    global_id_floor: f64,
    global_id_reach_m: f64,
    local_id_floor: f64,
    earth_radius_m: f64,
    kind_radius_m: BTreeMap<String, f64>,
    kind_compatibility: Vec<(String, String, f64)>,
    generic_words: Vec<String>,
    abbreviations: BTreeMap<String, String>,
    ligatures: BTreeMap<String, String>,
    platform_hosts: Vec<String>,
}

#[derive(Deserialize)]
struct Normalisation {
    input: String,
    normalized: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Rec {
    source: String,
    kind: String,
    name: Option<String>,
    lat: f64,
    lon: f64,
    #[serde(default)]
    accuracy_m: f64,
    osm: Option<String>,
    wikidata: Option<String>,
    phone: Option<String>,
    website: Option<String>,
    postcode: Option<String>,
    city_code: Option<String>,
}

#[derive(Deserialize)]
struct Case {
    id: String,
    why: String,
    expected: String,
    score: Option<f64>,
    a: Rec,
    b: Rec,
}

#[derive(Deserialize)]
struct Vectors {
    version: u32,
    parameters: Parameters,
    names: Vec<Normalisation>,
    phones: Vec<Normalisation>,
    websites: Vec<Normalisation>,
    cases: Vec<Case>,
}

fn vectors() -> Vectors {
    let text = std::fs::read_to_string(PATH).expect("schema/conflation-vectors.json is readable");
    serde_json::from_str(&text).expect("the vectors follow the documented format")
}

fn to_record(r: &Rec) -> (SourceId, NormalizedRecord) {
    let kind: PlaceKind = r.kind.parse().unwrap();
    let mut rec = NormalizedRecord::new(kind, Position::new(r.lat, r.lon).unwrap());
    rec.name.clone_from(&r.name);
    rec.accuracy_m = r.accuracy_m;
    rec.osm_ref.clone_from(&r.osm);
    rec.wikidata.clone_from(&r.wikidata);
    rec.phone.clone_from(&r.phone);
    rec.website.clone_from(&r.website);
    rec.address.postcode.clone_from(&r.postcode);
    rec.address.city_code.clone_from(&r.city_code);
    (SourceId::new(&r.source).unwrap(), rec)
}

#[test]
fn the_parameters_are_the_constants_of_the_rust_scorer() {
    let v = vectors();
    assert_eq!(v.version, 1);
    let p = v.parameters;
    let eq = |a: f64, b: f64, what: &str| {
        assert!((a - b).abs() < 1e-12, "{what}: file {a}, code {b}");
    };
    eq(p.merge_threshold, score::MERGE_THRESHOLD, "mergeThreshold");
    eq(
        p.review_threshold,
        score::REVIEW_THRESHOLD,
        "reviewThreshold",
    );
    eq(
        p.weights.distance,
        score::WEIGHT_DISTANCE,
        "weights.distance",
    );
    eq(p.weights.name, score::WEIGHT_NAME, "weights.name");
    eq(
        p.weights.municipality,
        score::WEIGHT_MUNICIPALITY,
        "weights.municipality",
    );
    eq(p.name_unknown, score::NAME_UNKNOWN, "nameUnknown");
    eq(p.accuracy_cap_m, score::ACCURACY_CAP_M, "accuracyCapM");
    eq(p.global_id_floor, score::GLOBAL_ID_FLOOR, "globalIdFloor");
    eq(
        p.global_id_reach_m,
        score::GLOBAL_ID_REACH_M,
        "globalIdReachM",
    );
    eq(p.local_id_floor, score::LOCAL_ID_FLOOR, "localIdFloor");
    eq(p.earth_radius_m, EARTH_RADIUS_M, "earthRadiusM");

    let radii: BTreeMap<String, f64> = PlaceKind::ALL
        .iter()
        .map(|k| (k.code().to_owned(), kind_radius_m(*k)))
        .collect();
    assert_eq!(
        p.kind_radius_m, radii,
        "kindRadiusM must list every kind with the code's radius"
    );
    let max = radii.values().copied().fold(0.0, f64::max);
    eq(
        max,
        score::MAX_KIND_RADIUS_M,
        "MAX_KIND_RADIUS_M is the largest radius",
    );

    let code: Vec<(String, String, f64)> = KIND_COMPATIBILITY
        .iter()
        .map(|(a, b, v)| (a.code().to_owned(), b.code().to_owned(), *v))
        .collect();
    assert_eq!(p.kind_compatibility, code, "kindCompatibility");

    let generic: Vec<String> = normalize::GENERIC_WORDS
        .iter()
        .map(|s| (*s).to_owned())
        .collect();
    assert_eq!(p.generic_words, generic, "genericWords");
    let abbreviations: BTreeMap<String, String> = normalize::ABBREVIATIONS
        .iter()
        .map(|(a, b)| ((*a).to_owned(), (*b).to_owned()))
        .collect();
    assert_eq!(p.abbreviations, abbreviations, "abbreviations");
    let ligatures: BTreeMap<String, String> = normalize::LIGATURES
        .iter()
        .map(|(c, s)| (c.to_string(), (*s).to_owned()))
        .collect();
    assert_eq!(p.ligatures, ligatures, "ligatures");
    let hosts: Vec<String> = normalize::PLATFORM_HOSTS
        .iter()
        .map(|s| (*s).to_owned())
        .collect();
    assert_eq!(p.platform_hosts, hosts, "platformHosts");
}

#[test]
fn names_phones_and_websites_normalise_as_the_vectors_say() {
    let v = vectors();
    for n in &v.names {
        assert_eq!(
            Some(normalize::normalize_name(&n.input)),
            n.normalized,
            "name {:?}",
            n.input
        );
    }
    for n in &v.phones {
        assert_eq!(
            normalize::normalize_phone(&n.input),
            n.normalized,
            "phone {:?}",
            n.input
        );
    }
    for n in &v.websites {
        assert_eq!(
            normalize::normalize_website(&n.input),
            n.normalized,
            "website {:?}",
            n.input
        );
    }
}

#[test]
fn every_pair_gets_its_expected_decision_and_score() {
    let v = vectors();
    let mut failures = Vec::new();
    for c in &v.cases {
        let (sa, ra) = to_record(&c.a);
        let (sb, rb) = to_record(&c.b);
        let (ca, cb) = (MatchCandidate::new(&sa, &ra), MatchCandidate::new(&sb, &rb));
        let ab = score::score(&ca, &cb);
        let ba = score::score(&cb, &ca);
        assert_eq!(
            ab.score.to_bits(),
            ba.score.to_bits(),
            "{}: scoring must be symmetric",
            c.id
        );
        assert_eq!(ab.decision, ba.decision, "{}", c.id);
        let decision_ok = ab.decision.code() == c.expected;
        let score_ok = c.score.is_some_and(|s| (s - ab.score).abs() <= 0.001);
        if !(decision_ok && score_ok) {
            failures.push(format!(
                "{}: expected {} {:?}, got {} {:.4} ({:?}; {})\n  components {:?}",
                c.id,
                c.expected,
                c.score,
                ab.decision.code(),
                ab.score,
                ab.reason,
                c.why,
                ab.components
            ));
        }
    }
    assert!(
        failures.is_empty(),
        "{} case(s) failed:\n{}",
        failures.len(),
        failures.join("\n")
    );
}

#[test]
fn the_cases_cover_what_the_contract_asks_for() {
    let v = vectors();
    assert!(
        v.cases.len() >= 25,
        "the contract asks for 25 cases or more"
    );
    let ids: BTreeSet<&str> = v.cases.iter().map(|c| c.id.as_str()).collect();
    assert_eq!(ids.len(), v.cases.len(), "case ids are unique");
    let decisions: BTreeSet<&str> = v.cases.iter().map(|c| c.expected.as_str()).collect();
    for d in [Decision::Merge, Decision::Review, Decision::Distinct] {
        assert!(decisions.contains(d.code()), "no case expects {}", d.code());
    }
    assert!(
        v.cases.iter().any(|c| c.a.source == c.b.source),
        "a same-source pair"
    );
    assert!(
        v.cases.iter().any(|c| c.a.kind != c.b.kind),
        "a pair of different kinds"
    );
    assert!(
        v.cases
            .iter()
            .any(|c| c.a.osm.is_some() && c.a.osm == c.b.osm),
        "a shared identifier"
    );
    assert!(
        v.cases.iter().any(|c| c.a.source == "osm"
            && c.b.source == "osm"
            && c.a.osm.is_some()
            && c.b.osm.is_some()
            && c.a.osm != c.b.osm),
        "two OSM records, each naming its own element, as every real OSM record does"
    );
    assert!(
        v.cases.iter().any(|c| c.a.wikidata.is_some()
            && c.expected == "distinct"
            && c.a.wikidata.as_deref().map(str::to_uppercase)
                == c.b.wikidata.as_deref().map(str::to_uppercase)),
        "a shared identifier out of reach"
    );
    assert!(
        v.cases
            .iter()
            .any(|c| c.a.accuracy_m > 0.0 || c.b.accuracy_m > 0.0),
        "an uncertain position"
    );
}
