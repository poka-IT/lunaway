//! The adapters on recorded, trimmed real payloads: an Overpass answer
//! around Angers and the Loire-Atlantique coast (ODbL, © OpenStreetMap
//! contributors), rows of the Atout France CSV and the BAN's answer for them
//! (Licence Ouverte 2.0).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::{TimeZone, Utc};
use lunaway_domain::{OvernightStatus, PlaceKind, Service};
use lunaway_ingest::{FetchedRecord, atout_france, geocode, osm};

const OVERPASS: &[u8] = include_bytes!("fixtures/overpass_sample.json");
const ATOUT_CSV: &[u8] = include_bytes!("fixtures/atout_france_sample.csv");
const BAN_ANSWER: &[u8] = include_bytes!("fixtures/ban_answer_sample.csv");

fn osm_records() -> (osm::Parsed, chrono::DateTime<Utc>) {
    let at = Utc.with_ymd_and_hms(2026, 10, 5, 22, 42, 50).unwrap();
    (osm::parse(OVERPASS, at).unwrap(), at)
}

fn find<'a>(records: &'a [FetchedRecord], id: &str) -> &'a FetchedRecord {
    records
        .iter()
        .find(|r| r.external_id == id)
        .unwrap_or_else(|| panic!("{id} missing"))
}

#[test]
fn every_overpass_element_becomes_a_record_or_joins_its_site() {
    let (p, at) = osm_records();
    assert!(p.skipped.is_empty(), "{:?}", p.skipped);
    assert_eq!(
        p.attached_dump_stations, 3,
        "three bornes stand inside a campsite"
    );
    assert_eq!(
        p.records.len(),
        19,
        "22 elements, 3 of them folded into their site"
    );
    assert!(p.records.iter().all(|r| r.fetched_at == at));
    let kinds = |k: PlaceKind| p.records.iter().filter(|r| r.record.kind == k).count();
    assert_eq!(kinds(PlaceKind::Campsite), 9);
    assert_eq!(kinds(PlaceKind::MotorhomeArea), 7);
    assert_eq!(kinds(PlaceKind::Parking), 1);
    assert_eq!(kinds(PlaceKind::ServiceArea), 2, "two bornes stand alone");
}

#[test]
fn a_campsite_way_is_mapped_with_its_size_and_its_attached_dump_station() {
    let (p, _) = osm_records();
    let r = find(&p.records, "way/207901408");
    assert_eq!(
        r.external_url.as_deref(),
        Some("https://www.openstreetmap.org/way/207901408")
    );
    let x = &r.record;
    assert_eq!(x.kind, PlaceKind::Campsite);
    assert_eq!(x.name.as_deref(), Some("Camping municipal du Port"));
    assert_eq!(x.overnight, OvernightStatus::Allowed);
    assert!(
        (x.accuracy_m - 109.3).abs() < 0.1,
        "half the diagonal of the way's bounding box: {}",
        x.accuracy_m
    );
    for s in [
        Service::DrinkingWater,
        Service::Toilets,
        Service::Showers,
        Service::Electricity,
    ] {
        assert!(x.services.contains(&s), "{s:?} from the site's own tags");
    }
    assert!(
        x.services.contains(&Service::BlackWater) && x.services.contains(&Service::GreyWater),
        "the borne inside the campsite gives it its dump services"
    );
    assert_eq!(
        r.raw["_attached"].as_array().map(Vec::len),
        Some(1),
        "the borne is kept in the raw payload"
    );
    assert_eq!(x.osm_ref.as_deref(), Some("way/207901408"));
    assert_eq!(
        x.phone.as_deref(),
        Some("+33 2 41 72 20 75; +33 6 71 78 51 73")
    );
    assert_eq!(x.address.country_code.as_deref(), Some("FR"));
}

#[test]
fn an_explicit_motorhome_stopover_stays_one_even_with_campsite_services() {
    let (p, _) = osm_records();
    let x = &find(&p.records, "way/193703749").record;
    assert_eq!(x.name.as_deref(), Some("Camping de Bouchemaine"));
    assert_eq!(
        x.kind,
        PlaceKind::MotorhomeArea,
        "caravan_site=motorhome_stopover wins over the name"
    );
    assert_eq!(x.price_parking_eur, Some(17.0));
}

#[test]
fn prices_read_only_what_is_unambiguous() {
    let (p, _) = osm_records();
    assert_eq!(
        find(&p.records, "way/565675851").record.price_parking_eur,
        Some(14.3)
    );
    assert_eq!(
        find(&p.records, "way/435157184").record.price_parking_eur,
        Some(13.5)
    );
    assert_eq!(
        find(&p.records, "way/435157186").record.price_parking_eur,
        None,
        "\"13/50 EUR / night\" is a typo, not a price"
    );
    assert_eq!(
        find(&p.records, "way/1317588157").record.price_parking_eur,
        Some(0.0),
        "fee=no is free"
    );
    let borne = &find(&p.records, "node/9827293952").record;
    assert_eq!(borne.kind, PlaceKind::ServiceArea);
    assert_eq!(
        borne.price_services_eur,
        Some(0.0),
        "a borne's fee is the price of its services"
    );
    assert_eq!(borne.price_parking_eur, None);
}

#[test]
fn a_motorhome_car_park_takes_its_night_from_its_tags() {
    let (p, _) = osm_records();
    let x = &find(&p.records, "way/319419555").record;
    assert_eq!(x.kind, PlaceKind::Parking);
    assert_eq!(
        x.overnight,
        OvernightStatus::DayOnly,
        "motorhome=yes says nothing of the night, motorhome:overnight=no does \
         (\"Stationnement Camping-Cars (de Jour)\")"
    );
    assert_eq!(x.capacity, None, "a car park's capacity counts cars");
}

fn atout() -> atout_france::ParsedCsv {
    atout_france::parse_csv(ATOUT_CSV).unwrap()
}

#[test]
fn the_csv_keeps_the_metropolitan_campsites() {
    let p = atout();
    assert_eq!(p.campsites.len(), 12);
    assert_eq!(p.other_kinds, 1, "the hotel");
    assert_eq!(p.overseas, 1, "the campsite in La Réunion");
    assert_eq!(
        p.duplicates, 0,
        "two \"Camping du Lac\" share a postcode but not a municipality"
    );
    let ids: Vec<&str> = p.campsites.iter().map(|c| c.external_id.as_str()).collect();
    assert!(ids.contains(&"40200:mimizan:camping-du-lac"));
    assert!(ids.contains(&"40200:sainte-eulalie-en-born:camping-du-lac"));
}

#[test]
fn the_geocoder_request_matches_the_recorded_answer() {
    let p = atout();
    let queries = atout_france::address_queries(&p.campsites);
    let answer = geocode::parse_answer(BAN_ANSWER).unwrap();
    let mut asked: Vec<&str> = queries.iter().map(|q| q.key.as_str()).collect();
    let mut answered: Vec<&str> = answer.iter().map(|g| g.key.as_str()).collect();
    asked.sort_unstable();
    answered.sort_unstable();
    assert_eq!(
        asked, answered,
        "the keys sent are the keys the recorded answer carries"
    );
}

#[test]
fn geocoded_campsites_become_records_and_misses_are_counted() {
    let p = atout();
    let answer = geocode::parse_answer(BAN_ANSWER).unwrap();
    let at = Utc.with_ymd_and_hms(2026, 10, 6, 0, 0, 0).unwrap();
    let (records, drops) = atout_france::to_records(&p.campsites, &answer, at);
    assert_eq!(records.len(), 10);
    assert_eq!(
        drops,
        atout_france::GeocodeDrops {
            not_found: 2,
            low_score: 0,
            municipality_only: 0
        },
        "La Bradière and the farm at Hélette are not in the address base"
    );

    let etang = find(&records, "49320:brissac-quince:ecoetang-camping-de-l-etang");
    let x = &etang.record;
    assert_eq!(x.kind, PlaceKind::Campsite);
    assert_eq!(x.name.as_deref(), Some("Écoétang Camping de l'Étang"));
    assert_eq!(x.stars, Some(4));
    assert_eq!(x.capacity, Some(163), "pitches, not people");
    assert!(
        (x.accuracy_m - 30.0).abs() < f64::EPSILON,
        "a house-number match"
    );
    assert_eq!(x.address.city.as_deref(), Some("Brissac-Quincé"));
    assert_eq!(
        x.address.city_code.as_deref(),
        Some("49050"),
        "the INSEE code from the geocoder"
    );
    assert_eq!(x.overnight, OvernightStatus::Allowed);
    assert_eq!(etang.raw["geocoding"]["type"], "HouseNumber");
    assert_eq!(
        etang.raw["row"]["NOM COMMERCIAL"],
        "ÉCOÉTANG CAMPING DE L'ÉTANG"
    );

    let port = &find(&records, "49170:la-possonniere:camping-municipal-du-port").record;
    assert!(
        (port.accuracy_m - 250.0).abs() < f64::EPSILON,
        "a street match is the street's middle"
    );
    assert_eq!(port.stars, Some(1));

    let lodging = &find(
        &records,
        "49130:sainte-gemmes-sur-loire:lodg-ing-nature-camp-anjou",
    )
    .record;
    assert_eq!(
        lodging.website.as_deref(),
        Some("http://www.lodg-ing.com"),
        "a scheme is added so the link works"
    );
}
