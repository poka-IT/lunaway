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
    municipalities::{self, Municipality},
    places::{self, Change, PlaceFilter},
    records::{self, NewRecord},
    search,
};
use lunaway_domain::{
    Address, BBox, NormalizedRecord, OvernightStatus, PlaceKind, Position, Service, SourceId,
    conflation::PlaceContent, search::LookupPath,
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
    b.max_length_m = Some(8.0);
    let b = put(&pool, &b).await;
    let mut c = content(PlaceKind::Parking, "Parking C", 47.42, -0.62);
    c.max_height_m = Some(2.0);
    c.max_width_m = Some(2.2);
    c.max_weight_t = Some(3.5);
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
    assert_eq!(
        ids(PlaceFilter {
            vehicle_length_m: Some(9.0),
            ..all.clone()
        })
        .await,
        [a, c],
        "an 8 m limit excludes a 9 m vehicle; an unknown length does not"
    );
    assert_eq!(
        ids(PlaceFilter {
            vehicle_width_m: Some(2.35),
            vehicle_weight_t: Some(3.0),
            ..all.clone()
        })
        .await,
        [a, b],
        "a 2.2 m width excludes a 2.35 m vehicle, whatever its weight"
    );
    assert_eq!(
        ids(PlaceFilter {
            vehicle_weight_t: Some(4.5),
            ..all.clone()
        })
        .await,
        [a, b],
        "a 3.5 t limit excludes a 4.5 t vehicle"
    );
    let read = places::by_id(&pool, b).await.unwrap().unwrap();
    assert_eq!(
        (read.max_length_m, read.max_width_m, read.max_weight_t),
        (Some(8.0), None, None),
        "the limits a place states are read back"
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
            Change::Delete { id, .. } | Change::Left { id, .. } => *id,
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
        ids(search::search(&pool, "chataigniers", None, 20)
            .await
            .unwrap()),
        [chat]
    );
    assert_eq!(
        ids(search::search(&pool, "CHÂTAIGNIERS", None, 20)
            .await
            .unwrap()),
        [chat],
        "case and accents fold on both sides"
    );
    assert_eq!(
        ids(search::search(&pool, "bradere", None, 20).await.unwrap()),
        [brad],
        "a missing letter"
    );
    assert_eq!(
        ids(search::search(&pool, "saint etienne", None, 20)
            .await
            .unwrap()),
        [chat],
        "the municipality counts"
    );
    let nantes = Position::new(47.22, -1.55).unwrap();
    let annecy = Position::new(45.90, 6.12).unwrap();
    // Both "Camping du Lac" match fully, the nearer first; other campsites
    // share "camping d" and come after them.
    let from_nantes = ids(search::search(&pool, "camping du lac", Some(nantes), 20)
        .await
        .unwrap());
    assert_eq!(from_nantes[..2], [lac_nantes, lac_annecy]);
    let from_annecy = ids(search::search(&pool, "camping du lac", Some(annecy), 20)
        .await
        .unwrap());
    assert_eq!(from_annecy[..2], [lac_annecy, lac_nantes]);
    assert!(from_annecy.len() <= 4 && !from_annecy.contains(&gone));
    assert!(
        search::search(&pool, "zzzzqqq", None, 20)
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
        scope: None,
    }];
    let af = [NewRecord {
        external_id: "49170:x:y",
        external_url: None,
        record: &r,
        raw: &raw,
        fetched_at: at,
        scope: None,
    }];
    records::upsert(&pool, &SourceId::OSM, &osm).await.unwrap();
    records::upsert(&pool, &SourceId::ATOUT_FRANCE, &af)
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

/// A square commune around a point, half a side of `half` degrees.
fn square(code: &str, name: &str, lat: f64, lon: f64, half: f64) -> Municipality {
    let ring = serde_json::json!([[
        [lon - half, lat - half],
        [lon + half, lat - half],
        [lon + half, lat + half],
        [lon - half, lat + half],
        [lon - half, lat - half]
    ]]);
    Municipality {
        code: code.to_owned(),
        name: name.to_owned(),
        geometry: serde_json::json!({"type": "Polygon", "coordinates": ring}),
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_communes_of_more_places_than_a_batch_are_written_a_thousand_at_a_time(pool: PgPool) {
    // 2 500 French places in one commune: statements of a thousand places
    // at most, as the filter ratings, whose single statement over every
    // place ran into the statement timeout on production (2026-10-08).
    sqlx::query(
        "INSERT INTO places (id, kind, geom, overnight, content_hash, country_code) \
         SELECT gen_random_uuid(), 'parking', \
                ST_SetSRID(ST_MakePoint(6.1 + i * 0.00001, 45.9), 4326)::geography, \
                'allowed', 'x', 'FR' \
         FROM generate_series(1, 2500) AS i",
    )
    .execute(&pool)
    .await
    .unwrap();
    // Each statement's rows, as the trigger of the search's words sees them.
    sqlx::raw_sql(
        "CREATE TABLE statement_rows (n bigint NOT NULL);
         CREATE FUNCTION count_statement_rows() RETURNS trigger LANGUAGE plpgsql AS $$
         BEGIN INSERT INTO statement_rows SELECT count(*) FROM written; RETURN NULL; END $$;
         CREATE TRIGGER count_statement_rows AFTER UPDATE ON places
             REFERENCING NEW TABLE AS written
             FOR EACH STATEMENT EXECUTE FUNCTION count_statement_rows();",
    )
    .execute(&pool)
    .await
    .unwrap();
    let mut tx = conflation::begin_writer(&pool).await.unwrap();
    let stats = municipalities::replace_all(
        &mut tx,
        &[square("74010", "Annecy", 45.9, 6.12, 0.05)],
        Utc::now(),
    )
    .await
    .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(stats.places_changed, 2_500);
    let statements: Vec<i64> = sqlx::query_scalar("SELECT n FROM statement_rows ORDER BY n DESC")
        .fetch_all(&pool)
        .await
        .unwrap();
    assert_eq!(
        statements,
        [1_000, 1_000, 500],
        "a thousand rows a statement: one statement of every place joins its rows quadratically"
    );
    let without: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM places \
         WHERE municipality IS DISTINCT FROM 'Annecy' OR municipality_code IS DISTINCT FROM '74010'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(without, 0, "every batch wrote its places");
    let mut tx = conflation::begin_writer(&pool).await.unwrap();
    assert_eq!(
        municipalities::refresh_places(&mut tx).await.unwrap(),
        0,
        "and nothing is left to write"
    );
    tx.commit().await.unwrap();

    // The commune gone (a new year's file without it): every place loses
    // it, a null name and code written through the same batches.
    let before = places::last_seq(&pool).await.unwrap();
    let mut tx = conflation::begin_writer(&pool).await.unwrap();
    let stats = municipalities::replace_all(&mut tx, &[], Utc::now())
        .await
        .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(stats.places_changed, 2_500);
    let still: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM places WHERE municipality IS NOT NULL OR municipality_code IS NOT NULL \
         OR updated_seq <= $1",
    )
    .bind(before)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        still, 0,
        "every place lost its commune and moved in the feed, so devices drop the name"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_town_s_name_finds_its_places_before_names_that_share_letters(pool: PgPool) {
    // The places of the production report: "annecy" listed spots that only
    // share "anne", and missed the car park of Annecy whose sources give no
    // town.
    let colmyr = put(
        &pool,
        &content(
            PlaceKind::MotorhomeArea,
            "Aire de stationnement camping-cars de Colmyr",
            45.8907,
            6.1388,
        ),
    )
    .await;
    let mut belvedere = content(PlaceKind::Campsite, "Le Belvédère", 45.8911, 6.1313);
    belvedere.address.city = Some("Annecy".into());
    let belvedere = put(&pool, &belvedere).await;
    let mut sainte_anne = content(PlaceKind::Campsite, "Sainte-Anne", 46.34, -1.39);
    sainte_anne.address.city = Some("La Tranche-sur-Mer".into());
    let sainte_anne = put(&pool, &sainte_anne).await;
    let annexe = put(
        &pool,
        &content(PlaceKind::Campsite, "Houx Annexe", 47.95, 0.21),
    )
    .await;
    let mut anneyron = content(PlaceKind::Campsite, "Camping la Châtaigneraie", 45.27, 4.88);
    anneyron.address.city = Some("Anneyron".into());
    let anneyron = put(&pool, &anneyron).await;

    let ids = |r: Vec<places::PlaceRow>| r.iter().map(|p| p.id).collect::<Vec<_>>();
    let before = places::last_seq(&pool).await.unwrap();
    assert_eq!(
        ids(search::search(&pool, "annecy", None, 20).await.unwrap()),
        [belvedere],
        "before the communes are loaded only the address names the town, and a word that \
         shares four letters is not a match"
    );

    let mut tx = conflation::begin_writer(&pool).await.unwrap();
    let stats = municipalities::replace_all(
        &mut tx,
        &[
            square("74010", "Annecy", 45.9, 6.13, 0.05),
            square("85294", "La Tranche-sur-Mer", 46.34, -1.39, 0.05),
        ],
        chrono::Utc::now(),
    )
    .await
    .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(stats.municipalities, 2);
    assert_eq!(
        stats.places_changed, 3,
        "Colmyr, the Belvédère and Sainte-Anne lie in them"
    );
    let colmyr_row = places::by_id(&pool, colmyr).await.unwrap().unwrap();
    assert_eq!(colmyr_row.municipality.as_deref(), Some("Annecy"));
    assert!(
        colmyr_row.updated_seq > before,
        "a place that learns its commune moves in the feed, so devices receive it"
    );

    let near_annecy = Position::new(45.9, 6.12).unwrap();
    let found = ids(search::search(&pool, "annecy", Some(near_annecy), 20)
        .await
        .unwrap());
    assert_eq!(found.len(), 2, "{found:?}");
    assert!(found.contains(&colmyr) && found.contains(&belvedere));
    assert!(
        !found.contains(&sainte_anne) && !found.contains(&annexe) && !found.contains(&anneyron)
    );

    let anne = ids(search::search(&pool, "anne", None, 20).await.unwrap());
    assert_eq!(
        anne.first(),
        Some(&sainte_anne),
        "the whole word comes before the words it begins: {anne:?}"
    );
    let prefix_rank = |id| anne.iter().position(|x| *x == id).unwrap();
    assert!(
        prefix_rank(colmyr) > 0 && prefix_rank(anneyron) > 0 && prefix_rank(annexe) > 0,
        "Annecy, Anneyron and Annexe begin with the word"
    );

    // A place written after the load takes its commune when the conflation
    // writes it.
    let later = put(
        &pool,
        &content(PlaceKind::Parking, "Parking du Pâquier", 45.9, 6.125),
    )
    .await;
    assert_eq!(
        places::by_id(&pool, later)
            .await
            .unwrap()
            .unwrap()
            .municipality
            .as_deref(),
        Some("Annecy")
    );
}

fn ids(rows: Vec<places::PlaceRow>) -> Vec<Uuid> {
    rows.into_iter().map(|p| p.id).collect()
}

#[sqlx::test(migrations = "../../migrations")]
async fn generic_words_rank_the_places_a_name_finds_and_never_filter_them(pool: PgPool) {
    let camping = put(
        &pool,
        &content(PlaceKind::Campsite, "Camping du Lac", 45.86, 6.17),
    )
    .await;
    let aire = put(
        &pool,
        &content(PlaceKind::MotorhomeArea, "Aire du Lac", 45.87, 6.18),
    )
    .await;
    let parking = put(&pool, &content(PlaceKind::Parking, "Le Lac", 45.88, 6.16)).await;
    let pins = put(
        &pool,
        &content(PlaceKind::Campsite, "Camping des Pins", 45.85, 6.15),
    )
    .await;

    let found = ids(search::search(&pool, "camping du lac", None, 20)
        .await
        .unwrap());
    assert_eq!(
        found.first(),
        Some(&camping),
        "the whole name first: {found:?}"
    );
    assert!(
        found.contains(&aire) && found.contains(&parking),
        "the lake's other places match without the generic words: {found:?}"
    );
    assert!(
        !found.contains(&pins),
        "a generic word alone does not make a place match a name: {found:?}"
    );

    let near = Position::new(45.87, 6.18).unwrap();
    assert_eq!(
        ids(search::search(&pool, "camping", Some(near), 20)
            .await
            .unwrap()),
        [camping, pins],
        "a kind word around a point: the campsites, nearest first"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_query_of_kind_words_lists_the_nearest_places_of_that_kind(pool: PgPool) {
    let mut unnamed = content(PlaceKind::Parking, "x", 47.20, -1.55);
    unnamed.name = None;
    let unnamed = put(&pool, &unnamed).await;
    let port = put(
        &pool,
        &content(PlaceKind::Parking, "Parking du Port", 47.25, -1.55),
    )
    .await;
    let area = put(
        &pool,
        &content(
            PlaceKind::MotorhomeArea,
            "Parking des camping-cars",
            47.21,
            -1.55,
        ),
    )
    .await;
    let far = put(
        &pool,
        &content(PlaceKind::Parking, "Parking de la Gare", 48.85, 2.35),
    )
    .await;
    let nantes = Position::new(47.2, -1.55).unwrap();
    assert_eq!(
        ids(search::search(&pool, "parking", Some(nantes), 20)
            .await
            .unwrap()),
        [unnamed, port, far],
        "the car parks nearest first, named so or not; a motorhome area named after car parks \
         is no car park"
    );
    assert_eq!(
        ids(search::search(&pool, "parking", None, 20).await.unwrap()),
        [port, far, area],
        "without a point, by name, the car parks before the place of another kind"
    );
    let areas = ids(
        search::search(&pool, "aire de camping car", Some(nantes), 20)
            .await
            .unwrap(),
    );
    assert_eq!(
        areas,
        [area],
        "\"camping car\" names the motorhome areas, whatever their name says"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_word_no_place_starts_with_finds_the_word_it_was_meant_to_be(pool: PgPool) {
    let mut arolles = content(PlaceKind::Campsite, "Les Arolles", 45.92, 6.87);
    arolles.address.city = Some("Chamonix-Mont-Blanc".into());
    let arolles = put(&pool, &arolles).await;
    let chamois = put(
        &pool,
        &content(PlaceKind::Campsite, "Le Chamois", 44.9, 6.4),
    )
    .await;
    let annecy = Position::new(45.9, 6.15).unwrap();
    assert_eq!(
        ids(search::search(&pool, "chamonis", Some(annecy), 20)
            .await
            .unwrap()),
        [arolles, chamois],
        "both words are one edit away; the nearer place first"
    );
    let port = put(
        &pool,
        &content(PlaceKind::Parking, "Parking du Port", 47.1, 2.0),
    )
    .await;
    let later = put(
        &pool,
        &content(PlaceKind::Parking, "Parking des Grillons", 47.0, 2.0),
    )
    .await;
    assert_eq!(
        ids(search::search(&pool, "grilons", None, 20).await.unwrap()),
        [later],
        "the words of a place written later are corrected to as well"
    );
    tombstone(&pool, later, None).await;
    let words: Vec<String> = sqlx::query_scalar("SELECT word FROM place_search_words")
        .fetch_all(&pool)
        .await
        .unwrap();
    assert!(
        !words.contains(&"grillons".to_owned()) && words.contains(&"parking".to_owned()),
        "a word no live place holds leaves, one another place holds stays: {words:?}"
    );
    assert_eq!(
        ids(search::search(&pool, "parking", None, 20).await.unwrap()),
        [port],
        "a word the gone place shared is still a word, not a typo"
    );
    assert_eq!(
        ids(search::search(&pool, "gerrardm", None, 20).await.unwrap()),
        Vec::<Uuid>::new(),
        "nothing within reach, nothing found"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn every_way_of_finding_the_candidates_ranks_the_same_places(pool: PgPool) {
    for (i, (kind, name)) in [
        (PlaceKind::Campsite, "Camping du Lac"),
        (PlaceKind::MotorhomeArea, "Aire du Lac"),
        (PlaceKind::Parking, "Lac Bleu"),
        (PlaceKind::Campsite, "Camping des Pins"),
        (PlaceKind::Campsite, "Camping du Lac"),
    ]
    .into_iter()
    .enumerate()
    {
        let offset = f64::from(u8::try_from(i).unwrap()) * 0.3;
        put(&pool, &content(kind, name, 45.0 + offset, 6.0)).await;
    }
    let near = Position::new(45.4, 6.0).unwrap();
    for (text, matching) in [("lac", 4), ("camping du lac", 4), ("lac bl", 1)] {
        let index = ids(
            search::search_by_path(&pool, text, Some(near), 20, LookupPath::Index)
                .await
                .unwrap(),
        );
        assert_eq!(index.len(), matching, "{text}");
        for path in [LookupPath::Nearest, LookupPath::Scan] {
            assert_eq!(
                ids(search::search_by_path(&pool, text, Some(near), 20, path)
                    .await
                    .unwrap()),
                index,
                "{text}, {path:?}: the ways differ in cost, not in what they rank"
            );
        }
        assert_eq!(
            ids(search::search(&pool, text, Some(near), 20).await.unwrap()),
            index,
            "{text}: the way the search picks"
        );
    }
}

/// A place of `kind` named `name` (none for `None`) whose address names
/// `city`.
fn in_town(kind: PlaceKind, name: Option<&str>, city: &str, lat: f64, lon: f64) -> PlaceContent {
    let mut c = content(kind, name.unwrap_or_default(), lat, lon);
    c.name = name.map(str::to_owned);
    c.address.city = Some(city.to_owned());
    c
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_town_the_text_names_and_the_names_that_carry_it_come_before_longer_towns(
    pool: PgPool,
) {
    // The audit of 2026-10-10 searched "Viviers" from the middle of France:
    // the places of Chapelle-Viviers and Torcé-Viviers-en-Charnie, nearer,
    // came first, and Viviers's motorhome area 19th of 20.
    let mut tx = conflation::begin_writer(&pool).await.unwrap();
    municipalities::replace_all(
        &mut tx,
        &[square("07346", "Viviers", 44.487, 4.68, 0.03)],
        Utc::now(),
    )
    .await
    .unwrap();
    tx.commit().await.unwrap();
    let area = put(
        &pool,
        &in_town(
            PlaceKind::MotorhomeArea,
            Some("Camping-car Park Viviers"),
            "Viviers",
            44.4823,
            4.6802,
        ),
    )
    .await;
    // Unnamed, and its address names no town: it lies in Viviers by its
    // commune alone.
    let mut parking = content(PlaceKind::Parking, "x", 44.4926, 4.6788);
    parking.name = None;
    let parking = put(&pool, &parking).await;
    let mouchet = put(
        &pool,
        &in_town(
            PlaceKind::Campsite,
            Some("Camping du Mouchet"),
            "Chapelle-Viviers",
            46.4839,
            0.7352,
        ),
    )
    .await;
    let torce = put(
        &pool,
        &in_town(
            PlaceKind::Parking,
            None,
            "Torcé-Viviers-en-Charnie",
            48.0921,
            -0.2569,
        ),
    )
    .await;
    let lege = put(
        &pool,
        &in_town(
            PlaceKind::Campsite,
            Some("Les Viviers"),
            "Lège-Cap-Ferret",
            44.79,
            -1.2,
        ),
    )
    .await;
    let middle = Position::new(46.6, 2.5).unwrap();
    assert_eq!(
        ids(search::search(&pool, "Viviers", Some(middle), 20)
            .await
            .unwrap()),
        [area, lege, parking, mouchet, torce],
        "the place named after Viviers in Viviers first; then a place named so elsewhere; then \
         Viviers's unnamed car park, which no name of it puts first; then the towns whose \
         longer name holds the word, nearest first"
    );
    assert_eq!(
        ids(search::search(&pool, "vivier", Some(middle), 20)
            .await
            .unwrap())
        .first(),
        Some(&mouchet),
        "a word being typed is no town's nor name's word yet: the nearest first"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_place_two_sources_put_kilometres_apart_is_listed_once(pool: PgPool) {
    // Chapelle-Viviers, 2026-10-10: OpenStreetMap maps the campsite,
    // Atout France places it 2.5 km away by its postal address, past the
    // reach of the conflation; the search listed it twice.
    let mut tx = conflation::begin_writer(&pool).await.unwrap();
    municipalities::replace_all(
        &mut tx,
        &[square("86059", "Chapelle-Viviers", 46.47, 0.73, 0.05)],
        Utc::now(),
    )
    .await
    .unwrap();
    tx.commit().await.unwrap();
    let raw = serde_json::json!({});
    let at = Utc::now();
    let precise = NormalizedRecord::new(PlaceKind::Campsite, Position::new(46.47, 0.73).unwrap());
    // Atout France's accuracy for a campsite placed by its postal address.
    let mut by_address = precise.clone();
    by_address.accuracy_m = 250.0;
    let record = |external_id, record| NewRecord {
        external_id,
        external_url: None,
        record,
        raw: &raw,
        fetched_at: at,
        scope: None,
    };
    records::upsert(
        &pool,
        &SourceId::OSM,
        &[
            record("way/216786156", &precise),
            record("node/1", &precise),
            record("node/2", &precise),
            record("node/3", &precise),
        ],
    )
    .await
    .unwrap();
    records::upsert(
        &pool,
        &SourceId::ATOUT_FRANCE,
        &[record(
            "86300:chapelle-viviers:camping-du-mouchet",
            &by_address,
        )],
    )
    .await
    .unwrap();
    records::upsert(&pool, &SourceId::COMMUNITY, &[record("pins", &precise)])
        .await
        .unwrap();
    let id_of = async |source: &SourceId, external_id: &str| {
        records::id_of(&pool, source, external_id)
            .await
            .unwrap()
            .unwrap()
    };
    let at_place = |lat, lon, name| content(PlaceKind::Campsite, name, lat, lon);
    let osm = put(&pool, &at_place(46.4839, 0.7352, "Camping du Mouchet")).await;
    let af = put(&pool, &at_place(46.4620, 0.7255, "Camping du Mouchet")).await;
    // Two car parks of one source and one name, a kilometre apart: the
    // source lists them apart, two places.
    let first = put(
        &pool,
        &content(PlaceKind::Parking, "Parking du Mouchet", 46.48, 0.74),
    )
    .await;
    let second = put(
        &pool,
        &content(PlaceKind::Parking, "Parking du Mouchet", 46.47, 0.745),
    )
    .await;
    // Two campsites of one name pinned precisely 2 km apart by two
    // sources, and two whose records are not known: two places each.
    let osm_pins = put(&pool, &at_place(46.49, 0.70, "Camping des Pins")).await;
    let community_pins = put(&pool, &at_place(46.47, 0.71, "Camping des Pins")).await;
    let moulin = put(&pool, &at_place(46.49, 0.72, "Camping du Moulin")).await;
    let other_moulin = put(&pool, &at_place(46.47, 0.72, "Camping du Moulin")).await;
    let links = [
        (id_of(&SourceId::OSM, "way/216786156").await, osm),
        (
            id_of(
                &SourceId::ATOUT_FRANCE,
                "86300:chapelle-viviers:camping-du-mouchet",
            )
            .await,
            af,
        ),
        (id_of(&SourceId::OSM, "node/1").await, first),
        (id_of(&SourceId::OSM, "node/2").await, second),
        (id_of(&SourceId::OSM, "node/3").await, osm_pins),
        (id_of(&SourceId::COMMUNITY, "pins").await, community_pins),
    ];
    let mut tx = conflation::begin_writer(&pool).await.unwrap();
    conflation::relink(
        &mut tx,
        &links.iter().map(|(r, _)| *r).collect::<Vec<_>>(),
        &links
            .iter()
            .map(|(r, p)| (*r, *p, None))
            .collect::<Vec<_>>(),
    )
    .await
    .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(
        places::by_id(&pool, af)
            .await
            .unwrap()
            .unwrap()
            .municipality
            .as_deref(),
        Some("Chapelle-Viviers"),
        "the two places of the campsite lie in one commune"
    );

    let near = Position::new(46.49, 0.74).unwrap();
    assert_eq!(
        ids(search::search(&pool, "mouchet", Some(near), 20)
            .await
            .unwrap()),
        [osm, first, second],
        "the campsite once, as the nearer of its two places; both car parks"
    );
    assert_eq!(
        ids(search::search(
            &pool,
            "mouchet",
            Some(Position::new(46.46, 0.72).unwrap()),
            20
        )
        .await
        .unwrap()),
        [af, second, first],
        "from beside the other point, that one is kept and the first told leaves"
    );
    assert_eq!(
        ids(search::search(&pool, "camping mouchet", Some(near), 2)
            .await
            .unwrap()),
        [osm, first],
        "the place told twice leaves the list, which still holds as many places as asked"
    );
    let pins = ids(search::search(&pool, "pins", Some(near), 20).await.unwrap());
    assert!(
        pins.contains(&osm_pins) && pins.contains(&community_pins),
        "two campsites pinned precisely 2 km apart are two: {pins:?}"
    );
    let moulins = ids(search::search(&pool, "moulin", Some(near), 20)
        .await
        .unwrap());
    assert!(
        moulins.contains(&moulin) && moulins.contains(&other_moulin),
        "two places of one name without records, neither placed roughly, stay two: \
         {moulins:?}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_search_past_its_time_limit_answers_no_place_rather_than_an_error(pool: PgPool) {
    let lac = put(
        &pool,
        &content(PlaceKind::Campsite, "Camping du Lac", 45.86, 6.17),
    )
    .await;
    // Both ways read `places`: held by another transaction, each waits
    // past its time limit.
    let mut holder = pool.begin().await.unwrap();
    sqlx::query("LOCK TABLE places IN ACCESS EXCLUSIVE MODE")
        .execute(&mut *holder)
        .await
        .unwrap();
    let started = std::time::Instant::now();
    let blocked = search::search(&pool, "lac", None, 5).await.unwrap();
    assert!(blocked.is_empty(), "no place, and no error");
    assert!(
        started.elapsed() < std::time::Duration::from_secs(3),
        "two tries, each bounded: {:?}",
        started.elapsed()
    );
    holder.rollback().await.unwrap();
    assert_eq!(
        ids(search::search(&pool, "lac", None, 5).await.unwrap()),
        [lac],
        "the connections of the pool search again once the table is free"
    );
}
