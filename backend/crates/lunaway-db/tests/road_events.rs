//! Road events in the database: an update never goes back in versions, a
//! complete snapshot ends what it no longer carries (unless it looks cut),
//! events without an end expire, the change feed moves only with what the
//! app sees, and each role writes only what it should.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::{DateTime, Duration, TimeZone, Utc};
use lunaway_db::{
    PgPool, accounts,
    road_events::{self as db, Missing, NewEvent, NewReport},
};
use lunaway_domain::{
    Position,
    road_events::{
        Carriageway, Confidence, EndReason, EventClass, EventDirection, MatchQuality, Schedule,
        SourceGeometry, VehicleLimits, community::ReportKind,
    },
};
use sqlx::postgres::PgPoolOptions;

fn t0() -> DateTime<Utc> {
    Utc.with_ymd_and_hms(2026, 10, 6, 10, 0, 0).unwrap()
}

fn p(lat: f64, lon: f64) -> Position {
    Position::new(lat, lon).unwrap()
}

fn event(id: &str, version: &str) -> NewEvent {
    NewEvent {
        external_id: id.to_owned(),
        external_version: version.to_owned(),
        situation_id: Some("s1".to_owned()),
        class: EventClass::Closure,
        detail: "roadClosed".to_owned(),
        carriageway: Carriageway::Main,
        direction: EventDirection::Both,
        road_number: Some("N165".to_owned()),
        road_name: None,
        limits: VehicleLimits::default(),
        valid_from: t0() - Duration::hours(1),
        valid_to: None,
        schedule: Schedule::default(),
        geometry: SourceGeometry::Lines(vec![vec![p(47.75, -3.30), p(47.75, -3.27)]]),
        match_quality: MatchQuality::Pending,
        confidence: Confidence::Official,
        description: Some("N165 fermée".to_owned()),
        detour: None,
        url: None,
        source_updated_at: Some(t0() - Duration::hours(1)),
        raw: "<situationRecord/>".to_owned(),
        ended: None,
    }
}

async fn store(
    pool: &PgPool,
    source: &str,
    events: &[NewEvent],
    at: DateTime<Utc>,
    ordered: bool,
) -> db::UpsertReport {
    let mut w = db::begin_writer(pool).await.unwrap();
    let r = db::upsert(&mut w, source, events, at, at, ordered)
        .await
        .unwrap();
    w.commit().await.unwrap();
    r
}

async fn revision_of(pool: &PgPool, id: &str) -> (i64, Option<String>) {
    let r = sqlx::query!(
        "SELECT revision, end_reason FROM road_events WHERE external_id = $1",
        id
    )
    .fetch_one(pool)
    .await
    .unwrap();
    (r.revision, r.end_reason)
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_older_version_never_replaces_a_newer_one(pool: PgPool) {
    let mut newer = event("r1", "0000000003");
    newer.description = Some("version 3".to_owned());
    let r = store(&pool, "dir", &[newer], t0(), true).await;
    assert_eq!(r.inserted, 1);
    let mut older = event("r1", "0000000002");
    older.description = Some("version 2".to_owned());
    let r = store(&pool, "dir", &[older], t0(), true).await;
    assert_eq!(
        r.older, 1,
        "an aggregate published before an increment must not undo it"
    );
    let d = sqlx::query_scalar!("SELECT description FROM road_events WHERE external_id = 'r1'")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(d.as_deref(), Some("version 3"));
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_feed_moves_with_what_the_app_sees_and_not_with_each_read(pool: PgPool) {
    store(&pool, "dir", &[event("r1", "0000000001")], t0(), true).await;
    let (first, _) = revision_of(&pool, "r1").await;
    let r = store(
        &pool,
        "dir",
        &[event("r1", "0000000001")],
        t0() + Duration::hours(1),
        true,
    )
    .await;
    assert_eq!(r.unchanged, 1);
    assert_eq!(
        revision_of(&pool, "r1").await.0,
        first,
        "seeing an event again in every hourly aggregate must not resend it to every phone"
    );
    let mut changed = event("r1", "0000000002");
    changed.valid_to = Some(t0() + Duration::hours(5));
    let r = store(&pool, "dir", &[changed], t0() + Duration::hours(2), true).await;
    assert_eq!(r.changed, 1);
    let (second, _) = revision_of(&pool, "r1").await;
    assert!(second > first, "a new end date reaches the phones");
    let head = db::feed_head(&pool).await.unwrap();
    assert_eq!(head.revision, second);
    assert_eq!(head.identity.len(), 40);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_snapshot_ends_what_it_no_longer_carries_unless_it_looks_cut(pool: PgPool) {
    let all: Vec<NewEvent> = (0..30)
        .map(|i| event(&format!("r{i}"), "0000000001"))
        .collect();
    store(&pool, "dir", &all, t0(), true).await;
    // An answer cut short: 5 of 30.
    let mut w = db::begin_writer(&pool).await.unwrap();
    let present: Vec<String> = (0..5).map(|i| format!("r{i}")).collect();
    let refused = db::end_missing(
        &mut w,
        "dir",
        &present,
        t0() + Duration::hours(1),
        t0() + Duration::hours(1),
    )
    .await
    .unwrap();
    w.commit().await.unwrap();
    assert_eq!(
        refused,
        Missing::Refused { live: 30, seen: 5 },
        "a truncated aggregate must not end every closure of France"
    );
    // A real one: 28 of 30, the two missing end.
    let mut w = db::begin_writer(&pool).await.unwrap();
    let present: Vec<String> = (0..28).map(|i| format!("r{i}")).collect();
    let ended = db::end_missing(
        &mut w,
        "dir",
        &present,
        t0() + Duration::hours(1),
        t0() + Duration::hours(1),
    )
    .await
    .unwrap();
    w.commit().await.unwrap();
    assert_eq!(ended, Missing::Ended(2));
    assert_eq!(
        revision_of(&pool, "r29").await.1.as_deref(),
        Some("disappeared")
    );
    // An event the source changed after the aggregate was published (an
    // increment newer than it) is kept.
    let mut fresh = event("late", "0000000001");
    fresh.source_updated_at = Some(t0() + Duration::hours(3));
    store(&pool, "dir", &[fresh], t0() + Duration::hours(3), true).await;
    let mut w = db::begin_writer(&pool).await.unwrap();
    db::end_missing(
        &mut w,
        "dir",
        &present,
        t0() + Duration::hours(2),
        t0() + Duration::hours(3),
    )
    .await
    .unwrap();
    w.commit().await.unwrap();
    assert_eq!(revision_of(&pool, "late").await.1, None);
    // Another source is untouched.
    store(&pool, "dialog", &[event("d1", "0000000001")], t0(), true).await;
    assert_eq!(db::live_count(&pool, "dialog").await.unwrap(), 1);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_new_version_of_a_situation_settles_its_records(pool: PgPool) {
    store(
        &pool,
        "dir",
        &[event("s1-1", "0000000001"), event("s1-2", "0000000001")],
        t0(),
        true,
    )
    .await;
    let mut w = db::begin_writer(&pool).await.unwrap();
    let n = db::settle_situation(
        &mut w,
        "dir",
        "s1",
        &["s1-1".to_owned()],
        &[],
        t0() + Duration::minutes(2),
        t0() + Duration::minutes(3),
    )
    .await
    .unwrap();
    w.commit().await.unwrap();
    assert_eq!(n, 1, "a record its situation no longer carries is over");
    assert_eq!(
        revision_of(&pool, "s1-2").await.1.as_deref(),
        Some("disappeared")
    );
    let mut w = db::begin_writer(&pool).await.unwrap();
    db::end_records(
        &mut w,
        "dir",
        &["s1-1".to_owned()],
        t0() + Duration::minutes(6),
    )
    .await
    .unwrap();
    w.commit().await.unwrap();
    assert_eq!(
        revision_of(&pool, "s1-1").await.1.as_deref(),
        Some("source_end")
    );
    // The source carries it again in a later version: live again.
    store(
        &pool,
        "dir",
        &[event("s1-1", "0000000002")],
        t0() + Duration::minutes(9),
        true,
    )
    .await;
    assert_eq!(revision_of(&pool, "s1-1").await.1, None);
}

#[sqlx::test(migrations = "../../migrations")]
async fn events_without_an_end_expire_and_ended_ones_are_purged(pool: PgPool) {
    let mut open = event("open", "0000000001");
    open.valid_to = None;
    let mut over = event("over", "0000000001");
    over.valid_to = Some(t0() - Duration::minutes(30));
    let mut ended = event("gone", "0000000001");
    ended.ended = Some(EndReason::SourceEnd);
    store(
        &pool,
        "dir",
        &[open, over, ended],
        t0() - Duration::hours(1),
        true,
    )
    .await;
    let l = db::lifecycle(
        &pool,
        t0() + Duration::hours(2),
        Duration::hours(6),
        Duration::days(7),
        Duration::days(14),
    )
    .await
    .unwrap();
    assert_eq!(
        l.past_end, 1,
        "an end more than an hour past ends the event"
    );
    assert_eq!(l.expired, 0, "seen three hours ago: not yet");
    let l = db::lifecycle(
        &pool,
        t0() + Duration::hours(8),
        Duration::hours(6),
        Duration::days(7),
        Duration::days(14),
    )
    .await
    .unwrap();
    assert_eq!(
        l.expired, 1,
        "an event without an end its source stopped showing ends after the expiry"
    );
    assert_eq!(
        revision_of(&pool, "open").await.1.as_deref(),
        Some("expired")
    );
    let before = db::feed_head(&pool).await.unwrap();
    let l = db::lifecycle(
        &pool,
        t0() + Duration::days(9),
        Duration::hours(6),
        Duration::days(7),
        Duration::days(14),
    )
    .await
    .unwrap();
    assert_eq!(l.purged, 3);
    let after = db::feed_head(&pool).await.unwrap();
    assert!(
        after.purged_through >= before.revision,
        "a client holding an older cursor would miss these ends: it must start over"
    );
}

/// A pool whose connections act as `role`.
async fn as_role(pool: &PgPool, set_role: &'static str) -> PgPool {
    PgPoolOptions::new()
        .max_connections(2)
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

async fn account(pool: &PgPool, name: &str) -> uuid::Uuid {
    account_of_level(pool, name, 0).await
}

async fn account_of_level(pool: &PgPool, name: &str, level: i16) -> uuid::Uuid {
    // Each account its own recovery code: they are unique.
    let mut code = [0_u8; 32];
    code[..name.len().min(32)].copy_from_slice(&name.as_bytes()[..name.len().min(32)]);
    accounts::create_granted(pool, name, level, &code)
        .await
        .unwrap()
        .id
}

async fn confidence_of(pool: &PgPool, event: uuid::Uuid) -> (String, Option<String>) {
    let r = sqlx::query!(
        "SELECT confidence, end_reason FROM road_events WHERE id = $1",
        event
    )
    .fetch_one(pool)
    .await
    .unwrap();
    (r.confidence, r.end_reason)
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_api_writes_the_community_s_events_only(pool: PgPool) {
    store(&pool, "dir", &[event("r1", "0000000001")], t0(), true).await;
    let a = account(&pool, "Loutre du Morvan").await;
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let at = p(45.8, 1.25);
    let first = db::report(
        &app,
        &NewReport {
            account: a,
            kind: ReportKind::Closure,
            at,
            heading_deg: Some(90),
            value_m: None,
        },
        t0(),
    )
    .await
    .unwrap();
    assert_eq!(first.confidence, Confidence::Reported);
    let rewrite = sqlx::query!("UPDATE road_events SET description = 'x' WHERE source = 'dir'")
        .execute(&app)
        .await
        .unwrap();
    assert_eq!(
        rewrite.rows_affected(),
        0,
        "an API compromise must not rewrite an official closure"
    );
    let forged = sqlx::query!(
        r#"
        INSERT INTO road_events (id, source, external_id, external_version, class, detail,
            carriageway, direction, valid_from, geom_source, match_quality, confidence,
            first_seen_at, last_seen_at, content_hash, raw, revision)
        VALUES ($1, 'dir', 'forged', '1', 'closure', 'x', 'main', 'both', now(),
            ST_SetSRID(ST_MakePoint(1.25, 45.8), 4326)::geography, 'point', 'official',
            now(), now(), 'h', '', 0)
        "#,
        uuid::Uuid::now_v7()
    )
    .execute(&app)
    .await;
    assert!(forged.is_err(), "nor invent an official one");
    assert_eq!(
        db::clear(&app, a, first.event_id, t0()).await.unwrap(),
        db::Cleared::Ended
    );
    let official = sqlx::query_scalar!("SELECT id FROM road_events WHERE source = 'dir'")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        db::clear(&app, a, official, t0()).await.unwrap(),
        db::Cleared::Official,
        "a user cannot end an official closure"
    );
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    store(&ingest, "dir", &[event("r2", "0000000001")], t0(), true).await;
    db::lifecycle(
        &ingest,
        t0(),
        Duration::hours(6),
        Duration::days(7),
        Duration::days(14),
    )
    .await
    .unwrap();
}

#[sqlx::test(migrations = "../../migrations")]
async fn two_accounts_at_the_same_spot_confirm_and_a_moderator_is_told(pool: PgPool) {
    let a = account_of_level(&pool, "Loutre du Morvan", 1).await;
    let b = account_of_level(&pool, "Héron des Landes", 1).await;
    let report = |account, lat, heading| NewReport {
        account,
        kind: ReportKind::LowClearance,
        at: p(lat, 1.25),
        heading_deg: Some(heading),
        value_m: Some(3.3),
    };
    let one = db::report(&pool, &report(a, 45.8, 90), t0()).await.unwrap();
    let again = db::report(&pool, &report(a, 45.8001, 95), t0() + Duration::minutes(5))
        .await
        .unwrap();
    assert_eq!(again.event_id, one.event_id);
    assert_eq!(
        again.confidence,
        Confidence::Reported,
        "the same account twice confirms nothing"
    );
    let elsewhere = db::report(&pool, &report(b, 45.802, 90), t0() + Duration::minutes(10))
        .await
        .unwrap();
    assert_ne!(
        elsewhere.event_id, one.event_id,
        "a report 200 m away is about another spot"
    );
    let two = db::report(&pool, &report(b, 45.8003, 85), t0() + Duration::minutes(20))
        .await
        .unwrap();
    assert_eq!(two.event_id, one.event_id);
    assert_eq!(two.confidence, Confidence::Confirmed);
    assert!(two.confirmed_now);
    let queued = sqlx::query_scalar!(
        "SELECT count(*) AS \"n!\" FROM moderation_queue WHERE target_type = 'road_event' AND target_id = $1",
        one.event_id
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        queued, 1,
        "a report that blocks routes for everyone is looked at"
    );
    let row = sqlx::query!(
        "SELECT class, max_height_m, valid_to FROM road_events WHERE id = $1",
        one.event_id
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(row.class, "vehicle_limit");
    assert_eq!(row.max_height_m, Some(3.3));
    assert_eq!(
        row.valid_to,
        Some(t0() + Duration::minutes(20) + Duration::days(7))
    );
    // A moderator removes one report: one account is left, a warning again.
    let report_id = sqlx::query_scalar!(
        "SELECT id FROM road_event_reports WHERE account_id = $1 AND event_id = $2",
        b,
        one.event_id
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(db::remove_report(&pool, report_id).await.unwrap());
    let c = sqlx::query_scalar!(
        "SELECT confidence FROM road_events WHERE id = $1",
        one.event_id
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(c, "reported");
}

async fn privileges(pool: &PgPool, role: &str, table: &str) -> Vec<&'static str> {
    let mut out = Vec::new();
    for p in ["SELECT", "INSERT", "UPDATE", "DELETE"] {
        let has = sqlx::query_scalar!(
            r#"SELECT has_table_privilege($1, $2, $3) AS "has!""#,
            role,
            table,
            p
        )
        .fetch_one(pool)
        .await
        .unwrap();
        if has {
            out.push(p);
        }
    }
    out
}

#[sqlx::test(migrations = "../../migrations")]
async fn each_role_holds_what_it_needs_of_the_road_events(pool: PgPool) {
    for (role, table, want) in [
        (
            "lunaway_app",
            "road_events",
            vec!["SELECT", "INSERT", "UPDATE"],
        ),
        (
            "lunaway_app",
            "road_event_reports",
            vec!["SELECT", "INSERT", "UPDATE"],
        ),
        ("lunaway_app", "road_event_sources", vec!["SELECT"]),
        ("lunaway_app", "road_event_purges", vec!["SELECT"]),
        (
            "lunaway_ingest",
            "road_events",
            vec!["SELECT", "INSERT", "UPDATE", "DELETE"],
        ),
        ("lunaway_ingest", "road_event_reports", vec!["DELETE"]),
        (
            "lunaway_ingest",
            "road_event_sources",
            vec!["SELECT", "UPDATE"],
        ),
        (
            "lunaway_ingest",
            "road_event_purges",
            vec!["SELECT", "UPDATE"],
        ),
    ] {
        assert_eq!(
            privileges(&pool, role, table).await,
            want,
            "{role} on {table}"
        );
    }
    for (column, want) in [
        ("account_id", false),
        ("created_at", true),
        ("geom", false),
        ("heading_deg", false),
    ] {
        let has = sqlx::query_scalar!(
            r#"SELECT has_column_privilege('lunaway_ingest', 'road_event_reports', $1, 'SELECT') AS "has!""#,
            column
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(
            has, want,
            "the poller, which parses untrusted payloads, never reads where an account was ({column})"
        );
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn new_accounts_cannot_block_and_one_account_cannot_lift_or_lower(pool: PgPool) {
    let report = |account, minutes: i64, height: f64| {
        let r = NewReport {
            account,
            kind: ReportKind::LowClearance,
            at: p(45.8, 1.25),
            heading_deg: Some(90),
            value_m: Some(height),
        };
        let pool = pool.clone();
        async move {
            db::report(&pool, &r, t0() + Duration::minutes(minutes))
                .await
                .unwrap()
        }
    };
    let fresh_a = account(&pool, "Loutre du Morvan").await;
    let fresh_b = account(&pool, "Héron des Landes").await;
    report(fresh_a, 0, 3.3).await;
    let fresh = report(fresh_b, 5, 3.3).await;
    assert_eq!(
        fresh.confidence,
        Confidence::Reported,
        "two level-0 accounts cost two key pairs: a warning only"
    );

    let a = account_of_level(&pool, "Martre des Vosges", 1).await;
    let b = account_of_level(&pool, "Grive du Jura", 1).await;
    let c = account_of_level(&pool, "Lynx du Doubs", 1).await;
    let d = account_of_level(&pool, "Chamois des Bauges", 1).await;
    let one = report(a, 10, 3.4).await;
    let two = report(b, 12, 3.4).await;
    assert_eq!(two.event_id, one.event_id);
    assert_eq!(two.confidence, Confidence::Confirmed);
    let lower = report(c, 14, 1.5).await;
    assert_ne!(
        lower.event_id, one.event_id,
        "a figure far from the confirmed one is another event"
    );
    assert_eq!(lower.confidence, Confidence::Reported);
    let height = sqlx::query_scalar!(
        "SELECT max_height_m FROM road_events WHERE id = $1",
        one.event_id
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        height,
        Some(3.4),
        "one account must not lower a confirmed limit"
    );

    let new_account = account(&pool, "Castor de Loire").await;
    assert_eq!(
        db::clear(
            &pool,
            new_account,
            one.event_id,
            t0() + Duration::minutes(20)
        )
        .await
        .unwrap(),
        db::Cleared::Noted(Confidence::Confirmed),
        "a level-0 account cannot lift a confirmed limit"
    );
    assert_eq!(
        db::clear(&pool, c, one.event_id, t0() + Duration::minutes(21))
            .await
            .unwrap(),
        db::Cleared::Noted(Confidence::Reported),
        "one trusted account makes it a warning"
    );
    assert_eq!(
        db::clear(&pool, d, one.event_id, t0() + Duration::minutes(22))
            .await
            .unwrap(),
        db::Cleared::Ended,
        "two trusted accounts end it"
    );
    assert_eq!(
        confidence_of(&pool, one.event_id).await.1.as_deref(),
        Some("cleared")
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_banned_or_deleted_account_stops_counting(pool: PgPool) {
    let a = account_of_level(&pool, "Martre des Vosges", 1).await;
    let b = account_of_level(&pool, "Grive du Jura", 1).await;
    let report = |account| NewReport {
        account,
        kind: ReportKind::Closure,
        at: p(45.8, 1.25),
        heading_deg: None,
        value_m: None,
    };
    let now = Utc::now();
    let first = db::report(&pool, &report(a), now).await.unwrap();
    let two = db::report(&pool, &report(b), now + Duration::minutes(5))
        .await
        .unwrap();
    assert_eq!(two.confidence, Confidence::Confirmed);
    accounts::ban(&pool, b, "vandal").await.unwrap();
    // The API weighs the events again, with its own role; the importers'
    // role cannot (it does not read who reported what).
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    assert_eq!(db::reweigh_community(&app).await.unwrap(), 1);
    assert_eq!(
        confidence_of(&pool, first.event_id).await.0,
        "reported",
        "a banned account's report no longer confirms a closure"
    );
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let denied = db::reweigh_community(&ingest)
        .await
        .expect_err("the importers' role does not read the reports' facts");
    assert!(format!("{denied:?}").contains("42501"), "{denied:?}");
    accounts::delete_account(&pool, a).await.unwrap();
    db::reweigh_community(&app).await.unwrap();
    assert_eq!(
        confidence_of(&pool, first.event_id).await.1.as_deref(),
        Some("moderated"),
        "with every reporter gone, the event is over"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn one_bad_record_does_not_fail_its_feed(pool: PgPool) {
    let mut too_heavy = event("heavy", "0000000001");
    too_heavy.class = EventClass::VehicleLimit;
    too_heavy.limits.max_weight_t = Some(3_500.0);
    let mut flat_ring = event("flat", "0000000001");
    flat_ring.geometry =
        SourceGeometry::Polygons(vec![vec![p(45.8, 1.25), p(45.81, 1.26), p(45.8, 1.25)]]);
    let long_id = event(&"x".repeat(201), "0000000001");
    let mut nul = event("nul", "0000000001");
    nul.description = Some("Route\0 barrée".to_owned());
    nul.raw = "{\"a\":\"\0\"}".to_owned();
    nul.url = Some("javascript:alert(1)".to_owned());
    let older = event("twice", "0000000001");
    let newer = event("twice", "0000000002");
    let r = store(
        &pool,
        "dialog",
        &[
            event("good", "0000000001"),
            too_heavy,
            flat_ring,
            long_id,
            nul,
            newer,
            older,
        ],
        t0(),
        true,
    )
    .await;
    assert_eq!(r.refused, 3, "{r:?}");
    assert_eq!(r.duplicates, 1, "{r:?}");
    assert_eq!(r.inserted, 3, "the good records are stored: {r:?}");
    let kept = sqlx::query!(
        "SELECT external_version, description, url FROM road_events WHERE external_id = $1",
        "twice"
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        kept.external_version, "0000000002",
        "the latest version wins"
    );
    let cleaned =
        sqlx::query!("SELECT description, url FROM road_events WHERE external_id = 'nul'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(cleaned.description.as_deref(), Some("Route barrée"));
    assert_eq!(cleaned.url, None, "only an https page is kept");
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_older_snapshot_does_not_bring_back_what_a_newer_increment_ended(pool: PgPool) {
    store(&pool, "dir", &[event("r1", "0000000001")], t0(), true).await;
    let mut w = db::begin_writer(&pool).await.unwrap();
    db::end_records(
        &mut w,
        "dir",
        &["r1".to_owned()],
        t0() + Duration::minutes(30),
    )
    .await
    .unwrap();
    w.commit().await.unwrap();
    // The aggregate published before that end, read after it.
    let mut w = db::begin_writer(&pool).await.unwrap();
    db::upsert(
        &mut w,
        "dir",
        &[event("r1", "0000000001")],
        t0() + Duration::minutes(10),
        t0() + Duration::minutes(50),
        true,
    )
    .await
    .unwrap();
    w.commit().await.unwrap();
    assert_eq!(
        revision_of(&pool, "r1").await.1.as_deref(),
        Some("source_end"),
        "an aggregate older than the end keeps it ended"
    );
    // A publication after the end carries it again: it is live again.
    store(
        &pool,
        "dir",
        &[event("r1", "0000000001")],
        t0() + Duration::hours(2),
        true,
    )
    .await;
    assert_eq!(revision_of(&pool, "r1").await.1, None);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_match_made_on_an_old_geometry_is_not_stored(pool: PgPool) {
    store(&pool, "dir", &[event("r1", "0000000001")], t0(), true).await;
    let task = db::match_tasks(&pool, "g1", 10)
        .await
        .unwrap()
        .into_iter()
        .next()
        .unwrap();
    // While the engine works, the source moves the section.
    let mut moved = event("r1", "0000000002");
    moved.geometry = SourceGeometry::Lines(vec![vec![p(47.80, -3.30), p(47.80, -3.27)]]);
    store(&pool, "dir", &[moved], t0() + Duration::minutes(3), true).await;
    let mut w = db::begin_writer(&pool).await.unwrap();
    let stored = db::set_match(
        &mut w,
        &task,
        Some(&[vec![p(47.75, -3.30), p(47.75, -3.27)]]),
        "g1",
    )
    .await
    .unwrap();
    w.commit().await.unwrap();
    assert!(!stored, "the lines of the old section must not be stored");
    let quality =
        sqlx::query_scalar!("SELECT match_quality FROM road_events WHERE external_id = 'r1'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        quality, "pending",
        "the moved section waits for its own match"
    );
    let fresh = db::match_tasks(&pool, "g1", 10).await.unwrap();
    let mut w = db::begin_writer(&pool).await.unwrap();
    assert!(
        db::set_match(&mut w, &fresh[0], None, "g1").await.unwrap(),
        "a task read after the move is stored"
    );
    w.commit().await.unwrap();
}

#[sqlx::test(migrations = "../../migrations")]
async fn revisions_commit_in_the_order_they_are_taken(pool: PgPool) {
    store(&pool, "dir", &[event("p", "0000000001")], t0(), true).await;
    let mut first = db::begin_writer(&pool).await.unwrap();
    db::upsert(
        &mut first,
        "dir",
        &[event("a", "0000000001")],
        t0(),
        t0(),
        true,
    )
    .await
    .unwrap();
    let writer = {
        let pool = pool.clone();
        tokio::spawn(async move {
            let mut w = db::begin_writer(&pool).await.unwrap();
            db::upsert(&mut w, "dir", &[event("b", "0000000001")], t0(), t0(), true)
                .await
                .unwrap();
            w.commit().await.unwrap();
        })
    };
    // A write outside the writers' lock: the migration's trigger takes it.
    let stray = {
        let pool = pool.clone();
        tokio::spawn(async move {
            sqlx::query!(
                "UPDATE road_events SET ended_at = now(), end_reason = 'moderated' WHERE external_id = 'p'"
            )
            .execute(&pool)
            .await
            .unwrap();
        })
    };
    tokio::time::sleep(std::time::Duration::from_millis(300)).await;
    assert!(
        !writer.is_finished() && !stray.is_finished(),
        "a revision taken while another writer is open would commit out of order"
    );
    first.commit().await.unwrap();
    writer.await.unwrap();
    stray.await.unwrap();
    let a = revision_of(&pool, "a").await.0;
    assert!(revision_of(&pool, "b").await.0 > a);
    assert!(
        revision_of(&pool, "p").await.0 > a,
        "a phone that read revision a must not miss what committed after it"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_community_event_keeps_the_published_position_and_no_heading(pool: PgPool) {
    let reporter = account(&pool, "Loutre du Morvan").await;
    let exact = p(45.812_345_6, 1.256_789_1);
    let done = db::report(
        &pool,
        &NewReport {
            account: reporter,
            kind: ReportKind::Closure,
            at: exact,
            heading_deg: Some(123),
            value_m: None,
        },
        t0(),
    )
    .await
    .unwrap();
    // What the importers' role reads: the event's position, published
    // already, and nothing that ties a report to an account.
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let joined = sqlx::query!(
        r#"SELECT e.heading_deg,
                  ST_Y(e.geom_source::geometry) AS "lat!", ST_X(e.geom_source::geometry) AS "lon!"
           FROM road_events e WHERE e.id = $1"#,
        done.event_id
    )
    .fetch_one(&ingest)
    .await
    .unwrap();
    assert_eq!(
        (joined.lat, joined.lon, joined.heading_deg),
        (45.8123, 1.2568, None),
        "the event gives the published position only"
    );
    for closed in [
        "SELECT account_id::text AS a FROM road_event_reports LIMIT 1",
        "SELECT salt AS a FROM road_event_report_salt",
        "SELECT reporter AS a FROM road_event_report_facts LIMIT 1",
    ] {
        let denied = sqlx::query_scalar::<_, String>(sqlx::AssertSqlSafe(closed))
            .fetch_one(&ingest)
            .await
            .expect_err("the importers never link a report to an account");
        assert_eq!(
            denied.as_database_error().and_then(|e| e.code()).as_deref(),
            Some("42501"),
            "{closed}"
        );
    }
    let at = p(joined.lat, joined.lon);
    assert!(at.distance_m(exact) > 1.0 && at.distance_m(exact) < 10.0);
    let exact_column = sqlx::query!(
        "SELECT ST_AsText(geom) AS g FROM road_event_reports WHERE event_id = $1",
        done.event_id
    )
    .fetch_one(&ingest)
    .await;
    assert_eq!(
        exact_column
            .expect_err("the report's own position stays closed to the importers")
            .as_database_error()
            .and_then(|e| e.code())
            .as_deref(),
        Some("42501")
    );
    // The same spot is still recognised from the coarse position: a second
    // account's report joins the event, whichever way it heads, since the
    // event keeps no heading (a closure reported on one carriageway may
    // then block both: a detour too many, never a closure missed).
    let other = account(&pool, "Héron des Landes").await;
    let second = db::report(
        &pool,
        &NewReport {
            account: other,
            kind: ReportKind::Closure,
            at: p(45.812_4, 1.256_9),
            heading_deg: Some(300),
            value_m: None,
        },
        t0() + Duration::minutes(5),
    )
    .await
    .unwrap();
    assert_eq!(second.event_id, done.event_id);
    // The view's key tells two accounts apart on one event, and one account
    // on two events cannot be followed from one to the other.
    let elsewhere = db::report(
        &pool,
        &NewReport {
            account: reporter,
            kind: ReportKind::Closure,
            at: p(45.9, 1.3),
            heading_deg: None,
            value_m: None,
        },
        t0() + Duration::minutes(10),
    )
    .await
    .unwrap();
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let keys = sqlx::query!(
        r#"SELECT event_id AS "event_id!", reporter AS "reporter!"
           FROM road_event_report_facts ORDER BY created_at"#
    )
    .fetch_all(&app)
    .await
    .unwrap();
    assert_eq!(keys.len(), 3);
    assert_ne!(keys[0].reporter, keys[1].reporter, "two accounts, two keys");
    assert_eq!(keys[2].event_id, elsewhere.event_id);
    assert_ne!(
        keys[0].reporter, keys[2].reporter,
        "the same account on another event has another key"
    );
    let second_salt =
        sqlx::query!("INSERT INTO road_event_report_salt (salt) VALUES (repeat('a', 64))")
            .execute(&pool)
            .await
            .expect_err("one salt: two would show every report twice, one account as two");
    assert_eq!(
        second_salt
            .as_database_error()
            .and_then(|e| e.code())
            .as_deref(),
        Some("23505")
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_purge_after_the_head_was_read_sends_the_client_back_to_the_whole_set(pool: PgPool) {
    store(&pool, "dir", &[event("kept", "0000000001")], t0(), true).await;
    // The client holds every change up to here.
    let held = db::feed_head(&pool).await.unwrap().revision;
    let mut ended = event("gone", "0000000001");
    ended.ended = Some(EndReason::SourceEnd);
    store(&pool, "dir", &[ended], t0(), true).await;
    // The API reads the head (it keeps it five seconds), then a purge runs
    // before the page is read: the end of "gone" leaves the table.
    let head = db::feed_head(&pool).await.unwrap();
    assert_eq!(
        db::changed_since(&pool, held, head.revision, 100)
            .await
            .unwrap()
            .map(|rows| rows.len()),
        Some(1),
        "before the purge, the client receives the end"
    );
    db::lifecycle(
        &pool,
        t0() + Duration::days(9),
        Duration::days(30),
        Duration::days(7),
        Duration::days(14),
    )
    .await
    .unwrap();
    assert!(
        head.purged_through <= held,
        "the head read before the purge still honours the cursor"
    );
    assert_eq!(
        db::changed_since(&pool, held, head.revision, 100)
            .await
            .unwrap(),
        None,
        "the page re-reads the purge horizon with its rows: the client starts over instead of \
         missing an end"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_report_waits_three_seconds_for_the_feeds_then_gives_up(pool: PgPool) {
    let reporter = account(&pool, "Loutre du Morvan").await;
    // A feed is being written: it holds the writers' lock.
    let feed = db::begin_writer(&pool).await.unwrap();
    let started = std::time::Instant::now();
    let report = tokio::time::timeout(
        std::time::Duration::from_secs(20),
        db::report(
            &pool,
            &NewReport {
                account: reporter,
                kind: ReportKind::Closure,
                at: p(45.8, 1.25),
                heading_deg: None,
                value_m: None,
            },
            t0(),
        ),
    )
    .await
    .expect("a report never holds the API's connection for long");
    let waited = started.elapsed();
    let error = report.expect_err("the lock is held throughout");
    assert!(db::is_busy(&error), "{error}");
    assert!(
        (2.5..10.0).contains(&waited.as_secs_f64()),
        "about three seconds: {waited:?}"
    );
    feed.commit().await.unwrap();
    assert!(
        db::report(
            &pool,
            &NewReport {
                account: reporter,
                kind: ReportKind::Closure,
                at: p(45.8, 1.25),
                heading_deg: None,
                value_m: None,
            },
            t0(),
        )
        .await
        .is_ok(),
        "once the feed is written, the report goes through"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_phones_feed_leaves_out_the_feeds_the_graph_does_not_cover(pool: PgPool) {
    let routed = || async {
        sqlx::query_scalar::<_, bool>(
            "SELECT bool_and(routed) FROM road_event_sources WHERE id IN ('ndw', 'dgt')",
        )
        .fetch_one(&pool)
        .await
        .unwrap()
    };
    assert!(
        routed().await,
        "the Europe graph covers the Netherlands and Spain: their feeds are routed"
    );
    // A feed the graph would not cover, as the Spanish one was on the
    // France graph.
    sqlx::query("UPDATE road_event_sources SET routed = false WHERE id = 'dgt'")
        .execute(&pool)
        .await
        .unwrap();
    store(&pool, "dir", &[event("fr-1", "0000000001")], t0(), true).await;
    store(&pool, "dgt", &[event("es-1", "0000000001")], t0(), true).await;
    let head = db::feed_head(&pool).await.unwrap();
    let ids = |rows: Vec<db::EventRow>| rows.into_iter().map(|r| r.source).collect::<Vec<_>>();
    assert_eq!(
        ids(
            db::live_events(&pool, &[EventClass::Closure], false, 0, head.revision, 100)
                .await
                .unwrap()
        ),
        ["dir"],
        "a closure off the graph cannot be on a route it computes"
    );
    assert_eq!(
        ids(db::changed_since(&pool, 0, head.revision, 100)
            .await
            .unwrap()
            .unwrap()),
        ["dir"],
        "nor in the changes a phone polls every three minutes"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_purged_report_takes_its_key_with_it(pool: PgPool) {
    let a = account_of_level(&pool, "Loutre du Morvan", 1).await;
    let now = Utc::now();
    let key = lunaway_db::idempotency::Key::of(
        a,
        "road-key-purged",
        lunaway_db::idempotency::Operation::ReportRoadEvent,
        &serde_json::json!({"kind": "closure"}),
    );
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let report = NewReport {
        account: a,
        kind: ReportKind::Closure,
        at: p(45.8, 1.25),
        heading_deg: None,
        value_m: None,
    };
    db::report_once(&app, &key, &report, now).await.unwrap();
    let keys = || async {
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM idempotency_keys")
            .fetch_one(&pool)
            .await
            .unwrap()
    };
    assert_eq!(keys().await, 1);
    // The importers' role purges the reports and holds no right on the
    // keys: the trigger drops them with its owner's rights.
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let done = db::lifecycle(
        &ingest,
        now + Duration::days(15),
        Duration::hours(6),
        Duration::days(7),
        Duration::days(14),
    )
    .await
    .unwrap();
    assert_eq!(done.reports_purged, 1);
    assert_eq!(
        keys().await,
        0,
        "a key names the account, the time and the request of a report the privacy page says is erased"
    );
}

/// The ids of `rows`, by external id.
fn external_ids(rows: &[db::EventRow]) -> Vec<&str> {
    rows.iter().map(|r| r.external_id.as_str()).collect()
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_event_reaches_the_phones_when_its_start_comes_within_the_window(pool: PgPool) {
    let window: bool =
        sqlx::query_scalar("SELECT road_events_feed_window() = make_interval(hours => $1::int)")
            .bind(i32::try_from(db::FEED_WINDOW_HOURS).unwrap())
            .fetch_one(&pool)
            .await
            .unwrap();
    assert!(window, "the Rust copy of the window is the one SQL applies");
    let now = Utc::now();
    let mut today = event("today", "0000000001");
    today.valid_from = now - Duration::hours(1);
    let mut soon = event("soon", "0000000001");
    soon.valid_from = now + Duration::hours(db::FEED_WINDOW_HOURS - 1);
    let mut later = event("later", "0000000001");
    later.valid_from = now + Duration::days(3);
    later.valid_to = Some(now + Duration::days(4));
    store(&pool, "ndw", &[today, soon, later], now, true).await;
    let head = db::feed_head(&pool).await.unwrap();
    let whole = db::live_events(&pool, &[EventClass::Closure], false, 0, head.revision, 100)
        .await
        .unwrap();
    assert_eq!(
        external_ids(&whole),
        ["today", "soon"],
        "a phone's whole set holds what is in force or starts within two days, \
         not two weeks of planned works"
    );
    let changes = db::changed_since(&pool, 0, head.revision, 100)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(external_ids(&changes), ["today", "soon"]);

    // While it waits, a new version of the later event is not sent: no
    // phone holds it.
    let mut moved = event("later", "0000000002");
    moved.valid_from = now + Duration::days(3);
    moved.valid_to = Some(now + Duration::days(5));
    store(&pool, "ndw", &[moved], now, true).await;
    assert_eq!(db::feed_head(&pool).await.unwrap().revision, head.revision);

    // The poller's pass, as the importers' role, 20 hours on: the later
    // event starts 52 hours after, still out; 25 hours on, it enters.
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let pass = |at| {
        db::lifecycle(
            &ingest,
            at,
            Duration::days(30),
            Duration::days(7),
            Duration::days(14),
        )
    };
    assert_eq!(
        pass(now + Duration::hours(20))
            .await
            .unwrap()
            .entered_window,
        0
    );
    let done = pass(now + Duration::hours(25)).await.unwrap();
    assert_eq!(done.entered_window, 1);
    let next = db::feed_head(&pool).await.unwrap();
    let changes = db::changed_since(&pool, head.revision, next.revision, 100)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        external_ids(&changes),
        ["later"],
        "the cursor a phone already holds brings the event that entered the window, \
         though the event itself did not change"
    );
    assert!(changes[0].in_window && changes[0].ended_at.is_none());

    // Postponed past the window by its source: phones that hold it drop it.
    let mut postponed = event("soon", "0000000002");
    postponed.valid_from = Utc::now() + Duration::days(6);
    store(&pool, "ndw", &[postponed], Utc::now(), true).await;
    let last = db::feed_head(&pool).await.unwrap();
    let changes = db::changed_since(&pool, next.revision, last.revision, 100)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(external_ids(&changes), ["soon"]);
    assert!(
        !changes[0].in_window,
        "a start moved past the window takes the event out of the phones' sets"
    );
    let whole = db::live_events(&pool, &[EventClass::Closure], false, 0, last.revision, 100)
        .await
        .unwrap();
    assert_eq!(
        external_ids(&whole),
        ["today", "later"],
        "nor is it in the whole set a new phone starts from"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_events_near_a_route_hold_everything_within_their_widths_far_north(pool: PgPool) {
    use crate::routing::moved;
    // The route of the restrictions' test near Tromsø: 30 km east in one
    // segment, then 2 km north.
    let route = [p(69.6, 18.0), p(69.6, 18.785), p(69.618, 18.785)];
    let side = p(69.609, 18.785);
    let wide = moved(&pool, side, 1_000.0, 90.0).await;
    let far = moved(&pool, side, 1_300.0, 90.0).await;
    // Placed by the matcher 30 m south of the long segment's middle, its
    // own point 5 km away.
    let middle = p(69.6, 18.3925);
    let placed_from = moved(&pool, middle, 30.0, 180.0).await;
    let placed_to = moved(&pool, placed_from, 50.0, 90.0).await;
    let own_point = moved(&pool, middle, 5_000.0, 180.0).await;
    let events: Vec<NewEvent> = [("wide", wide), ("far", far), ("matched", own_point)]
        .into_iter()
        .map(|(id, at)| NewEvent {
            geometry: SourceGeometry::Point(at),
            ..event(id, "0000000001")
        })
        .collect();
    store(&pool, "dir", &events, t0(), true).await;
    sqlx::query(
        "UPDATE road_events SET geom_matched = ST_SetSRID(ST_MakeLine(
            ST_MakePoint($1, $2), ST_MakePoint($3, $4)), 4326)::geography
         WHERE external_id = 'matched'",
    )
    .bind(placed_from.lon())
    .bind(placed_from.lat())
    .bind(placed_to.lon())
    .bind(placed_to.lat())
    .execute(&pool)
    .await
    .unwrap();
    let api = as_role(&pool, "SET ROLE lunaway_app").await;
    // The API's widths, 20 m and 1 000 m, with its margin of 11 m.
    let near = db::events_near(&api, &route, 31.0, 1_011.0).await.unwrap();
    let mut found: Vec<&str> = near.iter().map(|e| e.external_id.as_str()).collect();
    found.sort_unstable();
    assert_eq!(
        found,
        ["matched", "wide"],
        "a placed line within 31 m and an own point within 1 011 m are near the \
         route at 70 degrees north, beside a 30 km segment; 1 300 m away is not"
    );
}
