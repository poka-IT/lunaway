//! The external community source as the app sees it: a place's card reads
//! the partner's reviews, ratings and photos with the source's label and
//! the authors' pseudonyms; the photo proxy downloads a photo once, through
//! the upload's pipeline, and serves it from Lunaway's host; the switch
//! hides everything at once; none of it is in the packs.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::{collections::HashMap, path::Path, sync::Arc};

use axum::{
    body::Body,
    http::{Request, StatusCode, header},
};
use chrono::{NaiveDate, TimeZone, Utc};
use http_body_util::BodyExt;
use lunaway_api::{ApiConfig, ApiState, external_photos::PhotoSource};
use lunaway_db::{PgPool, accounts, community, content, extcom};
use lunaway_domain::{
    SourceId,
    community::{ReportReason, ReportTarget},
    extcom::Terms,
};
use lunaway_ingest::{
    cache::Cache,
    extcom::{Input, Limits, Options, import},
};
use serde_json::{Value, json};
use tower::ServiceExt;
use uuid::Uuid;

const FEED: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../lunaway-ingest/tests/fixtures/extcom_feed.jsonl"
);

/// The smallest PNG: one transparent pixel.
const PIXEL: &[u8] = &[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
];

fn config(media: &Path) -> ApiConfig {
    let d = ApiConfig::default();
    ApiConfig {
        media: lunaway_api::config::MediaConfig {
            dir: media.to_path_buf(),
            base_url: "https://media.test/".into(),
            ..d.media.clone()
        },
        tiles: lunaway_api::config::TilesConfig {
            public_url: "https://api.test".into(),
            ..d.tiles.clone()
        },
        ..d
    }
}

/// The router, with the partner's photos `photos` (URL, bytes) in memory.
fn app(pool: &PgPool, media: &Path, photos: &[(&str, &[u8])]) -> axum::Router {
    app_with(pool, config(media), photos)
}

fn app_with(pool: &PgPool, config: ApiConfig, photos: &[(&str, &[u8])]) -> axum::Router {
    let photos: HashMap<String, Vec<u8>> = photos
        .iter()
        .map(|(u, b)| ((*u).to_owned(), b.to_vec()))
        .collect();
    let state = ApiState::new(pool.clone(), config)
        .with_external_photos(PhotoSource::Memory(Arc::new(photos)));
    lunaway_api::router(state)
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_downloads_of_a_day_are_bounded_for_all_clients(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    seeded(&pool, &dir.path().join("raw")).await;
    let mut c = config(&dir.path().join("media"));
    c.external_photos.downloads_per_day = 1;
    let app = app_with(
        &pool,
        c,
        &[
            ("https://img.partner.example/p-1.jpg", PIXEL),
            ("https://img.partner.example/p-2.jpg", PIXEL),
        ],
    );
    let ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT id FROM external_photos WHERE external_id IN ('p-1', 'p-2') ORDER BY external_id",
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    assert_eq!(
        get(&app, &format!("/external-photos/{}/thumb", ids[0]))
            .await
            .0,
        StatusCode::FOUND
    );
    let (status, headers) = get(&app, &format!("/external-photos/{}/thumb", ids[1])).await;
    assert_eq!(
        status,
        StatusCode::SERVICE_UNAVAILABLE,
        "a walk over the whole map cannot copy the partner's library in a day"
    );
    assert!(headers.contains_key(header::RETRY_AFTER));
    assert_eq!(
        get(&app, &format!("/external-photos/{}/large", ids[0]))
            .await
            .0,
        StatusCode::FOUND,
        "a photo already stored is served whatever the day's budget"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn one_client_cannot_spend_the_downloads_of_all(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    seeded(&pool, &dir.path().join("raw")).await;
    let mut c = config(&dir.path().join("media"));
    c.quotas.external_photo = lunaway_api::config::Quota {
        count: 1,
        period: std::time::Duration::from_secs(86_400),
    };
    // Through the listener, behind Caddy on the loopback: each client is
    // the address Caddy saw.
    let app = app_with(
        &pool,
        c,
        &[
            ("https://img.partner.example/p-1.jpg", PIXEL),
            ("https://img.partner.example/p-2.jpg", PIXEL),
        ],
    )
    .layer(axum::extract::connect_info::MockConnectInfo(
        "127.0.0.1:40000".parse::<std::net::SocketAddr>().unwrap(),
    ));
    let ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT id FROM external_photos WHERE external_id IN ('p-1', 'p-2') ORDER BY external_id",
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    let from = |client: &'static str, id: Uuid, size: &'static str| {
        let app = app.clone();
        async move {
            let response = app
                .oneshot(
                    Request::get(format!("/external-photos/{id}/{size}"))
                        .header("x-forwarded-for", client)
                        .body(Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap();
            (response.status(), response.headers().clone())
        }
    };
    assert_eq!(
        from("203.0.113.9", ids[0], "thumb").await.0,
        StatusCode::FOUND
    );
    let (status, headers) = from("203.0.113.9", ids[1], "thumb").await;
    assert_eq!(
        status,
        StatusCode::TOO_MANY_REQUESTS,
        "a client past its share waits, whatever is left of the day's budget"
    );
    assert!(headers.contains_key(header::RETRY_AFTER));
    assert_eq!(
        from("198.51.100.7", ids[1], "thumb").await.0,
        StatusCode::FOUND,
        "another client still gets the photo"
    );
    assert_eq!(
        from("203.0.113.9", ids[1], "large").await.0,
        StatusCode::FOUND,
        "a photo already stored costs no download"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_download_the_day_s_budget_refuses_costs_the_client_nothing(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    seeded(&pool, &dir.path().join("raw")).await;
    let mut c = config(&dir.path().join("media"));
    c.external_photos.downloads_per_day = 1;
    c.quotas.external_photo = lunaway_api::config::Quota {
        count: 2,
        period: std::time::Duration::from_secs(86_400),
    };
    let app = app_with(
        &pool,
        c,
        &[
            ("https://img.partner.example/p-1.jpg", PIXEL),
            ("https://img.partner.example/p-2.jpg", PIXEL),
        ],
    );
    let ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT id FROM external_photos WHERE external_id IN ('p-1', 'p-2') ORDER BY external_id",
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    let thumb = |id: Uuid| format!("/external-photos/{id}/thumb");
    assert_eq!(get(&app, &thumb(ids[0])).await.0, StatusCode::FOUND);
    for attempt in 1..=2 {
        assert_eq!(
            get(&app, &thumb(ids[1])).await.0,
            StatusCode::SERVICE_UNAVAILABLE,
            "attempt {attempt}: the day's budget is spent, not the client's share, which \
             gets back the download that did not happen"
        );
    }
}

/// The fixture feed imported and conflated; the place of spot 1001.
async fn seeded(pool: &PgPool, cache_dir: &Path) -> Uuid {
    let options = Options {
        terms: Terms::new("EXTCOM-TEST-2026-01", &["img.partner.example".into()]).unwrap(),
        limits: Limits::default(),
        refresh: false,
        today: NaiveDate::from_ymd_opt(2026, 10, 7).unwrap(),
    };
    let http = lunaway_ingest::http::client_allowing_plain_http().unwrap();
    import(
        pool,
        &http,
        &Cache::new(cache_dir),
        &Input::File(FEED.into()),
        &options,
    )
    .await
    .unwrap();
    let now = Utc.with_ymd_and_hms(2026, 10, 7, 12, 0, 0).unwrap();
    lunaway_conflate::run(pool, now, None).await.unwrap();
    sqlx::query_scalar(
        "SELECT ps.place_id FROM place_sources ps JOIN source_records r ON r.id = ps.record_id \
         WHERE r.source_id = 'extcom' AND r.external_id = '1001'",
    )
    .fetch_one(pool)
    .await
    .unwrap()
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

async fn get(app: &axum::Router, uri: &str) -> (StatusCode, axum::http::HeaderMap) {
    let response = app
        .clone()
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();
    (response.status(), response.headers().clone())
}

const CARD: &str = r"
query($id: UUID!, $first: Int, $after: String) {
  place(id: $id) {
    sources { source { id name licence attribution } }
    externalReviews(first: $first, after: $after) {
      nodes { id sourceId sourceLabel authorName rating text lang authorVehicle writtenAt licence }
      endCursor hasNextPage totalCount
    }
    externalRatings { sourceId average count }
    externalPhotos { id sourceId sourceLabel authorName licence thumbUrl largeUrl width height }
  }
}";

#[sqlx::test(migrations = "../../migrations")]
async fn a_place_card_reads_the_partner_s_reviews_ratings_and_photos(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, &dir.path().join("raw")).await;
    let app = app(&pool, &dir.path().join("media"), &[]);
    let body = gql(&app, CARD, json!({"id": place, "first": 1})).await;
    let p = &ok(&body)["place"];
    let source = p["sources"]
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["source"]["id"] == "extcom")
        .expect("the place lists the source");
    assert_eq!(source["source"]["name"], "Source communautaire externe");
    assert_eq!(
        source["source"]["licence"], "Written agreement",
        "the card shows the kind of licence, never the agreement's reference"
    );
    assert!(
        source["source"]["attribution"]
            .as_str()
            .unwrap()
            .starts_with("Source communautaire externe"),
        "the attribution is the agreement's"
    );

    let reviews = &p["externalReviews"];
    assert_eq!(
        reviews["totalCount"], 2,
        "the reviews with text; a rating alone counts in the summary"
    );
    assert_eq!(reviews["hasNextPage"], true);
    let first = &reviews["nodes"][0];
    assert_eq!(
        first["authorName"], "Marie",
        "the newest first, with its author's pseudonym"
    );
    assert_eq!(first["sourceLabel"], "Source communautaire externe");
    assert_eq!(first["sourceId"], "extcom");
    assert_eq!(first["rating"], 4);
    assert_eq!(first["authorVehicle"], "CAMPERVAN");
    assert_eq!(first["licence"], "EXTCOM-TEST-2026-01");
    assert!(
        first.get("authorId").is_none(),
        "the partner's author id is never served"
    );
    let next = gql(
        &app,
        CARD,
        json!({"id": place, "first": 1, "after": reviews["endCursor"]}),
    )
    .await;
    let next = &ok(&next)["place"]["externalReviews"];
    assert_eq!(next["nodes"][0]["authorName"], "Hans");
    assert_eq!(next["hasNextPage"], false);

    assert_eq!(
        p["externalRatings"],
        json!([{"sourceId": "extcom", "average": 4.2, "count": 87}])
    );
    let photos = p["externalPhotos"].as_array().unwrap();
    assert_eq!(photos.len(), 2);
    for photo in photos {
        let id = photo["id"].as_str().unwrap();
        assert_eq!(
            photo["thumbUrl"],
            format!("https://api.test/external-photos/{id}/thumb"),
            "a photo not downloaded yet leads to the proxy, never to the partner"
        );
        assert_eq!(photo["width"], Value::Null);
        assert_eq!(photo["sourceLabel"], "Source communautaire externe");
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_partner_s_and_the_open_reviews_page_as_one_list(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, &dir.path().join("raw")).await;
    let app = app(&pool, &dir.path().join("media"), &[]);
    // Around the partner's Marie (14 August) and Hans (2 July).
    let open = |sig: &str, day: (u32, u32)| content::NewReview {
        place_id: place,
        external_id: sig.to_owned(),
        rating: Some(4),
        text: Some(format!("Avis ouvert {sig}.")),
        lang: None,
        author: Some(sig.to_owned()),
        author_key: Some(sig.repeat(64)),
        written_at: Utc.with_ymd_and_hms(2026, day.0, day.1, 12, 0, 0).unwrap(),
        page_url: format!("https://mangrove.reviews/list?signature={sig}"),
        licence: "CC BY 4.0".into(),
        licence_url: "https://creativecommons.org/licenses/by/4.0/".into(),
        distance_m: Some(5.0),
    };
    content::replace_reviews(
        &pool,
        "mangrove",
        &[open("a", (9, 1)), open("b", (7, 20)), open("c", (6, 1))],
        Utc::now(),
    )
    .await
    .unwrap();

    let mut read = Vec::new();
    let mut after = Value::Null;
    let mut pages = 0;
    loop {
        let body = gql(
            &app,
            r"query($id: UUID!, $after: String) { place(id: $id) {
                externalReviews(first: 2, after: $after) {
                  nodes { authorName sourceId sourceLabel pageUrl licenceUrl }
                  endCursor hasNextPage totalCount } } }",
            json!({"id": place, "after": after}),
        )
        .await;
        let page = ok(&body)["place"]["externalReviews"].clone();
        assert_eq!(page["totalCount"], 5, "both sources count");
        pages += 1;
        for n in page["nodes"].as_array().unwrap() {
            if n["sourceId"] == "extcom" {
                assert_eq!(n["sourceLabel"], "Source communautaire externe");
                assert_eq!(n["pageUrl"], Value::Null, "the partner's has no link");
                assert_eq!(n["licenceUrl"], Value::Null);
            } else {
                assert_eq!(n["sourceLabel"], "Mangrove Reviews");
                assert!(n["pageUrl"].as_str().unwrap().starts_with("https://"));
            }
            read.push(n["authorName"].as_str().unwrap().to_owned());
        }
        if page["hasNextPage"] == false {
            break;
        }
        after = page["endCursor"].clone();
        assert!(pages < 5, "the pages end");
    }
    assert_eq!(
        read,
        ["a", "Marie", "b", "Hans", "c"],
        "newest first across the sources, each once"
    );
    assert_eq!(pages, 3);
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_proxy_downloads_a_photo_once_and_serves_it_from_lunaway(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, &dir.path().join("raw")).await;
    let media = dir.path().join("media");
    let app = app(
        &pool,
        &media,
        &[("https://img.partner.example/p-1.jpg", PIXEL)],
    );
    let id: Uuid = sqlx::query_scalar("SELECT id FROM external_photos WHERE external_id = 'p-1'")
        .fetch_one(&pool)
        .await
        .unwrap();

    let (status, headers) = get(&app, &format!("/external-photos/{id}/thumb")).await;
    assert_eq!(status, StatusCode::FOUND);
    let location = headers[header::LOCATION].to_str().unwrap();
    let relative = location
        .strip_prefix("https://media.test/")
        .expect("the photo is served from Lunaway's media host");
    assert!(
        media.join(relative).exists(),
        "the re-encoded thumbnail is stored under the media root"
    );
    assert!(
        relative.ends_with(".webp"),
        "re-encoded, no byte of the original kept"
    );

    // Downloaded once: a proxy that no longer holds the photo still serves it.
    let without = self::app(&pool, &media, &[]);
    let (status, headers) = get(&without, &format!("/external-photos/{id}/large")).await;
    assert_eq!(status, StatusCode::FOUND);
    assert!(
        headers[header::LOCATION]
            .to_str()
            .unwrap()
            .starts_with("https://media.test/photos/")
    );
    let body = gql(&without, CARD, json!({"id": place})).await;
    let photo = ok(&body)["place"]["externalPhotos"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["id"] == id.to_string())
        .unwrap()
        .clone();
    assert!(
        photo["thumbUrl"]
            .as_str()
            .unwrap()
            .starts_with("https://media.test/photos/"),
        "once stored, the card names the file itself"
    );
    assert_eq!(photo["width"], 1);

    for bad in [
        "/external-photos/not-a-uuid/thumb".to_owned(),
        format!("/external-photos/{id}/original"),
        format!("/external-photos/{}/thumb", Uuid::now_v7()),
    ] {
        assert_eq!(get(&app, &bad).await.0, StatusCode::NOT_FOUND, "{bad}");
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_failed_download_waits_before_the_next_try(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    seeded(&pool, &dir.path().join("raw")).await;
    let app = app(&pool, &dir.path().join("media"), &[]);
    let id: Uuid = sqlx::query_scalar("SELECT id FROM external_photos WHERE external_id = 'p-2'")
        .fetch_one(&pool)
        .await
        .unwrap();
    let (status, _) = get(&app, &format!("/external-photos/{id}/thumb")).await;
    assert_eq!(status, StatusCode::BAD_GATEWAY);
    let (status, headers) = get(&app, &format!("/external-photos/{id}/thumb")).await;
    assert_eq!(
        status,
        StatusCode::SERVICE_UNAVAILABLE,
        "the partner's host is not asked again at every view"
    );
    let wait: u64 = headers[header::RETRY_AFTER]
        .to_str()
        .unwrap()
        .parse()
        .unwrap();
    assert!(
        (3_500..=3_600).contains(&wait),
        "an hour after a first failure: {wait}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_switch_hides_everything_of_the_source_at_once(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, &dir.path().join("raw")).await;
    let media = dir.path().join("media");
    let app = app(
        &pool,
        &media,
        &[("https://img.partner.example/p-1.jpg", PIXEL)],
    );
    let id: Uuid = sqlx::query_scalar("SELECT id FROM external_photos WHERE external_id = 'p-1'")
        .fetch_one(&pool)
        .await
        .unwrap();
    extcom::set_hidden(&pool, &SourceId::EXTCOM, true, None)
        .await
        .unwrap();
    let body = gql(&app, CARD, json!({"id": place})).await;
    let p = &ok(&body)["place"];
    assert_eq!(p["externalReviews"]["totalCount"], 0);
    assert_eq!(p["externalRatings"], json!([]));
    assert_eq!(p["externalPhotos"], json!([]));
    assert!(
        p["sources"]
            .as_array()
            .unwrap()
            .iter()
            .all(|s| s["source"]["id"] != "extcom"),
        "before any conflation, the place no longer lists the source"
    );
    assert_eq!(
        get(&app, &format!("/external-photos/{id}/thumb")).await.0,
        StatusCode::NOT_FOUND,
        "the proxy serves nothing of a hidden source"
    );
    let sources = gql(&app, "{ sources { id } }", json!({})).await;
    assert!(
        ok(&sources)["sources"]
            .as_array()
            .unwrap()
            .iter()
            .all(|s| s["id"] != "extcom")
    );
}

/// A reporter of level 2, number `n`.
async fn reporter(pool: &PgPool, n: u8) -> Uuid {
    let mut key = [n; 65];
    key[0] = 4;
    let (a, _) = accounts::create_with_key(
        pool,
        accounts::NewAccount {
            pseudonym: "Hérisson du Vercors",
            thumbprint: &format!("{n:0>43}"),
            public_key: &key,
            session_hash: &[n; 32],
            session_ttl_secs: 3_600.0,
        },
    )
    .await
    .unwrap();
    accounts::set_trust_level(pool, a.id, 2).await.unwrap();
    a.id
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_reported_partner_review_does_not_hide_a_photo_of_the_same_id(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, &dir.path().join("raw")).await;
    let app = app(&pool, &dir.path().join("media"), &[]);
    // The partner does not say its review and photo ids differ: one photo
    // carries the id of Marie's review.
    sqlx::query("UPDATE external_photos SET external_id = 'r-1' WHERE external_id = 'p-1'")
        .execute(&pool)
        .await
        .unwrap();
    let review: Uuid = sqlx::query_scalar(
        "SELECT id FROM external_reviews WHERE source_id = 'extcom' AND external_id = 'r-1'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    for n in 1..=3 {
        let who = reporter(&pool, n).await;
        community::report_content(
            &pool,
            who,
            ReportTarget::ExternalReview,
            review,
            ReportReason::Offensive,
            None,
            3,
        )
        .await
        .unwrap();
    }
    let body = gql(&app, CARD, json!({"id": place})).await;
    let p = &ok(&body)["place"];
    assert_eq!(
        p["externalReviews"]["totalCount"], 1,
        "three reports hide the review"
    );
    assert_eq!(
        p["externalPhotos"].as_array().unwrap().len(),
        2,
        "the photo that shares the review's id at the partner stays"
    );
}

#[test]
fn the_packs_carry_nothing_of_the_partner_s_reviews_and_photos() {
    let selection = lunaway_api::packs::PLACE_SELECTION;
    for field in ["externalReviews", "externalRatings", "externalPhotos"] {
        assert!(
            !selection.contains(field),
            "{field} is read per place when its card opens, never kept offline"
        );
    }
}
