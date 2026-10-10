//! Searching places by name, municipality and kind.
//!
//! A place's words are its folded name, address city and municipality,
//! stored as a `tsvector` (`places.search_vector`). The words of a query
//! that name a place must all start a word of it; the generic ones ("aire",
//! "camping", "de") only rank (`lunaway_domain::search`). A word that
//! starts no word of any place is replaced by the words of places within an
//! edit or two of it (`place_search_words`), so "chamonis" finds Chamonix.
//!
//! How the candidates are found depends on how many places hold the words,
//! read from the planner's statistics (`pg_stats`): every match from the
//! GIN index when few places do; the nearest matches, walking the spatial
//! index out from the point, when many do ("parking" near a town takes the
//! nearest car parks rather than every one in Europe); the first matches
//! read from the table when many do and there is no point. A query of kind
//! words ending on one ("aire de camping car") around a point takes the
//! nearest places of that kind, named after it or not.
//!
//! Then, in order: the query's words in their order as whole words, then
//! with the last one being typed, then all of them in any order, then the
//! naming words only; the places of a town the text names whole ("viviers":
//! Viviers, not Chapelle-Viviers); the places of the kind the query names;
//! the places whose name holds the naming words, so that a place named
//! after the text comes before the places that hold it by their town alone;
//! the nearest to `near`; the shortest text. A place told twice, by two
//! sources the conflation did not join, one of them placing it roughly (by
//! its postal address), is listed once (`lunaway_domain::search::one_place`).
//!
//! Every statement has a short time limit: a search slower than it (a word
//! more common than the statistics said) is tried again the other way, and
//! gives no place rather than an error when that is slow too.

use lunaway_domain::{
    Position,
    search::{
        Listed, LookupPath, PlaceQuery, Placement, QueryWord, WordShares, alike, one_place,
        repeated,
    },
};
use sqlx::{Acquire, Postgres, Transaction};
use uuid::Uuid;

use crate::{
    DbError, PgPool,
    places::{PlaceDb, PlaceRow},
};

/// Time limit of each statement of a search. On the bench of 2026-10-07
/// (200 queries, five times the production volume, a 2-vCPU server), the
/// slowest search took 44 ms, 81 ms as the first on its connection; one
/// past this has taken the wrong way.
const STATEMENT_LIMIT: &str = "250ms";

/// Candidates kept around a point for each `first` result asked: the
/// ranking puts better name matches before nearer ones, so it needs more
/// than it returns.
const NEAREST_PER_RESULT: i64 = 2;
/// At least this many candidates around a point.
const NEAREST_MIN: i64 = 40;
/// At most this many candidates from the index around a point, all ranked
/// by distance: the statistics give the index only the words held by few
/// places, this bounds a word they underestimate.
const INDEX_CAP_NEAR: i64 = 10_000;
/// At most this many candidates without a point: none is nearer than
/// another, a sample of the many matches of a common word is ranked.
const INDEX_CAP: i64 = 1_000;
/// Places read beyond `first`, for those told twice that leave the list
/// (`lunaway_domain::search::repeated`): a page rarely holds more than one.
const REPEAT_SLACK: i64 = 5;

/// Live places matching `text` (accents and case ignored), at most
/// `first`, best first: see the module documentation for the order. `near`
/// is a point already coarsened by the caller.
///
/// # Errors
///
/// [`DbError`] when a query fails other than by its time limit, or a row
/// does not decode.
pub async fn search(
    pool: &PgPool,
    text: &str,
    near: Option<Position>,
    first: i64,
) -> Result<Vec<PlaceRow>, DbError> {
    search_on(pool, text, near, first, None).await
}

/// [`search`] with its candidates found `path`'s way rather than the
/// cheaper one the statistics point to: for the tests and the benchmarks
/// that compare the ways.
///
/// # Errors
///
/// As [`search`].
#[doc(hidden)]
pub async fn search_by_path(
    pool: &PgPool,
    text: &str,
    near: Option<Position>,
    first: i64,
    path: LookupPath,
) -> Result<Vec<PlaceRow>, DbError> {
    search_on(pool, text, near, first, Some(path)).await
}

async fn search_on(
    pool: &PgPool,
    text: &str,
    near: Option<Position>,
    first: i64,
    forced: Option<LookupPath>,
) -> Result<Vec<PlaceRow>, DbError> {
    let mut tx = pool.begin().await?;
    // The plan of each statement is the same whatever the words: the path
    // is chosen here, by a parameter its branches test at run time, and the
    // text search queries reach the planner through a scalar subquery. A
    // generic plan, made once per connection, saves planning the main
    // statement again at each search (1.5 ms on average, 27 ms at worst on
    // the test server).
    sqlx::query!(
        "SELECT set_config('statement_timeout', $1, true) AS time_limit,
                set_config('plan_cache_mode', 'force_generic_plan', true) AS plan_mode",
        STATEMENT_LIMIT
    )
    .fetch_one(&mut *tx)
    .await?;
    let (shares, places) = match statistics(&mut tx).await {
        Ok(found) => found,
        Err(e) if timed_out(&e) => return Ok(gave_up("statistics")),
        Err(e) => return Err(e),
    };
    let words = match query_words(&mut tx, text).await {
        Ok(words) => words,
        Err(e) if timed_out(&e) => return Ok(gave_up("words")),
        Err(e) => return Err(e),
    };
    let Some(query) = PlaceQuery::new(&words) else {
        return Ok(Vec::new());
    };
    let nearest = (first * NEAREST_PER_RESULT).max(NEAREST_MIN);
    let path = forced.unwrap_or_else(|| {
        query.path(
            &shares,
            places,
            near.is_some(),
            u32::try_from(nearest).unwrap_or(u32::MAX),
        )
    });
    let ask = Ask {
        query: &query,
        lookup: query.lookup(&shares, places),
        towns: query.town_names(),
        near,
        nearest,
        first,
    };
    let mut attempt = (&mut *tx).begin().await?;
    let rows = match ask.run(&mut attempt, path).await {
        Ok(rows) => {
            attempt.commit().await?;
            rows
        }
        Err(e) if timed_out(&e) => {
            attempt.rollback().await?;
            let other = match path {
                LookupPath::Index if near.is_some() => LookupPath::Nearest,
                LookupPath::Index => LookupPath::Scan,
                LookupPath::Nearest | LookupPath::Scan | LookupPath::Kind => LookupPath::Index,
            };
            tracing::warn!(
                ?path,
                ?other,
                "place search over its time limit, tried the other way"
            );
            match ask.run(&mut tx, other).await {
                Ok(rows) => rows,
                Err(e) if timed_out(&e) => return Ok(gave_up("both ways")),
                Err(e) => return Err(e),
            }
        }
        Err(e) => return Err(e),
    };
    let mut rows = rows
        .into_iter()
        .map(PlaceRow::try_from)
        .collect::<Result<Vec<_>, _>>()?;
    let repeats = match repeats(&mut tx, &rows).await {
        Ok(repeats) => repeats,
        // The places were found: told twice rather than not at all.
        Err(e) if timed_out(&e) => Vec::new(),
        Err(e) => return Err(e),
    };
    tx.commit().await?;
    for i in repeats.into_iter().rev() {
        rows.remove(i);
    }
    rows.truncate(usize::try_from(first).unwrap_or(0));
    Ok(rows)
}

/// The positions of the places of `rows` that tell an earlier one again
/// (`lunaway_domain::search::repeated`). Where the records place them is
/// read only when two places are alike.
async fn repeats(
    tx: &mut Transaction<'_, Postgres>,
    rows: &[PlaceRow],
) -> Result<Vec<usize>, DbError> {
    let listed: Vec<Listed<'_>> = rows
        .iter()
        .map(|r| Listed {
            kind: r.kind,
            name: r.name.as_deref(),
            municipality: r.municipality.as_deref(),
            position: r.position,
        })
        .collect();
    let pairs = alike(&listed);
    if pairs.is_empty() {
        return Ok(Vec::new());
    }
    let ids: Vec<Uuid> = pairs
        .iter()
        .flat_map(|&(a, b)| [rows[a].id, rows[b].id])
        .collect();
    let found = sqlx::query!(
        r#"
        SELECT s.place_id, r.source_id, r.accuracy_m
        FROM place_sources s
        JOIN source_records r ON r.id = s.record_id
        WHERE s.place_id = ANY($1) AND r.deleted_at IS NULL
        "#,
        &ids
    )
    .fetch_all(&mut **tx)
    .await?;
    let placement = |i: usize| {
        let mut p = Placement::default();
        for f in found.iter().filter(|f| f.place_id == rows[i].id) {
            if !p.sources.contains(&f.source_id) {
                p.sources.push(f.source_id.clone());
            }
            p.accuracy_m = Some(p.accuracy_m.map_or(f.accuracy_m, |a| a.min(f.accuracy_m)));
        }
        p
    };
    Ok(repeated(&pairs, |a, b| {
        one_place(&placement(a), &placement(b))
    }))
}

/// Whether a statement was cancelled by its time limit (SQLSTATE 57014).
fn timed_out(e: &DbError) -> bool {
    matches!(e, DbError::Query(sqlx::Error::Database(d)) if d.code().as_deref() == Some("57014"))
}

/// No place, logged: the search answers with the addresses alone rather
/// than an error. The text is not logged.
fn gave_up(step: &'static str) -> Vec<PlaceRow> {
    tracing::warn!(step, "place search over its time limit, no place returned");
    Vec::new()
}

/// The share of places holding each of their most common words, and the
/// number of places, from the planner's statistics; empty and zero before
/// the table was first analysed.
async fn statistics(tx: &mut Transaction<'_, Postgres>) -> Result<(WordShares, f64), DbError> {
    let row = sqlx::query!(
        r#"
        SELECT c.reltuples::float8 AS "places!",
               s.most_common_elems::text::text[] AS words,
               s.most_common_elem_freqs AS freqs
        FROM pg_class c
        LEFT JOIN pg_stats s
               ON s.schemaname = 'public' AND s.tablename = 'places'
              AND s.attname = 'search_vector'
        WHERE c.oid = 'places'::regclass
        "#
    )
    .fetch_one(&mut **tx)
    .await?;
    let shares = WordShares::new(
        row.words.unwrap_or_default(),
        row.freqs.as_deref().unwrap_or_default(),
    );
    Ok((shares, row.places.max(0.0)))
}

/// The folded words of `text`, whether a place holds a word starting with
/// each, and for those none does, the words of places that look like them.
async fn query_words(
    tx: &mut Transaction<'_, Postgres>,
    text: &str,
) -> Result<Vec<QueryWord>, DbError> {
    // `%` keeps the words sharing at least 30 % of their trigrams
    // (pg_trgm's default threshold); the edit distance then picks among
    // them (`lunaway_domain::search`).
    let rows = sqlx::query!(
        r#"
        SELECT u.word AS "word!", k.known AS "known!",
               CASE WHEN k.known THEN ARRAY[]::text[]
                    ELSE ARRAY(SELECT x.word::text FROM place_search_words x
                               WHERE x.word % u.word
                               ORDER BY similarity(x.word, u.word) DESC, x.word
                               LIMIT 20)
               END AS "lookalikes!"
        FROM unnest(lunaway_search_words($1)) WITH ORDINALITY AS u(word, ord)
        CROSS JOIN LATERAL (
            SELECT EXISTS (
                SELECT 1 FROM place_search_words x
                WHERE x.word >= u.word COLLATE "C"
                  AND x.word < (u.word || chr(1114111)) COLLATE "C"
            ) AS known
        ) k
        ORDER BY u.ord
        "#,
        text
    )
    .fetch_all(&mut **tx)
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| QueryWord {
            word: r.word,
            known: r.known,
            lookalikes: r.lookalikes,
        })
        .collect())
}

/// One search, ready to run one way or the other.
struct Ask<'a> {
    query: &'a PlaceQuery,
    lookup: String,
    towns: Vec<String>,
    near: Option<Position>,
    nearest: i64,
    first: i64,
}

impl Ask<'_> {
    async fn run(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        path: LookupPath,
    ) -> Result<Vec<PlaceDb>, DbError> {
        // Places of a kind are ranked by distance alone: the nearest `first`
        // are the answer, with the few that may leave the list as told
        // twice, and walking out from the point costs more for each one
        // taken (parking: one place in 80 is a car park).
        let nearest = if path == LookupPath::Kind {
            self.first + REPEAT_SLACK
        } else {
            self.nearest
        };
        let path = match path {
            LookupPath::Index => "index",
            LookupPath::Nearest => "nearest",
            LookupPath::Scan => "scan",
            LookupPath::Kind => "kind",
        };
        let kinds: Vec<String> = self
            .query
            .kinds()
            .iter()
            .map(|k| k.code().to_owned())
            .collect();
        let cap = if self.near.is_some() {
            INDEX_CAP_NEAR
        } else {
            INDEX_CAP
        };
        // The text search queries and the point are computed once, in `q`,
        // and read through scalar subqueries: the planner then sees no
        // constant to second-guess the path with, and no row parses them
        // again. Each branch of `candidates` runs only on its path, so no
        // place comes twice. Only the best are read whole, a few more than
        // `first` for the places told twice that leave the list.
        let rows = sqlx::query_as!(
            PlaceDb,
            r#"
            WITH q AS MATERIALIZED (
                SELECT to_tsquery('simple', $3) AS filter, to_tsquery('simple', $4) AS lookup,
                       to_tsquery('simple', $5) AS phrase, to_tsquery('simple', $6) AS typed,
                       to_tsquery('simple', $7) AS every,
                       -- Null for a text that names nothing as typed:
                       -- generic words only, or a corrected word.
                       to_tsquery('simple', $14) AS naming,
                       ST_SetSRID(ST_MakePoint($2::float8, $1::float8), 4326)::geography AS focus,
                       -- How long a town's name may be as written for its
                       -- folded name to be one of the texts: folding
                       -- expands a ligature, and turns a run of signs
                       -- between two words (" - ") into one space.
                       (SELECT min(length(n)) - 2 FROM unnest($13::text[]) n) AS town_shortest,
                       (SELECT max(length(n) + 2 * (length(n) - length(replace(n, ' ', ''))) + 2)
                        FROM unnest($13::text[]) n) AS town_longest
            ),
            candidates AS (
                (SELECT id, kind, geom, search_vector, search_text, name, city, municipality
                 FROM places
                 WHERE $9::text = 'index' AND deleted_at IS NULL
                   AND search_vector @@ (SELECT lookup FROM q)
                   AND ts_match_vq(search_vector, (SELECT filter FROM q))
                 LIMIT $11)
                UNION ALL
                (SELECT id, kind, geom, search_vector, search_text, name, city, municipality
                 FROM places
                 WHERE $9 = 'nearest' AND deleted_at IS NULL
                   AND ts_match_vq(search_vector, (SELECT filter FROM q))
                 ORDER BY geom <-> (SELECT focus FROM q)
                 LIMIT $10)
                UNION ALL
                (SELECT id, kind, geom, search_vector, search_text, name, city, municipality
                 FROM places
                 WHERE $9 = 'scan' AND deleted_at IS NULL
                   AND ts_match_vq(search_vector, (SELECT filter FROM q))
                 LIMIT $11)
                UNION ALL
                (SELECT id, kind, geom, search_vector, search_text, name, city, municipality
                 FROM places
                 WHERE $9 = 'kind' AND deleted_at IS NULL
                   AND kind = ANY($8::text[])
                 ORDER BY geom <-> (SELECT focus FROM q)
                 LIMIT $10)
            ),
            -- The ranking keys of each candidate but its town's, with its
            -- town: what the next steps read, without the heavy columns.
            -- `whole`: whether it holds the words naming a place as whole
            -- words, in its name or its town; the costlier tests of the town
            -- and the name run only for those. `town_words`: whether the
            -- text of its town, after its name in `search_text`, holds them.
            found AS (
                SELECT id, municipality, city,
                       whole AND substr(search_text, coalesce(length(name), 0) + 1)
                                 LIKE ALL($15::text[]) AS town_words,
                       CASE WHEN $9 = 'kind' THEN 0
                            WHEN search_vector @@ (SELECT phrase FROM q) THEN 4
                            WHEN search_vector @@ (SELECT typed FROM q) THEN 3
                            WHEN search_vector @@ (SELECT every FROM q) THEN 2
                            ELSE 1
                       END AS tier,
                       kind = ANY($8) AS kind_match,
                       -- The folded name starts `search_text`, its town
                       -- follows. A name that lacks a word stops at the
                       -- patterns; when the town holds none, the whole
                       -- words are the name's. Only a name that shares a
                       -- word with its town ("Ferme du Lac", La Ferme) has
                       -- its own words compared, the costly test. Folding
                       -- keeps a name's length but for a ligature it
                       -- expands ("Cœur" gives "coeur"), which the 2
                       -- extra characters cover up to two of, and a
                       -- decomposed accent it drops, rare in the sources'
                       -- names: past those, only the order of a few places
                       -- may move.
                       CASE WHEN NOT whole OR name IS NULL THEN false
                            WHEN NOT left(search_text, length(name) + 2) LIKE ALL($15::text[])
                                THEN false
                            WHEN NOT substr(search_text, length(name) + 1) LIKE ANY($15::text[])
                                THEN true
                            ELSE (lunaway_search_vector(name, NULL, NULL)
                                  @@ (SELECT naming FROM q)) IS TRUE
                       END AS named,
                       CASE WHEN $1 IS NULL THEN 0 ELSE geom <-> (SELECT focus FROM q) END AS distance,
                       length(search_text) AS length
                FROM (SELECT c.*, (search_vector @@ (SELECT naming FROM q)) IS TRUE AS whole
                      FROM candidates c) c
            ),
            -- The towns the text names whole, each town of a fitting length
            -- folded once (the places of a town share its name), kept apart
            -- so that the planner does not fold every candidate's.
            towns AS MATERIALIZED (
                SELECT municipality AS t FROM found
                WHERE town_words AND length(municipality) BETWEEN (SELECT town_shortest FROM q)
                                                              AND (SELECT town_longest FROM q)
                UNION
                SELECT city FROM found
                WHERE town_words AND length(city) BETWEEN (SELECT town_shortest FROM q)
                                                      AND (SELECT town_longest FROM q)
            ),
            named_towns AS (
                SELECT t FROM towns WHERE lunaway_town_fold(t) = ANY($13::text[])
            ),
            best AS (
                SELECT id, tier,
                       town_words AND (municipality IN (SELECT t FROM named_towns)
                                       OR city IN (SELECT t FROM named_towns)) IS TRUE AS in_town,
                       kind_match, named, distance, length
                FROM found
                ORDER BY tier DESC, in_town DESC, kind_match DESC, named DESC, distance, length, id
                LIMIT $12
            )
            SELECT p.id, p.kind, p.name, ST_Y(p.geom::geometry) AS "lat!", ST_X(p.geom::geometry) AS "lon!",
                   p.overnight, p.services, p.activities, p.description, p.street, p.postcode, p.city,
                   p.country_code, p.price_parking_eur, p.price_services_eur,
                   p.price_services_included, p.price_parking_includes, p.max_height_m,
                   p.max_length_m, p.max_width_m, p.max_weight_t, p.capacity,
                   p.opening_hours, p.opening_hours_parsed, p.opening_intervals,
                   p.opening_intervals_until, p.website, p.phone, p.stars, p.last_confirmed_at,
                   p.updated_at, p.updated_seq, p.provenance,
                   p.deleted_at IS NOT NULL AS "deleted!", p.merged_into, p.municipality,
                   p.descriptions, p.external_links, p.rating_avg, p.rating_count, p.review_count,
                   p.photo_count, p.cover_photos, p.reported_issues, p.verification, p.region,
                   p.filter_rating, p.opening_season
            FROM best JOIN places p USING (id)
            ORDER BY best.tier DESC, best.in_town DESC, best.kind_match DESC, best.named DESC,
                     best.distance, best.length, best.id
            "#,
            self.near.map(Position::lat),
            self.near.map(Position::lon),
            self.query.filter(),
            self.lookup,
            self.query.phrase(),
            self.query.phrase_typed(),
            self.query.every_word(),
            &kinds,
            path,
            nearest,
            cap,
            self.first + REPEAT_SLACK,
            &self.towns,
            self.query.naming(),
            &self.query.naming_patterns(),
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}
