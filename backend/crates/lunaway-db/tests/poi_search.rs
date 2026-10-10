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
            kinds: None,
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
                kinds: None,
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
            kinds: Some(&PoiCategory::Lodging.kinds()),
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

#[sqlx::test(migrations = "../../migrations")]
async fn a_name_near_the_map_wins_over_a_town_of_its_last_word(pool: PgPool) {
    sqlx::query(
        "INSERT INTO place_towns (key, name, folded, postcode, country_code, places, lat, lon)
         VALUES ('c:TR:34:istanbul', 'İstanbul', 'istanbul', '34000', 'TR', 27, 41.0, 28.97),
                ('c:HU:7812:gare', 'Garé', 'gare', '7812', 'HU', 1, 45.92, 18.19),
                ('m:74056', 'Chamonix-Mont-Blanc', 'chamonix mont blanc', '74400', 'FR', 98,
                 45.92, 6.87),
                ('m:49328', 'Saumur', 'saumur', '49400', 'FR', 64, 47.26, -0.08)",
    )
    .execute(&pool)
    .await
    .unwrap();
    let saumur = |km: f64| Position::new(47.26, -0.08 + km / 75.2).unwrap();
    store(
        &pool,
        &SourceId::OSM,
        &[
            (
                "node/1",
                point(PoiKind::FastFood, east(2.0), Some("Grill Istanbul")),
                true,
            ),
            (
                "node/2",
                point(PoiKind::CarRepair, east(3.0), Some("Garage de la Gare")),
                true,
            ),
            (
                "node/3",
                point(PoiKind::CarRepair, east(0.5), Some("Garage Martin")),
                true,
            ),
            (
                "node/4",
                point(
                    PoiKind::Bakery,
                    Position::new(45.923, 6.871).unwrap(),
                    Some("Le Fournil"),
                ),
                true,
            ),
            (
                "node/5",
                point(
                    PoiKind::Hairdresser,
                    saumur(16.0),
                    Some("Le Maître Coiffeur"),
                ),
                false,
            ),
            (
                "node/6",
                point(PoiKind::Hairdresser, saumur(0.5), Some("Coiff&Co")),
                false,
            ),
        ],
    )
    .await;
    let grill = find(&pool, "grill istanbul", Some(lyon())).await;
    assert!(
        grill.town.is_none() && names(&grill) == ["Grill Istanbul"],
        "the shop named so near the map, not the grills of a far town"
    );
    let gare = find(&pool, "garage de la gare", Some(lyon())).await;
    assert!(
        gare.town.is_none(),
        "an article before a word does not make it a place"
    );
    assert_eq!(names(&gare)[0], "Garage de la Gare");
    let chamonix = find(&pool, "boulangerie chamonix", Some(lyon())).await;
    assert_eq!(
        chamonix.town.as_ref().map(|t| t.name.as_str()),
        Some("Chamonix-Mont-Blanc"),
        "a town found by the first word of its name"
    );
    assert_eq!(names(&chamonix), ["Le Fournil"]);
    let coiffeur = find(&pool, "coiffeur à saumur", Some(lyon())).await;
    assert_eq!(
        names(&coiffeur),
        ["Coiff&Co", "Le Maître Coiffeur"],
        "by kind, the nearest first: a hairdresser named after the kind is no exact match"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_typo_some_point_bears_or_a_swap_is_corrected_on_a_second_look(pool: PgPool) {
    store(
        &pool,
        &SourceId::OSM,
        &[
            (
                "node/1",
                point(PoiKind::Bakery, east(80.0), Some("Boulangerei du Coin")),
                true,
            ),
            (
                "node/2",
                point(PoiKind::Bakery, east(1.0), Some("Boulangerie Navarro")),
                true,
            ),
            (
                "node/3",
                point(PoiKind::Beauty, east(2.0), Some("Lily Beauté")),
                false,
            ),
            (
                "node/4",
                point(PoiKind::Beauty, east(2.5), Some("Beate Lily")),
                false,
            ),
            (
                "node/5",
                point(PoiKind::Bakery, east(90.0), Some("Boulangere Martin")),
                true,
            ),
        ],
    )
    .await;
    assert_eq!(
        names(&find(&pool, "boulangerei navarro", Some(lyon())).await),
        ["Boulangerie Navarro"],
        "a word some point misspells is widened to the one meant"
    );
    assert_eq!(
        names(&find(&pool, "boulangere navarro", Some(lyon())).await),
        ["Boulangerie Navarro"],
        "a letter missing, which no swap nor slip of the word typed gives back: \
         the lookalikes after the swaps"
    );
    assert_eq!(
        names(&find(&pool, "lily beuate", Some(lyon())).await)[0],
        "Lily Beauté",
        "two letters swapped, which the trigrams rank too low"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_chain_or_a_kind_is_read_in_the_cells_around_first_and_answers_as_everywhere(
    pool: PgPool,
) {
    use lunaway_domain::poi_search::geohash;
    for (lat, lon) in [(45.76, 4.83), (48.85, 2.35), (-17.7, 179.99), (64.1, -21.9)] {
        let ours = geohash(Position::new(lat, lon).unwrap(), 6);
        let theirs: String =
            sqlx::query_scalar("SELECT ST_GeoHash(ST_SetSRID(ST_MakePoint($2, $1), 4326), 6)")
                .bind(lat)
                .bind(lon)
                .fetch_one(&pool)
                .await
                .unwrap();
        assert_eq!(
            ours, theirs,
            "the cells a query names are those the rows bear"
        );
    }
    // A chain: three shops near the map, three hundred from 50 to 350 km
    // east; and launderettes, two near, sixty far.
    let mut points = Vec::new();
    for (i, km) in [0.3, 0.8, 1.5].into_iter().enumerate() {
        points.push((
            format!("node/near{i}"),
            point(PoiKind::Supermarket, east(km), Some("Lidl")),
        ));
        points.push((
            format!("node/wash{i}"),
            point(
                PoiKind::Laundry,
                east(km + 0.1),
                Some(&format!("Lavomatic {i}")),
            ),
        ));
    }
    for i in 0..300 {
        let km = 50.0 + f64::from(i);
        points.push((
            format!("node/far{i}"),
            point(PoiKind::Supermarket, east(km), Some("Lidl")),
        ));
        if i < 60 {
            points.push((
                format!("node/farwash{i}"),
                point(PoiKind::Laundry, east(km + 0.5), Some("Laverie")),
            ));
        }
        // A name many bear far away, which near the map points bear in
        // part ("Pauline") or beside other words ("Saint-Paul"): classes the
        // cells must not mix up.
        if i < 250 {
            points.push((
                format!("node/paul{i}"),
                point(PoiKind::Bakery, east(km + 0.7), Some("Paul")),
            ));
        }
    }
    points.push((
        "node/paul-near".to_owned(),
        point(PoiKind::Bakery, east(6.0), Some("Paul")),
    ));
    for i in 0..5 {
        let km = 0.1 + f64::from(i) * 0.05;
        points.push((
            format!("node/pauline{i}"),
            point(PoiKind::Clothes, east(km), Some(&format!("Pauline {i}"))),
        ));
        points.push((
            format!("node/saint-paul{i}"),
            point(
                PoiKind::Pharmacy,
                east(km + 0.02),
                Some(&format!("Pharmacie Saint-Paul {i}")),
            ),
        ));
    }
    let rows: Vec<(&str, PoiRecord, bool)> = points
        .iter()
        .map(|(id, r)| (id.as_str(), r.clone(), false))
        .collect();
    store(&pool, &SourceId::OSM, &rows).await;
    let near_cell = format!("h_{}", geohash(east(0.3), 6));
    let bears: bool = sqlx::query_scalar(
        "SELECT words @@ $2::tsquery FROM poi_search s JOIN pois p USING (id)
         WHERE p.external_id = $1",
    )
    .bind("node/near0")
    .bind(&near_cell)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(bears, "a point written bears the cells holding it");
    sqlx::query("ANALYZE poi_search")
        .execute(&pool)
        .await
        .unwrap();
    let stats = poi_search::statistics(&pool).await.unwrap();
    for text in ["lidl", "laverie", "paul", "pau", "boulangerie paul"] {
        let ask = PoiAsk {
            text,
            near: Some(lyon()),
            first: 5,
            kinds: None,
        };
        let around = poi_search::search(&pool, ask, &stats).await.unwrap();
        let everywhere = poi_search::search_by_path(&pool, ask, &stats, LookupPath::Index)
            .await
            .unwrap();
        let at = |found: &PoiSearch| -> Vec<i64> {
            found
                .rows
                .iter()
                .map(|r| (r.record.position.distance_m(lyon()) / 100.0).round() as i64)
                .collect()
        };
        assert_eq!(
            at(&around),
            at(&everywhere),
            "{text}: the nearest, found in the cells around as when reading every match"
        );
        assert_eq!(around.rows.len(), 5, "{text}");
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_dead_word_and_a_deleted_point_leave_the_search(pool: PgPool) {
    store(
        &pool,
        &SourceId::OSM,
        &[
            (
                "node/1",
                point(PoiKind::Bakery, east(1.0), Some("Zorglub")),
                true,
            ),
            (
                "node/2",
                point(PoiKind::Bakery, east(2.0), Some("Marsupilami")),
                true,
            ),
        ],
    )
    .await;
    let words = |pool: PgPool| async move {
        sqlx::query_scalar!(r#"SELECT word::text AS "word!" FROM poi_search_words ORDER BY word"#)
            .fetch_all(&pool)
            .await
            .unwrap()
    };
    sqlx::query!("UPDATE pois SET hidden = true WHERE external_id = 'node/1'")
        .execute(&pool)
        .await
        .unwrap();
    assert!(
        words(pool.clone()).await.contains(&"zorglub".to_owned()),
        "a hidden point leaves the search, its words stay until they are cleared"
    );
    let cleared = poi_search::clear_words(&pool).await.unwrap();
    assert_eq!(cleared, 1);
    assert_eq!(
        words(pool.clone()).await,
        ["marsupilami"],
        "only the words a live point bears are kept for the corrections"
    );

    sqlx::query!("DELETE FROM pois WHERE external_id = 'node/2'")
        .execute(&pool)
        .await
        .unwrap();
    let left = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM poi_search"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        left, 0,
        "a point deleted by hand takes its words and position out of the search"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_statement_over_its_time_limit_leaves_the_search_answering(pool: PgPool) {
    sqlx::query(
        "INSERT INTO place_towns (key, name, folded, postcode, country_code, places, lat, lon)
         VALUES ('m:74010', 'Annecy', 'annecy', '74000', 'FR', 80, 45.9, 6.12)",
    )
    .execute(&pool)
    .await
    .unwrap();
    let mut pizza = point(
        PoiKind::Restaurant,
        Position::new(45.901, 6.121).unwrap(),
        Some("La Voglia"),
    );
    pizza.cuisine = vec!["pizza".into()];
    store(&pool, &SourceId::OSM, &[("node/1", pizza, true)]).await;
    let stats = poi_search::statistics(&pool).await.unwrap();
    // Another session holds a table the search reads, so the statement
    // waits until its time limit cancels it: the towns, then the points.
    for (table, lock) in [
        (
            "place_towns",
            "LOCK TABLE place_towns IN ACCESS EXCLUSIVE MODE",
        ),
        (
            "poi_search",
            "LOCK TABLE poi_search IN ACCESS EXCLUSIVE MODE",
        ),
    ] {
        let mut holder = pool.begin().await.unwrap();
        sqlx::query(lock).execute(&mut *holder).await.unwrap();
        let answer = poi_search::search(
            &pool,
            PoiAsk {
                text: "pizzeria annecy",
                near: Some(lyon()),
                first: 5,
                kinds: None,
            },
            &stats,
        )
        .await;
        holder.rollback().await.unwrap();
        let answer = answer.unwrap_or_else(|e| {
            panic!("{table} held: the search must answer, without its points if need be: {e}")
        });
        assert!(
            answer.rows.is_empty(),
            "{table} held: nothing found in time, nothing returned"
        );
    }
    assert_eq!(
        names(&find(&pool, "pizzeria annecy", Some(lyon())).await),
        ["La Voglia"],
        "once nothing holds the tables, the same search finds the pizzeria"
    );
}
