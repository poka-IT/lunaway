//! The places' tiles at the database: the services mask the tiles carry,
//! the version's cadence, the dots each publication keeps, and the dots
//! tiles built ahead.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::time::Duration;

use lunaway_db::{PgPool, conflation, place_ratings, place_tiles};
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
             SELECT z, tx, ty, kind, night, s, price, h, r, o1, o2, py, px, n FROM place_dots)
            UNION ALL
            (SELECT z, tx, ty, kind, night, s, price, h, r, o1, o2, py, px, n FROM place_dots
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
            (SELECT id, kind, night, s, price, h, r, o1, o2, gx, gy FROM place_dot_sources
             EXCEPT ALL
             SELECT place_id, kind, night, s, price, h, r, o1, o2, gx, gy FROM place_dot_members)
            UNION ALL
            (SELECT place_id, kind, night, s, price, h, r, o1, o2, gx, gy FROM place_dot_members
             EXCEPT ALL
             SELECT id, kind, night, s, price, h, r, o1, o2, gx, gy FROM place_dot_sources)
        ) d
        "#
    )
    .fetch_one(pool)
    .await
    .unwrap();
    (dots, members)
}

/// Stored dots tiles that differ from a build from the dots now, both
/// ways (a tile missing, one left over, other bytes): zero when each
/// publication stored the tiles it changed.
async fn stale_tiles(pool: &PgPool) -> i64 {
    sqlx::query_scalar!(
        r#"
        SELECT count(*) AS "n!"
        FROM (SELECT t.z, t.tx, t.ty, lunaway_place_dots_tile(t.z, t.tx, t.ty, 512) AS mvt
              FROM (SELECT DISTINCT z::integer AS z, tx, ty FROM place_dots) t) f
        FULL JOIN place_dot_tiles s ON s.z = f.z AND s.tx = f.tx AND s.ty = f.ty
        WHERE s.mvt IS DISTINCT FROM f.mvt
        "#
    )
    .fetch_one(pool)
    .await
    .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_dots_tile_is_the_one_its_version_s_publication_stored(pool: PgPool) {
    // Annecy and Brest, far apart: a tile of each at zoom 9.
    place(&pool, 45.899, 6.129, &[]).await;
    let brest = place(&pool, 48.39, -4.49, &[]).await;
    place_tiles::publish_layer_now(&pool).await.unwrap();
    let tiles = place_tiles::dots_tiles_with_places(&pool).await.unwrap();
    let z9: Vec<(i32, i32, i32)> = tiles.iter().copied().filter(|t| t.0 == 9).collect();
    assert_eq!(z9.len(), 2);
    let (z, x, y) = z9[0];
    let built = place_tiles::tile(&pool, z, x, y, 4_000).await.unwrap();
    assert!(!built.is_empty());

    // What the API serves is the stored tile, not a build.
    sqlx::query!(
        "UPDATE place_dot_tiles SET mvt = '\\x01' WHERE z = $1 AND tx = $2 AND ty = $3",
        z,
        x,
        y
    )
    .execute(&pool)
    .await
    .unwrap();
    assert_eq!(
        place_tiles::tile(&pool, z, x, y, 4_000).await.unwrap(),
        [1],
        "a stored tile is read, never built at the request"
    );
    // A version published by a release that does not store them: the
    // tiles are built from the dots until the worker stores them, at its
    // next run, without moving the version.
    sqlx::query!("UPDATE place_layer SET version = version + 1")
        .execute(&pool)
        .await
        .unwrap();
    assert_eq!(
        place_tiles::tile(&pool, z, x, y, 4_000).await.unwrap(),
        built,
        "stored tiles of another version are not served"
    );
    let before = place_tiles::layer_version(&pool).await.unwrap().version;
    assert_eq!(
        place_tiles::publish_layer(&pool, Duration::ZERO)
            .await
            .unwrap(),
        None,
        "no place written: the version stays"
    );
    assert_eq!(
        place_tiles::layer_version(&pool).await.unwrap().version,
        before
    );
    assert_eq!(stale_tiles(&pool).await, 0, "its tiles are stored again");
    let complete: bool =
        sqlx::query_scalar!(r#"SELECT dot_tiles_version = version AS "c!" FROM place_layer"#)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert!(complete, "and served from the store");

    // Brest gone: its tiles hold no dot and lose their rows.
    write(&pool, brest, "deleted_at = now()").await;
    place_tiles::publish_layer_now(&pool).await.unwrap();
    assert_eq!(stale_tiles(&pool).await, 0, "every tile stored again");
    let after = place_tiles::dots_tiles_with_places(&pool).await.unwrap();
    assert_eq!(after.iter().filter(|t| t.0 == 9).count(), 1);
    let gone = z9
        .iter()
        .copied()
        .find(|t| !after.contains(t))
        .expect("Brest's tile left the list");
    assert!(
        place_tiles::tile(&pool, gone.0, gone.1, gone.2, 4_000)
            .await
            .unwrap()
            .is_empty(),
        "a tile without a dot is empty"
    );
}

/// The dots as rows, to tell whether a write changed them.
async fn dots_now(pool: &PgPool) -> Vec<String> {
    sqlx::query_scalar!(
        r#"
        SELECT concat_ws(',', z, tx, ty, kind, night, s, price, h, r, py, px, n) AS "row!"
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
    assert_eq!(
        stale_tiles(&pool).await,
        0,
        "the first publication stores every tile"
    );
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
    assert_eq!(
        stale_tiles(&pool).await,
        0,
        "the tiles the writes touched are stored again, and only they changed"
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
        stale_tiles(&pool).await,
        0,
        "every tile stored again after a version published without them"
    );
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

/// What a dot says of a rating in tenths: the highest step it reaches.
fn step_of(tenths: Option<i32>) -> Option<i32> {
    let tenths = tenths?;
    place_tiles::DOTS_RATING_STEPS
        .iter()
        .rev()
        .copied()
        .find(|s| tenths >= *s)
}

/// Computes the filter ratings as the worker does after a run.
async fn rate(pool: &PgPool) -> u64 {
    let mut tx = conflation::begin_writer(pool).await.unwrap();
    let changed = place_ratings::refresh_filter_ratings(&mut tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    changed
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_rating_reaches_the_dots_with_the_next_version(pool: PgPool) {
    // Lunaway users' averages around each step, and a place nobody rated.
    let averages = [
        None,
        Some(2.9),
        Some(3.0),
        Some(3.94),
        Some(4.0),
        Some(4.44),
        Some(4.45),
        Some(5.0),
    ];
    let mut ids = Vec::new();
    for (i, avg) in averages.into_iter().enumerate() {
        let lon = 5.0 + f64::from(u32::try_from(i).unwrap()) * 0.1;
        let id = place(&pool, 45.0, lon, &[]).await;
        sqlx::query!(
            "UPDATE places SET rating_avg = $2, rating_count = $3 WHERE id = $1",
            id,
            avg,
            i32::from(avg.is_some()),
        )
        .execute(&pool)
        .await
        .unwrap();
        ids.push(id);
    }
    assert_eq!(rate(&pool).await, 7, "the worker writes the seven ratings");
    place_tiles::publish_layer_now(&pool).await.unwrap();
    for id in &ids {
        let r = sqlx::query!(
            r#"SELECT round(p.filter_rating * 10)::int AS tenths, m.r
               FROM places p JOIN place_dot_members m ON m.place_id = p.id WHERE p.id = $1"#,
            id
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(
            r.r,
            step_of(r.tenths),
            "{:?} tenths: the dot's step is the highest of DOTS_RATING_STEPS it reaches",
            r.tenths
        );
    }
    assert_eq!(drift(&pool).await, (0, 0));
    let stored: Vec<Option<i32>> =
        sqlx::query_scalar!("SELECT DISTINCT r FROM place_dots ORDER BY 1")
            .fetch_all(&pool)
            .await
            .unwrap();
    assert_eq!(stored, [Some(30), Some(40), Some(45), None]);

    // A rating that changes gets a new position in the change feed from the
    // worker; the dots follow with the next version.
    sqlx::query!("UPDATE places SET rating_avg = 4.8 WHERE id = $1", ids[1])
        .execute(&pool)
        .await
        .unwrap();
    let published = dots_now(&pool).await;
    assert_eq!(rate(&pool).await, 1);
    assert_eq!(dots_now(&pool).await, published, "until the next version");
    sqlx::query!("UPDATE place_layer SET changed_at = now() - interval '1 hour'")
        .execute(&pool)
        .await
        .unwrap();
    place_tiles::publish_layer(&pool, Duration::from_secs(60))
        .await
        .unwrap()
        .expect("the new rating moved the change feed");
    assert_eq!(drift(&pool).await, (0, 0));
    let r: Option<i32> = sqlx::query_scalar!(
        "SELECT r FROM place_dot_members WHERE place_id = $1",
        ids[1]
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(r, Some(45), "rated 4.8: the step of 4.5");
}
