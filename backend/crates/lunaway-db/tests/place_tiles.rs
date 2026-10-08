//! The places' tiles at the database: the services mask the tiles carry,
//! the version's cadence, the dots each publication keeps, and the dots
//! tiles built ahead.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::time::Duration;

use lunaway_db::{PgPool, place_tiles};
use lunaway_domain::Service;
use uuid::Uuid;

async fn place(pool: &PgPool, lat: f64, lon: f64, services: &[Service]) -> Uuid {
    let id = Uuid::now_v7();
    let codes: Vec<String> = services.iter().map(|s| s.code().to_owned()).collect();
    sqlx::query!(
        r#"
        INSERT INTO places (id, kind, geom, overnight, services, content_hash)
        VALUES ($1, 'parking', ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography, 'unknown', $4, 'x')
        "#,
        id,
        lat,
        lon,
        &codes,
    )
    .execute(pool)
    .await
    .unwrap();
    id
}

async fn mask_of(pool: &PgPool, id: Uuid) -> i32 {
    sqlx::query_scalar!(
        r#"SELECT services_mask AS "m!" FROM places WHERE id = $1"#,
        id
    )
    .fetch_one(pool)
    .await
    .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_stored_mask_uses_the_domain_s_bits(pool: PgPool) {
    // The tiles carry this column and the app reads it with the domain's
    // bits: the SQL list of the migration must be the domain's order.
    for s in Service::ALL {
        let id = place(&pool, 47.0, 2.0, &[*s]).await;
        assert_eq!(
            mask_of(&pool, id).await,
            1 << s.bit(),
            "{s}: the database and the domain disagree on its bit"
        );
    }
    let all = place(&pool, 47.0, 2.0, Service::ALL).await;
    assert_eq!(
        i64::from(mask_of(&pool, all).await),
        i64::from(Service::mask(Service::ALL))
    );
    let none = place(&pool, 47.0, 2.0, &[]).await;
    assert_eq!(mask_of(&pool, none).await, 0);
    let id = place(&pool, 47.0, 2.0, &[Service::Wifi]).await;
    sqlx::query!(
        "UPDATE places SET services = '{grey_water,black_water}' WHERE id = $1",
        id
    )
    .execute(&pool)
    .await
    .unwrap();
    assert_eq!(
        mask_of(&pool, id).await,
        0b110,
        "the mask follows every write of the services"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_version_moves_when_places_changed_and_no_sooner_than_asked(pool: PgPool) {
    // The version's date is the migration's, so as old as the test
    // template: dated a minute ago here, the interval below is measured
    // from the test and not from when the template was migrated.
    sqlx::query!("UPDATE place_layer SET changed_at = now() - interval '1 minute'")
        .execute(&pool)
        .await
        .unwrap();
    let start = place_tiles::layer_version(&pool).await.unwrap();
    assert_eq!(
        place_tiles::publish_layer(&pool, Duration::ZERO)
            .await
            .unwrap(),
        None,
        "nothing written since the version: devices keep their tiles"
    );
    place(&pool, 47.0, 2.0, &[]).await;
    assert_eq!(
        place_tiles::publish_layer(&pool, Duration::from_secs(900))
            .await
            .unwrap(),
        None,
        "a version younger than the interval stays"
    );
    let moved = place_tiles::publish_layer(&pool, Duration::ZERO)
        .await
        .unwrap();
    assert_eq!(moved, Some(start.version + 1));
    let v = place_tiles::layer_version(&pool).await.unwrap();
    let head: i64 = sqlx::query_scalar!(r#"SELECT max(updated_seq) AS "s!" FROM places"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(v.published_seq, head, "the version covers the feed's end");
    assert_eq!(
        place_tiles::publish_layer(&pool, Duration::ZERO)
            .await
            .unwrap(),
        None,
        "published once"
    );
    assert_eq!(
        place_tiles::publish_layer_now(&pool).await.unwrap(),
        start.version + 2,
        "a takedown moves it whatever the interval"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_tiles_built_ahead_are_every_dots_tile_holding_a_place(pool: PgPool) {
    // Annecy and Brest: two tiles at zoom 9, one at zoom 2, none near an
    // edge.
    place(&pool, 45.899, 6.129, &[]).await;
    place(&pool, 48.39, -4.49, &[]).await;
    assert!(
        place_tiles::dots_tiles_with_places(&pool)
            .await
            .unwrap()
            .is_empty(),
        "the dots are those of the published version"
    );
    place_tiles::publish_layer_now(&pool).await.unwrap();
    let tiles = place_tiles::dots_tiles_with_places(&pool).await.unwrap();
    let zooms = place_tiles::DOTS_MIN_ZOOM..place_tiles::PIN_ZOOM;
    for z in zooms.clone() {
        let n = tiles.iter().filter(|t| t.0 == z).count();
        assert!((1..=2).contains(&n), "zoom {z}: {n} tiles");
    }
    assert!(tiles.iter().all(|t| zooms.contains(&t.0)));
    assert_eq!(
        tiles
            .iter()
            .filter(|t| t.0 == place_tiles::PIN_ZOOM - 1)
            .count(),
        2
    );
    assert!(
        tiles.windows(2).all(|w| w[0].0 <= w[1].0),
        "the lowest zooms first: they cost the most"
    );
    // Each listed tile holds its place: a dots tile built for it is not
    // empty.
    for &(z, x, y) in &tiles {
        let mvt = place_tiles::tile(&pool, z, x, y, 4_000).await.unwrap();
        assert!(!mvt.is_empty(), "{z}/{x}/{y} is listed but empty");
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_grid_puts_a_point_in_the_tile_web_mercator_does(pool: PgPool) {
    // The dots and the clusters place a point by `lunaway_grid_x` and
    // `_y`, the tiles' envelopes come from ST_TileEnvelope in EPSG:3857: a
    // point must fall in the same tile by both, at every level the tiles
    // use, up to the unit of a cluster tile of zoom 9 (2^21 a side).
    let off: i64 = sqlx::query_scalar!(
        r#"
        WITH pts AS (
            SELECT lon, lat, ST_Transform(ST_SetSRID(ST_MakePoint(lon, lat), 4326), 3857) AS g
            FROM generate_series(-31.0, 34.0, 0.3711) AS lon,
                 generate_series(27.5, 80.5, 0.2937) AS lat
        )
        SELECT count(*) AS "n!"
        FROM pts CROSS JOIN generate_series(0, 21) AS z
        WHERE floor((ST_X(g) + 20037508.342789244) / (40075016.68557849 / (1 << z)))
                  <> lunaway_grid_x(lon) >> (28 - z)
           OR floor((20037508.342789244 - ST_Y(g)) / (40075016.68557849 / (1 << z)))
                  <> lunaway_grid_y(lat) >> (28 - z)
        "#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(off, 0, "points placed in another tile than Web Mercator's");
}

/// Rows of the dots or of the members that differ from what the live
/// places make, both ways: zero when the publications kept them right.
async fn drift(pool: &PgPool) -> (i64, i64) {
    let dots = sqlx::query_scalar!(
        r#"
        SELECT count(*) AS "n!" FROM (
            (SELECT * FROM place_dots_computed
             EXCEPT ALL
             SELECT z, tx, ty, kind, night, s, price, h, py, px, n FROM place_dots)
            UNION ALL
            (SELECT z, tx, ty, kind, night, s, price, h, py, px, n FROM place_dots
             EXCEPT ALL
             SELECT * FROM place_dots_computed)
        ) d
        "#
    )
    .fetch_one(pool)
    .await
    .unwrap();
    let members = sqlx::query_scalar!(
        r#"
        SELECT count(*) AS "n!" FROM (
            (SELECT id, kind, night, s, price, h, gx, gy FROM place_dot_sources
             EXCEPT ALL
             SELECT place_id, kind, night, s, price, h, gx, gy FROM place_dot_members)
            UNION ALL
            (SELECT place_id, kind, night, s, price, h, gx, gy FROM place_dot_members
             EXCEPT ALL
             SELECT id, kind, night, s, price, h, gx, gy FROM place_dot_sources)
        ) d
        "#
    )
    .fetch_one(pool)
    .await
    .unwrap();
    (dots, members)
}

/// The dots as rows, to tell whether a write changed them.
async fn dots_now(pool: &PgPool) -> Vec<String> {
    sqlx::query_scalar!(
        r#"
        SELECT concat_ws(',', z, tx, ty, kind, night, s, price, h, py, px, n) AS "row!"
        FROM place_dots ORDER BY 1
        "#
    )
    .fetch_all(pool)
    .await
    .unwrap()
}

/// A write of a place as the writers make it: the change feed moves.
async fn write(pool: &PgPool, id: Uuid, set: &'static str) {
    // `set` is a literal of this test.
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "UPDATE places SET {set}, updated_seq = nextval('place_change_seq') WHERE id = $1"
    )))
    .bind(id)
    .execute(pool)
    .await
    .unwrap();
}

#[sqlx::test(migrations = "../../migrations")]
async fn each_publication_leaves_the_dots_the_live_places_make(pool: PgPool) {
    // Places around 5.625 E, 45.089 N, a corner of tiles of zooms 6 to 9,
    // so that dots fall in the margins, with every combination of the
    // properties the dots carry.
    let kinds = ["parking", "motorhome_area", "campsite"];
    let nights = ["allowed", "tolerated", "unknown"];
    let mut state: u64 = 7;
    let mut next = move |n: u64| {
        state = state
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1_442_695_040_888_963_407);
        (state >> 33) % n
    };
    let mut ids = Vec::new();
    for _ in 0..300 {
        let id = Uuid::now_v7();
        let lat = 45.0 + f64::from(u32::try_from(next(2_000)).unwrap()) / 10_000.0;
        let lon = 5.525 + f64::from(u32::try_from(next(2_000)).unwrap()) / 10_000.0;
        let services: Vec<String> = Service::ALL
            .iter()
            .filter(|_| next(5) == 0)
            .map(|s| s.code().to_owned())
            .collect();
        let price = match next(3) {
            0 => None,
            1 => Some(0.0),
            _ => Some(8.0),
        };
        let height = (next(3) == 0).then_some(3.2);
        sqlx::query!(
            r#"
            INSERT INTO places (id, kind, geom, overnight, services, price_parking_eur,
                                max_height_m, content_hash)
            VALUES ($1, $2, ST_SetSRID(ST_MakePoint($4, $3), 4326)::geography, $5, $6, $7, $8,
                    'x')
            "#,
            id,
            kinds[usize::try_from(next(3)).unwrap()],
            lat,
            lon,
            nights[usize::try_from(next(3)).unwrap()],
            &services,
            price,
            height,
        )
        .execute(&pool)
        .await
        .unwrap();
        ids.push(id);
    }
    // A place in the pixel of another with the same properties: one dot of
    // two places.
    let twin = Uuid::now_v7();
    sqlx::query!(
        r#"
        INSERT INTO places (id, kind, geom, overnight, services, price_parking_eur, max_height_m,
                            content_hash)
        SELECT $1, kind, geom, overnight, services, price_parking_eur, max_height_m, 'x'
        FROM places WHERE id = $2
        "#,
        twin,
        ids[0],
    )
    .execute(&pool)
    .await
    .unwrap();
    assert_eq!(drift(&pool).await.1, 301, "nothing published yet");
    place_tiles::publish_layer_now(&pool).await.unwrap();
    assert_eq!(drift(&pool).await, (0, 0), "the first publication");
    let in_margins: i64 = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM place_dots
           WHERE px NOT BETWEEN 0 AND 511 OR py NOT BETWEEN 0 AND 511"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(in_margins > 0, "the seeds reach the margins");

    // Writes of every kind: a place moved, one of another kind, one gone,
    // one renamed only, the twin gone (its dot stays, for the other), new
    // services and no height, a new place.
    let published = dots_now(&pool).await;
    write(
        &pool,
        ids[1],
        "geom = ST_SetSRID(ST_MakePoint(5.6, 45.1), 4326)::geography",
    )
    .await;
    write(&pool, ids[2], "kind = 'farm'").await;
    write(&pool, ids[3], "deleted_at = now()").await;
    write(&pool, ids[4], "name = 'Aire des Grillons'").await;
    write(&pool, twin, "deleted_at = now()").await;
    write(
        &pool,
        ids[5],
        "services = '{drinking_water,laundry,wifi}', max_height_m = NULL",
    )
    .await;
    sqlx::query!(
        r#"
        INSERT INTO places (id, kind, geom, overnight, content_hash)
        VALUES ($1, 'parking', ST_SetSRID(ST_MakePoint(5.625, 45.089), 4326)::geography,
                'unknown', 'x')
        "#,
        Uuid::now_v7(),
    )
    .execute(&pool)
    .await
    .unwrap();
    assert_eq!(
        dots_now(&pool).await,
        published,
        "until the next version, the dots are those of the version"
    );
    sqlx::query!("UPDATE place_layer SET changed_at = now() - interval '1 hour'")
        .execute(&pool)
        .await
        .unwrap();
    place_tiles::publish_layer(&pool, Duration::from_secs(60))
        .await
        .unwrap()
        .expect("places were written since the version");
    assert_eq!(
        drift(&pool).await,
        (0, 0),
        "the version moved with the dots"
    );

    // A release that does not keep the dots publishes (the worker of the
    // release before, until the deploy restarts it): the next publication
    // catches up from the dots' own position.
    write(&pool, ids[6], "overnight = 'forbidden'").await;
    sqlx::query!(
        r#"
        UPDATE place_layer SET version = version + 1,
            published_seq = (SELECT max(updated_seq) FROM places)
        "#
    )
    .execute(&pool)
    .await
    .unwrap();
    assert_ne!(drift(&pool).await, (0, 0));
    sqlx::query!("UPDATE place_layer SET changed_at = now() - interval '1 hour'")
        .execute(&pool)
        .await
        .unwrap();
    place_tiles::publish_layer(&pool, Duration::from_secs(60))
        .await
        .unwrap()
        .expect("the worker publishes again: no place was written, but the dots lag");
    assert_eq!(drift(&pool).await, (0, 0), "caught up");
    assert_eq!(
        place_tiles::publish_layer(&pool, Duration::ZERO)
            .await
            .unwrap(),
        None,
        "and then nothing waits"
    );
    let empty: i64 = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM place_dots WHERE n <= 0"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(empty, 0, "a dot goes with its last place");
}
