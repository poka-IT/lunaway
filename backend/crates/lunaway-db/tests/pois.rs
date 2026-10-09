//! The points of interest in the database: the codes the schema accepts,
//! what each role may do with the layer, when the tiles' version moves, the
//! community's "still there?" answers, and the vending machines users add.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::collections::BTreeMap;

use chrono::{TimeZone, Utc};
use lunaway_db::{
    PgPool,
    pois::{self, NewPoi},
    submissions::{self, NewSubmission, Submitted},
};
use lunaway_domain::{
    Position, SourceId,
    poi::{NewVendingMachine, PoiKind, PoiRecord},
};
use uuid::Uuid;

fn point(kind: PoiKind, lat: f64, lon: f64, name: &str) -> PoiRecord {
    let mut r = PoiRecord::new(kind, Position::new(lat, lon).unwrap());
    r.name = Some(name.to_owned());
    r
}

async fn store(pool: &PgPool, points: &[(&str, PoiRecord)]) -> lunaway_db::records::UpsertStats {
    let raw = serde_json::value::to_raw_value(&serde_json::json!({})).unwrap();
    let at = Utc.with_ymd_and_hms(2026, 10, 5, 22, 0, 0).unwrap();
    let rows: Vec<NewPoi<'_>> = points
        .iter()
        .map(|(id, r)| NewPoi {
            external_id: id,
            external_url: None,
            record: r,
            raw: &raw,
            fetched_at: at,
            scope: Some("FR"),
        })
        .collect();
    pois::upsert(pool, &SourceId::OSM, &rows).await.unwrap()
}

/// The tiles' version once what waits is published: the worker publishes
/// at most every few hours, the tests at once.
async fn version(pool: &PgPool) -> i64 {
    pois::publish_layer(pool, std::time::Duration::ZERO)
        .await
        .unwrap();
    pois::layer_version(pool).await.unwrap().version
}

#[sqlx::test(migrations = "../../migrations")]
async fn every_poi_code_is_accepted_and_an_unknown_one_refused(pool: PgPool) {
    // The CHECK lists of the migration repeat the domain's codes; a kind
    // added to the domain without a migration fails here.
    let points: Vec<(String, PoiRecord)> = PoiKind::ALL
        .iter()
        .enumerate()
        .map(|(i, k)| (format!("node/{i}"), point(*k, 45.0, 5.0, k.code())))
        .collect();
    let refs: Vec<(&str, PoiRecord)> = points
        .iter()
        .map(|(i, r)| (i.as_str(), r.clone()))
        .collect();
    let s = store(&pool, &refs).await;
    assert_eq!(s.inserted as usize, PoiKind::ALL.len());
    let unknown = sqlx::query!(
        r#"
        INSERT INTO pois (id, source_id, external_id, category, kind, geom, data, raw, fetched_at)
        VALUES ($1, 'osm', 'node/x', 'groceries', 'castle',
                ST_SetSRID(ST_MakePoint(5, 45), 4326)::geography, '{}', '{}', now())
        "#,
        Uuid::now_v7(),
    )
    .execute(&pool)
    .await;
    assert!(
        unknown.is_err(),
        "the schema refuses a kind the domain does not know"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_upsert_tells_new_changed_and_unchanged_points_apart(pool: PgPool) {
    let v0 = version(&pool).await;
    let a = point(PoiKind::Bakery, 45.0, 5.0, "Boulangerie A");
    let b = point(PoiKind::Pharmacy, 45.001, 5.001, "Pharmacie B");
    let first = store(&pool, &[("node/1", a.clone()), ("node/2", b.clone())]).await;
    assert_eq!(first.inserted, 2);
    let again = store(&pool, &[("node/1", a.clone()), ("node/2", b.clone())]).await;
    assert_eq!(again.unchanged, 2);
    let mut a2 = a.clone();
    a2.name = Some("Boulangerie A et fils".into());
    let renamed = store(&pool, &[("node/1", a2), ("node/2", b)]).await;
    assert_eq!((renamed.changed, renamed.unchanged), (1, 1));
    assert_eq!(
        version(&pool).await,
        v0,
        "the tiles' version moves once per import, by its caller, not per batch"
    );
    let other_country = ["DE".to_owned()];
    let retired = pois::retire_missing(
        &pool,
        &SourceId::OSM,
        Some(&other_country),
        &["node/1".to_owned()],
        Utc::now(),
    )
    .await
    .unwrap();
    assert_eq!(
        retired, 0,
        "a run of another country retires none of the French points"
    );
    let france = ["FR".to_owned()];
    let retired = pois::retire_missing(
        &pool,
        &SourceId::OSM,
        Some(&france),
        &["node/1".to_owned()],
        Utc::now(),
    )
    .await
    .unwrap();
    assert_eq!(retired, 1);
    assert_eq!(
        pois::live_count(&pool, &SourceId::OSM, None).await.unwrap(),
        1
    );
    // A version that moved a second ago: the template database's may be
    // hours old.
    sqlx::query("UPDATE poi_layer SET changed_at = now() - interval '1 second'")
        .execute(&pool)
        .await
        .unwrap();
    pois::mark_layer_now(&pool).await.unwrap();
    assert_eq!(
        pois::publish_layer(&pool, std::time::Duration::from_secs(3_600))
            .await
            .unwrap(),
        None,
        "a version younger than the interval does not move"
    );
    assert_eq!(
        pois::publish_layer(&pool, std::time::Duration::ZERO)
            .await
            .unwrap(),
        Some(v0 + 1),
        "a waiting change is published once the interval has passed"
    );
    assert_eq!(
        pois::publish_layer(&pool, std::time::Duration::ZERO)
            .await
            .unwrap(),
        None,
        "nothing waits any more"
    );
}

async fn account(pool: &PgPool, level: i16) -> Uuid {
    let id = Uuid::now_v7();
    sqlx::query!(
        "INSERT INTO accounts (id, pseudonym, trust_level) VALUES ($1, $2, $3)",
        id,
        format!("Compte {}", &id.simple().to_string()[24..]),
        level,
    )
    .execute(pool)
    .await
    .unwrap();
    id
}

async fn refresh(pool: &PgPool) -> u64 {
    let mut tx = pois::begin_poi_writer(pool).await.unwrap();
    let queued = pois::take_refresh_queue(&mut tx).await.unwrap();
    let n = pois::refresh_community(&mut tx, &queued).await.unwrap();
    tx.commit().await.unwrap();
    n
}

async fn hidden(pool: &PgPool, poi: Uuid) -> bool {
    sqlx::query_scalar!("SELECT hidden FROM pois WHERE id = $1", poi)
        .fetch_one(pool)
        .await
        .unwrap()
}

async fn open_checks(pool: &PgPool, poi: Uuid) -> i64 {
    sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM moderation_queue
           WHERE kind = 'poi_check' AND target_id = $1 AND status = 'open'"#,
        poi
    )
    .fetch_one(pool)
    .await
    .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn three_accounts_saying_gone_hide_a_point_until_a_trusted_one_finds_it(pool: PgPool) {
    store(
        &pool,
        &[(
            "node/1",
            point(PoiKind::VendingPizza, 47.27, -0.07, "Pizza"),
        )],
    )
    .await;
    let poi = sqlx::query_scalar!("SELECT id FROM pois")
        .fetch_one(&pool)
        .await
        .unwrap();
    let fresh = account(&pool, 0).await;
    pois::confirm(&pool, fresh, poi, false).await.unwrap();
    refresh(&pool).await;
    assert!(
        !hidden(&pool, poi).await,
        "a level-0 account's \"gone\" does not count"
    );
    let mut level_one = Vec::new();
    for _ in 0..3 {
        level_one.push(account(&pool, 1).await);
    }
    for a in &level_one {
        pois::confirm(&pool, *a, poi, false).await.unwrap();
    }
    let before = version(&pool).await;
    assert_eq!(refresh(&pool).await, 1);
    assert!(hidden(&pool, poi).await);
    assert!(
        !pois::is_live(&pool, poi).await.unwrap(),
        "hidden from the map"
    );
    assert!(
        pois::exists(&pool, poi).await.unwrap(),
        "but still answerable"
    );
    assert!(version(&pool).await > before, "every tile URL changes");
    assert_eq!(
        open_checks(&pool, poi).await,
        1,
        "the worker that hides it sends it to the moderators"
    );

    pois::confirm(&pool, fresh, poi, true).await.unwrap();
    refresh(&pool).await;
    assert!(
        hidden(&pool, poi).await,
        "a new account's \"still there\" does not bring it back"
    );
    let finder = account(&pool, 1).await;
    pois::confirm(&pool, finder, poi, true).await.unwrap();
    refresh(&pool).await;
    assert!(
        !hidden(&pool, poi).await,
        "a trusted \"still there\" after them shows it"
    );
    let row = pois::by_id(&pool, poi).await.unwrap().unwrap();
    assert!(row.last_confirmed_at.is_some());
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_point_hidden_by_any_path_reaches_the_moderators(pool: PgPool) {
    // The path of the security audit of 2026-10-06: answers taken back
    // after the fact still hide the point, and the check opens.
    store(
        &pool,
        &[("node/1", point(PoiKind::Toilets, 47.27, -0.07, "WC"))],
    )
    .await;
    let poi = sqlx::query_scalar!("SELECT id FROM pois")
        .fetch_one(&pool)
        .await
        .unwrap();
    let (a, b, c) = (
        account(&pool, 1).await,
        account(&pool, 1).await,
        account(&pool, 1).await,
    );
    pois::confirm(&pool, a, poi, false).await.unwrap();
    pois::confirm(&pool, b, poi, false).await.unwrap();
    let (there, _) = pois::confirm(&pool, a, poi, true).await.unwrap();
    pois::confirm(&pool, c, poi, false).await.unwrap();
    refresh(&pool).await;
    assert!(
        !hidden(&pool, poi).await,
        "two gone after a's latest \"still there\""
    );
    assert!(pois::delete_confirmation(&pool, a, there).await.unwrap());
    refresh(&pool).await;
    assert!(
        hidden(&pool, poi).await,
        "a's answer is \"gone\" again: three"
    );
    assert_eq!(open_checks(&pool, poi).await, 1);

    // A moderator who finds it there sets the "gone" answers aside.
    assert!(
        lunaway_db::moderation::hide_poi(&pool, poi, false, None)
            .await
            .unwrap()
    );
    refresh(&pool).await;
    assert!(!hidden(&pool, poi).await);
    // One who finds it gone hides it whatever the answers say, and the tiles
    // get a new version at once, without waiting for the publication.
    let published = pois::layer_version(&pool).await.unwrap().version;
    assert!(
        lunaway_db::moderation::hide_poi(&pool, poi, true, Some("demolished"))
            .await
            .unwrap()
    );
    let d = account(&pool, 2).await;
    pois::confirm(&pool, d, poi, true).await.unwrap();
    refresh(&pool).await;
    assert!(hidden(&pool, poi).await, "a moderator's decision holds");
    let after = pois::layer_version(&pool).await.unwrap();
    assert_eq!(
        (after.version, after.pending_since),
        (published + 1, None),
        "a point a moderator hides leaves every tile now"
    );
    assert!(
        !lunaway_db::moderation::hide_poi(&pool, Uuid::now_v7(), true, None)
            .await
            .unwrap()
    );

    // A year later, the answers go and the point is counted again.
    lunaway_db::moderation::hide_poi(&pool, poi, false, None)
        .await
        .unwrap();
    refresh(&pool).await;
    sqlx::query!("UPDATE poi_confirmations SET created_at = now() - interval '400 days'")
        .execute(&pool)
        .await
        .unwrap();
    let mut tx = pois::begin_poi_writer(&pool).await.unwrap();
    let purged = pois::purge_old_answers(&mut tx).await.unwrap();
    tx.commit().await.unwrap();
    assert_eq!(purged, vec![poi]);
    let left = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM poi_confirmations"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(left, 0, "a dated list of where an account was is not kept");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_vending_machine_a_user_adds_becomes_a_community_point(pool: PgPool) {
    let author = account(&pool, 1).await;
    let key = Uuid::now_v7();
    sqlx::query!(
        "INSERT INTO device_keys (id, account_id, thumbprint, public_key) VALUES ($1, $2, $3, $4)",
        key,
        author,
        "a".repeat(43),
        vec![4u8; 65],
    )
    .execute(&pool)
    .await
    .unwrap();
    let machine = NewVendingMachine {
        kind: PoiKind::VendingBread,
        position: Position::new(47.238, -0.1025).unwrap(),
        name: None,
        operator: Some("maBaguette".into()),
        brand: None,
        products: vec!["eggs".into()],
        payment: vec!["coins".into()],
        always_open: true,
    };
    let row = submissions::submit(
        &pool,
        NewSubmission {
            account: author,
            device_key: key,
            what: Submitted::Poi(&machine),
            accepted: true,
            held_for: None,
        },
    )
    .await
    .unwrap();
    assert_eq!(row.kind, "poi");
    let mut tx = pois::begin_poi_writer(&pool).await.unwrap();
    let stats = pois::apply_submissions(&mut tx).await.unwrap();
    tx.commit().await.unwrap();
    assert_eq!(stats.applied, 1);
    let applied = submissions::submission(&pool, row.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(applied.status, "applied");
    let poi = applied.poi_id.expect("the point it became");
    let p = pois::by_id(&pool, poi).await.unwrap().unwrap();
    assert_eq!(p.source_id, SourceId::COMMUNITY);
    assert_eq!(p.external_id, format!("submission/{}", row.id));
    assert_eq!(
        p.record.products,
        vec!["bread", "eggs"],
        "tagged as OSM would"
    );
    assert_eq!(p.record.opening_hours.as_deref(), Some("24/7"));
    assert!(p.always_open);
    assert_eq!(
        pois::vending_near(
            &pool,
            Position::new(47.2381, -0.1025).unwrap(),
            PoiKind::VendingBread,
            25.0
        )
        .await
        .unwrap(),
        Some(poi),
        "the next one 11 m away is a duplicate"
    );

    // Its author banned, the point goes.
    sqlx::query!(
        "UPDATE accounts SET banned_at = now() WHERE id = $1",
        author
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query!("INSERT INTO poi_refresh_queue (poi_id) VALUES ($1)", poi)
        .execute(&pool)
        .await
        .unwrap();
    refresh(&pool).await;
    assert!(
        !pois::is_live(&pool, poi).await.unwrap(),
        "a spammer's points leave with them"
    );

    // The places' worker step leaves a vending machine alone.
    let mut tx = lunaway_db::conflation::begin_writer(&pool).await.unwrap();
    submissions::apply_accepted(&mut tx).await.unwrap();
    tx.commit().await.unwrap();
    let records = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM source_records"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        records, 0,
        "a vending machine is a point, never a place record"
    );
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
async fn the_api_reads_the_layer_and_writes_only_the_community_s_answers(pool: PgPool) {
    for t in ["pois", "poi_join_records", "poi_layer"] {
        assert_eq!(
            privileges(&pool, "lunaway_app", t).await,
            ["SELECT"],
            "lunaway_app on {t}: the API serves the layer and writes none of it"
        );
        assert_eq!(
            privileges(&pool, "lunaway_ingest", t).await,
            ["SELECT", "INSERT", "UPDATE"],
            "lunaway_ingest on {t}: a gone point is a tombstone, never deleted"
        );
    }
    assert_eq!(
        privileges(&pool, "lunaway_app", "poi_confirmations").await,
        ["SELECT", "INSERT", "UPDATE", "DELETE"]
    );
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "poi_confirmations").await,
        ["SELECT", "DELETE"],
        "the worker purges the answers past their year"
    );
    assert_eq!(
        privileges(&pool, "lunaway_app", "poi_moderation").await,
        ["SELECT", "INSERT", "DELETE"],
        "the moderators hide and show points with the API's role"
    );
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "poi_moderation").await,
        ["SELECT"]
    );
    assert_eq!(
        privileges(&pool, "lunaway_app", "poi_refresh_queue").await,
        ["INSERT"]
    );
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "poi_refresh_queue").await,
        ["SELECT", "DELETE"]
    );
    assert_eq!(
        privileges(&pool, "lunaway_app", "poi_cluster_cells").await,
        ["SELECT"],
        "the API builds the cluster tiles from the cells"
    );
    assert_eq!(
        privileges(&pool, "lunaway_ingest", "poi_cluster_cells").await,
        ["SELECT", "INSERT", "UPDATE", "DELETE"],
        "the worker counts the cells again when it publishes a version"
    );
}

/// The cells of `poi_cluster_cells` as the points make them, counted here
/// from each visible point's position on the grid: per zoom 6 to 9, tile,
/// cell of the tile's 32 by 32 grid, category, and again per kind for the
/// vending machines a filter can pick.
async fn cells_of_the_points(
    pool: &PgPool,
) -> BTreeMap<(i16, i32, i32, i16, String, String), (i32, i64, i64)> {
    let points = sqlx::query!(
        r#"
        SELECT category, kind, lunaway_grid_x(ST_X(geom::geometry)) AS "gx!",
               lunaway_grid_y(ST_Y(geom::geometry)) AS "gy!"
        FROM pois WHERE deleted_at IS NULL AND NOT hidden
        "#
    )
    .fetch_all(pool)
    .await
    .unwrap();
    let mut cells = BTreeMap::new();
    for p in points {
        let picked = p.category == "vending" && p.kind != "vending_other";
        for z in 6..=pois::CLUSTER_TABLE_MAX_ZOOM {
            let (cx, cy) = (p.gx >> (23 - z), p.gy >> (23 - z));
            let at = |kind: &str| {
                (
                    i16::try_from(z).unwrap(),
                    cx >> 5,
                    cy >> 5,
                    i16::try_from((cy & 31) * 32 + (cx & 31)).unwrap(),
                    p.category.clone(),
                    kind.to_owned(),
                )
            };
            let mut keys = vec![at("")];
            if picked {
                keys.push(at(&p.kind));
            }
            for key in keys {
                let c: &mut (i32, i64, i64) = cells.entry(key).or_default();
                *c = (c.0 + 1, c.1 + i64::from(p.gx), c.2 + i64::from(p.gy));
            }
        }
    }
    cells
}

async fn stored_cells(
    pool: &PgPool,
) -> BTreeMap<(i16, i32, i32, i16, String, String), (i32, i64, i64)> {
    sqlx::query!("SELECT z, tx, ty, cell, category, kind, n, sx, sy FROM poi_cluster_cells")
        .fetch_all(pool)
        .await
        .unwrap()
        .into_iter()
        .map(|r| {
            (
                (r.z, r.tx, r.ty, r.cell, r.category, r.kind),
                (r.n, r.sx, r.sy),
            )
        })
        .collect()
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_cluster_cells_are_the_counts_of_the_published_points(pool: PgPool) {
    // Points around 5.625 E, 45.089 N, a corner of tiles of zooms 6 to 9,
    // of every kind, the food vending machines among them.
    let mut state: u64 = 11;
    let mut next = move |n: u64| {
        state = state
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1_442_695_040_888_963_407);
        (state >> 33) % n
    };
    let mut seeds = Vec::new();
    for i in 0..600 {
        let kinds = u64::try_from(PoiKind::ALL.len()).unwrap();
        let kind = PoiKind::ALL[usize::try_from(next(kinds)).unwrap()];
        let lat = 44.9 + f64::from(u32::try_from(next(4_000)).unwrap()) / 10_000.0;
        let lon = 5.425 + f64::from(u32::try_from(next(4_000)).unwrap()) / 10_000.0;
        seeds.push((format!("node/{i}"), point(kind, lat, lon, kind.code())));
    }
    let refs: Vec<(&str, PoiRecord)> = seeds.iter().map(|(i, r)| (i.as_str(), r.clone())).collect();
    store(&pool, &refs).await;
    assert!(
        stored_cells(&pool).await.is_empty(),
        "the cells are those of the published version"
    );
    let v = version(&pool).await;
    pois::mark_layer_now(&pool).await.unwrap();
    assert!(version(&pool).await > v);
    let expected = cells_of_the_points(&pool).await;
    assert!(
        expected.keys().any(|k| !k.5.is_empty()),
        "the seeds hold vending machines a filter picks"
    );
    assert_eq!(
        stored_cells(&pool).await,
        expected,
        "a version publishes the cells of its points"
    );

    // Points gone, hidden and new: the cells stay those of the version
    // until the next one.
    sqlx::query!(
        "UPDATE pois SET deleted_at = now() WHERE external_id IN ('node/1', 'node/2', 'node/3')"
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query!("UPDATE pois SET hidden = true WHERE external_id = 'node/4'")
        .execute(&pool)
        .await
        .unwrap();
    store(
        &pool,
        &[(
            "node/new",
            point(PoiKind::VendingPizza, 45.089, 5.625, "Pizza"),
        )],
    )
    .await;
    assert_eq!(stored_cells(&pool).await, expected);
    sqlx::query("UPDATE poi_layer SET changed_at = now() - interval '1 second'")
        .execute(&pool)
        .await
        .unwrap();
    pois::mark_layer_now(&pool).await.unwrap();
    pois::publish_layer(&pool, std::time::Duration::ZERO)
        .await
        .unwrap()
        .expect("a change waits");
    let after = cells_of_the_points(&pool).await;
    assert_ne!(after, expected);
    assert_eq!(stored_cells(&pool).await, after, "the next version");

    // A moderator's hide publishes at once, the cells with it.
    sqlx::query!("UPDATE pois SET hidden = true WHERE external_id = 'node/new'")
        .execute(&pool)
        .await
        .unwrap();
    let mut tx = pois::begin_poi_writer(&pool).await.unwrap();
    pois::publish_layer_now(&mut tx).await.unwrap();
    tx.commit().await.unwrap();
    assert_eq!(stored_cells(&pool).await, cells_of_the_points(&pool).await);
}

#[sqlx::test(migrations = "../../migrations")]
async fn hours_gone_from_the_source_leave_nothing_behind(pool: PgPool) {
    let mut bakery = point(PoiKind::Bakery, 45.0, 5.0, "Boulangerie");
    bakery.opening_hours = Some("Mo-Sa 07:00-13:00".into());
    store(&pool, &[("node/1", bakery.clone())]).await;
    let poi = sqlx::query_scalar!("SELECT id FROM pois")
        .fetch_one(&pool)
        .await
        .unwrap();
    let today = chrono::NaiveDate::from_ymd_opt(2026, 11, 2).unwrap();
    let now = Utc.with_ymd_and_hms(2026, 11, 2, 12, 0, 0).unwrap();
    let mut tx = pois::begin_poi_writer(&pool).await.unwrap();
    let stale = pois::stale_hours(&mut tx, now, 10).await.unwrap();
    assert_eq!(stale.len(), 1);
    assert_eq!(stale[0].source_id, SourceId::OSM);
    pois::set_hours(
        &mut tx,
        &[pois::HoursWrite {
            id: poi,
            parsed: true,
            intervals: Some(Vec::new()),
            until: Some(Utc.with_ymd_and_hms(2026, 11, 15, 23, 0, 0).unwrap()),
            window_start: today,
            refresh_at: Utc.with_ymd_and_hms(2026, 11, 2, 23, 0, 0).unwrap(),
            source: Some(SourceId::OSM),
            tile: Some(String::new()),
        }],
    )
    .await
    .unwrap();
    tx.commit().await.unwrap();
    bakery.opening_hours = None;
    store(&pool, &[("node/1", bakery)]).await;
    let r = sqlx::query!(
        r#"SELECT opening_hours_parsed, opening_intervals, opening_intervals_until,
                  opening_source, opening_tile FROM pois WHERE id = $1"#,
        poi
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(!r.opening_hours_parsed);
    assert!(
        r.opening_intervals.is_none()
            && r.opening_intervals_until.is_none()
            && r.opening_source.is_none()
            && r.opening_tile.is_none(),
        "the map and the app would otherwise show hours the source took back"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn neither_its_author_nor_a_moderator_s_hide_opens_a_check(pool: PgPool) {
    let author = account(&pool, 1).await;
    let key = Uuid::now_v7();
    sqlx::query!(
        "INSERT INTO device_keys (id, account_id, thumbprint, public_key) VALUES ($1, $2, $3, $4)",
        key,
        author,
        "b".repeat(43),
        vec![4u8; 65],
    )
    .execute(&pool)
    .await
    .unwrap();
    let machine = NewVendingMachine {
        kind: PoiKind::VendingPizza,
        position: Position::new(47.27, -0.07).unwrap(),
        name: None,
        operator: None,
        brand: None,
        products: Vec::new(),
        payment: Vec::new(),
        always_open: true,
    };
    let row = submissions::submit(
        &pool,
        NewSubmission {
            account: author,
            device_key: key,
            what: Submitted::Poi(&machine),
            accepted: true,
            held_for: None,
        },
    )
    .await
    .unwrap();
    let mut tx = pois::begin_poi_writer(&pool).await.unwrap();
    pois::apply_submissions(&mut tx).await.unwrap();
    tx.commit().await.unwrap();
    let poi = submissions::submission(&pool, row.id)
        .await
        .unwrap()
        .unwrap()
        .poi_id
        .unwrap();
    for _ in 0..3 {
        let a = account(&pool, 1).await;
        pois::confirm(&pool, a, poi, false).await.unwrap();
    }
    // Its author answers last, and would otherwise hold it up.
    pois::confirm(&pool, author, poi, true).await.unwrap();
    refresh(&pool).await;
    assert!(
        hidden(&pool, poi).await,
        "the answers of a point's author do not count on it"
    );
    assert_eq!(open_checks(&pool, poi).await, 1);

    // A point a moderator hides opens nothing to decide.
    store(
        &pool,
        &[("node/9", point(PoiKind::Toilets, 45.0, 5.0, "WC"))],
    )
    .await;
    let other = sqlx::query_scalar!("SELECT id FROM pois WHERE external_id = 'node/9'")
        .fetch_one(&pool)
        .await
        .unwrap();
    lunaway_db::moderation::hide_poi(&pool, other, true, Some("spam"))
        .await
        .unwrap();
    refresh(&pool).await;
    assert!(hidden(&pool, other).await);
    assert_eq!(
        open_checks(&pool, other).await,
        0,
        "approving such a check would undo the moderator's decision"
    );
}
