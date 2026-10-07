//! The road events poller against a local server playing the DIR and
//! DiaLog: the aggregate, then the increments from the aggregate's number,
//! the cursor stored and resumed, an end marker applied, a dataset whose
//! order disappears; then the matching on a fake routing engine.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::{
    net::SocketAddr,
    sync::{Arc, Mutex},
    time::Duration,
};

use axum::{
    Router,
    extract::State,
    http::{HeaderMap, StatusCode, Uri},
    response::{IntoResponse, Response},
    routing::any,
};
use chrono::{TimeZone, Utc};
use lunaway_db::{
    PgPool, road_events as db,
    routing::{self as graphs, NewGraph},
};
use lunaway_domain::{Position, road_events::EventDirection, routing::polyline};
use lunaway_ingest::{
    cache::Cache,
    http::{self, RetryPolicy},
    road_events::{
        matching::{self, Engine, MatchError},
        poll::{self, DirState, PollConfig},
    },
};
use serde_json::{Value, json};

const DIR_CONTENT: &str = include_str!("fixtures/road_events/dir_content_excerpt.xml");
const DIALOG: &str = include_str!("fixtures/road_events/dialog_temporary_excerpt.xml");
const DGT: &str = include_str!("fixtures/road_events/dgt_excerpt.xml");
const NDW: &[u8] = include_bytes!("fixtures/road_events/ndw_planning_excerpt.xml");
const COTES_D_ARMOR: &str = include_str!("fixtures/road_events/cotes_d_armor_excerpt.geojson");

/// The Côtes-d'Armor's orders repeated, under new ids, until they fill the
/// page the export is asked with.
fn cotes_d_armor_full_page() -> String {
    let mut collection: Value = serde_json::from_str(COTES_D_ARMOR).unwrap();
    let features = collection["features"].as_array().unwrap().clone();
    let page: Vec<Value> = (0..lunaway_ingest::road_events::local::COTES_D_ARMOR_PAGE)
        .map(|i| {
            let mut f = features[i % features.len()].clone();
            f["id"] = json!(format!("page-{i}"));
            f
        })
        .collect();
    collection["features"] = Value::Array(page);
    collection.to_string()
}

/// NDW's file as it is served: gzip, without `Content-Encoding`.
fn ndw_gz() -> Vec<u8> {
    use std::io::Write as _;
    let mut z = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
    z.write_all(NDW).unwrap();
    z.finish().unwrap()
}

/// The night closure of the N20 (record 260122-001799-2) ended by a new
/// version of its situation, as an increment.
fn increment_ending_the_n20() -> String {
    let start = DIR_CONTENT
        .find("<ns2:situation id=\"260122-001799\"")
        .unwrap();
    let end =
        start + DIR_CONTENT[start..].find("</ns2:situation>").unwrap() + "</ns2:situation>".len();
    let situation = DIR_CONTENT[start..end]
        .replace("version=\"1\"", "version=\"2\"")
        .replace(
            "id=\"260122-001799-2\" version=\"2\">",
            "id=\"260122-001799-2\" version=\"2\"><ns2:management><ns2:lifeCycleManagement><ns2:end>true</ns2:end></ns2:lifeCycleManagement></ns2:management>",
        );
    let head_end = DIR_CONTENT.find("<ns2:situation ").unwrap();
    let head = DIR_CONTENT[..head_end]
        .replace(
            "<ns2:updateMethod>snapshot</ns2:updateMethod>",
            "<ns2:updateMethod>allElementUpdate</ns2:updateMethod>",
        )
        .replace(
            "2026-10-06T12:57:45.691+02:00",
            "2026-10-06T13:01:00.000+02:00",
        );
    let tail = &DIR_CONTENT[DIR_CONTENT.rfind("</ns2:payloadPublication>").unwrap()..];
    format!("{head}{situation}{tail}")
}

#[derive(Clone)]
struct Feeds {
    dialog: Arc<Mutex<String>>,
    seen: Arc<Mutex<Vec<String>>>,
    /// Whether increment 3572541 is published broken.
    broken: Arc<Mutex<bool>>,
}

async fn serve(State(f): State<Feeds>, uri: Uri, headers: HeaderMap) -> Response {
    let path = uri.path().to_owned();
    let ua = headers
        .get("user-agent")
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default()
        .to_owned();
    assert!(
        ua.ends_with("(+https://lunaway.net)"),
        "an honest User-Agent: {ua}"
    );
    f.seen.lock().unwrap().push(path.clone());
    match path.as_str() {
        "/dir/content.xml" => {
            if headers.get("if-none-match").and_then(|v| v.to_str().ok()) == Some("\"a1\"") {
                return StatusCode::NOT_MODIFIED.into_response();
            }
            ([("etag", "\"a1\"")], DIR_CONTENT.to_owned()).into_response()
        }
        "/dir/3572540.xml" | "/dir/3572543.xml" => increment_ending_the_n20().into_response(),
        "/dir/3572541.xml" if *f.broken.lock().unwrap() => "<not-datex".into_response(),
        "/dialog" => f.dialog.lock().unwrap().clone().into_response(),
        "/dgt" => DGT.to_owned().into_response(),
        "/ndw.xml.gz" => ([("content-type", "application/xml")], ndw_gz()).into_response(),
        "/cotes-d-armor" => cotes_d_armor_full_page().into_response(),
        _ => StatusCode::NOT_FOUND.into_response(),
    }
}

async fn feeds() -> (Feeds, SocketAddr) {
    let f = Feeds {
        dialog: Arc::new(Mutex::new(DIALOG.to_owned())),
        seen: Arc::new(Mutex::new(Vec::new())),
        broken: Arc::new(Mutex::new(false)),
    };
    let app = Router::new().fallback(any(serve)).with_state(f.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    (f, addr)
}

fn config(addr: SocketAddr) -> PollConfig {
    PollConfig {
        dir_base: format!("http://{addr}/dir/"),
        dir_hosts: vec!["127.0.0.1".into()],
        dir_pace: Duration::ZERO,
        dialog_url: format!("http://{addr}/dialog"),
        dialog_hosts: vec!["127.0.0.1".into()],
        dgt_url: format!("http://{addr}/dgt"),
        dgt_hosts: vec!["127.0.0.1".into()],
        ndw_url: format!("http://{addr}/ndw.xml.gz"),
        ndw_hosts: vec!["127.0.0.1".into()],
        local: Vec::new(),
        retry: RetryPolicy {
            min_delay: Duration::from_millis(5),
            max_delay: Duration::from_millis(20),
            max_retries: 1,
        },
        ..PollConfig::default()
    }
}

async fn ended(pool: &PgPool, id: &str) -> Option<String> {
    sqlx::query_scalar!(
        "SELECT end_reason FROM road_events WHERE external_id = $1",
        id
    )
    .fetch_one(pool)
    .await
    .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_dir_feed_is_read_whole_then_followed_and_resumed(pool: PgPool) {
    let (f, addr) = feeds().await;
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let client = http::client_allowing_plain_http().unwrap();
    let engine: Option<&matching::Valhalla> = None;
    let report = poll::poll(&pool, &client, &cache, &config(addr), engine)
        .await
        .unwrap();
    let r = &report.sources["dir"];
    assert!(r.error.is_none(), "{:?}", r.error);
    assert!(r.full);
    assert_eq!(
        r.increments, 1,
        "the increment numbered as the aggregate is newer than it"
    );
    assert_eq!(
        ended(&pool, "260122-001799-2").await.as_deref(),
        Some("source_end"),
        "the increment's end marker ends the closure"
    );
    assert_eq!(ended(&pool, "260122-001799-1").await, None);
    assert_eq!(
        ended(&pool, "260927-005546-103").await.as_deref(),
        Some("source_end"),
        "an end marker in the aggregate"
    );
    let feed = db::feed(&pool, "dir").await.unwrap().unwrap();
    let state: DirState = serde_json::from_value(feed.state).unwrap();
    assert_eq!(state.next, Some(3_572_541));
    assert_eq!(state.etag.as_deref(), Some("\"a1\""));
    assert!(
        cache
            .read("road-events/dir/content.xml")
            .await
            .unwrap()
            .is_some()
    );
    // DiaLog too: due at the first pass.
    assert!(report.sources["dialog"].error.is_none());
    assert_eq!(db::live_count(&pool, "dialog").await.unwrap(), 6);

    // The next pass, three minutes later: the aggregate is not due, the
    // poller resumes at the next increment and finds none yet.
    f.seen.lock().unwrap().clear();
    let report = poll::poll(&pool, &client, &cache, &config(addr), engine)
        .await
        .unwrap();
    let seen = f.seen.lock().unwrap().clone();
    assert!(!seen.contains(&"/dir/content.xml".to_owned()), "{seen:?}");
    assert_eq!(
        seen.first().map(String::as_str),
        Some("/dir/3572541.xml"),
        "resumed from the stored cursor"
    );
    assert_eq!(report.sources["dir"].increments, 0);
    assert!(
        !report.sources.contains_key("dialog"),
        "DiaLog is read every 15 minutes"
    );

    // 3572541 and 3572542 never come; after a quarter of an hour of waiting
    // the poller looks past them and resumes at 3572543.
    let feed = db::feed(&pool, "dir").await.unwrap().unwrap();
    let mut state: DirState = serde_json::from_value(feed.state).unwrap();
    assert!(
        state.waiting_since.is_some(),
        "the wait for 3572541 is remembered"
    );
    state.waiting_since = Some(Utc::now() - chrono::Duration::minutes(20));
    let read = db::Read {
        state: &serde_json::to_value(&state).unwrap(),
        full: false,
        data_at: None,
    };
    db::record_read(&pool, "dir", Utc::now(), Ok(read))
        .await
        .unwrap();
    let report = poll::poll(&pool, &client, &cache, &config(addr), engine)
        .await
        .unwrap();
    assert_eq!(report.sources["dir"].increments, 1, "the gap is skipped");
    let feed = db::feed(&pool, "dir").await.unwrap().unwrap();
    let state: DirState = serde_json::from_value(feed.state).unwrap();
    assert_eq!(state.next, Some(3_572_544));

    // Forced: the aggregate is asked conditionally and has not changed.
    f.seen.lock().unwrap().clear();
    let mut forced = config(addr);
    forced.force = true;
    forced.only = vec!["dialog".into()];
    // An order disappears from DiaLog: it ended.
    let gone = {
        let start = DIALOG.find("<trafficRegulationOrder ").unwrap();
        let end = start
            + DIALOG[start..].find("</trafficRegulationOrder>").unwrap()
            + "</trafficRegulationOrder>".len();
        format!("{}{}", &DIALOG[..start], &DIALOG[end..])
    };
    *f.dialog.lock().unwrap() = gone;
    let report = poll::poll(&pool, &client, &cache, &forced, engine)
        .await
        .unwrap();
    assert_eq!(
        report.sources["dialog"].ended, 1,
        "an order DiaLog no longer lists is over"
    );
    assert_eq!(db::live_count(&pool, "dialog").await.unwrap(), 5);
}

#[sqlx::test(migrations = "../../migrations")]
async fn what_was_applied_before_a_failure_is_not_read_again(pool: PgPool) {
    let (f, addr) = feeds().await;
    *f.broken.lock().unwrap() = true;
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let client = http::client_allowing_plain_http().unwrap();
    let engine: Option<&matching::Valhalla> = None;
    let mut only_dir = config(addr);
    only_dir.only = vec!["dir".into()];
    let report = poll::poll(&pool, &client, &cache, &only_dir, engine)
        .await
        .unwrap();
    assert!(
        report.sources["dir"].error.is_some(),
        "a broken increment fails the pass"
    );
    assert_eq!(
        ended(&pool, "260122-001799-2").await.as_deref(),
        Some("source_end"),
        "the increment before it was applied"
    );
    let feed = db::feed(&pool, "dir").await.unwrap().unwrap();
    let state: DirState = serde_json::from_value(feed.state).unwrap();
    assert_eq!(
        state.next,
        Some(3_572_541),
        "the next pass resumes after the increment applied, not before it"
    );
    assert_eq!(
        state.etag.as_deref(),
        Some("\"a1\""),
        "the aggregate applied is not downloaded again"
    );
    assert!(feed.data_at.is_some(), "the data applied is current");
}

/// A routing engine that drives straight through the points asked, on a
/// road numbered N 20 and A 75.
struct Straight;

impl Engine for Straight {
    async fn route(&self, body: &Value) -> Result<Option<Value>, MatchError> {
        let points: Vec<Position> = body["locations"]
            .as_array()
            .unwrap()
            .iter()
            .map(|l| Position::new(l["lat"].as_f64().unwrap(), l["lon"].as_f64().unwrap()).unwrap())
            .collect();
        let distance: f64 = points.windows(2).map(|w| w[0].distance_m(w[1])).sum();
        Ok(Some(json!({
            "code": "Ok",
            "waypoints": [{"distance": 1.0}, {"distance": 1.0}],
            "routes": [{
                "geometry": polyline::encode(&points),
                "distance": distance,
                "legs": [{"steps": [{"distance": distance, "ref": "N 20; A 75"}]}]
            }]
        })))
    }
}

/// [`Straight`], except for the lines that start or end within 50 m of
/// `refuse_near`, which it refuses as Valhalla refused real ones in
/// production; it counts the requests it receives.
struct Picky {
    refuse_near: Option<Position>,
    calls: std::sync::atomic::AtomicUsize,
}

impl Engine for Picky {
    async fn route(&self, body: &Value) -> Result<Option<Value>, MatchError> {
        self.calls.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        let ends: Vec<Position> = body["locations"]
            .as_array()
            .unwrap()
            .iter()
            .map(|l| Position::new(l["lat"].as_f64().unwrap(), l["lon"].as_f64().unwrap()).unwrap())
            .collect();
        let refused = match self.refuse_near {
            Some(at) => ends.iter().any(|e| e.distance_m(at) < 50.0),
            None => true,
        };
        if refused {
            return Err(MatchError::Refused(
                "HTTP 400 error 154: Insufficient number of locations provided".into(),
            ));
        }
        Straight.route(body).await
    }
}

/// [`Straight`], counting the requests with a point in the Netherlands and
/// in Spain.
#[derive(Default)]
struct Abroad {
    dutch: std::sync::atomic::AtomicUsize,
    spanish: std::sync::atomic::AtomicUsize,
}

impl Engine for Abroad {
    async fn route(&self, body: &Value) -> Result<Option<Value>, MatchError> {
        let points: Vec<Position> = body["locations"]
            .as_array()
            .unwrap()
            .iter()
            .map(|l| Position::new(l["lat"].as_f64().unwrap(), l["lon"].as_f64().unwrap()).unwrap())
            .collect();
        let within = |path: &str| {
            let region = lunaway_domain::routing::coverage::region(path).unwrap();
            points.iter().any(|p| region.contains(*p))
        };
        if within("europe/netherlands") {
            self.dutch.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        }
        if within("europe/spain") {
            self.spanish
                .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        }
        Straight.route(body).await
    }
}

async fn graph(pool: &PgPool, id: &str) {
    graphs::load_graph(
        pool,
        &NewGraph {
            id: id.into(),
            osm_data_at: Utc.with_ymd_and_hms(2026, 10, 5, 20, 0, 0).unwrap(),
            ign_fetched_at: None,
            ign_edition: None,
            built_at: Utc.with_ymd_and_hms(2026, 10, 6, 3, 0, 0).unwrap(),
            engine: "valhalla 3.9.0".into(),
            stats: json!({}),
        },
        &[],
    )
    .await
    .unwrap();
    graphs::activate(pool, id).await.unwrap();
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_line_the_engine_refuses_waits_and_the_others_are_placed(pool: PgPool) {
    let (_, addr) = feeds().await;
    let dir = tempfile::tempdir().unwrap();
    let client = http::client_allowing_plain_http().unwrap();
    let mut only_dir = config(addr);
    only_dir.only = vec!["dir".into()];
    let engine: Option<&matching::Valhalla> = None;
    poll::poll(&pool, &client, &Cache::new(dir.path()), &only_dir, engine)
        .await
        .unwrap();
    graph(&pool, "20261006T0300Z-fr").await;
    let start = sqlx::query!(
        r#"SELECT ST_Y(ST_StartPoint(geom_source::geometry)) AS "lat!",
                  ST_X(ST_StartPoint(geom_source::geometry)) AS "lon!"
           FROM road_events WHERE external_id = '260122-001799-1'"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    let picky = Picky {
        refuse_near: Some(Position::new(start.lat, start.lon).unwrap()),
        calls: 0.into(),
    };
    let report = matching::match_pending(&pool, &picky, 100, Duration::from_secs(30))
        .await
        .unwrap();
    assert!(
        report.refused >= 1,
        "the N20's lines, refused, are counted: {report:?}"
    );
    assert!(
        report.matched >= 1,
        "the events after the refused one are placed in the same pass: {report:?}"
    );
    let refused = || async {
        sqlx::query!(
            r#"SELECT match_quality, match_error, match_attempts,
                      match_retry_at > now() + interval '20 minutes' AS "later?"
               FROM road_events WHERE external_id = '260122-001799-1'"#
        )
        .fetch_one(&pool)
        .await
        .unwrap()
    };
    let r = refused().await;
    assert_eq!(
        r.match_quality, "unmatched",
        "left unplaced: it warns where it is"
    );
    assert!(r.match_error.unwrap().contains("error 154"));
    assert_eq!((r.match_attempts, r.later), (1, Some(true)));

    let calls = picky.calls.load(std::sync::atomic::Ordering::SeqCst);
    let again = matching::match_pending(&pool, &picky, 100, Duration::from_secs(30))
        .await
        .unwrap();
    assert_eq!(
        (
            again.refused,
            picky.calls.load(std::sync::atomic::Ordering::SeqCst)
        ),
        (0, calls),
        "a refused line is not asked again at every pass"
    );
    // Due again twice, refused twice: then it waits for the next graph.
    for attempts in [2, 3] {
        sqlx::query!(
            "UPDATE road_events SET match_retry_at = now() - interval '1 minute'
             WHERE external_id = '260122-001799-1'"
        )
        .execute(&pool)
        .await
        .unwrap();
        let r = matching::match_pending(&pool, &picky, 100, Duration::from_secs(30))
            .await
            .unwrap();
        assert_eq!(r.refused, 1);
        assert_eq!(refused().await.match_attempts, attempts);
    }
    let r = refused().await;
    assert_eq!(
        r.later, None,
        "after three refusals, no retry on this graph"
    );
    graph(&pool, "20261013T0300Z-fr").await;
    let on_new_graph = matching::match_pending(&pool, &Straight, 100, Duration::from_secs(30))
        .await
        .unwrap();
    assert!(on_new_graph.matched >= 2, "{on_new_graph:?}");
    let r = refused().await;
    assert_eq!(
        (r.match_quality.as_str(), r.match_error, r.match_attempts),
        ("matched", None, 0),
        "a new graph asks every line again"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_engine_that_refuses_everything_stops_the_pass(pool: PgPool) {
    let (_, addr) = feeds().await;
    let dir = tempfile::tempdir().unwrap();
    let client = http::client_allowing_plain_http().unwrap();
    let engine: Option<&matching::Valhalla> = None;
    poll::poll(
        &pool,
        &client,
        &Cache::new(dir.path()),
        &config(addr),
        engine,
    )
    .await
    .unwrap();
    graph(&pool, "20261006T0300Z-fr").await;
    let waiting: i64 = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM road_events WHERE match_quality = 'pending'"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(waiting > 5, "the fixtures hold enough lines: {waiting}");
    let broken = Picky {
        refuse_near: None,
        calls: 0.into(),
    };
    let report = matching::match_pending(&pool, &broken, 100, Duration::from_secs(30))
        .await
        .unwrap();
    assert_eq!(
        (report.refused, report.more),
        (5, true),
        "five refusals in a row are the engine's fault: the pass stops"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn sections_are_placed_on_their_road_in_their_direction(pool: PgPool) {
    let (_, addr) = feeds().await;
    let dir = tempfile::tempdir().unwrap();
    let client = http::client_allowing_plain_http().unwrap();
    let mut only_dir = config(addr);
    only_dir.only = vec!["dir".into()];
    let engine: Option<&matching::Valhalla> = None;
    poll::poll(&pool, &client, &Cache::new(dir.path()), &only_dir, engine)
        .await
        .unwrap();
    graphs::load_graph(
        &pool,
        &NewGraph {
            id: "20261006T0300Z-fr".into(),
            osm_data_at: Utc.with_ymd_and_hms(2026, 10, 5, 20, 0, 0).unwrap(),
            ign_fetched_at: None,
            ign_edition: None,
            built_at: Utc.with_ymd_and_hms(2026, 10, 6, 3, 0, 0).unwrap(),
            engine: "valhalla 3.9.0".into(),
            stats: json!({}),
        },
        &[],
    )
    .await
    .unwrap();
    graphs::activate(&pool, "20261006T0300Z-fr").await.unwrap();
    let report = matching::match_pending(&pool, &Straight, 100, Duration::from_secs(30))
        .await
        .unwrap();
    assert!(report.matched >= 2 && report.unmatched >= 1, "{report:?}");
    let row = |id: &'static str| {
        let pool = pool.clone();
        async move {
            sqlx::query!(
                r#"SELECT match_quality, direction,
                   ST_NumGeometries(geom_matched::geometry) AS lines
                   FROM road_events WHERE external_id = $1"#,
                id
            )
            .fetch_one(&pool)
            .await
            .unwrap()
        }
    };
    let both = row("260122-001799-1").await;
    assert_eq!(both.match_quality, "matched");
    assert_eq!(both.direction, EventDirection::Both.code());
    assert_eq!(
        both.lines,
        Some(2),
        "both carriageways, each in its driving order"
    );
    let one_way = row("260927-005546-1").await;
    assert_eq!(one_way.match_quality, "matched");
    assert_eq!(
        one_way.lines,
        Some(1),
        "a northbound section covers its own carriageway"
    );
    let other_road = row("260928-001439-102").await;
    assert_eq!(
        other_road.match_quality, "unmatched",
        "a route on another road number is not the N94's closure"
    );
    let ramp = row("260113-001342-1").await;
    assert_eq!(
        ramp.match_quality, "ramp",
        "slip road events are never matched as lines"
    );
    assert_eq!(ramp.lines, None);
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_dutch_and_spanish_feeds_are_read_and_placed_on_the_europe_graph(pool: PgPool) {
    let (f, addr) = feeds().await;
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let client = http::client_allowing_plain_http().unwrap();
    let engine: Option<&matching::Valhalla> = None;
    let report = poll::poll(&pool, &client, &cache, &config(addr), engine)
        .await
        .unwrap();
    assert!(
        report.sources["dgt"].error.is_none(),
        "{:?}",
        report.sources["dgt"].error
    );
    assert!(
        !report.sources.contains_key("ndw"),
        "NDW's 200 MB file is read by its own unit only"
    );
    assert!(!f.seen.lock().unwrap().contains(&"/ndw.xml.gz".to_owned()));
    let mut ndw_only = config(addr);
    ndw_only.only = vec!["ndw".into()];
    let report = poll::poll(&pool, &client, &cache, &ndw_only, engine)
        .await
        .unwrap();
    let r = &report.sources["ndw"];
    assert!(r.error.is_none(), "{:?}", r.error);
    assert!(r.full, "a complete snapshot");
    assert!(db::live_count(&pool, "ndw").await.unwrap() > 0);
    assert!(db::live_count(&pool, "dgt").await.unwrap() > 0);
    let feed = db::feed(&pool, "ndw").await.unwrap().unwrap();
    assert_eq!(
        feed.data_at,
        Some(
            Utc.with_ymd_and_hms(2026, 10, 6, 10, 45, 0).unwrap()
                + chrono::Duration::microseconds(636)
        ),
        "current as of the file's publication"
    );
    assert!(
        cache
            .read("road-events/ndw/planning.xml.gz")
            .await
            .unwrap()
            .is_some_and(|c| c.bytes.starts_with(&[0x1f, 0x8b])),
        "the file is kept compressed"
    );

    graph(&pool, "20261006T2326Z-eu").await;
    let watch = Abroad::default();
    matching::match_pending(&pool, &watch, 10_000, Duration::from_secs(60))
        .await
        .unwrap();
    assert!(
        watch.dutch.load(std::sync::atomic::Ordering::SeqCst) > 0
            && watch.spanish.load(std::sync::atomic::Ordering::SeqCst) > 0,
        "the graph covers the Netherlands and Spain: their lines are placed on it"
    );
    let waiting: i64 = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM road_events
           WHERE source IN ('ndw', 'dgt') AND match_quality = 'pending'"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(waiting, 0, "every line was asked of the engine");
    let detours = sqlx::query!(
        r#"SELECT count(*) AS "all!", count(matched_graph_id) AS "asked!" FROM road_events
           WHERE source = 'ndw' AND class = 'detour'"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(detours.all > 0, "the fixture holds detours");
    assert_eq!(
        detours.asked, 0,
        "a detour is shown with its route, never placed on the graph"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_failing_feed_waits_its_pace_before_it_is_asked_again(pool: PgPool) {
    let (f, addr) = feeds().await;
    *f.dialog.lock().unwrap() = "<not-datex".to_owned();
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let client = http::client_allowing_plain_http().unwrap();
    let engine: Option<&matching::Valhalla> = None;
    let mut only_dialog = config(addr);
    only_dialog.only = vec!["dialog".into()];
    let report = poll::poll(&pool, &client, &cache, &only_dialog, engine)
        .await
        .unwrap();
    assert!(
        report.sources["dialog"].error.is_some(),
        "a broken export fails"
    );
    f.seen.lock().unwrap().clear();
    let report = poll::poll(&pool, &client, &cache, &only_dialog, engine)
        .await
        .unwrap();
    assert!(
        !report.sources.contains_key("dialog") && f.seen.lock().unwrap().is_empty(),
        "three minutes later, a feed that failed is not asked again before its 15 minutes"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_export_that_fills_its_page_is_not_applied(pool: PgPool) {
    let (_f, addr) = feeds().await;
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let client = http::client_allowing_plain_http().unwrap();
    let engine: Option<&matching::Valhalla> = None;
    let mut only = config(addr);
    only.local = vec![poll::LocalConfig {
        id: "cotes-d-armor".into(),
        url: format!("http://{addr}/cotes-d-armor"),
        hosts: vec!["127.0.0.1".into()],
        format: lunaway_ingest::road_events::local::Format::CotesDArmorOrders,
    }];
    only.only = vec!["cotes-d-armor".into()];
    let report = poll::poll(&pool, &client, &cache, &only, engine)
        .await
        .unwrap();
    let error = report.sources["cotes-d-armor"]
        .error
        .as_deref()
        .unwrap_or_default();
    assert!(
        error.contains("filled its page"),
        "a full page may have more orders after it: {error:?}"
    );
    let stored: i64 = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM road_events WHERE source = 'cotes-d-armor'"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        stored, 0,
        "read as a complete snapshot, a truncated page would end the orders past it"
    );
    let asked = lunaway_ingest::road_events::local::FEEDS
        .iter()
        .find(|f| f.id == "cotes-d-armor")
        .unwrap()
        .url;
    assert!(
        asked.contains(&format!(
            "size={}&",
            lunaway_ingest::road_events::local::COTES_D_ARMOR_PAGE
        )),
        "the page checked is the page asked: {asked}"
    );
}
