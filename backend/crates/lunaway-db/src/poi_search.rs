//! Searching the points of interest and establishments by name, brand,
//! kind and town (`lunaway_domain::poi_search`).
//!
//! The candidates come from `poi_search`, a narrow copy of the live points
//! (kind, position, words) the triggers of `pois` keep: by the GIN index of
//! the words when few points hold them, by walking the spatial index out
//! from the point the results are ranked around when many do, by reading
//! the table in order without such a point. A query by kind ("coiffeur",
//! "pizzeria") is a query of the tokens of those kinds. The cheaper way is
//! chosen from the planner's statistics of the words (`pg_stats`).
//!
//! Then, for a query by name: its words in their order as whole words,
//! then with the last one being typed, then all of them in any order, then
//! the naming words only; the points of the kinds it names; the nearest;
//! the shortest name. A query by kind: the nearest. When the text ends on a
//! town the towns of the search know (`place_towns`), the results are
//! ranked around that town and its words filter nothing.
//!
//! Only the `first` best are read whole from `pois`. An establishment of
//! another source than OpenStreetMap that names the same shop as an
//! OpenStreetMap point near it is left out: OpenStreetMap's is kept.
//!
//! Every statement has a short time limit, as for the places
//! (`crate::search`): past it the other way is tried, then no point is
//! returned rather than an error. The text and the point are never logged.

use lunaway_domain::{
    Position, SourceId,
    conflation::normalize::fold,
    poi::{PoiCategory, PoiKind},
    poi_search::{PoiMatch, PoiQuery, looks_like_address},
    search::{LookupPath, QueryWord, WordShares},
};
use sqlx::{Acquire, Postgres, Transaction};
use uuid::Uuid;

use crate::{
    DbError, PgPool,
    pois::{self, PoiRow},
    towns::TownRow,
};

/// Time limit of each statement of a search.
const STATEMENT_LIMIT: &str = "250ms";

/// Candidates kept around a point for each result asked: the ranking puts
/// better name matches before nearer ones, and the shops another source
/// names twice are dropped after it.
const NEAREST_PER_RESULT: i64 = 3;
/// At least this many candidates around a point.
const NEAREST_MIN: i64 = 40;
/// At most this many candidates from the index around a point.
const INDEX_CAP_NEAR: i64 = 20_000;
/// At most this many candidates without a point.
const INDEX_CAP: i64 = 1_000;
/// How near the point asked a point named exactly as typed comes first,
/// metres: "le petit bistrot" brings the Petit Bistrot of the town first,
/// not one 300 km away before the bistros around.
const EXACT_NEAR_M: f64 = 30_000.0;
/// How close an establishment of another source must be to an
/// OpenStreetMap point of a like name to be the same shop, metres.
const SAME_SHOP_M: f64 = 150.0;
/// Places a town of the search holds for its name, ending a text, to be
/// taken as the town without a preposition before it: "pizzeria annecy"
/// (80 places on 2026-10-10) is in Annecy, "boulangerie paul" names the
/// bakeries Paul, not the hamlet of Paul in Portugal (6 places). A smaller
/// town is taken when a preposition names it ("à", "in") or when nothing
/// bears the name.
const TOWN_MIN_PLACES: i32 = 10;

/// What the search of points needs of the planner's statistics: how many
/// points hold each common word, and how many points there are. Read once
/// and kept a few minutes by the API: the list of words is long.
#[derive(Debug, Clone, Default)]
pub struct PoiStats {
    shares: WordShares,
    points: f64,
}

/// The statistics of `poi_search` (empty and zero before it was first
/// analysed).
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn statistics(pool: &PgPool) -> Result<PoiStats, DbError> {
    let row = sqlx::query!(
        r#"
        SELECT c.reltuples::float8 AS "points!",
               s.most_common_elems::text::text[] AS words,
               s.most_common_elem_freqs AS freqs
        FROM pg_class c
        LEFT JOIN pg_stats s
               ON s.schemaname = 'public' AND s.tablename = 'poi_search' AND s.attname = 'words'
        WHERE c.oid = 'poi_search'::regclass
        "#
    )
    .fetch_one(pool)
    .await?;
    Ok(PoiStats {
        shares: WordShares::new(
            row.words.unwrap_or_default(),
            row.freqs.as_deref().unwrap_or_default(),
        ),
        points: row.points.max(0.0),
    })
}

/// What a search asks.
#[derive(Debug, Clone, Copy)]
pub struct PoiAsk<'a> {
    /// The text typed.
    pub text: &'a str,
    /// The point to rank around, already coarsened by the caller.
    pub near: Option<Position>,
    /// Most points returned.
    pub first: i64,
    /// Only the points of these categories, when given.
    pub categories: Option<&'a [PoiCategory]>,
}

/// What a search found.
#[derive(Debug, Clone, PartialEq)]
pub struct PoiSearch {
    /// The points, best first, each with its distance from the point they
    /// were ranked around.
    pub rows: Vec<PoiRow>,
    /// The kinds the text names.
    pub kinds: Vec<PoiKind>,
    /// How the points answer the text.
    pub matched: PoiMatch,
    /// The town the text ended on, which the points were ranked around.
    pub town: Option<TownRow>,
}

impl PoiSearch {
    fn empty(kinds: Vec<PoiKind>) -> Self {
        Self {
            rows: Vec::new(),
            kinds,
            matched: PoiMatch::None,
            town: None,
        }
    }
}

/// The points matching `ask` (accents and case ignored), best first: see the
/// module documentation for the order.
///
/// # Errors
///
/// [`DbError`] when a query fails other than by its time limit, or a row
/// does not decode.
pub async fn search(
    pool: &PgPool,
    ask: PoiAsk<'_>,
    stats: &PoiStats,
) -> Result<PoiSearch, DbError> {
    search_on(pool, ask, stats, None).await
}

/// [`search`] with its candidates found `path`'s way: for the tests and the
/// benchmarks that compare the ways.
///
/// # Errors
///
/// As [`search`].
#[doc(hidden)]
pub async fn search_by_path(
    pool: &PgPool,
    ask: PoiAsk<'_>,
    stats: &PoiStats,
    path: LookupPath,
) -> Result<PoiSearch, DbError> {
    search_on(pool, ask, stats, Some(path)).await
}

async fn search_on(
    pool: &PgPool,
    ask: PoiAsk<'_>,
    stats: &PoiStats,
    forced: Option<LookupPath>,
) -> Result<PoiSearch, DbError> {
    let mut tx = begin(pool).await?;
    let words = match query_words(&mut tx, ask.text).await {
        Ok(words) => words,
        Err(e) if timed_out(&e) => return Ok(gave_up("words", Vec::new())),
        Err(e) => return Err(e),
    };
    let Some(mut query) = PoiQuery::new(&words) else {
        return Ok(PoiSearch::empty(Vec::new()));
    };
    let folded: Vec<&str> = words.iter().map(|w| w.word.as_str()).collect();
    let mut town = None;
    // A small town without a preposition is kept for when the text names
    // nothing as it is.
    let mut maybe_town = None;
    let candidates = query.town_candidates();
    if !candidates.is_empty() {
        let found = match find_town(&mut tx, &candidates, ask.near).await {
            Ok(found) => found,
            Err(e) if timed_out(&e) => None,
            Err(e) => return Err(e),
        };
        if let Some((row, take)) = found
            && let Some(rest) = query.without_last(take)
        {
            if row.places >= TOWN_MIN_PLACES || query.preposition_before(take) {
                query = rest;
                town = Some(row);
            } else {
                maybe_town = Some((row, rest));
            }
        }
    }
    let found = look(&mut tx, &query, town.as_ref(), ask, stats, forced).await?;
    tx.commit().await?;
    let (query, town, found) = match (found.is_empty(), maybe_town) {
        (true, Some((row, rest))) => {
            let mut tx = begin(pool).await?;
            let found = look(&mut tx, &rest, Some(&row), ask, stats, forced).await?;
            tx.commit().await?;
            (rest, Some(row), found)
        }
        _ => (query, town, found),
    };
    let Some(found) = found.into_result() else {
        return Ok(gave_up("both ways", query.kinds()));
    };
    let kinds = query.kinds();
    let best_tier = found.first().map_or(0, |c| c.tier);
    let ids: Vec<Uuid> = found.iter().map(|c| c.id).collect();
    let mut rows = pois::by_ids(pool, &ids).await?;
    // In the ranking's order, each with its distance from the point the
    // results were ranked around.
    rows.sort_by_key(|r| ids.iter().position(|id| *id == r.id));
    for r in &mut rows {
        r.distance_m = found
            .iter()
            .find(|c| c.id == r.id)
            .and_then(|c| c.distance_m);
    }
    let mut rows = without_twins(rows);
    rows.truncate(usize::try_from(ask.first).unwrap_or(0));
    let matched = if rows.is_empty() {
        PoiMatch::None
    } else if query.by_kind() {
        PoiMatch::Kind
    } else if best_tier >= 3 && !looks_like_address(&folded) {
        PoiMatch::Name
    } else {
        PoiMatch::Partial
    };
    Ok(PoiSearch {
        rows,
        kinds,
        matched,
        town,
    })
}

/// A transaction whose statements have the search's time limit and a
/// generic plan: the plan of each statement is the same whatever the words
/// (the path is chosen here, by a parameter its branches test at run
/// time), and planning the main statement again at each search would cost
/// a millisecond or two.
async fn begin(pool: &PgPool) -> Result<Transaction<'static, Postgres>, DbError> {
    let mut tx = pool.begin().await?;
    sqlx::query!(
        "SELECT set_config('statement_timeout', $1, true) AS time_limit,
                set_config('plan_cache_mode', 'force_generic_plan', true) AS plan_mode",
        STATEMENT_LIMIT
    )
    .fetch_one(&mut *tx)
    .await?;
    Ok(tx)
}

/// What a look for candidates gave: the candidates, or that it ran past its
/// time limit both ways.
enum Found {
    Some(Vec<Candidate>),
    GaveUp,
}

impl Found {
    fn is_empty(&self) -> bool {
        matches!(self, Self::Some(c) if c.is_empty())
    }

    fn into_result(self) -> Option<Vec<Candidate>> {
        match self {
            Self::Some(c) => Some(c),
            Self::GaveUp => None,
        }
    }
}

/// The candidates of `query` around `town` or the point asked, the cheaper
/// way, then the other way when the first runs past its time limit.
async fn look(
    tx: &mut Transaction<'_, Postgres>,
    query: &PoiQuery,
    town: Option<&TownRow>,
    ask: PoiAsk<'_>,
    stats: &PoiStats,
    forced: Option<LookupPath>,
) -> Result<Found, DbError> {
    let anchor = town
        .and_then(|t| Position::new(t.lat, t.lon).ok())
        .or(ask.near);
    if query.by_kind() && anchor.is_none() {
        // The nearest of a kind, without a point to be near: nothing to say.
        return Ok(Found::Some(Vec::new()));
    }
    let nearest = (ask.first * NEAREST_PER_RESULT).max(NEAREST_MIN);
    let path = forced.unwrap_or_else(|| {
        query.path(
            &stats.shares,
            stats.points,
            anchor.is_some(),
            u32::try_from(nearest).unwrap_or(u32::MAX),
        )
    });
    let path = if path == LookupPath::Kind {
        LookupPath::Nearest
    } else {
        path
    };
    let (filter, lookup) = if query.by_kind() {
        (query.types(), query.types())
    } else {
        (query.filter(), query.lookup(&stats.shares, stats.points))
    };
    let only: Option<Vec<String>> = ask.categories.map(|cats| {
        cats.iter()
            .flat_map(|c| c.kinds())
            .map(|k| k.code().to_owned())
            .collect()
    });
    let run = Run {
        query,
        filter: &filter,
        lookup: &lookup,
        near: anchor,
        nearest,
        first: ask.first,
        only: only.as_deref(),
    };
    let mut attempt = (&mut **tx).begin().await?;
    let found = match run.candidates(&mut attempt, path).await {
        Ok(found) => {
            attempt.commit().await?;
            found
        }
        Err(e) if timed_out(&e) => {
            attempt.rollback().await?;
            let other = match path {
                LookupPath::Index if anchor.is_some() => LookupPath::Nearest,
                LookupPath::Index => LookupPath::Scan,
                LookupPath::Nearest | LookupPath::Scan | LookupPath::Kind => LookupPath::Index,
            };
            tracing::warn!(
                ?path,
                ?other,
                "point search over its time limit, tried the other way"
            );
            match run.candidates(tx, other).await {
                Ok(found) => found,
                Err(e) if timed_out(&e) => return Ok(Found::GaveUp),
                Err(e) => return Err(e),
            }
        }
        Err(e) => return Err(e),
    };
    Ok(Found::Some(found))
}

/// The points without an establishment of another source than
/// OpenStreetMap that names the same shop as an OpenStreetMap point near
/// it: its name's words mostly those of the other's, within
/// [`SAME_SHOP_M`]. The OpenStreetMap point stays, with its hours and its
/// contributors' care.
fn without_twins(rows: Vec<PoiRow>) -> Vec<PoiRow> {
    let words = |r: &PoiRow| -> Vec<String> {
        r.record
            .name
            .as_deref()
            .map(fold)
            .unwrap_or_default()
            .split(' ')
            .filter(|w| w.len() > 2)
            .map(str::to_owned)
            .collect()
    };
    let osm: Vec<(Position, Vec<String>)> = rows
        .iter()
        .filter(|r| r.source_id == SourceId::OSM)
        .map(|r| (r.record.position, words(r)))
        .collect();
    rows.into_iter()
        .filter(|r| {
            if r.source_id == SourceId::OSM {
                return true;
            }
            let mine = words(r);
            !osm.iter().any(|(at, theirs)| {
                at.distance_m(r.record.position) <= SAME_SHOP_M && alike(&mine, theirs)
            })
        })
        .collect()
}

/// Whether two names share at least half the words of the shorter.
fn alike(a: &[String], b: &[String]) -> bool {
    let shorter = a.len().min(b.len());
    if shorter == 0 {
        return false;
    }
    let shared = a.iter().filter(|w| b.contains(w)).count();
    shared * 2 >= shorter
}

/// Whether a statement was cancelled by its time limit (SQLSTATE 57014).
fn timed_out(e: &DbError) -> bool {
    matches!(e, DbError::Query(sqlx::Error::Database(d)) if d.code().as_deref() == Some("57014"))
}

/// No point, logged: the search answers with the places and addresses
/// alone rather than an error. The text is not logged.
fn gave_up(step: &'static str, kinds: Vec<PoiKind>) -> PoiSearch {
    tracing::warn!(step, "point search over its time limit, no point returned");
    PoiSearch::empty(kinds)
}

/// The folded words of `text`, whether a point holds a word starting with
/// each, and for those none does, the words of points that look like them.
async fn query_words(
    tx: &mut Transaction<'_, Postgres>,
    text: &str,
) -> Result<Vec<QueryWord>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT u.word AS "word!", k.known AS "known!",
               CASE WHEN k.known THEN ARRAY[]::text[]
                    ELSE ARRAY(SELECT x.word::text FROM poi_search_words x
                               WHERE x.word % u.word
                               ORDER BY similarity(x.word, u.word) DESC, x.word
                               LIMIT 20)
               END AS "lookalikes!"
        FROM unnest(lunaway_search_words($1)) WITH ORDINALITY AS u(word, ord)
        CROSS JOIN LATERAL (
            SELECT EXISTS (
                SELECT 1 FROM poi_search_words x
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

/// The town among `candidates` (folded texts, longest first, with how
/// many words each takes) that a town of the search bears: the longest
/// that one bears; among homonyms the nearest to `near`, else the one with
/// most places.
async fn find_town(
    tx: &mut Transaction<'_, Postgres>,
    candidates: &[(String, usize)],
    near: Option<Position>,
) -> Result<Option<(TownRow, usize)>, DbError> {
    let texts: Vec<String> = candidates.iter().map(|(t, _)| t.clone()).collect();
    let row = sqlx::query!(
        r#"
        SELECT name, postcode, department, country_code, places, lat, lon, folded
        FROM place_towns
        WHERE folded = ANY($1)
        ORDER BY array_position($1, folded),
                 CASE WHEN $2::float8 IS NULL THEN 0 ELSE
                      ST_Distance(ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography,
                                  ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography) END,
                 places DESC, key
        LIMIT 1
        "#,
        &texts,
        near.map(Position::lat),
        near.map(Position::lon),
    )
    .fetch_optional(&mut **tx)
    .await?;
    Ok(row.and_then(|r| {
        let take = candidates.iter().find(|(t, _)| *t == r.folded)?.1;
        Some((
            TownRow {
                name: r.name,
                postcode: r.postcode,
                department: r.department,
                country_code: r.country_code,
                places: r.places,
                lat: r.lat,
                lon: r.lon,
            },
            take,
        ))
    }))
}

/// One candidate, ranked.
#[derive(Debug, Clone, Copy)]
struct Candidate {
    id: Uuid,
    tier: i32,
    distance_m: Option<f64>,
}

/// One search, ready to run one way or the other.
struct Run<'a> {
    query: &'a PoiQuery,
    filter: &'a str,
    lookup: &'a str,
    near: Option<Position>,
    nearest: i64,
    first: i64,
    only: Option<&'a [String]>,
}

impl Run<'_> {
    async fn candidates(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        path: LookupPath,
    ) -> Result<Vec<Candidate>, DbError> {
        let path = match path {
            LookupPath::Index => "index",
            LookupPath::Nearest | LookupPath::Kind => "nearest",
            LookupPath::Scan => "scan",
        };
        let cap = if self.near.is_some() {
            INDEX_CAP_NEAR
        } else {
            INDEX_CAP
        };
        let by_kind = self.query.by_kind();
        // The text search queries and the point are computed once, in `q`,
        // and read through scalar subqueries: the plan is the same whatever
        // the words. The queries are lexemes already folded, cast as they
        // are: the tokens of the kinds hold `_`, which the parser of
        // `to_tsquery` would split on. An empty one is NULL, and matches
        // nothing.
        let rows = sqlx::query!(
            r#"
            WITH q AS MATERIALIZED (
                SELECT NULLIF($3, '')::tsquery AS filter, NULLIF($4, '')::tsquery AS lookup,
                       NULLIF($5, '')::tsquery AS phrase, NULLIF($6, '')::tsquery AS typed,
                       NULLIF($7, '')::tsquery AS every, NULLIF($8, '')::tsquery AS types,
                       ST_SetSRID(ST_MakePoint($2::float8, $1::float8), 4326)::geography AS focus
            ),
            candidates AS (
                (SELECT id, geom, words, name_length FROM poi_search
                 WHERE $9::text = 'index'
                   AND words @@ (SELECT lookup FROM q)
                   AND ts_match_vq(words, (SELECT filter FROM q))
                   AND ($13::text[] IS NULL OR kind = ANY($13))
                 LIMIT $11)
                UNION ALL
                (SELECT id, geom, words, name_length FROM poi_search
                 WHERE $9 = 'nearest'
                   AND ts_match_vq(words, (SELECT filter FROM q))
                   AND ($13::text[] IS NULL OR kind = ANY($13))
                 ORDER BY geom <-> (SELECT focus FROM q)
                 LIMIT $10)
                UNION ALL
                (SELECT id, geom, words, name_length FROM poi_search
                 WHERE $9 = 'scan'
                   AND ts_match_vq(words, (SELECT filter FROM q))
                   AND ($13::text[] IS NULL OR kind = ANY($13))
                 LIMIT $11)
            )
            SELECT id AS "id!",
                   coalesce(words @@ NULLIF($15, '')::tsquery, false)
                       AND ($1::float8 IS NULL OR geom <-> (SELECT focus FROM q) < $16)
                       AS "exact!",
                   (CASE WHEN $14 THEN 0
                         WHEN coalesce(words @@ (SELECT phrase FROM q), false) THEN 4
                         WHEN coalesce(words @@ (SELECT typed FROM q), false) THEN 3
                         WHEN coalesce(words @@ (SELECT every FROM q), false) THEN 2
                         ELSE 1
                    END)::int4 AS "tier!",
                   CASE WHEN $1::float8 IS NULL THEN NULL
                        ELSE geom <-> (SELECT focus FROM q) END AS distance_m
            FROM candidates
            ORDER BY 2 DESC, 3 DESC,
                     coalesce(words @@ (SELECT types FROM q), false) DESC,
                     CASE WHEN $1::float8 IS NULL THEN 0
                          ELSE geom <-> (SELECT focus FROM q) END,
                     name_length, id
            LIMIT $12
            "#,
            self.near.map(Position::lat),
            self.near.map(Position::lon),
            self.filter,
            self.lookup,
            self.query.phrase(),
            self.query.phrase_typed(),
            self.query.every_word(),
            self.query.types(),
            path,
            self.nearest,
            cap,
            (self.first * NEAREST_PER_RESULT).max(self.first),
            self.only,
            by_kind,
            self.query.whole_phrase(),
            EXACT_NEAR_M,
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows
            .into_iter()
            .map(|r| Candidate {
                id: r.id,
                tier: r.tier,
                distance_m: r.distance_m,
            })
            .collect())
    }
}
