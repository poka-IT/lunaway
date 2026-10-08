//! The external community source (`extcom`) and its kind: a partner's
//! feed under a written agreement (`docs/feeds.md`). Its records are
//! `source_records` like any source's; this module holds what else it
//! brings (the agreement, the reviews, the rating summaries, the photos)
//! and the switch that hides or purges a source at once.
//!
//! The importer (`lunaway_ingest`) writes everything here but the files of
//! the photos, which the API's photo proxy writes the first time a device
//! asks for one (with `lunaway_app`, which may only fill those columns).
//! Reviews and photos hang on the record that carried them: the place they
//! show on is whichever place that record belongs to, merges included,
//! and a record the conflation unlinks takes them away with it.

use std::{
    borrow::Cow,
    collections::{BTreeMap, BTreeSet},
};

use chrono::{DateTime, NaiveDate, Utc};
use lunaway_domain::{
    SourceId,
    extcom::{Agreement, author_hash},
};
use uuid::Uuid;

use crate::{DbError, PgPool, community::Page};

/// Stores `agreement` as one `source` came under, seen at `at`: the latest
/// seen gives the source its licence and attribution (`source_terms`).
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn upsert_agreement(
    pool: &PgPool,
    source: &SourceId,
    agreement: &Agreement,
    at: DateTime<Utc>,
) -> Result<(), DbError> {
    let scope: Vec<String> = agreement
        .scope
        .iter()
        .map(|s| s.code().to_owned())
        .collect();
    let mut tx = pool.begin().await?;
    sqlx::query!(
        r#"
        INSERT INTO source_agreements AS g
            (source_id, reference, grantor, grantee, signed_on, valid_until, scope, attribution,
             licence_url, photo_hosts, first_seen_at, last_seen_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $11)
        ON CONFLICT (source_id, reference) DO UPDATE SET
            grantor = EXCLUDED.grantor, grantee = EXCLUDED.grantee,
            signed_on = EXCLUDED.signed_on, valid_until = EXCLUDED.valid_until,
            scope = EXCLUDED.scope, attribution = EXCLUDED.attribution,
            licence_url = EXCLUDED.licence_url, photo_hosts = EXCLUDED.photo_hosts,
            last_seen_at = greatest(g.last_seen_at, EXCLUDED.last_seen_at)
        "#,
        source.as_str(),
        agreement.reference,
        agreement.grantor,
        agreement.grantee,
        agreement.signed_on,
        agreement.valid_until,
        &scope,
        agreement.attribution,
        agreement.licence_url,
        &agreement.photo_hosts,
        at,
    )
    .execute(&mut *tx)
    .await?;
    // The photo proxy downloads from the hosts of every agreement in
    // force: only the one the server is configured with keeps any, so a
    // host taken out of the configuration is no longer reached.
    sqlx::query!(
        r#"
        UPDATE source_agreements SET photo_hosts = '{}'
        WHERE source_id = $1 AND reference <> $2 AND photo_hosts <> '{}'
        "#,
        source.as_str(),
        agreement.reference,
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(())
}

/// A source's switch.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Switch {
    /// Since when it is hidden.
    pub hidden_at: Option<DateTime<Utc>>,
    /// When its content was purged.
    pub purged_at: Option<DateTime<Utc>>,
}

/// The switch of `source`; a source never switched is shown.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn switch(pool: &PgPool, source: &SourceId) -> Result<Switch, DbError> {
    let row = sqlx::query!(
        "SELECT hidden_at, purged_at FROM source_switches WHERE source_id = $1",
        source.as_str()
    )
    .fetch_optional(pool)
    .await?;
    Ok(row.map_or_else(Switch::default, |r| Switch {
        hidden_at: r.hidden_at,
        purged_at: r.purged_at,
    }))
}

/// Hides `source` (`hidden`) or shows it again, and flags its records for
/// the conflation, which counts the records of a hidden source as retired:
/// its next run takes them off every place, and the change feed hands the
/// places so changed to every device. The API stops serving the source's
/// reviews, ratings and photos at once. Returns the records flagged.
///
/// # Errors
///
/// [`DbError`] when a statement fails; nothing is changed then.
pub async fn set_hidden(
    pool: &PgPool,
    source: &SourceId,
    hidden: bool,
    note: Option<&str>,
) -> Result<u64, DbError> {
    let mut tx = crate::begin_locked(pool).await?;
    sqlx::query!(
        r#"
        INSERT INTO source_switches AS w (source_id, hidden_at, note, changed_at)
        VALUES ($1, CASE WHEN $2 THEN now() END, $3, now())
        ON CONFLICT (source_id) DO UPDATE SET
            hidden_at = CASE WHEN $2 THEN coalesce(w.hidden_at, now()) END,
            purged_at = CASE WHEN $2 THEN w.purged_at END,
            note = coalesce($3, w.note), changed_at = now()
        "#,
        source.as_str(),
        hidden,
        note,
    )
    .execute(&mut *tx)
    .await?;
    let flagged = sqlx::query!(
        r#"
        UPDATE source_records SET needs_conflation = true
        WHERE source_id = $1 AND taken_down_at IS NULL AND NOT needs_conflation
        "#,
        source.as_str(),
    )
    .execute(&mut *tx)
    .await?;
    crate::community::notify_worker(&mut tx).await?;
    tx.commit().await?;
    Ok(flagged.rows_affected())
}

/// What a purge removed.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Purged {
    /// Records emptied, flagged for the conflation.
    pub records: u64,
    /// Reviews deleted.
    pub reviews: u64,
    /// Rating summaries deleted.
    pub ratings: u64,
    /// Photos retired: their files go with `purge-media`.
    pub photos: u64,
}

/// Purges `source`: hides it, empties its records (no name, no position,
/// no payload, no licence) and retires them, deletes its reviews and
/// rating summaries, and retires its photos, their URL and author
/// forgotten. The conflation then takes the records off their places, and
/// [`retired_photo_files`] lists the files the API's role removes. A
/// later import, under a new agreement and once the source is shown again,
/// fills the records anew.
///
/// # Errors
///
/// [`DbError`] when a statement fails; nothing is changed then.
pub async fn purge(
    pool: &PgPool,
    source: &SourceId,
    note: Option<&str>,
) -> Result<Purged, DbError> {
    let mut tx = crate::begin_locked(pool).await?;
    sqlx::query!(
        r#"
        INSERT INTO source_switches AS w (source_id, hidden_at, purged_at, note, changed_at)
        VALUES ($1, now(), now(), $2, now())
        ON CONFLICT (source_id) DO UPDATE SET
            hidden_at = coalesce(w.hidden_at, now()), purged_at = now(),
            note = coalesce($2, w.note), changed_at = now()
        "#,
        source.as_str(),
        note,
    )
    .execute(&mut *tx)
    .await?;
    let records = sqlx::query!(
        r#"
        UPDATE source_records SET
            name = NULL, external_url = NULL, licence = NULL,
            geom = ST_SetSRID(ST_MakePoint(0, 0), 4326)::geography, accuracy_m = 0,
            data = jsonb_build_object('kind', data->'kind',
                                      'position', jsonb_build_object('lat', 0, 'lon', 0)),
            raw = '{}', deleted_at = coalesce(deleted_at, now()),
            needs_conflation = true, changed_at = now()
        WHERE source_id = $1 AND taken_down_at IS NULL
          AND (raw <> '{}'::jsonb OR deleted_at IS NULL OR name IS NOT NULL)
        "#,
        source.as_str(),
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    let reviews = sqlx::query!(
        "DELETE FROM external_reviews WHERE source_id = $1",
        source.as_str()
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    let ratings = sqlx::query!(
        "DELETE FROM external_ratings WHERE source_id = $1",
        source.as_str()
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    let photos = sqlx::query!(
        r#"
        UPDATE external_photos SET url = NULL, author = NULL, author_id = NULL,
               retired_at = coalesce(retired_at, now())
        WHERE source_id = $1 AND (url IS NOT NULL OR retired_at IS NULL)
        "#,
        source.as_str()
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    crate::community::notify_worker(&mut tx).await?;
    tx.commit().await?;
    Ok(Purged {
        records,
        reviews,
        ratings,
        photos,
    })
}

/// Sets the licence of the records `external_ids` of `source` to
/// `licence` (an agreement's reference), writing only the rows whose
/// licence differs. Returns how many changed.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn set_record_licence(
    pool: &PgPool,
    source: &SourceId,
    external_ids: &[String],
    licence: &str,
) -> Result<u64, DbError> {
    let mut tx = crate::begin_locked(pool).await?;
    let done = sqlx::query!(
        r#"
        UPDATE source_records SET licence = $3
        WHERE source_id = $1 AND external_id = ANY($2) AND taken_down_at IS NULL
          AND licence IS DISTINCT FROM $3
        "#,
        source.as_str(),
        external_ids,
        licence,
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(done.rows_affected())
}

/// Retires the records `external_ids` of `source`: the feed says they are
/// gone (a line marked deleted). Their content is forgotten by
/// [`forget_retired`]. Returns how many were live.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn retire_records(
    pool: &PgPool,
    source: &SourceId,
    external_ids: &[String],
) -> Result<u64, DbError> {
    let mut tx = crate::begin_locked(pool).await?;
    let done = sqlx::query!(
        r#"
        UPDATE source_records
        SET deleted_at = now(), needs_conflation = true, changed_at = now()
        WHERE source_id = $1 AND external_id = ANY($2) AND deleted_at IS NULL
          AND taken_down_at IS NULL
        "#,
        source.as_str(),
        external_ids,
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(done.rows_affected())
}

/// What [`forget_retired`] removed.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Forgotten {
    /// Retired records emptied.
    pub records: u64,
    /// Their reviews, deleted.
    pub reviews: u64,
    /// Their rating summaries, deleted.
    pub ratings: u64,
    /// Their photos, retired.
    pub photos: u64,
}

/// Forgets what `source` said of its retired records: each is emptied (no
/// name, no position, no payload), its reviews and rating summary deleted,
/// its photos retired with their URL and author. A partner's spot that is
/// gone is an erasure Lunaway passes on, not a tombstone that keeps the
/// partner's content. The record keeps its id, so the conflation can take
/// it off its place, and a later feed that lists the spot again fills it
/// anew.
///
/// # Errors
///
/// [`DbError`] when a statement fails; nothing is changed then.
pub async fn forget_retired(pool: &PgPool, source: &SourceId) -> Result<Forgotten, DbError> {
    let mut tx = crate::begin_locked(pool).await?;
    let reviews = sqlx::query!(
        r#"
        DELETE FROM external_reviews e USING source_records r
        WHERE r.id = e.record_id AND e.source_id = $1 AND r.deleted_at IS NOT NULL
        "#,
        source.as_str()
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    let ratings = sqlx::query!(
        r#"
        DELETE FROM external_ratings e USING source_records r
        WHERE r.id = e.record_id AND e.source_id = $1 AND r.deleted_at IS NOT NULL
        "#,
        source.as_str()
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    let photos = sqlx::query!(
        r#"
        UPDATE external_photos e
        SET url = NULL, author = NULL, author_id = NULL, retired_at = now()
        FROM source_records r
        WHERE r.id = e.record_id AND e.source_id = $1 AND r.deleted_at IS NOT NULL
          AND e.retired_at IS NULL
        "#,
        source.as_str()
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    // The conflation reads a retired record's flag only: its emptied
    // content changes no place it is not already leaving.
    let records = sqlx::query!(
        r#"
        UPDATE source_records SET
            name = NULL, external_url = NULL, licence = NULL,
            geom = ST_SetSRID(ST_MakePoint(0, 0), 4326)::geography, accuracy_m = 0,
            data = jsonb_build_object('kind', data->'kind',
                                      'position', jsonb_build_object('lat', 0, 'lon', 0)),
            raw = '{}'
        WHERE source_id = $1 AND deleted_at IS NOT NULL AND taken_down_at IS NULL
          AND raw <> '{}'::jsonb
        "#,
        source.as_str(),
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    tx.commit().await?;
    Ok(Forgotten {
        records,
        reviews,
        ratings,
        photos,
    })
}

/// What an erasure removed.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Erased {
    /// Reviews deleted.
    pub reviews: u64,
    /// Photos retired.
    pub photos: u64,
}

/// Erases the author `author_id` (the partner's id) of `source`, at the
/// partner's request: their reviews are deleted, their photos retired with
/// their URL and author, and the hash of the id (`author_hash`) is kept so
/// an import skips what later feeds still carry of them.
///
/// # Errors
///
/// [`DbError`] when a statement fails; nothing is changed then.
pub async fn erase_author(
    pool: &PgPool,
    source: &SourceId,
    author_id: &str,
    author_hash: &str,
) -> Result<Erased, DbError> {
    let mut tx = crate::begin_locked(pool).await?;
    sqlx::query!(
        r#"
        INSERT INTO source_erasures (source_id, author_hash) VALUES ($1, $2)
        ON CONFLICT DO NOTHING
        "#,
        source.as_str(),
        author_hash,
    )
    .execute(&mut *tx)
    .await?;
    let reviews = sqlx::query!(
        "DELETE FROM external_reviews WHERE source_id = $1 AND author_id = $2",
        source.as_str(),
        author_id,
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    let photos = sqlx::query!(
        r#"
        UPDATE external_photos
        SET url = NULL, author = NULL, author_id = NULL, retired_at = coalesce(retired_at, now())
        WHERE source_id = $1 AND author_id = $2
        "#,
        source.as_str(),
        author_id,
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    tx.commit().await?;
    Ok(Erased { reviews, photos })
}

/// The hashes of the authors of `source` erased so far.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn erased_authors(pool: &PgPool, source: &SourceId) -> Result<BTreeSet<String>, DbError> {
    erased_hashes(pool, source).await
}

async fn erased_hashes<'e>(
    conn: impl sqlx::PgExecutor<'e>,
    source: &SourceId,
) -> Result<BTreeSet<String>, DbError> {
    Ok(sqlx::query_scalar!(
        "SELECT author_hash FROM source_erasures WHERE source_id = $1",
        source.as_str()
    )
    .fetch_all(conn)
    .await?
    .into_iter()
    .collect())
}

/// A review as the feed gives it, checked.
#[derive(Debug, Clone, PartialEq)]
pub struct NewReview {
    /// Its id in the feed.
    pub external_id: String,
    /// The partner's id of its author, for erasures; never served.
    pub author_id: Option<String>,
    /// The author's pseudonym.
    pub author: Option<String>,
    /// When it was written.
    pub written_at: DateTime<Utc>,
    /// Its language (BCP 47).
    pub lang: Option<String>,
    /// Stars, 1 to 5.
    pub rating: Option<i16>,
    /// The text.
    pub body: Option<String>,
    /// The author's vehicle, a `VehicleKind` code.
    pub vehicle: Option<String>,
}

/// A photo as the feed gives it, checked.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewPhoto {
    /// Its id in the feed.
    pub external_id: String,
    /// Where to download it, on a host of the agreement.
    pub url: String,
    /// The partner's id of its author, for erasures; never served.
    pub author_id: Option<String>,
    /// The author's pseudonym.
    pub author: Option<String>,
    /// Its own licence, or the agreement's reference.
    pub licence: String,
    /// When it was taken or published.
    pub taken_at: Option<DateTime<Utc>>,
}

/// What the feed says of one record beside its content.
#[derive(Debug, Clone, PartialEq)]
pub struct Extras {
    /// The record's id in the feed.
    pub external_id: String,
    /// Its reviews; `None` leaves what is stored alone: the agreement does
    /// not cover them, or the line does not say (its producer has not read
    /// them yet). An empty list removes every stored one.
    pub reviews: Option<Vec<NewReview>>,
    /// Its rating summary (mean, count); `Some(None)` removes the stored
    /// one, `None` leaves it alone (the agreement does not cover reviews).
    pub rating: Option<Option<(f64, i32)>>,
    /// Its photos; `None` leaves what is stored alone, as for the reviews.
    pub photos: Option<Vec<NewPhoto>>,
}

/// What a store of extras did.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct ExtrasStats {
    /// Reviews inserted or changed.
    pub reviews_written: u64,
    /// Reviews the feed no longer holds, deleted.
    pub reviews_removed: u64,
    /// Rating summaries inserted, changed or removed.
    pub ratings_written: u64,
    /// Photos inserted or changed.
    pub photos_written: u64,
    /// Photos the feed no longer holds, or whose URL changed, retired.
    pub photos_retired: u64,
    /// Records of the batch not found (not stored by the record upsert).
    pub missing_records: u64,
    /// Reviews and photos of an erased author, left out. The importer
    /// moves this count into its report's `erased_skipped`, with those its
    /// reading skipped.
    pub erased_skipped: u64,
}

impl std::ops::AddAssign for ExtrasStats {
    fn add_assign(&mut self, o: Self) {
        self.reviews_written += o.reviews_written;
        self.reviews_removed += o.reviews_removed;
        self.ratings_written += o.ratings_written;
        self.photos_written += o.photos_written;
        self.photos_retired += o.photos_retired;
        self.missing_records += o.missing_records;
        self.erased_skipped += o.erased_skipped;
    }
}

/// The authors erased, by `author_hash`, as one transaction sees them.
struct ErasedAuthors(BTreeSet<String>);

impl ErasedAuthors {
    async fn read(conn: &mut sqlx::PgConnection, source: &SourceId) -> Result<Self, DbError> {
        Ok(Self(erased_hashes(conn, source).await?))
    }

    fn erased(&self, author_id: Option<&str>) -> bool {
        author_id.is_some_and(|id| self.0.contains(&author_hash(id)))
    }

    /// `items` without those of an erased author, counted in `skipped`.
    fn keep<'a, T: Clone>(
        &self,
        items: &'a [T],
        author_id: impl Fn(&T) -> Option<&str>,
        skipped: &mut u64,
    ) -> Cow<'a, [T]> {
        if self.0.is_empty() || !items.iter().any(|i| self.erased(author_id(i))) {
            return Cow::Borrowed(items);
        }
        let kept: Vec<T> = items
            .iter()
            .filter(|i| !self.erased(author_id(i)))
            .cloned()
            .collect();
        *skipped += u64::try_from(items.len() - kept.len()).unwrap_or(u64::MAX);
        Cow::Owned(kept)
    }
}

/// The UUID v7 of a review written at `at`: the newest reviews come first
/// in id order, as the community's do, whatever order the feed lists them.
pub(crate) fn review_id(at: DateTime<Utc>) -> Uuid {
    let secs = u64::try_from(at.timestamp()).unwrap_or(0);
    Uuid::new_v7(uuid::Timestamp::from_unix(
        uuid::NoContext,
        secs,
        at.timestamp_subsec_nanos(),
    ))
}

/// Stores the reviews, rating summaries and photos of a batch of records
/// of `source`, in one transaction: each record's reviews become exactly
/// the feed's (the others deleted), its summary the feed's, its photos the
/// feed's (the others retired, as is a photo whose URL changed). A row is
/// written only when what the feed says of it changed. Nothing is written
/// while the source is hidden: the answer is `None` then.
///
/// The erased authors are read again here, under the writers' lock that
/// [`erase_author`] takes too: an erasure that lands while an import runs
/// is either seen by its next batch or applied after it, so no batch
/// writes an erased author's review or photo back, whatever the import
/// read when it started.
///
/// # Errors
///
/// [`DbError`] when a statement fails; nothing of the batch is kept then.
pub async fn store_extras(
    pool: &PgPool,
    source: &SourceId,
    licence: &str,
    fetched_at: DateTime<Utc>,
    batch: &[Extras],
) -> Result<Option<ExtrasStats>, DbError> {
    let mut stats = ExtrasStats::default();
    let ids: Vec<String> = batch.iter().map(|e| e.external_id.clone()).collect();
    // Under the writers' lock, as a purge is: an import cannot write a
    // review between the purge's deletions and its commit.
    let mut tx = crate::begin_locked(pool).await?;
    if is_hidden(&mut tx, source).await? {
        return Ok(None);
    }
    let erased = ErasedAuthors::read(&mut tx, source).await?;
    let found: BTreeMap<String, Uuid> = sqlx::query!(
        r#"
        SELECT external_id, id FROM source_records
        WHERE source_id = $1 AND external_id = ANY($2) AND deleted_at IS NULL
        "#,
        source.as_str(),
        &ids,
    )
    .fetch_all(&mut *tx)
    .await?
    .into_iter()
    .map(|r| (r.external_id, r.id))
    .collect();
    for e in batch {
        let Some(&record) = found.get(&e.external_id) else {
            stats.missing_records += 1;
            continue;
        };
        if let Some(reviews) = &e.reviews {
            let reviews = erased.keep(
                reviews,
                |r| r.author_id.as_deref(),
                &mut stats.erased_skipped,
            );
            let (w, r) =
                sync_reviews(&mut tx, source, record, licence, fetched_at, &reviews).await?;
            stats.reviews_written += w;
            stats.reviews_removed += r;
        }
        if let Some(rating) = e.rating {
            stats.ratings_written +=
                sync_rating(&mut tx, source, record, licence, fetched_at, rating).await?;
        }
        if let Some(photos) = &e.photos {
            let photos = erased.keep(
                photos,
                |p| p.author_id.as_deref(),
                &mut stats.erased_skipped,
            );
            let (w, r) = sync_photos(&mut tx, source, record, fetched_at, &photos).await?;
            stats.photos_written += w;
            stats.photos_retired += r;
        }
    }
    tx.commit().await?;
    Ok(Some(stats))
}

/// Whether `source` is hidden, read in the caller's transaction.
pub(crate) async fn is_hidden(
    conn: &mut sqlx::PgConnection,
    source: &SourceId,
) -> Result<bool, DbError> {
    Ok(sqlx::query_scalar!(
        r#"SELECT EXISTS (SELECT 1 FROM source_switches
                         WHERE source_id = $1 AND hidden_at IS NOT NULL) AS "hidden!""#,
        source.as_str()
    )
    .fetch_one(conn)
    .await?)
}

async fn sync_reviews(
    tx: &mut sqlx::PgConnection,
    source: &SourceId,
    record: Uuid,
    licence: &str,
    fetched_at: DateTime<Utc>,
    reviews: &[NewReview],
) -> Result<(u64, u64), DbError> {
    let keep: Vec<String> = reviews.iter().map(|r| r.external_id.clone()).collect();
    let removed = sqlx::query!(
        r#"
        DELETE FROM external_reviews
        WHERE source_id = $1 AND record_id = $2 AND NOT (external_id = ANY($3))
        "#,
        source.as_str(),
        record,
        &keep,
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if reviews.is_empty() {
        return Ok((0, removed));
    }
    let n = reviews.len();
    let mut ids = Vec::with_capacity(n);
    let mut ext = Vec::with_capacity(n);
    let mut author_ids: Vec<Option<String>> = Vec::with_capacity(n);
    let mut authors: Vec<Option<String>> = Vec::with_capacity(n);
    let mut written = Vec::with_capacity(n);
    let mut langs: Vec<Option<String>> = Vec::with_capacity(n);
    let mut ratings: Vec<Option<i16>> = Vec::with_capacity(n);
    let mut bodies: Vec<Option<String>> = Vec::with_capacity(n);
    let mut vehicles: Vec<Option<String>> = Vec::with_capacity(n);
    for r in reviews {
        ids.push(review_id(r.written_at));
        ext.push(r.external_id.clone());
        author_ids.push(r.author_id.clone());
        authors.push(r.author.clone());
        written.push(r.written_at);
        langs.push(r.lang.clone());
        ratings.push(r.rating);
        bodies.push(r.body.clone());
        vehicles.push(r.vehicle.clone());
    }
    // A review moved to another record (the partner merged two spots)
    // follows it: the record is part of what the feed says of it.
    let written_rows = sqlx::query!(
        r#"
        INSERT INTO external_reviews AS e
            (id, source_id, record_id, external_id, author_id, author, written_at, lang, rating,
             body, vehicle, licence, fetched_at)
        SELECT u.id, $1, $2, u.external_id, u.author_id, u.author, u.written_at, u.lang,
               u.rating, u.body, u.vehicle, $3, $4
        FROM UNNEST($5::uuid[], $6::text[], $13::text[], $7::text[], $8::timestamptz[],
                    $9::text[], $10::int2[], $11::text[], $12::text[])
             AS u(id, external_id, author_id, author, written_at, lang, rating, body, vehicle)
        ON CONFLICT (source_id, external_id) DO UPDATE SET
            record_id = EXCLUDED.record_id, author_id = EXCLUDED.author_id,
            author = EXCLUDED.author, written_at = EXCLUDED.written_at, lang = EXCLUDED.lang,
            rating = EXCLUDED.rating, body = EXCLUDED.body, vehicle = EXCLUDED.vehicle,
            licence = EXCLUDED.licence, fetched_at = EXCLUDED.fetched_at, changed_at = now()
        WHERE (e.record_id, e.author_id, e.author, e.written_at, e.lang, e.rating, e.body,
               e.vehicle, e.licence)
              IS DISTINCT FROM
              (EXCLUDED.record_id, EXCLUDED.author_id, EXCLUDED.author, EXCLUDED.written_at,
               EXCLUDED.lang, EXCLUDED.rating, EXCLUDED.body, EXCLUDED.vehicle,
               EXCLUDED.licence)
        "#,
        source.as_str(),
        record,
        licence,
        fetched_at,
        &ids,
        &ext,
        &authors as &[Option<String>],
        &written,
        &langs as &[Option<String>],
        &ratings as &[Option<i16>],
        &bodies as &[Option<String>],
        &vehicles as &[Option<String>],
        &author_ids as &[Option<String>],
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    Ok((written_rows, removed))
}

async fn sync_rating(
    tx: &mut sqlx::PgConnection,
    source: &SourceId,
    record: Uuid,
    licence: &str,
    fetched_at: DateTime<Utc>,
    rating: Option<(f64, i32)>,
) -> Result<u64, DbError> {
    let Some((average, count)) = rating else {
        return Ok(
            sqlx::query!("DELETE FROM external_ratings WHERE record_id = $1", record)
                .execute(&mut *tx)
                .await?
                .rows_affected(),
        );
    };
    Ok(sqlx::query!(
        r#"
        INSERT INTO external_ratings AS t (record_id, source_id, average, count, licence, fetched_at)
        VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT (record_id) DO UPDATE SET
            average = EXCLUDED.average, count = EXCLUDED.count, licence = EXCLUDED.licence,
            fetched_at = EXCLUDED.fetched_at
        WHERE (t.average, t.count, t.licence)
              IS DISTINCT FROM (EXCLUDED.average, EXCLUDED.count, EXCLUDED.licence)
        "#,
        record,
        source.as_str(),
        average,
        count,
        licence,
        fetched_at,
    )
    .execute(&mut *tx)
    .await?
    .rows_affected())
}

async fn sync_photos(
    tx: &mut sqlx::PgConnection,
    source: &SourceId,
    record: Uuid,
    fetched_at: DateTime<Utc>,
    photos: &[NewPhoto],
) -> Result<(u64, u64), DbError> {
    let keep: Vec<String> = photos.iter().map(|p| p.external_id.clone()).collect();
    let urls: Vec<String> = photos.iter().map(|p| p.url.clone()).collect();
    // Retired: the live photos of this record the feed no longer lists,
    // found through the record (external_photos_record_idx), and any live
    // photo of the feed whose URL changed (a new picture under the same id:
    // its files must be made again), found by its id
    // (external_photos_live_idx). Two statements: the two conditions in
    // one, joined by OR, read the whole table at every line of a feed
    // (163 ms a line at 35 249 photos in production, 2026-10-08).
    let gone = sqlx::query!(
        r#"
        UPDATE external_photos e
        SET retired_at = now(), url = NULL, author = NULL, author_id = NULL
        WHERE e.record_id = $2 AND e.retired_at IS NULL AND e.source_id = $1
          AND NOT (e.external_id = ANY($3))
        "#,
        source.as_str(),
        record,
        &keep,
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if photos.is_empty() {
        return Ok((0, gone));
    }
    let replaced = sqlx::query!(
        r#"
        UPDATE external_photos e
        SET retired_at = now(), url = NULL, author = NULL, author_id = NULL
        FROM UNNEST($2::text[], $3::text[]) AS u(external_id, url)
        WHERE e.source_id = $1 AND e.retired_at IS NULL AND e.external_id = u.external_id
          AND e.url IS DISTINCT FROM u.url
        "#,
        source.as_str(),
        &keep,
        &urls,
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    let retired = gone + replaced;
    let n = photos.len();
    let mut ids = Vec::with_capacity(n);
    let mut author_ids: Vec<Option<String>> = Vec::with_capacity(n);
    let mut authors: Vec<Option<String>> = Vec::with_capacity(n);
    let mut licences = Vec::with_capacity(n);
    let mut taken: Vec<Option<DateTime<Utc>>> = Vec::with_capacity(n);
    for p in photos {
        ids.push(Uuid::now_v7());
        author_ids.push(p.author_id.clone());
        authors.push(p.author.clone());
        licences.push(p.licence.clone());
        taken.push(p.taken_at);
    }
    let written = sqlx::query!(
        r#"
        INSERT INTO external_photos AS e
            (id, source_id, record_id, external_id, url, author_id, author, licence, taken_at,
             fetched_at)
        SELECT u.id, $1, $2, u.external_id, u.url, u.author_id, u.author, u.licence,
               u.taken_at, $3
        FROM UNNEST($4::uuid[], $5::text[], $6::text[], $10::text[], $7::text[], $8::text[],
                    $9::timestamptz[])
             AS u(id, external_id, url, author_id, author, licence, taken_at)
        ON CONFLICT (source_id, external_id) WHERE retired_at IS NULL DO UPDATE SET
            record_id = EXCLUDED.record_id, author_id = EXCLUDED.author_id,
            author = EXCLUDED.author, licence = EXCLUDED.licence, taken_at = EXCLUDED.taken_at,
            fetched_at = EXCLUDED.fetched_at
        WHERE (e.record_id, e.author_id, e.author, e.licence, e.taken_at)
              IS DISTINCT FROM
              (EXCLUDED.record_id, EXCLUDED.author_id, EXCLUDED.author, EXCLUDED.licence,
               EXCLUDED.taken_at)
        "#,
        source.as_str(),
        record,
        fetched_at,
        &ids,
        &keep,
        &urls,
        &authors as &[Option<String>],
        &licences,
        &taken as &[Option<DateTime<Utc>>],
        &author_ids as &[Option<String>],
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    Ok((written, retired))
}

/// A review as a place's card shows it.
#[derive(Debug, Clone, PartialEq)]
pub struct ExternalReviewRow {
    /// Its id.
    pub id: Uuid,
    /// Its source.
    pub source_id: String,
    /// The source's display name ("Source communautaire externe").
    pub source_label: String,
    /// The author's pseudonym.
    pub author: Option<String>,
    /// When it was written.
    pub written_at: DateTime<Utc>,
    /// Its language.
    pub lang: Option<String>,
    /// Stars.
    pub rating: Option<i16>,
    /// The text.
    pub body: String,
    /// The author's vehicle code.
    pub vehicle: Option<String>,
    /// The agreement it came under.
    pub licence: String,
}

/// The reviews with text of the records linked to `place`, of the sources
/// not hidden, newest first, after the review `after`.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn reviews_of_place(
    pool: &PgPool,
    place: Uuid,
    first: i64,
    after: Option<Uuid>,
) -> Result<Page<ExternalReviewRow>, DbError> {
    let rows = sqlx::query_as!(
        ExternalReviewRow,
        r#"
        SELECT e.id, e.source_id, s.name AS source_label, e.author, e.written_at, e.lang,
               e.rating, e.body AS "body!", e.vehicle, e.licence
        FROM place_sources ps
        JOIN external_reviews e ON e.record_id = ps.record_id
        JOIN sources s ON s.id = e.source_id
        LEFT JOIN source_switches w ON w.source_id = e.source_id
        WHERE ps.place_id = $1 AND w.hidden_at IS NULL AND e.body IS NOT NULL
          AND ($2::uuid IS NULL OR e.id < $2)
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = e.source_id
                AND ((h.scope = 'review' AND h.key = e.external_id)
                  OR (h.scope = 'place' AND h.key = $1::text)
                  OR h.scope = 'source'))
        ORDER BY e.id DESC
        LIMIT $3
        "#,
        place,
        after,
        first + 1,
    )
    .fetch_all(pool)
    .await?;
    let total_count = sqlx::query_scalar!(
        r#"
        SELECT count(*) AS "n!"
        FROM place_sources ps
        JOIN external_reviews e ON e.record_id = ps.record_id
        LEFT JOIN source_switches w ON w.source_id = e.source_id
        WHERE ps.place_id = $1 AND w.hidden_at IS NULL AND e.body IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = e.source_id
                AND ((h.scope = 'review' AND h.key = e.external_id)
                  OR (h.scope = 'place' AND h.key = $1::text)
                  OR h.scope = 'source'))
        "#,
        place,
    )
    .fetch_one(pool)
    .await?;
    Ok(crate::community::page(rows, first, total_count))
}

/// A rating summary as a place's card shows it.
#[derive(Debug, Clone, PartialEq)]
pub struct ExternalRatingRow {
    /// Its source.
    pub source_id: String,
    /// Mean stars.
    pub average: f64,
    /// Ratings counted.
    pub count: i32,
}

/// The rating summaries of the records linked to `place`, one per source
/// not hidden (a mean weighted by the counts when two records of a source
/// are linked to the place).
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn ratings_of_place(
    pool: &PgPool,
    place: Uuid,
) -> Result<Vec<ExternalRatingRow>, DbError> {
    Ok(sqlx::query_as!(
        ExternalRatingRow,
        r#"
        SELECT t.source_id,
               (sum(t.average * t.count) / sum(t.count))::float8 AS "average!",
               sum(t.count)::int4 AS "count!"
        FROM place_sources ps
        JOIN external_ratings t ON t.record_id = ps.record_id
        LEFT JOIN source_switches w ON w.source_id = t.source_id
        WHERE ps.place_id = $1 AND w.hidden_at IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = t.source_id
                AND ((h.scope = 'place' AND h.key = $1::text) OR h.scope = 'source'))
        GROUP BY t.source_id
        ORDER BY t.source_id
        "#,
        place,
    )
    .fetch_all(pool)
    .await?)
}

/// A photo as a place's card shows it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExternalPhotoRow {
    /// Its id.
    pub id: Uuid,
    /// Its source.
    pub source_id: String,
    /// The source's display name.
    pub source_label: String,
    /// The author's pseudonym.
    pub author: Option<String>,
    /// Its licence: its own, or the agreement's reference.
    pub licence: String,
    /// When it was taken.
    pub taken_at: Option<DateTime<Utc>>,
    /// The stored photo, once the proxy made it.
    pub path: Option<String>,
    /// The stored thumbnail.
    pub thumb_path: Option<String>,
    /// Width of the stored photo.
    pub width: Option<i32>,
    /// Height of the stored photo.
    pub height: Option<i32>,
    /// Its ThumbHash.
    pub thumbhash: Option<Vec<u8>>,
}

/// The live photos of the records linked to `place`, of the sources not
/// hidden, newest first, `limit` at most.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn photos_of_place(
    pool: &PgPool,
    place: Uuid,
    limit: i64,
) -> Result<Vec<ExternalPhotoRow>, DbError> {
    Ok(sqlx::query_as!(
        ExternalPhotoRow,
        r#"
        SELECT e.id, e.source_id, s.name AS source_label, e.author, e.licence, e.taken_at,
               e.path, e.thumb_path, e.width, e.height, e.thumbhash
        FROM place_sources ps
        JOIN external_photos e ON e.record_id = ps.record_id AND e.retired_at IS NULL
        JOIN sources s ON s.id = e.source_id
        LEFT JOIN source_switches w ON w.source_id = e.source_id
        WHERE ps.place_id = $1 AND w.hidden_at IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = e.source_id
                AND ((h.scope = 'photo' AND h.key = e.external_id)
                  OR (h.scope = 'place' AND h.key = $1::text)
                  OR h.scope = 'source'))
        ORDER BY e.taken_at DESC NULLS LAST, e.id DESC
        LIMIT $2
        "#,
        place,
        limit,
    )
    .fetch_all(pool)
    .await?)
}

/// What the photo proxy needs of a photo.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProxyPhoto {
    /// Its id.
    pub id: Uuid,
    /// Where to download it.
    pub url: String,
    /// The stored photo, when made.
    pub path: Option<String>,
    /// The stored thumbnail, when made.
    pub thumb_path: Option<String>,
    /// Failed downloads so far.
    pub attempts: i16,
    /// No download before this.
    pub retry_after: Option<DateTime<Utc>>,
    /// The hosts the source's agreements in force allow, today.
    pub hosts: Vec<String>,
}

/// The photo `id` as the proxy may serve it: live, on a source not hidden,
/// with the hosts of every agreement of its source that covers photos and
/// is in force on `today`. `None` when there is no such photo.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn photo_for_proxy(
    pool: &PgPool,
    id: Uuid,
    today: NaiveDate,
) -> Result<Option<ProxyPhoto>, DbError> {
    Ok(sqlx::query_as!(
        ProxyPhoto,
        r#"
        SELECT e.id, e.url AS "url!", e.path, e.thumb_path, e.attempts, e.retry_after,
               coalesce((
                   SELECT array_agg(DISTINCT h ORDER BY h)
                   FROM source_agreements g, unnest(g.photo_hosts) AS h
                   WHERE g.source_id = e.source_id AND 'photos' = ANY(g.scope)
                     AND g.signed_on <= $2 AND (g.valid_until IS NULL OR g.valid_until >= $2)
               ), '{}') AS "hosts!"
        FROM external_photos e
        LEFT JOIN source_switches w ON w.source_id = e.source_id
        WHERE e.id = $1 AND e.retired_at IS NULL AND e.url IS NOT NULL AND w.hidden_at IS NULL
          -- A photo the reports, a moderator or the operator hid is no
          -- longer served, even to a client that kept its address.
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = e.source_id
                AND ((h.scope = 'photo' AND h.key = e.external_id) OR h.scope = 'source'))
        "#,
        id,
        today,
    )
    .fetch_optional(pool)
    .await?)
}

/// The files the proxy made of a photo.
#[derive(Debug, Clone, Copy)]
pub struct ProcessedPhoto<'a> {
    /// The stored photo's path.
    pub path: &'a str,
    /// The thumbnail's path.
    pub thumb_path: &'a str,
    /// Size of the photo.
    pub size: (i32, i32),
    /// Size of the thumbnail.
    pub thumb_size: (i32, i32),
    /// Its ThumbHash.
    pub thumbhash: &'a [u8],
}

/// What recording a photo's files found.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Recorded {
    /// The photo is live and now names the files.
    Live,
    /// The photo was retired while it was downloaded (an import, an
    /// erasure, a purge): it names the files all the same, so
    /// `purge-media` removes them, and nothing may serve them.
    Retired,
    /// Another request recorded its files first.
    Already,
}

/// Records the files the proxy made of photo `id`, unless another request
/// did first. A photo retired meanwhile records them too, so that
/// [`retired_photo_files`] finds them: a file no row names would stay
/// under the media root for good.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn photo_processed(
    pool: &PgPool,
    id: Uuid,
    p: ProcessedPhoto<'_>,
) -> Result<Recorded, DbError> {
    let row = sqlx::query_scalar!(
        r#"
        UPDATE external_photos SET path = $2, thumb_path = $3, width = $4, height = $5,
               thumb_width = $6, thumb_height = $7, thumbhash = $8, processed_at = now(),
               retry_after = NULL
        WHERE id = $1 AND processed_at IS NULL
        RETURNING retired_at IS NOT NULL AS "retired!"
        "#,
        id,
        p.path,
        p.thumb_path,
        p.size.0,
        p.size.1,
        p.thumb_size.0,
        p.thumb_size.1,
        p.thumbhash,
    )
    .fetch_optional(pool)
    .await?;
    Ok(match row {
        Some(false) => Recorded::Live,
        Some(true) => Recorded::Retired,
        None => Recorded::Already,
    })
}

/// Records a failed download of photo `id`: no new one before
/// `retry_after`.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn photo_failed(
    pool: &PgPool,
    id: Uuid,
    retry_after: DateTime<Utc>,
) -> Result<(), DbError> {
    sqlx::query!(
        r#"
        UPDATE external_photos SET attempts = least(attempts + 1, 1000), retry_after = $2
        WHERE id = $1 AND processed_at IS NULL
        "#,
        id,
        retry_after,
    )
    .execute(pool)
    .await?;
    Ok(())
}

/// A retired photo and its files.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RetiredPhoto {
    /// Its id.
    pub id: Uuid,
    /// Its files, those still referenced elsewhere left out: a file is
    /// content-addressed, and a live photo (a community upload of the same
    /// picture, or the same picture under another id) may share it.
    pub unshared_files: Vec<String>,
    /// The paths the row named when it was listed: it is deleted only if
    /// it still names them (a download that finished meanwhile records
    /// new ones, which the next round removes).
    pub path: Option<String>,
    /// The thumbnail's path when listed.
    pub thumb_path: Option<String>,
}

/// Up to `limit` retired photos, with the files of each no other photo
/// row uses.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn retired_photo_files(pool: &PgPool, limit: i64) -> Result<Vec<RetiredPhoto>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT e.id, e.path, e.thumb_path,
               array_remove(ARRAY[
                   CASE WHEN e.path IS NOT NULL AND NOT EXISTS (
                            SELECT 1 FROM external_photos o
                            WHERE o.id <> e.id AND (o.path = e.path OR o.thumb_path = e.path)
                              AND o.retired_at IS NULL)
                        AND NOT EXISTS (
                            SELECT 1 FROM photos p WHERE p.path = e.path OR p.thumb_path = e.path)
                        THEN e.path END,
                   CASE WHEN e.thumb_path IS NOT NULL AND NOT EXISTS (
                            SELECT 1 FROM external_photos o
                            WHERE o.id <> e.id
                              AND (o.path = e.thumb_path OR o.thumb_path = e.thumb_path)
                              AND o.retired_at IS NULL)
                        AND NOT EXISTS (
                            SELECT 1 FROM photos p
                            WHERE p.path = e.thumb_path OR p.thumb_path = e.thumb_path)
                        THEN e.thumb_path END
               ], NULL) AS "files!"
        FROM external_photos e
        WHERE e.retired_at IS NOT NULL
        ORDER BY e.id
        LIMIT $1
        "#,
        limit,
    )
    .fetch_all(pool)
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| RetiredPhoto {
            id: r.id,
            unshared_files: r.files,
            path: r.path,
            thumb_path: r.thumb_path,
        })
        .collect())
}

/// Deletes the retired photo rows `photos`, once their files are gone,
/// each only if it still names the paths it was listed with.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn delete_retired_photos(pool: &PgPool, photos: &[RetiredPhoto]) -> Result<u64, DbError> {
    let ids: Vec<Uuid> = photos.iter().map(|p| p.id).collect();
    let paths: Vec<Option<String>> = photos.iter().map(|p| p.path.clone()).collect();
    let thumbs: Vec<Option<String>> = photos.iter().map(|p| p.thumb_path.clone()).collect();
    Ok(sqlx::query!(
        r#"
        DELETE FROM external_photos e
        USING UNNEST($1::uuid[], $2::text[], $3::text[]) AS u(id, path, thumb_path)
        WHERE e.id = u.id AND e.retired_at IS NOT NULL
          AND e.path IS NOT DISTINCT FROM u.path
          AND e.thumb_path IS NOT DISTINCT FROM u.thumb_path
        "#,
        &ids,
        &paths as &[Option<String>],
        &thumbs as &[Option<String>],
    )
    .execute(pool)
    .await?
    .rows_affected())
}

/// Counts of what a source holds, for `lunaway extcom status`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Counts {
    /// Live records.
    pub records: i64,
    /// Records linked to a place.
    pub linked: i64,
    /// Reviews.
    pub reviews: i64,
    /// Rating summaries.
    pub ratings: i64,
    /// Live photos.
    pub photos: i64,
    /// Of them, downloaded and stored.
    pub photos_stored: i64,
    /// Retired photos whose files wait for `purge-media`.
    pub photos_retired: i64,
}

/// What `source` holds.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn counts(pool: &PgPool, source: &SourceId) -> Result<Counts, DbError> {
    let r = sqlx::query!(
        r#"
        SELECT
          (SELECT count(*) FROM source_records WHERE source_id = $1 AND deleted_at IS NULL)
              AS "records!",
          (SELECT count(*) FROM source_records r JOIN place_sources ps ON ps.record_id = r.id
           WHERE r.source_id = $1) AS "linked!",
          (SELECT count(*) FROM external_reviews WHERE source_id = $1) AS "reviews!",
          (SELECT count(*) FROM external_ratings WHERE source_id = $1) AS "ratings!",
          (SELECT count(*) FROM external_photos WHERE source_id = $1 AND retired_at IS NULL)
              AS "photos!",
          (SELECT count(*) FROM external_photos
           WHERE source_id = $1 AND retired_at IS NULL AND processed_at IS NOT NULL)
              AS "photos_stored!",
          (SELECT count(*) FROM external_photos WHERE source_id = $1 AND retired_at IS NOT NULL)
              AS "photos_retired!"
        "#,
        source.as_str()
    )
    .fetch_one(pool)
    .await?;
    Ok(Counts {
        records: r.records,
        linked: r.linked,
        reviews: r.reviews,
        ratings: r.ratings,
        photos: r.photos,
        photos_stored: r.photos_stored,
        photos_retired: r.photos_retired,
    })
}
