//! The towns of the map's search (`place_towns`): every town the places
//! lie in, with how many places it holds, rebuilt from `places` by the
//! conflation worker, and found by the start of its name.
//!
//! A place's town is its commune when its address names none, or names the
//! commune or the start of its name ("Chamonix" for Chamonix-Mont-Blanc,
//! one town, not two); otherwise the town its address names (a hamlet a
//! source writes as the town, a town abroad). A commune is one town by its
//! INSEE code; another town is one by its country, its commune or postcode
//! area and its name, so the homonyms of two departments stay two.

use crate::{DbError, PgPool};

/// A town of the search.
#[derive(Debug, Clone, PartialEq)]
pub struct TownRow {
    /// Its name, as most of its places write it.
    pub name: String,
    /// The postcode most of its places carry.
    pub postcode: Option<String>,
    /// The French department (`07`, `2A`, `974`); `None` outside France.
    pub department: Option<String>,
    /// ISO 3166-1 alpha-2 country code, upper case, when known.
    pub country_code: Option<String>,
    /// Live places in it.
    pub places: i32,
    /// The middle of its places.
    pub lat: f64,
    /// The middle of its places.
    pub lon: f64,
}

/// What a rebuild changed.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct RefreshStats {
    /// Towns written: new, or with another count, name or middle.
    pub written: u64,
    /// Towns gone: no live place lies in them any more.
    pub removed: u64,
}

/// Rebuilds the towns from the live places, writing only the rows that
/// changed. Run by the conflation worker when the places' tiles take a new
/// version, and when the table is empty.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn refresh(pool: &PgPool) -> Result<RefreshStats, DbError> {
    let mut tx = pool.begin().await?;
    // One rebuild at a time: a second worker waits, then finds nothing to
    // change.
    sqlx::query!("LOCK TABLE place_towns IN SHARE ROW EXCLUSIVE MODE")
        .execute(&mut *tx)
        .await?;
    // One statement, no temporary table: the roles have no TEMPORARY
    // privilege on the production database (infra/server/postgres.sh).
    // 4 to 5 s on production (200 961 live places, 41 791 towns,
    // 2026-10-08), at most once per version of the places' tiles.
    let r = sqlx::query!(
        r#"
        WITH p AS (
            SELECT p.municipality_code AS code, p.municipality, p.city,
                   upper(p.country_code) AS cc, p.postcode,
                   ST_Y(p.geom::geometry) AS lat, ST_X(p.geom::geometry) AS lon,
                   lunaway_town_fold(p.municipality) AS fm, lunaway_town_fold(p.city) AS fc
            FROM places p
            WHERE p.deleted_at IS NULL AND coalesce(p.city, p.municipality) IS NOT NULL
        ),
        d AS (
            SELECT *,
                   -- The commune when the address names none, the commune
                   -- itself, or the start of its name.
                   municipality IS NOT NULL
                       AND (city IS NULL OR fm = fc OR starts_with(fm, fc || ' ')) AS commune,
                   CASE WHEN cc = 'FR' AND postcode ~ '^[0-9]{5}$' THEN
                        CASE WHEN postcode LIKE '97%' THEN left(postcode, 3)
                             WHEN postcode LIKE '20%' AND postcode < '20200' THEN '2A'
                             WHEN postcode LIKE '20%' THEN '2B'
                             ELSE left(postcode, 2) END
                   END AS pdept,
                   CASE WHEN code LIKE '97%' THEN left(code, 3) ELSE left(code, 2) END AS cdept
            FROM p
        ),
        -- The communes by folded name and department, the names one commune
        -- alone holds there: a town an address names that is a commune of
        -- its department ("Viviers 07220" written on a place across the
        -- Rhône, in the Drôme) is that commune.
        m AS (
            SELECT fn, dept, min(code) AS code
            FROM (SELECT code, lunaway_town_fold(name) AS fn,
                         CASE WHEN code LIKE '97%' THEN left(code, 3) ELSE left(code, 2) END
                             AS dept
                  FROM municipalities) x
            GROUP BY fn, dept
            HAVING count(*) = 1
        ),
        k AS (
            SELECT CASE WHEN d.commune THEN 'm:' || d.code
                        WHEN m.code IS NOT NULL THEN 'm:' || m.code
                        ELSE 'c:' || coalesce(d.cc, '') || ':'
                             || coalesce(d.pdept, d.cdept, left(d.postcode, 2), '') || ':' || d.fc
                   END AS key,
                   CASE WHEN d.commune THEN d.cdept
                        WHEN m.code IS NOT NULL THEN m.dept
                        ELSE coalesce(d.pdept, d.cdept)
                   END AS department,
                   CASE WHEN d.commune THEN d.municipality ELSE d.city END AS town,
                   d.cc, d.postcode, d.lat, d.lon
            FROM d
            LEFT JOIN m ON NOT d.commune AND d.cc = 'FR' AND m.fn = d.fc
                       AND m.dept = coalesce(d.pdept, d.cdept)
            WHERE CASE WHEN d.commune THEN d.fm ELSE d.fc END <> ''
        ),
        fresh AS (
            SELECT key,
                   mode() WITHIN GROUP (ORDER BY town) AS name,
                   mode() WITHIN GROUP (ORDER BY postcode) AS postcode,
                   max(department) AS department,
                   mode() WITHIN GROUP (ORDER BY cc) AS country_code,
                   count(*)::int AS places,
                   round(avg(lat)::numeric, 5)::float8 AS lat,
                   round(avg(lon)::numeric, 5)::float8 AS lon
            FROM k
            GROUP BY key
        ),
        -- The two touch other keys: the one deletes the towns gone, the
        -- other writes the towns there are.
        gone AS (
            DELETE FROM place_towns t
            WHERE NOT EXISTS (SELECT 1 FROM fresh f WHERE f.key = t.key)
            RETURNING 1
        ),
        written AS (
            INSERT INTO place_towns AS t
                (key, name, folded, postcode, department, country_code, places, lat, lon)
            SELECT key, name, lunaway_town_fold(name), postcode, department, country_code,
                   places, lat, lon
            FROM fresh
            ON CONFLICT (key) DO UPDATE SET
                name = EXCLUDED.name, folded = EXCLUDED.folded, postcode = EXCLUDED.postcode,
                department = EXCLUDED.department, country_code = EXCLUDED.country_code,
                places = EXCLUDED.places, lat = EXCLUDED.lat, lon = EXCLUDED.lon
            WHERE (t.name, t.postcode, t.department, t.country_code, t.places, t.lat, t.lon)
                  IS DISTINCT FROM (EXCLUDED.name, EXCLUDED.postcode, EXCLUDED.department,
                                    EXCLUDED.country_code, EXCLUDED.places, EXCLUDED.lat,
                                    EXCLUDED.lon)
            RETURNING 1
        )
        SELECT (SELECT count(*) FROM gone) AS "removed!", (SELECT count(*) FROM written) AS "written!"
        "#
    )
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(RefreshStats {
        written: u64::try_from(r.written).unwrap_or(0),
        removed: u64::try_from(r.removed).unwrap_or(0),
    })
}

/// Whether no town is stored: a database the worker never rebuilt them in.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn is_empty(pool: &PgPool) -> Result<bool, DbError> {
    Ok(
        sqlx::query_scalar!(r#"SELECT NOT EXISTS (SELECT 1 FROM place_towns) AS "empty!""#)
            .fetch_one(pool)
            .await?,
    )
}

/// The towns whose folded name starts like the folded `text`, at most
/// `first`: the towns named exactly so first (the homonyms of several
/// departments together), then by how many places they hold.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn search(pool: &PgPool, text: &str, first: i64) -> Result<Vec<TownRow>, DbError> {
    Ok(sqlx::query_as!(
        TownRow,
        r#"
        SELECT name, postcode, department, country_code, places, lat, lon
        FROM place_towns
        -- The folded text holds letters, digits and single spaces only: no
        -- wildcard of LIKE can come from it.
        WHERE lunaway_town_fold($1) <> '' AND folded LIKE lunaway_town_fold($1) || '%'
        ORDER BY folded = lunaway_town_fold($1) DESC, places DESC, name, department
        LIMIT $2
        "#,
        text,
        first,
    )
    .fetch_all(pool)
    .await?)
}
