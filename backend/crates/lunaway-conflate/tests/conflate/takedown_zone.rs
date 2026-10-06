//! The zone of a place taken down: a new place inside it, from a source or
//! from the community, and a live place moving into it, wait for a
//! moderator, who may release them; and the journal outside the database
//! takes the place down again after a restore of an older dump.

use lunaway_conflate::{
    run,
    takedown::{self, Request, TakedownError},
};
use lunaway_db::{
    PgPool,
    conflation::begin_writer,
    holds,
    moderation::{self, Decided, Decision},
    records,
    submissions::{self, NewSubmission, Submitted},
    takedown_journal::{Entry, JournalError, TakedownJournal},
    takedowns::{self, Purge, TakeDown},
};
use lunaway_domain::{
    NormalizedRecord, PlaceKind, Position, SourceId,
    community::submission::{NewPlace, PlacePatch},
    takedown::TakedownCode,
};
use uuid::Uuid;

use super::{M, account, as_role, at, test_key};

/// The private home listed as a spot, in the Mauges.
const SPOT: (f64, f64) = (47.3, -0.5);

fn north_of_spot(m: f64) -> Position {
    Position::new(SPOT.0 + m * M, SPOT.1).unwrap()
}

/// OpenStreetMap lists (or lists again) the element `id`.
async fn list(pool: &PgPool, id: &str, kind: PlaceKind, name: &str, at_: Position) {
    let mut r = NormalizedRecord::new(kind, at_);
    r.name = Some(name.to_owned());
    let raw = serde_json::json!({});
    records::upsert(
        pool,
        &SourceId::OSM,
        &[records::NewRecord {
            external_id: id,
            external_url: None,
            record: &r,
            raw: &raw,
            fetched_at: at(1),
            scope: Some("FR"),
        }],
    )
    .await
    .unwrap();
}

/// The live place the record `external_id` of `source` belongs to.
async fn place_of(pool: &PgPool, source: &SourceId, external_id: &str) -> Option<Uuid> {
    sqlx::query_scalar!(
        r#"
        SELECT p.id FROM source_records r
        JOIN place_sources ps ON ps.record_id = r.id
        JOIN places p ON p.id = ps.place_id AND p.deleted_at IS NULL
        WHERE r.source_id = $1 AND r.external_id = $2
        "#,
        source.as_str(),
        external_id
    )
    .fetch_optional(pool)
    .await
    .unwrap()
}

async fn position_of(pool: &PgPool, place: Uuid) -> Position {
    let r = sqlx::query!(
        r#"SELECT ST_Y(geom::geometry) AS "lat!", ST_X(geom::geometry) AS "lon!" FROM places WHERE id = $1"#,
        place
    )
    .fetch_one(pool)
    .await
    .unwrap();
    Position::new(r.lat, r.lon).unwrap()
}

/// The open queue entries of held groups.
async fn held_entries(app: &PgPool) -> Vec<moderation::QueueEntry> {
    moderation::open(app, 100)
        .await
        .unwrap()
        .into_iter()
        .filter(|e| e.kind == "place_hold")
        .collect()
}

/// Takes the place of `node/1` down through the catalogue's step, with the
/// journal in `dir`.
async fn take_down_spot(ingest: &PgPool, dir: &std::path::Path) -> takedowns::TakenDown {
    let place = place_of(ingest, &SourceId::OSM, "node/1").await.unwrap();
    match takedown::take_down(
        ingest,
        &test_key(),
        &TakedownJournal::new(dir),
        Request {
            place,
            reason: "GDPR erasure, ticket 1",
            code: TakedownCode::PrivateHome,
            with_nearby: false,
        },
        at(2),
    )
    .await
    .unwrap()
    {
        TakeDown::Done(d) => d,
        other => panic!("not taken down: {other:?}"),
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_listing_near_a_place_taken_down_waits_until_a_moderator_releases_it(pool: PgPool) {
    let key = test_key();
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    list(
        &pool,
        "node/1",
        PlaceKind::Homestay,
        "Chez Dupont",
        north_of_spot(0.0),
    )
    .await;
    run(&ingest, at(2), Some(&key)).await.unwrap();
    let journal = tempfile::tempdir().unwrap();
    let done = take_down_spot(&ingest, journal.path()).await;
    let stored: i64 = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM takedown_cells"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        usize::try_from(stored).unwrap(),
        done.cells.len(),
        "the zone is stored, and no position with it"
    );
    assert!(done.cells.len() >= 61);
    let line = TakedownJournal::new(journal.path()).read().unwrap();
    assert_eq!(line.entries.len(), 1, "journaled before it committed");
    assert_eq!(line.entries[0].places, [done.place]);
    assert_eq!(line.entries[0].cells, done.cells);

    // The same home under another element 20 m away, and a car park far
    // enough not to be held.
    list(
        &pool,
        "node/2",
        PlaceKind::Homestay,
        "Accueil Dupont",
        north_of_spot(20.0),
    )
    .await;
    list(
        &pool,
        "node/3",
        PlaceKind::Parking,
        "Parking du bourg",
        north_of_spot(600.0),
    )
    .await;
    let s = run(&ingest, at(2), Some(&key)).await.unwrap();
    assert_eq!(
        (s.created, s.held_near_takedown, s.new_holds),
        (1, 1, 1),
        "the far car park goes live; the listing at the home waits"
    );
    assert!(place_of(&pool, &SourceId::OSM, "node/3").await.is_some());
    assert!(
        place_of(&pool, &SourceId::OSM, "node/2").await.is_none(),
        "a spot taken down does not come back under another element"
    );
    let entries = held_entries(&app).await;
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].reason, holds::REASON);
    let excerpt = entries[0].excerpt.clone().unwrap();
    assert!(
        excerpt.contains("node/2") && excerpt.contains("Accueil Dupont"),
        "the moderator sees which records wait: {excerpt}"
    );

    // Listed again with another name: the same hold, no second entry.
    list(
        &pool,
        "node/2",
        PlaceKind::Homestay,
        "Accueil chez Dupont",
        north_of_spot(20.0),
    )
    .await;
    let s = run(&ingest, at(2), Some(&key)).await.unwrap();
    assert_eq!((s.held_near_takedown, s.new_holds), (1, 0));
    assert_eq!(held_entries(&app).await.len(), 1);

    // A community member adds a spot 100 m from the home: held too, with
    // its author.
    let author = account(&app, 1).await;
    let device: Uuid = sqlx::query_scalar!("SELECT id FROM device_keys")
        .fetch_one(&pool)
        .await
        .unwrap();
    let new = NewPlace {
        kind: PlaceKind::Nature,
        position: north_of_spot(-100.0),
        details: PlacePatch {
            name: Some("Jardin partagé".into()),
            ..PlacePatch::default()
        },
    };
    submissions::submit(
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
    let s = run(&ingest, at(2), Some(&key)).await.unwrap();
    assert_eq!(
        (s.submissions_applied, s.created, s.held_near_takedown),
        (1, 0, 1)
    );
    let entries = held_entries(&app).await;
    let community = entries
        .iter()
        .find(|e| e.account_id == Some(author))
        .expect("the community's listing waits with its author");
    let osm = entries
        .iter()
        .find(|e| e.account_id.is_none())
        .unwrap()
        .clone();

    // A rejected hold stays held, and does not come back to the queue.
    assert!(matches!(
        moderation::decide(&app, community.id, Decision::Reject, None)
            .await
            .unwrap(),
        Decided::Done { .. }
    ));
    sqlx::query!("UPDATE source_records SET needs_conflation = true WHERE source_id = 'community'")
        .execute(&pool)
        .await
        .unwrap();
    let s = run(&ingest, at(2), Some(&key)).await.unwrap();
    assert_eq!((s.created, s.held_near_takedown, s.new_holds), (0, 1, 0));
    assert_eq!(
        held_entries(&app).await.len(),
        1,
        "only the OSM listing waits"
    );

    // The owner now welcomes vans: released, journaled, and live at the
    // worker's next run.
    assert!(matches!(
        moderation::decide(&app, osm.id, Decision::Approve, Some("owner welcomes vans"))
            .await
            .unwrap(),
        Decided::Done { .. }
    ));
    let release = sqlx::query!(
        r#"SELECT r.note, h.status FROM place_hold_releases r JOIN place_holds h ON h.id = r.hold_id"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        (release.note.as_deref(), release.status.as_str()),
        (Some("owner welcomes vans"), "released"),
        "a release is journaled with its note"
    );
    let s = run(&ingest, at(3), Some(&key)).await.unwrap();
    assert_eq!(
        (s.released_records, s.created, s.held_near_takedown),
        (1, 1, 0)
    );
    let released = place_of(&pool, &SourceId::OSM, "node/2").await.unwrap();
    assert_ne!(released, done.place, "a new place, not the one taken down");
    assert!(held_entries(&app).await.is_empty());
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_place_moving_into_the_zone_waits_and_a_neighbour_inside_it_does_not(pool: PgPool) {
    let key = test_key();
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    list(
        &pool,
        "node/1",
        PlaceKind::Homestay,
        "Chez Dupont",
        north_of_spot(0.0),
    )
    .await;
    list(
        &pool,
        "node/10",
        PlaceKind::Parking,
        "Parking de l'église",
        north_of_spot(45.0),
    )
    .await;
    list(
        &pool,
        "node/11",
        PlaceKind::Parking,
        "Parking du stade",
        north_of_spot(500.0),
    )
    .await;
    run(&ingest, at(2), Some(&key)).await.unwrap();
    let journal = tempfile::tempdir().unwrap();
    take_down_spot(&ingest, journal.path()).await;

    // The neighbour the takedown left inside the zone changes as before.
    list(
        &pool,
        "node/10",
        PlaceKind::Parking,
        "Parking de l'église Saint-Pierre",
        north_of_spot(45.0),
    )
    .await;
    let s = run(&ingest, at(2), Some(&key)).await.unwrap();
    assert_eq!((s.updated, s.held_near_takedown), (1, 0));
    let church = place_of(&pool, &SourceId::OSM, "node/10").await.unwrap();
    assert_eq!(
        places_name(&pool, church).await.as_deref(),
        Some("Parking de l'église Saint-Pierre")
    );

    // The stadium's node dragged onto the home: the place stays where it
    // was shown, and a moderator decides.
    let stadium = place_of(&pool, &SourceId::OSM, "node/11").await.unwrap();
    let before = position_of(&pool, stadium).await;
    list(
        &pool,
        "node/11",
        PlaceKind::Parking,
        "Parking du stade",
        north_of_spot(10.0),
    )
    .await;
    let s = run(&ingest, at(2), Some(&key)).await.unwrap();
    assert_eq!((s.updated, s.held_near_takedown, s.new_holds), (0, 1, 1));
    assert_eq!(position_of(&pool, stadium).await, before);
    let hold = sqlx::query!("SELECT kind, place_id FROM place_holds")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!((hold.kind.as_str(), hold.place_id), ("move", Some(stadium)));
    let entry = held_entries(&app).await.pop().unwrap();
    moderation::decide(&app, entry.id, Decision::Approve, None)
        .await
        .unwrap();
    run(&ingest, at(3), Some(&key)).await.unwrap();
    assert!(
        position_of(&pool, stadium)
            .await
            .distance_m(north_of_spot(10.0))
            < 0.01,
        "released, the move applies"
    );
}

async fn places_name(pool: &PgPool, place: Uuid) -> Option<String> {
    sqlx::query_scalar!("SELECT name FROM places WHERE id = $1", place)
        .fetch_one(pool)
        .await
        .unwrap()
}

/// Without `LUNAWAY_TAKEDOWN_SECRET` the worker runs and holds nothing: it
/// cannot hash a position into a cell.
#[sqlx::test(migrations = "../../migrations")]
async fn without_the_secret_the_conflation_runs_and_holds_nothing(pool: PgPool) {
    let key = test_key();
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    list(
        &pool,
        "node/1",
        PlaceKind::Homestay,
        "Chez Dupont",
        north_of_spot(0.0),
    )
    .await;
    run(&ingest, at(2), Some(&key)).await.unwrap();
    let journal = tempfile::tempdir().unwrap();
    take_down_spot(&ingest, journal.path()).await;
    list(
        &pool,
        "node/2",
        PlaceKind::Homestay,
        "Accueil Dupont",
        north_of_spot(20.0),
    )
    .await;
    let s = run(&ingest, at(2), None).await.unwrap();
    assert_eq!((s.created, s.held_near_takedown), (1, 0));
    assert!(place_of(&pool, &SourceId::OSM, "node/2").await.is_some());
}

/// A dump taken before a takedown, restored: the database holds the place
/// alive again, with its review, and a record near it imported but not yet
/// conflated, while the journal on the data volume holds the takedown. The
/// restored state is made here by taking the place down in a transaction
/// rolled back after its line was written.
#[sqlx::test(migrations = "../../migrations")]
async fn the_journal_takes_a_restored_place_down_again_once(pool: PgPool) {
    let key = test_key();
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    list(
        &pool,
        "node/1",
        PlaceKind::Homestay,
        "Chez Dupont",
        north_of_spot(0.0),
    )
    .await;
    run(&ingest, at(2), Some(&key)).await.unwrap();
    let place = place_of(&pool, &SourceId::OSM, "node/1").await.unwrap();
    let author = account(&app, 1).await;
    lunaway_db::community::rate(&app, author, place, 5)
        .await
        .unwrap();
    let dir = tempfile::tempdir().unwrap();
    let journal = TakedownJournal::new(dir.path());
    let mut tx = begin_writer(&ingest).await.unwrap();
    let TakeDown::Done(d) = takedowns::take_down(&mut tx, place, "court order 7", false, &key)
        .await
        .unwrap()
    else {
        panic!("not taken down");
    };
    journal
        .record(Entry {
            places: d.family.clone(),
            taken_down_at: at(2),
            code: TakedownCode::CourtOrder,
            with_nearby: false,
            cells: d.cells.clone(),
            key_check: Some(key.check()),
        })
        .await
        .unwrap();
    drop(tx);
    list(
        &pool,
        "node/5",
        PlaceKind::Homestay,
        "Dupont",
        north_of_spot(25.0),
    )
    .await;
    assert!(
        !takedowns::standing(&pool, place)
            .await
            .unwrap()
            .unwrap()
            .taken_down,
        "the restored database holds the place alive"
    );

    assert!(
        matches!(
            takedown::replay(
                &ingest,
                &key,
                &TakedownJournal::new(dir.path().join("lost")),
                false,
                false,
                at(3)
            )
            .await,
            Err(TakedownError::Journal(JournalError::Empty(_)))
        ),
        "a journal not put back must not pass for one with nothing to replay"
    );

    let dry = takedown::replay(&ingest, &key, &journal, true, false, at(3))
        .await
        .unwrap();
    assert_eq!((dry.would_take_down.clone(), dry.cells), (vec![place], 0));
    assert!(
        !takedowns::standing(&pool, place)
            .await
            .unwrap()
            .unwrap()
            .taken_down
    );

    let r = takedown::replay(&ingest, &key, &journal, false, false, at(3))
        .await
        .unwrap();
    assert_eq!(r.taken_down.len(), 1);
    assert_eq!(r.taken_down[0].place, place);
    assert_eq!(usize::try_from(r.cells).unwrap(), d.cells.len());
    assert!(
        takedowns::standing(&pool, place)
            .await
            .unwrap()
            .unwrap()
            .taken_down
    );
    assert!(
        place_of(&pool, &SourceId::OSM, "node/5").await.is_none(),
        "the record restored unconflated is held, the cells being back first"
    );
    assert_eq!(holds::open_count(&pool).await.unwrap(), 1);

    // The API's step: the review the dump brought back goes.
    assert_eq!(takedowns::unpurged(&app).await.unwrap(), [place]);
    assert!(matches!(
        takedowns::purge_community(&app, place).await.unwrap(),
        Purge::Done { reviews: 1, .. }
    ));
    assert!(takedowns::unpurged(&app).await.unwrap().is_empty());

    let again = takedown::replay(&ingest, &key, &journal, false, false, at(4))
        .await
        .unwrap();
    assert_eq!(
        (again.taken_down.len(), again.already, again.cells),
        (0, 1, 0),
        "a second replay finds everything done and writes nothing"
    );
}

/// Two live places outside the zone, joined by a person and both dragged
/// onto the spot: the group is held, and neither place disappears in the
/// meantime, nor after a moderator refuses the move.
#[sqlx::test(migrations = "../../migrations")]
async fn a_held_group_tombstones_none_of_the_places_it_describes(pool: PgPool) {
    use lunaway_domain::conflation::ConstraintKind;
    let key = test_key();
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    list(
        &pool,
        "node/1",
        PlaceKind::Homestay,
        "Chez Dupont",
        north_of_spot(0.0),
    )
    .await;
    list(
        &pool,
        "node/20",
        PlaceKind::Parking,
        "Parking des Tilleuls",
        north_of_spot(400.0),
    )
    .await;
    list(
        &pool,
        "node/21",
        PlaceKind::Parking,
        "Parking du lavoir",
        north_of_spot(470.0),
    )
    .await;
    run(&ingest, at(2), Some(&key)).await.unwrap();
    let journal = tempfile::tempdir().unwrap();
    take_down_spot(&ingest, journal.path()).await;
    let a = place_of(&pool, &SourceId::OSM, "node/20").await.unwrap();
    let b = place_of(&pool, &SourceId::OSM, "node/21").await.unwrap();
    let (before_a, before_b) = (position_of(&pool, a).await, position_of(&pool, b).await);

    list(
        &pool,
        "node/20",
        PlaceKind::Parking,
        "Parking des Tilleuls",
        north_of_spot(10.0),
    )
    .await;
    list(
        &pool,
        "node/21",
        PlaceKind::Parking,
        "Parking du lavoir",
        north_of_spot(12.0),
    )
    .await;
    let (ra, rb) = (
        records::id_of(&pool, &SourceId::OSM, "node/20")
            .await
            .unwrap()
            .unwrap(),
        records::id_of(&pool, &SourceId::OSM, "node/21")
            .await
            .unwrap()
            .unwrap(),
    );
    records::set_constraint(
        &pool,
        ra,
        rb,
        ConstraintKind::MustLink,
        Some("one car park"),
    )
    .await
    .unwrap();
    let s = run(&ingest, at(2), Some(&key)).await.unwrap();
    assert_eq!((s.held_near_takedown, s.tombstoned), (1, 0));
    let live = |p: Uuid| {
        let pool = pool.clone();
        async move {
            sqlx::query_scalar!(
                r#"SELECT deleted_at IS NULL AS "live!" FROM places WHERE id = $1"#,
                p
            )
            .fetch_one(&pool)
            .await
            .unwrap()
        }
    };
    assert!(
        live(a).await && live(b).await,
        "a held group changes no place: neither is absorbed into the other"
    );
    assert_eq!(position_of(&pool, a).await, before_a);
    assert_eq!(position_of(&pool, b).await, before_b);

    let entry = held_entries(&app).await.pop().unwrap();
    moderation::decide(&app, entry.id, Decision::Reject, None)
        .await
        .unwrap();
    records::set_constraint(&pool, ra, rb, ConstraintKind::MustLink, Some("again"))
        .await
        .unwrap();
    sqlx::query!(
        "UPDATE source_records SET needs_conflation = true WHERE id = ANY($1)",
        &[ra, rb][..]
    )
    .execute(&pool)
    .await
    .unwrap();
    let s = run(&ingest, at(3), Some(&key)).await.unwrap();
    assert_eq!((s.held_near_takedown, s.new_holds, s.tombstoned), (1, 0, 0));
    assert!(
        live(a).await && live(b).await,
        "refused, the move stays held and both places stay"
    );
}

/// A neighbour the takedown left inside the zone, dragged onto the spot:
/// it moves to another cell, so it waits like a new listing.
#[sqlx::test(migrations = "../../migrations")]
async fn a_neighbour_inside_the_zone_moved_onto_the_spot_waits(pool: PgPool) {
    let key = test_key();
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    list(
        &pool,
        "node/1",
        PlaceKind::Homestay,
        "Chez Dupont",
        north_of_spot(0.0),
    )
    .await;
    list(
        &pool,
        "node/10",
        PlaceKind::Parking,
        "Parking de l'église",
        north_of_spot(110.0),
    )
    .await;
    run(&ingest, at(2), Some(&key)).await.unwrap();
    let journal = tempfile::tempdir().unwrap();
    take_down_spot(&ingest, journal.path()).await;
    let church = place_of(&pool, &SourceId::OSM, "node/10").await.unwrap();
    let before = position_of(&pool, church).await;
    list(
        &pool,
        "node/10",
        PlaceKind::Parking,
        "Parking de l'église",
        north_of_spot(2.0),
    )
    .await;
    let s = run(&ingest, at(2), Some(&key)).await.unwrap();
    assert_eq!((s.updated, s.held_near_takedown), (0, 1));
    assert_eq!(position_of(&pool, church).await, before);
}

/// Under another secret than the takedowns', the cells match nothing: the
/// conflation holds nothing and says so, and neither a takedown nor a
/// replay runs.
#[sqlx::test(migrations = "../../migrations")]
async fn another_secret_is_told_apart(pool: PgPool) {
    let key = test_key();
    let other = lunaway_domain::takedown::TakedownKey::new(&[7; 32]).unwrap();
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    list(
        &pool,
        "node/1",
        PlaceKind::Homestay,
        "Chez Dupont",
        north_of_spot(0.0),
    )
    .await;
    list(
        &pool,
        "node/30",
        PlaceKind::Parking,
        "Parking du bourg",
        north_of_spot(900.0),
    )
    .await;
    run(&ingest, at(2), Some(&key)).await.unwrap();
    let dir = tempfile::tempdir().unwrap();
    take_down_spot(&ingest, dir.path()).await;
    let bourg = place_of(&pool, &SourceId::OSM, "node/30").await.unwrap();
    assert!(matches!(
        takedown::take_down(
            &ingest,
            &other,
            &TakedownJournal::new(dir.path()),
            Request {
                place: bourg,
                reason: "test",
                code: TakedownCode::Other,
                with_nearby: false,
            },
            at(2),
        )
        .await
        .unwrap(),
        TakeDown::OtherKey
    ));
    assert!(matches!(
        takedown::replay(
            &ingest,
            &other,
            &TakedownJournal::new(dir.path()),
            true,
            false,
            at(3)
        )
        .await,
        Err(TakedownError::OtherKey)
    ));
    list(
        &pool,
        "node/2",
        PlaceKind::Homestay,
        "Accueil Dupont",
        north_of_spot(20.0),
    )
    .await;
    let s = run(&ingest, at(2), Some(&other)).await.unwrap();
    assert_eq!(s.held_near_takedown, 0);
    assert_eq!(
        TakedownJournal::new(dir.path())
            .read()
            .unwrap()
            .entries
            .len(),
        1,
        "the refused takedown wrote no line"
    );
}

/// The dump restored had the journaled place's family joined to a
/// neighbour the takedown never touched: the replay leaves both to the
/// operator instead of emptying the neighbour.
#[sqlx::test(migrations = "../../migrations")]
async fn a_replay_leaves_alone_a_family_the_journal_does_not_name(pool: PgPool) {
    let key = test_key();
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    list(
        &pool,
        "node/1",
        PlaceKind::Homestay,
        "Chez Dupont",
        north_of_spot(0.0),
    )
    .await;
    list(
        &pool,
        "node/40",
        PlaceKind::Parking,
        "Parking voisin",
        north_of_spot(800.0),
    )
    .await;
    run(&ingest, at(2), Some(&key)).await.unwrap();
    let place = place_of(&pool, &SourceId::OSM, "node/1").await.unwrap();
    let neighbour = place_of(&pool, &SourceId::OSM, "node/40").await.unwrap();
    let dir = tempfile::tempdir().unwrap();
    let journal = TakedownJournal::new(dir.path());
    let mut tx = begin_writer(&ingest).await.unwrap();
    let TakeDown::Done(d) = takedowns::take_down(&mut tx, place, "gdpr 9", false, &key)
        .await
        .unwrap()
    else {
        panic!("not taken down");
    };
    journal
        .record(Entry {
            places: d.family.clone(),
            taken_down_at: at(2),
            code: TakedownCode::Gdpr,
            with_nearby: false,
            cells: d.cells.clone(),
            key_check: Some(key.check()),
        })
        .await
        .unwrap();
    drop(tx);
    // In the restored database the neighbour was merged into the place.
    sqlx::query!(
        "UPDATE places SET merged_into = $1, deleted_at = now() WHERE id = $2",
        place,
        neighbour
    )
    .execute(&pool)
    .await
    .unwrap();
    let r = takedown::replay(&ingest, &key, &journal, false, false, at(3))
        .await
        .unwrap();
    assert_eq!(r.to_check, [(place, neighbour)]);
    assert!(r.taken_down.is_empty());
    let emptied: bool = sqlx::query_scalar!(
        r#"SELECT taken_down_at IS NOT NULL AS "t!" FROM places WHERE id = $1"#,
        neighbour
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(
        !emptied,
        "the neighbour keeps its content for the operator to judge"
    );
    assert!(r.cells > 0, "the zone is back all the same");
}
