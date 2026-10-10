//! The search of the points of interest and establishments: by kind in the
//! app's languages, by name beside a kind, around the town a text ends on,
//! with a typo, without the twin another source gives of an OpenStreetMap
//! shop, and the table it reads following every write of the points.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::{TimeZone, Utc};
use lunaway_db::{
    PgPool,
    poi_search::{self, PoiAsk, PoiSearch},
    pois::{self, NewPoi},
};
use lunaway_domain::{
    Position, SourceId,
    poi::{PoiCategory, PoiKind, PoiRecord},
    poi_search::PoiMatch,
    search::LookupPath,
};

/// The centre of Lyon, where the map is.
fn lyon() -> Position {
    Position::new(45.76, 4.83).unwrap()
}

/// A point `km` east of the centre of Lyon.
fn east(km: f64) -> Position {
    Position::new(45.76, 4.83 + km / 77.6).unwrap()
}

fn point(kind: PoiKind, at: Position, name: Option<&str>) -> PoiRecord {
    let mut r = PoiRecord::new(kind, at);
    r.name = name.map(str::to_owned);
    r
}

async fn store(pool: &PgPool, source: &SourceId, points: &[(&str, PoiRecord, bool)]) {
    let raw = serde_json::value::to_raw_value(&serde_json::json!({})).unwrap();
    let at = Utc.with_ymd_and_hms(2026, 10, 10, 2, 0, 0).unwrap();
    let rows: Vec<NewPoi<'_>> = points
        .iter()
        .map(|(id, r, in_tiles)| NewPoi {
            external_id: id,
            external_url: None,
            record: r,
            raw: &raw,
            fetched_at: at,
            scope: Some("FR"),
            in_tiles: *in_tiles,
        })
        .collect();
    pois::upsert(pool, source, &rows).await.unwrap();
}

async fn find(pool: &PgPool, text: &str, near: Option<Position>) -> PoiSearch {
    let stats = poi_search::statistics(pool).await.unwrap();
    poi_search::search(
        pool,
        PoiAsk {
            text,
            near,
            first: 5,
            categories: None,
        },
        &stats,
    )
    .await
    .unwrap()
}

fn names(found: &PoiSearch) -> Vec<String> {
    found
        .rows
        .iter()
        .map(|r| r.record.name.clone().unwrap_or_default())
        .collect()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_kind_in_any_language_finds_the_nearest_of_it_named_so_or_not(pool: PgPool) {
    store(
        &pool,
        &SourceId::OSM,
        &[
            (
                "node/1",
                point(PoiKind::Hairdresser, east(0.5), Some("Coiff'Annie")),
                false,
            ),
            (
                "node/2",
                point(PoiKind::Hairdresser, east(3.0), Some("Salon Martine")),
                false,
            ),
            (
                "node/3",
                point(PoiKind::Hairdresser, east(80.0), Some("Friseur Weit")),
                false,
            ),
            (
                "node/4",
                point(PoiKind::Restaurant, east(0.1), Some("Le Coiffeur")),
                true,
            ),
        ],
    )
    .await;
    for text in [
        "coiffeur",
        "Friseur",
        "peluquería",
        "parrucchiere",
        "kapper",
        "salon de coiffure",
    ] {
        let found = find(&pool, text, Some(lyon())).await;
        assert_eq!(found.matched, PoiMatch::Kind, "{text}");
        assert_eq!(found.kinds, [PoiKind::Hairdresser], "{text}");
        assert_eq!(
            names(&found)[..2],
            ["Coiff'Annie", "Salon Martine"],
            "{text}: the nearest hairdressers, whatever their names; a restaurant named after one is none"
        );
    }
    let nowhere = find(&pool, "coiffeur", None).await;
    assert!(
        nowhere.rows.is_empty() && nowhere.matched == PoiMatch::None,
        "the nearest of a kind, with no point to be near, says nothing"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_name_beside_a_kind_brings_the_nearest_of_that_name_and_kind(pool: PgPool) {
    store(
        &pool,
        &SourceId::OSM,
        &[
            (
                "node/1",
                point(PoiKind::Bakery, east(1.0), Some("Paul")),
                true,
            ),
            (
                "node/2",
                point(PoiKind::Bakery, east(300.0), Some("Boulangerie Paul")),
                true,
            ),
            (
                "node/3",
                point(PoiKind::Shoes, east(0.3), Some("Chaussures Paul")),
                false,
            ),
            (
                "node/4",
                point(PoiKind::Bakery, east(0.2), Some("La Mie Câline")),
                true,
            ),
        ],
    )
    .await;
    let found = find(&pool, "boulangerie paul", Some(lyon())).await;
    assert_eq!(found.matched, PoiMatch::Name);
    assert_eq!(
        names(&found),
        ["Paul", "Boulangerie Paul", "Chaussures Paul"],
        "a bakery named Paul answers as well as one named Boulangerie Paul, the nearer first; \
         a Paul of another kind after them; a bakery of another name not at all"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_text_ending_on_a_town_is_ranked_around_it(pool: PgPool) {
    sqlx::query(
        "INSERT INTO place_towns (key, name, folded, postcode, country_code, places, lat, lon)
         VALUES ('m:74010', 'Annecy', 'annecy', '74000', 'FR', 80, 45.9, 6.12),
                ('c:PT:6:paul', 'Paul', 'paul', '6215', 'PT', 6, 40.2, -7.6)",
    )
    .execute(&pool)
    .await
    .unwrap();
    let mut pizza_annecy = point(
        PoiKind::Restaurant,
        Position::new(45.901, 6.121).unwrap(),
        Some("La Voglia"),
    );
    pizza_annecy.cuisine = vec!["pizza".into()];
    let mut pizza_lyon = point(PoiKind::Restaurant, east(0.2), Some("Pizza Lyon"));
    pizza_lyon.cuisine = vec!["pizza".into()];
    let thai_annecy = point(
        PoiKind::Restaurant,
        Position::new(45.9, 6.12).unwrap(),
        Some("Siam"),
    );
    store(
        &pool,
        &SourceId::OSM,
        &[
            ("node/1", pizza_annecy, true),
            ("node/2", pizza_lyon, true),
            ("node/3", thai_annecy, true),
            (
                "node/4",
                point(PoiKind::Bakery, east(0.4), Some("Paul")),
                true,
            ),
        ],
    )
    .await;
    let found = find(&pool, "pizzeria annecy", Some(lyon())).await;
    assert_eq!(found.town.as_ref().map(|t| t.name.as_str()), Some("Annecy"));
    assert_eq!(found.matched, PoiMatch::Kind);
    assert_eq!(
        names(&found)[0],
        "La Voglia",
        "the pizzeria of Annecy before the one under the map, and no restaurant of another cuisine"
    );
    assert!(!names(&found).contains(&"Siam".to_owned()));
    let paul = find(&pool, "boulangerie paul", Some(lyon())).await;
    assert!(
        paul.town.is_none() && names(&paul) == ["Paul"],
        "a hamlet of six places named like a bakery is the bakery"
    );
    let a_paul = find(&pool, "boulangerie à paul", Some(lyon())).await;
    assert_eq!(
        a_paul.town.as_ref().map(|t| t.name.as_str()),
        Some("Paul"),
        "a preposition says it is the place"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_typo_is_corrected_and_the_ways_agree(pool: PgPool) {
    store(
        &pool,
        &SourceId::OSM,
        &[
            (
                "node/1",
                point(PoiKind::Supermarket, east(2.0), Some("Carrefour Market")),
                true,
            ),
            (
                "node/2",
                point(PoiKind::Supermarket, east(9.0), Some("Carrefour")),
                true,
            ),
            (
                "node/3",
                point(PoiKind::Hotel, east(1.0), Some("Hôtel du Carré")),
                false,
            ),
        ],
    )
    .await;
    let found = find(&pool, "carefour", Some(lyon())).await;
    assert_eq!(
        names(&found),
        ["Carrefour Market", "Carrefour"],
        "one edit away"
    );
    let stats = poi_search::statistics(&pool).await.unwrap();
    for path in [LookupPath::Index, LookupPath::Nearest, LookupPath::Scan] {
        let near = (path != LookupPath::Scan).then(lyon);
        let by = poi_search::search_by_path(
            &pool,
            PoiAsk {
                text: "carrefour",
                near,
                first: 5,
                categories: None,
            },
            &stats,
            path,
        )
        .await
        .unwrap();
        let mut got = names(&by);
        got.sort();
        assert_eq!(got, ["Carrefour", "Carrefour Market"], "{path:?}");
    }
    let shops = poi_search::search(
        &pool,
        PoiAsk {
            text: "carr",
            near: Some(lyon()),
            first: 5,
            categories: Some(&[PoiCategory::Lodging]),
        },
        &stats,
    )
    .await
    .unwrap();
    assert_eq!(
        names(&shops),
        ["Hôtel du Carré"],
        "only the categories asked"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn another_source_s_twin_of_an_osm_shop_is_left_out(pool: PgPool) {
    sqlx::query(
        "INSERT INTO sources (id, name, licence, licence_url, attribution, url)
         VALUES ('other', 'Other', 'CC0', 'https://example.org/l', 'Other', 'https://example.org')",
    )
    .execute(&pool)
    .await
    .unwrap();
    store(
        &pool,
        &SourceId::OSM,
        &[(
            "node/1",
            point(PoiKind::Hairdresser, east(1.0), Some("Coiffure Annie")),
            false,
        )],
    )
    .await;
    store(
        &pool,
        &SourceId::new("other").unwrap(),
        &[
            (
                "o1",
                point(PoiKind::Hairdresser, east(1.05), Some("Annie Coiffure")),
                false,
            ),
            (
                "o2",
                point(PoiKind::Hairdresser, east(1.5), Some("Salon Lucie")),
                false,
            ),
        ],
    )
    .await;
    let found = find(&pool, "coiffeur", Some(lyon())).await;
    assert_eq!(
        names(&found),
        ["Coiffure Annie", "Salon Lucie"],
        "the same shop 40 m away under the other source is left out; another shop of it stays"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_search_follows_every_write_of_the_points(pool: PgPool) {
    store(
        &pool,
        &SourceId::OSM,
        &[(
            "node/1",
            point(PoiKind::Florist, east(1.0), Some("Fleurs de Lys")),
            false,
        )],
    )
    .await;
    assert_eq!(
        names(&find(&pool, "fleurs de lys", Some(lyon())).await),
        ["Fleurs de Lys"]
    );
    store(
        &pool,
        &SourceId::OSM,
        &[(
            "node/1",
            point(PoiKind::Florist, east(1.0), Some("Au Jardin d'Émilie")),
            false,
        )],
    )
    .await;
    assert!(
        find(&pool, "fleurs de lys", Some(lyon()))
            .await
            .rows
            .is_empty(),
        "renamed"
    );
    assert_eq!(
        names(&find(&pool, "emilie", Some(lyon())).await),
        ["Au Jardin d'Émilie"],
        "its new name, accents ignored"
    );
    sqlx::query("UPDATE pois SET hidden = true")
        .execute(&pool)
        .await
        .unwrap();
    assert!(
        find(&pool, "emilie", Some(lyon())).await.rows.is_empty(),
        "hidden"
    );
    sqlx::query("UPDATE pois SET hidden = false")
        .execute(&pool)
        .await
        .unwrap();
    assert_eq!(
        find(&pool, "emilie", Some(lyon())).await.rows.len(),
        1,
        "shown again"
    );
    pois::retire_missing(&pool, &SourceId::OSM, None, &[], Utc::now(), false)
        .await
        .unwrap();
    assert!(
        find(&pool, "emilie", Some(lyon())).await.rows.is_empty(),
        "retired"
    );
    let words: Vec<String> =
        sqlx::query_scalar("SELECT word::text FROM poi_search_words ORDER BY 1")
            .fetch_all(&pool)
            .await
            .unwrap();
    assert!(
        words.iter().all(|w| !w.contains('_')),
        "the tokens of kinds are no words a typo may be corrected to"
    );
}
