//! How long the contribution tables keep what they hold
//! (`lunaway_db::retention`), what a ban leaves of a review, and what a
//! deleted account leaves of its key and its submissions. Each sweep runs
//! with the API's role, as `lunaway retention` does.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::{DateTime, Duration, Utc};
use lunaway_db::{
    PgPool, accounts, community,
    conflation::{self, PlaceWrite},
    moderation::{self, Decision},
    retention::{self, Swept},
    submissions::{self, NewSubmission, Submitted, Withdrawal},
};
use lunaway_domain::{
    PlaceKind, Position,
    community::{
        ConfirmationStatus, IssueKind, ReportReason, ReportTarget, ReviewStatus,
        submission::{NewPlace, PlacePatch},
    },
};
use sqlx::postgres::PgPoolOptions;
use uuid::Uuid;

/// A pool whose connections act as the API's role.
async fn as_api(pool: &PgPool) -> PgPool {
    PgPoolOptions::new()
        .max_connections(2)
        .after_connect(|conn, _| {
            Box::pin(async move {
                sqlx::query("SET ROLE lunaway_app").execute(conn).await?;
                Ok(())
            })
        })
        .connect_with((*pool.connect_options()).clone())
        .await
        .unwrap()
}

/// A live place, written by the conflation's path.
async fn place(pool: &PgPool) -> Uuid {
    let id = Uuid::now_v7();
    let content = lunaway_domain::conflation::PlaceContent {
        name: Some("Aire du Lac".into()),
        kind: PlaceKind::MotorhomeArea,
        position: Position::new(45.9, 6.1).unwrap(),
        overnight: lunaway_domain::OvernightStatus::Allowed,
        services: Vec::new(),
        activities: Vec::new(),
        description: None,
        address: lunaway_domain::Address::default(),
        price_parking_eur: None,
        price_services_eur: None,
        price_services_included: false,
        price_parking_includes: Vec::new(),
        max_height_m: None,
        max_length_m: None,
        max_width_m: None,
        max_weight_t: None,
        capacity: None,
        opening_hours: None,
        website: None,
        phone: None,
        stars: None,
    };
    let opening = conflation::OpeningEval {
        parsed: false,
        intervals: None,
        until: None,
        window_start: None,
        refresh_at: None,
        season: None,
    };
    let mut tx = conflation::begin_writer(pool).await.unwrap();
    conflation::upsert_place(
        &mut tx,
        PlaceWrite {
            id,
            content: &content,
            provenance: &[],
            opening: &opening,
            descriptions: &[],
            external_links: &[],
            content_hash: "h",
        },
    )
    .await
    .unwrap();
    tx.commit().await.unwrap();
    id
}

/// The device key of account number `n`, a distinct point for each.
fn key_of(n: u8) -> [u8; 65] {
    let mut k = [n; 65];
    k[0] = 4;
    k
}

/// Account number `n`, at level 2 (it may write and report).
async fn account(app: &PgPool, n: u8) -> Uuid {
    let (a, _) = accounts::create_with_key(
        app,
        accounts::NewAccount {
            pseudonym: "Hérisson du Vercors",
            thumbprint: &format!("{n:0>43}"),
            public_key: &key_of(n),
            session_hash: &[n; 32],
            session_ttl_secs: 3_600.0,
        },
    )
    .await
    .unwrap();
    accounts::set_trust_level(app, a.id, 2).await.unwrap();
    a.id
}

async fn review(app: &PgPool, account: Uuid, place: Uuid) -> Uuid {
    community::review(
        app,
        community::ReviewWrite {
            account,
            place,
            stars: 4,
            body: "Calme, propre, une borne qui marche.",
            lang: Some("fr"),
            visited_on: None,
            vehicle: None,
            status: ReviewStatus::Published,
            held_for: None,
        },
    )
    .await
    .unwrap()
    .id
}

async fn sweep(app: &PgPool, days: i64) -> Swept {
    retention::sweep(app, after(days)).await.unwrap()
}

fn after(days: i64) -> DateTime<Utc> {
    Utc::now() + Duration::days(days)
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_issue_report_goes_after_ninety_days(pool: PgPool) {
    let app = as_api(&pool).await;
    let (a, p) = (account(&app, 1).await, place(&pool).await);
    community::report_issue(&app, a, p, IssueKind::NightBan, Some("Police à 23 h"))
        .await
        .unwrap();
    assert_eq!(sweep(&app, 89).await.issue_reports, 0);
    assert_eq!(
        sweep(&app, 91).await.issue_reports,
        1,
        "the privacy page says ninety days"
    );
    let left: i64 = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM issue_reports"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(left, 0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_report_and_its_entry_go_a_year_after_the_decision(pool: PgPool) {
    let app = as_api(&pool).await;
    let p = place(&pool).await;
    let reporter = account(&app, 9).await;
    let mut reviews = Vec::new();
    for n in 1..=3 {
        let r = review(&app, account(&app, n).await, p).await;
        community::report_content(
            &app,
            reporter,
            ReportTarget::Review,
            r,
            ReportReason::Offensive,
            Some("insulte le gérant"),
            3,
        )
        .await
        .unwrap();
        reviews.push(r);
    }
    let entry = |r: Uuid| {
        let pool = &pool;
        async move {
            sqlx::query_scalar!(
                "SELECT id FROM moderation_queue WHERE target_id = $1 AND status = 'open'",
                r
            )
            .fetch_one(pool)
            .await
            .unwrap()
        }
    };
    // Kept, and dismissed: approved; the second removed; the third waits.
    moderation::decide(&app, entry(reviews[0]).await, Decision::Approve, None)
        .await
        .unwrap();
    moderation::decide(
        &app,
        entry(reviews[1]).await,
        Decision::Reject,
        Some("insulte"),
    )
    .await
    .unwrap();

    let kept = sweep(&app, 364).await;
    assert_eq!((kept.content_reports, kept.moderation_entries), (0, 0));
    let swept = sweep(&app, 366).await;
    assert_eq!(
        (swept.content_reports, swept.moderation_entries),
        (2, 2),
        "a year after the decision, whichever it was"
    );
    let reports: Vec<Uuid> = sqlx::query_scalar!("SELECT target_id FROM content_reports")
        .fetch_all(&pool)
        .await
        .unwrap();
    assert_eq!(
        reports,
        [reviews[2]],
        "a report nobody decided waits for its moderator"
    );
    let open: i64 = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM moderation_queue WHERE status = 'open'"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(open, 1);
    assert_eq!(sweep(&app, 3_000).await.content_reports, 0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_refused_or_withdrawn_submission_loses_its_content_after_thirty_days(pool: PgPool) {
    let app = as_api(&pool).await;
    let author = account(&app, 1).await;
    let device: Uuid =
        sqlx::query_scalar!("SELECT id FROM device_keys WHERE account_id = $1", author)
            .fetch_one(&pool)
            .await
            .unwrap();
    let new = NewPlace {
        kind: PlaceKind::Parking,
        position: Position::new(47.123_456, -1.654_321).unwrap(),
        details: PlacePatch {
            name: Some("Chez nous".into()),
            ..PlacePatch::default()
        },
    };
    let propose = || {
        let app = &app;
        let new = &new;
        async move {
            submissions::submit(
                app,
                NewSubmission {
                    account: author,
                    device_key: device,
                    what: Submitted::Create(new),
                    accepted: false,
                    held_for: None,
                },
            )
            .await
            .unwrap()
            .id
        }
    };
    let (refused, withdrawn, waiting) = (propose().await, propose().await, propose().await);
    let entry: Uuid = sqlx::query_scalar!(
        "SELECT id FROM moderation_queue WHERE target_id = $1",
        refused
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    moderation::decide(&app, entry, Decision::Reject, None)
        .await
        .unwrap();
    assert_eq!(
        submissions::withdraw(&app, author, withdrawn)
            .await
            .unwrap(),
        Withdrawal::Withdrawn
    );

    assert_eq!(sweep(&app, 29).await.submission_payloads, 0);
    assert_eq!(sweep(&app, 31).await.submission_payloads, 2);
    for (id, emptied) in [(refused, true), (withdrawn, true), (waiting, false)] {
        let payload = submissions::submission(&pool, id)
            .await
            .unwrap()
            .unwrap()
            .payload;
        assert_eq!(
            payload == serde_json::json!({}),
            emptied,
            "{id}: a refused or withdrawn proposal keeps no position past thirty days, \
             one a moderator has not seen keeps it: {payload}"
        );
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_ban_leaves_ratings_without_text(pool: PgPool) {
    let app = as_api(&pool).await;
    let (a, p) = (account(&app, 1).await, place(&pool).await);
    let r = review(&app, a, p).await;
    accounts::ban(&app, a, "spam").await.unwrap().unwrap();
    let row = sqlx::query!("SELECT body, lang, stars FROM reviews WHERE id = $1", r)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        (row.body, row.lang, row.stars),
        (None, None, 4),
        "the text goes at the ban, the rating stays a rating"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_banned_account_that_deletes_itself_leaves_its_key_hash_for_two_years(pool: PgPool) {
    let app = as_api(&pool).await;
    let (banned, other) = (account(&app, 1).await, account(&app, 2).await);
    let p = place(&pool).await;
    for a in [banned, other] {
        community::confirm(&app, a, p, ConfirmationStatus::StillOk, None)
            .await
            .unwrap();
    }
    accounts::ban(&app, banned, "spam").await.unwrap().unwrap();
    accounts::delete_account(&app, banned)
        .await
        .unwrap()
        .unwrap();
    accounts::delete_account(&app, other)
        .await
        .unwrap()
        .unwrap();
    let answers: i64 = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM confirmations"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        answers, 1,
        "the banned account's answer goes (kept without author it would count again), the \
         other's stays without author"
    );
    assert!(
        accounts::key_banned(&app, &key_of(1)).await.unwrap(),
        "the key of a banned account opens nothing after its deletion"
    );
    assert!(
        !accounts::key_banned(&app, &key_of(2)).await.unwrap(),
        "an account that was not banned leaves nothing"
    );
    let kept: Vec<Vec<u8>> = sqlx::query_scalar!("SELECT key_hash FROM banned_keys")
        .fetch_all(&pool)
        .await
        .unwrap();
    assert_eq!(kept.len(), 1);
    assert_ne!(kept[0], key_of(1), "a hash, never the key");

    assert_eq!(sweep(&app, 729).await.banned_keys, 0);
    assert_eq!(sweep(&app, 731).await.banned_keys, 1);
    assert!(!accounts::key_banned(&app, &key_of(1)).await.unwrap());
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_deleted_account_leaves_no_content_in_what_was_not_applied(pool: PgPool) {
    let app = as_api(&pool).await;
    let author = account(&app, 1).await;
    let device: Uuid =
        sqlx::query_scalar!("SELECT id FROM device_keys WHERE account_id = $1", author)
            .fetch_one(&pool)
            .await
            .unwrap();
    let new = NewPlace {
        kind: PlaceKind::Parking,
        position: Position::new(47.123_456, -1.654_321).unwrap(),
        details: PlacePatch::default(),
    };
    let mut ids = Vec::new();
    for accepted in [true, true, false] {
        ids.push(
            submissions::submit(
                &app,
                NewSubmission {
                    account: author,
                    device_key: device,
                    what: Submitted::Create(&new),
                    accepted,
                    held_for: None,
                },
            )
            .await
            .unwrap()
            .id,
        );
    }
    // The worker applied the first: it is part of the places database.
    sqlx::query!(
        "UPDATE place_submissions SET status = 'applied', applied_at = now() WHERE id = $1",
        ids[0]
    )
    .execute(&pool)
    .await
    .unwrap();
    let entry: Uuid = sqlx::query_scalar!(
        "SELECT id FROM moderation_queue WHERE target_id = $1",
        ids[2]
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    moderation::decide(&app, entry, Decision::Reject, None)
        .await
        .unwrap();

    accounts::delete_account(&app, author)
        .await
        .unwrap()
        .unwrap();
    let rows = sqlx::query!(
        r#"
        SELECT id, status, payload, account_id FROM place_submissions
        WHERE id = ANY($1) ORDER BY id
        "#,
        &ids
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    let got: Vec<(&str, bool, bool)> = rows
        .iter()
        .map(|r| {
            (
                r.status.as_str(),
                r.payload == serde_json::json!({}),
                r.account_id.is_none(),
            )
        })
        .collect();
    assert_eq!(
        got,
        [
            ("applied", false, true),
            ("withdrawn", true, true),
            ("rejected", true, true),
        ],
        "an applied submission is ODbL data and stays, unsigned; the others keep no \
         position, and one accepted but not applied never will be"
    );
}
