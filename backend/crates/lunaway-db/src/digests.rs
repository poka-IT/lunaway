//! What a list of places shows of each row beyond the place's summary
//! (`Query.placeDigests`): its ratings by source, the description an
//! excerpt is cut from, and the day Lunaway added it.

use std::collections::HashMap;

use chrono::{DateTime, Utc};
use lunaway_domain::BBox;
use uuid::Uuid;

use crate::{DbError, PgPool};

/// The longest part of a description read for an excerpt: three times
/// the excerpt (`listing::EXCERPT_CHARS`), room enough once the line
/// breaks and doubled spaces are collapsed, where a stored description may
/// hold two thousand.
const DESCRIPTION_READ_CHARS: i32 = 420;

/// A rating summary of one source.
#[derive(Debug, Clone, PartialEq)]
pub struct RatingSummary {
    /// Its source.
    pub source_id: String,
    /// Mean stars.
    pub average: f64,
    /// Ratings counted.
    pub count: i32,
}

/// One place's digest, its description not cut yet.
#[derive(Debug, Clone, PartialEq)]
pub struct DigestRow {
    /// The place.
    pub id: Uuid,
    /// When Lunaway added it.
    pub created_at: DateTime<Utc>,
    /// Lunaway users' ratings, when someone rated it.
    pub community: Option<RatingSummary>,
    /// The ratings of the other sources that hand a summary over: the
    /// external community source's, as the place's card reads them
    /// (`extcom::ratings_of_place`).
    pub external: Vec<RatingSummary>,
    /// The description in the language asked, else in English, else the
    /// first a source wrote; its first few hundred characters.
    pub description: Option<DescriptionStart>,
}

/// The opening of a description, before the excerpt is cut from it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DescriptionStart {
    /// Its language.
    pub lang: String,
    /// Its first characters.
    pub text: String,
    /// The source that wrote it.
    pub source_id: String,
}

/// The digests of the live places among `ids`, in no particular order; a
/// deleted or merged place is left out.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn of_places(pool: &PgPool, ids: &[Uuid], lang: &str) -> Result<Vec<DigestRow>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT p.id, p.created_at, p.rating_avg, p.rating_count,
               d.lang AS "lang?", left(d.text, $3) AS "text?", d.source_id AS "source_id?"
        FROM places p
        LEFT JOIN LATERAL (
            SELECT e.value->>'lang' AS lang, e.value->>'text' AS text,
                   e.value->>'sourceId' AS source_id
            FROM jsonb_array_elements(p.descriptions) WITH ORDINALITY AS e(value, n)
            WHERE coalesce(btrim(e.value->>'text'), '') <> ''
            ORDER BY (e.value->>'lang' = $2) DESC, (e.value->>'lang' = 'en') DESC, e.n
            LIMIT 1
        ) d ON true
        WHERE p.id = ANY($1) AND p.deleted_at IS NULL
        "#,
        ids,
        lang,
        DESCRIPTION_READ_CHARS,
    )
    .fetch_all(pool)
    .await?;
    let mut external = external_ratings(pool, ids).await?;
    Ok(rows
        .into_iter()
        .map(|r| DigestRow {
            id: r.id,
            created_at: r.created_at,
            community: match r.rating_avg {
                Some(average) if r.rating_count > 0 => Some(RatingSummary {
                    source_id: lunaway_domain::SourceId::COMMUNITY_CC_BY.to_string(),
                    average,
                    count: r.rating_count,
                }),
                _ => None,
            },
            external: external.remove(&r.id).unwrap_or_default(),
            description: match (r.lang, r.text, r.source_id) {
                (Some(lang), Some(text), Some(source_id)) => Some(DescriptionStart {
                    lang,
                    text,
                    source_id,
                }),
                _ => None,
            },
        })
        .collect())
}

/// The digests of the live places inside `bbox`, `limit` at most, in the
/// order of their ids.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn in_bbox(
    pool: &PgPool,
    bbox: BBox,
    lang: &str,
    limit: i64,
) -> Result<Vec<DigestRow>, DbError> {
    let ids = sqlx::query_scalar!(
        r#"
        SELECT id FROM places
        WHERE deleted_at IS NULL
          AND geom::geometry && ST_MakeEnvelope($1, $2, $3, $4, 4326)
        ORDER BY id
        LIMIT $5
        "#,
        bbox.west(),
        bbox.south(),
        bbox.east(),
        bbox.north(),
        limit,
    )
    .fetch_all(pool)
    .await?;
    let mut rows = of_places(pool, &ids, lang).await?;
    rows.sort_by_key(|r| r.id);
    Ok(rows)
}

/// The rating summaries of the records linked to each of `places`, one per
/// source not hidden, under the rules of `extcom::ratings_of_place` (a
/// mean weighted by the counts when two records of a source are linked to
/// a place), for many places at once.
async fn external_ratings(
    pool: &PgPool,
    places: &[Uuid],
) -> Result<HashMap<Uuid, Vec<RatingSummary>>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT ps.place_id, t.source_id,
               (sum(t.average * t.count) / sum(t.count))::float8 AS "average!",
               sum(t.count)::int4 AS "count!"
        FROM place_sources ps
        JOIN external_ratings t ON t.record_id = ps.record_id
        LEFT JOIN source_switches w ON w.source_id = t.source_id
        WHERE ps.place_id = ANY($1) AND w.hidden_at IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = t.source_id
                AND ((h.scope = 'place' AND h.key = ps.place_id::text) OR h.scope = 'source'))
        GROUP BY ps.place_id, t.source_id
        ORDER BY ps.place_id, t.source_id
        "#,
        places,
    )
    .fetch_all(pool)
    .await?;
    let mut by_place: HashMap<Uuid, Vec<RatingSummary>> = HashMap::new();
    for r in rows {
        by_place.entry(r.place_id).or_default().push(RatingSummary {
            source_id: r.source_id,
            average: r.average,
            count: r.count,
        });
    }
    Ok(by_place)
}
