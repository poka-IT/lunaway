//! The points of interest of a recorded OpenStreetMap sample
//! (`fixtures/osm_poi_sample.json`: real elements of the France extract of
//! 2026-10-05, around Ambérieu-en-Bugey and Saumur): their kinds, fields
//! and the identifiers that join them to the fuel feed, La Poste and FINESS.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::collections::BTreeMap;

use chrono::{TimeZone, Utc};
use lunaway_domain::poi::{PoiCategory, PoiKind};
use lunaway_ingest::poi_osm;

const SAMPLE: &[u8] = include_bytes!("fixtures/osm_poi_sample.json");

fn parsed() -> poi_osm::ParsedPois {
    poi_osm::parse(SAMPLE, Utc.with_ymd_and_hms(2026, 10, 5, 22, 0, 0).unwrap()).unwrap()
}

#[test]
fn every_element_of_the_sample_is_a_point() {
    let p = parsed();
    assert!(p.skipped.is_empty(), "{:?}", p.skipped);
    assert_eq!(p.points.len(), 28);
    let mut by_category: BTreeMap<PoiCategory, usize> = BTreeMap::new();
    for point in &p.points {
        *by_category.entry(point.record.kind.category()).or_default() += 1;
    }
    for c in [
        PoiCategory::Groceries,
        PoiCategory::Vending,
        PoiCategory::Fuel,
        PoiCategory::Health,
        PoiCategory::Services,
    ] {
        assert!(by_category.contains_key(&c), "{c} missing: {by_category:?}");
    }
}

fn find<'a>(p: &'a poi_osm::ParsedPois, id: &str) -> &'a poi_osm::FetchedPoi {
    p.points
        .iter()
        .find(|x| x.external_id == id)
        .unwrap_or_else(|| panic!("{id}"))
}

#[test]
fn the_join_keys_are_read_from_their_tags() {
    let p = parsed();
    let post = find(&p, "node/812029833");
    assert_eq!(post.record.kind, PoiKind::PostOffice);
    assert_eq!(post.record.refs.laposte.as_deref(), Some("00001A"));
    let pharmacy = find(&p, "node/1687393915");
    assert_eq!(pharmacy.record.kind, PoiKind::Pharmacy);
    assert_eq!(pharmacy.record.refs.finess.as_deref(), Some("010002285"));
    let station = find(&p, "way/116147677");
    assert_eq!(station.record.kind, PoiKind::FuelStation);
    assert_eq!(station.record.refs.fuel.as_deref(), Some("40500002"));
    let fuels: Vec<&str> = p
        .points
        .iter()
        .filter_map(|x| x.record.refs.fuel.as_deref())
        .collect();
    for id in ["40500002", "18200011", "95650002", "34150003", "5100009"] {
        assert!(fuels.contains(&id), "{id}: a station of the fuel sample");
    }
}

#[test]
fn vending_machines_are_classified_by_what_they_sell() {
    let p = parsed();
    let pizza = find(&p, "node/11794224624");
    assert_eq!(pizza.record.kind, PoiKind::VendingPizza);
    assert!(pizza.record.products.contains(&"pizza".to_owned()));
    let bread = find(&p, "node/8440180524");
    assert_eq!(bread.record.kind, PoiKind::VendingBread);
}
