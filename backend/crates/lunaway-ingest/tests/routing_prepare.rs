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

use crate::osm_extract::{Strings, file_of, file_with, node, relation_of, way};

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

/// Degrees of longitude for `metres` east at latitude `lat`.
fn east_deg(lat: f64, metres: f64) -> f64 {
    metres / (111_195.0 * lat.to_radians().cos())
}

/// The element `<kind id="id" ...>...</kind>` of a change file, or "".
fn element(osc: &str, kind: &str, id: i64) -> String {
    let Some(start) = osc.find(&format!("<{kind} id=\"{id}\" ")) else {
        return String::new();
    };
    let end = osc[start..]
        .find(&format!("</{kind}>"))
        .map_or(osc.len(), |e| start + e);
    osc[start..end].to_owned()
}

/// The node ids of a way element, in order.
fn nds(way: &str) -> Vec<i64> {
    way.split("<nd ref=\"")
        .skip(1)
        .filter_map(|rest| rest.split('"').next()?.parse().ok())
        .collect()
}

/// A street with a 2.1 m bar in its middle (node 3), which is also where a
/// side road starts; a turn from the street onto a third road at its far
/// end, and a road route along both; a service ring closed at a bollard; a
/// way of 3 m with a bar; a street whose bar a turn through it names as
/// its `via` way. The extract's highest ids are node 5000 and way 900.
fn extract_with_bars(dir: &std::path::Path) -> std::path::PathBuf {
    let lat = 45.05;
    let at = |metres: f64| 1.0 + east_deg(lat, metres);
    let mut s = Strings(vec![String::new()]);
    let mut nodes = Vec::new();
    for (id, metres) in [(1, 0.0), (2, 50.0), (4, 150.0), (5, 200.0), (7, 250.0)] {
        nodes.push(node(&mut s, id, lat, at(metres), &[]));
    }
    nodes.push(node(
        &mut s,
        3,
        lat,
        at(100.0),
        &[("barrier", "height_restrictor"), ("maxheight", "2.1")],
    ));
    nodes.push(node(&mut s, 6, lat + 0.0009, at(100.0), &[]));
    nodes.push(node(
        &mut s,
        10,
        lat - 0.001,
        at(0.0),
        &[("barrier", "bollard"), ("maxwidth", "1.5")],
    ));
    nodes.push(node(&mut s, 11, lat - 0.001, at(30.0), &[]));
    nodes.push(node(&mut s, 12, lat - 0.0013, at(30.0), &[]));
    nodes.push(node(&mut s, 20, lat + 0.002, at(0.0), &[]));
    nodes.push(node(
        &mut s,
        21,
        lat + 0.002,
        at(1.5),
        &[("barrier", "height_restrictor"), ("maxheight", "2")],
    ));
    nodes.push(node(&mut s, 22, lat + 0.002, at(3.0), &[]));
    for (id, metres) in [(39, 0.0), (40, 50.0), (42, 150.0), (43, 200.0)] {
        nodes.push(node(&mut s, id, lat + 0.004, at(metres), &[]));
    }
    nodes.push(node(
        &mut s,
        41,
        lat + 0.004,
        at(100.0),
        &[("barrier", "height_restrictor"), ("maxheight", "2.5")],
    ));
    nodes.push(node(&mut s, 30, lat + 0.006, at(0.0), &[]));
    nodes.push(node(&mut s, 5_000, lat + 0.006, at(50.0), &[]));
    let street = [("highway", "residential"), ("name", "Rue A")];
    let ways = vec![
        way(&mut s, 100, &[1, 2, 3, 4, 5], &street),
        way(&mut s, 200, &[3, 6], &[("highway", "service")]),
        way(&mut s, 300, &[5, 7], &[("highway", "residential")]),
        way(&mut s, 400, &[10, 11, 12, 10], &[("highway", "service")]),
        way(&mut s, 500, &[20, 21, 22], &[("highway", "service")]),
        way(&mut s, 600, &[40, 41, 42], &[("highway", "residential")]),
        way(&mut s, 610, &[42, 43], &[("highway", "residential")]),
        way(&mut s, 620, &[39, 40], &[("highway", "residential")]),
        way(&mut s, 900, &[30, 5_000], &[("highway", "track")]),
    ];
    let relations = vec![
        relation_of(
            &mut s,
            7_000,
            &[(1, 100, "from"), (0, 5, "via"), (1, 300, "to")],
            &[("type", "restriction"), ("restriction", "no_left_turn")],
        ),
        relation_of(
            &mut s,
            8_000,
            &[(1, 100, ""), (1, 300, "")],
            &[
                ("type", "route"),
                ("route", "road"),
                ("network", "FR:D"),
                ("ref", "1"),
            ],
        ),
        relation_of(
            &mut s,
            9_100,
            &[(1, 620, "from"), (1, 600, "via"), (1, 610, "to")],
            &[("type", "restriction"), ("restriction", "no_u_turn")],
        ),
    ];
    let path = dir.join("bars.osm.pbf");
    std::fs::write(&path, file_with(&s, &nodes, &ways, &relations)).unwrap();
    path
}

#[test]
fn a_bar_on_a_node_closes_a_stretch_of_each_way_through_it_and_the_relations_follow() {
    let dir = tempfile::tempdir().unwrap();
    let pbf = extract_with_bars(dir.path());
    let at = Utc.with_ymd_and_hms(2026, 10, 11, 1, 0, 0).unwrap();
    let prepared = routing::prepare(&pbf, &[], at, at).unwrap();
    let r = &prepared.report;
    assert_eq!(
        (
            r.node_limits_carried,
            r.node_limit_ways,
            r.node_limit_ways_created,
            r.node_limit_nodes_created,
            r.node_limit_relations,
            r.node_limit_ways_left_whole,
        ),
        (2, 3, 3, 3, 2, 2),
        "{r:?}"
    );
    assert!(
        !records_of(&prepared, "node/3").is_empty(),
        "the check keeps the bar: a vehicle the engine lets through is still warned"
    );
    assert_eq!(
        prepared.cut_ways,
        vec![100, 200],
        "the short way keeps its id whole, the ways left whole are not cut"
    );

    routing::write(&prepared, dir.path()).unwrap();
    assert_eq!(
        std::fs::read_to_string(dir.path().join("cut-ways.txt")).unwrap(),
        "100\n200\n",
        "the build checks the route tests against this list"
    );
    let mut osc = String::new();
    flate2::read::GzDecoder::new(std::fs::File::open(dir.path().join("fixes.osc.gz")).unwrap())
        .read_to_string(&mut osc)
        .unwrap();
    let create = osc.find("<create>").unwrap();

    // The street: three pieces, the middle one 4 m long around the bar.
    let street = element(&osc, "way", 100);
    assert!(
        osc.find(&street).unwrap() < create,
        "the way is modified: {osc}"
    );
    assert_eq!(nds(&street), vec![1, 2, 5_001]);
    assert!(!street.contains("maxheight"), "{street}");
    let bar = element(&osc, "way", 901);
    assert!(
        osc.find(&bar).unwrap() > create,
        "a piece is created: {osc}"
    );
    assert_eq!(nds(&bar), vec![5_001, 3, 5_002]);
    assert!(bar.contains(r#"<tag k="maxheight" v="2.1"/>"#), "{bar}");
    assert!(
        bar.contains(r#"<tag k="name" v="Rue A"/>"#),
        "the piece keeps the street's tags, so its name and guidance do not change: {bar}"
    );
    let rest = element(&osc, "way", 902);
    assert_eq!(nds(&rest), vec![5_002, 4, 5]);
    assert!(!rest.contains("maxheight"), "{rest}");
    let lon_of = |id: i64| -> f64 {
        let n = element(&osc, "node", id);
        n.split("lon=\"")
            .nth(1)
            .unwrap()
            .split('"')
            .next()
            .unwrap()
            .parse()
            .unwrap()
    };
    let metres = |lon: f64| (lon - 1.0) * 111_195.0 * 45.05_f64.to_radians().cos();
    assert!((metres(lon_of(5_001)) - 98.0).abs() < 0.05);
    assert!((metres(lon_of(5_002)) - 102.0).abs() < 0.05);

    // The side road starts at the bar: its first 2 m carry the limit.
    let side = element(&osc, "way", 200);
    assert_eq!(nds(&side), vec![3, 5_003]);
    assert!(side.contains(r#"<tag k="maxheight" v="2.1"/>"#), "{side}");
    assert_eq!(nds(&element(&osc, "way", 903)), vec![5_003, 6]);

    // A way shorter than the stretch takes the limit whole.
    let short = element(&osc, "way", 500);
    assert_eq!(nds(&short), vec![20, 21, 22]);
    assert!(short.contains(r#"<tag k="maxheight" v="2"/>"#), "{short}");

    // Left to the check: the ring closed at its bollard, the street a turn
    // goes through.
    assert!(element(&osc, "way", 400).is_empty(), "{osc}");
    assert!(element(&osc, "way", 600).is_empty(), "{osc}");
    assert!(element(&osc, "relation", 9_100).is_empty(), "{osc}");

    // The turn starts from the piece that reaches its node; the route names
    // every piece in order.
    let turn = element(&osc, "relation", 7_000);
    assert!(
        turn.contains(r#"<member type="way" ref="902" role="from"/>"#)
            && turn.contains(r#"<member type="node" ref="5" role="via"/>"#)
            && turn.contains(r#"<member type="way" ref="300" role="to"/>"#)
            && turn.contains(r#"<tag k="restriction" v="no_left_turn"/>"#),
        "{turn}"
    );
    let route = element(&osc, "relation", 8_000);
    let members: Vec<&str> = route
        .split("<member ")
        .skip(1)
        .map(|m| m.split("/>").next().unwrap())
        .collect();
    assert_eq!(
        members,
        vec![
            r#"type="way" ref="100" role="""#,
            r#"type="way" ref="901" role="""#,
            r#"type="way" ref="902" role="""#,
            r#"type="way" ref="300" role="""#,
        ],
        "{route}"
    );

    // Every node a way of the change file names exists, in the extract or
    // created by it.
    let created: std::collections::HashSet<i64> = (5_001..=5_003).collect();
    for id in [100, 200, 500, 901, 902, 903] {
        for n in nds(&element(&osc, "way", id)) {
            assert!(
                n < 5_000 || created.contains(&n),
                "way {id} names node {n}, which nothing creates"
            );
        }
    }
}
