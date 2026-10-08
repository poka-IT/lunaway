//! `lunaway routing prepare` on a small extract and a few IGN sections: what
//! the change file tells Valhalla, and what the check after each route
//! receives, for the urban limits of `plan/research/61-limites-urbaines.md`.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::io::Read as _;

use chrono::{TimeZone, Utc};
use lunaway_domain::{
    Position,
    routing::{RestrictionKind, RestrictionRecord, RestrictionSource},
};
use lunaway_ingest::{ign::IgnSection, routing};

use crate::osm_extract::{Strings, file_of, node, way};

/// Three nodes 50 m apart going east from (`lat`, `lon`), ids from `first`.
fn street(s: &mut Strings, first: i64, lat: f64, lon: f64) -> Vec<Vec<u8>> {
    (0..3)
        .map(|i| {
            #[allow(clippy::cast_precision_loss, reason = "0 to 2")]
            let east = 0.000_65 * i as f64;
            node(s, first + i, lat, lon + east, &[])
        })
        .collect()
}

fn line(lat: f64, lon: f64) -> Vec<Position> {
    vec![
        Position::new(lat, lon).unwrap(),
        Position::new(lat, lon + 0.0013).unwrap(),
    ]
}

fn section(id: &str, lat: f64, lon: f64, nature: &str, access: &str) -> IgnSection {
    IgnSection {
        id: id.to_owned(),
        height_m: None,
        weight_t: Some(3.5),
        width_m: None,
        length_m: None,
        ground: Some(0),
        name: None,
        modified_at: None,
        geometry: line(lat, lon),
        nature: Some(nature.to_owned()),
        access: Some(access.to_owned()),
        road_number: None,
    }
}

/// The extract: a "sauf desserte" street mapped on the rating alone (as
/// iD maps a B13 in France), a "sauf livraisons" street, a motorway and a
/// public road beside which IGN draws a reserved lane.
fn extract(dir: &std::path::Path) -> std::path::PathBuf {
    let mut s = Strings(vec![String::new()]);
    let mut nodes = Vec::new();
    nodes.extend(street(&mut s, 1, 45.000, 1.000));
    nodes.extend(street(&mut s, 11, 45.010, 1.000));
    nodes.extend(street(&mut s, 21, 45.020, 1.000));
    nodes.extend(street(&mut s, 31, 45.030, 1.000));
    let ways = vec![
        way(
            &mut s,
            100,
            &[1, 2, 3],
            &[
                ("highway", "residential"),
                ("maxweightrating", "3.5"),
                ("maxweightrating:conditional", "none @ destination"),
            ],
        ),
        way(
            &mut s,
            200,
            &[11, 12, 13],
            &[
                ("highway", "residential"),
                ("maxweight", "3.5"),
                ("maxweight:conditional", "none @ delivery"),
            ],
        ),
        way(
            &mut s,
            300,
            &[21, 22, 23],
            &[("highway", "motorway"), ("oneway", "yes")],
        ),
        way(&mut s, 400, &[31, 32, 33], &[("highway", "primary")]),
    ];
    let path = dir.join("sample.osm.pbf");
    std::fs::write(&path, file_of(&s, &nodes, &ways)).unwrap();
    path
}

/// An aire behind the "sauf desserte" street of [`extract`]: a service
/// road leaving its last node, 111 m long, then a track going 556 m
/// farther; a residential street from its first node to a tertiary road
/// 111 m south, open to everyone; and a service road from its middle node
/// that a 7.5 t street without the plate also leads into.
fn extract_with_aire(dir: &std::path::Path) -> std::path::PathBuf {
    let mut s = Strings(vec![String::new()]);
    let mut nodes = Vec::new();
    nodes.extend(street(&mut s, 1, 45.000, 1.000));
    nodes.extend(street(&mut s, 31, 45.030, 1.000));
    for (id, north) in [(51, 0.0005), (52, 0.001), (53, 0.004), (54, 0.006)] {
        nodes.push(node(&mut s, id, 45.000 + north, 1.0013, &[]));
    }
    nodes.push(node(&mut s, 61, 44.999, 1.000, &[]));
    nodes.push(node(&mut s, 62, 44.999, 1.001, &[]));
    for (id, north) in [(71, 0.0005), (72, 0.001)] {
        nodes.push(node(&mut s, id, 45.000 + north, 1.000_65, &[]));
    }
    let ways = vec![
        way(
            &mut s,
            100,
            &[1, 2, 3],
            &[
                ("highway", "residential"),
                ("maxweightrating", "3.5"),
                ("maxweightrating:conditional", "none @ destination"),
            ],
        ),
        way(&mut s, 400, &[31, 32, 33], &[("highway", "primary")]),
        way(&mut s, 500, &[3, 51, 52], &[("highway", "service")]),
        way(&mut s, 700, &[1, 61], &[("highway", "residential")]),
        way(&mut s, 710, &[61, 62], &[("highway", "tertiary")]),
        way(&mut s, 800, &[52, 53, 54], &[("highway", "track")]),
        way(&mut s, 900, &[2, 71], &[("highway", "service")]),
        way(
            &mut s,
            910,
            &[71, 72],
            &[("highway", "residential"), ("maxweight", "7.5")],
        ),
    ];
    let path = dir.join("aire.osm.pbf");
    std::fs::write(&path, file_of(&s, &nodes, &ways)).unwrap();
    path
}

fn sections() -> Vec<IgnSection> {
    vec![
        // The desserte street, 3.5 t at IGN too.
        section("TRONROUT1", 45.000, 1.000, "Route à 1 chaussée", "Libre"),
        // The motorway, 3.5 t at IGN as the A8 at Rousset.
        section("TRONROUT3", 45.020, 1.000, "Type autoroutier", "A péage"),
        // A reserved lane along the primary road, as beside the D113 at
        // Vitrolles.
        section(
            "TRONROUT4",
            45.030,
            1.000,
            "Route à 1 chaussée",
            "Restreint aux ayants droit",
        ),
    ]
}

fn records_of(prepared: &routing::Prepared, id: &str) -> Vec<RestrictionRecord> {
    prepared
        .records
        .iter()
        .filter(|r| r.external_id == id)
        .cloned()
        .collect()
}

#[test]
fn urban_limits_reach_the_graph_and_the_check_as_a_motorhome_reads_them() {
    let dir = tempfile::tempdir().unwrap();
    let pbf = extract(dir.path());
    let at = Utc.with_ymd_and_hms(2026, 10, 6, 20, 20, 59).unwrap();
    let prepared = routing::prepare(&pbf, &sections(), at, at).unwrap();

    let desserte = records_of(&prepared, "way/100");
    assert_eq!(desserte.len(), 1, "{desserte:?}");
    assert_eq!(desserte[0].kind, RestrictionKind::MaxWeight);
    assert!(
        desserte[0].except_destination,
        "a trip may end in the street of a 'sauf desserte' plate"
    );
    let ign = records_of(&prepared, "ign/TRONROUT1");
    assert_eq!(ign.len(), 1);
    assert_eq!(ign[0].source, RestrictionSource::Ign);
    assert!(
        ign[0].except_destination,
        "IGN's figure for the same street must not close what OpenStreetMap's plate opens"
    );
    let delivery = records_of(&prepared, "way/200");
    assert!(
        !delivery[0].except_destination,
        "a delivery plate does not let a motorhome in"
    );
    assert!(
        records_of(&prepared, "ign/TRONROUT3").is_empty(),
        "IGN's 3.5 t on a motorway is set aside"
    );
    assert!(records_of(&prepared, "ign/TRONROUT4").is_empty());
    assert_eq!(prepared.report.ign_weight_set_aside, 2);
    assert_eq!(prepared.report.local_access_written, 1);
    assert_eq!(prepared.report.local_access_removed, 1);

    routing::write(&prepared, dir.path()).unwrap();
    let mut osc = String::new();
    flate2::read::GzDecoder::new(std::fs::File::open(dir.path().join("fixes.osc.gz")).unwrap())
        .read_to_string(&mut osc)
        .unwrap();
    let block = |id: i64| -> String {
        let start = osc.find(&format!("<way id=\"{id}\"")).unwrap_or(osc.len());
        let end = osc[start..].find("</way>").map_or(osc.len(), |e| start + e);
        osc[start..end].to_owned()
    };
    let w100 = block(100);
    assert!(w100.contains(r#"<tag k="maxweight" v="3.5"/>"#), "{osc}");
    assert!(
        w100.contains(r#"<tag k="maxweight:conditional" v="none @ destination"/>"#),
        "Valhalla reads the plate on the key it reads: {w100}"
    );
    let w200 = block(200);
    assert!(w200.contains(r#"<tag k="maxweight" v="3.5"/>"#), "{w200}");
    assert!(
        !w200.contains("maxweight:conditional"),
        "Valhalla would take 'none @ delivery' for local access: {w200}"
    );
    assert!(
        block(300).is_empty() && block(400).is_empty(),
        "the motorway and the public road are left as mapped: {osc}"
    );
}

#[test]
fn the_roads_enclosed_behind_a_sauf_desserte_street_take_its_limit_and_plate() {
    let dir = tempfile::tempdir().unwrap();
    let pbf = extract_with_aire(dir.path());
    let at = Utc.with_ymd_and_hms(2026, 10, 6, 20, 20, 59).unwrap();
    let prepared = routing::prepare(&pbf, &[], at, at).unwrap();
    assert_eq!(
        prepared.report.local_access_areas, 1,
        "{:?}",
        prepared.report
    );
    assert_eq!(
        prepared.report.local_access_extended, 1,
        "the service road within 500 m of the street, not the track beyond"
    );
    let aire = records_of(&prepared, "way/500");
    assert_eq!(aire.len(), 1, "{aire:?}");
    assert!(
        aire[0].enclosed && aire[0].except_destination,
        "the check joins the service road to the zone and never tells of it: {aire:?}"
    );
    assert_eq!(aire[0].limit, Some(3.5));
    routing::write(&prepared, dir.path()).unwrap();
    let mut osc = String::new();
    flate2::read::GzDecoder::new(std::fs::File::open(dir.path().join("fixes.osc.gz")).unwrap())
        .read_to_string(&mut osc)
        .unwrap();
    let block = |id: i64| -> String {
        let start = osc.find(&format!("<way id=\"{id}\"")).unwrap_or(osc.len());
        let end = osc[start..].find("</way>").map_or(osc.len(), |e| start + e);
        osc[start..end].to_owned()
    };
    let aire = block(500);
    assert!(
        aire.contains(r#"<tag k="maxweight" v="3.5"/>"#)
            && aire.contains(r#"<tag k="maxweight:conditional" v="none @ destination"/>"#),
        "a trip ending at the aire gets the right from its own edge: {osc}"
    );
    assert!(aire.contains(r#"<tag k="highway" v="service"/>"#), "{aire}");
    assert!(
        aire.contains(r#"<nd ref="3"/>"#),
        "the way keeps its nodes: {aire}"
    );
    assert!(
        block(700).is_empty(),
        "a street that leads to a tertiary road 111 m away is open to everyone: {osc}"
    );
    assert!(
        block(900).is_empty(),
        "a 7.5 t street without the plate leads in too: a 5 t vehicle may pass: {osc}"
    );
    assert!(
        block(800).is_empty(),
        "the track beyond 500 m stays as mapped: {osc}"
    );
    assert!(block(400).is_empty());
}

#[test]
fn a_search_left_unfinished_or_grown_past_a_campsite_marks_nothing() {
    // Behind the "sauf desserte" street of `extract`: from its last node, a
    // chain of ten short service roads, deeper than the passes read; from
    // its first node, a road to a hub with seventy dead ends, more roads
    // than a campsite has.
    let mut s = Strings(vec![String::new()]);
    let mut nodes = street(&mut s, 1, 45.000, 1.000);
    let mut ways = vec![way(
        &mut s,
        100,
        &[1, 2, 3],
        &[
            ("highway", "residential"),
            ("maxweightrating", "3.5"),
            ("maxweightrating:conditional", "none @ destination"),
        ],
    )];
    let mut previous = 3;
    for k in 0..10_i64 {
        #[allow(clippy::cast_precision_loss, reason = "ten steps")]
        let north = 0.000_05 * (k + 1) as f64;
        nodes.push(node(&mut s, 100 + k, 45.000 + north, 1.0013, &[]));
        ways.push(way(
            &mut s,
            1_000 + k,
            &[previous, 100 + k],
            &[("highway", "service")],
        ));
        previous = 100 + k;
    }
    nodes.push(node(&mut s, 300, 44.9995, 1.000, &[]));
    ways.push(way(&mut s, 2_000, &[1, 300], &[("highway", "service")]));
    for k in 0..70_i64 {
        #[allow(clippy::cast_precision_loss, reason = "seventy steps")]
        let east = 0.000_01 * (k + 1) as f64;
        nodes.push(node(&mut s, 400 + k, 44.9994, 1.000 + east, &[]));
        ways.push(way(
            &mut s,
            3_000 + k,
            &[300, 400 + k],
            &[("highway", "service")],
        ));
    }
    let dir = tempfile::tempdir().unwrap();
    let pbf = dir.path().join("deep.osm.pbf");
    std::fs::write(&pbf, file_of(&s, &nodes, &ways)).unwrap();
    let at = Utc.with_ymd_and_hms(2026, 10, 6, 20, 20, 59).unwrap();
    let prepared = routing::prepare(&pbf, &[], at, at).unwrap();
    assert_eq!(
        prepared.report.local_access_extended, 0,
        "neither a chain the passes did not finish nor seventy roads are a campsite: {:?}",
        prepared.report
    );
    assert!(prepared.records.iter().all(|r| !r.enclosed));
}
