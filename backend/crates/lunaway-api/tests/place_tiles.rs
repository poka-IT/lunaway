//! The places as the web app reads them without syncing: the map tiles
//! (pins with their id from the pin zoom, dots below), filtered on the
//! device with the same meaning as the `places` query's filter, and the
//! list of the places nearest to the map's centre, page by page.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::collections::{BTreeMap, BTreeSet};

use axum::{
    body::Body,
    http::{Request, StatusCode, header},
};
use http_body_util::BodyExt;
use lunaway_api::{ApiConfig, ApiState};
use lunaway_db::{PgPool, place_tiles};
use lunaway_domain::{OvernightStatus, PlaceKind, Position, Service};
use serde_json::{Value, json};
use tower::ServiceExt;
use uuid::Uuid;

use crate::mvt::{Feature, decode, tile_of};

fn app(pool: &PgPool) -> axum::Router {
    let config = ApiConfig {
        tiles: lunaway_api::config::TilesConfig {
            public_url: "https://api.test".into(),
            // The building ahead runs in the background; these tests read
            // what a client builds.
            warm: false,
            ..ApiConfig::default().tiles
        },
        ..ApiConfig::default()
    };
    lunaway_api::router(ApiState::new(pool.clone(), config))
}

async fn get(
    app: &axum::Router,
    uri: &str,
    headers: &[(&str, &str)],
) -> (StatusCode, axum::http::HeaderMap, Vec<u8>) {
    let mut r = Request::get(uri);
    for (k, v) in headers {
        r = r.header(*k, *v);
    }
    let response = app
        .clone()
        .oneshot(r.body(Body::empty()).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let headers = response.headers().clone();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (status, headers, bytes.to_vec())
}

async fn post(app: &axum::Router, body: Value) -> Value {
    let request = Request::post("/graphql")
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap()
}

async fn gql(app: &axum::Router, query: &str, variables: Value) -> Value {
    post(app, json!({"query": query, "variables": variables})).await
}

fn ok(body: &Value) -> &Value {
    assert!(body.get("errors").is_none(), "unexpected errors: {body}");
    &body["data"]
}

fn code(body: &Value) -> &str {
    body["errors"][0]["extensions"]["code"]
        .as_str()
        .unwrap_or_else(|| panic!("no error code in {body}"))
}

/// A place as the test writes it.
#[derive(Debug, Clone)]
struct Seed {
    id: Uuid,
    lat: f64,
    lon: f64,
    kind: PlaceKind,
    night: OvernightStatus,
    services: Vec<Service>,
    price: Option<f64>,
    height_m: Option<f64>,
    name: Option<String>,
}

/// The tile of zoom 12 the seeds sit in, around Annecy.
fn home() -> (u32, u32) {
    tile_of(45.9, 6.12, 12)
}

/// The latitude and longitude of the north-west corner of `z/x/y`.
fn corner(z: u32, x: u32, y: u32) -> (f64, f64) {
    let n = f64::from(1u32 << z);
    let lon = f64::from(x) / n * 360.0 - 180.0;
    let lat = (std::f64::consts::PI * (1.0 - 2.0 * f64::from(y) / n))
        .sinh()
        .atan()
        .to_degrees();
    (lat, lon)
}

/// Forty places spread inside the home tile with every combination the
/// filters read, the same each run (a fixed linear congruential sequence),
/// plus two pairs at one position: the same properties, and different ones.
fn seeds() -> Vec<Seed> {
    let (x, y) = home();
    let (north, west) = corner(12, x, y);
    let (south, east) = corner(12, x + 1, y + 1);
    let mut state: u64 = 42;
    let mut next = move |n: u64| {
        state = state
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1_442_695_040_888_963_407);
        (state >> 33) % n
    };
    let kinds = [
        PlaceKind::MotorhomeArea,
        PlaceKind::Campsite,
        PlaceKind::Parking,
        PlaceKind::ServiceArea,
        PlaceKind::Farm,
    ];
    let mut out = Vec::new();
    for i in 0..40_u32 {
        let f = |v: u64| f64::from(u32::try_from(v).unwrap()) / 1000.0;
        let lat = south + (north - south) * (0.05 + 0.9 * f(next(1000)));
        let lon = west + (east - west) * (0.05 + 0.9 * f(next(1000)));
        let services: Vec<Service> = Service::ALL
            .iter()
            .copied()
            .filter(|_| next(4) == 0)
            .collect();
        out.push(Seed {
            id: Uuid::now_v7(),
            lat,
            lon,
            kind: kinds[usize::try_from(next(5)).unwrap()],
            night: OvernightStatus::ALL[usize::try_from(next(5)).unwrap()],
            services,
            price: match next(3) {
                0 => None,
                1 => Some(0.0),
                _ => Some(f64::from(u32::try_from(next(20)).unwrap()) + 0.5),
            },
            // Whole centimetres, as the tiles carry them.
            height_m: (next(3) == 0).then(|| f64::from(250 + (i % 10) * 10) / 100.0),
            name: (next(4) != 0).then(|| format!("Aire {i}")),
        });
    }
    let base = out[0].clone();
    out.push(Seed {
        id: Uuid::now_v7(),
        name: Some("Twin".into()),
        ..base.clone()
    });
    out.push(Seed {
        id: Uuid::now_v7(),
        kind: if base.kind == PlaceKind::Farm {
            PlaceKind::Parking
        } else {
            PlaceKind::Farm
        },
        ..base
    });
    out
}

async fn seeded(pool: &PgPool) -> Vec<Seed> {
    let seeds = seeds();
    for s in &seeds {
        let services: Vec<String> = s.services.iter().map(|v| v.code().to_owned()).collect();
        sqlx::query!(
            r#"
            INSERT INTO places (id, kind, name, geom, overnight, services, price_parking_eur,
                                max_height_m, content_hash)
            VALUES ($1, $2, $3, ST_SetSRID(ST_MakePoint($5, $4), 4326)::geography, $6, $7, $8,
                    $9, 'x')
            "#,
            s.id,
            s.kind.code(),
            s.name,
            s.lat,
            s.lon,
            s.night.code(),
            &services,
            s.price,
            s.height_m,
        )
        .execute(pool)
        .await
        .unwrap();
    }
    // A place deleted: in no tile and no list.
    sqlx::query!(
        r#"
        INSERT INTO places (id, kind, geom, overnight, content_hash, deleted_at)
        VALUES ($1, 'parking', ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography, 'allowed', 'x',
                now())
        "#,
        Uuid::now_v7(),
        seeds[1].lat,
        seeds[1].lon,
    )
    .execute(pool)
    .await
    .unwrap();
    seeds
}

/// What a tile says of a place: the properties the map's filters read.
fn tile_props(s: &Seed, dots: bool) -> BTreeMap<String, Value> {
    let mut p = BTreeMap::new();
    p.insert("kind".into(), json!(s.kind.code()));
    p.insert("night".into(), json!(s.night.code()));
    let mask = Service::mask(&s.services);
    p.insert(
        "s".into(),
        json!(if dots {
            mask & u32::try_from(place_tiles::DOTS_SERVICES).unwrap()
        } else {
            mask
        }),
    );
    if let Some(price) = s.price {
        p.insert("price".into(), json!(u8::from(price > 0.0)));
    }
    if let Some(h) = s.height_m {
        p.insert(
            "h".into(),
            json!(format!("{:.0}", h * 100.0).parse::<u64>().unwrap()),
        );
    }
    p
}

async fn version(app: &axum::Router) -> (i64, Value) {
    let (status, headers, body) = get(app, "/places/tiles.json", &[]).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(headers[header::CACHE_CONTROL], "public, max-age=60");
    let tj: Value = serde_json::from_slice(&body).unwrap();
    let url = tj["tiles"][0].as_str().unwrap();
    let rest = url.strip_prefix("https://api.test/places/").unwrap();
    assert!(rest.ends_with("/{z}/{x}/{y}.mvt"), "{url}");
    (rest.split('/').next().unwrap().parse().unwrap(), tj)
}

fn layer<'a>(layers: &'a BTreeMap<String, (u64, Vec<Feature>)>, name: &str) -> &'a [Feature] {
    &layers
        .get(name)
        .unwrap_or_else(|| panic!("no layer {name}: {:?}", layers.keys()))
        .1
}

#[sqlx::test(migrations = "../../migrations")]
async fn pins_carry_every_place_with_what_the_filters_read(pool: PgPool) {
    let seeds = seeded(&pool).await;
    let app = app(&pool);
    let (v, tj) = version(&app).await;
    assert_eq!(tj["tilejson"], "3.0.0");
    assert_eq!(tj["minzoom"], place_tiles::DOTS_MIN_ZOOM);
    assert_eq!(tj["maxzoom"], 14);
    assert!(
        tj["attribution"]
            .as_str()
            .unwrap()
            .contains("OpenStreetMap contributors"),
        "ODbL: the tiles credit OpenStreetMap"
    );
    let ids: Vec<&str> = tj["vector_layers"]
        .as_array()
        .unwrap()
        .iter()
        .map(|l| l["id"].as_str().unwrap())
        .collect();
    assert_eq!(ids, ["places", "place_dots"]);
    assert_eq!(tj["vector_layers"][0]["minzoom"], place_tiles::PIN_ZOOM);

    let (x, y) = home();
    let (status, headers, body) = get(&app, &format!("/places/{v}/12/{x}/{y}.mvt"), &[]).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        headers[header::CONTENT_TYPE],
        "application/vnd.mapbox-vector-tile"
    );
    assert_eq!(
        headers[header::CACHE_CONTROL],
        "public, max-age=31536000, immutable"
    );
    let layers = decode(&body);
    assert!(
        !layers.contains_key("place_dots"),
        "pins only from the pin zoom"
    );
    let pins = layer(&layers, "places");
    assert_eq!(
        pins.len(),
        seeds.len(),
        "every live place once, the deleted one never"
    );
    for s in &seeds {
        let pin = pins
            .iter()
            .find(|f| f.props["id"] == s.id.to_string())
            .unwrap_or_else(|| panic!("{} missing", s.id));
        let mut expected = tile_props(s, false);
        expected.insert("id".into(), json!(s.id.to_string()));
        if let Some(n) = &s.name {
            expected.insert("name".into(), json!(n));
        }
        assert_eq!(pin.props, expected, "what the tile says of {}", s.id);
    }

    // At the pin zoom, no names: they would add 60% to the tile.
    let (x10, y10) = tile_of(45.9, 6.12, place_tiles::PIN_ZOOM.try_into().unwrap());
    let (_, _, body) = get(
        &app,
        &format!("/places/{v}/{}/{x10}/{y10}.mvt", place_tiles::PIN_ZOOM),
        &[],
    )
    .await;
    let layers = decode(&body);
    let pins = layer(&layers, "places");
    assert_eq!(pins.len(), seeds.len());
    assert!(pins.iter().all(|f| !f.props.contains_key("name")));
    assert!(pins.iter().all(|f| f.props.contains_key("id")));
}

#[sqlx::test(migrations = "../../migrations")]
async fn pins_carry_their_town_from_the_zoom_of_the_names(pool: PgPool) {
    // The app's list reads the pins from that zoom on: a place without a
    // name is titled by its kind and its town.
    let (lat, lon) = (45.9, 6.12);
    let cases = [
        (Uuid::now_v7(), Some("Annecy"), None, Some("Annecy")),
        (
            Uuid::now_v7(),
            None,
            Some("Talloires-Montmin"),
            Some("Talloires-Montmin"),
        ),
        (
            Uuid::now_v7(),
            Some("Sevrier"),
            Some("Annecy"),
            Some("Sevrier"),
        ),
        (Uuid::now_v7(), None, None, None),
    ];
    for (i, (id, city, municipality, _)) in cases.iter().enumerate() {
        let offset = f64::from(u32::try_from(i).unwrap()) * 0.001;
        sqlx::query!(
            r#"
            INSERT INTO places (id, kind, geom, overnight, city, municipality, content_hash)
            VALUES ($1, 'parking', ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography, 'allowed',
                    $4, $5, 'x')
            "#,
            id,
            lat + offset,
            lon,
            *city,
            *municipality,
        )
        .execute(&pool)
        .await
        .unwrap();
    }
    let app = app(&pool);
    let (v, tj) = version(&app).await;
    assert!(
        tj["vector_layers"][0]["fields"]["city"].is_string(),
        "the TileJSON says what the field holds"
    );
    let z = u32::try_from(place_tiles::NAME_MIN_ZOOM).unwrap();
    let (x, y) = tile_of(lat, lon, z);
    let (_, _, body) = get(&app, &format!("/places/{v}/{z}/{x}/{y}.mvt"), &[]).await;
    let layers = decode(&body);
    let pins = layer(&layers, "places");
    for (id, _, _, town) in &cases {
        let pin = pins
            .iter()
            .find(|f| f.props["id"] == id.to_string())
            .unwrap_or_else(|| panic!("{id} missing"));
        assert_eq!(
            pin.props.get("city").and_then(Value::as_str),
            *town,
            "the address's town first, else the commune's"
        );
    }
    let below = u32::try_from(place_tiles::NAME_MIN_ZOOM - 1).unwrap();
    let (x, y) = tile_of(lat, lon, below);
    let (_, _, body) = get(&app, &format!("/places/{v}/{below}/{x}/{y}.mvt"), &[]).await;
    let layers = decode(&body);
    assert!(
        layer(&layers, "places")
            .iter()
            .all(|f| !f.props.contains_key("city")),
        "below the zoom of the names, no town either"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn dots_keep_a_place_per_pixel_and_set_of_properties(pool: PgPool) {
    let seeds = seeded(&pool).await;
    let app = app(&pool);
    let (v, _) = version(&app).await;
    for z in place_tiles::DOTS_MIN_ZOOM..place_tiles::PIN_ZOOM {
        let zu = u32::try_from(z).unwrap();
        let (x, y) = tile_of(45.9, 6.12, zu);
        let (status, _, body) = get(&app, &format!("/places/{v}/{z}/{x}/{y}.mvt"), &[]).await;
        assert_eq!(status, StatusCode::OK, "zoom {z}");
        let layers = decode(&body);
        assert!(!layers.contains_key("places"), "no pins below the pin zoom");
        let (extent, dots) = &layers["place_dots"];
        assert_eq!(*extent, 512, "one unit per pixel of a 512 px tile");
        let sets: BTreeSet<String> = seeds
            .iter()
            .map(|s| serde_json::to_string(&tile_props(s, true)).unwrap())
            .collect();
        let seen: BTreeSet<String> = dots
            .iter()
            .map(|f| serde_json::to_string(&f.props).unwrap())
            .collect();
        assert_eq!(
            seen, sets,
            "zoom {z}: one feature per set of properties, no id, no name, services 0 to 8"
        );
        for f in dots {
            assert!(
                f.points
                    .iter()
                    .all(|p| (0..512).contains(&p.0) && (0..512).contains(&p.1)),
                "inside the tile"
            );
            let unique: BTreeSet<_> = f.points.iter().collect();
            assert_eq!(unique.len(), f.points.len(), "a pixel once per set");
        }
        let points: usize = dots.iter().map(|f| f.points.len()).sum();
        assert!(
            points < seeds.len(),
            "zoom {z}: the twin with the same properties is one dot"
        );
    }
    // The two places at one position with other properties are two dots of
    // two features, at the same pixel.
    let twin_kind = seeds.last().unwrap();
    let (x, y) = tile_of(45.9, 6.12, 9);
    let (_, _, body) = get(&app, &format!("/places/{v}/9/{x}/{y}.mvt"), &[]).await;
    let layers = decode(&body);
    let a = layer(&layers, "place_dots")
        .iter()
        .find(|f| f.props == tile_props(&seeds[0], true))
        .unwrap();
    let b = layer(&layers, "place_dots")
        .iter()
        .find(|f| f.props == tile_props(twin_kind, true))
        .unwrap();
    assert!(
        a.points.iter().any(|p| b.points.contains(p)),
        "a filter on the kind keeps either one: both stay"
    );
}

/// The map's filter as the app writes it on the tiles' properties.
type TileFilter = fn(&BTreeMap<String, Value>) -> bool;

fn mask(services: &[Service]) -> u64 {
    u64::from(Service::mask(services))
}

fn s_of(p: &BTreeMap<String, Value>) -> u64 {
    p["s"].as_u64().unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_list_and_the_tiles_keep_the_same_places_for_each_filter(pool: PgPool) {
    seeded(&pool).await;
    let app = app(&pool);
    let (v, _) = version(&app).await;
    let (x, y) = home();
    let (_, _, body) = get(&app, &format!("/places/{v}/12/{x}/{y}.mvt"), &[]).await;
    let layers = decode(&body);
    let pins = layer(&layers, "places");
    let (north, west) = corner(12, x, y);
    let (south, east) = corner(12, x + 1, y + 1);
    let bbox = json!({"south": south, "west": west, "north": north, "east": east});

    let cases: Vec<(Value, TileFilter)> = vec![
        (json!({}), |_| true),
        (json!({"overnight": ["ALLOWED", "TOLERATED"]}), |p| {
            ["allowed", "tolerated"].contains(&p["night"].as_str().unwrap())
        }),
        (json!({"overnight": ["UNKNOWN"]}), |p| {
            p["night"] == "unknown"
        }),
        (
            json!({"serviceGroups": [["GREY_WATER", "BLACK_WATER"]]}),
            |p| s_of(p) & mask(&[Service::GreyWater, Service::BlackWater]) != 0,
        ),
        (
            json!({"serviceGroups": [["DRINKING_WATER"], ["ELECTRICITY"]]}),
            |p| {
                s_of(p) & mask(&[Service::DrinkingWater]) != 0
                    && s_of(p) & mask(&[Service::Electricity]) != 0
            },
        ),
        (json!({"services": ["TOILETS", "SHOWERS"]}), |p| {
            let m = mask(&[Service::Toilets, Service::Showers]);
            s_of(p) & m == m
        }),
        (json!({"freeOnly": true}), |p| {
            p.get("price") == Some(&json!(0))
        }),
        (json!({"vehicleHeightM": 2.9}), |p| {
            p.get("h").is_none_or(|h| h.as_f64().unwrap() >= 290.0)
        }),
        (json!({"kinds": ["CAMPSITE", "MOTORHOME_AREA"]}), |p| {
            ["campsite", "motorhome_area"].contains(&p["kind"].as_str().unwrap())
        }),
        (
            json!({"overnightOk": true, "freeOnly": true,
                   "serviceGroups": [["GREY_WATER", "BLACK_WATER"]]}),
            |p| {
                ["allowed", "tolerated"].contains(&p["night"].as_str().unwrap())
                    && p.get("price") == Some(&json!(0))
                    && s_of(p) & mask(&[Service::GreyWater, Service::BlackWater]) != 0
            },
        ),
    ];
    let mut non_empty = 0;
    for (filter, on_tile) in cases {
        let body = gql(
            &app,
            "query($b: BBoxInput!, $f: PlaceFilter) {
               places(bbox: $b, filter: $f, first: 500) { totalCount nodes { id } } }",
            json!({"b": bbox, "f": filter}),
        )
        .await;
        let listed: BTreeSet<String> = ok(&body)["places"]["nodes"]
            .as_array()
            .unwrap()
            .iter()
            .map(|n| n["id"].as_str().unwrap().to_owned())
            .collect();
        let drawn: BTreeSet<String> = pins
            .iter()
            .filter(|f| on_tile(&f.props))
            .map(|f| f.props["id"].as_str().unwrap().to_owned())
            .collect();
        assert_eq!(
            listed, drawn,
            "{filter}: the list and the map must show the same places"
        );
        assert_eq!(ok(&body)["places"]["totalCount"], listed.len(), "{filter}");
        if !listed.is_empty() {
            non_empty += 1;
        }
    }
    assert!(
        non_empty >= 8,
        "the seeds exercise the filters: {non_empty} cases kept a place"
    );
}

const NEAR: &str = "query($b: BBoxInput!, $n: LatLonInput, $after: String, $first: Int) {
  places(bbox: $b, near: $n, first: $first, after: $after) {
    totalCount hasNextPage endCursor nodes { id lat lon } } }";

/// Every page of `places(near:)` with pages of `first`.
async fn all_pages(
    app: &axum::Router,
    bbox: &Value,
    near: Value,
    first: i32,
) -> (Vec<(String, f64, f64)>, i64) {
    let mut out = Vec::new();
    let mut after = Value::Null;
    loop {
        let body = gql(
            app,
            NEAR,
            json!({"b": bbox, "n": near, "after": after, "first": first}),
        )
        .await;
        let page = &ok(&body)["places"];
        let total = page["totalCount"].as_i64().unwrap();
        for n in page["nodes"].as_array().unwrap() {
            out.push((
                n["id"].as_str().unwrap().to_owned(),
                n["lat"].as_f64().unwrap(),
                n["lon"].as_f64().unwrap(),
            ));
        }
        if !page["hasNextPage"].as_bool().unwrap() {
            return (out, total);
        }
        after = page["endCursor"].clone();
        assert!(out.len() < 1_000, "pages never end");
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_nearest_places_come_first_page_after_page(pool: PgPool) {
    let seeds = seeded(&pool).await;
    let app = app(&pool);
    let europe = json!({"south": 27.0, "west": -32.0, "north": 81.0, "east": 35.0});
    let anchor = json!({"lat": 45.9012, "lon": 6.1288});
    let (one_by_one, total) = all_pages(&app, &europe, anchor.clone(), 1).await;
    assert_eq!(
        usize::try_from(total).unwrap(),
        seeds.len(),
        "with near, a viewport of all of Europe is served and counted"
    );
    let ids: BTreeSet<&String> = one_by_one.iter().map(|p| &p.0).collect();
    assert_eq!(
        ids.len(),
        seeds.len(),
        "every place once, the twins at one position included, across pages of one"
    );
    let at = Position::new(45.90, 6.13).unwrap();
    let distances: Vec<f64> = one_by_one
        .iter()
        .map(|p| at.distance_m(Position::new(p.1, p.2).unwrap()))
        .collect();
    assert!(
        distances.windows(2).all(|w| w[0] <= w[1] + 1.0),
        "nearest first from the anchor rounded to 0.01 degree: {distances:?}"
    );
    let (by_seven, _) = all_pages(&app, &europe, anchor, 7).await;
    assert_eq!(
        by_seven, one_by_one,
        "the cursor keeps the order whatever the page size"
    );
    let (elsewhere, _) = all_pages(&app, &europe, json!({"lat": 45.8951, "lon": 6.1349}), 7).await;
    assert_eq!(
        elsewhere, one_by_one,
        "two anchors in the same 0.01 degree cell give the same list: nothing finer is used"
    );

    // Without near, the viewport stays bounded.
    let body = gql(&app, NEAR, json!({"b": europe, "n": null})).await;
    assert_eq!(code(&body), "INVALID_INPUT");
    let body = gql(
        &app,
        NEAR,
        json!({"b": europe, "n": {"lat": 91.0, "lon": 0.0}}),
    )
    .await;
    assert_eq!(code(&body), "INVALID_INPUT");
    let body = gql(
        &app,
        NEAR,
        json!({"b": europe, "n": {"lat": 45.9, "lon": 6.1}, "after": "p1.not-a-cursor"}),
    )
    .await;
    assert_eq!(
        code(&body),
        "INVALID_INPUT",
        "an id cursor does not continue a list by distance"
    );
    let body = gql(
        &app,
        "query($b: BBoxInput!) { places(bbox: $b, filter: {serviceGroups: [[]]}) { totalCount } }",
        json!({"b": europe}),
    )
    .await;
    assert_eq!(
        code(&body),
        "INVALID_INPUT",
        "an empty group would keep nothing"
    );
    let body = gql(
        &app,
        "query($b: BBoxInput!) { places(bbox: $b, near: {lat: 45.9, lon: 6.1}, filter: {overnight: []}) { totalCount } }",
        json!({"b": europe}),
    )
    .await;
    assert_eq!(
        code(&body),
        "INVALID_INPUT",
        "an empty list of statuses would keep nothing"
    );
    let id = seeds[0].id;
    let nan = f64::NAN.to_bits();
    let negative = (-1.0_f64).to_bits();
    for broken in [
        format!("n1.zz.{id}"),
        format!("n1.{nan:016x}.{id}"),
        format!("n1.{negative:016x}.{id}"),
        format!("n1.{:016x}.not-a-uuid", 10.0_f64.to_bits()),
        format!("n1.{:016x}", 10.0_f64.to_bits()),
        format!("n1..{id}"),
    ] {
        let body = gql(
            &app,
            NEAR,
            json!({"b": europe, "n": {"lat": 45.9, "lon": 6.1}, "after": broken}),
        )
        .await;
        assert_eq!(code(&body), "INVALID_INPUT", "{broken}");
    }
}

/// An app whose tile builds are refused by the client's budget (a request
/// costs 1 000, a build 2 000 more, the burst is 2 500): a tile it gets was
/// built by the API ahead of any client.
fn app_building_ahead(pool: &PgPool, concurrency: usize) -> axum::Router {
    let defaults = ApiConfig::default();
    let config = ApiConfig {
        tiles: lunaway_api::config::TilesConfig {
            public_url: "https://api.test".into(),
            warm: true,
            concurrency,
            ..defaults.tiles.clone()
        },
        limits: lunaway_api::config::Limits {
            rate_burst: 2_500,
            rate_per_second: 1_500,
            ..defaults.limits
        },
        ..defaults
    };
    lunaway_api::router(ApiState::new(pool.clone(), config))
}

/// Asks `uri` once a second until it answers 200, up to `tries` times.
async fn ready(app: &axum::Router, uri: &str, tries: u32) -> bool {
    for _ in 0..tries {
        let (status, _, _) = get(app, uri, &[]).await;
        if status == StatusCode::OK {
            return true;
        }
        assert_eq!(status, StatusCode::TOO_MANY_REQUESTS, "{uri}");
        tokio::time::sleep(std::time::Duration::from_millis(1_100)).await;
    }
    false
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_dots_of_a_new_version_are_built_before_anyone_asks(pool: PgPool) {
    seeded(&pool).await;
    let app = app_building_ahead(&pool, 2);
    let (v, _) = version(&app).await;
    let (x12, y12) = home();
    let (status, _, _) = get(&app, &format!("/places/{v}/12/{x12}/{y12}.mvt"), &[]).await;
    assert_eq!(
        status,
        StatusCode::TOO_MANY_REQUESTS,
        "a pin tile is not built ahead, and this client cannot build one"
    );
    for z in place_tiles::DOTS_MIN_ZOOM..place_tiles::PIN_ZOOM {
        let (x, y) = tile_of(45.9, 6.12, u32::try_from(z).unwrap());
        assert!(
            ready(&app, &format!("/places/{v}/{z}/{x}/{y}.mvt"), 20).await,
            "zoom {z}: built ahead once the TileJSON named version {v}"
        );
    }
    // A new version: the first request naming it starts the building again.
    let next = place_tiles::publish_layer_now(&pool).await.unwrap();
    tokio::time::sleep(std::time::Duration::from_millis(250)).await;
    let (x, y) = tile_of(45.9, 6.12, 9);
    assert!(
        ready(&app, &format!("/places/{next}/9/{x}/{y}.mvt"), 20).await,
        "the tiles of version {next} are built ahead too"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn with_one_builder_nothing_is_built_ahead(pool: PgPool) {
    seeded(&pool).await;
    let app = app_building_ahead(&pool, 1);
    let (v, _) = version(&app).await;
    let (x, y) = tile_of(45.9, 6.12, 9);
    assert!(
        !ready(&app, &format!("/places/{v}/9/{x}/{y}.mvt"), 4).await,
        "the only builder stays the clients'"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn tiles_follow_the_version_and_cost_nothing_twice(pool: PgPool) {
    let seeds = seeded(&pool).await;
    let app = app(&pool);
    let (v, _) = version(&app).await;
    let (x, y) = home();
    let uri = format!("/places/{v}/12/{x}/{y}.mvt");
    let (_, headers, _) = get(&app, &uri, &[]).await;
    let etag = headers[header::ETAG].to_str().unwrap().to_owned();
    let (status, _, body) = get(&app, &uri, &[("if-none-match", &etag)]).await;
    assert_eq!(status, StatusCode::NOT_MODIFIED);
    assert!(body.is_empty());
    let (status, _, _) = get(&app, &format!("/places/{v}/1/1/0.mvt"), &[]).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "below the dots");
    let (status, _, _) = get(&app, &format!("/places/{v}/15/1/1.mvt"), &[]).await;
    assert_eq!(
        status,
        StatusCode::NOT_FOUND,
        "beyond zoom 14 the map overzooms"
    );
    let (status, _, _) = get(&app, &format!("/places/{v}/14/1/1.mvt"), &[]).await;
    assert_eq!(status, StatusCode::NO_CONTENT, "outside the bounds");
    let (status, _, _) = get(&app, &format!("/places/{v}/14/8000/5000.mvt"), &[]).await;
    assert_eq!(status, StatusCode::NO_CONTENT, "an empty square of land");

    // A takedown's tombstone, then a new version: the place leaves the
    // tiles of the new version, an old version gets today's data briefly.
    sqlx::query!(
        "UPDATE places SET deleted_at = now(), updated_seq = nextval('place_change_seq') WHERE id = $1",
        seeds[3].id
    )
    .execute(&pool)
    .await
    .unwrap();
    let next = place_tiles::publish_layer_now(&pool).await.unwrap();
    // The API reads the version again when a client names a newer one, at
    // most every 200 ms (`tiles::VERSION_RECHECK`).
    tokio::time::sleep(std::time::Duration::from_millis(250)).await;
    let (status, headers, body) = get(&app, &format!("/places/{next}/12/{x}/{y}.mvt"), &[]).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        headers[header::CACHE_CONTROL],
        "public, max-age=31536000, immutable"
    );
    let layers = decode(&body);
    assert!(
        layer(&layers, "places")
            .iter()
            .all(|f| f.props["id"] != seeds[3].id.to_string()),
        "the place taken down is in no tile of the new version"
    );
    let (status, headers, body) = get(&app, &uri, &[]).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        headers[header::CACHE_CONTROL],
        "public, max-age=300",
        "an old version gets today's data, briefly cached"
    );
    assert_eq!(layer(&decode(&body), "places").len(), seeds.len() - 1);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_tapped_place_is_fetched_by_its_persisted_query(pool: PgPool) {
    let seeds = seeded(&pool).await;
    let app = app(&pool);
    let document = "query Place($id: UUID!) { place(id: $id) { id name kind } }";
    let hash = lunaway_api::persisted::hash(document);
    let by_hash = json!({
        "operationName": "Place",
        "variables": {"id": seeds[0].id},
        "extensions": {"persistedQuery": {"version": 1, "sha256Hash": hash}},
    });
    assert_eq!(
        code(&post(&app, by_hash.clone()).await),
        "PERSISTED_QUERY_NOT_FOUND"
    );
    let mut with_document = by_hash.clone();
    with_document["query"] = document.into();
    let first = post(&app, with_document).await;
    assert_eq!(ok(&first)["place"]["id"], seeds[0].id.to_string());
    let again = post(&app, by_hash).await;
    assert_eq!(ok(&again), ok(&first), "then by its hash alone");
}
