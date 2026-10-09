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
use lunaway_domain::{Position, SourceId, poi::decode_hours};
use lunaway_ingest::{
    finess, fuel, laposte, poi_osm,
    store::{store_joins, store_pois},
};
use serde_json::{Value, json};
use tower::ServiceExt;

use crate::mvt::{decode, tile_of};

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
            (-64..4096 + 64).contains(&f.point().0) && (-64..4096 + 64).contains(&f.point().1),
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
           WHERE deleted_at IS NULL AND category NOT IN ('food', 'sights')
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
        "the default clusters count every point of their tile but those read on demand \
         (the sample's tourist office is something to see)"
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

/// The counts of a cluster tile per layer, name (category or kind) and
/// cell of the zoom's grid over the world: a cell of a tile of 4096 units
/// is 128 units wide.
fn cluster_counts(
    tile: &[u8],
    z: u32,
    (x, y): (u32, u32),
) -> BTreeMap<(String, String, u32, u32), u64> {
    let mut out = BTreeMap::new();
    for (layer, name) in [
        ("poi_clusters", "category"),
        ("poi_vending_clusters", "kind"),
    ] {
        let Some((extent, features)) = decode(tile).remove(layer) else {
            continue;
        };
        assert_eq!(extent, 4096);
        for f in features {
            let (px, py) = f.point();
            assert!(
                (0..4096).contains(&px) && (0..4096).contains(&py),
                "{z}: a cluster stands in its tile"
            );
            let cell = (
                x * 32 + u32::try_from(px / 128).unwrap(),
                y * 32 + u32::try_from(py / 128).unwrap(),
            );
            *out.entry((
                layer.to_owned(),
                f.props[name].as_str().unwrap().to_owned(),
                cell.0,
                cell.1,
            ))
            .or_default() += f.props["count"].as_u64().unwrap();
        }
    }
    out
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_cluster_tile_counts_what_the_four_cells_of_the_next_zoom_count(pool: PgPool) {
    seeded(&pool).await;
    // Up to zoom 9 the clusters are those the version published; above,
    // the tile counts its points. Both must agree: a cell is the four
    // cells below it.
    lunaway_db::pois::mark_layer_now(&pool).await.unwrap();
    lunaway_db::pois::publish_layer(&pool, std::time::Duration::ZERO)
        .await
        .unwrap()
        .expect("the sample waits for a version");
    let app = app(&pool);
    let v = version(&app).await;
    for (lat, lon) in [AMBERIEU, SAUMUR] {
        let z = u32::try_from(lunaway_db::pois::CLUSTER_TABLE_MAX_ZOOM).unwrap();
        let (x, y) = tile_of(lat, lon, z);
        let (status, _, body) = get(&app, &format!("/poi/{v}/{z}/{x}/{y}.mvt"), &[]).await;
        assert_eq!(status, StatusCode::OK);
        let parent = cluster_counts(&body, z, (x, y));
        let mut children = BTreeMap::new();
        for (cx, cy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
            let child = (2 * x + cx, 2 * y + cy);
            let (status, _, body) = get(
                &app,
                &format!("/poi/{v}/{}/{}/{}.mvt", z + 1, child.0, child.1),
                &[],
            )
            .await;
            if status == StatusCode::NO_CONTENT {
                continue;
            }
            for ((layer, name, gx, gy), n) in cluster_counts(&body, z + 1, child) {
                *children.entry((layer, name, gx / 2, gy / 2)).or_default() += n;
            }
        }
        if (lat, lon) == SAUMUR {
            assert!(
                parent.keys().any(|k| k.0 == "poi_vending_clusters"),
                "Saumur's machines are counted per kind"
            );
        }
        assert_eq!(
            parent,
            children,
            "zoom {z} over ({lat}, {lon}): the published cells and the counts of zoom {}",
            z + 1
        );
    }
}

/// Saumur, where the sample's food vending machines stand.
const SAUMUR: (f64, f64) = (47.26, -0.08);

#[sqlx::test(migrations = "../../migrations")]
async fn cluster_tiles_count_the_vending_machines_per_kind_in_their_own_layer(pool: PgPool) {
    seeded(&pool).await;
    let app = app(&pool);
    let v = version(&app).await;
    let (x, y) = tile_of(SAUMUR.0, SAUMUR.1, 10);
    let (xi, yi) = (i32::try_from(x).unwrap(), i32::try_from(y).unwrap());
    let (status, _, body) = get(&app, &format!("/poi/{v}/10/{x}/{y}.mvt"), &[]).await;
    assert_eq!(status, StatusCode::OK);
    let layers = decode(&body);

    let kinds = sqlx::query!(
        r#"SELECT kind, count(*) AS "n!" FROM pois
           WHERE deleted_at IS NULL AND NOT hidden AND category = 'vending'
             AND geom::geometry && ST_Transform(ST_TileEnvelope(10, $1, $2), 4326)
           GROUP BY kind"#,
        xi,
        yi,
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    let in_db: BTreeMap<String, u64> = kinds
        .into_iter()
        .map(|r| (r.kind, u64::try_from(r.n).unwrap()))
        .collect();
    assert!(
        in_db.contains_key("vending_pizza") && in_db.contains_key("vending_other"),
        "the sample holds a pizza machine and one of no known kind there: {in_db:?}"
    );

    let mut per_kind = BTreeMap::<String, u64>::new();
    for f in &layers["poi_vending_clusters"].1 {
        *per_kind
            .entry(f.props["kind"].as_str().unwrap().to_owned())
            .or_default() += f.props["count"].as_u64().unwrap();
        assert!(
            !f.props.contains_key("category"),
            "a map that knows only the category clusters must not draw these"
        );
    }
    let wanted: BTreeMap<String, u64> = in_db
        .iter()
        .filter(|(k, _)| k.as_str() != "vending_other")
        .map(|(k, n)| (k.clone(), *n))
        .collect();
    assert_eq!(
        per_kind, wanted,
        "every machine a kind filter can pick is counted under its kind, and no other"
    );

    let vending_in_clusters: u64 = layers["poi_clusters"]
        .1
        .iter()
        .filter(|f| f.props["category"] == "vending")
        .map(|f| f.props["count"].as_u64().unwrap())
        .sum();
    assert_eq!(
        vending_in_clusters,
        in_db.values().sum::<u64>(),
        "the category's clusters still count every machine, those of no known kind too"
    );

    // Zoomed in, the points carry their kind and no kind layer is sent.
    let (x, y) = tile_of(47.267_784_4, -0.069_596_8, 14);
    let (_, _, body) = get(&app, &format!("/poi/{v}/14/{x}/{y}.mvt"), &[]).await;
    let points = decode(&body);
    assert!(!points.contains_key("poi_vending_clusters"));
    assert!(
        points["pois"]
            .1
            .iter()
            .any(|f| f.props["kind"] == "vending_pizza"),
        "a pizza machine's point names its kind, for the filter"
    );

    let (_, _, body) = get(&app, "/poi/tiles.json", &[]).await;
    let tj: Value = serde_json::from_slice(&body).unwrap();
    assert!(
        tj["vector_layers"]
            .as_array()
            .unwrap()
            .iter()
            .any(|l| l["id"] == "poi_vending_clusters" && l["fields"]["kind"].is_string()),
        "the TileJSON describes the new layer"
    );
}

const MORE: &[u8] = include_bytes!("../../lunaway-ingest/tests/fixtures/osm_poi_more_sample.json");

/// The sample, and the restaurants, sights, outdoor shop, washes and
/// motorhome garage of the second sample.
async fn seeded_with_stops(pool: &PgPool) {
    seeded(pool).await;
    let at = Utc.with_ymd_and_hms(2026, 10, 5, 22, 0, 0).unwrap();
    let parsed = poi_osm::parse(MORE, at).unwrap();
    assert!(parsed.skipped.is_empty(), "{:?}", parsed.skipped);
    store_pois(pool, &SourceId::OSM, &parsed.points)
        .await
        .unwrap();
}

/// The categories of a tile's clusters, and the kinds of each points layer.
fn tile_contents(tile: &[u8]) -> BTreeMap<String, Vec<String>> {
    decode(tile)
        .into_iter()
        .map(|(layer, (_, features))| {
            let key = if layer == "poi_clusters" {
                "category"
            } else {
                "kind"
            };
            let mut names: Vec<String> = features
                .iter()
                .map(|f| f.props[key].as_str().unwrap().to_owned())
                .collect();
            names.sort();
            names.dedup();
            (layer, names)
        })
        .collect()
}

#[sqlx::test(migrations = "../../migrations")]
async fn restaurants_and_sights_come_only_in_the_tiles_of_every_category(pool: PgPool) {
    seeded_with_stops(&pool).await;
    lunaway_db::pois::mark_layer_now(&pool).await.unwrap();
    lunaway_db::pois::publish_layer(&pool, std::time::Duration::ZERO)
        .await
        .unwrap()
        .expect("the samples wait for a version");
    let app = app(&pool);
    let v = version(&app).await;
    let (status, _, body) = get(&app, "/poi/all/tiles.json", &[]).await;
    assert_eq!(status, StatusCode::OK);
    let tj: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(
        tj["tiles"][0],
        format!("https://api.test/poi/{v}/all/{{z}}/{{x}}/{{y}}.mvt"),
        "the same version as the default tiles"
    );

    let (x, y) = tile_of(AMBERIEU.0, AMBERIEU.1, 14);
    let (_, base_headers, base) = get(&app, &format!("/poi/{v}/14/{x}/{y}.mvt"), &[]).await;
    let (status, all_headers, all) = get(&app, &format!("/poi/{v}/all/14/{x}/{y}.mvt"), &[]).await;
    assert_eq!(status, StatusCode::OK);
    let base = tile_contents(&base);
    let all = tile_contents(&all);
    assert!(
        base["pois"].contains(&"post_office".to_owned()),
        "{:?}",
        base["pois"]
    );
    for kind in ["restaurant", "cafe", "fast_food", "museum"] {
        assert!(
            !base["pois"].contains(&kind.to_owned()),
            "{kind}: not in the tiles a map reads by default: {base:?}"
        );
        assert!(all["pois"].contains(&kind.to_owned()), "{kind}: {all:?}");
    }
    assert!(
        base["pois"].iter().all(|k| all["pois"].contains(k)),
        "every point of the default tiles is in the tiles of every category"
    );
    let office = decode(&get(&app, &format!("/poi/{v}/14/{x}/{y}.mvt"), &[]).await.2)["pois"]
        .1
        .iter()
        .find(|f| f.props["kind"] == "tourist_office")
        .map(|f| f.props["category"].clone());
    assert_eq!(
        office,
        Some(Value::from("sights")),
        "a kind the first apps knew stays in the default tiles, under its new category"
    );
    assert!(
        !base.contains_key("pois_more") && !all.contains_key("pois_more"),
        "no kind added since in the default tiles of Amberieu, none apart in the others"
    );
    // The outdoor shop of the sample: a kind the first apps did not know, of
    // a category the default tiles carry.
    let (x, y) = tile_of(46.0381, 5.7012, 14);
    let base = tile_contents(&get(&app, &format!("/poi/{v}/14/{x}/{y}.mvt"), &[]).await.2);
    let all = tile_contents(
        &get(&app, &format!("/poi/{v}/all/14/{x}/{y}.mvt"), &[])
            .await
            .2,
    );
    assert_eq!(base["pois_more"], ["outdoor_shop"], "{base:?}");
    assert!(
        base.get("pois")
            .is_none_or(|k| !k.contains(&"outdoor_shop".to_owned())),
        "an app that predates the kind never draws it: {base:?}"
    );
    assert!(all["pois"].contains(&"outdoor_shop".to_owned()), "{all:?}");
    let (x, y) = tile_of(AMBERIEU.0, AMBERIEU.1, 14);
    assert_ne!(
        base_headers[header::ETAG],
        all_headers[header::ETAG],
        "the two sets never share an ETag"
    );
    let decoded = decode(
        &get(&app, &format!("/poi/{v}/all/14/{x}/{y}.mvt"), &[])
            .await
            .2,
    );
    let restaurant = decoded["pois"]
        .1
        .iter()
        .find(|f| f.props["kind"] == "restaurant")
        .unwrap();
    assert_eq!(restaurant.props["category"], "food");
    assert_eq!(restaurant.props["name"], "Le Garde Manger");

    let (x, y) = tile_of(AMBERIEU.0, AMBERIEU.1, 10);
    let (_, _, base) = get(&app, &format!("/poi/{v}/10/{x}/{y}.mvt"), &[]).await;
    let (_, _, all) = get(&app, &format!("/poi/{v}/all/10/{x}/{y}.mvt"), &[]).await;
    let (base, all) = (tile_contents(&base), tile_contents(&all));
    for c in ["food", "sights"] {
        assert!(
            !base["poi_clusters"].contains(&c.to_owned()),
            "{c}: {base:?}"
        );
        assert!(all["poi_clusters"].contains(&c.to_owned()), "{c}: {all:?}");
    }
    let z = u32::try_from(lunaway_db::pois::CLUSTER_TABLE_MAX_ZOOM).unwrap();
    let (x, y) = tile_of(AMBERIEU.0, AMBERIEU.1, z);
    let (_, _, base) = get(&app, &format!("/poi/{v}/{z}/{x}/{y}.mvt"), &[]).await;
    let (_, _, all) = get(&app, &format!("/poi/{v}/all/{z}/{x}/{y}.mvt"), &[]).await;
    assert!(
        !tile_contents(&base)["poi_clusters"].contains(&"food".to_owned()),
        "the published clusters too"
    );
    assert!(tile_contents(&all)["poi_clusters"].contains(&"food".to_owned()));
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_tile_costs_its_client_in_proportion_to_its_size_from_the_cache_too(pool: PgPool) {
    seeded_with_stops(&pool).await;
    let (x, y) = tile_of(AMBERIEU.0, AMBERIEU.1, 14);
    let uri = |v: i64| format!("/poi/{v}/all/14/{x}/{y}.mvt");
    // The tile's size, read on an API of the usual budget.
    let roomy = app(&pool);
    let v = version(&roomy).await;
    let (status, _, body) = get(&roomy, &uri(v), &[]).await;
    assert_eq!(status, StatusCode::OK);
    let size = body.len() / 100;
    assert!(size > 10, "a tile of some weight: {} bytes", body.len());
    // A budget for the TileJSON, the tile built and served, and one more
    // request served from the cache: everything but the second size.
    let request = 1_000;
    let burst = request + (request + 2_000 + size) + request + size - 1;
    let config = ApiConfig {
        tiles: lunaway_api::config::TilesConfig {
            public_url: "https://api.test".into(),
            ..ApiConfig::default().tiles
        },
        limits: lunaway_api::config::Limits {
            rate_burst: u64::try_from(burst).unwrap(),
            rate_per_second: 1,
            ..ApiConfig::default().limits
        },
        ..ApiConfig::default()
    };
    let tight = lunaway_api::router(ApiState::new(pool.clone(), config));
    let v = version(&tight).await;
    let (status, _, _) = get(&tight, &uri(v), &[]).await;
    assert_eq!(status, StatusCode::OK, "built and served within the budget");
    let (status, headers, _) = get(&tight, &uri(v), &[]).await;
    assert_eq!(
        status,
        StatusCode::TOO_MANY_REQUESTS,
        "served again from the cache, it still costs its size"
    );
    assert!(headers.contains_key(header::RETRY_AFTER));
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_wash_says_the_vehicles_it_takes_and_a_stop_has_its_category(pool: PgPool) {
    seeded_with_stops(&pool).await;
    let app = app(&pool);
    let id = |external: &'static str| {
        let pool = pool.clone();
        async move {
            sqlx::query_scalar!("SELECT id FROM pois WHERE external_id = $1", external)
                .fetch_one(&pool)
                .await
                .unwrap()
        }
    };
    let q = "query($id: UUID!) { poi(id: $id) { kind category motorhome hgv maxHeightM } }";
    let lorries = gql(&app, q, json!({"id": id("node/2169351301").await})).await;
    assert_eq!(
        ok(&lorries)["poi"],
        json!({"kind": "CAR_WASH", "category": "SERVICES", "motorhome": null, "hgv": true,
               "maxHeightM": null})
    );
    let gantry = gql(&app, q, json!({"id": id("node/4514289596").await})).await;
    assert_eq!(ok(&gantry)["poi"]["maxHeightM"], 2.4);
    let museum = gql(&app, q, json!({"id": id("way/67071477").await})).await;
    assert_eq!(ok(&museum)["poi"]["category"], "SIGHTS");

    let near = gql(
        &app,
        r"query($lat: Float!, $lon: Float!) {
            nearbyPois(at: {lat: $lat, lon: $lon}, categories: [FOOD, SIGHTS], perCategory: 3) {
              category radiusM pois { kind name }
            }
          }",
        json!({"lat": AMBERIEU.0, "lon": AMBERIEU.1}),
    )
    .await;
    let groups = ok(&near)["nearbyPois"].as_array().unwrap();
    assert_eq!(groups[0]["category"], "FOOD");
    assert_eq!(groups[0]["radiusM"], 5000.0);
    assert!(
        groups[0]["pois"]
            .as_array()
            .unwrap()
            .iter()
            .any(|p| p["kind"] == "RESTAURANT"),
        "{near}"
    );
    assert_eq!(groups[1]["category"], "SIGHTS");
    assert_eq!(
        groups[1]["radiusM"], 10000.0,
        "something to see is worth a drive"
    );
    let sights: Vec<&str> = groups[1]["pois"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["kind"].as_str().unwrap())
        .collect();
    assert!(sights.contains(&"MUSEUM"), "{sights:?}");
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
    // The server keeps the point on the 0.05 degree grid only: the centre
    // of Ambérieu and the grid's node beside it get the same answer, its
    // distances measured from the node.
    let node = Position::new(AMBERIEU.0, AMBERIEU.1).unwrap().coarsened();
    assert!(node.distance_m(Position::new(AMBERIEU.0, AMBERIEU.1).unwrap()) > 500.0);
    let at_node = gql(
        &app,
        &q,
        json!({"lat": node.lat(), "lon": node.lon(), "at": "2026-10-06T08:00:00Z"}),
    )
    .await;
    assert_eq!(body, at_node, "the point sent never reaches the search");
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
            "SERVICES",
            "FOOD",
            "SIGHTS"
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
        for p in g["pois"].as_array().unwrap() {
            let at = Position::new(p["lat"].as_f64().unwrap(), p["lon"].as_f64().unwrap()).unwrap();
            assert!(
                (p["distanceM"].as_f64().unwrap() - at.distance_m(node)).abs()
                    < 2.0 + at.distance_m(node) * 0.005,
                "measured from the grid's node: {p}"
            );
        }
    }
    let health = &groups[4]["pois"][0];
    assert_eq!(health["name"], "Pharmacie du Champ de Mars");
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
    let machine = Position::new(47.2678, -0.0696).unwrap();
    assert!(
        (vending[0]["pois"][0]["distanceM"].as_f64().unwrap()
            - machine.distance_m(machine.coarsened()))
        .abs()
            < 20.0,
        "the machine at the point asked about, its distance from the grid's node"
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
    let search = |lat: f64, lon: f64| {
        let app = &app;
        async move {
            gql(
                app,
                "query($lat: Float!, $lon: Float!) { searchPois(text: \"pharmacie\", \
                 near: {lat: $lat, lon: $lon}) { lat lon distanceM } }",
                json!({"lat": lat, "lon": lon}),
            )
            .await
        }
    };
    let off_grid = search(45.9597, 5.3582).await;
    let node = Position::new(45.9597, 5.3582).unwrap().coarsened();
    assert_eq!(
        off_grid,
        search(node.lat(), node.lon()).await,
        "the search ranks from the grid's node, never from the point sent"
    );
    let first = &ok(&off_grid)["searchPois"][0];
    let at = Position::new(
        first["lat"].as_f64().unwrap(),
        first["lon"].as_f64().unwrap(),
    )
    .unwrap();
    assert!(
        (first["distanceM"].as_f64().unwrap() - at.distance_m(node)).abs()
            < 2.0 + at.distance_m(node) * 0.005,
        "measured from the grid's node (the database's spheroid against a sphere here)"
    );

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
    assert_eq!(
        cats.len(),
        lunaway_domain::poi::PoiCategory::ALL.len(),
        "every category, those of the establishments too"
    );
    assert_eq!(
        cats.iter()
            .map(|c| c["kinds"].as_array().unwrap().len())
            .sum::<usize>(),
        lunaway_domain::poi::PoiKind::ALL.len(),
        "every kind under one category"
    );
}
