//! Fetching through a local server that plays Overpass, data.gouv.fr and the
//! geocoder: the User-Agent, the retries, and the cache that keeps a re-run
//! off the network.

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
    body::Bytes,
    extract::State,
    http::{HeaderMap, StatusCode, Uri},
    response::{IntoResponse, Response},
    routing::any,
};
use lunaway_ingest::{
    IngestError, atout_france,
    cache::Cache,
    geocode::{self, AddressQuery, GeocoderConfig},
    http::{self, RetryPolicy},
    osm::{self, OverpassConfig},
};

const OVERPASS: &[u8] = include_bytes!("fixtures/overpass_sample.json");
const ATOUT_CSV: &[u8] = include_bytes!("fixtures/atout_france_sample.csv");
const BAN_ANSWER: &[u8] = include_bytes!("fixtures/ban_answer_sample.csv");

const FAST: RetryPolicy = RetryPolicy {
    min_delay: Duration::from_millis(5),
    max_delay: Duration::from_millis(20),
    max_retries: 2,
};

/// What the server saw of one request.
#[derive(Debug, Clone)]
struct Seen {
    path: String,
    user_agent: String,
    content_type: String,
    body: Vec<u8>,
}

/// The answers a fake server gives, in order: status, extra headers, body.
type Script = Vec<(StatusCode, Vec<(&'static str, String)>, Vec<u8>)>;

/// A server answering each request with the next scripted response (the
/// last one repeats), recording what it received.
#[derive(Clone)]
struct Fake {
    script: Arc<Mutex<Script>>,
    seen: Arc<Mutex<Vec<Seen>>>,
}

async fn handle(State(f): State<Fake>, uri: Uri, headers: HeaderMap, body: Bytes) -> Response {
    let header = |name: &str| {
        headers
            .get(name)
            .and_then(|v| v.to_str().ok())
            .unwrap_or_default()
            .to_owned()
    };
    f.seen.lock().unwrap().push(Seen {
        path: uri.path().to_owned(),
        user_agent: header("user-agent"),
        content_type: header("content-type"),
        body: body.to_vec(),
    });
    let mut script = f.script.lock().unwrap();
    let (status, extra, bytes) = if script.len() > 1 {
        script.remove(0)
    } else {
        script[0].clone()
    };
    let mut response = (status, bytes).into_response();
    for (name, value) in extra {
        response.headers_mut().insert(name, value.parse().unwrap());
    }
    response
}

/// A server answering with `replies` (status and body), in order.
async fn serve(replies: Vec<(StatusCode, Vec<u8>)>) -> (Fake, SocketAddr) {
    serve_script(
        replies
            .into_iter()
            .map(|(status, body)| (status, Vec::new(), body))
            .collect(),
    )
    .await
}

async fn serve_script(script: Script) -> (Fake, SocketAddr) {
    let fake = Fake {
        script: Arc::new(Mutex::new(script)),
        seen: Arc::new(Mutex::new(Vec::new())),
    };
    let app = Router::new().fallback(any(handle)).with_state(fake.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    (fake, addr)
}

fn overpass_config(addr: SocketAddr) -> OverpassConfig {
    OverpassConfig {
        urls: vec![format!("http://{addr}/api/interpreter")],
        pace: Duration::ZERO,
        retry: FAST,
    }
}

fn region() -> osm::Region {
    osm::region("FR-PDL").unwrap()
}

#[tokio::test]
async fn overpass_is_asked_once_with_an_honest_user_agent_then_read_from_the_cache() {
    let (fake, addr) = serve(vec![
        (StatusCode::TOO_MANY_REQUESTS, b"rate limited".to_vec()),
        (StatusCode::OK, OVERPASS.to_vec()),
    ])
    .await;
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let client = http::client_allowing_plain_http().unwrap();
    let config = overpass_config(addr);

    let first = osm::fetch_region(&client, &cache, &config, region(), false)
        .await
        .unwrap();
    assert!(!first.cached);
    assert_eq!(first.body, OVERPASS);
    {
        let seen = fake.seen.lock().unwrap();
        assert_eq!(seen.len(), 2, "the 429 is retried once");
        let ua = &seen[1].user_agent;
        assert!(
            ua.starts_with("Lunaway/") && ua.ends_with("(+https://lunaway.net)"),
            "{ua}"
        );
        assert_eq!(seen[1].content_type, "application/x-www-form-urlencoded");
        let form = String::from_utf8_lossy(&seen[1].body);
        assert!(
            form.starts_with("data="),
            "the query goes in the data field: {form}"
        );
        assert!(form.contains("FR-PDL"), "the query names its region");
    }

    let again = osm::fetch_region(&client, &cache, &config, region(), false)
        .await
        .unwrap();
    assert!(again.cached);
    assert_eq!(again.body, OVERPASS);
    assert_eq!(
        fake.seen.lock().unwrap().len(),
        2,
        "a cached region costs no request"
    );

    let refreshed = osm::fetch_region(&client, &cache, &config, region(), true)
        .await
        .unwrap();
    assert!(!refreshed.cached);
    assert_eq!(fake.seen.lock().unwrap().len(), 3, "--refresh asks again");
}

#[tokio::test]
async fn an_incomplete_overpass_answer_is_retried_and_never_cached() {
    let incomplete = br#"{"remark":"runtime error: Query timed out in \"query\" at line 3 after 901 seconds.","elements":[]}"#;
    let (fake, addr) = serve(vec![(StatusCode::OK, incomplete.to_vec())]).await;
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let err = osm::fetch_region(
        &http::client_allowing_plain_http().unwrap(),
        &cache,
        &overpass_config(addr),
        region(),
        false,
    )
    .await
    .unwrap_err();
    assert!(
        matches!(err, IngestError::OverpassIncomplete { .. }),
        "{err}"
    );
    assert_eq!(
        fake.seen.lock().unwrap().len(),
        3,
        "first attempt and two retries"
    );
    assert!(
        !dir.path().join("osm").exists(),
        "a partial answer must not be read back as a complete one"
    );
}

#[tokio::test]
async fn a_client_error_is_not_retried() {
    let (fake, addr) = serve(vec![(StatusCode::BAD_REQUEST, b"parse error".to_vec())]).await;
    let dir = tempfile::tempdir().unwrap();
    let err = osm::fetch_region(
        &http::client_allowing_plain_http().unwrap(),
        &Cache::new(dir.path()),
        &overpass_config(addr),
        region(),
        false,
    )
    .await
    .unwrap_err();
    assert!(
        matches!(
            err,
            IngestError::Status {
                status: StatusCode::BAD_REQUEST,
                ..
            }
        ),
        "{err}"
    );
    assert_eq!(fake.seen.lock().unwrap().len(), 1);
}

fn queries() -> Vec<AddressQuery> {
    let parsed = atout_france::parse_csv(ATOUT_CSV).unwrap();
    atout_france::address_queries(&parsed.campsites)
}

#[tokio::test]
async fn geocoding_posts_a_csv_and_caches_the_answer() {
    let (fake, addr) = serve(vec![(StatusCode::OK, BAN_ANSWER.to_vec())]).await;
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let config = GeocoderConfig {
        url: format!("http://{addr}/geocodage"),
        chunk: 100,
        pace: Duration::ZERO,
        retry: FAST,
    };
    let client = http::client_allowing_plain_http().unwrap();
    let q = queries();
    let out = geocode::geocode(&client, &cache, &config, &q, false)
        .await
        .unwrap();
    assert_eq!(out.len(), q.len());
    {
        let seen = fake.seen.lock().unwrap();
        assert_eq!(seen.len(), 1);
        assert_eq!(seen[0].path, "/geocodage/search/csv/");
        assert!(seen[0].content_type.starts_with("multipart/form-data"));
        let body = String::from_utf8_lossy(&seen[0].body);
        assert!(
            body.contains("name=\"columns\""),
            "the address columns are named"
        );
        assert!(body.contains("key,adresse,code_postal,commune"));
    }
    let again = geocode::geocode(&client, &cache, &config, &q, false)
        .await
        .unwrap();
    assert_eq!(again, out);
    assert_eq!(
        fake.seen.lock().unwrap().len(),
        1,
        "the same addresses are not geocoded twice"
    );
    let refreshed = geocode::geocode(&client, &cache, &config, &q, true)
        .await
        .unwrap();
    assert_eq!(refreshed, out);
    assert_eq!(
        fake.seen.lock().unwrap().len(),
        2,
        "--refresh geocodes again, as the command's help says"
    );
}

#[tokio::test]
async fn a_short_geocoder_answer_is_an_error() {
    let header_only = b"key,latitude,longitude,result_score,result_type,result_label,result_citycode,result_status\n";
    let (_fake, addr) = serve(vec![(StatusCode::OK, header_only.to_vec())]).await;
    let dir = tempfile::tempdir().unwrap();
    let config = GeocoderConfig {
        url: format!("http://{addr}"),
        chunk: 100,
        pace: Duration::ZERO,
        retry: FAST,
    };
    let err = geocode::geocode(
        &http::client_allowing_plain_http().unwrap(),
        &Cache::new(dir.path()),
        &config,
        &queries(),
        false,
    )
    .await
    .unwrap_err();
    assert!(
        matches!(err, IngestError::Incomplete { got: 0, .. }),
        "{err}"
    );
}

#[tokio::test]
async fn the_atout_france_csv_is_found_through_the_data_gouv_api() {
    // The API answer points to a CSV on the same fake server.
    let (fake, addr) = serve(vec![(StatusCode::OK, Vec::new())]).await;
    let dataset = serde_json::json!({
        "resources": [
            {"url": format!("http://{addr}/static/hebergements_classes.csv"), "format": "csv",
             "last_modified": "2026-10-05T04:00:04+00:00"}
        ]
    });
    *fake.script.lock().unwrap() = vec![
        (StatusCode::OK, Vec::new(), dataset.to_string().into_bytes()),
        (StatusCode::OK, Vec::new(), ATOUT_CSV.to_vec()),
    ];
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let client = http::client_allowing_plain_http().unwrap();
    let api = format!("http://{addr}/api/1");
    let first = atout_france::fetch_csv(&client, &cache, &api, &["127.0.0.1"], FAST, false)
        .await
        .unwrap();
    assert!(!first.cached);
    assert_eq!(first.body, ATOUT_CSV);
    {
        let seen = fake.seen.lock().unwrap();
        assert_eq!(
            seen[0].path,
            format!("/api/1/datasets/{}/", atout_france::DATASET_ID)
        );
        assert_eq!(seen[1].path, "/static/hebergements_classes.csv");
    }
    assert!(
        dir.path()
            .join("atout-france/hebergements_classes-2026-10-05.csv")
            .exists()
    );
    let again = atout_france::fetch_csv(&client, &cache, &api, &["127.0.0.1"], FAST, false)
        .await
        .unwrap();
    assert!(again.cached);
    assert_eq!(
        fake.seen.lock().unwrap().len(),
        2,
        "a cached CSV costs no request"
    );
}

#[tokio::test]
async fn a_busy_instance_hands_over_to_the_next_one() {
    let (busy, busy_addr) = serve(vec![(StatusCode::GATEWAY_TIMEOUT, b"too busy".to_vec())]).await;
    let (healthy, healthy_addr) = serve(vec![(StatusCode::OK, OVERPASS.to_vec())]).await;
    let dir = tempfile::tempdir().unwrap();
    let config = OverpassConfig {
        urls: vec![
            format!("http://{busy_addr}/api/interpreter"),
            format!("http://{healthy_addr}/api/interpreter"),
        ],
        pace: Duration::ZERO,
        retry: FAST,
    };
    let payload = osm::fetch_region(
        &http::client_allowing_plain_http().unwrap(),
        &Cache::new(dir.path()),
        &config,
        region(),
        false,
    )
    .await
    .unwrap();
    assert_eq!(payload.body, OVERPASS);
    assert_eq!(
        busy.seen.lock().unwrap().len(),
        1,
        "the busy instance is asked once"
    );
    assert_eq!(
        healthy.seen.lock().unwrap().len(),
        1,
        "the retry goes to the next instance"
    );
}

#[tokio::test]
async fn retry_after_is_honoured_before_the_next_attempt() {
    let (fake, addr) = serve_script(vec![
        (
            StatusCode::TOO_MANY_REQUESTS,
            vec![("retry-after", "1".to_owned())],
            b"slow down".to_vec(),
        ),
        (StatusCode::OK, Vec::new(), OVERPASS.to_vec()),
    ])
    .await;
    let dir = tempfile::tempdir().unwrap();
    let started = std::time::Instant::now();
    osm::fetch_region(
        &http::client_allowing_plain_http().unwrap(),
        &Cache::new(dir.path()),
        &overpass_config(addr),
        region(),
        false,
    )
    .await
    .unwrap();
    assert_eq!(fake.seen.lock().unwrap().len(), 2);
    assert!(
        started.elapsed() >= Duration::from_secs(1),
        "the backoff of 5 ms must not cut the second the server asked for: {:?}",
        started.elapsed()
    );
}

#[tokio::test]
async fn a_retry_after_beyond_an_hour_stops_the_import() {
    let (fake, addr) = serve_script(vec![(
        StatusCode::SERVICE_UNAVAILABLE,
        vec![("retry-after", "86400".to_owned())],
        b"maintenance".to_vec(),
    )])
    .await;
    let dir = tempfile::tempdir().unwrap();
    let err = osm::fetch_region(
        &http::client_allowing_plain_http().unwrap(),
        &Cache::new(dir.path()),
        &overpass_config(addr),
        region(),
        false,
    )
    .await
    .unwrap_err();
    assert!(
        matches!(
            err,
            IngestError::Status {
                retry_after: Some(d),
                ..
            } if d == Duration::from_secs(86_400)
        ),
        "{err}"
    );
    assert_eq!(
        fake.seen.lock().unwrap().len(),
        1,
        "a source asking for a day off is not asked again"
    );
}

#[tokio::test]
async fn not_implemented_is_not_retried() {
    let (fake, addr) = serve(vec![(StatusCode::NOT_IMPLEMENTED, b"no".to_vec())]).await;
    let dir = tempfile::tempdir().unwrap();
    let err = osm::fetch_region(
        &http::client_allowing_plain_http().unwrap(),
        &Cache::new(dir.path()),
        &overpass_config(addr),
        region(),
        false,
    )
    .await
    .unwrap_err();
    assert!(matches!(err, IngestError::Status { .. }), "{err}");
    assert_eq!(fake.seen.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn the_import_client_refuses_plain_http() {
    let (fake, addr) = serve(vec![(StatusCode::OK, OVERPASS.to_vec())]).await;
    let dir = tempfile::tempdir().unwrap();
    let err = osm::fetch_region(
        &http::client().unwrap(),
        &Cache::new(dir.path()),
        &overpass_config(addr),
        region(),
        false,
    )
    .await
    .unwrap_err();
    assert!(matches!(err, IngestError::Http { .. }), "{err}");
    assert!(
        fake.seen.lock().unwrap().is_empty(),
        "nothing leaves the importer over plain HTTP"
    );
}

#[tokio::test]
async fn a_csv_location_on_another_host_is_not_fetched() {
    let (fake, addr) = serve(vec![(StatusCode::OK, Vec::new())]).await;
    let dataset = serde_json::json!({
        "resources": [
            {"url": format!("http://localhost:{}/static/hebergements_classes.csv", addr.port()),
             "format": "csv", "last_modified": "2026-10-05T04:00:04+00:00"}
        ]
    });
    *fake.script.lock().unwrap() =
        vec![(StatusCode::OK, Vec::new(), dataset.to_string().into_bytes())];
    let dir = tempfile::tempdir().unwrap();
    let err = atout_france::fetch_csv(
        &http::client_allowing_plain_http().unwrap(),
        &Cache::new(dir.path()),
        &format!("http://{addr}/api/1"),
        &["127.0.0.1"],
        FAST,
        false,
    )
    .await
    .unwrap_err();
    assert!(matches!(err, IngestError::UntrustedUrl { .. }), "{err}");
    assert_eq!(
        fake.seen.lock().unwrap().len(),
        1,
        "only the metadata was asked for"
    );
}

#[tokio::test]
async fn an_answer_larger_than_any_real_one_is_refused() {
    // 17 MB where a thousand addresses come back in about 330 KB.
    let (_fake, addr) = serve(vec![(StatusCode::OK, vec![b'a'; 17 * 1024 * 1024])]).await;
    let dir = tempfile::tempdir().unwrap();
    let config = GeocoderConfig {
        url: format!("http://{addr}"),
        chunk: 100,
        pace: Duration::ZERO,
        retry: FAST,
    };
    let err = geocode::geocode(
        &http::client_allowing_plain_http().unwrap(),
        &Cache::new(dir.path()),
        &config,
        &queries(),
        false,
    )
    .await
    .unwrap_err();
    assert!(matches!(err, IngestError::TooLarge { .. }), "{err}");
}

#[tokio::test]
async fn a_redirect_to_another_host_is_not_followed() {
    // The metadata's link answers with a redirect to a server outside the
    // sources' hosts ("localhost" here, against "127.0.0.1" first asked).
    let (elsewhere, elsewhere_addr) = serve(vec![(StatusCode::OK, ATOUT_CSV.to_vec())]).await;
    let (fake, addr) = serve(vec![(StatusCode::OK, Vec::new())]).await;
    let dataset = serde_json::json!({
        "resources": [
            {"url": format!("http://{addr}/r/1"), "format": "csv",
             "last_modified": "2026-10-05T04:00:04+00:00"}
        ]
    });
    *fake.script.lock().unwrap() = vec![
        (StatusCode::OK, Vec::new(), dataset.to_string().into_bytes()),
        (
            StatusCode::FOUND,
            vec![(
                "location",
                format!("http://localhost:{}/x.csv", elsewhere_addr.port()),
            )],
            Vec::new(),
        ),
    ];
    let dir = tempfile::tempdir().unwrap();
    let err = atout_france::fetch_csv(
        &http::client_allowing_plain_http().unwrap(),
        &Cache::new(dir.path()),
        &format!("http://{addr}/api/1"),
        &["127.0.0.1", "localhost"],
        FAST,
        false,
    )
    .await
    .unwrap_err();
    assert!(
        matches!(
            err,
            IngestError::Status {
                status: StatusCode::FOUND,
                ..
            }
        ),
        "{err}"
    );
    assert!(
        elsewhere.seen.lock().unwrap().is_empty(),
        "the other server is never contacted"
    );
}

/// A server that cuts its first answer short (a `Content-Length` it never
/// reaches, then a closed connection) and sends the whole body after.
async fn cutting_server(body: &'static [u8]) -> (SocketAddr, Arc<Mutex<usize>>) {
    use tokio::io::{AsyncReadExt as _, AsyncWriteExt as _};
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let served = Arc::new(Mutex::new(0_usize));
    let count = Arc::clone(&served);
    tokio::spawn(async move {
        loop {
            let Ok((mut socket, _)) = listener.accept().await else {
                return;
            };
            let n = {
                let mut c = count.lock().unwrap();
                *c += 1;
                *c
            };
            let mut request = [0_u8; 4096];
            let _ = socket.read(&mut request).await;
            let head = format!(
                "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n",
                body.len()
            );
            let _ = socket.write_all(head.as_bytes()).await;
            let sent = if n == 1 {
                &body[..body.len() / 2]
            } else {
                body
            };
            let _ = socket.write_all(sent).await;
            let _ = socket.shutdown().await;
        }
    });
    (addr, served)
}

#[tokio::test]
async fn a_body_cut_off_is_asked_again() {
    let body: &'static [u8] = br#"[{"id": 1, "latitude": "4365100", "longitude": "-269000"}]"#;
    let (addr, served) = cutting_server(body).await;
    let dir = tempfile::tempdir().unwrap();
    let config = lunaway_ingest::fuel::FuelConfig {
        url: format!("http://{addr}/export"),
        retry: FAST,
    };
    let (got, _, cached) = lunaway_ingest::fuel::fetch(
        &http::client_allowing_plain_http().unwrap(),
        &Cache::new(dir.path()),
        &config,
        true,
    )
    .await
    .unwrap();
    assert!(!cached);
    assert_eq!(got, body, "the second answer is whole");
    assert_eq!(
        *served.lock().unwrap(),
        2,
        "a body cut off mid-transfer is transient: reqwest calls it a decode error, \
         and the import must not give up on it"
    );
}

#[test]
fn an_interrupted_body_is_transient() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let error = runtime.block_on(async {
        let (addr, _) = cutting_server(b"0123456789").await;
        let response = http::client_allowing_plain_http()
            .unwrap()
            .get(format!("http://{addr}/"))
            .send()
            .await
            .unwrap();
        let mut response = response;
        loop {
            match response.chunk().await {
                Ok(Some(_)) => {}
                Ok(None) => panic!("the body should be cut"),
                Err(e) => break e,
            }
        }
    });
    assert!(
        error.is_decode() && !error.is_body() && !error.is_timeout() && !error.is_connect(),
        "reqwest reports a cut body as a decode error, which the old rule never retried: {error:?}"
    );
    let wrapped = IngestError::Body {
        url: "u".into(),
        source: error,
    };
    assert!(wrapped.is_transient());
}
