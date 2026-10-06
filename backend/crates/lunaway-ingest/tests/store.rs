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
