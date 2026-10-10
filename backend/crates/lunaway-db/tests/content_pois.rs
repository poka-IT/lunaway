//! The open content of the points of interest: a review or a photo hangs on
//! a place or on a point, the points due are those whose tags name
//! something, and a point's reviews and photos are hidden, reported and
//! purged as a place's.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::{Duration, TimeZone, Utc};
use lunaway_db::{
    PgPool,
    community::ReportOutcome,
    content::{self, ContentTarget, Hide, ItemKind, NewReview, PoiDueQuery},
    pois::{self, NewPoi},
};
use lunaway_domain::{
    Position, SourceId,
    community::ReportTarget,
    poi::{PoiKind, PoiRecord, PoiRefs},
};
use uuid::Uuid;

use crate::content::{account, as_role, photo, place, report};

/// Stores a point of OpenStreetMap and returns its id.
pub(crate) async fn poi(
    pool: &PgPool,
    external_id: &str,
    name: Option<&str>,
    (lat, lon): (f64, f64),
    refs: PoiRefs,
) -> Uuid {
    let mut r = PoiRecord::new(PoiKind::Bakery, Position::new(lat, lon).unwrap());
    r.name = name.map(str::to_owned);
    r.refs = refs;
    let raw = serde_json::value::to_raw_value(&serde_json::json!({})).unwrap();
    let at = Utc.with_ymd_and_hms(2026, 10, 5, 22, 0, 0).unwrap();
    pois::upsert(
        pool,
        &SourceId::OSM,
        &[NewPoi {
            external_id,
            external_url: None,
            record: &r,
            raw: &raw,
            fetched_at: at,
            scope: Some("FR"),
            in_tiles: false,
        }],
    )
    .await
    .unwrap();
    sqlx::query_scalar!(
        "SELECT id FROM pois WHERE source_id = 'osm' AND external_id = $1",
        external_id
    )
    .fetch_one(pool)
    .await
    .unwrap()
}

fn commons(file: &str) -> PoiRefs {
    PoiRefs {
        commons: Some(file.to_owned()),
        ..PoiRefs::default()
    }
}

fn review(target: ContentTarget, sig: &str, key: Option<String>) -> NewReview {
    NewReview {
        target,
        external_id: sig.to_owned(),
        rating: Some(5),
        text: Some("Le meilleur pain de la vallée.".into()),
        lang: None,
        author: Some("Surreality".into()),
        author_key: key,
        written_at: Utc::now(),
        page_url: format!("https://mangrove.reviews/list?signature={sig}"),
        licence: "CC BY 4.0".into(),
        licence_url: "https://creativecommons.org/licenses/by/4.0/".into(),
        distance_m: Some(4.0),
    }
}

async fn shown(pool: &PgPool, poi: Uuid) -> (usize, usize, usize) {
    let reviews = content::reviews_of_poi(pool, poi, 20, None)
        .await
        .unwrap()
        .nodes
        .len();
    let ratings = content::ratings_of_poi(pool, poi).await.unwrap().len();
    let photos = content::photos_of_poi(pool, poi, 4).await.unwrap().len();
    (reviews, ratings, photos)
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_review_or_a_photo_hangs_on_a_place_or_a_point_never_both_never_neither(pool: PgPool) {
    let a = place(&pool, "A", 47.0, 2.0).await;
    let b = poi(
        &pool,
        "node/1",
        Some("Boulangerie"),
        (47.0, 2.0),
        PoiRefs::default(),
    )
    .await;
    for (place_id, poi_id) in [(Some(a), Some(b)), (None, None)] {
        let err = sqlx::query(
            "INSERT INTO content_reviews (id, place_id, poi_id, source_id, external_id, rating, \
             written_at, page_url, licence, licence_url, fetched_at) \
             VALUES ($1, $2, $3, 'mangrove', 'sig', 4, now(), 'https://m.example', 'CC BY 4.0', \
             'https://c.example', now())",
        )
        .bind(Uuid::now_v7())
        .bind(place_id)
        .bind(poi_id)
        .execute(&pool)
        .await
        .unwrap_err();
        assert!(
            err.to_string().contains("content_reviews_one_target"),
            "{place_id:?} {poi_id:?}: {err}"
        );
    }
    content::replace_reviews(
        &pool,
        "mangrove",
        &[review(ContentTarget::Poi(b), "sig", None)],
        Utc::now(),
    )
    .await
    .expect("a review of a point alone is stored");
    content::replace_poi_photos(
        &pool,
        b,
        "wikimedia-commons",
        &[photo("File:Pain.jpg", "linked", 1)],
        Utc::now(),
        1,
    )
    .await
    .expect("a photo of a point alone is stored");
    let err = sqlx::query("UPDATE content_photos SET place_id = $1")
        .bind(a)
        .execute(&pool)
        .await
        .unwrap_err();
    assert!(
        err.to_string().contains("content_photos_one_target"),
        "{err}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_points_reviews_and_photos_are_hidden_like_a_places(pool: PgPool) {
    let bakery = poi(
        &pool,
        "node/1",
        Some("Boulangerie Dupont"),
        (45.0, 5.0),
        commons("File:Pain.jpg"),
    )
    .await;
    let other = place(&pool, "Aire du Lac", 45.1, 5.1).await;
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let key = "cd".repeat(32);
    content::replace_reviews(
        &ingest,
        "mangrove",
        &[
            review(ContentTarget::Poi(bakery), "sig-poi", Some(key.clone())),
            review(ContentTarget::Place(other), "sig-place", None),
        ],
        Utc::now(),
    )
    .await
    .expect("the content worker writes a point's reviews with the import role");
    content::replace_poi_photos(
        &ingest,
        bakery,
        "wikimedia-commons",
        &[photo("File:Pain.jpg", "linked", 1)],
        Utc::now(),
        1,
    )
    .await
    .expect("and its photos");
    assert_eq!(shown(&app, bakery).await, (1, 1, 1));
    assert_eq!(
        content::reviews_of_place(&app, other, 20, None)
            .await
            .unwrap()
            .nodes
            .len(),
        1,
        "the place keeps its own review"
    );
    assert!(
        content::review_pairs(&ingest, "mangrove")
            .await
            .unwrap()
            .contains(&(ContentTarget::Poi(bakery), key.clone())),
        "a key shown on a point holds its slot there, as on a place"
    );
    assert!(
        content::replace_poi_photos(&app, bakery, "wikimedia-commons", &[], Utc::now(), 0)
            .await
            .is_err(),
        "the API never writes the open content"
    );

    let review_id = content::reviews_of_poi(&app, bakery, 20, None)
        .await
        .unwrap()
        .nodes[0]
        .id;
    let item = content::item(&ingest, ItemKind::Review, review_id)
        .await
        .unwrap()
        .expect("`lunaway content hide review <id>` finds a point's review");
    assert_eq!(item.external_id, "sig-poi");

    for (hide, source, what) in [
        (
            Hide::Place(bakery),
            "mangrove",
            "everything the source shows on the point",
        ),
        (
            Hide::Author(key.clone()),
            "mangrove",
            "every review of one key",
        ),
        (
            Hide::Item(ItemKind::Review, "sig-poi".into()),
            "mangrove",
            "one review",
        ),
        (Hide::Source, "mangrove", "the whole source"),
    ] {
        content::set_hidden(&ingest, source, &hide, true)
            .await
            .unwrap();
        let (reviews, ratings, photos) = shown(&app, bakery).await;
        assert_eq!((reviews, ratings), (0, 0), "hidden: {what}");
        assert_eq!(photos, 1, "a hide of Mangrove leaves Commons alone: {what}");
        content::set_hidden(&ingest, source, &hide, false)
            .await
            .unwrap();
    }
    for hide in [
        Hide::Place(bakery),
        Hide::Item(ItemKind::Photo, "File:Pain.jpg".into()),
        Hide::Source,
    ] {
        content::set_hidden(&ingest, "wikimedia-commons", &hide, true)
            .await
            .unwrap();
        assert_eq!(shown(&app, bakery).await, (1, 1, 0), "{hide:?}");
        content::set_hidden(&ingest, "wikimedia-commons", &hide, false)
            .await
            .unwrap();
    }
    sqlx::query("INSERT INTO source_switches (source_id, hidden_at) VALUES ('mangrove', now())")
        .execute(&pool)
        .await
        .unwrap();
    assert_eq!(
        shown(&app, bakery).await,
        (0, 0, 1),
        "a source switched off shows nothing on a point"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn three_reports_hide_a_points_review_and_photo(pool: PgPool) {
    let bakery = poi(
        &pool,
        "node/1",
        Some("Boulangerie Dupont"),
        (45.0, 5.0),
        commons("File:Pain.jpg"),
    )
    .await;
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    content::replace_reviews(
        &pool,
        "mangrove",
        &[review(
            ContentTarget::Poi(bakery),
            "sig",
            Some("ab".repeat(32)),
        )],
        Utc::now(),
    )
    .await
    .unwrap();
    content::replace_poi_photos(
        &pool,
        bakery,
        "wikimedia-commons",
        &[photo("File:Pain.jpg", "linked", 1)],
        Utc::now(),
        1,
    )
    .await
    .unwrap();
    let review = content::reviews_of_poi(&app, bakery, 20, None)
        .await
        .unwrap()
        .nodes[0]
        .id;
    let photo_id = content::photos_of_poi(&app, bakery, 4).await.unwrap()[0].id;
    let reporters = [
        account(&app, 1).await,
        account(&app, 2).await,
        account(&app, 3).await,
    ];
    for (n, r) in reporters.iter().enumerate() {
        let outcome = report(&app, *r, ReportTarget::ExternalReview, review).await;
        let expected = if n == 2 {
            ReportOutcome::Hidden
        } else {
            ReportOutcome::Queued
        };
        assert_eq!(outcome, expected, "report {n} of a point's review");
    }
    assert_eq!(
        shown(&app, bakery).await,
        (0, 0, 1),
        "the third report hides the review"
    );
    for r in reporters {
        report(&app, r, ReportTarget::ExternalPhoto, photo_id).await;
    }
    assert_eq!(shown(&app, bakery).await, (0, 0, 0), "and the photo");
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_points_due_are_those_whose_tags_name_the_source(pool: PgPool) {
    let file = poi(
        &pool,
        "node/1",
        Some("Mairie"),
        (45.0, 5.0),
        commons("File:Mairie.jpg"),
    )
    .await;
    let item = poi(
        &pool,
        "node/2",
        None,
        (45.1, 5.0),
        PoiRefs {
            wikidata: Some("Q42".into()),
            ..PoiRefs::default()
        },
    )
    .await;
    let picture = poi(
        &pool,
        "node/3",
        Some("Café"),
        (45.2, 5.0),
        PoiRefs {
            panoramax: Some("d8dc9efb-d1b4-4a64-b948-f28bde76b202".into()),
            ..PoiRefs::default()
        },
    )
    .await;
    let bare = poi(
        &pool,
        "node/4",
        Some("Épicerie"),
        (45.3, 5.0),
        PoiRefs::default(),
    )
    .await;
    let gone = poi(
        &pool,
        "node/5",
        Some("Musée"),
        (45.4, 5.0),
        commons("File:Musée.jpg"),
    )
    .await;
    sqlx::query("UPDATE pois SET deleted_at = now() WHERE id = $1")
        .bind(gone)
        .execute(&pool)
        .await
        .unwrap();
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let commons_refs = ["commons".to_owned(), "wikidata".to_owned()];
    let panoramax_refs = ["panoramax".to_owned()];
    let week_ago = Utc::now() - Duration::days(7);
    let ids = |due: &[content::DuePoi]| due.iter().map(|p| p.id).collect::<Vec<_>>();
    let first = content::pois_due(&ingest, due("wikimedia-commons", &commons_refs, week_ago))
        .await
        .unwrap();
    assert_eq!(
        ids(&first),
        [file, item],
        "a Commons file or a Wikidata item, on a live point"
    );
    assert!(
        !ids(&first).contains(&bare),
        "never a point that names nothing"
    );
    assert_eq!(
        ids(
            &content::pois_due(&ingest, due("panoramax", &panoramax_refs, week_ago))
                .await
                .unwrap()
        ),
        [picture]
    );

    content::replace_poi_photos(&ingest, file, "wikimedia-commons", &[], Utc::now(), 0)
        .await
        .unwrap();
    content::mark_poi_checked(
        &ingest,
        item,
        "wikimedia-commons",
        week_ago - Duration::days(1),
        0,
    )
    .await
    .unwrap();
    let again = content::pois_due(&ingest, due("wikimedia-commons", &commons_refs, week_ago))
        .await
        .unwrap();
    assert_eq!(
        ids(&again),
        [item],
        "a point asked this week waits; one asked before is due again"
    );
    assert!(again[0].checked_at.is_some());
    let after = content::pois_due(
        &ingest,
        PoiDueQuery {
            after: Some(again[0].cursor()),
            ..due("wikimedia-commons", &commons_refs, week_ago)
        },
    )
    .await
    .unwrap();
    assert!(after.is_empty(), "a run goes on from where it stands");
}

fn due<'a>(source: &'a str, refs: &'a [String], before: chrono::DateTime<Utc>) -> PoiDueQuery<'a> {
    PoiDueQuery {
        source,
        refs,
        before,
        limit: 10,
        area: None,
        after: None,
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_points_photos_go_with_its_tag_and_with_the_point(pool: PgPool) {
    let tagged = poi(
        &pool,
        "node/1",
        Some("Mairie"),
        (45.0, 5.0),
        commons("File:Mairie.jpg"),
    )
    .await;
    let gone = poi(
        &pool,
        "node/2",
        Some("Musée"),
        (45.1, 5.0),
        commons("File:Musée.jpg"),
    )
    .await;
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    for (p, n) in [(tagged, 1), (gone, 2)] {
        content::replace_poi_photos(
            &ingest,
            p,
            "wikimedia-commons",
            &[photo(&format!("File:{n}.jpg"), "linked", n)],
            Utc::now(),
            1,
        )
        .await
        .unwrap();
    }
    content::replace_reviews(
        &ingest,
        "mangrove",
        &[review(ContentTarget::Poi(gone), "sig", None)],
        Utc::now(),
    )
    .await
    .unwrap();
    let refs = vec!["commons".to_owned(), "wikidata".to_owned()];
    let kept = content::purge_unlinked_pois(&ingest, "wikimedia-commons", &refs)
        .await
        .unwrap();
    assert_eq!(kept.removed, 0, "both points still name their file");

    // The tag goes from OpenStreetMap: the next import writes the point
    // without it.
    poi(
        &pool,
        "node/1",
        Some("Mairie"),
        (45.0, 5.0),
        PoiRefs::default(),
    )
    .await;
    let untagged = content::purge_unlinked_pois(&ingest, "wikimedia-commons", &refs)
        .await
        .unwrap();
    assert_eq!(untagged.removed, 1);
    assert_eq!(
        untagged.orphaned_files.len(),
        2,
        "the photo's two files go from the media store"
    );
    assert_eq!(
        content::photos_of_poi(&ingest, tagged, 4)
            .await
            .unwrap()
            .len(),
        0
    );

    sqlx::query("UPDATE pois SET deleted_at = now() WHERE id = $1")
        .bind(gone)
        .execute(&pool)
        .await
        .unwrap();
    let purged = content::purge_gone_pois(&ingest).await.unwrap();
    assert_eq!(purged.removed, 2, "the gone point's photo and review");
    let left: i64 = sqlx::query_scalar("SELECT count(*) FROM content_poi_checks")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(left, 0, "and their checks");
}

#[sqlx::test(migrations = "../../migrations")]
async fn only_the_import_role_keeps_the_checks_of_the_points(pool: PgPool) {
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let err = sqlx::query("SELECT 1 FROM content_poi_checks")
        .execute(&app)
        .await
        .unwrap_err();
    assert!(
        err.to_string().contains("permission denied"),
        "the API never reads the worker's progress: {err}"
    );
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let p = poi(
        &pool,
        "node/1",
        Some("Mairie"),
        (45.0, 5.0),
        commons("File:Mairie.jpg"),
    )
    .await;
    content::mark_poi_checked(&ingest, p, "wikimedia-commons", Utc::now(), 0)
        .await
        .expect("the content worker records its checks");
}
