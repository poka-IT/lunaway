//! The points of interest over HTTP, as the app sees them: the map tiles
//! (decoded here, protobuf by hand), "around this place", one point with
//! what the fuel feed, La Poste and FINESS say of it, the search, and the
//! offline download; on a database filled by the real adapters from
//! recorded payloads (OpenStreetMap elements, the fuel export, La Poste's
//! calendar, FINESS).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::collections::{BTreeMap, HashSet};

use axum::{
    body::Body,
    http::{Request, StatusCode, header},
};
use chrono::{TimeZone, Utc};
use http_body_util::BodyExt;
use lunaway_api::{ApiConfig, ApiState};
use lunaway_db::{PgPool, pois::NewJoin};
use lunaway_domain::{SourceId, poi::decode_hours};
use lunaway_ingest::{
    finess, fuel, laposte, poi_osm,
    store::{store_joins, store_pois},
};
use serde_json::{Value, json};
use tower::ServiceExt;

const POIS: &[u8] = include_bytes!("../../lunaway-ingest/tests/fixtures/osm_poi_sample.json");
const FUEL: &[u8] = include_bytes!("../../lunaway-ingest/tests/fixtures/fuel_export_sample.json");
const LAPOSTE: &[u8] =
    include_bytes!("../../lunaway-ingest/tests/fixtures/laposte_ouvertur_sample.json");
const FINESS: &[u8] =
    include_bytes!("../../lunaway-ingest/tests/fixtures/finess_structures_sample.json");

/// Noon of the day of La Poste's sample (its calendar runs from 6 to 20
/// October), the same date in France.
fn now() -> chrono::DateTime<Utc> {
    Utc.with_ymd_and_hms(2026, 10, 6, 12, 0, 0).unwrap()
}

/// The post office of Ambérieu-en-Bugey (La Poste `00001A`).
const AMBERIEU: (f64, f64) = (45.9597, 5.3582);

fn app(pool: &PgPool) -> axum::Router {
    let config = ApiConfig {
        tiles: lunaway_api::config::TilesConfig {
            public_url: "https://api.test".into(),
            ..ApiConfig::default().tiles
        },
        ..ApiConfig::default()
    };
    lunaway_api::router(ApiState::new(pool.clone(), config))
}

async fn seeded(pool: &PgPool) {
    let at = Utc.with_ymd_and_hms(2026, 10, 5, 22, 0, 0).unwrap();
    let parsed = poi_osm::parse(POIS, at).unwrap();
    assert!(parsed.skipped.is_empty(), "{:?}", parsed.skipped);
    store_pois(pool, &SourceId::OSM, &parsed.points)
        .await
        .unwrap();

    let stations = fuel::parse(FUEL).unwrap();
    let data: Vec<Value> = stations
        .stations
        .iter()
        .map(|s| serde_json::to_value(&s.station).unwrap())
        .collect();
    let rows: Vec<NewJoin<'_>> = stations
        .stations
        .iter()
        .zip(&data)
        .map(|(s, d)| NewJoin {
            key: &s.key,
            data: d,
            raw: &s.raw,
            fetched_at: at,
        })
        .collect();
    store_joins(pool, &SourceId::FUEL_PRICES, &rows)
        .await
        .unwrap();

    let sites = laposte::build(laposte::parse_page(LAPOSTE).unwrap().lines);
    let data: Vec<Value> = sites
        .sites
        .iter()
        .map(|s| serde_json::to_value(&s.days).unwrap())
        .collect();
    let rows: Vec<NewJoin<'_>> = sites
        .sites
        .iter()
        .zip(&data)
        .map(|(s, d)| NewJoin {
            key: &s.key,
            data: d,
            raw: &s.raw,
            fetched_at: at,
        })
        .collect();
    store_joins(pool, &SourceId::LAPOSTE, &rows).await.unwrap();

    let wanted: HashSet<String> = lunaway_db::pois::join_keys(pool, &SourceId::FINESS)
        .await
        .unwrap()
        .into_iter()
        .collect();
    let health = finess::parse(FINESS, &wanted).unwrap();
    let data: Vec<Value> = health
        .establishments
        .iter()
        .map(|e| serde_json::to_value(&e.establishment).unwrap())
        .collect();
    let rows: Vec<NewJoin<'_>> = health
        .establishments
        .iter()
        .zip(&data)
        .map(|(e, d)| NewJoin {
            key: &e.key,
            data: d,
            raw: &e.raw,
            fetched_at: at,
        })
        .collect();
    store_joins(pool, &SourceId::FINESS, &rows).await.unwrap();

    lunaway_conflate::pois::refresh_hours(pool, now())
        .await
        .unwrap();
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

async fn gql(app: &axum::Router, query: &str, variables: Value) -> Value {
    let request = Request::post("/graphql")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({"query": query, "variables": variables}).to_string(),
        ))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap()
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

/// The tile `z/x/y` that holds `(lat, lon)`.
fn tile_of(lat: f64, lon: f64, z: u32) -> (u32, u32) {
    let n = f64::from(1u32 << z);
    let x = ((lon + 180.0) / 360.0 * n).floor();
    let r = lat.to_radians();
    let y = ((1.0 - (r.tan() + 1.0 / r.cos()).ln() / std::f64::consts::PI) / 2.0 * n).floor();
    (x as u32, y as u32)
}

// A Mapbox Vector Tile reader, enough for the test: layers, their keys and
// values, and each feature's tags and point.

fn varint(b: &[u8], i: &mut usize) -> u64 {
    let mut v = 0u64;
    let mut shift = 0;
    loop {
        let byte = b[*i];
        *i += 1;
        v |= u64::from(byte & 0x7f) << shift;
        if byte & 0x80 == 0 {
            return v;
        }
        shift += 7;
    }
}

/// The fields of a message: (field number, wire type, varint or bytes).
fn fields(b: &[u8]) -> Vec<(u64, u64, u64, &[u8])> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < b.len() {
        let key = varint(b, &mut i);
        let (field, wire) = (key >> 3, key & 7);
        match wire {
            0 => out.push((field, wire, varint(b, &mut i), &b[0..0])),
            1 => {
                out.push((
                    field,
                    wire,
                    u64::from_le_bytes(b[i..i + 8].try_into().unwrap()),
                    &b[0..0],
                ));
                i += 8;
            }
            2 => {
                let len = usize::try_from(varint(b, &mut i)).unwrap();
                out.push((field, wire, 0, &b[i..i + len]));
                i += len;
            }
            5 => {
                out.push((
                    field,
                    wire,
                    u64::from(u32::from_le_bytes(b[i..i + 4].try_into().unwrap())),
                    &b[0..0],
                ));
                i += 4;
            }
            w => panic!("wire type {w}"),
        }
    }
    out
}

fn packed(b: &[u8]) -> Vec<u64> {
    let mut i = 0;
    let mut out = Vec::new();
    while i < b.len() {
        out.push(varint(b, &mut i));
    }
    out
}

fn unzigzag(n: u64) -> i64 {
    ((n >> 1) as i64) ^ -((n & 1) as i64)
}

/// A decoded feature: its properties and its point in tile units.
#[derive(Debug)]
struct Feature {
    props: BTreeMap<String, Value>,
    point: (i64, i64),
}

/// The layers of a tile, by name.
fn decode(tile: &[u8]) -> BTreeMap<String, (u64, Vec<Feature>)> {
    let mut layers = BTreeMap::new();
    for (field, _, _, layer) in fields(tile) {
        assert_eq!(field, 3, "a tile holds layers only");
        let lf = fields(layer);
        let name = lf
            .iter()
            .find(|f| f.0 == 1)
            .map(|f| String::from_utf8(f.3.to_vec()).unwrap())
            .unwrap();
        let extent = lf.iter().find(|f| f.0 == 5).map_or(4096, |f| f.2);
        let keys: Vec<String> = lf
            .iter()
            .filter(|f| f.0 == 3)
            .map(|f| String::from_utf8(f.3.to_vec()).unwrap())
            .collect();
        let values: Vec<Value> = lf
            .iter()
            .filter(|f| f.0 == 4)
            .map(|f| {
                let (vf, _, n, bytes) = fields(f.3)[0];
                match vf {
                    1 => Value::String(String::from_utf8(bytes.to_vec()).unwrap()),
                    2 => json!(f32::from_bits(u32::try_from(n).unwrap())),
                    3 => json!(f64::from_bits(n)),
                    4 | 5 => json!(n),
                    6 => json!(unzigzag(n)),
                    7 => Value::Bool(n != 0),
                    other => panic!("value field {other}"),
                }
            })
            .collect();
        let features = lf
            .iter()
            .filter(|f| f.0 == 2)
            .map(|f| {
                let ff = fields(f.3);
                let tags = ff
                    .iter()
                    .find(|x| x.0 == 2)
                    .map(|x| packed(x.3))
                    .unwrap_or_default();
                let geometry = ff.iter().find(|x| x.0 == 4).map(|x| packed(x.3)).unwrap();
                assert_eq!(geometry[0], 9, "one MoveTo of one point");
                let props = tags
                    .chunks(2)
                    .map(|kv| {
                        (
                            keys[usize::try_from(kv[0]).unwrap()].clone(),
                            values[usize::try_from(kv[1]).unwrap()].clone(),
                        )
                    })
                    .collect();
                Feature {
                    props,
                    point: (unzigzag(geometry[1]), unzigzag(geometry[2])),
                }
            })
            .collect();
        layers.insert(name, (extent, features));
    }
    layers
}

async fn version(app: &axum::Router) -> i64 {
    let (status, _, body) = get(app, "/poi/tiles.json", &[]).await;
    assert_eq!(status, StatusCode::OK);
    let tj: Value = serde_json::from_slice(&body).unwrap();
    let url = tj["tiles"][0].as_str().unwrap();
    let rest = url.strip_prefix("https://api.test/poi/").unwrap();
    assert!(rest.ends_with("/{z}/{x}/{y}.mvt"), "{url}");
    rest.split('/').next().unwrap().parse().unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_tiles_carry_every_point_with_its_hours_and_flags(pool: PgPool) {
    seeded(&pool).await;
    let app = app(&pool);
    let v = version(&app).await;

    let (x, y) = tile_of(AMBERIEU.0, AMBERIEU.1, 14);
    let uri = format!("/poi/{v}/14/{x}/{y}.mvt");
    let (status, headers, body) = get(&app, &uri, &[]).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        headers[header::CONTENT_TYPE],
        "application/vnd.mapbox-vector-tile"
    );
    assert_eq!(
        headers[header::CACHE_CONTROL],
        "public, max-age=31536000, immutable",
        "a tile of the current version never changes"
    );
    let layers = decode(&body);
    let (extent, features) = &layers["pois"];
    assert_eq!(*extent, 4096);
    assert!(
        features.len() >= 10,
        "the centre of Ambérieu: {}",
        features.len()
    );
    for f in features {
        for key in ["id", "category", "kind"] {
            assert!(f.props.contains_key(key), "{key} missing: {f:?}");
        }
        assert!(
            (-64..4096 + 64).contains(&f.point.0) && (-64..4096 + 64).contains(&f.point.1),
            "{f:?}"
        );
    }
    let post = features
        .iter()
        .find(|f| f.props["kind"] == "post_office")
        .expect("the post office");
    assert_eq!(post.props["category"], "services");
    assert_eq!(post.props["name"], "Ambérieu en Bugey");
    let hours = decode_hours(post.props["hours"].as_str().unwrap()).unwrap();
    assert_eq!(
        hours[0].start,
        Utc.with_ymd_and_hms(2026, 10, 6, 7, 0, 0).unwrap(),
        "La Poste's 09:00 in Ambérieu, in UTC: the calendar wins over the tag"
    );
    assert_eq!(
        hours[1].start,
        Utc.with_ymd_and_hms(2026, 10, 6, 12, 0, 0).unwrap(),
        "the afternoon opening at 14:00"
    );
    let until = post.props["hoursUntil"].as_u64().unwrap();
    assert_eq!(
        i64::try_from(until).unwrap(),
        Utc.with_ymd_and_hms(2026, 10, 19, 22, 0, 0)
            .unwrap()
            .timestamp()
            / 60,
        "fourteen days from local midnight of the 6th"
    );
    assert!(
        features.iter().any(|f| f.props["kind"] == "pharmacy"
            && f.props["name"] == "Pharmacie du Champ de Mars"
            && !f.props.contains_key("maybeClosed")),
        "an open pharmacy carries no flag"
    );

    // The pharmacy FINESS lists as closed (010003887).
    let (x, y) = tile_of(45.9767, 5.6006, 14);
    let (_, _, body) = get(&app, &format!("/poi/{v}/14/{x}/{y}.mvt"), &[]).await;
    let closed = decode(&body);
    assert!(
        closed["pois"]
            .1
            .iter()
            .any(|f| f.props["name"] == "Pharmacie Vallée" && f.props["maybeClosed"] == true),
        "{:?}",
        closed["pois"].1
    );

    // LPG: the Intermarché of 40500002 sells it; the one of 34150003
    // stopped for good, whatever OSM says.
    for (lat, lon, key, lpg) in [
        (43.7739, -0.5673, "40500002", true),
        (43.6504, 3.5452, "34150003", false),
    ] {
        let (x, y) = tile_of(lat, lon, 14);
        let (_, _, body) = get(&app, &format!("/poi/{v}/14/{x}/{y}.mvt"), &[]).await;
        let layers = decode(&body);
        let station = layers["pois"]
            .1
            .iter()
            .find(|f| f.props["kind"] == "fuel_station")
            .unwrap_or_else(|| panic!("station {key}"));
        assert_eq!(
            station.props.get("lpg") == Some(&Value::Bool(true)),
            lpg,
            "{key}"
        );
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn cluster_tiles_count_every_point_and_caching_follows_the_version(pool: PgPool) {
    seeded(&pool).await;
    let app = app(&pool);
    let v = version(&app).await;
    let (x, y) = tile_of(AMBERIEU.0, AMBERIEU.1, 10);
    let (status, _, body) = get(&app, &format!("/poi/{v}/10/{x}/{y}.mvt"), &[]).await;
    assert_eq!(status, StatusCode::OK);
    let layers = decode(&body);
    assert!(
        !layers.contains_key("pois"),
        "below the point zoom, clusters only"
    );
    let counted: u64 = layers["poi_clusters"]
        .1
        .iter()
        .map(|f| f.props["count"].as_u64().unwrap())
        .sum();
    let expected = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM pois
           WHERE deleted_at IS NULL
             AND geom::geometry && ST_Transform(ST_TileEnvelope(10, $1, $2), 4326)"#,
        i32::try_from(x).unwrap(),
        i32::try_from(y).unwrap(),
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        counted,
        u64::try_from(expected).unwrap(),
        "clusters count every point of their tile"
    );
    assert!(
        layers["poi_clusters"]
            .1
            .iter()
            .all(|f| f.props["category"].as_str().is_some()),
        "a cluster names its category, for the chips"
    );

    // Caching: an ETag, a 304, and a short life under an old version.
    let uri = format!("/poi/{v}/10/{x}/{y}.mvt");
    let (_, headers, _) = get(&app, &uri, &[]).await;
    let etag = headers[header::ETAG].to_str().unwrap().to_owned();
    let (status, _, body) = get(&app, &uri, &[("if-none-match", &etag)]).await;
    assert_eq!(status, StatusCode::NOT_MODIFIED);
    assert!(body.is_empty());
    let old = format!("/poi/{}/10/{x}/{y}.mvt", v - 1);
    let (status, headers, body_old) = get(&app, &old, &[]).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        headers[header::CACHE_CONTROL],
        "public, max-age=300",
        "an old version gets today's data, briefly cached"
    );
    assert!(!body_old.is_empty());

    // Out of the layer, and an empty square of sea.
    let (status, _, _) = get(&app, &format!("/poi/{v}/5/16/11.mvt"), &[]).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "below the lowest zoom");
    let (status, _, _) = get(&app, &format!("/poi/{v}/14/1/1.mvt"), &[]).await;
    assert_eq!(status, StatusCode::NO_CONTENT, "nothing there");
    let (status, _, _) = get(&app, "/poi/x/14/1/1.mvt", &[]).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

const POI_FIELDS: &str = r"
  id category kind name brand lat lon distanceM
  openingHours openingHoursParsed alwaysOpen openingIntervalsUntil
  openingIntervals { start end }
  openNow(at: $at) { state closesAt opensAt }
  lpg fuel { sellsLpg prices { fuel priceEur } shortages { fuel kind } highway sourceId }
  reportedClosed { sourceId closedOn }
  postOfficeKind
  sources { sourceId externalId }
  provenance { field sourceId }
";

#[sqlx::test(migrations = "../../migrations")]
async fn around_a_point_each_category_gives_its_nearest(pool: PgPool) {
    seeded(&pool).await;
    let app = app(&pool);
    let q = format!(
        r"query($lat: Float!, $lon: Float!, $at: DateTime) {{
            nearbyPois(at: {{lat: $lat, lon: $lon}}, perCategory: 3) {{
              category radiusM pois {{ {POI_FIELDS} }}
            }}
          }}"
    );
    let body = gql(
        &app,
        &q,
        json!({"lat": AMBERIEU.0, "lon": AMBERIEU.1, "at": "2026-10-06T08:00:00Z"}),
    )
    .await;
    let groups = ok(&body)["nearbyPois"].as_array().unwrap();
    let categories: Vec<&str> = groups
        .iter()
        .map(|g| g["category"].as_str().unwrap())
        .collect();
    assert_eq!(
        categories,
        [
            "GROCERIES",
            "VENDING",
            "WATER",
            "FUEL",
            "HEALTH",
            "SERVICES"
        ],
        "every category, in display order, even an empty one"
    );
    for g in groups {
        let d: Vec<f64> = g["pois"]
            .as_array()
            .unwrap()
            .iter()
            .map(|p| p["distanceM"].as_f64().unwrap())
            .collect();
        assert!(d.windows(2).all(|w| w[0] <= w[1]), "nearest first: {d:?}");
        assert!(d.iter().all(|x| *x <= g["radiusM"].as_f64().unwrap()));
    }
    let health = &groups[4]["pois"][0];
    assert_eq!(health["name"], "Pharmacie du Champ de Mars");
    assert!(health["distanceM"].as_f64().unwrap() < 200.0);
    let services = groups[5]["pois"].as_array().unwrap();
    let post = services
        .iter()
        .find(|p| p["kind"] == "POST_OFFICE")
        .expect("the post office is among the three nearest services");
    assert_eq!(post["postOfficeKind"], "Bureau de Poste");
    assert_eq!(
        post["openNow"],
        json!({"state": "OPEN", "closesAt": "2026-10-06T10:00:00+00:00", "opensAt": null}),
        "10:00 local on a Tuesday: open until noon"
    );
    assert!(
        post["provenance"]
            .as_array()
            .unwrap()
            .contains(&json!({"field": "openingIntervals", "sourceId": "laposte"})),
        "the intervals are credited to La Poste: {}",
        post["provenance"]
    );
    assert!(
        post["sources"]
            .as_array()
            .unwrap()
            .contains(&json!({"sourceId": "laposte", "externalId": "00001A"}))
    );
    assert_eq!(
        groups[1]["pois"],
        json!([]),
        "no vending machine within 5 km of Ambérieu in the sample"
    );

    let wide = gql(
        &app,
        &q.replace(
            "perCategory: 3",
            "perCategory: 1, categories: [VENDING], radiusM: 20000",
        ),
        json!({"lat": 47.2678, "lon": -0.0696, "at": null}),
    )
    .await;
    let vending = &ok(&wide)["nearbyPois"];
    assert_eq!(vending.as_array().unwrap().len(), 1);
    assert_eq!(vending[0]["pois"][0]["kind"], "VENDING_PIZZA");
    assert!(
        vending[0]["pois"][0]["distanceM"].as_f64().unwrap() < 20.0,
        "the machine at the point asked about, give or take the rounding of the coordinates"
    );

    let both = gql(
        &app,
        "{ nearbyPois(placeId: \"0192a0e6-0000-7000-8000-000000000000\", at: {lat: 45.0, lon: 5.0}) { category } }",
        json!({}),
    )
    .await;
    assert_eq!(code(&both), "INVALID_INPUT", "a place or a point, not both");
    let too_many = gql(
        &app,
        "{ nearbyPois(at: {lat: 45.0, lon: 5.0}, perCategory: 11) { category } }",
        json!({}),
    )
    .await;
    assert_eq!(code(&too_many), "INVALID_INPUT");
    let unknown_place = gql(
        &app,
        "{ nearbyPois(placeId: \"0192a0e6-0000-7000-8000-000000000000\") { category } }",
        json!({}),
    )
    .await;
    assert_eq!(code(&unknown_place), "NOT_FOUND");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_point_shows_what_each_source_says(pool: PgPool) {
    seeded(&pool).await;
    let app = app(&pool);
    let id_of = |external: &'static str| {
        let pool = pool.clone();
        async move {
            sqlx::query_scalar!("SELECT id FROM pois WHERE external_id = $1", external)
                .fetch_one(&pool)
                .await
                .unwrap()
        }
    };
    let q = format!("query($id: UUID!, $at: DateTime) {{ poi(id: $id) {{ {POI_FIELDS} }} }}");

    let lpg = gql(
        &app,
        &q,
        json!({"id": id_of("way/116147677").await, "at": null}),
    )
    .await;
    let station = &ok(&lpg)["poi"];
    assert_eq!(station["lpg"], true);
    assert_eq!(station["fuel"]["sellsLpg"], true);
    assert_eq!(station["fuel"]["sourceId"], "prix-carburants");
    assert!(
        station["fuel"]["prices"]
            .as_array()
            .unwrap()
            .iter()
            .any(|p| p["fuel"] == "LPG" && p["priceEur"].as_f64().unwrap() > 0.0),
        "{station}"
    );
    assert!(
        station["provenance"]
            .as_array()
            .unwrap()
            .contains(&json!({"field": "lpg", "sourceId": "prix-carburants"}))
    );

    let stopped = gql(
        &app,
        &q,
        json!({"id": id_of("node/1860566260").await, "at": null}),
    )
    .await;
    assert_eq!(
        ok(&stopped)["poi"]["lpg"],
        false,
        "the feed's definitive shortage wins over a tag"
    );

    let closed = gql(
        &app,
        &q,
        json!({"id": id_of("node/5499300276").await, "at": null}),
    )
    .await;
    assert_eq!(
        ok(&closed)["poi"]["reportedClosed"],
        json!({"sourceId": "finess", "closedOn": "2026-09-28"})
    );
    let open = gql(
        &app,
        &q,
        json!({"id": id_of("node/1687393915").await, "at": null}),
    )
    .await;
    assert_eq!(ok(&open)["poi"]["reportedClosed"], Value::Null);

    let found = gql(
        &app,
        "{ searchPois(text: \"amberieu\", near: {lat: 45.96, lon: 5.36}) { name kind distanceM } }",
        json!({}),
    )
    .await;
    assert_eq!(ok(&found)["searchPois"][0]["name"], "Ambérieu en Bugey");

    let gone = gql(
        &app,
        &q,
        json!({"id": "0192a0e6-0000-7000-8000-000000000000", "at": null}),
    )
    .await;
    assert_eq!(ok(&gone)["poi"], Value::Null);
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_area_downloads_in_pages_and_the_layer_says_where_its_tiles_are(pool: PgPool) {
    seeded(&pool).await;
    let app = app(&pool);
    let bbox = json!({"south": 45.9, "west": 5.3, "north": 46.0, "east": 5.4});
    let page = r"query($bbox: BBoxInput!, $after: String) {
        pois(bbox: $bbox, first: 4, after: $after) { nodes { id } endCursor hasNextPage }
    }";
    let mut seen = Vec::new();
    let mut after = Value::Null;
    loop {
        let body = gql(&app, page, json!({"bbox": bbox, "after": after})).await;
        let p = &ok(&body)["pois"];
        seen.extend(
            p["nodes"]
                .as_array()
                .unwrap()
                .iter()
                .map(|n| n["id"].as_str().unwrap().to_owned()),
        );
        if p["hasNextPage"] == false {
            break;
        }
        after = p["endCursor"].clone();
    }
    let expected = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM pois
           WHERE deleted_at IS NULL AND geom::geometry && ST_MakeEnvelope(5.3, 45.9, 5.4, 46.0, 4326)"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(seen.len(), usize::try_from(expected).unwrap());
    let distinct: HashSet<&String> = seen.iter().collect();
    assert_eq!(distinct.len(), seen.len(), "no point twice across pages");

    let wide = gql(
        &app,
        r#"{ pois(bbox: {south: 44.0, west: 2.0, north: 47.0, east: 6.0}) { hasNextPage } }"#,
        json!({}),
    )
    .await;
    assert_eq!(
        code(&wide),
        "INVALID_INPUT",
        "12 square degrees is too wide"
    );

    let layer = gql(
        &app,
        "{ poiLayer { version tilesUrl tileJsonUrl minZoom pointMinZoom maxZoom attribution } poiCategories { category kinds defaultRadiusM } }",
        json!({}),
    )
    .await;
    let l = &ok(&layer)["poiLayer"];
    let v = l["version"].as_i64().unwrap();
    assert_eq!(
        l["tilesUrl"],
        format!("https://api.test/poi/{v}/{{z}}/{{x}}/{{y}}.mvt")
    );
    assert_eq!(l["tileJsonUrl"], "https://api.test/poi/tiles.json");
    assert_eq!(
        (
            l["minZoom"].as_i64(),
            l["pointMinZoom"].as_i64(),
            l["maxZoom"].as_i64()
        ),
        (Some(6), Some(13), Some(14))
    );
    let cats = ok(&layer)["poiCategories"].as_array().unwrap();
    assert_eq!(cats.len(), 6);
    assert_eq!(
        cats.iter()
            .map(|c| c["kinds"].as_array().unwrap().len())
            .sum::<usize>(),
        lunaway_domain::poi::PoiKind::ALL.len(),
        "every kind under one category"
    );
}
