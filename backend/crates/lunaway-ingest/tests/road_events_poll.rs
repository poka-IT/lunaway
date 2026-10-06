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
