//! Scratch, build server only: stores OpenStreetMap's cameras of the
//! Limousin extract the local engine runs on, to measure the zone build
//! against the real engine. Never committed.

#![allow(clippy::unwrap_used, clippy::expect_used, reason = "scratch")]

use lunaway_db::enforcement::{self as db, NewDevice};
use lunaway_domain::SourceId;
use lunaway_ingest::{cameras_osm, osm_extract};

#[tokio::test]
#[ignore = "scratch"]
async fn store_limousin_cameras() {
    let pool = sqlx::PgPool::connect(&std::env::var("DATABASE_URL").unwrap())
        .await
        .unwrap();
    let area = osm_extract::Area::of(&osm_extract::extract("france").unwrap());
    let listed = cameras_osm::read(
        std::path::Path::new("/root/valhalla/input/extract.osm.pbf"),
        area,
    )
    .unwrap();
    let raw = serde_json::json!({});
    let rows: Vec<NewDevice<'_>> = listed
        .iter()
        .map(|l| NewDevice {
            device: &l.device,
            country: "FR",
            scope: "FR",
            raw: &raw,
        })
        .collect();
    let n = db::upsert_devices(&pool, &SourceId::OSM, &rows, chrono::Utc::now())
        .await
        .unwrap();
    let with_bearing = listed
        .iter()
        .filter(|l| l.device.bearing_deg.is_some())
        .count();
    println!(
        "osm cameras {} stored {n} with bearing {with_bearing}",
        listed.len()
    );
}
