//! The place queries the API serves: viewport, change feed, redirects,
//! search and sources.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::Utc;
use lunaway_db::{
    PgPool,
    conflation::{self, OpeningEval, PlaceWrite},
    places::{self, Change, PlaceFilter},
    records::{self, NewRecord},
};
use lunaway_domain::{
    Address, BBox, NormalizedRecord, OvernightStatus, PlaceKind, Position, Service, SourceId,
    conflation::PlaceContent,
};
use uuid::Uuid;

fn content(kind: PlaceKind, name: &str, lat: f64, lon: f64) -> PlaceContent {
    PlaceContent {
        name: Some(name.to_owned()),
        kind,
        position: Position::new(lat, lon).unwrap(),
        overnight: OvernightStatus::Unknown,
        services: Vec::new(),
        activities: Vec::new(),
        description: None,
        address: Address::default(),
        price_parking_eur: None,
        price_services_eur: None,
        max_height_m: None,
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
};

async fn put(pool: &PgPool, c: &PlaceContent) -> Uuid {
    let id = Uuid::now_v7();
    let mut tx = conflation::begin_writer(pool).await.unwrap();
    conflation::upsert_place(
        &mut tx,
        PlaceWrite {
            id,
            content: c,
            provenance: &[],
            opening: &NO_OPENING,
            content_hash: "h",
        },
    )
    .await
    .unwrap();
    tx.commit().await.unwrap();
    id
}

async fn tombstone(pool: &PgPool, id: Uuid, into: Option<Uuid>) {
    let mut tx = conflation::begin_writer(pool).await.unwrap();
    assert!(conflation::tombstone(&mut tx, id, into).await.unwrap());
    tx.commit().await.unwrap();
}

/// Around Angers.
fn anjou() -> BBox {
    BBox::new(47.2, -0.8, 47.6, -0.3).unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_viewport_filters_and_pages(pool: PgPool) {
    let a = put(
        &pool,
        &content(PlaceKind::Campsite, "Camping A", 47.40, -0.60),
    )
    .await;
    let mut b = content(PlaceKind::MotorhomeArea, "Aire B", 47.41, -0.61);
    b.services = vec![Service::DrinkingWater, Service::Electricity];
    b.overnight = OvernightStatus::Allowed;
    b.max_height_m = Some(3.5);
    let b = put(&pool, &b).await;
    let mut c = content(PlaceKind::Parking, "Parking C", 47.42, -0.62);
    c.max_height_m = Some(2.0);
    c.services = vec![Service::DrinkingWater];
    c.overnight = OvernightStatus::Tolerated;
    let c = put(&pool, &c).await;
    put(&pool, &content(PlaceKind::Campsite, "Far away", 43.3, 5.4)).await;
    let gone = put(&pool, &content(PlaceKind::Campsite, "Gone", 47.43, -0.63)).await;
    tombstone(&pool, gone, None).await;

    let all = PlaceFilter::default();
    let page1 = places::in_bbox(&pool, anjou(), &all, 2, None)
        .await
        .unwrap();
    assert_eq!(
        page1.total_count, 3,
        "the tombstone and the place outside do not count"
    );
    assert!(page1.has_next_page);
    let ids1: Vec<Uuid> = page1.nodes.iter().map(|p| p.id).collect();
    assert_eq!(
        ids1,
        [a, b],
        "pages follow the ids, which are UUID v7 in creation order"
    );
    let page2 = places::in_bbox(&pool, anjou(), &all, 2, Some(b))
        .await
        .unwrap();
    assert_eq!(page2.nodes.iter().map(|p| p.id).collect::<Vec<_>>(), [c]);
    assert!(!page2.has_next_page);

    let ids = |f: PlaceFilter| {
        let pool = pool.clone();
        async move {
            places::in_bbox(&pool, anjou(), &f, 50, None)
                .await
                .unwrap()
                .nodes
                .iter()
                .map(|p| p.id)
                .collect::<Vec<_>>()
        }
    };
    assert_eq!(
        ids(PlaceFilter {
            kinds: Some(vec![PlaceKind::Parking, PlaceKind::MotorhomeArea]),
            ..all.clone()
        })
        .await,
        [b, c]
    );
    assert_eq!(
        ids(PlaceFilter {
            services: vec![Service::DrinkingWater, Service::Electricity],
            ..all.clone()
        })
        .await,
        [b],
        "a place must have every requested service"
    );
    assert_eq!(
        ids(PlaceFilter {
            overnight_ok: true,
            ..all.clone()
        })
        .await,
        [b, c]
    );
    assert_eq!(
        ids(PlaceFilter {
            vehicle_height_m: Some(2.5),
            ..all.clone()
        })
        .await,
        [a, b],
        "a 2.0 m limit excludes a 2.5 m vehicle; an unknown limit does not"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_change_feed_pages_by_cursor_and_reports_deletions(pool: PgPool) {
    let a = put(&pool, &content(PlaceKind::Campsite, "A", 47.40, -0.60)).await;
    let b = put(&pool, &content(PlaceKind::Campsite, "B", 47.41, -0.60)).await;
    let c = put(&pool, &content(PlaceKind::Campsite, "C", 47.42, -0.60)).await;
    put(&pool, &content(PlaceKind::Campsite, "Outside", 43.3, 5.4)).await;

    let (first, more) = places::changes(&pool, anjou(), 0, 2, false).await.unwrap();
    assert!(more);
    let ids: Vec<Uuid> = first
        .iter()
        .map(|ch| match ch {
            Change::Upsert(p) => p.id,
            Change::Delete { id, .. } => *id,
        })
        .collect();
    assert_eq!(ids, [a, b]);
    let cursor = first.last().unwrap().seq();
    let (rest, more) = places::changes(&pool, anjou(), cursor, 2, false)
        .await
        .unwrap();
    assert!(!more);
    assert_eq!(rest.len(), 1);
    let cursor = rest[0].seq();

    tombstone(&pool, b, Some(c)).await;
    let (after, _) = places::changes(&pool, anjou(), cursor, 10, true)
        .await
        .unwrap();
    assert!(
        matches!(after.as_slice(), [Change::Delete { id, .. }] if *id == b),
        "a deletion after the cursor is reported: {after:?}"
    );
    let (initial, _) = places::changes(&pool, anjou(), 0, 10, false).await.unwrap();
    assert_eq!(initial.len(), 2, "a first sync gets the live places only");
    assert!(places::last_seq(&pool).await.unwrap() > cursor);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_merged_place_redirects_to_the_place_that_absorbed_it(pool: PgPool) {
    let a = put(&pool, &content(PlaceKind::Campsite, "A", 47.40, -0.60)).await;
    let b = put(&pool, &content(PlaceKind::Campsite, "B", 47.41, -0.60)).await;
    let c = put(&pool, &content(PlaceKind::Campsite, "C", 47.42, -0.60)).await;
    tombstone(&pool, a, Some(b)).await;
    tombstone(&pool, b, Some(c)).await;
    assert_eq!(
        places::by_id(&pool, a).await.unwrap().map(|p| p.id),
        Some(c),
        "redirects chain"
    );
    let d = put(&pool, &content(PlaceKind::Campsite, "D", 47.43, -0.60)).await;
    tombstone(&pool, d, None).await;
    assert!(
        places::by_id(&pool, d).await.unwrap().is_none(),
        "deleted without a successor"
    );
    assert!(
        places::by_id(&pool, Uuid::now_v7())
            .await
            .unwrap()
            .is_none()
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn search_ignores_accents_tolerates_typos_and_prefers_the_nearest(pool: PgPool) {
    let mut chat = content(PlaceKind::Campsite, "Camping des Châtaigniers", 45.43, 4.39);
    chat.address.city = Some("Saint-Étienne".into());
    let chat = put(&pool, &chat).await;
    let brad = put(
        &pool,
        &content(PlaceKind::Campsite, "Camping de la Bradière", 47.42, -0.66),
    )
    .await;
    let lac_annecy = put(
        &pool,
        &content(PlaceKind::Campsite, "Camping du Lac", 45.86, 6.17),
    )
    .await;
    let lac_nantes = put(
        &pool,
        &content(PlaceKind::Campsite, "Camping du Lac", 47.25, -1.52),
    )
    .await;
    let gone = put(
        &pool,
        &content(PlaceKind::Campsite, "Camping des Châtaigniers", 45.0, 4.0),
    )
    .await;
    tombstone(&pool, gone, None).await;

    let ids = |r: Vec<places::PlaceRow>| r.iter().map(|p| p.id).collect::<Vec<_>>();
    assert_eq!(
        ids(places::search(&pool, "chataigniers", None, 20)
            .await
            .unwrap()),
        [chat]
    );
    assert_eq!(
        ids(places::search(&pool, "CHÂTAIGNIERS", None, 20)
            .await
            .unwrap()),
        [chat],
        "case and accents fold on both sides"
    );
    assert_eq!(
        ids(places::search(&pool, "bradere", None, 20).await.unwrap()),
        [brad],
        "a missing letter"
    );
    assert_eq!(
        ids(places::search(&pool, "saint etienne", None, 20)
            .await
            .unwrap()),
        [chat],
        "the municipality counts"
    );
    let nantes = Position::new(47.22, -1.55).unwrap();
    let annecy = Position::new(45.90, 6.12).unwrap();
    // Both "Camping du Lac" match fully, the nearer first; other campsites
    // share "camping d" and come after them.
    let from_nantes = ids(places::search(&pool, "camping du lac", Some(nantes), 20)
        .await
        .unwrap());
    assert_eq!(from_nantes[..2], [lac_nantes, lac_annecy]);
    let from_annecy = ids(places::search(&pool, "camping du lac", Some(annecy), 20)
        .await
        .unwrap());
    assert_eq!(from_annecy[..2], [lac_annecy, lac_nantes]);
    assert!(from_annecy.len() <= 4 && !from_annecy.contains(&gone));
    assert_eq!(
        places::search_threshold("lac"),
        0.6,
        "short queries stay strict"
    );
    assert_eq!(places::search_threshold("bradere"), 0.5);
    assert!(
        places::search(&pool, "zzzzqqq", None, 20)
            .await
            .unwrap()
            .is_empty()
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_sources_of_many_places_come_in_one_query(pool: PgPool) {
    let raw = serde_json::json!({});
    let at = Utc::now();
    let r = NormalizedRecord::new(PlaceKind::Campsite, Position::new(47.4, -0.6).unwrap());
    let osm = [NewRecord {
        external_id: "way/1",
        external_url: Some("https://www.openstreetmap.org/way/1"),
        record: &r,
        raw: &raw,
        fetched_at: at,
    }];
    let af = [NewRecord {
        external_id: "49170:x:y",
        external_url: None,
        record: &r,
        raw: &raw,
        fetched_at: at,
    }];
    records::upsert(&pool, &SourceId::OSM, None, &osm)
        .await
        .unwrap();
    records::upsert(&pool, &SourceId::ATOUT_FRANCE, None, &af)
        .await
        .unwrap();
    let r1 = records::id_of(&pool, &SourceId::OSM, "way/1")
        .await
        .unwrap()
        .unwrap();
    let r2 = records::id_of(&pool, &SourceId::ATOUT_FRANCE, "49170:x:y")
        .await
        .unwrap()
        .unwrap();
    let p = put(&pool, &content(PlaceKind::Campsite, "P", 47.4, -0.6)).await;
    let mut tx = conflation::begin_writer(&pool).await.unwrap();
    conflation::relink(
        &mut tx,
        &[r1, r2],
        &[(r1, p, Some(0.97)), (r2, p, Some(0.97))],
    )
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let rows = places::sources_of(&pool, &[p, Uuid::now_v7()])
        .await
        .unwrap();
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[0].source_id, SourceId::ATOUT_FRANCE);
    assert_eq!(rows[0].licence, "Licence Ouverte 2.0");
    assert_eq!(rows[1].source_id, SourceId::OSM);
    assert_eq!(
        rows[1].external_url.as_deref(),
        Some("https://www.openstreetmap.org/way/1")
    );
    assert_eq!(rows[1].match_score, Some(0.97));
}
