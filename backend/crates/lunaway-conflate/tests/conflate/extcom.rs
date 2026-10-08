//! The external community source among the others: its spot merges with
//! the car park OSM maps, each field from the source trusted for it; the
//! switch takes it off every place in one conflation run and puts it back.

use lunaway_db::{PgPool, extcom, places};
use lunaway_domain::{NormalizedRecord, OvernightStatus, PlaceKind, Position, Service, SourceId};
use lunaway_ingest::{FetchedRecord, store::store_complete};
use uuid::Uuid;

use super::{at, live_places, place_of, record_id, run};

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

/// A record at `lat`, `lon` with `accuracy_m` of uncertainty.
fn spot(kind: PlaceKind, name: &str, lat: f64, lon: f64, accuracy_m: f64) -> NormalizedRecord {
    let mut r = NormalizedRecord::new(kind, Position::new(lat, lon).unwrap());
    r.name = Some(name.to_owned());
    r.accuracy_m = accuracy_m;
    r
}

/// A pin of the external source, with its postcode.
fn pin(kind: PlaceKind, name: &str, lat: f64, lon: f64, postcode: &str) -> NormalizedRecord {
    let mut r = spot(kind, name, lat, lon, 20.0);
    r.address.postcode = Some(postcode.to_owned());
    r
}

/// The stored score of the merge decision between two records.
async fn merge_score(pool: &PgPool, a: Uuid, b: Uuid) -> f64 {
    let (lo, hi) = if a < b { (a, b) } else { (b, a) };
    sqlx::query_scalar::<_, f64>(
        "SELECT score FROM match_pairs \
         WHERE record_a = $1 AND record_b = $2 AND decision = 'merge'",
    )
    .bind(lo)
    .bind(hi)
    .fetch_one(pool)
    .await
    .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn each_pin_joins_the_spot_it_stands_on_when_the_scores_tie(pool: PgPool) {
    // The records as stored in production on 2026-10-07 (report 67). On
    // the A7 at Saint-Rambert-d'Albon, OSM maps each side of the motorway
    // area as a polygon whose accuracy covers both pins of the external
    // source, so all four pairs score 1.0. At Le Pont-de-Montvert, the
    // tourist office's motorhome area scores 0.9 with a car park 79 m away
    // and with the service area 17 m away. The record keys broke those
    // ties, and crossed the pins over.
    let mut west = spot(
        PlaceKind::RestArea,
        "Aire de Saint-Rambert-d'Albon Ouest",
        45.276_229,
        4.826_000,
        414.4,
    );
    west.osm_ref = Some("way/129217210".into());
    let mut east = spot(
        PlaceKind::RestArea,
        "Aire de Saint-Rambert-d'Albon Est",
        45.276_494,
        4.828_141,
        353.7,
    );
    east.osm_ref = Some("way/129268256".into());
    store_complete(
        &pool,
        &SourceId::OSM,
        Some("FR-ARA"),
        &[
            fetched("way/129217210", west),
            fetched("way/129268256", east),
        ],
    )
    .await
    .unwrap();
    let mut office = spot(
        PlaceKind::MotorhomeArea,
        "AIRE DE SERVICE COMMUNALE DU PONT MONTVERT",
        44.363_854,
        3.746_413,
        240.0,
    );
    office.address.postcode = Some("48220".into());
    office.address.city_code = Some("48116".into());
    store_complete(
        &pool,
        &SourceId::DATATOURISME,
        None,
        &[fetched("office", office)],
    )
    .await
    .unwrap();
    let area = "Saint-Rambert-d'Albon - Aire de Saint-Rambert-d'Albon";
    store_complete(
        &pool,
        &SourceId::EXTCOM,
        None,
        &[
            fetched(
                "east-pin",
                pin(PlaceKind::RestArea, area, 45.277_190, 4.828_461, "26140"),
            ),
            fetched(
                "west-pin",
                pin(PlaceKind::RestArea, area, 45.276_537, 4.825_698, "26140"),
            ),
            fetched(
                "car-park",
                pin(
                    PlaceKind::Parking,
                    "Le Pont-de-Montvert - Route de Finiels",
                    44.363_899,
                    3.745_420,
                    "48220",
                ),
            ),
            fetched(
                "service-area",
                pin(
                    PlaceKind::ServiceArea,
                    "Pont-de-Montvert-Sud-Mont-Lozère - 5 Route de Finiels",
                    44.363_913,
                    3.746_221,
                    "48220",
                ),
            ),
        ],
    )
    .await
    .unwrap();
    run(&pool, at(1), None).await.unwrap();

    let west = record_id(&pool, &SourceId::OSM, "way/129217210").await;
    let east = record_id(&pool, &SourceId::OSM, "way/129268256").await;
    let east_pin = record_id(&pool, &SourceId::EXTCOM, "east-pin").await;
    let west_pin = record_id(&pool, &SourceId::EXTCOM, "west-pin").await;
    let office = record_id(&pool, &SourceId::DATATOURISME, "office").await;
    let car_park = record_id(&pool, &SourceId::EXTCOM, "car-park").await;
    let service_area = record_id(&pool, &SourceId::EXTCOM, "service-area").await;
    for (a, b, score) in [
        (west, east_pin, 1.0),
        (west, west_pin, 1.0),
        (east, east_pin, 1.0),
        (east, west_pin, 1.0),
        (office, car_park, 0.9),
        (office, service_area, 0.9),
    ] {
        assert!(
            (merge_score(&pool, a, b).await - score).abs() < 1e-9,
            "the score alone cannot tell the pairings apart"
        );
    }
    assert!(
        west < east && east < east_pin && east_pin < west_pin,
        "the keys order the crossed pairing first, as in production"
    );
    assert!(office < car_park && car_park < service_area);

    let place = |source: SourceId, external_id: &'static str| {
        let pool = pool.clone();
        async move { place_of(&pool, &source, external_id).await }
    };
    assert_eq!(
        place(SourceId::EXTCOM, "west-pin").await,
        place(SourceId::OSM, "way/129217210").await,
        "the west pin, 42 m from the west side, joins it"
    );
    assert_eq!(
        place(SourceId::EXTCOM, "east-pin").await,
        place(SourceId::OSM, "way/129268256").await,
        "the east pin, 81 m from the east side, joins it"
    );
    assert_eq!(
        place(SourceId::DATATOURISME, "office").await,
        place(SourceId::EXTCOM, "service-area").await,
        "the office's area joins the service area pinned 17 m away"
    );
    assert_ne!(
        place(SourceId::DATATOURISME, "office").await,
        place(SourceId::EXTCOM, "car-park").await
    );
}
