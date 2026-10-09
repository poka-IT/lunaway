//! What lies along a route besides fuel, through the router: points of
//! interest and places set beside the real line of the A20 between Limoges
//! and Brive (93.7 km), at known distances along it and off it, and the
//! fake routing engine of the fuel tests (1.3 times the straight line, at
//! 60 km/h).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::{collections::HashSet, time::Duration};

use axum::Router;
use chrono::{TimeZone, Utc};
use lunaway_api::{
    ApiConfig, ApiState,
    config::{Quota, RoutingConfig},
};
use lunaway_db::{
    PgPool,
    pois::{self, NewPoi},
};
use lunaway_domain::{
    Position, SourceId,
    along::{Standing, order},
    fuel::Corridor,
    poi::{PoiKind, PoiRecord},
    routing::polyline,
};
use serde_json::{Value, json};
use uuid::Uuid;

use crate::fuel::{ROUTE, code, engine, gql, ok};

fn line() -> Vec<Position> {
    polyline::decode(ROUTE.trim()).unwrap()
}

/// The point `off_m` to the right of the route, `along_km` from its start.
fn beside(along_km: f64, off_m: f64) -> Position {
    let c = Corridor::new(line(), 100.0).unwrap();
    let at = c.point_at(along_km * 1_000.0);
    let right = (c.heading_at(along_km * 1_000.0) + 90.0).to_radians();
    let k = 111_195.0;
    Position::new(
        at.lat() + off_m * right.cos() / k,
        at.lon() + off_m * right.sin() / (k * at.lat().to_radians().cos()),
    )
    .unwrap()
}

fn app(pool: &PgPool, engine: Option<&str>, quota: Option<Quota>) -> Router {
    let mut config = ApiConfig {
        routing: RoutingConfig {
            valhalla_url: engine.map(str::to_owned),
            timeout: Duration::from_millis(800),
            concurrency: 4,
            queue_wait: Duration::from_millis(200),
        },
        ..ApiConfig::default()
    };
    if let Some(q) = quota {
        config.quotas.along_route = q;
    }
    lunaway_api::router(ApiState::new(pool.clone(), config))
}

/// Points of interest of `kind` named after where they stand.
async fn seed_pois(pool: &PgPool, kind: PoiKind, at: &[(&str, f64, f64)]) {
    let raw = json!({});
    let records: Vec<(String, PoiRecord)> = at
        .iter()
        .map(|(name, along, off)| {
            let mut r = PoiRecord::new(kind, beside(*along, *off));
            r.name = Some((*name).to_owned());
            (format!("node/{kind}-{name}"), r)
        })
        .collect();
    let rows: Vec<NewPoi<'_>> = records
        .iter()
        .map(|(id, r)| NewPoi {
            external_id: id,
            external_url: None,
            record: r,
            raw: &raw,
            fetched_at: Utc.with_ymd_and_hms(2026, 10, 5, 22, 0, 0).unwrap(),
            scope: Some("FR"),
        })
        .collect();
    pois::upsert(pool, &SourceId::OSM, &rows).await.unwrap();
}

const ITEMS: &str = "alongKm distanceM detour { km minutes measured } \
                     poi { id name kind openingIntervalsUntil } \
                     place { id name overnight priceParkingEur coverPhotos { thumbUrl } } \
                     photo { id sourceId sourceLabel thumbUrl licence }";

fn query() -> String {
    format!(
        "query($i: AlongRouteInput!) {{ alongRoute(input: $i) {{ \
         routeKm searchedKm candidates next detoursMeasured items {{ {ITEMS} }} }} }}"
    )
}

fn toilets(limit: i32) -> Value {
    json!({"i": {
        "polyline": ROUTE.trim(),
        "poiKinds": ["TOILETS"],
        "maxDetourKm": 6.0,
        "nearKm": 50.0,
        "limit": limit,
    }})
}

fn names(items: &[Value], what: &str) -> Vec<String> {
    items
        .iter()
        .map(|i| i[what]["name"].as_str().unwrap_or_default().to_owned())
        .collect()
}

/// Where the toilets of [`seed_toilets`] stand: name, kilometres along the
/// route, metres to its right.
const TOILETS: &[(&str, f64, f64)] = &[
    ("by-the-road-10", 10.0, 40.0),
    ("off-the-road-20", 20.0, 2_900.0),
    ("by-the-road-30", 30.0, 150.0),
    ("a-little-off-40", 40.0, 2_500.0),
    ("far-by-the-road-70", 70.0, 60.0),
    // Outside the band of 3 km.
    ("too-far-off-25", 25.0, 4_500.0),
];

async fn seed_toilets(pool: &PgPool) {
    seed_pois(pool, PoiKind::Toilets, TOILETS).await;
    // Another kind on the road: not asked for.
    seed_pois(pool, PoiKind::DrinkingWater, &[("fountain-15", 15.0, 20.0)]).await;
}

#[sqlx::test(migrations = "../../migrations")]
async fn what_lies_ahead_comes_by_the_minutes_it_adds_the_near_before_the_far(pool: PgPool) {
    seed_toilets(&pool).await;
    let (url, asked) = engine(None).await;
    let api = app(&pool, Some(&url), None);
    let body = gql(&api, &query(), toilets(20)).await;
    let r = &ok(&body)["alongRoute"];
    let items = r["items"].as_array().unwrap();
    let got = names(items, "poi");
    assert_eq!(
        got.iter().cloned().collect::<HashSet<_>>(),
        [
            "by-the-road-10",
            "off-the-road-20",
            "by-the-road-30",
            "a-little-off-40",
            "far-by-the-road-70"
        ]
        .map(str::to_owned)
        .into_iter()
        .collect::<HashSet<_>>(),
        "the toilets of the band: {got:?}"
    );
    assert_eq!(r["candidates"], 5);
    assert_eq!(r["next"], Value::Null);
    assert_eq!(r["detoursMeasured"], true);
    assert!((93.0..94.5).contains(&r["routeKm"].as_f64().unwrap()));
    assert!(!asked.lock().unwrap().is_empty(), "the engine measured");
    // In the order of the list: the near ones by whole minutes, then along
    // the route; the one past 50 km last.
    let standing = |i: &Value| Standing {
        along_m: i["alongKm"].as_f64().unwrap() * 1_000.0,
        minutes: i["detour"]["minutes"].as_f64().unwrap(),
    };
    for w in items.windows(2) {
        assert_ne!(
            order(standing(&w[0]), standing(&w[1]), 50_000.0),
            std::cmp::Ordering::Greater,
            "{got:?}"
        );
    }
    assert_eq!(got.last().unwrap(), "far-by-the-road-70");
    assert_eq!(got[0], "by-the-road-10", "on the road and nearest");
    let at = |name: &str| got.iter().position(|n| n == name).unwrap();
    assert!(
        at("a-little-off-40") < at("off-the-road-20"),
        "measured, 40 adds fewer minutes than 20, which the straight line ranked first: \
         the page is ranked again on what the engine measured ({got:?})"
    );
    let off = items
        .iter()
        .find(|i| i["poi"]["name"] == "off-the-road-20")
        .unwrap();
    // The road bends: its nearest point may be nearer than the one it
    // was set beside.
    assert!(
        (1_500.0..=2_900.0).contains(&off["distanceM"].as_f64().unwrap()),
        "{off}"
    );
    assert!(off["detour"]["minutes"].as_f64().unwrap() >= 1.5, "{off}");
    for i in items {
        assert_eq!(i["poi"]["kind"], "TOILETS");
        assert!(i["alongKm"].as_f64().unwrap() >= 2.0);
        assert_eq!(i["place"], Value::Null);
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn what_no_road_reaches_once_measured_is_left_out(pool: PgPool) {
    seed_toilets(&pool).await;
    let blocked = beside(30.0, 150.0);
    let (url, _) = engine(Some((blocked.lat(), blocked.lon()))).await;
    let api = app(&pool, Some(&url), None);
    let body = gql(&api, &query(), toilets(20)).await;
    let r = &ok(&body)["alongRoute"];
    let got = names(r["items"].as_array().unwrap(), "poi");
    assert!(
        !got.contains(&"by-the-road-30".to_owned()),
        "the engine finds no road to it: {got:?}"
    );
    assert_eq!(got.len(), 4);
    assert_eq!(
        r["candidates"], 5,
        "counted among the candidates all the same"
    );
    assert_eq!(r["detoursMeasured"], true);
}

#[sqlx::test(migrations = "../../migrations")]
async fn pages_follow_each_other_and_a_cursor_pages_its_own_search_only(pool: PgPool) {
    let at: Vec<(String, f64, f64)> = (0..7)
        .map(|i| (format!("t{i}"), 5.0 + 10.0 * f64::from(i), 100.0))
        .collect();
    let at: Vec<(&str, f64, f64)> = at.iter().map(|(n, a, o)| (n.as_str(), *a, *o)).collect();
    seed_pois(&pool, PoiKind::Toilets, &at).await;
    // No engine: the detours are estimated, the pages still in order.
    let api = app(&pool, None, None);
    let mut seen = Vec::new();
    let mut input = toilets(3);
    let mut pages = 0;
    loop {
        let body = gql(&api, &query(), input.clone()).await;
        let r = ok(&body)["alongRoute"].clone();
        assert_eq!(r["candidates"], 7);
        assert_eq!(r["detoursMeasured"], false);
        let items = r["items"].as_array().unwrap();
        assert!(items.len() <= 3);
        seen.extend(names(items, "poi"));
        pages += 1;
        match r["next"].as_str() {
            Some(next) => input["i"]["after"] = next.into(),
            None => break,
        }
    }
    assert_eq!(pages, 3);
    assert_eq!(
        seen,
        ["t0", "t1", "t2", "t3", "t4", "t5", "t6"].map(str::to_owned),
        "every item once, by distance along the route at equal minutes"
    );
    // The cursor of the second page with another order.
    let first = gql(&api, &query(), toilets(3)).await;
    let next = ok(&first)["alongRoute"]["next"]
        .as_str()
        .unwrap()
        .to_owned();
    let mut other = toilets(3);
    other["i"]["nearKm"] = 20.0.into();
    other["i"]["after"] = next.into();
    assert_eq!(code(&gql(&api, &query(), other).await), "INVALID_INPUT");
}

/// A place set beside the route: its name, kilometres along, metres off,
/// night, height limit, price of a night, services.
type PlaceSeed = (
    &'static str,
    f64,
    f64,
    &'static str,
    Option<f64>,
    Option<f64>,
    &'static [&'static str],
);

#[sqlx::test(migrations = "../../migrations")]
async fn places_to_sleep_are_those_whose_night_is_asked_and_that_take_the_vehicle(pool: PgPool) {
    let places: [PlaceSeed; 7] = [
        ("allowed-12", 12.0, 300.0, "allowed", None, Some(12.0), &[]),
        ("tolerated-25", 25.0, 600.0, "tolerated", None, None, &[]),
        ("forbidden-15", 15.0, 200.0, "forbidden", None, None, &[]),
        (
            "low-barrier-18",
            18.0,
            100.0,
            "allowed",
            Some(2.0),
            None,
            &[],
        ),
        (
            "tall-enough-35",
            35.0,
            100.0,
            "allowed",
            Some(3.5),
            Some(0.0),
            &[],
        ),
        (
            "water-tap-28",
            28.0,
            80.0,
            "forbidden",
            None,
            None,
            &["drinking_water"],
        ),
        (
            "wifi-only-32",
            32.0,
            80.0,
            "forbidden",
            None,
            None,
            &["wifi"],
        ),
    ];
    let mut ids = std::collections::HashMap::new();
    for (name, along, off, night, height, price, services) in places {
        let id = Uuid::now_v7();
        ids.insert(name, id);
        let p = beside(along, off);
        let services: Vec<String> = services.iter().map(|s| (*s).to_owned()).collect();
        sqlx::query!(
            r#"
            INSERT INTO places (id, kind, name, geom, overnight, max_height_m,
                                price_parking_eur, services, content_hash)
            VALUES ($1, 'motorhome_area', $2, ST_SetSRID(ST_MakePoint($4, $3), 4326)::geography,
                    $5, $6, $7, $8, 'x')
            "#,
            id,
            name,
            p.lat(),
            p.lon(),
            night,
            height,
            price,
            &services,
        )
        .execute(&pool)
        .await
        .unwrap();
    }
    // A photo of the place itself; one of the surroundings only and one of
    // DATAtourisme, which the card shows with its update date; one whose
    // rights ended.
    for (place, source, relation, rights_end) in [
        ("allowed-12", "wikimedia-commons", "linked", None),
        ("tolerated-25", "wikimedia-commons", "nearby", None),
        ("tolerated-25", "datatourisme", "linked", None),
        (
            "tall-enough-35",
            "wikimedia-commons",
            "linked",
            chrono::NaiveDate::from_ymd_opt(2020, 1, 1),
        ),
    ] {
        sqlx::query!(
            r#"
            INSERT INTO content_photos (id, place_id, source_id, external_id, version, relation,
                                        page_url, licence, licence_url, path, thumb_path, width,
                                        height, thumbhash, rank, fetched_at, rights_end_on)
            VALUES ($1, $2, $3, $4, '1', $5,
                    'https://commons.wikimedia.org/wiki/File:x.jpg', 'CC BY-SA 4.0',
                    'https://creativecommons.org/licenses/by-sa/4.0/', 'ab/full.webp',
                    'ab/thumb.webp', 1280, 960, '\x00', 0, now(), $6)
            "#,
            Uuid::now_v7(),
            ids[place],
            source,
            format!("File:{place}-{source}.jpg"),
            relation,
            rights_end,
        )
        .execute(&pool)
        .await
        .unwrap();
    }
    let api = app(&pool, None, None);
    // Any of the services asked: the water tap, not the wifi.
    let body = gql(
        &api,
        &query(),
        json!({"i": {
            "polyline": ROUTE.trim(),
            "places": {"anyService": ["DRINKING_WATER", "GREY_WATER"]},
        }}),
    )
    .await;
    assert_eq!(
        names(
            ok(&body)["alongRoute"]["items"].as_array().unwrap(),
            "place"
        ),
        ["water-tap-28"]
    );
    let body = gql(
        &api,
        &query(),
        json!({"i": {
            "polyline": ROUTE.trim(),
            "places": {"overnight": ["ALLOWED", "TOLERATED"]},
            "maxDetourKm": 6.0,
            "vehicle": {"kind": "OVERCAB", "heightM": 3.3, "widthM": 2.3, "lengthM": 7.4,
                        "weightT": 3.5},
        }}),
    )
    .await;
    let items = ok(&body)["alongRoute"]["items"].as_array().unwrap().clone();
    let got: HashSet<String> = names(&items, "place").into_iter().collect();
    assert_eq!(
        got,
        ["allowed-12", "tolerated-25", "tall-enough-35"]
            .map(str::to_owned)
            .into_iter()
            .collect(),
        "a forbidden night and a barrier under the vehicle are left out"
    );
    let item = |name: &str| items.iter().find(|i| i["place"]["name"] == name).unwrap();
    let allowed = item("allowed-12");
    assert_eq!(allowed["place"]["overnight"], "ALLOWED");
    assert_eq!(allowed["place"]["priceParkingEur"], 12.0);
    assert_eq!(allowed["photo"]["sourceId"], "wikimedia-commons");
    assert_eq!(allowed["photo"]["licence"], "CC BY-SA 4.0");
    assert!(
        allowed["photo"]["thumbUrl"]
            .as_str()
            .unwrap()
            .ends_with("ab/thumb.webp")
    );
    assert_eq!(
        item("tolerated-25")["photo"],
        Value::Null,
        "a photo of the surroundings is not the place's, and DATAtourisme's waits for the card"
    );
    let tall = item("tall-enough-35");
    assert_eq!(tall["place"]["priceParkingEur"], 0.0);
    assert_eq!(tall["photo"], Value::Null, "its rights ended");

    // The open source's photos hidden, one by one, then all of them.
    let photo_of = |name: &'static str| {
        let api = api.clone();
        async move {
            let body = gql(
                &api,
                &query(),
                json!({"i": {"polyline": ROUTE.trim(), "places": {"overnight": ["ALLOWED"]}}}),
            )
            .await;
            ok(&body)["alongRoute"]["items"]
                .as_array()
                .unwrap()
                .iter()
                .find(|i| i["place"]["name"] == name)
                .map(|i| i["photo"].clone())
                .unwrap()
        }
    };
    assert_ne!(photo_of("allowed-12").await, Value::Null);
    for (scope, key) in [
        ("photo", "File:allowed-12-wikimedia-commons.jpg".to_owned()),
        ("place", ids["allowed-12"].to_string()),
        ("source", "wikimedia-commons".to_owned()),
    ] {
        sqlx::query!(
            "INSERT INTO content_hides (source_id, scope, key) VALUES ('wikimedia-commons', $1, $2)",
            scope,
            key,
        )
        .execute(&pool)
        .await
        .unwrap();
        assert_eq!(
            photo_of("allowed-12").await,
            Value::Null,
            "hidden by {scope}"
        );
        sqlx::query!("DELETE FROM content_hides")
            .execute(&pool)
            .await
            .unwrap();
    }
    sqlx::query!(
        "INSERT INTO source_switches (source_id, hidden_at) VALUES ('wikimedia-commons', now())"
    )
    .execute(&pool)
    .await
    .unwrap();
    assert_eq!(
        photo_of("allowed-12").await,
        Value::Null,
        "the source hidden"
    );
}

/// The photo of `place`'s row in a search along a line through the
/// partner's Parking du lac at Annecy, due north.
async fn row_photo(api: &Router, place: Uuid) -> Value {
    let line = polyline::encode(&[
        Position::new(45.80, 6.1294).unwrap(),
        Position::new(46.00, 6.1294).unwrap(),
    ]);
    let body = gql(
        api,
        &query(),
        json!({"i": {"polyline": line, "places": {}, "maxDetourKm": 2.0}}),
    )
    .await;
    ok(&body)["alongRoute"]["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|i| i["place"]["id"] == json!(place))
        .map(|i| i["photo"].clone())
        .expect("the place lies on the line")
}

async fn external_id_of(pool: &PgPool, photo: &Value) -> String {
    let id: Uuid = photo["id"].as_str().unwrap().parse().unwrap();
    sqlx::query_scalar!("SELECT external_id FROM external_photos WHERE id = $1", id)
        .fetch_one(pool)
        .await
        .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_row_shows_the_partner_s_newest_stored_photo_and_nothing_hidden(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let place = crate::digests::seeded(&pool, dir.path()).await;
    let api = app(&pool, None, None);
    assert_eq!(
        row_photo(&api, place).await,
        Value::Null,
        "a photo the proxy has not fetched yet: a list never makes it download"
    );
    // Both photos of the place (p-1 taken in August, p-2 undated) stored.
    sqlx::query!(
        r#"
        UPDATE external_photos
        SET path = 'photos/ab/cd/' || md5(external_id) || md5(external_id) || '.webp',
            thumb_path = 'photos/ab/cd/' || md5(external_id || 't') || md5(external_id) || '.webp',
            processed_at = now()
        WHERE external_id IN ('p-1', 'p-2')
        "#,
    )
    .execute(&pool)
    .await
    .unwrap();
    let shown = row_photo(&api, place).await;
    assert_eq!(shown["sourceId"], "extcom");
    assert_eq!(external_id_of(&pool, &shown).await, "p-1", "the newest");
    let hide = |scope: &'static str, key: String| {
        let pool = pool.clone();
        async move {
            sqlx::query!(
                "INSERT INTO content_hides (source_id, scope, key) VALUES ('extcom', $1, $2)",
                scope,
                key,
            )
            .execute(&pool)
            .await
            .unwrap();
        }
    };
    hide("photo", "p-1".to_owned()).await;
    let shown = row_photo(&api, place).await;
    assert_eq!(external_id_of(&pool, &shown).await, "p-2", "p-1 hidden");
    hide("place", place.to_string()).await;
    assert_eq!(
        row_photo(&api, place).await,
        Value::Null,
        "the place's hidden"
    );
    sqlx::query!("DELETE FROM content_hides WHERE scope = 'place'")
        .execute(&pool)
        .await
        .unwrap();
    assert_ne!(row_photo(&api, place).await, Value::Null);
    // An author erased: the photo is retired, its files stay until purged.
    sqlx::query!("UPDATE external_photos SET retired_at = now() WHERE external_id = 'p-2'")
        .execute(&pool)
        .await
        .unwrap();
    assert_eq!(row_photo(&api, place).await, Value::Null, "p-2 retired");
    sqlx::query!("UPDATE external_photos SET retired_at = NULL WHERE external_id = 'p-2'")
        .execute(&pool)
        .await
        .unwrap();
    assert_ne!(row_photo(&api, place).await, Value::Null);
    hide("source", "extcom".to_owned()).await;
    assert_eq!(
        row_photo(&api, place).await,
        Value::Null,
        "the source's hidden"
    );
    sqlx::query!("DELETE FROM content_hides WHERE scope = 'source'")
        .execute(&pool)
        .await
        .unwrap();
    assert_ne!(row_photo(&api, place).await, Value::Null);
    sqlx::query!("INSERT INTO source_switches (source_id, hidden_at) VALUES ('extcom', now())")
        .execute(&pool)
        .await
        .unwrap();
    assert_eq!(
        row_photo(&api, place).await,
        Value::Null,
        "the source hidden"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_search_along_a_route_is_bounded_and_counted(pool: PgPool) {
    seed_pois(&pool, PoiKind::Toilets, &[("t", 10.0, 50.0)]).await;
    let (url, asked) = engine(None).await;
    let api = app(
        &pool,
        Some(&url),
        Some(Quota {
            count: 1,
            period: Duration::from_secs(600),
        }),
    );
    let mut nothing = toilets(5);
    nothing["i"]["poiKinds"] = json!([]);
    assert_eq!(
        code(&gql(&api, &query(), nothing).await),
        "INVALID_INPUT",
        "neither points of interest nor places"
    );
    let mut wide = toilets(5);
    wide["i"]["maxDetourKm"] = 31.0.into();
    assert_eq!(code(&gql(&api, &query(), wide).await), "INVALID_INPUT");
    assert!(
        asked.lock().unwrap().is_empty(),
        "a bad request costs the engine nothing"
    );
    let twice = gql(
        &api,
        "query($i: AlongRouteInput!) { a: alongRoute(input: $i) { candidates } \
         b: alongRoute(input: $i) { candidates } }",
        toilets(5),
    )
    .await;
    assert_eq!(
        code(&twice),
        "INVALID_INPUT",
        "one engine search per request"
    );
    // The quota of one was spent by the first of the two above.
    assert_eq!(code(&gql(&api, &query(), toilets(5)).await), "RATE_LIMITED");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_route_within_its_two_cut_ends_searches_nothing(pool: PgPool) {
    seed_pois(&pool, PoiKind::Toilets, &[("t", 1.5, 20.0)]).await;
    let (url, asked) = engine(None).await;
    let api = app(&pool, Some(&url), None);
    let short: Vec<Position> = lunaway_domain::along::head(&line(), 3_500.0);
    let mut input = toilets(5);
    input["i"]["polyline"] = polyline::encode(&short).into();
    let body = gql(&api, &query(), input).await;
    let r = &ok(&body)["alongRoute"];
    assert_eq!(r["items"], json!([]));
    assert_eq!(r["candidates"], 0);
    assert_eq!(r["searchedKm"], 0.0);
    assert!(asked.lock().unwrap().is_empty());
}
