//! `Query.enforcement`: each item in the only form its country allows,
//! checked again when served (a point in France or in Switzerland never
//! leaves the server, whatever a row says), the rules of every country, the
//! lists with their last read, and the changes since a cursor. France's
//! points reach only a client that asked for them (`exactIn`), and that
//! choice leaves no trace in the logs.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use axum::{
    Router,
    body::Body,
    http::{Request, StatusCode},
};
use chrono::{TimeZone, Utc};
use http_body_util::BodyExt;
use lunaway_api::{ApiConfig, ApiState};
use lunaway_db::{
    PgPool,
    enforcement::{self as db, Item, ItemKind, NewDevice, Variant},
};
use lunaway_domain::{
    Position, SourceId,
    enforcement::{Device, DeviceKind},
    routing::polyline,
};
use lunaway_ingest::road_events::matching::{Engine, MatchError};
use serde_json::{Value, json};
use tower::ServiceExt;
use uuid::Uuid;

const QUERY: &str = r"
query Enforcement($since: String, $countries: [String!], $exactIn: [String!]) {
  enforcement(since: $since, countries: $countries, exactIn: $exactIn) {
    cursor full hasMore pollIntervalSeconds
    rules { version reviewedOn defaultMode
      countries { country mode optInMode zoneLengths { motorwayM ruralM urbanM } sources } }
    upserts { id kind category country line lat lon bearingDeg limitKmh sourceIds }
    removals
    sources { id licence attribution fetchedAt cameras }
  }
}";

async fn gql(app: &Router, variables: Value) -> (StatusCode, Value) {
    let request = Request::post("/graphql")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({"query": QUERY, "variables": variables}).to_string(),
        ))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (status, serde_json::from_slice(&bytes).unwrap())
}

fn p(lat: f64, lon: f64) -> Position {
    Position::new(lat, lon).unwrap()
}

fn item(key: &str, kind: ItemKind, category: &str, country: &str) -> Item {
    Item {
        id: Uuid::now_v7(),
        device_key: key.to_owned(),
        variant: Variant::All,
        opt_in_countries: Vec::new(),
        kind,
        category: category.to_owned(),
        country: country.to_owned(),
        line: None,
        point: None,
        bearing_deg: None,
        limit_kmh: None,
        source_ids: vec!["osm".to_owned()],
        content_hash: key.to_owned(),
    }
}

fn zone(key: &str, country: &str, line: Vec<Position>) -> Item {
    Item {
        line: Some(line),
        source_ids: vec!["securite-routiere".to_owned(), "osm".to_owned()],
        ..item(key, ItemKind::Zone, "fixed", country)
    }
}

fn camera(key: &str, country: &str, at: Position) -> Item {
    Item {
        point: Some(at),
        bearing_deg: Some(271.04),
        limit_kmh: Some(90),
        ..item(key, ItemKind::Camera, "section", country)
    }
}

/// `i` as the item of its camera for the clients without France's choice
/// (`Variant::Default`) or with it (`Variant::OptIn`).
fn for_choice(i: Item, variant: Variant) -> Item {
    Item {
        variant,
        opt_in_countries: vec!["FR".to_owned()],
        ..i
    }
}

fn ids(list: &Value) -> Vec<String> {
    list.as_array()
        .unwrap()
        .iter()
        .map(|v| {
            v.as_str()
                .map_or_else(|| v["id"].as_str().unwrap().to_owned(), str::to_owned)
        })
        .collect()
}

fn sorted(mut v: Vec<String>) -> Vec<String> {
    v.sort();
    v
}

fn id_set(items: &[&Item]) -> Vec<String> {
    sorted(items.iter().map(|i| i.id.to_string()).collect())
}

/// A pool whose every connection runs as `role`, as the services do.
async fn as_role(pool: &PgPool, set_role: &'static str) -> PgPool {
    sqlx::postgres::PgPoolOptions::new()
        .max_connections(4)
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
async fn each_item_is_served_in_the_form_its_country_allows(pool: PgPool) {
    let french_line = vec![p(45.83, 1.26), p(45.835, 1.27), p(45.84, 1.28)];
    let french = zone("securite-routiere/60004", "FR", french_line.clone());
    let madrid = camera("osm/node/1", "ES", p(40.4168, -3.7038));
    // Rows no build writes, as a bug or an older rule could leave them.
    let french_point = camera("osm/node/2", "FR", p(48.85, 2.35));
    let in_switzerland = camera("osm/node/3", "ES", p(46.948, 7.447));
    let moroccan = zone("osm/node/4", "MA", vec![p(34.0, -6.8), p(34.01, -6.81)]);
    db::write_items(
        &pool,
        &[
            french.clone(),
            madrid.clone(),
            french_point.clone(),
            in_switzerland,
            moroccan,
        ],
        &[],
    )
    .await
    .unwrap();
    let read_at = Utc.with_ymd_and_hms(2026, 10, 6, 16, 3, 47).unwrap();
    db::record_read(
        &pool,
        &SourceId::new("securite-routiere").unwrap(),
        read_at,
        3_664,
        None,
    )
    .await
    .unwrap();
    let app = lunaway_api::router(ApiState::new(pool.clone(), ApiConfig::default()));

    let (status, body) = gql(&app, json!({})).await;
    assert_eq!(status, StatusCode::OK);
    let e = &body["data"]["enforcement"];
    assert_eq!(e["full"], true, "{body}");
    assert_eq!(
        ids(&e["upserts"]),
        [french.id.to_string(), madrid.id.to_string()],
        "no point in France or in Switzerland, nothing in Morocco"
    );
    let z = &e["upserts"][0];
    assert_eq!(z["kind"], "ZONE");
    assert_eq!(z["category"], "FIXED");
    assert_eq!(z["lat"], Value::Null);
    assert_eq!(z["bearingDeg"], Value::Null);
    let line = polyline::decode(z["line"].as_str().unwrap()).unwrap();
    assert_eq!(line.len(), 3);
    assert!(line[1].distance_m(french_line[1]) < 0.5);
    let c = &e["upserts"][1];
    assert_eq!(c["kind"], "CAMERA");
    assert_eq!(c["category"], "SECTION_CONTROL");
    assert!((c["lat"].as_f64().unwrap() - 40.4168).abs() < 1e-9);
    assert_eq!(c["bearingDeg"], 271.0);
    assert_eq!(c["limitKmh"], 90);
    let rules = e["rules"]["countries"].as_array().unwrap();
    let rule = |c: &str| rules.iter().find(|r| r["country"] == c).unwrap();
    assert_eq!(rule("FR")["mode"], "ZONES");
    assert_eq!(
        rule("FR")["optInMode"],
        "EXACT",
        "a user may ask for France's points"
    );
    assert_eq!(rule("FR")["zoneLengths"]["motorwayM"], 4_000);
    assert_eq!(rule("CH")["mode"], "OFF");
    assert_eq!(rule("DE")["mode"], "OFF_WHILE_DRIVING");
    for c in ["CH", "DE", "ES", "IT", "PT", "NO", "FI", "IE", "MA"] {
        assert_eq!(
            rule(c).get("optInMode").cloned().unwrap_or(Value::Null),
            Value::Null,
            "{c} offers no choice"
        );
    }
    assert_eq!(e["rules"]["defaultMode"], "OFF");
    assert_eq!(e["rules"]["version"], 2);
    assert_eq!(e["rules"]["reviewedOn"], "2026-10-09");
    let source = &e["sources"][0];
    assert_eq!(source["id"], "securite-routiere");
    assert_eq!(
        source["attribution"],
        "Sécurité routière, radars.securite-routiere.gouv.fr"
    );
    let fetched =
        chrono::DateTime::parse_from_rfc3339(source["fetchedAt"].as_str().unwrap()).unwrap();
    assert_eq!(
        fetched, read_at,
        "the CRPA asks for the date of the list with its source"
    );
    assert_eq!(e["hasMore"], false);

    // Nothing changed: an empty answer.
    let cursor = e["cursor"].as_str().unwrap().to_owned();
    let (_, body) = gql(&app, json!({"since": cursor})).await;
    let e = &body["data"]["enforcement"];
    assert_eq!(
        (e["full"].clone(), e["upserts"].clone()),
        (json!(false), json!([]))
    );

    // Madrid's camera goes, the French point is written again: both come
    // back as removals.
    db::write_items(
        &pool,
        &[Item {
            content_hash: "moved".into(),
            ..french_point.clone()
        }],
        &[madrid.key()],
    )
    .await
    .unwrap();
    // The head is read at most every five seconds: a new state reads it.
    let app = lunaway_api::router(ApiState::new(pool.clone(), ApiConfig::default()));
    let (_, body) = gql(&app, json!({"since": cursor})).await;
    let e = &body["data"]["enforcement"];
    assert_eq!(e["full"], false, "{body}");
    assert_eq!(e["upserts"], json!([]));
    let mut removed = ids(&e["removals"]);
    removed.sort();
    let mut expected = vec![madrid.id.to_string(), french_point.id.to_string()];
    expected.sort();
    assert_eq!(removed, expected);

    // One country only.
    let (_, body) = gql(&app, json!({"countries": ["fr"]})).await;
    assert_eq!(
        ids(&body["data"]["enforcement"]["upserts"]),
        [french.id.to_string()]
    );
    let (_, body) = gql(&app, json!({"countries": ["FRA"]})).await;
    assert_eq!(body["errors"][0]["extensions"]["code"], "INVALID_INPUT");
    let (_, body) = gql(
        &app,
        json!({"since": "e1.0123456789abcdef0123456789abcdef00004000.1"}),
    )
    .await;
    assert_eq!(body["errors"][0]["extensions"]["code"], "INVALID_INPUT");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_small_page_gives_every_item_once_and_says_when_more_wait(pool: PgPool) {
    let line = |lon: f64| vec![p(45.83, lon), p(45.835, lon + 0.01)];
    let written: Vec<Item> = (0..3)
        .map(|i| {
            zone(
                &format!("securite-routiere/{i}"),
                "FR",
                line(1.2 + f64::from(i) * 0.05),
            )
        })
        .collect();
    db::write_items(&pool, &written, &[]).await.unwrap();
    let app = lunaway_api::router(ApiState::new(pool.clone(), ApiConfig::default()));
    let page = |since: Option<String>| {
        let app = app.clone();
        async move {
            let request = Request::post("/graphql")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "query": "query($since: String) { enforcement(since: $since, first: 2) \
                                  { cursor full hasMore upserts { id } removals } }",
                        "variables": {"since": since}
                    })
                    .to_string(),
                ))
                .unwrap();
            let response = app.oneshot(request).await.unwrap();
            let bytes = response.into_body().collect().await.unwrap().to_bytes();
            let body: Value = serde_json::from_slice(&bytes).unwrap();
            body["data"]["enforcement"].clone()
        }
    };
    let first = page(None).await;
    assert_eq!(
        (&first["full"], &first["hasMore"]),
        (&json!(true), &json!(true)),
        "{first}"
    );
    let second = page(first["cursor"].as_str().map(str::to_owned)).await;
    assert_eq!(
        (&second["full"], &second["hasMore"]),
        (&json!(false), &json!(false)),
        "{second}"
    );
    let mut seen = ids(&first["upserts"]);
    seen.extend(ids(&second["upserts"]));
    let mut expected: Vec<String> = written.iter().map(|i| i.id.to_string()).collect();
    seen.sort();
    expected.sort();
    assert_eq!(seen, expected, "every item once over the pages");
    assert_eq!(second["removals"], json!([]));
}

fn upsert(delta: &Value, id: Uuid) -> &Value {
    delta["upserts"]
        .as_array()
        .unwrap()
        .iter()
        .find(|u| u["id"] == id.to_string())
        .unwrap_or_else(|| panic!("{id} served: {delta}"))
}

#[sqlx::test(migrations = "../../migrations")]
async fn france_s_points_reach_only_a_client_that_asked_for_them(pool: PgPool) {
    let limousin = p(45.8336, 1.2611);
    let fr_zone = for_choice(
        zone(
            "securite-routiere/1001",
            "FR",
            vec![p(45.83, 1.25), limousin, p(45.84, 1.27)],
        ),
        Variant::Default,
    );
    let fr_point = for_choice(
        Item {
            category: "fixed".to_owned(),
            ..camera("securite-routiere/1001", "FR", limousin)
        },
        Variant::OptIn,
    );
    // A Spanish camera within a kilometre of France.
    let irun = p(43.3399, -1.7808);
    let irun_zone = for_choice(
        zone(
            "osm/node/12",
            "ES",
            vec![p(43.335, -1.79), irun, p(43.345, -1.77)],
        ),
        Variant::Default,
    );
    let irun_point = for_choice(camera("osm/node/12", "ES", irun), Variant::OptIn);
    let madrid = camera("osm/node/1", "ES", p(40.4168, -3.7038));
    let berlin = camera("osm/node/2", "DE", p(52.52, 13.405));
    // Rows no build writes, as a bug could leave them: a French point for
    // the clients without the choice, a Swiss point and a Moroccan zone for
    // those with it.
    let stray_point = for_choice(
        camera("securite-routiere/1002", "FR", p(48.85, 2.35)),
        Variant::Default,
    );
    let swiss_point = for_choice(camera("osm/node/3", "ES", p(46.948, 7.447)), Variant::OptIn);
    let moroccan = for_choice(
        zone("osm/node/4", "MA", vec![p(34.0, -6.8), p(34.01, -6.81)]),
        Variant::OptIn,
    );
    db::write_items(
        &pool,
        &[
            fr_zone.clone(),
            fr_point.clone(),
            irun_zone.clone(),
            irun_point.clone(),
            madrid.clone(),
            berlin.clone(),
            stray_point,
            swiss_point,
            moroccan,
        ],
        &[],
    )
    .await
    .unwrap();
    let app_role = as_role(&pool, "SET ROLE lunaway_app").await;
    let app = lunaway_api::router(ApiState::new(app_role, ApiConfig::default()));

    let (status, body) = gql(&app, json!({})).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let none = body["data"]["enforcement"].clone();
    assert_eq!(
        sorted(ids(&none["upserts"])),
        id_set(&[&fr_zone, &irun_zone, &madrid, &berlin]),
        "without the choice, zones in France and within a kilometre of it, never a point there: \
         {body}"
    );

    let (_, body) = gql(&app, json!({"exactIn": ["FR"]})).await;
    let fr = body["data"]["enforcement"].clone();
    assert_eq!(
        sorted(ids(&fr["upserts"])),
        id_set(&[&fr_point, &irun_point, &madrid, &berlin]),
        "with it, France's points and no French zone, nothing in Switzerland or Morocco: {body}"
    );
    let point = upsert(&fr, fr_point.id);
    assert_eq!(point["kind"], "CAMERA");
    assert_eq!(point["category"], "FIXED");
    assert!((point["lat"].as_f64().unwrap() - limousin.lat()).abs() < 1e-9);
    assert_eq!(
        (&point["bearingDeg"], &point["limitKmh"]),
        (&json!(271.0), &json!(90))
    );
    assert!(upsert(&fr, irun_point.id)["lat"].is_number());

    let (_, body) = gql(&app, json!({"exactIn": ["ES", "CH", "IT"]})).await;
    let other = &body["data"]["enforcement"];
    assert_eq!(
        sorted(ids(&other["upserts"])),
        sorted(ids(&none["upserts"]))
    );
    assert_eq!(
        other["cursor"], none["cursor"],
        "choices no country offers change nothing, not even the cursor"
    );

    // The setting turned on or off with a cursor: the whole set again, in
    // the other form.
    let (_, body) = gql(&app, json!({"since": none["cursor"], "exactIn": ["FR"]})).await;
    let e = &body["data"]["enforcement"];
    assert_eq!(e["full"], true, "{body}");
    assert_eq!(sorted(ids(&e["upserts"])), sorted(ids(&fr["upserts"])));
    let (_, body) = gql(&app, json!({"since": fr["cursor"]})).await;
    let e = &body["data"]["enforcement"];
    assert_eq!(e["full"], true, "{body}");
    assert_eq!(sorted(ids(&e["upserts"])), sorted(ids(&none["upserts"])));
    // The same choice: nothing new.
    let (_, body) = gql(&app, json!({"since": fr["cursor"], "exactIn": ["fr"]})).await;
    let e = &body["data"]["enforcement"];
    assert_eq!(
        (&e["full"], &e["upserts"]),
        (&json!(false), &json!([])),
        "{body}"
    );
    // A cursor of the format before the choices: the whole set, no error.
    let old = fr["cursor"].as_str().unwrap().replacen("n3.", "n2.", 1);
    let (_, body) = gql(&app, json!({"since": old, "exactIn": ["FR"]})).await;
    let e = &body["data"]["enforcement"];
    assert_eq!(e["full"], true, "{body}");
    assert_eq!(sorted(ids(&e["upserts"])), sorted(ids(&fr["upserts"])));

    // Refused like `countries`, without repeating the value.
    let (_, body) = gql(&app, json!({"exactIn": ["Q7"]})).await;
    assert_eq!(body["errors"][0]["extensions"]["code"], "INVALID_INPUT");
    assert!(!body.to_string().contains("Q7"), "{body}");
    let (_, body) = gql(&app, json!({"exactIn": vec!["FR"; 9]})).await;
    assert_eq!(body["errors"][0]["extensions"]["code"], "INVALID_INPUT");
}

/// A camera whose form starts to depend on France's choice (the first build
/// after the choice, or a rule that changes): its item keeps its row and
/// its id for the clients without the choice, and reaches those with it as
/// a removal, beside the new point.
#[sqlx::test(migrations = "../../migrations")]
async fn an_item_that_moves_to_one_side_of_the_choice_leaves_the_other(pool: PgPool) {
    let limousin = p(45.8336, 1.2611);
    let old = zone(
        "securite-routiere/1001",
        "FR",
        vec![p(45.83, 1.25), limousin, p(45.84, 1.27)],
    );
    db::write_items(&pool, std::slice::from_ref(&old), &[])
        .await
        .unwrap();
    let app_role = as_role(&pool, "SET ROLE lunaway_app").await;
    let app = lunaway_api::router(ApiState::new(app_role.clone(), ApiConfig::default()));
    let (_, body) = gql(&app, json!({})).await;
    let none = body["data"]["enforcement"].clone();
    let (_, body) = gql(&app, json!({"exactIn": ["FR"]})).await;
    let fr = body["data"]["enforcement"].clone();
    for e in [&none, &fr] {
        assert_eq!(ids(&e["upserts"]), [old.id.to_string()], "{e}");
    }

    let now_default = for_choice(
        Item {
            id: Uuid::now_v7(),
            content_hash: "built again".to_owned(),
            ..old.clone()
        },
        Variant::Default,
    );
    let point = for_choice(
        camera("securite-routiere/1001", "FR", limousin),
        Variant::OptIn,
    );
    db::write_items(&pool, &[now_default, point.clone()], &[])
        .await
        .unwrap();
    // The head is read at most every five seconds: a new state reads it.
    let app = lunaway_api::router(ApiState::new(app_role, ApiConfig::default()));
    let (_, body) = gql(&app, json!({"since": none["cursor"]})).await;
    let e = &body["data"]["enforcement"];
    assert_eq!(e["full"], false, "{body}");
    assert_eq!(
        ids(&e["upserts"]),
        [old.id.to_string()],
        "the zone, its id kept, for the client without the choice"
    );
    assert!(!ids(&e["removals"]).contains(&old.id.to_string()));
    let (_, body) = gql(&app, json!({"since": fr["cursor"], "exactIn": ["FR"]})).await;
    let e = &body["data"]["enforcement"];
    assert_eq!(e["full"], false, "{body}");
    assert_eq!(ids(&e["upserts"]), [point.id.to_string()]);
    assert_eq!(
        ids(&e["removals"]),
        [old.id.to_string()],
        "the zone the client held goes"
    );
}

/// An engine that answers along a straight road through the locations.
struct Straight;

impl Engine for Straight {
    async fn route(&self, body: &Value) -> Result<Option<Value>, MatchError> {
        let points: Vec<Position> = body["locations"]
            .as_array()
            .unwrap()
            .iter()
            .map(|l| p(l["lat"].as_f64().unwrap(), l["lon"].as_f64().unwrap()))
            .collect();
        let distance: f64 = points.windows(2).map(|w| w[0].distance_m(w[1])).sum();
        Ok(Some(json!({
            "code": "Ok",
            "routes": [{
                "geometry": polyline::encode(&points),
                "distance": distance,
                "legs": [{"steps": [{"distance": distance, "intersections": [{"classes": []}]}]}],
            }],
        })))
    }
}

/// A writer the test reads back, for the log assertions.
#[derive(Clone, Default)]
struct Captured(std::sync::Arc<std::sync::Mutex<Vec<u8>>>);

impl std::io::Write for Captured {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.0.lock().unwrap().extend_from_slice(buf);
        Ok(buf.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

fn device(id: &str, lat: f64, lon: f64) -> Device {
    Device {
        external_id: id.to_owned(),
        kind: DeviceKind::Fixed,
        position: p(lat, lon),
        bearing_deg: None,
        limit_kmh: None,
        road: None,
        section_end: None,
        section_length_m: None,
    }
}

/// The build with the import role, the API with its own: each client gets
/// the form of its choice, and the choice leaves no trace in the logs.
#[sqlx::test(migrations = "../../migrations")]
async fn the_build_and_the_api_under_their_roles_serve_each_client_its_form(pool: PgPool) {
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let now = Utc::now();
    let raw = json!({});
    let limousin = device("1001", 45.8336, 1.2611);
    db::upsert_devices(
        &ingest,
        &SourceId::SECURITE_ROUTIERE,
        &[NewDevice {
            device: &limousin,
            country: "FR",
            scope: "FR",
            raw: &raw,
        }],
        now,
    )
    .await
    .unwrap();
    let others = [
        (device("node/12", 43.3399, -1.7808), "ES"),
        (device("node/2", 52.52, 13.405), "DE"),
        (device("node/4", 34.02, -6.84), "MA"),
    ];
    db::upsert_devices(
        &ingest,
        &SourceId::OSM,
        &others
            .iter()
            .map(|(d, c)| NewDevice {
                device: d,
                country: c,
                scope: c,
                raw: &raw,
            })
            .collect::<Vec<_>>(),
        now,
    )
    .await
    .unwrap();
    let report = lunaway_ingest::enforcement::build(
        &ingest,
        &Straight,
        b"a test secret of the zone builder",
        false,
        false,
    )
    .await
    .unwrap();
    assert_eq!(
        (report.zones, report.opt_in, report.off),
        (2, 2, 1),
        "{report:?}"
    );

    let app_role = as_role(&pool, "SET ROLE lunaway_app").await;
    let app = lunaway_api::router(ApiState::new(app_role, ApiConfig::default()));
    let captured = Captured::default();
    let writer = captured.clone();
    let subscriber = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::TRACE)
        .with_writer(move || writer.clone())
        .with_ansi(false)
        .finish();
    let guard = tracing::subscriber::set_default(subscriber);
    let (_, body) = gql(&app, json!({})).await;
    let none = body["data"]["enforcement"].clone();
    let (_, body) = gql(&app, json!({"exactIn": ["FR"]})).await;
    let fr = body["data"]["enforcement"].clone();
    let (_, body) = gql(&app, json!({"since": none["cursor"], "exactIn": ["FR"]})).await;
    assert_eq!(body["data"]["enforcement"]["full"], true);
    let (_, refused) = gql(&app, json!({"exactIn": ["Q7"]})).await;
    drop(guard);

    let forms = |delta: &Value| -> Vec<(String, String, bool)> {
        let mut out: Vec<(String, String, bool)> = delta["upserts"]
            .as_array()
            .unwrap()
            .iter()
            .map(|u| {
                (
                    u["country"].as_str().unwrap().to_owned(),
                    u["kind"].as_str().unwrap().to_owned(),
                    u["lat"].is_number(),
                )
            })
            .collect();
        out.sort();
        out
    };
    let item = |c: &str, k: &str, point: bool| (c.to_owned(), k.to_owned(), point);
    assert_eq!(
        forms(&none),
        [
            item("DE", "CAMERA", true),
            item("ES", "ZONE", false),
            item("FR", "ZONE", false)
        ],
        "without the choice, no French point, none within a kilometre of France: {none}"
    );
    assert_eq!(
        forms(&fr),
        [
            item("DE", "CAMERA", true),
            item("ES", "CAMERA", true),
            item("FR", "CAMERA", true)
        ],
        "with it, points and no French zone: {fr}"
    );
    let french = fr["upserts"]
        .as_array()
        .unwrap()
        .iter()
        .find(|u| u["country"] == "FR")
        .unwrap();
    assert!((french["lat"].as_f64().unwrap() - 45.8336).abs() < 1e-9);
    assert_eq!(french["category"], "FIXED");
    assert_eq!(refused["errors"][0]["extensions"]["code"], "INVALID_INPUT");

    let logs = String::from_utf8(captured.0.lock().unwrap().clone()).unwrap();
    assert!(
        logs.contains("path=/graphql") && logs.contains("enforcement_items"),
        "the requests and their statements are logged, at every level: {logs}"
    );
    // The statements' text is the same for every client; no bound value
    // is logged.
    for trace in ["exactIn", "exact_in", "Q7", "\"FR\"", "[FR]", "\\\"FR\\\""] {
        assert!(
            !logs.contains(trace),
            "the user's choice is neither logged nor kept ({trace}): {logs}"
        );
    }
}
