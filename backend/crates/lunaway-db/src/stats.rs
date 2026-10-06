//! Counts that tell whether an import and a conflation did what they should.

use crate::{DbError, PgPool};

/// Records of one source.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SourceCount {
    /// The source.
    pub source_id: String,
    /// Records it lists today.
    pub live: i64,
    /// Records it no longer lists.
    pub deleted: i64,
    /// Records waiting for the conflation.
    pub dirty: i64,
}

/// Places of one kind.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KindCount {
    /// Kind code.
    pub kind: String,
    /// Live places.
    pub places: i64,
    /// Of which with two sources or more.
    pub merged: i64,
}

/// Places by the set of sources that describe them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SourceSetCount {
    /// Source ids, sorted, joined by `+`.
    pub sources: String,
    /// Live places.
    pub places: i64,
}

/// Review queue entries by reason.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReviewCount {
    /// Whether both records come from one source (a duplicate to report).
    pub same_source: bool,
    /// Pairs.
    pub pairs: i64,
}

/// Everything `lunaway stats` prints.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Stats {
    /// Per source.
    pub sources: Vec<SourceCount>,
    /// Live places.
    pub places: i64,
    /// Tombstones.
    pub tombstones: i64,
    /// Per kind.
    pub kinds: Vec<KindCount>,
    /// Per set of sources.
    pub source_sets: Vec<SourceSetCount>,
    /// Stored merge decisions.
    pub merge_pairs: i64,
    /// Review queue.
    pub review: Vec<ReviewCount>,
    /// Human constraints.
    pub constraints: i64,
    /// Live places with opening hours, and how many of them parse.
    pub opening_hours: (i64, i64),
    /// Places taken down that still hold reviews, photos, confirmations or
    /// issue reports: the second step of their takedown was not run.
    pub takedowns_unpurged: i64,
    /// Groups held near a place taken down, waiting for a moderator.
    pub holds_open: i64,
}

/// Reads the counts.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn read(pool: &PgPool) -> Result<Stats, DbError> {
    let sources = sqlx::query_as!(
        SourceCount,
        r#"
        SELECT s.id AS source_id,
               count(r.id) FILTER (WHERE r.deleted_at IS NULL) AS "live!",
               count(r.id) FILTER (WHERE r.deleted_at IS NOT NULL) AS "deleted!",
               count(r.id) FILTER (WHERE r.needs_conflation) AS "dirty!"
        FROM sources s LEFT JOIN source_records r ON r.source_id = s.id
        GROUP BY s.id ORDER BY s.id
        "#
    )
    .fetch_all(pool)
    .await?;
    let totals = sqlx::query!(
        r#"
        SELECT count(*) FILTER (WHERE deleted_at IS NULL) AS "places!",
               count(*) FILTER (WHERE deleted_at IS NOT NULL) AS "tombstones!",
               count(*) FILTER (WHERE deleted_at IS NULL AND opening_hours IS NOT NULL) AS "oh!",
               count(*) FILTER (WHERE deleted_at IS NULL AND opening_hours_parsed) AS "oh_parsed!"
        FROM places
        "#
    )
    .fetch_one(pool)
    .await?;
    let kinds = sqlx::query_as!(
        KindCount,
        r#"
        SELECT p.kind, count(*) AS "places!",
               count(*) FILTER (WHERE n.n >= 2) AS "merged!"
        FROM places p
        JOIN (SELECT place_id, count(*) AS n FROM place_sources GROUP BY place_id) n
          ON n.place_id = p.id
        WHERE p.deleted_at IS NULL
        GROUP BY p.kind ORDER BY count(*) DESC
        "#
    )
    .fetch_all(pool)
    .await?;
    let source_sets = sqlx::query_as!(
        SourceSetCount,
        r#"
        SELECT sources AS "sources!", count(*) AS "places!"
        FROM (
            SELECT ps.place_id, string_agg(DISTINCT r.source_id, '+' ORDER BY r.source_id) AS sources
            FROM place_sources ps JOIN source_records r ON r.id = ps.record_id
            JOIN places p ON p.id = ps.place_id AND p.deleted_at IS NULL
            GROUP BY ps.place_id
        ) t
        GROUP BY sources ORDER BY count(*) DESC
        "#
    )
    .fetch_all(pool)
    .await?;
    let merge_pairs =
        sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM match_pairs WHERE decision = 'merge'"#)
            .fetch_one(pool)
            .await?;
    let review = sqlx::query_as!(
        ReviewCount,
        r#"
        SELECT (ra.source_id = rb.source_id) AS "same_source!", count(*) AS "pairs!"
        FROM match_pairs m
        JOIN source_records ra ON ra.id = m.record_a
        JOIN source_records rb ON rb.id = m.record_b
        WHERE m.decision = 'review'
        GROUP BY 1 ORDER BY 1
        "#
    )
    .fetch_all(pool)
    .await?;
    let constraints = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM conflation_constraints"#)
        .fetch_one(pool)
        .await?;
    let takedowns_unpurged = sqlx::query_scalar!(
        r#"
        SELECT count(*) AS "n!" FROM places p
        WHERE p.taken_down_at IS NOT NULL
          AND (EXISTS (SELECT 1 FROM reviews WHERE place_id = p.id)
               OR EXISTS (SELECT 1 FROM photos WHERE place_id = p.id)
               OR EXISTS (SELECT 1 FROM confirmations WHERE place_id = p.id)
               OR EXISTS (SELECT 1 FROM issue_reports WHERE place_id = p.id))
        "#
    )
    .fetch_one(pool)
    .await?;
    let holds_open = crate::holds::open_count(pool).await?;
    Ok(Stats {
        holds_open,
        sources,
        places: totals.places,
        tombstones: totals.tombstones,
        kinds,
        source_sets,
        merge_pairs,
        review,
        constraints,
        opening_hours: (totals.oh, totals.oh_parsed),
        takedowns_unpurged,
    })
}
