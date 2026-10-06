//! Storing fetched records: a country extract speaks for every OSM record,
//! whatever region an earlier Overpass run filed it under.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::{TimeZone, Utc};
use lunaway_db::{PgPool, records};
use lunaway_domain::SourceId;
use lunaway_ingest::{
    osm,
    store::{store_complete, store_whole_source},
};

const OVERPASS: &[u8] = include_bytes!("fixtures/overpass_sample.json");

#[sqlx::test(migrations = "../../migrations")]
async fn an_extract_retires_records_of_every_region(pool: PgPool) {
    let at = Utc.with_ymd_and_hms(2026, 10, 5, 22, 0, 0).unwrap();
    let all = osm::parse(OVERPASS, at).unwrap().records;
    let (anjou, coast): (Vec<_>, Vec<_>) = all
        .iter()
        .cloned()
        .partition(|r| r.record.position.lon() > -1.0);
    store_complete(&pool, &SourceId::OSM, Some("FR-PDL"), &anjou)
        .await
        .unwrap();
    store_complete(&pool, &SourceId::OSM, Some("FR-BRE"), &coast)
        .await
        .unwrap();

    // The extract no longer holds one record of each region.
    let dropped = [anjou[0].external_id.clone(), coast[0].external_id.clone()];
    let extract: Vec<_> = all
        .iter()
        .filter(|r| !dropped.contains(&r.external_id))
        .cloned()
        .collect();
    let report = store_whole_source(&pool, &SourceId::OSM, "FR", &extract)
        .await
        .unwrap();
    assert_eq!(report.retired, 2, "both regions lose their missing record");
    assert_eq!(report.upsert.unchanged, 17);
    assert_eq!(
        records::live_count(&pool, &SourceId::OSM, None)
            .await
            .unwrap(),
        17
    );
    assert_eq!(
        records::live_count(&pool, &SourceId::OSM, Some("FR"))
            .await
            .unwrap(),
        17,
        "the records seen now belong to the extract's scope"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_truncated_extract_retires_nothing(pool: PgPool) {
    let at = Utc.with_ymd_and_hms(2026, 10, 5, 22, 0, 0).unwrap();
    let all = osm::parse(OVERPASS, at).unwrap().records;
    store_complete(&pool, &SourceId::OSM, Some("FR-PDL"), &all)
        .await
        .unwrap();
    let report = store_whole_source(&pool, &SourceId::OSM, "FR", &all[..5])
        .await
        .unwrap();
    assert!(report.retire_refused);
    assert_eq!(
        records::live_count(&pool, &SourceId::OSM, None)
            .await
            .unwrap(),
        19
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_record_stored_without_a_scope_is_french_to_a_run_of_countries(pool: PgPool) {
    use lunaway_ingest::{osm_extract::Coverage, store::retire_in_coverage};
    use std::collections::BTreeMap;
    let at = Utc.with_ymd_and_hms(2026, 10, 5, 22, 0, 0).unwrap();
    let all = osm::parse(OVERPASS, at).unwrap().records;
    store_complete(&pool, &SourceId::OSM, None, &all)
        .await
        .unwrap();
    let ids: Vec<String> = all.iter().map(|r| r.external_id.clone()).collect();

    let france = Coverage::Countries(["FR".to_owned()].into());
    let seen = &ids[1..];
    let by_scope = BTreeMap::from([("FR".to_owned(), seen.len())]);
    let reads = BTreeMap::from([("FR".to_owned(), at)]);
    let r = retire_in_coverage(&pool, &SourceId::OSM, &france, seen, &by_scope, &reads, at)
        .await
        .unwrap();
    assert_eq!(
        (r.retired, r.refused.len()),
        (1, 0),
        "France's run speaks for what France's import stored before scopes"
    );

    let seen = &ids[2..];
    let by_scope = BTreeMap::from([("FR".to_owned(), seen.len())]);
    let r = retire_in_coverage(
        &pool,
        &SourceId::OSM,
        &Coverage::Everywhere,
        seen,
        &by_scope,
        &BTreeMap::from([("*".to_owned(), at)]),
        at,
    )
    .await
    .unwrap();
    assert_eq!(r.retired, 1, "a continent speaks for every record");
    assert_eq!(
        records::live_count(&pool, &SourceId::OSM, None)
            .await
            .unwrap(),
        i64::try_from(ids.len() - 2).unwrap()
    );
}

/// The version of every row, by id: a row written again gets a new one.
async fn row_versions(pool: &PgPool) -> Vec<(uuid::Uuid, String)> {
    sqlx::query!(r#"SELECT id, xmin::text AS "v!" FROM source_records ORDER BY id"#)
        .fetch_all(pool)
        .await
        .unwrap()
        .into_iter()
        .map(|r| (r.id, r.v))
        .collect()
}

/// Each record's own date and the date a client sees, by external id.
async fn dates(
    pool: &PgPool,
) -> std::collections::BTreeMap<String, (chrono::DateTime<Utc>, chrono::DateTime<Utc>)> {
    sqlx::query!(
        r#"
        SELECT external_id, fetched_at,
               lunaway_read_at('records', source_id, scope, fetched_at, deleted_at) AS "seen!"
        FROM source_records
        "#
    )
    .fetch_all(pool)
    .await
    .unwrap()
    .into_iter()
    .map(|r| (r.external_id, (r.fetched_at, r.seen)))
    .collect()
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_unchanged_import_writes_no_row_and_still_dates_its_read(pool: PgPool) {
    let day = |d| Utc.with_ymd_and_hms(2026, 10, d, 22, 0, 0).unwrap();
    let all = osm::parse(OVERPASS, day(1)).unwrap().records;
    store_complete(&pool, &SourceId::OSM, Some("FR-PDL"), &all)
        .await
        .unwrap();
    let written = row_versions(&pool).await;

    let again = osm::parse(OVERPASS, day(2)).unwrap().records;
    let report = store_complete(&pool, &SourceId::OSM, Some("FR-PDL"), &again)
        .await
        .unwrap();
    assert_eq!(
        (
            report.upsert.inserted,
            report.upsert.changed,
            report.upsert.unchanged
        ),
        (0, 0, 19)
    );
    assert_eq!(
        row_versions(&pool).await,
        written,
        "a source read again as it was writes no row: rewriting them all doubled the table \
         until the next vacuum"
    );
    for (id, (own, seen)) in dates(&pool).await {
        assert_eq!(own, day(1), "{id} keeps the read that wrote it");
        assert_eq!(
            seen,
            day(2),
            "{id} was in the second read, and a client sees that date"
        );
    }

    // A record changes and another leaves the source.
    let mut third = osm::parse(OVERPASS, day(3)).unwrap().records;
    let changed = third[0].external_id.clone();
    third[0].record.name = Some("Aire renommée".to_owned());
    let gone = third.remove(1).external_id;
    let report = store_complete(&pool, &SourceId::OSM, Some("FR-PDL"), &third)
        .await
        .unwrap();
    assert_eq!((report.upsert.changed, report.retired), (1, 1));
    let rewritten: Vec<uuid::Uuid> = written
        .iter()
        .zip(row_versions(&pool).await)
        .filter(|(before, after)| before.1 != after.1)
        .map(|(_, after)| after.0)
        .collect();
    assert_eq!(
        rewritten.len(),
        2,
        "the changed row and the retired one only"
    );
    let dated = dates(&pool).await;
    assert_eq!(dated[&changed], (day(3), day(3)));
    assert_eq!(
        dated[&gone],
        (day(2), day(2)),
        "a retired record keeps the date of the last read that held it"
    );

    // A read that looks truncated retires nothing and dates nothing.
    let fourth = osm::parse(OVERPASS, day(4)).unwrap().records;
    let report = store_complete(&pool, &SourceId::OSM, Some("FR-PDL"), &fourth[2..6])
        .await
        .unwrap();
    assert!(report.retire_refused);
    let other = &fourth[10].external_id;
    assert_eq!(
        dates(&pool).await[other].1,
        day(3),
        "a record the truncated read did not hold was last read on day 3"
    );
}
