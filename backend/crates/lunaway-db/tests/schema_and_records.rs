//! The schema accepts what the domain produces, and records are upserted,
//! flagged and retired as the conflation expects.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::{TimeZone, Utc};
use lunaway_db::{
    PgPool,
    records::{self, NewRecord, UpsertStats},
    sources,
};
use lunaway_domain::{
    Activity, NormalizedRecord, OvernightStatus, PlaceKind, Position, Service, SourceId,
    conflation::ConstraintKind,
};

/// The rows, each under `scope`.
fn scoped<'a>(rows: &[NewRecord<'a>], scope: Option<&'a str>) -> Vec<NewRecord<'a>> {
    rows.iter().map(|r| NewRecord { scope, ..*r }).collect()
}

fn record(name: &str) -> NormalizedRecord {
    let mut r = NormalizedRecord::new(PlaceKind::Campsite, Position::new(47.4, -0.6).unwrap());
    r.name = Some(name.to_owned());
    r
}

async fn dirty_ids(pool: &PgPool) -> Vec<String> {
    sqlx::query_scalar!(
        "SELECT external_id FROM source_records WHERE needs_conflation ORDER BY external_id"
    )
    .fetch_all(pool)
    .await
    .unwrap()
}

async fn clear_flags(pool: &PgPool) {
    sqlx::query!("UPDATE source_records SET needs_conflation = false")
        .execute(pool)
        .await
        .unwrap();
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_sources_are_seeded_with_their_terms(pool: PgPool) {
    let s = sources::list(&pool).await.unwrap();
    let ids: Vec<&str> = s.iter().map(|s| s.id.as_str()).collect();
    assert_eq!(
        ids,
        [
            "atout-france",
            "cat-sct-radars",
            "community",
            "finess",
            "laposte",
            "lu-pch-radars",
            "no-nvdb-atk",
            "osm",
            "pl-canard",
            "prix-carburants",
            "securite-routiere"
        ]
    );
    for joined in [SourceId::FUEL_PRICES, SourceId::LAPOSTE, SourceId::FINESS] {
        assert!(
            ids.contains(&joined.as_str()),
            "{joined}: a source joined to the points is credited like any other"
        );
    }
    let community = s.iter().find(|s| s.id == SourceId::COMMUNITY).unwrap();
    assert_eq!(
        (community.licence.as_str(), community.attribution.as_str()),
        ("ODbL 1.0", "Lunaway contributors"),
        "places added by users join the ODbL database, credited to them"
    );
    let osm = s.iter().find(|s| s.id == SourceId::OSM).unwrap();
    assert_eq!(osm.licence, "ODbL 1.0");
    assert_eq!(
        osm.attribution, "© OpenStreetMap contributors",
        "the ODbL requires this credit"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn every_domain_code_is_accepted_and_an_unknown_one_refused(pool: PgPool) {
    // The CHECK lists of the migration repeat the taxonomy; a code added to
    // the domain without a migration fails here.
    let services: Vec<String> = Service::ALL.iter().map(|s| s.code().to_owned()).collect();
    let activities: Vec<String> = Activity::ALL.iter().map(|s| s.code().to_owned()).collect();
    for (i, kind) in PlaceKind::ALL.iter().enumerate() {
        let overnight = OvernightStatus::ALL[i % OvernightStatus::ALL.len()];
        sqlx::query!(
            r#"
            INSERT INTO places (id, kind, geom, overnight, services, activities, content_hash)
            VALUES ($1, $2, ST_SetSRID(ST_MakePoint(2, 47), 4326)::geography, $3, $4, $5, 'x')
            "#,
            uuid::Uuid::now_v7(),
            kind.code(),
            overnight.code(),
            &services,
            &activities,
        )
        .execute(&pool)
        .await
        .unwrap_or_else(|e| panic!("{kind:?} / {overnight:?} refused: {e}"));
    }
    for o in OvernightStatus::ALL {
        sqlx::query!(
            r#"
            INSERT INTO places (id, kind, geom, overnight, content_hash)
            VALUES ($1, 'parking', ST_SetSRID(ST_MakePoint(2, 47), 4326)::geography, $2, 'x')
            "#,
            uuid::Uuid::now_v7(),
            o.code(),
        )
        .execute(&pool)
        .await
        .unwrap();
    }
    let unknown = sqlx::query!(
        r#"
        INSERT INTO places (id, kind, geom, overnight, content_hash)
        VALUES ($1, 'castle', ST_SetSRID(ST_MakePoint(2, 47), 4326)::geography, 'allowed', 'x')
        "#,
        uuid::Uuid::now_v7(),
    )
    .execute(&pool)
    .await;
    assert!(
        unknown.is_err(),
        "the schema refuses a kind the domain does not know"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_upsert_flags_only_new_and_changed_records(pool: PgPool) {
    let raw = serde_json::json!({"id": 1});
    let at = Utc.with_ymd_and_hms(2026, 10, 1, 0, 0, 0).unwrap();
    let (a, b) = (record("Camping A"), record("Camping B"));
    let rows = [
        NewRecord {
            external_id: "way/1",
            external_url: None,
            record: &a,
            raw: &raw,
            fetched_at: at,
            scope: None,
        },
        NewRecord {
            external_id: "way/2",
            external_url: None,
            record: &b,
            raw: &raw,
            fetched_at: at,
            scope: None,
        },
    ];
    let first = records::upsert(&pool, &SourceId::OSM, &scoped(&rows, Some("FR-PDL")))
        .await
        .unwrap();
    assert_eq!(
        first,
        UpsertStats {
            inserted: 2,
            changed: 0,
            unchanged: 0
        }
    );
    assert_eq!(dirty_ids(&pool).await, ["way/1", "way/2"]);
    let id_before = records::id_of(&pool, &SourceId::OSM, "way/1")
        .await
        .unwrap()
        .unwrap();

    clear_flags(&pool).await;
    let later = Utc.with_ymd_and_hms(2026, 10, 2, 0, 0, 0).unwrap();
    let b2 = record("Camping B, renamed");
    let raw2 = serde_json::json!({"id": 1, "unread_tag": "changed"});
    let rows = [
        NewRecord {
            external_id: "way/1",
            external_url: None,
            record: &a,
            raw: &raw2,
            fetched_at: later,
            scope: None,
        },
        NewRecord {
            external_id: "way/2",
            external_url: None,
            record: &b2,
            raw: &raw,
            fetched_at: later,
            scope: None,
        },
    ];
    let second = records::upsert(&pool, &SourceId::OSM, &scoped(&rows, Some("FR-PDL")))
        .await
        .unwrap();
    assert_eq!(
        second,
        UpsertStats {
            inserted: 0,
            changed: 1,
            unchanged: 1
        }
    );
    assert_eq!(
        dirty_ids(&pool).await,
        ["way/2"],
        "a new fetch date or a raw change the normalisation ignores is not a change"
    );
    assert_eq!(
        records::id_of(&pool, &SourceId::OSM, "way/1")
            .await
            .unwrap(),
        Some(id_before),
        "a record keeps its id across imports, so constraints on it survive"
    );
    let fetched: chrono::DateTime<Utc> =
        sqlx::query_scalar!("SELECT fetched_at FROM source_records WHERE external_id = 'way/1'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(fetched, later, "the fetch date still moves");
}

#[sqlx::test(migrations = "../../migrations")]
async fn records_missing_from_a_scope_are_retired_and_come_back(pool: PgPool) {
    let raw = serde_json::json!({});
    let at = Utc.with_ymd_and_hms(2026, 10, 1, 0, 0, 0).unwrap();
    let r = record("X");
    let row = |id: &'static str| NewRecord {
        external_id: id,
        external_url: None,
        record: &r,
        raw: &raw,
        fetched_at: at,
        scope: None,
    };
    records::upsert(
        &pool,
        &SourceId::OSM,
        &scoped(&[row("way/1"), row("way/2")], Some("FR-PDL")),
    )
    .await
    .unwrap();
    records::upsert(
        &pool,
        &SourceId::OSM,
        &scoped(&[row("way/3")], Some("FR-BRE")),
    )
    .await
    .unwrap();
    clear_flags(&pool).await;

    let retired = records::retire_missing(
        &pool,
        &SourceId::OSM,
        Some("FR-PDL"),
        &["way/1".to_owned()],
        at,
    )
    .await
    .unwrap();
    assert_eq!(
        retired, 1,
        "way/2 left the region; way/3 belongs to another region"
    );
    assert_eq!(
        dirty_ids(&pool).await,
        ["way/2"],
        "a retired record must reach the conflation"
    );
    assert_eq!(
        records::live_count(&pool, &SourceId::OSM, Some("FR-PDL"))
            .await
            .unwrap(),
        1
    );
    assert_eq!(
        records::live_count(&pool, &SourceId::OSM, None)
            .await
            .unwrap(),
        2
    );

    clear_flags(&pool).await;
    let back = records::upsert(
        &pool,
        &SourceId::OSM,
        &scoped(&[row("way/2")], Some("FR-PDL")),
    )
    .await
    .unwrap();
    assert_eq!(
        back.changed, 1,
        "a record seen again after its retirement is a change"
    );
    assert_eq!(dirty_ids(&pool).await, ["way/2"]);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_constraint_is_stored_once_per_pair_and_flags_both_records(pool: PgPool) {
    let raw = serde_json::json!({});
    let at = Utc::now();
    let r = record("X");
    let rows = [
        NewRecord {
            external_id: "a",
            external_url: None,
            record: &r,
            raw: &raw,
            fetched_at: at,
            scope: None,
        },
        NewRecord {
            external_id: "b",
            external_url: None,
            record: &r,
            raw: &raw,
            fetched_at: at,
            scope: None,
        },
    ];
    records::upsert(&pool, &SourceId::OSM, &rows).await.unwrap();
    let a = records::id_of(&pool, &SourceId::OSM, "a")
        .await
        .unwrap()
        .unwrap();
    let b = records::id_of(&pool, &SourceId::OSM, "b")
        .await
        .unwrap()
        .unwrap();
    clear_flags(&pool).await;

    records::set_constraint(&pool, b, a, ConstraintKind::MustLink, Some("same spot"))
        .await
        .unwrap();
    records::set_constraint(
        &pool,
        a,
        b,
        ConstraintKind::CannotLink,
        Some("changed my mind"),
    )
    .await
    .unwrap();
    let rows = sqlx::query!("SELECT record_a, record_b, kind FROM conflation_constraints")
        .fetch_all(&pool)
        .await
        .unwrap();
    assert_eq!(rows.len(), 1, "the later decision replaces the earlier one");
    assert_eq!(rows[0].kind, "cannot_link");
    assert!(rows[0].record_a < rows[0].record_b);
    assert_eq!(dirty_ids(&pool).await, ["a", "b"]);
}
