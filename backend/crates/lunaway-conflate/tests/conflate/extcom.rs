//! The external community source among the others: its spot merges with
//! the car park OSM maps, each field from the source trusted for it; the
//! switch takes it off every place in one conflation run and puts it back.

use lunaway_db::{PgPool, extcom, places};
use lunaway_domain::{NormalizedRecord, OvernightStatus, PlaceKind, Position, Service, SourceId};
use lunaway_ingest::{FetchedRecord, store::store_complete};

use super::{at, live_places, place_of, run};

fn fetched(id: &str, record: NormalizedRecord) -> FetchedRecord {
    FetchedRecord {
        external_id: id.to_owned(),
        external_url: None,
        record,
        raw: serde_json::json!({ "id": id }),
        fetched_at: at(1),
    }
}

async fn seed(pool: &PgPool) {
    let mut osm =
        NormalizedRecord::new(PlaceKind::Parking, Position::new(45.8992, 6.1294).unwrap());
    osm.name = Some("Parking du Lac".into());
    osm.services = [Service::Toilets].into();
    osm.max_height_m = Some(2.2);
    store_complete(
        pool,
        &SourceId::OSM,
        Some("FR-ARA"),
        &[fetched("way/1", osm)],
    )
    .await
    .unwrap();
    // A visitor's pin 40 m north, and a spot OSM does not know, 5 km away.
    let mut pin = NormalizedRecord::new(
        PlaceKind::Parking,
        Position::new(45.8992 + 40.0 / 111_320.0, 6.1294).unwrap(),
    );
    pin.name = Some("Parking du lac".into());
    pin.accuracy_m = 20.0;
    pin.overnight = OvernightStatus::Tolerated;
    pin.services = [Service::DrinkingWater, Service::WasteBin].into();
    pin.max_height_m = Some(2.5);
    let mut alone = NormalizedRecord::new(PlaceKind::Nature, Position::new(45.95, 6.15).unwrap());
    alone.name = Some("Spot au bord du torrent".into());
    alone.accuracy_m = 20.0;
    store_complete(
        pool,
        &SourceId::EXTCOM,
        None,
        &[fetched("1001", pin), fetched("1002", alone)],
    )
    .await
    .unwrap();
}

async fn shown(pool: &PgPool, place: uuid::Uuid) -> (String, Vec<String>, f64, i64) {
    sqlx::query_as::<_, (String, Vec<String>, f64, i64)>(
        "SELECT overnight, services, max_height_m, updated_seq FROM places WHERE id = $1",
    )
    .bind(place)
    .fetch_one(pool)
    .await
    .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_community_pin_merges_with_the_mapped_car_park_field_by_field(pool: PgPool) {
    seed(&pool).await;
    run(&pool, at(1), None).await.unwrap();
    assert_eq!(
        live_places(&pool).await,
        2,
        "the pin joins the car park; the lone spot stands"
    );
    let place = place_of(&pool, &SourceId::OSM, "way/1").await;
    assert_eq!(place_of(&pool, &SourceId::EXTCOM, "1001").await, place);
    let (overnight, services, height, _) = shown(&pool, place).await;
    assert_eq!(overnight, "tolerated", "visitors know the nights");
    assert_eq!(
        services,
        ["drinking_water", "waste_bin"],
        "the services visitors report rank above the mapped ones"
    );
    assert!(
        (height - 2.2).abs() < 1e-9,
        "the height limit mapped from the sign ranks above a visitor's"
    );
    let sources = places::sources_of(&pool, &[place]).await.unwrap();
    let extcom = sources
        .iter()
        .find(|s| s.source_id == SourceId::EXTCOM)
        .expect("the place lists the external community source");
    assert_eq!(extcom.source_name, "Source communautaire externe");
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_switch_takes_the_source_off_every_place_and_puts_it_back(pool: PgPool) {
    seed(&pool).await;
    run(&pool, at(1), None).await.unwrap();
    let place = place_of(&pool, &SourceId::OSM, "way/1").await;
    let (_, _, _, seq_before) = shown(&pool, place).await;

    extcom::set_hidden(&pool, &SourceId::EXTCOM, true, Some("test"))
        .await
        .unwrap();
    assert!(
        places::sources_of(&pool, &[place])
            .await
            .unwrap()
            .iter()
            .all(|s| s.source_id != SourceId::EXTCOM),
        "a hidden source leaves a place's sources at once, before any conflation"
    );
    let stats = run(&pool, at(1), None).await.unwrap();
    assert_eq!(
        stats.tombstoned, 1,
        "the spot only the hidden source knew is gone"
    );
    assert_eq!(live_places(&pool).await, 1);
    let (overnight, services, _, seq_hidden) = shown(&pool, place).await;
    assert_eq!(
        overnight, "unknown",
        "nothing of the hidden source is shown"
    );
    assert_eq!(services, ["toilets"]);
    assert!(
        seq_hidden > seq_before,
        "the place moves in the change feed, so every device drops the hidden values"
    );

    extcom::set_hidden(&pool, &SourceId::EXTCOM, false, None)
        .await
        .unwrap();
    run(&pool, at(1), None).await.unwrap();
    assert_eq!(live_places(&pool).await, 2);
    assert_eq!(place_of(&pool, &SourceId::EXTCOM, "1001").await, place);
    let (overnight, _, _, _) = shown(&pool, place).await;
    assert_eq!(
        overnight, "tolerated",
        "shown again, the source supplies its values again"
    );
}
