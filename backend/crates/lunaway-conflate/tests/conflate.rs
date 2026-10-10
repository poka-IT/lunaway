//! The conflation on a real database: recorded OSM and Atout France payloads
//! around Angers, plus synthetic records where a case needs exact control.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::{TimeZone, Utc};
use lunaway_conflate::{RunStats, run};
use lunaway_db::{PgPool, places, records};
use lunaway_domain::{
    NormalizedRecord, PlaceKind, Position, SourceId, conflation::ConstraintKind,
    takedown::TakedownCode,
};
use lunaway_ingest::{FetchedRecord, atout_france, geocode, osm, store::store_complete};
use uuid::Uuid;

const OVERPASS: &[u8] = include_bytes!("../../lunaway-ingest/tests/fixtures/overpass_sample.json");
const ATOUT_CSV: &[u8] =
    include_bytes!("../../lunaway-ingest/tests/fixtures/atout_france_sample.csv");
const BAN_ANSWER: &[u8] =
    include_bytes!("../../lunaway-ingest/tests/fixtures/ban_answer_sample.csv");

// A place taken down keeps a zone where nothing new goes live unseen, and
// the journal outside the database brings its takedown back after a
// restore. Kept under tests/conflate/, where cargo makes no binary of it.
#[path = "conflate/takedown_zone.rs"]
mod takedown_zone;

// The confirmations that age out leave the summary as it was.
#[path = "conflate/retention.rs"]
mod retention;

// Whatever takes something off a place's card moves it in the change feed.
#[path = "conflate/feed.rs"]
mod feed;

// The external community source merges like any source, and its switch
// takes it off every place.
#[path = "conflate/extcom.rs"]
mod extcom;

// The towns of the search follow the places' tiles.
#[path = "conflate/towns.rs"]
mod towns;

/// The takedown secret of the tests.
fn test_key() -> lunaway_domain::takedown::TakedownKey {
    lunaway_domain::takedown::TakedownKey::new(&[42; 32]).unwrap()
}

/// Noon UTC of 2026-11-`d`: the same date in Paris, where the places are.
fn at(d: u32) -> chrono::DateTime<Utc> {
    Utc.with_ymd_and_hms(2026, 11, d, 12, 0, 0).unwrap()
}

fn osm_records() -> Vec<FetchedRecord> {
    let at = Utc.with_ymd_and_hms(2026, 10, 5, 22, 0, 0).unwrap();
    osm::parse(OVERPASS, at).unwrap().records
}

fn atout_records() -> Vec<FetchedRecord> {
    let at = Utc.with_ymd_and_hms(2026, 10, 6, 0, 0, 0).unwrap();
    let parsed = atout_france::parse_csv(ATOUT_CSV).unwrap();
    let answer = geocode::parse_answer(BAN_ANSWER).unwrap();
    atout_france::to_records(&parsed.campsites, &answer, at).0
}

async fn ingest_fixtures(pool: &PgPool) {
    store_complete(pool, &SourceId::OSM, Some("FR-PDL"), &osm_records())
        .await
        .unwrap();
    store_complete(pool, &SourceId::ATOUT_FRANCE, None, &atout_records())
        .await
        .unwrap();
}

async fn record_id(pool: &PgPool, source: &SourceId, external_id: &str) -> Uuid {
    records::id_of(pool, source, external_id)
        .await
        .unwrap()
        .unwrap()
}

async fn place_of(pool: &PgPool, source: &SourceId, external_id: &str) -> Uuid {
    let r = record_id(pool, source, external_id).await;
    sqlx::query_scalar!("SELECT place_id FROM place_sources WHERE record_id = $1", r)
        .fetch_one(pool)
        .await
        .unwrap()
}

async fn live_places(pool: &PgPool) -> i64 {
    sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM places WHERE deleted_at IS NULL"#)
        .fetch_one(pool)
        .await
        .unwrap()
}

/// Every place with its content digest, its feed position and its records.
async fn snapshot(pool: &PgPool) -> Vec<(Uuid, String, i64, Option<Uuid>)> {
    sqlx::query!(
        r#"
        SELECT p.id, p.content_hash, p.updated_seq, ps.record_id AS "record_id?"
        FROM places p LEFT JOIN place_sources ps ON ps.place_id = p.id
        ORDER BY p.id, ps.record_id
        "#
    )
    .fetch_all(pool)
    .await
    .unwrap()
    .into_iter()
    .map(|r| (r.id, r.content_hash, r.updated_seq, r.record_id))
    .collect()
}

const PORT_OSM: &str = "way/207901408";
const PORT_AF: &str = "49170:la-possonniere:camping-municipal-du-port";

#[sqlx::test(migrations = "../../migrations")]
async fn a_campsite_listed_by_both_sources_becomes_one_place_with_two_sources(pool: PgPool) {
    ingest_fixtures(&pool).await;
    let stats = run(&pool, at(2), None).await.unwrap();
    assert_eq!(
        stats.dirty, 29,
        "19 OSM and 10 geocoded Atout France records"
    );
    assert_eq!(stats.merges, 6);
    assert_eq!(stats.created, 23, "29 records, 6 merged pairs");
    assert_eq!(live_places(&pool).await, 23);

    let place = place_of(&pool, &SourceId::OSM, PORT_OSM).await;
    assert_eq!(
        place_of(&pool, &SourceId::ATOUT_FRANCE, PORT_AF).await,
        place
    );
    let row = places::by_id(&pool, place).await.unwrap().unwrap();
    assert_eq!(
        row.name.as_deref(),
        Some("Camping municipal du Port"),
        "OSM's spelling"
    );
    assert_eq!(row.stars, Some(1), "Atout France's classification");
    assert_eq!(row.capacity, Some(30), "Atout France's pitches");
    let osm_point = osm_records()
        .into_iter()
        .find(|r| r.external_id == PORT_OSM)
        .unwrap();
    // PostGIS may round the last bit of a coordinate on its way through
    // `geography`; a nanodegree is a tenth of a millimetre.
    let p = osm_point.record.position;
    assert!(
        (row.position.lat() - p.lat()).abs() < 1e-9 && (row.position.lon() - p.lon()).abs() < 1e-9,
        "OSM's mapped point, not the geocoded street"
    );
    let provenance = |field: &str| {
        row.provenance
            .iter()
            .find(|p| p.field == field)
            .unwrap()
            .clone()
    };
    assert_eq!(provenance("stars").source_id, SourceId::ATOUT_FRANCE);
    assert_eq!(provenance("position").source_id, SourceId::OSM);
    assert_eq!(
        provenance("name")
            .alternatives
            .iter()
            .map(|a| a.value.as_str())
            .collect::<Vec<_>>(),
        ["Camping Municipal du Port"],
        "the losing spelling stays visible"
    );

    let sources = places::sources_of(&pool, &[place]).await.unwrap();
    assert_eq!(sources.len(), 2);
    assert!(
        sources
            .iter()
            .all(|s| s.match_score.is_some_and(|m| m >= 0.85))
    );

    let pair = sqlx::query!(
        r#"SELECT decision, components FROM match_pairs WHERE decision = 'merge' LIMIT 1"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(
        pair.components.get("distance_m").is_some() && pair.components.get("name").is_some(),
        "the components of a decision are stored so it can be explained"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_motorhome_area_and_a_campsite_of_one_name_wait_for_a_person(pool: PgPool) {
    ingest_fixtures(&pool).await;
    run(&pool, at(2), None).await.unwrap();
    let stopover = place_of(&pool, &SourceId::OSM, "way/193703749").await;
    let campsite = place_of(
        &pool,
        &SourceId::ATOUT_FRANCE,
        "49080:bouchemaine:camping-de-bouchemaine",
    )
    .await;
    assert_ne!(stopover, campsite, "a review pair is not merged");
    let review: i64 = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM match_pairs WHERE decision = 'review'"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(review, 1, "it waits in the review queue");
}

#[sqlx::test(migrations = "../../migrations")]
async fn running_again_changes_nothing(pool: PgPool) {
    ingest_fixtures(&pool).await;
    run(&pool, at(2), None).await.unwrap();
    let before = snapshot(&pool).await;
    let again = run(&pool, at(2), None).await.unwrap();
    assert_eq!(again, RunStats::default(), "nothing flagged, nothing to do");
    assert_eq!(snapshot(&pool).await, before);

    // Re-importing the same payloads flags nothing either.
    ingest_fixtures(&pool).await;
    assert_eq!(run(&pool, at(2), None).await.unwrap(), RunStats::default());
    assert_eq!(snapshot(&pool).await, before);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_full_rebuild_lands_where_the_incremental_runs_did(pool: PgPool) {
    // Import the sources one after the other, conflating in between, then
    // rebuild everything: the same places, ids and digests come out.
    store_complete(&pool, &SourceId::OSM, Some("FR-PDL"), &osm_records())
        .await
        .unwrap();
    run(&pool, at(2), None).await.unwrap();
    store_complete(&pool, &SourceId::ATOUT_FRANCE, None, &atout_records())
        .await
        .unwrap();
    let second = run(&pool, at(2), None).await.unwrap();
    assert_eq!(
        second.updated, 6,
        "six OSM places gain an Atout France source"
    );
    let incremental = snapshot(&pool).await;

    records::mark_all_dirty(&pool).await.unwrap();
    let rebuild = run(&pool, at(2), None).await.unwrap();
    assert_eq!(
        (rebuild.created, rebuild.updated, rebuild.tombstoned),
        (0, 0, 0)
    );
    assert_eq!(rebuild.unchanged, 23);
    assert_eq!(snapshot(&pool).await, incremental);
}

fn campsite(name: &str, lat: f64, lon: f64) -> NormalizedRecord {
    let mut r = NormalizedRecord::new(PlaceKind::Campsite, Position::new(lat, lon).unwrap());
    r.name = Some(name.to_owned());
    r
}

fn fetched(id: &str, record: NormalizedRecord) -> FetchedRecord {
    FetchedRecord {
        external_id: id.to_owned(),
        external_url: None,
        record,
        raw: serde_json::json!({}),
        fetched_at: Utc.with_ymd_and_hms(2026, 10, 6, 0, 0, 0).unwrap(),
    }
}

/// One metre north, in degrees of latitude.
const M: f64 = 1.0 / 111_195.0;

#[sqlx::test(migrations = "../../migrations")]
async fn two_neighbouring_spots_stay_two_places(pool: PgPool) {
    // Two campsites 60 m apart, and the classification of one of them.
    let osm = [
        fetched("way/1", campsite("Camping Les Pins", 45.0, 4.0)),
        fetched("way/2", campsite("Camping La Mer", 45.0 + 60.0 * M, 4.0)),
    ];
    let af = [fetched(
        "x:pins",
        campsite("CAMPING LES PINS", 45.0 + 20.0 * M, 4.0),
    )];
    store_complete(&pool, &SourceId::OSM, None, &osm)
        .await
        .unwrap();
    store_complete(&pool, &SourceId::ATOUT_FRANCE, None, &af)
        .await
        .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let pins = place_of(&pool, &SourceId::OSM, "way/1").await;
    let mer = place_of(&pool, &SourceId::OSM, "way/2").await;
    assert_ne!(pins, mer);
    assert_eq!(
        place_of(&pool, &SourceId::ATOUT_FRANCE, "x:pins").await,
        pins
    );
    assert_eq!(places::sources_of(&pool, &[mer]).await.unwrap().len(), 1);
}

#[sqlx::test(migrations = "../../migrations")]
async fn two_records_of_one_source_are_never_merged(pool: PgPool) {
    let osm = [
        fetched("node/1", campsite("Camping du Gave", 43.3, -0.37)),
        fetched(
            "node/2",
            campsite("Camping du Gave", 43.3 + 10.0 * M, -0.37),
        ),
    ];
    store_complete(&pool, &SourceId::OSM, None, &osm)
        .await
        .unwrap();
    run(&pool, at(2), None).await.unwrap();
    assert_ne!(
        place_of(&pool, &SourceId::OSM, "node/1").await,
        place_of(&pool, &SourceId::OSM, "node/2").await
    );
    let reason: String = sqlx::query_scalar!("SELECT reason FROM match_pairs")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        reason, "same_source",
        "the duplicate waits in the review queue"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_cannot_link_splits_a_merge_and_every_later_import_respects_it(pool: PgPool) {
    ingest_fixtures(&pool).await;
    run(&pool, at(2), None).await.unwrap();
    let merged = place_of(&pool, &SourceId::OSM, PORT_OSM).await;
    let osm = record_id(&pool, &SourceId::OSM, PORT_OSM).await;
    let af = record_id(&pool, &SourceId::ATOUT_FRANCE, PORT_AF).await;

    records::set_constraint(
        &pool,
        osm,
        af,
        ConstraintKind::CannotLink,
        Some("two sites"),
    )
    .await
    .unwrap();
    let stats = run(&pool, at(2), None).await.unwrap();
    assert_eq!(
        (stats.updated, stats.created),
        (1, 1),
        "the place keeps one record, the other gets a new place"
    );
    let a = place_of(&pool, &SourceId::OSM, PORT_OSM).await;
    let b = place_of(&pool, &SourceId::ATOUT_FRANCE, PORT_AF).await;
    assert_ne!(a, b);
    assert!(
        a == merged || b == merged,
        "one of them keeps the merged place's id"
    );

    // A re-import and a full rebuild do not undo the human decision.
    ingest_fixtures(&pool).await;
    records::mark_all_dirty(&pool).await.unwrap();
    run(&pool, at(2), None).await.unwrap();
    assert_ne!(
        place_of(&pool, &SourceId::OSM, PORT_OSM).await,
        place_of(&pool, &SourceId::ATOUT_FRANCE, PORT_AF).await
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_must_link_merges_a_review_pair_and_leaves_a_redirect(pool: PgPool) {
    ingest_fixtures(&pool).await;
    run(&pool, at(2), None).await.unwrap();
    let stopover = record_id(&pool, &SourceId::OSM, "way/193703749").await;
    let campsite = record_id(
        &pool,
        &SourceId::ATOUT_FRANCE,
        "49080:bouchemaine:camping-de-bouchemaine",
    )
    .await;
    let old_af_place = place_of(
        &pool,
        &SourceId::ATOUT_FRANCE,
        "49080:bouchemaine:camping-de-bouchemaine",
    )
    .await;

    records::set_constraint(&pool, stopover, campsite, ConstraintKind::MustLink, None)
        .await
        .unwrap();
    let stats = run(&pool, at(2), None).await.unwrap();
    assert_eq!(stats.tombstoned, 1);
    let place = place_of(&pool, &SourceId::OSM, "way/193703749").await;
    assert_eq!(
        place_of(
            &pool,
            &SourceId::ATOUT_FRANCE,
            "49080:bouchemaine:camping-de-bouchemaine"
        )
        .await,
        place
    );
    let scores: Vec<Option<f64>> = places::sources_of(&pool, &[place])
        .await
        .unwrap()
        .iter()
        .map(|s| s.match_score)
        .collect();
    assert_eq!(scores, [Some(1.0), Some(1.0)], "a human link is certain");
    assert_eq!(
        places::by_id(&pool, old_af_place)
            .await
            .unwrap()
            .map(|p| p.id),
        Some(place),
        "the absorbed place redirects to the one that took it"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_changed_record_rewrites_only_its_place(pool: PgPool) {
    ingest_fixtures(&pool).await;
    run(&pool, at(2), None).await.unwrap();
    let before = snapshot(&pool).await;
    let place = place_of(&pool, &SourceId::OSM, PORT_OSM).await;

    let mut af = atout_records();
    af.iter_mut()
        .find(|r| r.external_id == PORT_AF)
        .unwrap()
        .record
        .capacity = Some(42);
    store_complete(&pool, &SourceId::ATOUT_FRANCE, None, &af)
        .await
        .unwrap();
    let stats = run(&pool, at(2), None).await.unwrap();
    assert_eq!((stats.dirty, stats.updated, stats.created), (1, 1, 0));
    assert_eq!(
        places::by_id(&pool, place).await.unwrap().unwrap().capacity,
        Some(42)
    );

    let after = snapshot(&pool).await;
    let seq = |snap: &[(Uuid, String, i64, Option<Uuid>)], id: Uuid| {
        snap.iter().find(|s| s.0 == id).map(|s| s.2).unwrap()
    };
    assert!(
        seq(&after, place) > seq(&before, place),
        "the place moves forward in the feed"
    );
    let others = |snap: &[(Uuid, String, i64, Option<Uuid>)]| {
        snap.iter()
            .filter(|s| s.0 != place)
            .cloned()
            .collect::<Vec<_>>()
    };
    assert_eq!(others(&after), others(&before), "no other place is touched");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_record_the_source_drops_leaves_its_place(pool: PgPool) {
    ingest_fixtures(&pool).await;
    run(&pool, at(2), None).await.unwrap();
    let merged = place_of(&pool, &SourceId::OSM, PORT_OSM).await;
    let alone = place_of(&pool, &SourceId::OSM, "way/347935372").await;
    let cursor = places::last_seq(&pool).await.unwrap();

    let osm: Vec<FetchedRecord> = osm_records()
        .into_iter()
        .filter(|r| r.external_id != PORT_OSM && r.external_id != "way/347935372")
        .collect();
    let report = store_complete(&pool, &SourceId::OSM, Some("FR-PDL"), &osm)
        .await
        .unwrap();
    assert_eq!(report.retired, 2);
    let stats = run(&pool, at(2), None).await.unwrap();
    assert_eq!((stats.updated, stats.tombstoned), (1, 1));

    let left = places::sources_of(&pool, &[merged]).await.unwrap();
    assert_eq!(
        left.len(),
        1,
        "the merged place keeps its Atout France record"
    );
    assert_eq!(left[0].source_id, SourceId::ATOUT_FRANCE);
    assert!(
        places::by_id(&pool, alone).await.unwrap().is_none(),
        "a place left without records is deleted"
    );
    let bbox = lunaway_domain::BBox::new(47.0, -3.0, 48.0, 0.0).unwrap();
    let (changes, _) = places::changes(&pool, bbox, cursor, 100, true)
        .await
        .unwrap();
    assert!(
        changes
            .iter()
            .any(|c| matches!(c, places::Change::Delete { id, .. } if *id == alone)),
        "the deletion reaches the change feed"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_truncated_fetch_does_not_retire_records(pool: PgPool) {
    ingest_fixtures(&pool).await;
    let few: Vec<FetchedRecord> = osm_records().into_iter().take(3).collect();
    let report = store_complete(&pool, &SourceId::OSM, Some("FR-PDL"), &few)
        .await
        .unwrap();
    assert!(report.retire_refused);
    assert_eq!(report.retired, 0);
    assert_eq!(
        records::live_count(&pool, &SourceId::OSM, Some("FR-PDL"))
            .await
            .unwrap(),
        19
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn opening_intervals_are_computed_and_refreshed_daily(pool: PgPool) {
    let mut r = campsite("Camping Horaires", 47.4, -0.6);
    r.opening_hours = Some("Mo-Fr 08:00-19:00".into());
    r.address.country_code = Some("FR".into());
    store_complete(&pool, &SourceId::OSM, None, &[fetched("node/9", r)])
        .await
        .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let place = place_of(&pool, &SourceId::OSM, "node/9").await;
    let row = places::by_id(&pool, place).await.unwrap().unwrap();
    assert!(row.opening_hours_parsed);
    let first = row.opening_intervals.unwrap();
    assert_eq!(first.len(), 10);
    assert_eq!(
        first[0].start,
        Utc.with_ymd_and_hms(2026, 11, 2, 7, 0, 0).unwrap()
    );

    let next = run(&pool, at(3), None).await.unwrap();
    assert_eq!(next.opening_refreshed, 1);
    let row2 = places::by_id(&pool, place).await.unwrap().unwrap();
    assert_eq!(
        row2.opening_intervals.unwrap()[0].start,
        Utc.with_ymd_and_hms(2026, 11, 3, 7, 0, 0).unwrap()
    );
    assert!(
        row2.updated_seq > row.updated_seq,
        "devices receive the new window"
    );
    assert_eq!(
        row2.opening_intervals_until,
        Some(Utc.with_ymd_and_hms(2026, 11, 16, 23, 0, 0).unwrap()),
        "fourteen days from local midnight on 3 November"
    );
    assert_eq!(
        run(&pool, at(3), None).await.unwrap().opening_refreshed,
        0,
        "once a day"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn intervals_computed_before_their_window_end_was_stored_get_it_the_same_day(pool: PgPool) {
    let mut r = campsite("Camping Horaires", 47.4, -0.6);
    // Hours, not a season (`24/7` is one, and has no window).
    r.opening_hours = Some("Mo-Su 08:00-20:00".into());
    r.address.country_code = Some("FR".into());
    store_complete(&pool, &SourceId::OSM, None, &[fetched("node/9", r)])
        .await
        .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let place = place_of(&pool, &SourceId::OSM, "node/9").await;
    // What a place written before the column existed looks like.
    sqlx::query!("UPDATE places SET opening_intervals_until = NULL")
        .execute(&pool)
        .await
        .unwrap();
    let before = places::by_id(&pool, place).await.unwrap().unwrap();
    let stats = run(&pool, at(2), None).await.unwrap();
    assert_eq!(stats.opening_refreshed, 1);
    let after = places::by_id(&pool, place).await.unwrap().unwrap();
    assert_eq!(
        after.opening_intervals_until,
        Some(Utc.with_ymd_and_hms(2026, 11, 15, 23, 0, 0).unwrap())
    );
    assert!(
        after.updated_seq > before.updated_seq,
        "devices that synced the intervals receive their window end"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_season_has_no_window_and_no_new_copy_at_midnight(pool: PgPool) {
    let mut r = campsite("Camping Saison", 47.4, -0.6);
    r.opening_hours = Some("Apr 01-Oct 31".into());
    r.address.country_code = Some("FR".into());
    store_complete(&pool, &SourceId::OSM, None, &[fetched("node/9", r)])
        .await
        .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let place = place_of(&pool, &SourceId::OSM, "node/9").await;
    let row = places::by_id(&pool, place).await.unwrap().unwrap();
    assert!(row.opening_hours_parsed);
    assert_eq!(
        row.opening_season.as_ref().map(|s| s.ranges().to_vec()),
        Some(vec![(92, 305)]),
        "1 April to 31 October"
    );
    assert_eq!(
        row.opening_intervals, None,
        "the season answers for every day"
    );
    assert_eq!(row.opening_intervals_until, None);

    let next = run(&pool, at(3), None).await.unwrap();
    assert_eq!(next.opening_refreshed, 0);
    let row2 = places::by_id(&pool, place).await.unwrap().unwrap();
    assert_eq!(
        row2.updated_seq, row.updated_seq,
        "devices do not download the place again at every local midnight"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_season_stored_with_a_window_by_the_release_before_loses_it_once(pool: PgPool) {
    let mut r = campsite("Camping Toute l'Annee", 47.4, -0.6);
    r.opening_hours = Some("Jan 01-Dec 31".into());
    r.address.country_code = Some("FR".into());
    store_complete(&pool, &SourceId::OSM, None, &[fetched("node/9", r)])
        .await
        .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let place = place_of(&pool, &SourceId::OSM, "node/9").await;
    // What the release before stored: two weeks of intervals, no season.
    sqlx::query(
        "UPDATE places SET opening_season = NULL,
             opening_intervals = '[{\"start\": \"2026-11-01T23:00:00Z\", \"end\": \"2026-11-15T23:00:00Z\"}]',
             opening_intervals_until = '2026-11-15T23:00:00Z', opening_window_start = '2026-11-02',
             opening_refresh_at = '2026-11-02T23:00:00Z'",
    )
    .execute(&pool)
    .await
    .unwrap();
    let before = places::by_id(&pool, place).await.unwrap().unwrap();
    assert!(before.opening_intervals.is_some());

    let stats = run(&pool, at(3), None).await.unwrap();
    assert_eq!(stats.opening_refreshed, 1);
    let after = places::by_id(&pool, place).await.unwrap().unwrap();
    assert!(after.opening_season.unwrap().is_all_year());
    assert_eq!(after.opening_intervals, None);
    assert!(
        after.updated_seq > before.updated_seq,
        "devices learn the season once"
    );
    assert_eq!(
        run(&pool, at(4), None).await.unwrap().opening_refreshed,
        0,
        "and nothing at the next midnight"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_season_a_release_before_seasons_left_behind_goes_with_its_window(pool: PgPool) {
    let mut r = campsite("Camping Horaires", 47.4, -0.6);
    r.opening_hours = Some("Mo-Fr 08:00-19:00".into());
    r.address.country_code = Some("FR".into());
    store_complete(&pool, &SourceId::OSM, None, &[fetched("node/9", r)])
        .await
        .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let place = place_of(&pool, &SourceId::OSM, "node/9").await;
    // A rollback's state: the release before rewrote the hours and their
    // window, and left the season the newer release had stored.
    sqlx::query("UPDATE places SET opening_season = '{92,305}', opening_refresh_at = now()")
        .execute(&pool)
        .await
        .unwrap();
    let before = places::by_id(&pool, place).await.unwrap().unwrap();
    assert!(before.opening_season.is_some());

    let stats = run(&pool, at(3), None).await.unwrap();
    assert_eq!(stats.opening_refreshed, 1);
    let after = places::by_id(&pool, place).await.unwrap().unwrap();
    assert_eq!(
        after.opening_season, None,
        "the hours are no season any more"
    );
    assert!(after.opening_intervals.is_some());
    assert!(
        after.updated_seq > before.updated_seq,
        "devices drop the season they had"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_campsite_mapped_twice_in_osm_waits_for_a_person(pool: PgPool) {
    // As the OSM adapter writes them: each record names its own element.
    let mut node = campsite("Camping du Gave", 43.3, -0.37);
    node.osm_ref = Some("node/1".into());
    let mut way = campsite("Camping du Gave", 43.3 + 40.0 * M, -0.37);
    way.osm_ref = Some("way/2".into());
    store_complete(
        &pool,
        &SourceId::OSM,
        None,
        &[fetched("node/1", node), fetched("way/2", way)],
    )
    .await
    .unwrap();
    let stats = run(&pool, at(2), None).await.unwrap();
    assert_eq!(
        stats.reviews, 1,
        "two different OSM elements of one spot are a duplicate to review, not two spots"
    );
    let reason: String = sqlx::query_scalar!("SELECT reason FROM match_pairs")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(reason, "same_source");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_shared_wikidata_item_merges_up_to_the_edge_of_the_reach(pool: PgPool) {
    // 500 m of uncertainty on each side: 1290 m apart is 290 m effective,
    // inside the 300 m reach, and the candidate search must find the pair.
    let mut a = NormalizedRecord::new(
        PlaceKind::MotorhomeArea,
        Position::new(48.85, 2.35).unwrap(),
    );
    a.name = Some("Aire des Bords de Seine".into());
    a.wikidata = Some("Q90".into());
    a.accuracy_m = 500.0;
    let mut b = a.clone();
    b.name = Some("Stationnement quai".into());
    b.position = Position::new(48.85 + 1_290.0 * M, 2.35).unwrap();
    // 1000 m apart with 500 m and 0 m of uncertainty: the database finds
    // the pair (its search reaches 300 + 500 + 500 m from the uncertain
    // record), the domain's reach stops at 300 m once 500 m are credited.
    let mut far = b.clone();
    far.wikidata = Some("Q91".into());
    far.accuracy_m = 500.0;
    far.position = Position::new(48.85, 2.36).unwrap();
    let mut far_twin = a.clone();
    far_twin.wikidata = Some("Q91".into());
    far_twin.accuracy_m = 0.0;
    far_twin.position = Position::new(48.85 + 1_000.0 * M, 2.36).unwrap();
    store_complete(
        &pool,
        &SourceId::OSM,
        None,
        &[fetched("way/1", a), fetched("way/3", far)],
    )
    .await
    .unwrap();
    store_complete(
        &pool,
        &SourceId::ATOUT_FRANCE,
        None,
        &[fetched("x:1", b), fetched("x:3", far_twin)],
    )
    .await
    .unwrap();
    run(&pool, at(2), None).await.unwrap();
    assert_eq!(
        place_of(&pool, &SourceId::OSM, "way/1").await,
        place_of(&pool, &SourceId::ATOUT_FRANCE, "x:1").await,
        "the edge of the domain's reach is inside the database's"
    );
    assert_ne!(
        place_of(&pool, &SourceId::OSM, "way/3").await,
        place_of(&pool, &SourceId::ATOUT_FRANCE, "x:3").await,
        "past the reach the shared item is ignored"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_pipeline_runs_with_the_import_role_alone(pool: PgPool) {
    let ingest = sqlx::postgres::PgPoolOptions::new()
        .max_connections(2)
        .after_connect(|conn, _| {
            Box::pin(async move {
                sqlx::query("SET ROLE lunaway_ingest").execute(conn).await?;
                Ok(())
            })
        })
        .connect_with((*pool.connect_options()).clone())
        .await
        .unwrap();
    ingest_fixtures(&ingest).await;
    let stats = run(&ingest, at(2), None).await.unwrap();
    assert_eq!(
        (stats.created, stats.merges),
        (23, 6),
        "the grants of lunaway_ingest cover the whole import and conflation"
    );
}

fn stored(i: u32, source: &SourceId) -> lunaway_db::conflation::StoredRecord {
    let lat = 43.0 + f64::from(i) * 0.001;
    lunaway_db::conflation::StoredRecord {
        id: Uuid::now_v7(),
        source_id: source.clone(),
        external_id: format!("r/{i}"),
        external_url: None,
        fetched_at: Utc.with_ymd_and_hms(2026, 10, 6, 0, 0, 0).unwrap(),
        deleted: false,
        record: campsite(&format!("Camping {i}"), lat, 1.0),
    }
}

#[test]
fn planning_a_country_where_half_the_places_vanish_stays_fast() {
    // 20 000 records, each in its own place, now merged two by two: 10 000
    // places vanish and each needs its heir. Searching the heirs place by
    // place over every record was quadratic: 18 s here in a debug build,
    // against under 1 s with one pass.
    use lunaway_conflate::{PlanInput, plan};
    use lunaway_db::conflation::PlaceState;
    use lunaway_domain::conflation::MergeEdge;
    let n = 20_000;
    let records: Vec<_> = (0..n)
        .map(|i| {
            stored(
                i,
                if i % 2 == 0 {
                    &SourceId::OSM
                } else {
                    &SourceId::ATOUT_FRANCE
                },
            )
        })
        .collect();
    let edges: Vec<MergeEdge<Uuid>> = records
        .chunks(2)
        .map(|p| MergeEdge {
            a: p[0].id,
            b: p[1].id,
            score: 0.9,
            distance_m: 10.0,
            name: 1.0,
        })
        .collect();
    let current: std::collections::BTreeMap<Uuid, Uuid> =
        records.iter().map(|r| (r.id, Uuid::now_v7())).collect();
    let states = current
        .values()
        .map(|p| {
            (
                *p,
                PlaceState {
                    id: *p,
                    content_hash: String::new(),
                    deleted: false,
                    position: None,
                },
            )
        })
        .collect();
    let input = PlanInput {
        records,
        edges,
        constraints: Vec::new(),
        current,
        states,
        now: at(2),
        exclusion: None,
        released: std::collections::BTreeSet::new(),
    };
    let started = std::time::Instant::now();
    let out = plan(&input).unwrap();
    let took = started.elapsed();
    assert_eq!(out.tombstones.len(), 10_000);
    assert!(
        out.tombstones.iter().all(|(_, heir)| heir.is_some()),
        "every vanished place points to the place that took its record"
    );
    assert!(
        took < std::time::Duration::from_secs(8),
        "planning must stay near linear: {took:?}"
    );
}

#[test]
fn a_record_placed_only_at_its_town_makes_no_place_of_its_own() {
    use lunaway_conflate::{PlanInput, plan};
    use lunaway_db::conflation::PlaceState;
    use lunaway_domain::conflation::MergeEdge;
    let mut town = stored(1, &SourceId::ATOUT_FRANCE);
    town.record.position_approximate = true;
    let alone = stored(2, &SourceId::OSM);
    let mut merged_town = stored(3, &SourceId::ATOUT_FRANCE);
    merged_town.record.position_approximate = true;
    let merged_osm = stored(4, &SourceId::OSM);
    let merged_osm_position = merged_osm.record.position;
    let edges = vec![MergeEdge {
        a: merged_town.id,
        b: merged_osm.id,
        score: 0.9,
        distance_m: 10.0,
        name: 1.0,
    }];
    // The town-placed record had a place of its own before the rule.
    let old = Uuid::now_v7();
    let current = std::collections::BTreeMap::from([(town.id, old)]);
    let states = std::collections::BTreeMap::from([(
        old,
        PlaceState {
            id: old,
            content_hash: String::new(),
            deleted: false,
            position: None,
        },
    )]);
    let input = PlanInput {
        records: vec![town.clone(), alone, merged_town.clone(), merged_osm],
        edges,
        constraints: Vec::new(),
        current,
        states,
        now: at(2),
        exclusion: None,
        released: std::collections::BTreeSet::new(),
    };
    let out = plan(&input).unwrap();
    assert_eq!(out.held_back, 1, "the town-placed record alone");
    assert_eq!(out.writes.len(), 2, "the OSM place, and the merged pair");
    let merged = out
        .writes
        .iter()
        .find(|w| {
            out.links
                .iter()
                .any(|(r, p, _)| *r == merged_town.id && *p == w.id)
        })
        .unwrap();
    assert_eq!(
        merged.content.position, merged_osm_position,
        "a merged pair takes OSM's position"
    );
    assert!(
        !out.links.iter().any(|(r, _, _)| *r == town.id),
        "the held record is linked to no place"
    );
    assert!(out.relink_records.contains(&town.id), "its old link goes");
    assert_eq!(
        out.tombstones,
        vec![(old, None)],
        "the place it had becomes a tombstone"
    );
    assert!(out.links.iter().any(|(r, _, _)| *r == merged_town.id));
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_scoring_leaves_the_async_runtime_free(pool: PgPool) {
    // 1500 campsites 5 m apart: some 240 000 pairs within reach, seconds of
    // scoring in a debug build. On the async thread that would freeze every
    // other task of the runtime (here, a 10 ms ticker) for as long.
    let records: Vec<FetchedRecord> = (0..1500u32)
        .map(|i| {
            fetched(
                &format!("way/{i}"),
                campsite(&format!("Camping {i}"), 45.0 + f64::from(i) * 5.0 * M, 4.0),
            )
        })
        .collect();
    store_complete(&pool, &SourceId::OSM, None, &records)
        .await
        .unwrap();
    let done = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let flag = done.clone();
    let ticker = tokio::spawn(async move {
        let mut worst = std::time::Duration::ZERO;
        let mut last = std::time::Instant::now();
        while !flag.load(std::sync::atomic::Ordering::Relaxed) {
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
            worst = worst.max(last.elapsed());
            last = std::time::Instant::now();
        }
        worst
    });
    let started = std::time::Instant::now();
    let stats = run(&pool, at(2), None).await.unwrap();
    let took = started.elapsed();
    done.store(true, std::sync::atomic::Ordering::Relaxed);
    let worst = ticker.await.unwrap();
    assert!(stats.scored > 100_000);
    // Measured in a debug build: 5 % of the run with the scoring on a
    // blocking thread, 19 % with it on the async thread.
    assert!(
        worst < took / 8,
        "a ticker beside the conflation stalled {worst:?} out of {took:?}"
    );
}

/// A pool whose connections act as `role`.
async fn as_role(pool: &PgPool, role: &'static str) -> PgPool {
    sqlx::postgres::PgPoolOptions::new()
        .max_connections(2)
        .after_connect(move |conn, _| {
            Box::pin(async move {
                sqlx::query(role).execute(conn).await?;
                Ok(())
            })
        })
        .connect_with((*pool.connect_options()).clone())
        .await
        .unwrap()
}

async fn place_named(pool: &PgPool, name: &str) -> Uuid {
    sqlx::query_scalar!(
        "SELECT id FROM places WHERE deleted_at IS NULL AND name = $1",
        name
    )
    .fetch_one(pool)
    .await
    .unwrap()
}

async fn account(app: &PgPool, n: u8) -> Uuid {
    let (a, _) = lunaway_db::accounts::create_with_key(
        app,
        lunaway_db::accounts::NewAccount {
            pseudonym: "Loutre du Morvan",
            thumbprint: &format!("{n:0>43}"),
            public_key: &[4; 65],
            session_hash: &[n; 32],
            session_ttl_secs: 3_600.0,
        },
    )
    .await
    .unwrap();
    a.id
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_worker_applies_the_community_s_work_with_the_import_role_alone(pool: PgPool) {
    use lunaway_db::submissions::{self, NewSubmission, Submitted};
    use lunaway_domain::community::submission::{NewPlace, PlacePatch};
    ingest_fixtures(&pool).await;
    run(&pool, at(2), None).await.unwrap();
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let author = account(&app, 1).await;
    let device: Uuid = sqlx::query_scalar!("SELECT id FROM device_keys")
        .fetch_one(&pool)
        .await
        .unwrap();
    let port = place_named(&pool, "Camping municipal du Port").await;
    lunaway_db::community::rate(&app, author, port, 4)
        .await
        .unwrap();
    let new = NewPlace {
        kind: PlaceKind::Nature,
        position: Position::new(47.1, -1.0).unwrap(),
        details: PlacePatch {
            name: Some("Clairière des Mauges".into()),
            ..PlacePatch::default()
        },
    };
    let patch = PlacePatch {
        max_height_m: Some(3.5),
        ..PlacePatch::default()
    };
    for what in [
        Submitted::Create(&new),
        Submitted::Edit {
            place: port,
            patch: &patch,
        },
    ] {
        submissions::submit(
            &app,
            NewSubmission {
                account: author,
                device_key: device,
                what,
                accepted: true,
                held_for: None,
            },
        )
        .await
        .unwrap();
    }
    let stats = run(&ingest, at(2), None).await.unwrap();
    assert_eq!(
        (stats.submissions_applied, stats.created),
        (2, 1),
        "the import role writes community records and their places"
    );
    let port_row = places::by_id(&pool, port).await.unwrap().unwrap();
    assert_eq!(port_row.community.rating_count, 1);
    assert_eq!(port_row.community.rating_avg, Some(4.0));
    assert_eq!(
        port_row.filter_rating,
        Some(4.0),
        "a user's rating rates the place for the filters with its summary, not a period later"
    );
    assert_eq!(
        port_row.max_height_m,
        Some(3.5),
        "the edit gives a height where OpenStreetMap had none"
    );
    let second = run(&ingest, at(2), None).await.unwrap();
    assert_eq!(
        (
            second.submissions_applied,
            second.community_refreshed,
            second.dirty
        ),
        (0, 0, 0),
        "a run with nothing new writes nothing"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn contributions_follow_a_place_merged_into_another(pool: PgPool) {
    ingest_fixtures(&pool).await;
    run(&pool, at(2), None).await.unwrap();
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let a = place_named(&pool, "Aire Val-du-Layon").await;
    let b = place_named(&pool, "Nature Camp Anjou").await;
    let (rater_a, rater_b) = (account(&app, 1).await, account(&app, 2).await);
    lunaway_db::community::rate(&app, rater_a, a, 2)
        .await
        .unwrap();
    lunaway_db::community::rate(&app, rater_b, b, 4)
        .await
        .unwrap();
    run(&pool, at(2), None).await.unwrap();
    // A person states the two are one spot: one place absorbs the other.
    let rec = |place: Uuid| {
        let pool = pool.clone();
        async move {
            sqlx::query_scalar!(
                "SELECT record_id FROM place_sources WHERE place_id = $1 LIMIT 1",
                place
            )
            .fetch_one(&pool)
            .await
            .unwrap()
        }
    };
    records::set_constraint(
        &pool,
        rec(a).await,
        rec(b).await,
        ConstraintKind::MustLink,
        None,
    )
    .await
    .unwrap();
    let stats = run(&pool, at(2), None).await.unwrap();
    assert_eq!(stats.tombstoned, 1);
    let heir = places::by_id(&pool, a).await.unwrap().unwrap();
    assert_eq!(heir.id, places::by_id(&pool, b).await.unwrap().unwrap().id);
    assert_eq!(
        heir.community.rating_count, 2,
        "the absorbed place's ratings count for the place that absorbed it, an account once"
    );
    // The account that rated the absorbed place rates the place it now
    // sees: its rating moves, it is not counted twice.
    let absorbed_rater = if heir.id == a { rater_b } else { rater_a };
    lunaway_db::community::rate(&app, absorbed_rater, heir.id, 5)
        .await
        .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let heir = places::by_id(&pool, heir.id).await.unwrap().unwrap();
    assert_eq!(heir.community.rating_count, 2);
    let expected = if heir.id == a {
        (2.0 + 5.0) / 2.0
    } else {
        (4.0 + 5.0) / 2.0
    };
    assert_eq!(heir.community.rating_avg, Some(expected));
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_community_place_is_verified_once_an_open_source_lists_it(pool: PgPool) {
    use lunaway_db::submissions::{self, NewSubmission, Submitted};
    use lunaway_domain::community::submission::{NewPlace, PlacePatch};
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let author = account(&app, 1).await;
    let device: Uuid = sqlx::query_scalar!("SELECT id FROM device_keys")
        .fetch_one(&pool)
        .await
        .unwrap();
    let new = NewPlace {
        kind: PlaceKind::Campsite,
        position: Position::new(46.5, 2.5).unwrap(),
        details: PlacePatch {
            name: Some("Camping des Bruyères".into()),
            ..PlacePatch::default()
        },
    };
    let sent = submissions::submit(
        &app,
        NewSubmission {
            account: author,
            device_key: device,
            what: Submitted::Create(&new),
            accepted: true,
            held_for: None,
        },
    )
    .await
    .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let place = submissions::submission(&pool, sent.id)
        .await
        .unwrap()
        .unwrap()
        .place_id
        .unwrap();
    let row = places::by_id(&pool, place).await.unwrap().unwrap();
    assert_eq!(
        row.community.verification,
        lunaway_domain::community::Verification::ToVerify
    );
    // OpenStreetMap maps the same campsite: it joins the place.
    let raw = serde_json::json!({});
    records::upsert(
        &pool,
        &SourceId::OSM,
        &[records::NewRecord {
            external_id: "way/77",
            external_url: Some("https://www.openstreetmap.org/way/77"),
            record: &campsite("Camping des Bruyères", 46.5, 2.5),
            raw: &raw,
            fetched_at: Utc::now(),
            scope: Some("test"),
        }],
    )
    .await
    .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let row = places::by_id(&pool, place).await.unwrap().unwrap();
    assert_eq!(row.id, place);
    assert_eq!(
        row.community.verification,
        lunaway_domain::community::Verification::Verified,
        "a place an open source lists needs no confirmation"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_place_without_an_address_takes_the_country_of_its_position(pool: PgPool) {
    // What a community submission gives: no address at all.
    let raw = serde_json::json!({});
    let record = campsite("Aire du lac", 45.9, 6.13);
    assert_eq!(record.address.country_code, None);
    records::upsert(
        &pool,
        &SourceId::COMMUNITY,
        &[records::NewRecord {
            external_id: "submission/1",
            external_url: None,
            record: &record,
            raw: &raw,
            fetched_at: Utc::now(),
            scope: None,
        }],
    )
    .await
    .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let (country, region): (Option<String>, Option<String>) =
        sqlx::query_as("SELECT country_code, region FROM places")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        (country.as_deref(), region.as_deref()),
        (Some("FR"), Some("FR")),
        "a place only the community describes gets a time zone and a sync region"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_issue_leaves_the_card_once_its_window_has_passed(pool: PgPool) {
    ingest_fixtures(&pool).await;
    run(&pool, at(2), None).await.unwrap();
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let reporter = account(&app, 1).await;
    lunaway_db::accounts::set_granted_level(&app, reporter, 1)
        .await
        .unwrap();
    let port = place_named(&pool, "Camping municipal du Port").await;
    lunaway_db::community::report_issue(
        &app,
        reporter,
        port,
        lunaway_domain::community::IssueKind::NightBan,
        None,
    )
    .await
    .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let row = places::by_id(&pool, port).await.unwrap().unwrap();
    assert_eq!(row.community.reported_issues.len(), 1);
    // A month passes: the report and the date the card shows grow old.
    sqlx::query!("UPDATE issue_reports SET created_at = now() - interval '31 days'")
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query!(
        r#"
        UPDATE places SET reported_issues = (
            SELECT jsonb_agg(jsonb_set(e, '{lastReportedAt}', to_jsonb(now() - interval '31 days')))
            FROM jsonb_array_elements(reported_issues) e)
        WHERE id = $1
        "#,
        port
    )
    .execute(&pool)
    .await
    .unwrap();
    let stats = run(&pool, at(2), None).await.unwrap();
    assert_eq!(stats.community_refreshed, 1);
    let row = places::by_id(&pool, port).await.unwrap().unwrap();
    assert!(
        row.community.reported_issues.is_empty(),
        "nothing happened at the place, the report still expires"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_watching_worker_wakes_on_the_api_s_signal(pool: PgPool) {
    use lunaway_db::submissions::{self, NewSubmission, Submitted};
    use lunaway_domain::community::submission::{NewPlace, PlacePatch};
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let worker = tokio::spawn(async move {
        lunaway_conflate::watch(
            &ingest,
            std::time::Duration::from_secs(600),
            std::time::Duration::ZERO,
            std::time::Duration::ZERO,
            || at(2),
            None,
        )
        .await
    });
    // Let the worker run once and start listening.
    tokio::time::sleep(std::time::Duration::from_millis(500)).await;
    let author = account(&app, 1).await;
    let device: Uuid = sqlx::query_scalar!("SELECT id FROM device_keys")
        .fetch_one(&pool)
        .await
        .unwrap();
    let new = NewPlace {
        kind: PlaceKind::Parking,
        position: Position::new(47.2, -0.5).unwrap(),
        details: PlacePatch {
            name: Some("Parking des Tilleuls".into()),
            ..PlacePatch::default()
        },
    };
    let sent = submissions::submit(
        &app,
        NewSubmission {
            account: author,
            device_key: device,
            what: Submitted::Create(&new),
            accepted: true,
            held_for: None,
        },
    )
    .await
    .unwrap();
    let version_before = lunaway_db::place_tiles::layer_version(&pool)
        .await
        .unwrap()
        .version;
    let mut applied = false;
    for _ in 0..50 {
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        let s = submissions::submission(&pool, sent.id)
            .await
            .unwrap()
            .unwrap();
        if s.status == "applied" && s.place_id.is_some() {
            applied = true;
            break;
        }
    }
    let mut published = false;
    for _ in 0..50 {
        let v = lunaway_db::place_tiles::layer_version(&pool).await.unwrap();
        if v.version > version_before {
            published = true;
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    }
    worker.abort();
    assert!(
        applied,
        "a submission is applied within seconds of the API's NOTIFY, not at the next period"
    );
    assert!(
        published,
        "the worker publishes the new place in the places' tiles after its run"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_watching_worker_rates_the_places_before_it_publishes_them(pool: PgPool) {
    // A place the partner rated, as an import leaves it: the import writes
    // the rating, never the place.
    let place = Uuid::now_v7();
    let record = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO places (id, kind, geom, overnight, content_hash) \
         VALUES ($1, 'parking', ST_SetSRID(ST_MakePoint(-0.5, 47.2), 4326)::geography, \
                 'allowed', 'x')",
    )
    .bind(place)
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO source_records (id, source_id, external_id, kind, geom, data, raw, \
                                     fetched_at, needs_conflation) \
         VALUES ($1, 'extcom', 'spot-1', 'parking', \
                 ST_SetSRID(ST_MakePoint(-0.5, 47.2), 4326)::geography, '{}', '{}', now(), \
                 false)",
    )
    .bind(record)
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query("INSERT INTO place_sources (record_id, place_id) VALUES ($1, $2)")
        .bind(record)
        .bind(place)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO external_ratings (record_id, source_id, average, count, licence, \
                                       fetched_at) \
         VALUES ($1, 'extcom', 4.46, 12, 'TEST-AGREEMENT', now())",
    )
    .bind(record)
    .execute(&pool)
    .await
    .unwrap();
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let worker = tokio::spawn(async move {
        lunaway_conflate::watch(
            &ingest,
            std::time::Duration::from_secs(600),
            std::time::Duration::ZERO,
            std::time::Duration::ZERO,
            || at(2),
            None,
        )
        .await
    });
    let mut seen = None;
    for _ in 0..50 {
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        let (rating, seq): (Option<f64>, i64) =
            sqlx::query_as("SELECT filter_rating, updated_seq FROM places WHERE id = $1")
                .bind(place)
                .fetch_one(&pool)
                .await
                .unwrap();
        let layer = lunaway_db::place_tiles::layer_version(&pool).await.unwrap();
        if rating.is_some() && layer.published_seq >= seq {
            seen = Some(rating);
            break;
        }
    }
    worker.abort();
    assert_eq!(
        seen,
        Some(Some(4.5)),
        "the worker writes the partner's 4.46 as 4.5, and the tiles it publishes next carry it"
    );
}

const POIS: &[u8] = include_bytes!("../../lunaway-ingest/tests/fixtures/osm_poi_sample.json");
const FUEL: &[u8] = include_bytes!("../../lunaway-ingest/tests/fixtures/fuel_export_sample.json");

#[sqlx::test(migrations = "../../migrations")]
async fn the_points_layer_runs_under_its_roles(pool: PgPool) {
    use lunaway_db::{
        pois,
        submissions::{self, NewSubmission, Submitted},
    };
    use lunaway_domain::poi::{NewVendingMachine, PoiKind};
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;

    // The importers, with the import role alone.
    let fetched = Utc.with_ymd_and_hms(2026, 10, 5, 22, 0, 0).unwrap();
    let points = lunaway_ingest::poi_osm::parse(POIS, fetched)
        .unwrap()
        .points;
    lunaway_ingest::store::store_pois(&ingest, &SourceId::OSM, &points)
        .await
        .unwrap();
    let stations = lunaway_ingest::fuel::parse(FUEL).unwrap();
    let data: Vec<serde_json::Value> = stations
        .stations
        .iter()
        .map(|s| serde_json::to_value(&s.station).unwrap())
        .collect();
    let rows: Vec<pois::NewJoin<'_>> = stations
        .stations
        .iter()
        .zip(&data)
        .map(|(s, d)| pois::NewJoin {
            key: &s.key,
            data: d,
            raw: &s.raw,
            fetched_at: fetched,
        })
        .collect();
    lunaway_ingest::store::store_joins(&ingest, &SourceId::FUEL_PRICES, &rows)
        .await
        .unwrap();

    // The community, with the API's role: a vending machine and three
    // "gone" answers about a point.
    let author = account(&app, 1).await;
    lunaway_db::accounts::set_granted_level(&pool, author, 1)
        .await
        .unwrap();
    let device: Uuid = sqlx::query_scalar!("SELECT id FROM device_keys")
        .fetch_one(&pool)
        .await
        .unwrap();
    let machine = NewVendingMachine {
        kind: PoiKind::VendingPizza,
        position: Position::new(46.0, 5.0).unwrap(),
        name: None,
        operator: None,
        brand: None,
        products: Vec::new(),
        payment: Vec::new(),
        always_open: true,
    };
    submissions::submit(
        &app,
        NewSubmission {
            account: author,
            device_key: device,
            what: Submitted::Poi(&machine),
            accepted: true,
            held_for: None,
        },
    )
    .await
    .unwrap();
    let poi = sqlx::query_scalar!("SELECT id FROM pois WHERE external_id = 'node/812029833'")
        .fetch_one(&pool)
        .await
        .unwrap();
    for n in 2..=4 {
        let a = account(&app, n).await;
        sqlx::query!("UPDATE accounts SET trust_level = 1 WHERE id = $1", a)
            .execute(&pool)
            .await
            .unwrap();
        pois::confirm(&app, a, poi, false).await.unwrap();
    }

    // The worker, with the import role alone.
    let stats = run(&ingest, at(2), None).await.unwrap();
    assert_eq!(stats.poi_community.vending_added, 1);
    assert!(
        stats.poi_hours.evaluated > 0,
        "the points' hours, under the import role"
    );
    assert!(
        !pois::is_live(&app, poi).await.unwrap(),
        "hidden by the worker"
    );
    let checks = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM moderation_queue WHERE kind = 'poi_check'"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(checks, 1, "the import role opens the check it must");

    // A moderator (the API's role) shows it again; the API reads it all.
    assert!(
        lunaway_db::moderation::hide_poi(&app, poi, false, None)
            .await
            .unwrap()
    );
    run(&ingest, at(2), None).await.unwrap();
    let back = pois::by_id(&app, poi).await.unwrap().unwrap();
    assert_eq!(back.record.refs.laposte.as_deref(), Some("00001A"));
    let around = pois::nearby(
        &app,
        Position::new(45.96, 5.36).unwrap(),
        &[lunaway_domain::poi::PoiCategory::Health],
        &[5_000.0],
        None,
        3,
    )
    .await
    .unwrap();
    assert!(!around.is_empty());
    let tile = pois::tile(
        &app,
        13,
        4217,
        2915,
        4_000,
        lunaway_domain::poi::PoiTileSet::Base,
    )
    .await
    .unwrap();
    assert!(!tile.is_empty(), "the API builds tiles with its own role");
    let stats = lunaway_db::poi_search::statistics(&app).await.unwrap();
    let found = lunaway_db::poi_search::search(
        &app,
        lunaway_db::poi_search::PoiAsk {
            text: "amberieu",
            near: None,
            first: 5,
            kinds: None,
        },
        &stats,
    )
    .await
    .unwrap();
    assert!(
        !found.rows.is_empty(),
        "the API searches the points with its own role"
    );
}

/// Each of `records` is emptied, retired, unlinked and taken down, and the
/// conflation can still read what is left of it.
async fn assert_emptied(pool: &PgPool, records: &[Uuid]) {
    for r in records {
        let row = sqlx::query!(
            r#"
            SELECT name, raw::text AS "raw!", data, deleted_at IS NOT NULL AS "deleted!",
                   taken_down_at IS NOT NULL AS "taken!",
                   EXISTS (SELECT 1 FROM place_sources WHERE record_id = $1) AS "linked!"
            FROM source_records WHERE id = $1
            "#,
            r
        )
        .fetch_one(pool)
        .await
        .unwrap();
        assert_eq!(
            (
                row.name,
                row.raw.as_str(),
                row.deleted,
                row.taken,
                row.linked
            ),
            (None, "{}", true, true, false),
            "a record of the place is emptied, retired and unlinked"
        );
        let record: NormalizedRecord = serde_json::from_value(row.data).unwrap();
        assert_eq!(record.position, Position::new(0.0, 0.0).unwrap());
    }
}

/// A place taken down (a private home, a legal request) keeps nothing of
/// its content in the database, leaves every device through the change
/// feed, and stays gone: the next import finds its records, the one its
/// source had retired included, and leaves them empty, and a full
/// conflation makes no place of them. The API's role cannot start it.
#[sqlx::test(migrations = "../../migrations")]
async fn a_place_taken_down_is_emptied_and_no_import_brings_it_back(pool: PgPool) {
    use lunaway_db::{
        conflation::begin_writer,
        submissions::{self, NewSubmission, Submitted},
        takedowns::{self, Purge},
    };
    use lunaway_domain::{
        BBox,
        community::{ConfirmationStatus, IssueKind, submission::PlacePatch},
    };
    ingest_fixtures(&pool).await;
    run(&pool, at(2), None).await.unwrap();
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let names = ["Aire Val-du-Layon", "Nature Camp Anjou"];
    let (a, b) = (
        place_named(&pool, names[0]).await,
        place_named(&pool, names[1]).await,
    );
    let first_record = |place: Uuid| {
        let pool = pool.clone();
        async move {
            sqlx::query_scalar!(
                "SELECT record_id FROM place_sources WHERE place_id = $1 ORDER BY record_id LIMIT 1",
                place
            )
            .fetch_one(&pool)
            .await
            .unwrap()
        }
    };
    let (record_a, record_b) = (first_record(a).await, first_record(b).await);
    records::set_constraint(&pool, record_a, record_b, ConstraintKind::MustLink, None)
        .await
        .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let heir = places::by_id(&pool, a).await.unwrap().unwrap().id;
    let absorbed = if heir == a { b } else { a };

    // The source drops the absorbed place's element before the request:
    // the conflation unlinks its record, which keeps its name and position.
    let dropped = if absorbed == a { record_a } else { record_b };
    let source: String = sqlx::query_scalar!(
        "SELECT source_id FROM source_records WHERE id = $1",
        dropped
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    let dropped_external: String = sqlx::query_scalar!(
        "SELECT external_id FROM source_records WHERE id = $1",
        dropped
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    let (fixtures, scope, source) = if source == "osm" {
        (osm_records(), Some("FR-PDL"), SourceId::OSM)
    } else {
        (atout_records(), None, SourceId::ATOUT_FRANCE)
    };
    let without: Vec<FetchedRecord> = fixtures
        .into_iter()
        .filter(|r| r.external_id != dropped_external)
        .collect();
    store_complete(&pool, &source, scope, &without)
        .await
        .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let still_linked: i64 = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM place_sources WHERE record_id = $1"#,
        dropped
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(still_linked, 0, "the retired record left its place");

    // The community's content, and an edit applied and one waiting.
    let author = account(&app, 1).await;
    let device: Uuid = sqlx::query_scalar!("SELECT id FROM device_keys")
        .fetch_one(&pool)
        .await
        .unwrap();
    let review = lunaway_db::community::rate(&app, author, heir, 4)
        .await
        .unwrap()
        .id;
    lunaway_db::community::confirm(&app, author, heir, ConfirmationStatus::StillOk, None)
        .await
        .unwrap();
    lunaway_db::community::report_issue(&app, author, heir, IssueKind::Danger, None)
        .await
        .unwrap();
    let file = |c: char| format!("photos/ab/cd/{}.webp", c.to_string().repeat(64));
    let photo = Uuid::now_v7();
    sqlx::query!(
        r#"
        INSERT INTO photos (id, place_id, account_id, status, path, thumb_path, width, height,
                            thumb_width, thumb_height, thumbhash)
        VALUES ($1, $2, $3, 'published', $4, $5, 2048, 1536, 512, 384, '\x01')
        "#,
        photo,
        heir,
        author,
        file('a'),
        file('b'),
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query!(
        r#"
        INSERT INTO content_reports (id, target_type, target_id, reporter_id, reason)
        VALUES ($1, 'review', $2, $3, 'privacy')
        "#,
        Uuid::now_v7(),
        review,
        author
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query!(
        r#"
        INSERT INTO moderation_queue (id, kind, target_type, target_id, reason)
        VALUES ($1, 'reported_content', 'review', $2, 'privacy')
        "#,
        Uuid::now_v7(),
        review
    )
    .execute(&pool)
    .await
    .unwrap();
    for accepted in [true, false] {
        let patch = PlacePatch {
            name: Some("Chez les Martin".into()),
            ..PlacePatch::default()
        };
        submissions::submit(
            &app,
            NewSubmission {
                account: author,
                device_key: device,
                what: Submitted::Edit {
                    place: heir,
                    patch: &patch,
                },
                accepted,
                held_for: (!accepted).then_some("first edit"),
            },
        )
        .await
        .unwrap();
        run(&pool, at(2), None).await.unwrap();
    }
    let live_before = live_places(&pool).await;
    let cursor = places::last_seq(&pool).await.unwrap();
    let described_by: Vec<Uuid> = sqlx::query_scalar!(
        "SELECT record_id FROM place_sources WHERE place_id = $1",
        heir
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    let community: i64 = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM source_records WHERE id = ANY($1) AND source_id = 'community'"#,
        &described_by
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(
        described_by.len() >= 2 && community == 1,
        "the record left of the two merged places and the edit's community record describe \
         the heir: {described_by:?}"
    );

    let preview = takedowns::preview(&ingest, absorbed)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        (
            preview.place,
            preview.live,
            preview.taken_down,
            preview.merged
        ),
        (heir, true, false, 1)
    );
    assert_eq!(
        preview.records,
        i64::try_from(described_by.len() + 1).unwrap(),
        "the linked records and the one retired from the place"
    );
    assert!(preview.nearby.is_empty() && preview.unconflated == 0);
    assert_eq!(
        (
            preview.reviews,
            preview.photos,
            preview.confirmations,
            preview.issue_reports
        ),
        (1, 1, 1, 1)
    );
    assert_eq!(preview.submissions, 2);
    // A record unlinked before `last_place_id` existed names no place: the
    // takedown finds it by its position, near the place.
    let hint = |last: Option<Uuid>| {
        let pool = pool.clone();
        async move {
            sqlx::query!(
                "UPDATE source_records SET last_place_id = $2 WHERE id = $1",
                dropped,
                last
            )
            .execute(&pool)
            .await
            .unwrap();
        }
    };
    hint(None).await;
    let older = takedowns::preview(&ingest, absorbed)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(older.records, preview.records - 1);
    assert_eq!(
        older.nearby.iter().map(|n| n.id).collect::<Vec<_>>(),
        [dropped],
        "an older retired record of the place is listed by its position, for the moderator"
    );
    hint(Some(heir)).await;

    // Another spot's record, retired before Lunaway kept the place a record
    // leaves, 30 m away: listed, and emptied only on request. While it
    // waits for the conflation, the takedown waits too.
    let spot = sqlx::query!(
        r#"SELECT ST_Y(geom::geometry) AS "lat!", ST_X(geom::geometry) AS "lon!" FROM places WHERE id = $1"#,
        heir
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    let mut neighbour = NormalizedRecord::new(
        PlaceKind::Parking,
        Position::new(spot.lat + 0.000_27, spot.lon).unwrap(),
    );
    neighbour.name = Some("Parking de la mairie".into());
    let raw = serde_json::json!({});
    records::upsert(
        &pool,
        &SourceId::OSM,
        &[records::NewRecord {
            external_id: "node/4242",
            external_url: None,
            record: &neighbour,
            raw: &raw,
            fetched_at: at(2),
            scope: Some("FR-PDL"),
        }],
    )
    .await
    .unwrap();
    let mut tx = begin_writer(&ingest).await.unwrap();
    assert_eq!(
        takedowns::take_down(&mut tx, heir, TakedownCode::CourtOrder, false, &test_key())
            .await
            .unwrap(),
        takedowns::TakeDown::Unconflated(1),
        "a record not read yet by the conflation could become the place again"
    );
    drop(tx);
    sqlx::query!(
        "UPDATE source_records SET deleted_at = now(), needs_conflation = false \
         WHERE external_id = 'node/4242'"
    )
    .execute(&pool)
    .await
    .unwrap();
    let listed = takedowns::preview(&ingest, absorbed)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        listed
            .nearby
            .iter()
            .map(|n| n.external_id.as_str())
            .collect::<Vec<_>>(),
        ["node/4242"]
    );

    // The API's role starts nothing.
    assert_eq!(
        takedowns::purge_community(&app, heir).await.unwrap(),
        Purge::NotTakenDown,
        "the community's step waits for the catalogue's"
    );
    let mut as_api = begin_writer(&app).await.unwrap();
    let refused =
        takedowns::take_down(&mut as_api, heir, TakedownCode::Other, false, &test_key()).await;
    assert!(
        matches!(&refused, Err(lunaway_db::DbError::Query(e))
            if e.as_database_error().and_then(|d| d.code()).as_deref() == Some("42501")),
        "a leak of the API's credentials does not empty the catalogue: {refused:?}"
    );
    drop(as_api);

    // A rating the filters read, as the worker writes it, a season and
    // what the prices include, as the conflation writes them: the
    // tombstone keeps none of it.
    sqlx::query!(
        "UPDATE places SET filter_rating = 4.2, opening_season = '{92,305}',
             price_services_included = true, price_parking_includes = '{tourist_tax}'
         WHERE id = ANY($1)",
        &[heir, absorbed][..]
    )
    .execute(&pool)
    .await
    .unwrap();
    let mut tx = begin_writer(&ingest).await.unwrap();
    let takedowns::TakeDown::Done(done) = takedowns::take_down(
        &mut tx,
        absorbed,
        TakedownCode::CourtOrder,
        false,
        &test_key(),
    )
    .await
    .unwrap() else {
        panic!("the place is taken down");
    };
    tx.commit().await.unwrap();
    let neighbour_now = sqlx::query!(
        r#"SELECT name, taken_down_at IS NULL AS "kept!" FROM source_records WHERE external_id = 'node/4242'"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        (neighbour_now.name.as_deref(), neighbour_now.kept),
        (Some("Parking de la mairie"), true),
        "another spot's record is not emptied without the moderator's say"
    );
    assert_eq!(
        done.place, heir,
        "a place merged into another takes down the one that absorbed it"
    );
    assert_eq!(
        (done.places, done.records),
        (2, u64::try_from(described_by.len() + 1).unwrap())
    );
    for id in [heir, absorbed] {
        assert!(places::by_id(&pool, id).await.unwrap().is_none());
        let row = sqlx::query!(
            r#"
            SELECT name, ST_X(geom::geometry) AS "lon!", ST_Y(geom::geometry) AS "lat!",
                   street, city, municipality_code, provenance::text AS "provenance!",
                   filter_rating, opening_season, price_services_included,
                   price_parking_includes,
                   deleted_at IS NOT NULL AS "deleted!", taken_down_at IS NOT NULL AS "taken!"
            FROM places WHERE id = $1
            "#,
            id
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(
            (
                row.name,
                row.lon,
                row.lat,
                row.street,
                row.city,
                row.municipality_code
            ),
            (None, 0.0, 0.0, None, None, None),
            "the tombstone keeps neither name nor position nor address"
        );
        assert_eq!(
            (row.provenance.as_str(), row.deleted, row.taken),
            ("[]", true, true)
        );
        assert_eq!(row.filter_rating, None, "nor the rating the filters read");
        assert_eq!(
            (
                row.opening_season,
                row.price_services_included,
                row.price_parking_includes
            ),
            (None, false, Vec::<String>::new()),
            "nor its season nor what its prices include"
        );
    }
    let mut emptied = described_by.clone();
    emptied.push(dropped);
    assert_emptied(&pool, &emptied).await;
    let submitted = sqlx::query!(
        r#"SELECT payload::text AS "payload!", status FROM place_submissions ORDER BY id"#
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    assert_eq!(
        submitted
            .iter()
            .map(|s| (s.payload.as_str(), s.status.as_str()))
            .collect::<Vec<_>>(),
        [("{}", "applied"), ("{}", "rejected")],
        "the edits lose their content, and the one waiting is refused"
    );
    assert!(
        lunaway_db::community::live_place(&app, heir)
            .await
            .unwrap()
            .is_none(),
        "the place takes no new contribution"
    );

    let purged = takedowns::purge_community(&app, absorbed).await.unwrap();
    let Purge::Done {
        place,
        reviews,
        photos,
        confirmations,
        issue_reports,
        orphan_files,
    } = purged
    else {
        panic!("the purge runs once the place is taken down: {purged:?}");
    };
    assert_eq!(
        (place, reviews, photos, confirmations, issue_reports),
        (heir, 1, 1, 1, 1)
    );
    assert_eq!(
        orphan_files,
        [file('a'), file('b')],
        "the caller removes these files"
    );
    let about_review: i64 = sqlx::query_scalar!(
        r#"SELECT (SELECT count(*) FROM content_reports WHERE target_id = $1)
                + (SELECT count(*) FROM moderation_queue WHERE target_id = $1) AS "n!""#,
        review
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        about_review, 0,
        "nothing about the review is left to decide"
    );

    // Far from the place, a device syncing Lyon is told too: the tombstone
    // keeps no position to filter on.
    let lyon = BBox::new(45.7, 4.8, 45.8, 4.9).unwrap();
    let (changes, _) = places::changes(&app, lyon, cursor, 100, true)
        .await
        .unwrap();
    assert!(
        changes
            .iter()
            .any(|c| matches!(c, places::Change::Delete { id, .. } if *id == heir)),
        "{changes:?}"
    );
    let region = done.region.expect("an Anjou place has a sync region");
    let (in_region, _) = places::changes_in_region(&app, &region, cursor, 100, true)
        .await
        .unwrap();
    assert!(
        in_region.iter().any(|c| matches!(
            c,
            places::Change::Delete { id, .. } | places::Change::Left { id, .. } if *id == heir
        )),
        "the devices keeping {region} drop it: {in_region:?}"
    );

    // Again: the first code and date stay, nothing else changes.
    let first_at: chrono::DateTime<Utc> =
        sqlx::query_scalar!("SELECT taken_down_at FROM places WHERE id = $1", heir)
            .fetch_one(&pool)
            .await
            .unwrap()
            .unwrap();
    let mut tx = begin_writer(&ingest).await.unwrap();
    takedowns::take_down(&mut tx, heir, TakedownCode::Gdpr, false, &test_key())
        .await
        .unwrap();
    tx.commit().await.unwrap();
    let logged = sqlx::query!("SELECT reason, taken_down_at FROM place_takedowns")
        .fetch_all(&pool)
        .await
        .unwrap();
    assert_eq!(logged.len(), 1);
    assert_eq!(
        logged[0].reason, "court-order",
        "the kind of request is kept, as its code: no text that could name the requester"
    );
    let again_at: Option<chrono::DateTime<Utc>> =
        sqlx::query_scalar!("SELECT taken_down_at FROM places WHERE id = $1", heir)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(again_at, Some(first_at));

    // The next import lists every record again, the retired one included;
    // a full conflation follows.
    ingest_fixtures(&ingest).await;
    records::mark_all_dirty(&ingest).await.unwrap();
    run(&ingest, at(3), None).await.unwrap();
    assert_emptied(&pool, &emptied).await;
    for name in names {
        let back: i64 = sqlx::query_scalar!(
            r#"SELECT count(*) AS "n!" FROM places WHERE deleted_at IS NULL AND name = $1"#,
            name
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(back, 0, "{name} does not come back");
    }
    assert_eq!(
        live_places(&pool).await,
        live_before - 1,
        "the place taken down, and nothing else, is gone"
    );
}
