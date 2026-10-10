//! The addresses of the places no source gives a street: which places are
//! due for a reverse geocoding, what an answer writes, and what the
//! conflation keeps of it when it writes the place again.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use lunaway_db::{
    PgPool,
    conflation::{self, OpeningEval, PlaceWrite},
    place_addresses,
    places::{self, Change},
    takedowns,
};
use lunaway_domain::{
    Address, BBox, OvernightStatus, PlaceKind, Position, SourceId,
    conflation::{FieldProvenance, PlaceContent},
    place_address::Geocoded,
    takedown::{TakedownCode, TakedownKey},
};
use uuid::Uuid;

fn content(kind: PlaceKind, lat: f64, lon: f64, address: Address) -> PlaceContent {
    PlaceContent {
        name: None,
        kind,
        position: Position::new(lat, lon).unwrap(),
        overnight: OvernightStatus::Unknown,
        services: Vec::new(),
        activities: Vec::new(),
        description: None,
        address,
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
    }
}

const NO_OPENING: OpeningEval = OpeningEval {
    parsed: false,
    intervals: None,
    until: None,
    window_start: None,
    refresh_at: None,
    season: None,
};

fn extcom_address() -> Vec<FieldProvenance> {
    vec![FieldProvenance {
        field: "address".to_owned(),
        source_id: SourceId::EXTCOM,
        alternatives: Vec::new(),
    }]
}

async fn write(pool: &PgPool, id: Uuid, c: &PlaceContent) {
    let provenance = extcom_address();
    let mut tx = conflation::begin_writer(pool).await.unwrap();
    conflation::upsert_place(
        &mut tx,
        PlaceWrite {
            id,
            content: c,
            provenance: &provenance,
            opening: &NO_OPENING,
            descriptions: &[],
            external_links: &[],
            content_hash: "h",
        },
    )
    .await
    .unwrap();
    tx.commit().await.unwrap();
}

/// Beside the Rhône at Viviers.
const LAT: f64 = 44.4818;
const LON: f64 = 4.6896;

fn town_only() -> Address {
    Address {
        postcode: Some("07220".into()),
        city: Some("Viviers".into()),
        country_code: Some("FR".into()),
        ..Address::default()
    }
}

fn answer(lat: f64, lon: f64) -> Geocoded {
    Geocoded {
        asked: Some(Position::new(lat, lon).unwrap()),
        house_number: Some("4".into()),
        street: Some("Rue de la Gare".into()),
        postcode: Some("07220".into()),
        city: Some("Viviers".into()),
        country_code: Some("FR".into()),
    }
}

async fn apply(pool: &PgPool, id: Uuid, g: &Geocoded) -> bool {
    let mut tx = conflation::begin_writer(pool).await.unwrap();
    let changed = place_addresses::apply(&mut tx, id, g).await.unwrap();
    tx.commit().await.unwrap();
    changed
}

async fn shown(pool: &PgPool, id: Uuid) -> places::PlaceRow {
    places::by_id(pool, id).await.unwrap().unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_place_without_a_street_takes_the_geocoded_address_once(pool: PgPool) {
    let car_park = Uuid::now_v7();
    write(
        &pool,
        car_park,
        &content(PlaceKind::Parking, LAT, LON, town_only()),
    )
    .await;
    let with_street = Uuid::now_v7();
    let mut street = town_only();
    street.street = Some("12 Avenue Mazarin".into());
    write(
        &pool,
        with_street,
        &content(PlaceKind::Parking, LAT, LON, street),
    )
    .await;

    let due = place_addresses::due(&pool, Uuid::nil(), 100).await.unwrap();
    assert_eq!(
        due.iter().map(|d| d.id).collect::<Vec<_>>(),
        [car_park],
        "a place whose source gives a street is never asked"
    );

    let before = places::feed_head(&pool).await.unwrap();
    assert!(apply(&pool, car_park, &answer(LAT, LON)).await);
    let p = shown(&pool, car_park).await;
    assert_eq!(
        p.address.street.as_deref(),
        Some("Rue de la Gare"),
        "a car park takes the street, not the number of the house beside it"
    );
    assert_eq!(p.address.city.as_deref(), Some("Viviers"));
    let credit = p.provenance.iter().find(|f| f.field == "address").unwrap();
    assert_eq!(
        credit.source_id,
        SourceId::OSM,
        "Photon serves OpenStreetMap's data"
    );
    assert_eq!(
        credit.alternatives[0].value, "07220 Viviers, FR",
        "the source's own address stays visible"
    );
    let bbox = BBox::new(LAT - 0.01, LON - 0.01, LAT + 0.01, LON + 0.01).unwrap();
    let (feed, _) = places::changes(&pool, bbox, before.last_seq, 100, true)
        .await
        .unwrap();
    assert!(
        feed.iter()
            .any(|c| matches!(c, Change::Upsert(p) if p.id == car_park)),
        "the devices that keep the place get its address"
    );
    assert!(
        place_addresses::due(&pool, Uuid::nil(), 100)
            .await
            .unwrap()
            .is_empty(),
        "a place is asked once"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_conflation_keeps_the_geocoded_address_until_the_place_moves(pool: PgPool) {
    let id = Uuid::now_v7();
    let c = content(PlaceKind::Parking, LAT, LON, town_only());
    write(&pool, id, &c).await;
    assert!(apply(&pool, id, &answer(LAT, LON)).await);

    // A source changed something else: the place is written again.
    write(&pool, id, &c).await;
    let p = shown(&pool, id).await;
    assert_eq!(p.address.street.as_deref(), Some("Rue de la Gare"));
    assert_eq!(
        p.provenance
            .iter()
            .find(|f| f.field == "address")
            .unwrap()
            .source_id,
        SourceId::OSM
    );

    // Moved by about 100 m: the old answer no longer applies, and the
    // place is due again.
    let moved = content(PlaceKind::Parking, LAT + 0.0009, LON, town_only());
    write(&pool, id, &moved).await;
    let p = shown(&pool, id).await;
    assert_eq!(
        p.address.street, None,
        "a street of where it stood is not its own"
    );
    assert_eq!(p.address.city.as_deref(), Some("Viviers"));
    let due = place_addresses::due(&pool, Uuid::nil(), 100).await.unwrap();
    assert_eq!(due.iter().map(|d| d.id).collect::<Vec<_>>(), [id]);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_private_host_never_gets_a_street(pool: PgPool) {
    let host = Uuid::now_v7();
    let mut given = town_only();
    given.street = Some("3 Impasse des Lilas".into());
    write(&pool, host, &content(PlaceKind::Homestay, LAT, LON, given)).await;
    let p = shown(&pool, host).await;
    assert_eq!(p.address.street, None, "not even the one a source gives");
    assert_eq!(p.address.city.as_deref(), Some("Viviers"));
    assert!(
        place_addresses::due(&pool, Uuid::nil(), 100)
            .await
            .unwrap()
            .is_empty(),
        "a host with its town is never geocoded"
    );

    let bare = Uuid::now_v7();
    write(
        &pool,
        bare,
        &content(PlaceKind::Homestay, LAT, LON, Address::default()),
    )
    .await;
    assert!(apply(&pool, bare, &answer(LAT, LON)).await);
    let p = shown(&pool, bare).await;
    assert_eq!(p.address.street, None);
    assert_eq!(p.address.city.as_deref(), Some("Viviers"), "its town only");
    let kept: (Option<String>, Option<String>) =
        sqlx::query_as("SELECT house_number, street FROM place_geocodes WHERE place_id = $1")
            .bind(bare)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(kept, (None, None), "nor kept aside, in the geocodes");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_farm_that_becomes_a_private_host_forgets_its_street(pool: PgPool) {
    let id = Uuid::now_v7();
    write(&pool, id, &content(PlaceKind::Farm, LAT, LON, town_only())).await;
    assert!(apply(&pool, id, &answer(LAT, LON)).await);
    assert_eq!(
        shown(&pool, id).await.address.street.as_deref(),
        Some("4 Rue de la Gare"),
        "a farm keeps its number"
    );

    write(
        &pool,
        id,
        &content(PlaceKind::Homestay, LAT, LON, town_only()),
    )
    .await;
    let p = shown(&pool, id).await;
    assert_eq!(p.address.street, None);
    assert_eq!(p.address.city.as_deref(), Some("Viviers"));
    let kept: (Option<String>, Option<String>, Option<String>) =
        sqlx::query_as("SELECT house_number, street, city FROM place_geocodes WHERE place_id = $1")
            .bind(id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        kept,
        (None, None, Some("Viviers".into())),
        "the street it had as a farm is not kept aside for a home"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_takedown_forgets_the_address_of_where_the_place_stood(pool: PgPool) {
    let id = Uuid::now_v7();
    write(
        &pool,
        id,
        &content(PlaceKind::Parking, LAT, LON, town_only()),
    )
    .await;
    assert!(apply(&pool, id, &answer(LAT, LON)).await);
    let mut tx = conflation::begin_writer(&pool).await.unwrap();
    let key = TakedownKey::new(&[42; 32]).unwrap();
    takedowns::take_down(&mut tx, id, TakedownCode::PrivateHome, false, &key)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    let kept: i64 = sqlx::query_scalar("SELECT count(*) FROM place_geocodes")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(kept, 0, "nothing of a home's address survives its takedown");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_host_row_written_before_the_rule_lends_no_street_to_its_provenance(pool: PgPool) {
    let host = Uuid::now_v7();
    write(
        &pool,
        host,
        &content(PlaceKind::Homestay, LAT, LON, Address::default()),
    )
    .await;
    // A row the conflation wrote before it stripped a host's street.
    sqlx::query("UPDATE places SET street = '3 Impasse des Lilas' WHERE id = $1")
        .bind(host)
        .execute(&pool)
        .await
        .unwrap();
    assert!(apply(&pool, host, &answer(LAT, LON)).await);
    let p = shown(&pool, host).await;
    assert_eq!(p.address.city.as_deref(), Some("Viviers"));
    let address = p.provenance.iter().find(|f| f.field == "address").unwrap();
    assert!(
        address
            .alternatives
            .iter()
            .all(|a| !a.value.contains("Lilas")),
        "the old street is not kept as another source's: {:?}",
        address.alternatives
    );
}
