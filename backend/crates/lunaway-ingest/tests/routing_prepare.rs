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
