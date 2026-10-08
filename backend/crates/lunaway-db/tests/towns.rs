//! The towns of the search (`place_towns`): rebuilt from the places, one
//! town per commune whatever the address calls it, homonyms of two
//! departments apart, a count of every live place, and the roles that
//! write and read them.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use lunaway_db::{
    PgPool,
    towns::{self, RefreshStats, TownRow},
};
use sqlx::postgres::PgPoolOptions;
use uuid::Uuid;

/// A pool whose connections act as `role`, as the services' logins do.
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

async fn commune(pool: &PgPool, code: &str, name: &str) {
    sqlx::query(
        "INSERT INTO municipalities (code, name, geom, fetched_at) VALUES \
         ($1, $2, ST_Multi(ST_MakeEnvelope(0, 0, 0.01, 0.01, 4326)), now())",
    )
    .bind(code)
    .bind(name)
    .execute(pool)
    .await
    .unwrap();
}

/// A live place with what the conflation writes of its town: the address's
/// city and postcode, and the commune that covers it.
async fn place(
    pool: &PgPool,
    city: Option<&str>,
    postcode: Option<&str>,
    commune: Option<(&str, &str)>,
    country: &str,
) -> Uuid {
    let id = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO places (id, kind, geom, overnight, city, postcode, country_code, \
                             municipality_code, municipality, content_hash) \
         VALUES ($1, 'parking', ST_SetSRID(ST_MakePoint(4.68, 44.48), 4326)::geography, \
                 'unknown', $2, $3, $4, $5, $6, 'x')",
    )
    .bind(id)
    .bind(city)
    .bind(postcode)
    .bind(country)
    .bind(commune.map(|c| c.0))
    .bind(commune.map(|c| c.1))
    .execute(pool)
    .await
    .unwrap();
    id
}

fn summary(rows: &[TownRow]) -> Vec<(String, Option<String>, Option<String>, i64)> {
    rows.iter()
        .map(|t| {
            (
                t.name.clone(),
                t.postcode.clone(),
                t.department.clone(),
                t.places,
            )
        })
        .collect()
}

fn s(v: &str) -> Option<String> {
    Some(v.to_owned())
}

#[sqlx::test(migrations = "../../migrations")]
async fn one_town_per_commune_and_the_homonyms_of_two_departments_apart(pool: PgPool) {
    commune(&pool, "07346", "Viviers").await;
    commune(&pool, "89485", "Viviers").await;
    commune(&pool, "57724", "Viviers").await;
    commune(&pool, "26085", "Châteauneuf-du-Rhône").await;
    commune(&pool, "74056", "Chamonix-Mont-Blanc").await;
    commune(&pool, "73329", "Viviers-du-Lac").await;
    let viviers = Some(("07346", "Viviers"));
    for _ in 0..3 {
        place(&pool, Some("Viviers"), Some("07220"), viviers, "fr").await;
    }
    // Its address says Viviers; it lies across the Rhône, in a commune of
    // the Drôme: still a place of Viviers, Ardèche.
    place(
        &pool,
        Some("Viviers"),
        Some("07220"),
        Some(("26085", "Châteauneuf-du-Rhône")),
        "fr",
    )
    .await;
    // Mapped without an address: its commune is its town.
    place(&pool, None, None, Some(("57724", "Viviers")), "fr").await;
    place(
        &pool,
        Some("Viviers"),
        Some("89700"),
        Some(("89485", "Viviers")),
        "fr",
    )
    .await;
    place(
        &pool,
        Some("Viviers-du-Lac"),
        Some("73420"),
        Some(("73329", "Viviers-du-Lac")),
        "fr",
    )
    .await;
    let gone = place(&pool, Some("Viviers"), Some("07220"), viviers, "fr").await;
    sqlx::query("UPDATE places SET deleted_at = now() WHERE id = $1")
        .bind(gone)
        .execute(&pool)
        .await
        .unwrap();
    // The audit's "Chamonix" and "Chamonix-Mont-Blanc", one town; a hamlet
    // the address names stays its own.
    let chamonix = Some(("74056", "Chamonix-Mont-Blanc"));
    place(&pool, Some("Chamonix"), Some("74400"), chamonix, "fr").await;
    place(
        &pool,
        Some("Chamonix-Mont-Blanc"),
        Some("74400"),
        chamonix,
        "fr",
    )
    .await;
    place(&pool, Some("Argentière"), Some("74400"), chamonix, "fr").await;

    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    towns::refresh(&ingest)
        .await
        .expect("the worker rebuilds the towns with the import role");
    let app = as_role(&pool, "SET ROLE lunaway_app").await;

    let found = towns::search(&app, "Viviers", 6)
        .await
        .expect("the API reads the towns");
    assert_eq!(
        summary(&found),
        [
            (s("Viviers"), s("07220"), s("07"), 4),
            (s("Viviers"), None, s("57"), 1),
            (s("Viviers"), s("89700"), s("89"), 1),
            (s("Viviers-du-Lac"), s("73420"), s("73"), 1),
        ]
        .map(|(n, p, d, c)| (n.unwrap(), p, d, c)),
        "the homonyms first, apart by department; every live place counted"
    );
    assert_eq!(
        summary(&towns::search(&app, "chamonix", 6).await.unwrap()),
        [("Chamonix-Mont-Blanc".to_owned(), s("74400"), s("74"), 2)]
    );
    assert_eq!(
        towns::search(&app, "argentiere", 6).await.unwrap()[0].name,
        "Argentière",
        "accents fold away"
    );
    assert_eq!(
        towns::search(&app, "chamonix mont", 6).await.unwrap()[0].name,
        "Chamonix-Mont-Blanc",
        "a hyphen is a space"
    );
    assert!(
        towns::search(&app, "%", 6).await.unwrap().is_empty(),
        "a wildcard folds to nothing and finds nothing"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_rebuild_writes_only_what_changed(pool: PgPool) {
    commune(&pool, "07346", "Viviers").await;
    let viviers = Some(("07346", "Viviers"));
    let a = place(&pool, Some("Viviers"), Some("07220"), viviers, "fr").await;
    let b = place(&pool, Some("Lyon"), Some("69001"), None, "fr").await;
    place(&pool, Some("Heidelberg"), Some("69117"), None, "de").await;
    assert!(towns::is_empty(&pool).await.unwrap());
    assert_eq!(
        towns::refresh(&pool).await.unwrap(),
        RefreshStats {
            written: 3,
            removed: 0
        }
    );
    assert!(!towns::is_empty(&pool).await.unwrap());
    assert_eq!(
        towns::refresh(&pool).await.unwrap(),
        RefreshStats::default(),
        "nothing changed, nothing written"
    );
    place(&pool, Some("Viviers"), Some("07220"), viviers, "fr").await;
    sqlx::query("UPDATE places SET deleted_at = now() WHERE id = $1")
        .bind(b)
        .execute(&pool)
        .await
        .unwrap();
    assert_eq!(
        towns::refresh(&pool).await.unwrap(),
        RefreshStats {
            written: 1,
            removed: 1
        },
        "Viviers has one more place, Lyon none left"
    );
    let found = towns::search(&pool, "viv", 6).await.unwrap();
    assert_eq!(found[0].places, 2);
    let heidelberg = towns::search(&pool, "heidelberg", 6).await.unwrap();
    assert_eq!(
        (
            heidelberg[0].department.as_deref(),
            heidelberg[0].country_code.as_deref()
        ),
        (None, Some("DE")),
        "a department is French"
    );
    let _ = a;
}
