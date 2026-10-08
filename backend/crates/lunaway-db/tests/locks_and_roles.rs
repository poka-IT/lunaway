//! What the schema enforces beyond the shape of rows: one writer of the
//! catalogue at a time, the stored reason codes, the sync epoch, and what
//! each service role may do.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::time::{Duration, Instant};

use chrono::Utc;
use lunaway_db::{
    PgPool, conflation,
    records::{self, NewRecord},
};
use lunaway_domain::{NormalizedRecord, PlaceKind, Position, SourceId, conflation::Reason};
use sqlx::postgres::PgPoolOptions;

/// How long a blocked writer is watched before the test calls it blocked.
const WATCH: Duration = Duration::from_millis(400);

fn record(name: &str) -> NormalizedRecord {
    let mut r = NormalizedRecord::new(PlaceKind::Campsite, Position::new(47.4, -0.6).unwrap());
    r.name = Some(name.to_owned());
    r
}

async fn insert(pool: &PgPool, external_id: &str) {
    let r = record(external_id);
    let raw = serde_json::json!({});
    records::upsert(
        pool,
        &SourceId::OSM,
        &[NewRecord {
            external_id,
            external_url: None,
            record: &r,
            raw: &raw,
            fetched_at: Utc::now(),
            scope: None,
        }],
    )
    .await
    .unwrap();
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_writer_of_places_waits_for_the_writer_before_it(pool: PgPool) {
    let first = conflation::begin_writer(&pool).await.unwrap();
    let other_pool = pool.clone();
    let second = tokio::spawn(async move {
        let tx = conflation::begin_writer(&other_pool).await.unwrap();
        let got = Instant::now();
        tx.commit().await.unwrap();
        got
    });
    tokio::time::sleep(WATCH).await;
    assert!(
        !second.is_finished(),
        "a second writer must wait: the change feed is safe only with one writer at a time"
    );
    let released = Instant::now();
    first.commit().await.unwrap();
    assert!(second.await.unwrap() >= released);
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_import_waits_for_a_running_conflation(pool: PgPool) {
    insert(&pool, "way/1").await;
    // The conflation holds the lock and the flagged records, as `run` does.
    let mut conflation_tx = conflation::begin_writer(&pool).await.unwrap();
    let dirty = conflation::dirty(&mut conflation_tx).await.unwrap();
    assert_eq!(dirty.len(), 1);

    // Neither statement touches the locked record: only the writers' lock
    // can hold them back.
    let import_pool = pool.clone();
    let import = tokio::spawn(async move {
        insert(&import_pool, "way/2").await;
        Instant::now()
    });
    let retire_pool = pool.clone();
    let retire = tokio::spawn(async move {
        records::retire_missing(&retire_pool, &SourceId::ATOUT_FRANCE, None, &[], Utc::now())
            .await
            .unwrap();
        Instant::now()
    });
    tokio::time::sleep(WATCH).await;
    assert!(
        !import.is_finished() && !retire.is_finished(),
        "an import running beside a conflation could lock the same records in the opposite \
         order; it must wait for the lock instead"
    );
    let released = Instant::now();
    conflation::clear_dirty(&mut conflation_tx, &dirty)
        .await
        .unwrap();
    conflation_tx.commit().await.unwrap();
    assert!(import.await.unwrap() >= released);
    assert!(retire.await.unwrap() >= released);
    let live = records::live_count(&pool, &SourceId::OSM, None)
        .await
        .unwrap();
    assert_eq!(live, 2, "the import ran in full once released");
}

#[sqlx::test(migrations = "../../migrations")]
async fn every_reason_code_is_stored_and_an_empty_one_refused(pool: PgPool) {
    insert(&pool, "way/1").await;
    insert(&pool, "way/2").await;
    let mut ids: Vec<uuid::Uuid> = sqlx::query_scalar!("SELECT id FROM source_records")
        .fetch_all(&pool)
        .await
        .unwrap();
    ids.sort();
    let store = |reason: String| {
        sqlx::query!(
            r#"
            INSERT INTO match_pairs (record_a, record_b, score, decision, reason, components)
            VALUES ($1, $2, 0.7, 'review', $3, '{}')
            ON CONFLICT (record_a, record_b) DO UPDATE SET reason = EXCLUDED.reason
            "#,
            ids[0],
            ids[1],
            reason,
        )
        .execute(&pool)
    };
    for r in Reason::ALL {
        store(r.code().to_owned())
            .await
            .unwrap_or_else(|e| panic!("{r:?} refused: {e}"));
    }
    assert!(
        store(String::new()).await.is_err(),
        "a pair without a reason cannot be explained to a reviewer"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_takedown_stores_a_code_and_never_a_text(pool: PgPool) {
    use lunaway_domain::takedown::TakedownCode;
    let place = uuid::Uuid::now_v7();
    let content = lunaway_domain::conflation::PlaceContent {
        name: None,
        kind: PlaceKind::Parking,
        position: Position::new(47.3, -0.5).unwrap(),
        overnight: lunaway_domain::OvernightStatus::Allowed,
        services: Vec::new(),
        activities: Vec::new(),
        description: None,
        address: lunaway_domain::Address::default(),
        price_parking_eur: None,
        price_services_eur: None,
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
    };
    let mut tx = conflation::begin_writer(&pool).await.unwrap();
    conflation::upsert_place(
        &mut tx,
        conflation::PlaceWrite {
            id: place,
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
    let store = |reason: String| {
        sqlx::query!(
            r#"
            INSERT INTO place_takedowns (place_id, reason) VALUES ($1, $2)
            ON CONFLICT (place_id) DO UPDATE SET reason = EXCLUDED.reason
            "#,
            place,
            reason,
        )
        .execute(&pool)
    };
    for c in TakedownCode::ALL {
        store(c.code().to_owned())
            .await
            .unwrap_or_else(|e| panic!("{c:?} refused: {e}"));
    }
    assert!(
        store("GDPR request from Jean Dupont, 12 rue des Lilas".to_owned())
            .await
            .is_err(),
        "a free text could name the requester: only the codes are stored"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_feed_identity_changes_when_a_restore_regenerates_the_epoch(pool: PgPool) {
    let head = lunaway_db::places::feed_head(&pool).await.unwrap();
    assert_eq!(head.last_seq, 0, "an empty feed");
    assert_eq!(lunaway_db::places::feed_head(&pool).await.unwrap(), head);
    // The statement of docs/deploy.md, "Backups and restore".
    sqlx::query!("UPDATE sync_epoch SET epoch = gen_random_uuid(), created_at = now()")
        .execute(&pool)
        .await
        .unwrap();
    let after = lunaway_db::places::feed_head(&pool).await.unwrap();
    assert_ne!(after.identity(), head.identity());
    assert_eq!(after.database, head.database);
    let second_row = sqlx::query!("INSERT INTO sync_epoch (singleton) VALUES (false)")
        .execute(&pool)
        .await;
    assert!(second_row.is_err(), "there is one epoch per database");
}

/// A pool whose connections act as `role`, as the services' logins do.
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

/// The tables the API writes: accounts and every contribution.
const COMMUNITY_TABLES: [&str; 15] = [
    "accounts",
    "device_keys",
    "sessions",
    "recovery_codes",
    "account_endorsements",
    "muted_authors",
    "reviews",
    "photos",
    "confirmations",
    "issue_reports",
    "content_reports",
    "moderation_queue",
    "favorite_lists",
    "favorite_items",
    "place_submissions",
];

fn denied(result: Result<sqlx::postgres::PgQueryResult, sqlx::Error>, why: &str) {
    let denied = result.expect_err(why);
    assert_eq!(
        denied.as_database_error().and_then(|e| e.code()).as_deref(),
        Some("42501"),
        "{why}: {denied}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_api_role_writes_contributions_and_never_the_catalogue(pool: PgPool) {
    for t in [
        "sources",
        "source_records",
        "places",
        "place_sources",
        "sync_epoch",
    ] {
        assert_eq!(
            privileges(&pool, "lunaway_app", t).await,
            ["SELECT"],
            "lunaway_app on {t}: the API reads the catalogue and writes none of it"
        );
    }
    for t in [
        "match_pairs",
        "conflation_constraints",
        "municipalities",
        "_sqlx_migrations",
        "enforcement_devices",
    ] {
        assert!(
            privileges(&pool, "lunaway_app", t).await.is_empty(),
            "lunaway_app on {t}: the API serves nothing from it"
        );
    }
    for t in COMMUNITY_TABLES {
        assert_eq!(
            privileges(&pool, "lunaway_app", t).await,
            ["SELECT", "INSERT", "UPDATE", "DELETE"],
            "lunaway_app on {t}"
        );
    }
    assert_eq!(
        privileges(&pool, "lunaway_app", "enforcement_sources").await,
        ["SELECT"],
        "lunaway_app on enforcement_sources: the lists' reads it cites"
    );
    assert_eq!(
        privileges(&pool, "lunaway_app", "place_layer").await,
        ["SELECT"],
        "lunaway_app on place_layer: the API names the places' tiles version, the worker moves it"
    );
    assert_eq!(
        privileges(&pool, "lunaway_app", "place_search_words").await,
        ["SELECT"],
        "the search corrects a typo to the words of places, which only their writers add"
    );
    for (column, granted) in [
        ("id", true),
        ("line", true),
        ("point", true),
        ("revision", true),
        ("device_key", false),
        ("content_hash", false),
    ] {
        let has = sqlx::query_scalar!(
            r#"SELECT has_column_privilege('lunaway_app', 'enforcement_items', $1, 'SELECT') AS "has!""#,
            column
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(
            has, granted,
            "the API serves the built items, and never the key that leads to a zone's camera \
             ({column})"
        );
    }
    assert_eq!(
        privileges(&pool, "lunaway_app", "place_refresh_queue").await,
        ["INSERT"],
        "the API queues a place for the worker and reads nothing back"
    );
    assert_eq!(
        privileges(&pool, "lunaway_app", "source_reads").await,
        ["SELECT"],
        "the API dates what it serves by the last read and records none"
    );
    assert!(
        privileges(&pool, "lunaway_app", "place_takedowns")
            .await
            .is_empty(),
        "the API's role cannot take a place down: a leak of its credentials must not empty \
         the catalogue"
    );
    assert!(
        privileges(&pool, "lunaway_app", "takedown_cells")
            .await
            .is_empty(),
        "the API never sees the takedowns' cells, nor holds the secret that reads them"
    );
    assert_eq!(
        privileges(&pool, "lunaway_app", "place_holds").await,
        ["SELECT"],
        "the moderators read the holds and decide them, column by column"
    );
    assert_eq!(
        privileges(&pool, "lunaway_app", "place_hold_releases").await,
        ["SELECT", "INSERT"],
        "a release is journaled and never rewritten"
    );
    assert_eq!(
        privileges(&pool, "lunaway_app", "banned_keys").await,
        ["SELECT", "INSERT", "DELETE"],
        "a banned key's hash is written at the deletion and removed after two years, never \
         rewritten"
    );
    assert_eq!(
        privileges(&pool, "lunaway_app", "confirmation_tallies").await,
        ["SELECT", "INSERT", "UPDATE", "DELETE"],
        "the daily retention job writes what the deleted confirmations gave"
    );
    insert(&pool, "way/1").await;
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    assert_eq!(
        lunaway_db::sources::list(&app).await.unwrap().len(),
        18,
        "the API reads the sources, with their agreements' terms"
    );
    lunaway_db::places::feed_head(&app).await.unwrap();
    lunaway_db::search::search(&app, "grilon", None, 5)
        .await
        .expect("the API role reads the words of places and their statistics");
    denied(
        sqlx::query!("UPDATE source_records SET needs_conflation = false")
            .execute(&app)
            .await,
        "an API compromise must not rewrite the catalogue",
    );
    denied(
        sqlx::query!(
            r#"
            INSERT INTO source_records (id, source_id, external_id, kind, geom, data, raw, fetched_at)
            VALUES ($1, 'community', 'x', 'parking', ST_SetSRID(ST_MakePoint(2, 47), 4326)::geography,
                    '{}', '{}', now())
            "#,
            uuid::Uuid::now_v7()
        )
        .execute(&app)
        .await,
        "not even a community record: submissions go through the worker",
    );
    denied(
        sqlx::query!("UPDATE places SET name = 'x'")
            .execute(&app)
            .await,
        "the API never writes a place",
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_api_role_runs_an_account_from_creation_to_deletion(pool: PgPool) {
    use lunaway_db::{accounts, community, conflation::PlaceWrite, lists};
    // A place to contribute to, written by the conflation's path.
    let place = uuid::Uuid::now_v7();
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
    };
    let mut tx = conflation::begin_writer(&pool).await.unwrap();
    conflation::upsert_place(
        &mut tx,
        PlaceWrite {
            id: place,
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

    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let (account, _) = accounts::create_with_key(
        &app,
        accounts::NewAccount {
            pseudonym: "Hérisson du Vercors",
            thumbprint: &"t".repeat(43),
            public_key: &[4; 65],
            session_hash: &[1; 32],
            session_ttl_secs: 3_600.0,
        },
    )
    .await
    .unwrap();
    community::rate(&app, account.id, place, 4).await.unwrap();
    community::rate(&app, account.id, place, 5)
        .await
        .expect("queueing a place already queued needs no more than INSERT");
    let list = lists::create(&app, account.id, "Été")
        .await
        .unwrap()
        .unwrap();
    lists::add(&app, account.id, list, &[place])
        .await
        .unwrap()
        .unwrap();
    accounts::set_recovery_code(&app, account.id, &[7; 32])
        .await
        .unwrap();
    let deleted = accounts::delete_account(&app, account.id).await.unwrap();
    assert!(
        deleted.is_some(),
        "the API role deletes an account and what hangs on it"
    );
    assert!(accounts::account(&app, account.id).await.unwrap().is_none());
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_import_role_writes_what_the_pipeline_writes_and_deletes_no_place(pool: PgPool) {
    for t in ["source_records", "places"] {
        assert_eq!(
            privileges(&pool, "lunaway_ingest", t).await,
            ["SELECT", "INSERT", "UPDATE"],
            "lunaway_ingest on {t}: a gone place is a tombstone the feed reports, never a DELETE"
        );
    }
    for t in ["place_sources", "match_pairs", "municipalities"] {
        assert_eq!(
            privileges(&pool, "lunaway_ingest", t).await,
            ["SELECT", "INSERT", "UPDATE", "DELETE"],
            "lunaway_ingest on {t}"
        );
    }
    for t in [
        "enforcement_devices",
        "enforcement_items",
        "enforcement_sources",
    ] {
        assert_eq!(
            privileges(&pool, "lunaway_ingest", t).await,
            ["SELECT", "INSERT", "UPDATE"],
            "lunaway_ingest on {t}: a camera gone is a tombstone the feed reports"
        );
    }
    for t in ["sources", "sync_epoch"] {
        assert_eq!(
            privileges(&pool, "lunaway_ingest", t).await,
            ["SELECT"],
            "lunaway_ingest on {t}: written by migrations and restores only; the pack builder \
             names the feed's copy"
        );
    }
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    lunaway_db::places::feed_head(&ingest)
        .await
        .expect("the pack builder reads the feed's identity with the import role");
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "place_layer").await,
        ["SELECT", "UPDATE"],
        "the worker and a takedown move the places' tiles version; its row is the migration's"
    );
    lunaway_db::place_tiles::publish_layer_now(&ingest)
        .await
        .expect("a takedown publishes the places layer with the import role");
    // The worker reads every source's ratings and the hides to write the
    // rating the filters use.
    let mut tx = lunaway_db::conflation::begin_writer(&ingest).await.unwrap();
    lunaway_db::place_ratings::refresh_filter_ratings(&mut tx)
        .await
        .expect("the worker computes the filter ratings with the import role");
    tx.commit().await.unwrap();
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "place_search_words").await,
        ["SELECT", "INSERT", "DELETE"],
        "a write of places adds and removes their words, through the triggers that run with the \
         writer's role"
    );
    sqlx::query(
        "INSERT INTO places (id, kind, name, geom, overnight, content_hash)
         VALUES ($1, 'parking', 'Parking des Grillons',
                 ST_SetSRID(ST_MakePoint(2, 47), 4326)::geography, 'unknown', 'h')",
    )
    .bind(uuid::Uuid::now_v7())
    .execute(&ingest)
    .await
    .expect("the import role writes a place, and its words with it");
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "source_reads").await,
        ["SELECT", "INSERT", "UPDATE"],
        "the importers date their reads, the pack builder reads the dates"
    );
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "place_towns").await,
        ["SELECT", "INSERT", "UPDATE", "DELETE"],
        "the worker rebuilds the towns of the search, a town gone included"
    );
    assert_eq!(
        privileges(&pool, "lunaway_app", "place_towns").await,
        ["SELECT"],
        "the API lists the towns and writes none"
    );
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "place_takedowns").await,
        ["SELECT", "INSERT"],
        "the catalogue's writer logs a takedown and never rewrites one"
    );
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "takedown_cells").await,
        ["SELECT", "INSERT"],
        "a takedown's zone is added to, never rewritten nor removed"
    );
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "confirmation_tallies").await,
        ["SELECT"],
        "the worker reads what aged-out confirmations gave a place"
    );
    assert!(
        privileges(&pool, "lunaway_ingest", "banned_keys")
            .await
            .is_empty(),
        "the importers have nothing to do with accounts"
    );
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "place_holds").await,
        ["SELECT", "INSERT"],
        "the worker writes a hold's records, column by column, never its decision"
    );
    let decides: bool = sqlx::query_scalar!(
        r#"SELECT has_column_privilege('lunaway_ingest', 'place_holds', 'status', 'UPDATE') AS "has!""#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(!decides, "a release is the moderators' decision");
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "place_hold_releases").await,
        ["SELECT"],
        "the worker reads the journal of releases and writes none"
    );
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "takedown_key").await,
        ["SELECT", "INSERT"]
    );
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "conflation_constraints").await,
        ["SELECT", "INSERT"],
        "the worker ties an edit to its place; it never rewrites a human decision"
    );
    for t in ["reviews", "photos", "confirmations", "issue_reports"] {
        assert_eq!(
            privileges(&pool, "lunaway_ingest", t).await,
            ["SELECT"],
            "lunaway_ingest on {t}: read for the community summary"
        );
    }
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "place_submissions").await,
        ["SELECT", "UPDATE"]
    );
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "place_refresh_queue").await,
        ["SELECT", "INSERT", "DELETE"],
        "the worker takes the queue, and queues for its summary step what a conflation changed"
    );
    for (column, granted) in [
        ("id", true),
        ("banned_at", true),
        ("trust_level", true),
        ("pseudonym", false),
        ("moderation_removals", false),
    ] {
        let has = sqlx::query_scalar!(
            r#"SELECT has_column_privilege('lunaway_ingest', 'accounts', $1, 'SELECT') AS "has!""#,
            column
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(
            has, granted,
            "the worker sees which accounts are banned and their level, nothing else ({column})"
        );
    }
    for t in [
        "_sqlx_migrations",
        "sessions",
        "device_keys",
        "recovery_codes",
        "muted_authors",
        "favorite_lists",
        "content_reports",
    ] {
        assert!(
            privileges(&pool, "lunaway_ingest", t).await.is_empty(),
            "lunaway_ingest on {t}"
        );
    }
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "moderation_queue").await,
        ["INSERT"],
        "the worker opens the check of a point it hides, and decides nothing"
    );
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    insert(&ingest, "way/1").await;
    let a = records::id_of(&ingest, &SourceId::OSM, "way/1")
        .await
        .unwrap()
        .unwrap();
    insert(&ingest, "way/2").await;
    let b = records::id_of(&ingest, &SourceId::OSM, "way/2")
        .await
        .unwrap()
        .unwrap();
    let constraint = records::set_constraint(
        &ingest,
        a,
        b,
        lunaway_domain::conflation::ConstraintKind::CannotLink,
        None,
    )
    .await;
    assert!(
        constraint.is_err(),
        "an import cannot replace a human decision on a pair"
    );
}

#[tokio::test]
async fn a_pool_can_bound_every_statement_on_the_server() {
    let url = std::env::var("DATABASE_URL").expect("the database tests need DATABASE_URL");
    let pool = lunaway_db::connect_with(
        &url,
        lunaway_db::PoolConfig {
            statement_timeout: Some(Duration::from_millis(1_500)),
            ..lunaway_db::PoolConfig::new(1)
        },
    )
    .await
    .unwrap();
    let limit: String =
        sqlx::query_scalar!(r#"SELECT current_setting('statement_timeout') AS "s!""#)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        limit, "1500ms",
        "a query the API gave up on must not keep running on the server"
    );
    let slow = sqlx::query!("SELECT pg_sleep(3)").execute(&pool).await;
    assert!(slow.is_err(), "the server cancels it");
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_import_waits_for_the_lock_past_its_role_s_statement_timeout(pool: PgPool) {
    // As lunaway_ingest in production: every statement bounded on the
    // server (10 minutes there, 300 ms here).
    let mut options = (*pool.connect_options()).clone();
    options = options.options([("statement_timeout", "300ms")]);
    let bounded = PgPoolOptions::new()
        .max_connections(1)
        .connect_with(options)
        .await
        .unwrap();
    let writer = conflation::begin_writer(&pool).await.unwrap();
    let import = tokio::spawn(async move {
        insert(&bounded, "way/1").await;
        bounded
    });
    tokio::time::sleep(Duration::from_millis(900)).await;
    writer.commit().await.unwrap();
    let bounded = import.await.unwrap();
    assert_eq!(
        records::live_count(&bounded, &SourceId::OSM, None)
            .await
            .unwrap(),
        1,
        "the import waited three times its statement limit for the lock, then ran"
    );
    let limit: String =
        sqlx::query_scalar!(r#"SELECT current_setting('statement_timeout') AS "s!""#)
            .fetch_one(&bounded)
            .await
            .unwrap();
    assert_eq!(limit, "300ms", "outside the lock, the role's limit holds");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_pack_build_knows_when_its_lock_went_with_its_session(pool: PgPool) {
    let mut lock = lunaway_db::packs::BuildLock::acquire(&pool).await.unwrap();
    assert!(lock.held().await.unwrap());
    // The server ends the lock's session (a restart, an administrator):
    // the lock is gone, and another build could take it.
    sqlx::query(
        "SELECT pg_terminate_backend(pid) FROM pg_locks \
         WHERE locktype = 'advisory' AND pid <> pg_backend_pid() \
           AND database = (SELECT oid FROM pg_database WHERE datname = current_database())",
    )
    .execute(&pool)
    .await
    .unwrap();
    assert!(
        !matches!(lock.held().await, Ok(true)),
        "a build must not record its packs once its lock is gone"
    );
    let other = lunaway_db::packs::BuildLock::acquire(&pool).await.unwrap();
    other.release().await.unwrap();
}

/// The external community source's tables go to the role that writes each:
/// the importers write the agreement, the switch, the reviews, the ratings
/// and the photo rows; the API reads them, fills in a photo's files and
/// deletes a retired photo's row once its files are gone. Run end to end
/// with the two roles, as the services and the commands do.
#[sqlx::test(migrations = "../../migrations")]
async fn the_partner_source_runs_with_the_import_and_api_roles(pool: PgPool) {
    use lunaway_db::extcom;
    use lunaway_domain::extcom::{Agreement, RawAgreement, Terms};

    for t in ["external_reviews", "external_ratings"] {
        assert_eq!(
            privileges(&pool, "lunaway_ingest", t).await,
            ["SELECT", "INSERT", "UPDATE", "DELETE"],
            "lunaway_ingest on {t}"
        );
    }
    assert_eq!(
        privileges(&pool, "lunaway_app", "external_ratings").await,
        ["SELECT"]
    );
    assert!(
        privileges(&pool, "lunaway_app", "external_reviews")
            .await
            .is_empty(),
        "the API reads the reviews column by column, the author id left out"
    );
    for t in ["source_agreements", "source_switches"] {
        assert_eq!(
            privileges(&pool, "lunaway_ingest", t).await,
            ["SELECT", "INSERT", "UPDATE"],
            "lunaway_ingest on {t}"
        );
        assert_eq!(
            privileges(&pool, "lunaway_app", t).await,
            ["SELECT"],
            "lunaway_app on {t}"
        );
    }
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "external_photos").await,
        ["SELECT", "INSERT", "UPDATE"],
        "the importers never delete a photo row: it names files the API wrote"
    );
    assert_eq!(
        privileges(&pool, "lunaway_app", "external_photos").await,
        ["DELETE"],
        "the API reads and fills in a photo's columns one by one (the author id left out), \
         and deletes retired rows"
    );
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "source_erasures").await,
        ["SELECT", "INSERT"],
        "an erasure is never undone by an import"
    );
    assert!(
        privileges(&pool, "lunaway_app", "source_erasures")
            .await
            .is_empty()
    );

    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let source = SourceId::EXTCOM;
    let today = chrono::NaiveDate::from_ymd_opt(2026, 10, 7).unwrap();
    let terms = Terms::new("REF-1", &["img.partner.example".into()]).unwrap();
    let agreement = Agreement::check(
        &RawAgreement {
            reference: "REF-1".into(),
            grantor: "Partner".into(),
            grantee: "Lunaway".into(),
            signed_on: chrono::NaiveDate::from_ymd_opt(2026, 1, 1),
            valid_until: None,
            scope: vec!["places".into(), "reviews".into(), "photos".into()],
            attribution: "Source communautaire externe".into(),
            licence_url: None,
        },
        &terms,
        today,
    )
    .unwrap();
    extcom::upsert_agreement(&ingest, &source, &agreement, Utc::now())
        .await
        .unwrap();
    let r = record("Parking du lac");
    let raw = serde_json::json!({});
    let stored = records::upsert_unless_hidden(
        &ingest,
        &source,
        &[NewRecord {
            external_id: "1",
            external_url: None,
            record: &r,
            raw: &raw,
            fetched_at: Utc::now(),
            scope: None,
        }],
    )
    .await
    .unwrap();
    assert_eq!(stored.map(|s| s.inserted), Some(1));
    extcom::set_record_licence(&ingest, &source, &["1".into()], "REF-1")
        .await
        .unwrap();
    let extras = extcom::Extras {
        external_id: "1".into(),
        reviews: Some(vec![extcom::NewReview {
            external_id: "r".into(),
            author_id: Some("u-1".into()),
            author: Some("Marie".into()),
            written_at: Utc::now(),
            lang: Some("fr".into()),
            rating: Some(4),
            body: Some("Calme".into()),
            vehicle: None,
        }]),
        rating: Some((4.0, 10)),
        photos: Some(vec![extcom::NewPhoto {
            external_id: "p".into(),
            url: "https://img.partner.example/p.jpg".into(),
            author_id: Some("u-1".into()),
            author: None,
            licence: "REF-1".into(),
            taken_at: None,
        }]),
    };
    let written = extcom::store_extras(&ingest, &source, "REF-1", Utc::now(), &[extras])
        .await
        .unwrap()
        .unwrap();
    assert_eq!((written.reviews_written, written.photos_written), (1, 1));

    // The API: the proxy reads a photo, records a failure, then its files.
    let photo: uuid::Uuid = sqlx::query_scalar("SELECT id FROM external_photos")
        .fetch_one(&pool)
        .await
        .unwrap();
    let p = extcom::photo_for_proxy(&app, photo, today)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(p.hosts, ["img.partner.example"]);
    extcom::photo_failed(&app, photo, Utc::now()).await.unwrap();
    denied(
        sqlx::query("UPDATE external_photos SET url = 'https://elsewhere.example/x.jpg'")
            .execute(&app)
            .await,
        "the API cannot point a photo at another host",
    );
    denied(
        sqlx::query("DELETE FROM external_reviews")
            .execute(&app)
            .await,
        "the API deletes no review of the partner",
    );
    denied(
        sqlx::query("SELECT author_id FROM external_reviews")
            .execute(&app)
            .await,
        "the API cannot read the partner's author ids",
    );

    // The author is erased while the proxy downloads their photo: the
    // files it then records stay named by the retired row, for
    // purge-media, and are served to nobody.
    let erased = extcom::erase_author(&ingest, &source, "u-1", &"0".repeat(64))
        .await
        .unwrap();
    assert_eq!((erased.reviews, erased.photos), (1, 1));
    let path = format!("photos/ab/cd/abcd{}.webp", "0".repeat(60));
    let thumb = format!("photos/ef/01/ef01{}.webp", "0".repeat(60));
    let recorded = extcom::photo_processed(
        &app,
        photo,
        extcom::ProcessedPhoto {
            path: &path,
            thumb_path: &thumb,
            size: (10, 10),
            thumb_size: (10, 10),
            thumbhash: &[1, 2, 3],
        },
    )
    .await
    .unwrap();
    assert_eq!(recorded, extcom::Recorded::Retired);

    // The switches, with the import role.
    extcom::set_hidden(&ingest, &source, true, None)
        .await
        .unwrap();
    extcom::purge(&ingest, &source, Some("agreement ended"))
        .await
        .unwrap();
    extcom::retire_records(&ingest, &source, &["1".into()])
        .await
        .unwrap();
    extcom::forget_retired(&ingest, &source).await.unwrap();

    // Then the API's role removes the retired rows once the files are gone.
    let retired = extcom::retired_photo_files(&app, 10).await.unwrap();
    assert_eq!(retired.len(), 1);
    assert_eq!(retired[0].unshared_files, [path, thumb]);
    assert_eq!(
        extcom::delete_retired_photos(&app, &retired).await.unwrap(),
        1
    );
}
