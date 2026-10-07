//! The routing tables on a real database: a graph's restrictions load and
//! activate, the corridor query returns what lies along a route (real
//! shapes of the Rue Maurice Utrillo case in Limoges, from Valhalla 3.9.0 on
//! the France graph of 2026-10-06), and each role holds the rights it needs.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::{TimeZone, Utc};
use lunaway_db::{
    PgPool,
    routing::{self, NewGraph},
};
use lunaway_domain::{
    Position,
    routing::{
        Certainty, RestrictionFeature, RestrictionKind, RestrictionRecord, RestrictionSource,
        RouteLine, VehicleInput, VehicleKind, VehicleProfile, assess, match_restriction,
        match_route, polyline,
    },
};
use sqlx::postgres::PgPoolOptions;

/// A 2.5 m van from 45.84719,1.28476 to 45.84510,1.28637: under the railway
/// bridge of Rue Maurice Utrillo (way 52984577, `maxheight=2.7`), 269 m.
const ROUTE_UNDER: &str = "yhhmvAshlmAD_@^wBlAcCnAiAvAy@jB_@tC]hDm@jj@q`@hd@c]~G_EjPyIlAu@";

fn at(lat: f64, lon: f64) -> Position {
    Position::new(lat, lon).unwrap()
}

/// The way under the bridge, as the route uses it (shape points 8 and 9).
fn tunnel() -> Vec<Position> {
    vec![at(45.846_841, 1.285_024), at(45.846_147, 1.285_561)]
}

fn graph(id: &str) -> NewGraph {
    NewGraph {
        id: id.to_owned(),
        osm_data_at: Utc.with_ymd_and_hms(2026, 10, 5, 20, 20, 43).unwrap(),
        ign_fetched_at: Some(Utc.with_ymd_and_hms(2026, 10, 6, 6, 0, 0).unwrap()),
        ign_edition: chrono::NaiveDate::from_ymd_opt(2026, 6, 15),
        built_at: Utc.with_ymd_and_hms(2026, 10, 6, 7, 0, 0).unwrap(),
        engine: "valhalla 3.9.0".to_owned(),
        stats: serde_json::json!({"records": 3}),
    }
}

fn record(
    source: RestrictionSource,
    external_id: &str,
    kind: RestrictionKind,
    limit: Option<f64>,
    shape: &[Position],
) -> (RestrictionRecord, Vec<Position>) {
    let r = RestrictionRecord {
        source,
        external_id: external_id.to_owned(),
        kind,
        limit,
        certainty: if limit.is_none() && kind == RestrictionKind::MaxHeight {
            Certainty::Unknown
        } else {
            Certainty::Known
        },
        feature: RestrictionFeature::Underpass,
        name: Some("Rue Maurice Utrillo".to_owned()),
        other_value: None,
        other_source: None,
        shape: polyline::encode(shape),
        observed_at: Utc.with_ymd_and_hms(2026, 10, 5, 20, 20, 43).unwrap(),
        except_destination: false,
        enclosed: false,
    };
    let points = r.check().unwrap();
    (r, points)
}

fn utrillo_records() -> Vec<(RestrictionRecord, Vec<Position>)> {
    // IGN draws the same road a few metres east, with 3.1 m.
    let ign: Vec<Position> = tunnel()
        .iter()
        .map(|p| at(p.lat(), p.lon() + 0.000_08))
        .collect();
    vec![
        record(
            RestrictionSource::Osm,
            "way/52984577",
            RestrictionKind::MaxHeight,
            Some(2.7),
            &tunnel(),
        ),
        record(
            RestrictionSource::Ign,
            "ign/TRONROUT0000000000000001",
            RestrictionKind::MaxHeight,
            Some(3.1),
            &ign,
        ),
        // A height bar 300 m away, off the route.
        record(
            RestrictionSource::Osm,
            "node/1",
            RestrictionKind::MaxHeight,
            Some(1.9),
            &[at(45.8490, 1.2870)],
        ),
    ]
}

async fn as_role(pool: &PgPool, set_role: &'static str) -> PgPool {
    PgPoolOptions::new()
        .max_connections(2)
        .after_connect(move |conn, _| {
            Box::pin(async move {
                sqlx::query(set_role).execute(conn).await?;
                Ok(())
            })
        })
        .connect_with((*pool.connect_options()).clone())
        .await
        .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_graph_serves_once_activated_and_the_previous_one_stays_for_a_rollback(pool: PgPool) {
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    for id in [
        "20261005T0300Z-fr",
        "20261012T0300Z-fr",
        "20261019T0300Z-fr",
    ] {
        let n = routing::load_graph(&ingest, &graph(id), &utrillo_records())
            .await
            .unwrap();
        assert_eq!(n, 3);
        assert_ne!(
            routing::active_graph(&ingest).await.unwrap().map(|g| g.id),
            Some(id.to_owned()),
            "a loaded graph does not serve before it is activated"
        );
        routing::activate(&ingest, id).await.unwrap().unwrap();
    }
    let active = routing::active_graph(&pool).await.unwrap().unwrap();
    assert_eq!(active.id, "20261019T0300Z-fr");
    assert_eq!(
        active.ign_edition,
        chrono::NaiveDate::from_ymd_opt(2026, 6, 15)
    );
    let again = routing::activate(&ingest, "20261019T0300Z-fr")
        .await
        .unwrap()
        .unwrap();
    assert!(
        again.dropped.is_empty(),
        "activating the active graph again keeps the previous one"
    );
    let ids: Vec<String> = routing::graphs(&pool)
        .await
        .unwrap()
        .into_iter()
        .map(|g| g.id)
        .collect();
    assert_eq!(
        ids,
        ["20261019T0300Z-fr", "20261012T0300Z-fr"],
        "the previous graph stays for a rollback, older ones go"
    );
    let rows: i64 = sqlx::query_scalar("SELECT count(*) FROM route_restrictions")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(rows, 6, "the rows of a dropped graph go with it");
    assert!(
        routing::load_graph(&ingest, &graph("20261019T0300Z-fr"), &utrillo_records())
            .await
            .is_err(),
        "the active graph is never replaced in place"
    );
    assert!(
        routing::activate(&ingest, "20261026T0300Z-fr")
            .await
            .unwrap()
            .is_none()
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_corridor_holds_what_lies_along_the_route_and_the_check_blocks_a_high_vehicle(
    pool: PgPool,
) {
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let id = "20261006T0300Z-fr";
    routing::load_graph(&ingest, &graph(id), &utrillo_records())
        .await
        .unwrap();
    routing::activate(&ingest, id).await.unwrap();
    // A community report (no graph) of a 2.6 m clearance on the same road.
    sqlx::query(
        "INSERT INTO route_restrictions (id, graph_id, source, external_id, kind, limit_value,
            certainty, feature, geom, observed_at)
         VALUES (gen_random_uuid(), NULL, 'community', 'report/1', 'max_height', 2.6, 'known',
            'underpass', ST_GeomFromText('POINT(1.2853 45.8465)', 4326)::geography, now())",
    )
    .execute(&pool)
    .await
    .unwrap();

    let api = as_role(&pool, "SET ROLE lunaway_app").await;
    let route = polyline::decode(ROUTE_UNDER).unwrap();
    let near = routing::restrictions_near(&api, id, &route, 15.0)
        .await
        .unwrap();
    let mut found: Vec<&str> = near.iter().map(|r| r.external_id.as_str()).collect();
    found.sort_unstable();
    assert_eq!(
        found,
        ["ign/TRONROUT0000000000000001", "report/1", "way/52984577"],
        "the bar 300 m away is not in the corridor; the community report is"
    );
    assert!(
        routing::restrictions_near(&api, "20200101T0000Z-fr", &route, 15.0)
            .await
            .unwrap()
            .iter()
            .all(|r| r.external_id == "report/1"),
        "another graph's rows are not read"
    );

    // The check: a 3.3 m motorhome on this route meets blockers from every
    // source; a 2.5 m van passes.
    let line = RouteLine::new(route).unwrap();
    let vehicle = |height_m| {
        VehicleProfile::new(VehicleInput {
            kind: VehicleKind::Overcab,
            height_m,
            width_m: 2.3,
            length_m: 7.4,
            weight_t: 3.5,
            axle_load_t: None,
            trailer: None,
            cruise_speed_kph: None,
        })
        .unwrap()
        .routing()
    };
    let blocking = |height_m| {
        near.iter()
            .filter(|r| !match_restriction(&line, &r.geometry, r.restriction.source).is_empty())
            .filter_map(|r| assess(&r.restriction, &vehicle(height_m)))
            .filter(|f| f.severity == lunaway_domain::routing::Severity::Blocking)
            .count()
    };
    assert_eq!(
        blocking(3.3),
        3,
        "OSM 2.7 m, IGN 3.1 m and the 2.6 m report each stop a 3.3 m vehicle"
    );
    assert_eq!(blocking(2.5), 0, "a 2.5 m van passes under 2.7 m");
    let hit = match_route(&line, &tunnel(), 3.0)[0];
    assert!(
        (40.0..60.0).contains(&hit.start_m) && (125.0..145.0).contains(&hit.end_m),
        "the route enters the way under the bridge 48 m from the start and leaves it 88 m on: {hit:?}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_route_too_long_to_check_whole_is_refused(pool: PgPool) {
    let points: Vec<Position> = (0..=routing::MAX_ROUTE_POINTS)
        .map(|i| {
            #[allow(clippy::cast_precision_loss, reason = "a test index")]
            let lon = 1.0 + i as f64 * 1e-6;
            at(45.0, lon)
        })
        .collect();
    let refused = routing::restrictions_near(&pool, "20261006T0300Z-fr", &points, 15.0).await;
    assert!(
        matches!(refused, Err(lunaway_db::DbError::TooLarge { .. })),
        "a prefix is never checked in place of the whole route"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_api_reads_the_routing_tables_and_writes_none(pool: PgPool) {
    for table in ["routing_graphs", "route_restrictions"] {
        for (role, expected) in [
            ("lunaway_app", vec!["SELECT"]),
            (
                "lunaway_ingest",
                vec!["SELECT", "INSERT", "UPDATE", "DELETE"],
            ),
        ] {
            let mut has = Vec::new();
            for p in ["SELECT", "INSERT", "UPDATE", "DELETE"] {
                let ok: bool = sqlx::query_scalar("SELECT has_table_privilege($1, $2, $3)")
                    .bind(role)
                    .bind(table)
                    .bind(p)
                    .fetch_one(&pool)
                    .await
                    .unwrap();
                if ok {
                    has.push(p);
                }
            }
            assert_eq!(has, expected, "{role} on {table}");
        }
    }
    let api = as_role(&pool, "SET ROLE lunaway_app").await;
    let denied = routing::load_graph(&api, &graph("20261006T0300Z-fr"), &utrillo_records()).await;
    assert!(denied.is_err(), "the API loads no graph");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_limit_that_spares_local_access_says_so_to_the_check(pool: PgPool) {
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let id = "20261006T0300Z-fr";
    let (mut spared, points) = record(
        RestrictionSource::Osm,
        "way/52984577",
        RestrictionKind::MaxWeight,
        Some(3.5),
        &tunnel(),
    );
    spared.except_destination = true;
    let plain = record(
        RestrictionSource::Ign,
        "ign/TRONROUT0000000000000001",
        RestrictionKind::MaxWeight,
        Some(3.5),
        &tunnel(),
    );
    routing::load_graph(&ingest, &graph(id), &[(spared, points), plain])
        .await
        .unwrap();
    routing::activate(&ingest, id).await.unwrap();
    let api = as_role(&pool, "SET ROLE lunaway_app").await;
    let route = polyline::decode(ROUTE_UNDER).unwrap();
    let near = routing::restrictions_near(&api, id, &route, 15.0)
        .await
        .unwrap();
    let flags: std::collections::BTreeMap<&str, bool> = near
        .iter()
        .map(|r| (r.external_id.as_str(), r.restriction.except_destination))
        .collect();
    assert_eq!(
        flags,
        std::collections::BTreeMap::from([
            ("ign/TRONROUT0000000000000001", false),
            ("way/52984577", true)
        ]),
        "the check must know which limit a trip may end on"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_database_refuses_a_row_that_does_not_hold_together(pool: PgPool) {
    routing::load_graph(&pool, &graph("20261006T0300Z-fr"), &[])
        .await
        .unwrap();
    for (what, sql) in [
        (
            "a ban with a figure",
            "INSERT INTO route_restrictions (id, graph_id, source, external_id, kind, limit_value,
                certainty, feature, geom, observed_at) VALUES (gen_random_uuid(), '20261006T0300Z-fr',
                'osm', 'way/1', 'motorhome_ban', 3.0, 'known', 'road',
                ST_GeomFromText('POINT(1 45)', 4326)::geography, now())",
        ),
        (
            "a disputed figure without the other source",
            "INSERT INTO route_restrictions (id, graph_id, source, external_id, kind, limit_value,
                certainty, feature, geom, observed_at) VALUES (gen_random_uuid(), '20261006T0300Z-fr',
                'osm', 'way/1', 'max_height', 3.0, 'disputed', 'road',
                ST_GeomFromText('POINT(1 45)', 4326)::geography, now())",
        ),
        (
            "a polygon",
            "INSERT INTO route_restrictions (id, graph_id, source, external_id, kind, limit_value,
                certainty, feature, geom, observed_at) VALUES (gen_random_uuid(), '20261006T0300Z-fr',
                'osm', 'way/1', 'max_height', 3.0, 'known', 'road',
                ST_GeomFromText('POLYGON((1 45,1.1 45,1.1 45.1,1 45))', 4326)::geography, now())",
        ),
        (
            "a graph row from a community report",
            "INSERT INTO route_restrictions (id, graph_id, source, external_id, kind, limit_value,
                certainty, feature, geom, observed_at) VALUES (gen_random_uuid(), '20261006T0300Z-fr',
                'community', 'report/1', 'max_height', 3.0, 'known', 'road',
                ST_GeomFromText('POINT(1 45)', 4326)::geography, now())",
        ),
        (
            "a clearance that spares local access",
            "INSERT INTO route_restrictions (id, graph_id, source, external_id, kind, limit_value,
                certainty, feature, geom, observed_at, except_destination) VALUES (gen_random_uuid(),
                '20261006T0300Z-fr', 'osm', 'way/1', 'max_height', 3.0, 'known', 'road',
                ST_GeomFromText('POINT(1 45)', 4326)::geography, now(), true)",
        ),
    ] {
        assert!(sqlx::query(sql).execute(&pool).await.is_err(), "{what}");
    }
    assert!(
        sqlx::query("INSERT INTO routing_graphs (id, osm_data_at, built_at, engine) VALUES ('latest', now(), now(), 'x')")
            .execute(&pool)
            .await
            .is_err(),
        "a graph is named by its build time and area"
    );
}

/// `from` moved `metres` towards `azimuth_deg` on the spheroid, as PostGIS
/// computes it: the test's distances do not rest on the code under test.
pub(crate) async fn moved(
    pool: &PgPool,
    from: Position,
    metres: f64,
    azimuth_deg: f64,
) -> Position {
    let (lat, lon): (f64, f64) = sqlx::query_as(
        "SELECT ST_Y(g::geometry), ST_X(g::geometry) FROM (SELECT ST_Project(
            ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, $3, radians($4)) AS g) t",
    )
    .bind(from.lon())
    .bind(from.lat())
    .bind(metres)
    .bind(azimuth_deg)
    .fetch_one(pool)
    .await
    .unwrap();
    at(lat, lon)
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_corridor_holds_everything_within_its_width_far_north_and_along_a_long_segment(
    pool: PgPool,
) {
    // Near Tromsø: 30 km east along the parallel in one segment, then 2 km
    // north. The check reads a segment as a straight line in degrees; the
    // great-circle arc between the same ends runs about 47 m north of it
    // at the middle.
    let (p0, p1, p2) = (at(69.6, 18.0), at(69.6, 18.785), at(69.618, 18.785));
    let south = moved(&pool, at(69.6, 18.3925), 20.0, 180.0).await;
    let east = moved(&pool, at(69.609, 18.785), 25.0, 90.0).await;
    let beyond = moved(&pool, p2, 25.0, 0.0).await;
    let far = moved(&pool, at(69.609, 18.785), 60.0, 90.0).await;
    for (id, p) in [
        ("south", south),
        ("east", east),
        ("beyond", beyond),
        ("far", far),
    ] {
        sqlx::query(
            "INSERT INTO route_restrictions (id, graph_id, source, external_id, kind,
                limit_value, certainty, feature, geom, observed_at)
             VALUES (gen_random_uuid(), NULL, 'community', $1, 'max_height', 2.6, 'known',
                'underpass', ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography, now())",
        )
        .bind(id)
        .bind(p.lon())
        .bind(p.lat())
        .execute(&pool)
        .await
        .unwrap();
    }
    let api = as_role(&pool, "SET ROLE lunaway_app").await;
    let near = routing::restrictions_near(&api, "20261006T2326Z-eu", &[p0, p1, p2], 26.0)
        .await
        .unwrap();
    let mut found: Vec<&str> = near.iter().map(|r| r.external_id.as_str()).collect();
    found.sort_unstable();
    assert_eq!(
        found,
        ["beyond", "east", "south"],
        "everything within 26 m of the line the check reads is in the corridor, \
         at 70 degrees north where a degree of longitude is a third of one of \
         latitude, beside a 30 km segment, past the route's end; 60 m is not"
    );
}

/// A restriction of `feature` on `shape`, as the graph build or DiaLog's
/// import hands it over.
fn featured(
    source: RestrictionSource,
    external_id: &str,
    kind: RestrictionKind,
    limit: Option<f64>,
    feature: RestrictionFeature,
    shape: &[Position],
) -> (RestrictionRecord, Vec<Position>) {
    let (mut r, _) = record(source, external_id, kind, limit, shape);
    r.feature = feature;
    let points = r.check().unwrap();
    (r, points)
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_rows_a_ring_may_exclude_and_the_version_that_says_when_they_change(pool: PgPool) {
    let id = "20261006T0300Z-fr";
    let road = [at(45.80, 1.25), at(45.801, 1.251)];
    let records = vec![
        featured(
            RestrictionSource::Osm,
            "node/1",
            RestrictionKind::MaxHeight,
            None,
            RestrictionFeature::Barrier,
            &[at(45.80, 1.25)],
        ),
        featured(
            RestrictionSource::Osm,
            "way/2",
            RestrictionKind::MaxWidth,
            Some(2.0),
            RestrictionFeature::Road,
            &road,
        ),
        featured(
            RestrictionSource::Osm,
            "way/3",
            RestrictionKind::MotorhomeBan,
            None,
            RestrictionFeature::Road,
            &road,
        ),
        // A clearance on a road and one under a bridge: a ring there would
        // cut the road above too.
        featured(
            RestrictionSource::Osm,
            "way/4",
            RestrictionKind::MaxHeight,
            Some(2.5),
            RestrictionFeature::Road,
            &road,
        ),
        featured(
            RestrictionSource::Osm,
            "way/5",
            RestrictionKind::MaxHeight,
            Some(2.7),
            RestrictionFeature::Underpass,
            &road,
        ),
        // Limits the vehicle respects.
        featured(
            RestrictionSource::Osm,
            "node/6",
            RestrictionKind::MaxHeight,
            Some(4.0),
            RestrictionFeature::Barrier,
            &[at(45.81, 1.26)],
        ),
        featured(
            RestrictionSource::Osm,
            "way/7",
            RestrictionKind::MaxWeight,
            Some(7.5),
            RestrictionFeature::Road,
            &road,
        ),
    ];
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    routing::load_graph(&ingest, &graph(id), &records)
        .await
        .unwrap();
    let api = as_role(&pool, "SET ROLE lunaway_app").await;
    assert_eq!(
        routing::restrictions_version(&api).await.unwrap(),
        None,
        "no graph serves yet"
    );
    routing::activate(&ingest, id).await.unwrap();
    let first = routing::restrictions_version(&api).await.unwrap().unwrap();
    assert_eq!(
        first,
        routing::RestrictionsVersion {
            graph_id: id.to_owned(),
            outside_rows: 0,
            outside_digest: None,
        }
    );
    let envelope = routing::Envelope {
        height_m: 3.3,
        width_m: 2.3,
        length_m: 7.4,
        weight_t: 3.5,
    };
    let ids = |rows: Vec<routing::NearRestriction>| {
        let mut v: Vec<String> = rows.into_iter().map(|r| r.external_id).collect();
        v.sort();
        v
    };
    assert_eq!(
        ids(routing::ring_candidates(&api, id, envelope).await.unwrap()),
        ["node/1", "way/2", "way/3"],
        "a bar of unknown height, a width, a ban; never a clearance on a road or \
         under a bridge, nor a limit the vehicle respects"
    );

    let dialog = featured(
        RestrictionSource::Dialog,
        "dialog/019d057d-1db1-771f-b6d5-4ddb7ffd698c#0",
        RestrictionKind::MaxLength,
        Some(6.0),
        RestrictionFeature::Road,
        &road,
    );
    lunaway_db::road_events::replace_dialog_restrictions(&ingest, std::slice::from_ref(&dialog))
        .await
        .unwrap();
    let second = routing::restrictions_version(&api).await.unwrap().unwrap();
    assert_eq!(second.outside_rows, 1);
    assert_ne!(
        second, first,
        "an import outside the graphs is a new version"
    );
    assert!(
        ids(routing::ring_candidates(&api, id, envelope).await.unwrap())
            .contains(&dialog.0.external_id),
        "DiaLog's rows are read with the graph's"
    );
    lunaway_db::road_events::replace_dialog_restrictions(&ingest, std::slice::from_ref(&dialog))
        .await
        .unwrap();
    assert_eq!(
        routing::restrictions_version(&api).await.unwrap().unwrap(),
        second,
        "the same orders imported again under new ids: nothing to compute again"
    );
    let mut longer = dialog;
    longer.0.limit = Some(6.5);
    lunaway_db::road_events::replace_dialog_restrictions(&ingest, &[longer])
        .await
        .unwrap();
    let third = routing::restrictions_version(&api).await.unwrap().unwrap();
    assert_eq!(third.outside_rows, 1);
    assert_ne!(third, second, "a figure changed: a new version");
}
