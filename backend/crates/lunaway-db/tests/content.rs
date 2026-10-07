//! The open content of the places: what the content worker writes, what
//! an operator hides, and what the card reads.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::{Duration, Utc};
use lunaway_db::{
    PgPool,
    conflation::{self, OpeningEval, PlaceWrite},
    content::{self, DueQuery, Hide, NewDescription, NewPhoto, NewReview, PhotoFiles, RunLock},
};
use lunaway_domain::{Address, OvernightStatus, PlaceKind, Position, conflation::PlaceContent};
use sqlx::postgres::PgPoolOptions;
use uuid::Uuid;

const NO_OPENING: OpeningEval = OpeningEval {
    parsed: false,
    intervals: None,
    until: None,
    window_start: None,
    refresh_at: None,
};

async fn place(pool: &PgPool, name: &str, lat: f64, lon: f64) -> Uuid {
    let c = PlaceContent {
        name: Some(name.to_owned()),
        kind: PlaceKind::MotorhomeArea,
        position: Position::new(lat, lon).unwrap(),
        overnight: OvernightStatus::Unknown,
        services: Vec::new(),
        activities: Vec::new(),
        description: None,
        address: Address::default(),
        price_parking_eur: None,
        price_services_eur: None,
        max_height_m: None,
        max_length_m: None,
        max_width_m: None,
        max_weight_t: None,
        capacity: None,
        opening_hours: None,
        website: None,
        phone: None,
        stars: None,
    };
    let id = Uuid::now_v7();
    let mut tx = conflation::begin_writer(pool).await.unwrap();
    conflation::upsert_place(
        &mut tx,
        PlaceWrite {
            id,
            content: &c,
            provenance: &[],
            opening: &NO_OPENING,
            descriptions: &[],
            external_links: &[],
            content_hash: "h",
        },
    )
    .await
    .unwrap();
    tx.commit().await.unwrap();
    id
}

async fn merge(pool: &PgPool, gone: Uuid, into: Uuid) {
    let mut tx = conflation::begin_writer(pool).await.unwrap();
    conflation::tombstone(&mut tx, gone, Some(into))
        .await
        .unwrap();
    tx.commit().await.unwrap();
}

fn files(n: u8) -> PhotoFiles {
    let h = format!("{n:02x}").repeat(32);
    PhotoFiles {
        path: format!("external/{}/{}/{h}.webp", &h[..2], &h[2..4]),
        thumb_path: format!("external/{}/{}/{h}-t.webp", &h[..2], &h[2..4]),
        width: 1280,
        height: 960,
        thumbhash: vec![1, 2, 3],
    }
}

fn photo(external_id: &str, relation: &str, n: u8) -> NewPhoto {
    NewPhoto {
        external_id: external_id.to_owned(),
        version: format!("v{n}"),
        relation: relation.to_owned(),
        distance_m: Some(12.0),
        page_url: format!("https://commons.wikimedia.org/wiki/{external_id}"),
        title: Some("Aire".into()),
        author: Some("Pierre".into()),
        publisher: None,
        source_updated_on: None,
        licence: "CC BY-SA 4.0".into(),
        licence_url: "https://creativecommons.org/licenses/by-sa/4.0/".into(),
        taken_at: None,
        rights_end_on: None,
        files: files(n),
    }
}

fn due(source: &str, before: chrono::DateTime<Utc>) -> DueQuery<'_> {
    DueQuery {
        source,
        before,
        limit: 10,
        area: None,
        with_records_of: None,
        skip: &[],
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_refresh_replaces_photos_and_frees_unused_files(pool: PgPool) {
    let a = place(&pool, "Aire A", 47.0, 2.0).await;
    let b = place(&pool, "Aire B", 47.001, 2.0).await;
    let now = Utc::now();
    let r = content::replace_photos(
        &pool,
        a,
        "wikimedia-commons",
        &[
            photo("File:Near.jpg", "nearby", 1),
            photo("File:A.jpg", "linked", 2),
        ],
        now,
        2,
    )
    .await
    .unwrap();
    assert_eq!((r.kept, r.removed), (2, 0));
    // The same file shown on a second place shares its files.
    content::replace_photos(
        &pool,
        b,
        "wikimedia-commons",
        &[photo("File:A.jpg", "linked", 2)],
        now,
        1,
    )
    .await
    .unwrap();
    let shown = content::photos_of_place(&pool, a, 24).await.unwrap();
    assert_eq!(
        shown
            .iter()
            .map(|p| p.relation.as_str())
            .collect::<Vec<_>>(),
        ["linked", "nearby"],
        "a photo the place's data names comes before one taken around it"
    );
    let again = content::replace_photos(
        &pool,
        a,
        "wikimedia-commons",
        &[photo("File:A.jpg", "linked", 2)],
        now,
        1,
    )
    .await
    .unwrap();
    assert_eq!(again.removed, 1);
    assert_eq!(
        again.orphaned_files,
        [files(1).thumb_path, files(1).path],
        "the nearby photo's files are free; the linked one's are still used"
    );
    let stored = content::stored_files(&pool, "wikimedia-commons", "File:A.jpg", "v2")
        .await
        .unwrap();
    assert_eq!(stored, Some(files(2)), "a version already made is reused");
    assert_eq!(
        content::stored_files(&pool, "wikimedia-commons", "File:A.jpg", "v3")
            .await
            .unwrap(),
        None,
        "a new version of a file is downloaded again"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_hidden_item_stays_hidden_whatever_a_refresh_does(pool: PgPool) {
    let a = place(&pool, "Aire A", 47.0, 2.0).await;
    let now = Utc::now();
    let put = |set: Vec<NewPhoto>| {
        let pool = pool.clone();
        async move {
            let n = set.len();
            content::replace_photos(&pool, a, "panoramax", &set, now, n)
                .await
                .unwrap();
        }
    };
    put(vec![photo("p1", "facing", 1), photo("p2", "facing", 2)]).await;
    let shown = content::photos_of_place(&pool, a, 24).await.unwrap();
    let item = content::item(&pool, shown[0].id).await.unwrap().unwrap();
    assert!(
        content::set_hidden(
            &pool,
            &item.source_id,
            &Hide::Item(item.external_id.clone()),
            true
        )
        .await
        .unwrap()
    );
    // The source drops the picture, then offers it again.
    put(vec![photo("p2", "facing", 2)]).await;
    put(vec![photo("p1", "facing", 1), photo("p2", "facing", 2)]).await;
    let ids: Vec<String> = content::photos_of_place(&pool, a, 24)
        .await
        .unwrap()
        .iter()
        .map(|p| p.page_url.clone())
        .collect();
    assert_eq!(
        ids,
        ["https://commons.wikimedia.org/wiki/p2"],
        "a picture hidden once is hidden when it comes back"
    );
    assert!(
        content::set_hidden(&pool, "panoramax", &Hide::Source, true)
            .await
            .unwrap()
    );
    assert!(
        content::photos_of_place(&pool, a, 24)
            .await
            .unwrap()
            .is_empty(),
        "a source switched off shows nothing"
    );
    content::set_hidden(&pool, "panoramax", &Hide::Source, false)
        .await
        .unwrap();
    assert_eq!(
        content::photos_of_place(&pool, a, 24).await.unwrap().len(),
        1
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_photo_whose_rights_ended_is_no_longer_shown(pool: PgPool) {
    let a = place(&pool, "Aire A", 47.0, 2.0).await;
    let mut ended = photo("dt:1", "linked", 1);
    ended.rights_end_on = Some((Utc::now() - Duration::days(1)).date_naive());
    let mut running = photo("dt:2", "linked", 2);
    running.rights_end_on = Some((Utc::now() + Duration::days(30)).date_naive());
    content::replace_photos(&pool, a, "datatourisme", &[ended, running], Utc::now(), 2)
        .await
        .unwrap();
    let shown = content::photos_of_place(&pool, a, 24).await.unwrap();
    assert_eq!(
        shown.len(),
        1,
        "the end of a photo's rights holds even when no refresh ran since"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn places_are_asked_least_recently_first_and_once_a_week(pool: PgPool) {
    let a = place(&pool, "A", 47.0, 2.0).await;
    let b = place(&pool, "B", 47.1, 2.0).await;
    let c = place(&pool, "C", 47.2, 2.0).await;
    let now = Utc::now();
    content::mark_checked(&pool, a, "panoramax", now - Duration::days(9), 0)
        .await
        .unwrap();
    content::mark_checked(&pool, b, "panoramax", now - Duration::days(1), 1)
        .await
        .unwrap();
    let week_ago = now - Duration::days(7);
    let got = content::places_due(&pool, due("panoramax", week_ago))
        .await
        .unwrap();
    let ids: Vec<Uuid> = got.iter().map(|p| p.id).collect();
    assert_eq!(
        ids,
        [c, a],
        "never asked first, then the oldest; a fresh one waits"
    );
    let skipped = content::places_due(
        &pool,
        DueQuery {
            skip: &[c],
            ..due("panoramax", week_ago)
        },
    )
    .await
    .unwrap();
    assert_eq!(
        skipped.iter().map(|p| p.id).collect::<Vec<_>>(),
        [a],
        "a place tried in this run is not asked again in it"
    );
    let only_north = content::places_due(
        &pool,
        DueQuery {
            area: Some((47.15, 1.0, 48.0, 3.0)),
            ..due("panoramax", now)
        },
    )
    .await
    .unwrap();
    assert_eq!(only_north.iter().map(|p| p.id).collect::<Vec<_>>(), [c]);
    let with_records = content::places_due(
        &pool,
        DueQuery {
            with_records_of: Some("datatourisme"),
            ..due("datatourisme", now)
        },
    )
    .await
    .unwrap();
    assert!(
        with_records.is_empty(),
        "no place has a DATAtourisme record"
    );
}

fn description(lang: &str) -> NewDescription {
    NewDescription {
        lang: lang.into(),
        text: "Une aire.".into(),
        title: Some("Aire".into()),
        page_url: "https://fr.wikipedia.org/wiki/Aire".into(),
        author: None,
        publisher: Some("Wikipedia".into()),
        source_updated_on: None,
        licence: "CC BY-SA 4.0".into(),
        licence_url: "https://creativecommons.org/licenses/by-sa/4.0/".into(),
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn content_of_a_merged_place_shows_on_the_place_that_absorbed_it_until_purged(pool: PgPool) {
    let kept = place(&pool, "Kept", 47.1, 2.0).await;
    let gone = place(&pool, "Gone", 47.0, 2.0).await;
    let now = Utc::now();
    content::replace_photos(
        &pool,
        gone,
        "panoramax",
        &[photo("p1", "facing", 7)],
        now,
        1,
    )
    .await
    .unwrap();
    content::replace_descriptions(&pool, gone, "wikipedia", &[description("fr")], now, 1)
        .await
        .unwrap();
    content::mark_checked(&pool, kept, "panoramax", now, 0)
        .await
        .unwrap();
    merge(&pool, gone, kept).await;
    assert_eq!(
        content::photos_of_place(&pool, kept, 24)
            .await
            .unwrap()
            .len(),
        1,
        "the absorbed place's photo shows on its new place at once"
    );
    assert_eq!(
        content::descriptions_of_place(&pool, kept)
            .await
            .unwrap()
            .len(),
        1
    );
    content::set_hidden(&pool, "panoramax", &Hide::Place(kept), true)
        .await
        .unwrap();
    assert!(
        content::photos_of_place(&pool, kept, 24)
            .await
            .unwrap()
            .is_empty(),
        "hiding a source on a place hides what the places merged into it bring"
    );
    let purged = content::purge_gone_places(&pool).await.unwrap();
    assert_eq!(purged.removed, 2);
    assert_eq!(purged.orphaned_files, [files(7).thumb_path, files(7).path]);
    let again = content::places_due(&pool, due("panoramax", now - Duration::days(7)))
        .await
        .unwrap();
    assert!(
        again.iter().any(|p| p.id == kept),
        "the absorbing place is asked again: the records it took may lead to content"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn reviews_are_replaced_as_a_whole_and_an_author_stays_hidden(pool: PgPool) {
    let a = place(&pool, "A", 47.0, 2.0).await;
    let key = "ab".repeat(32);
    let review = |sig: &str, days: i64| NewReview {
        place_id: a,
        external_id: sig.to_owned(),
        rating: Some(4),
        text: Some("Calme.".into()),
        lang: None,
        author: Some("Surreality".into()),
        author_key: Some(key.clone()),
        written_at: Utc::now() - Duration::days(days),
        page_url: format!("https://mangrove.reviews/list?signature={sig}"),
        licence: "CC BY 4.0".into(),
        licence_url: "https://creativecommons.org/licenses/by/4.0/".into(),
        distance_m: Some(8.0),
    };
    let now = Utc::now();
    content::replace_reviews(
        &pool,
        "mangrove",
        &[review("old", 30), review("new", 1)],
        now,
    )
    .await
    .unwrap();
    let shown = content::reviews_of_place(&pool, a, 20).await.unwrap();
    assert_eq!(
        shown
            .iter()
            .map(|r| r.page_url.ends_with("new"))
            .collect::<Vec<_>>(),
        [true, false],
        "newest first"
    );
    content::set_hidden(&pool, "mangrove", &Hide::Author(key.clone()), true)
        .await
        .unwrap();
    // The author edits a review: a new signature, the same key.
    let r = content::replace_reviews(&pool, "mangrove", &[review("edited", 0)], now)
        .await
        .unwrap();
    assert_eq!(r.removed, 2, "a review gone from the source goes");
    assert!(
        content::reviews_of_place(&pool, a, 20)
            .await
            .unwrap()
            .is_empty(),
        "an author hidden once stays hidden through an edit or a new review"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn one_content_run_at_a_time(pool: PgPool) {
    let first = RunLock::try_acquire(&pool).await.unwrap().unwrap();
    assert!(
        RunLock::try_acquire(&pool).await.unwrap().is_none(),
        "a second run waits for the next week rather than sharing files"
    );
    first.release().await.unwrap();
    let again = RunLock::try_acquire(&pool).await.unwrap();
    assert!(again.is_some(), "a released lock is free");
}

async fn as_role(pool: &PgPool, set_role: &'static str) -> PgPool {
    PgPoolOptions::new()
        .max_connections(2)
        .after_connect(move |conn, _| {
            Box::pin(async move {
                sqlx::query(set_role).execute(conn).await?;
                Ok(())
            })
        })
        .connect_with((*pool.connect_options()).clone())
        .await
        .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_worker_writes_the_content_and_the_api_only_reads_it(pool: PgPool) {
    let a = place(&pool, "A", 47.0, 2.0).await;
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let now = Utc::now();
    content::replace_photos(&ingest, a, "panoramax", &[photo("p", "facing", 3)], now, 1)
        .await
        .expect("the content worker runs with the import role");
    content::purge_gone_places(&ingest).await.unwrap();
    content::set_hidden(&ingest, "panoramax", &Hide::Item("x".into()), true)
        .await
        .expect("the operator hides with the import role");
    assert_eq!(
        content::photos_of_place(&app, a, 24).await.unwrap().len(),
        1
    );
    content::descriptions_of_place(&app, a).await.unwrap();
    content::reviews_of_place(&app, a, 20).await.unwrap();
    let write = content::replace_photos(&app, a, "panoramax", &[], now, 0).await;
    assert!(write.is_err(), "the API never writes the open content");
    let hide = content::set_hidden(&app, "panoramax", &Hide::Source, true).await;
    assert!(hide.is_err(), "nor what is hidden");
}
