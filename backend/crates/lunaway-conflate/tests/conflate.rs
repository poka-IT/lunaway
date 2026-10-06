//! The conflation on a real database: recorded OSM and Atout France payloads
//! around Angers, plus synthetic records where a case needs exact control.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::{NaiveDate, TimeZone, Utc};
use lunaway_conflate::{RunStats, run};
use lunaway_db::{PgPool, places, records};
use lunaway_domain::{NormalizedRecord, PlaceKind, Position, SourceId, conflation::ConstraintKind};
use lunaway_ingest::{FetchedRecord, atout_france, geocode, osm, store::store_complete};
use uuid::Uuid;

const OVERPASS: &[u8] = include_bytes!("../../lunaway-ingest/tests/fixtures/overpass_sample.json");
const ATOUT_CSV: &[u8] =
    include_bytes!("../../lunaway-ingest/tests/fixtures/atout_france_sample.csv");
const BAN_ANSWER: &[u8] =
    include_bytes!("../../lunaway-ingest/tests/fixtures/ban_answer_sample.csv");

fn day(d: u32) -> NaiveDate {
    NaiveDate::from_ymd_opt(2026, 11, d).unwrap()
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
    let stats = run(&pool, day(2)).await.unwrap();
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
    run(&pool, day(2)).await.unwrap();
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
    run(&pool, day(2)).await.unwrap();
    let before = snapshot(&pool).await;
    let again = run(&pool, day(2)).await.unwrap();
    assert_eq!(again, RunStats::default(), "nothing flagged, nothing to do");
    assert_eq!(snapshot(&pool).await, before);

    // Re-importing the same payloads flags nothing either.
    ingest_fixtures(&pool).await;
    assert_eq!(run(&pool, day(2)).await.unwrap(), RunStats::default());
    assert_eq!(snapshot(&pool).await, before);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_full_rebuild_lands_where_the_incremental_runs_did(pool: PgPool) {
    // Import the sources one after the other, conflating in between, then
    // rebuild everything: the same places, ids and digests come out.
    store_complete(&pool, &SourceId::OSM, Some("FR-PDL"), &osm_records())
        .await
        .unwrap();
    run(&pool, day(2)).await.unwrap();
    store_complete(&pool, &SourceId::ATOUT_FRANCE, None, &atout_records())
        .await
        .unwrap();
    let second = run(&pool, day(2)).await.unwrap();
    assert_eq!(
        second.updated, 6,
        "six OSM places gain an Atout France source"
    );
    let incremental = snapshot(&pool).await;

    records::mark_all_dirty(&pool).await.unwrap();
    let rebuild = run(&pool, day(2)).await.unwrap();
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
    run(&pool, day(2)).await.unwrap();
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
    run(&pool, day(2)).await.unwrap();
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
    run(&pool, day(2)).await.unwrap();
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
    let stats = run(&pool, day(2)).await.unwrap();
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
    run(&pool, day(2)).await.unwrap();
    assert_ne!(
        place_of(&pool, &SourceId::OSM, PORT_OSM).await,
        place_of(&pool, &SourceId::ATOUT_FRANCE, PORT_AF).await
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_must_link_merges_a_review_pair_and_leaves_a_redirect(pool: PgPool) {
    ingest_fixtures(&pool).await;
    run(&pool, day(2)).await.unwrap();
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
    let stats = run(&pool, day(2)).await.unwrap();
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
    run(&pool, day(2)).await.unwrap();
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
    let stats = run(&pool, day(2)).await.unwrap();
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
    run(&pool, day(2)).await.unwrap();
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
    let stats = run(&pool, day(2)).await.unwrap();
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
    run(&pool, day(2)).await.unwrap();
    let place = place_of(&pool, &SourceId::OSM, "node/9").await;
    let row = places::by_id(&pool, place).await.unwrap().unwrap();
    assert!(row.opening_hours_parsed);
    let first = row.opening_intervals.unwrap();
    assert_eq!(first.len(), 10);
    assert_eq!(
        first[0].start,
        Utc.with_ymd_and_hms(2026, 11, 2, 7, 0, 0).unwrap()
    );

    let next = run(&pool, day(3)).await.unwrap();
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
        run(&pool, day(3)).await.unwrap().opening_refreshed,
        0,
        "once a day"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn intervals_computed_before_their_window_end_was_stored_get_it_the_same_day(pool: PgPool) {
    let mut r = campsite("Camping Horaires", 47.4, -0.6);
    r.opening_hours = Some("24/7".into());
    r.address.country_code = Some("FR".into());
    store_complete(&pool, &SourceId::OSM, None, &[fetched("node/9", r)])
        .await
        .unwrap();
    run(&pool, day(2)).await.unwrap();
    let place = place_of(&pool, &SourceId::OSM, "node/9").await;
    // What a place written before the column existed looks like.
    sqlx::query!("UPDATE places SET opening_intervals_until = NULL")
        .execute(&pool)
        .await
        .unwrap();
    let before = places::by_id(&pool, place).await.unwrap().unwrap();
    let stats = run(&pool, day(2)).await.unwrap();
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
    let stats = run(&pool, day(2)).await.unwrap();
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
    run(&pool, day(2)).await.unwrap();
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
    let stats = run(&ingest, day(2)).await.unwrap();
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
        today: day(2),
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
    let stats = run(&pool, day(2)).await.unwrap();
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
