//! Machine translations of the reviews and descriptions the app shows
//! (`translations`): what a client may ask to translate, read under the
//! same rules as the screens that show it, and the translations kept so
//! the same text is translated once.
//!
//! Only a stored text is ever translated: [`original`] reads it by the
//! item's identity, never from anything a client sends.

use chrono::{DateTime, Utc};
use uuid::Uuid;

use crate::{DbError, PgPool};

/// What a client asks to translate, as the API names it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Translatable {
    /// A review of Lunaway's community, by its id.
    Review(Uuid),
    /// A review of another source (the external community source or
    /// Mangrove), by its id (`ExternalReview.id`).
    ExternalReview(Uuid),
    /// One of a place's own descriptions (`Place.descriptions`).
    Description {
        /// The place.
        place: Uuid,
        /// The source that wrote it.
        source: String,
        /// Its language tag as the place lists it (`und` included).
        lang: String,
    },
    /// A description of an open source (`Place.externalDescriptions`).
    ExternalDescription {
        /// The place the card shows.
        place: Uuid,
        /// The source that wrote it.
        source: String,
        /// Its language tag.
        lang: String,
    },
}

/// The table an item lives in, as `translations.item_kind` names it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ItemKind {
    /// `reviews`.
    Review,
    /// `external_reviews`.
    ExternalReview,
    /// `content_reviews`.
    ContentReview,
    /// `places.descriptions`.
    PlaceDescription,
    /// `content_descriptions`.
    ContentDescription,
}

impl ItemKind {
    /// The name `translations.item_kind` stores.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Review => "review",
            Self::ExternalReview => "external_review",
            Self::ContentReview => "content_review",
            Self::PlaceDescription => "place_description",
            Self::ContentDescription => "content_description",
        }
    }
}

/// Which translations an item's are: its table, its id, and for a
/// description its source and language.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ItemKey {
    /// Its table.
    pub kind: ItemKind,
    /// The review's id, or the place's.
    pub id: Uuid,
    /// A description's source; empty for a review.
    pub source: String,
    /// A description's language tag; empty for a review.
    pub lang: String,
}

/// A stored text a reader may see, as it stands now.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Original {
    /// Where its translations are kept.
    pub key: ItemKey,
    /// The text.
    pub text: String,
    /// The language its source or its author's app gave; `None` or `und`
    /// when neither said.
    pub lang: Option<String>,
}

/// The text of `item` as a reader sees it, under the rules of the screen
/// that shows it: a published review with text by an author not banned, on
/// a place whose merges lead to a live place; a review of another source on
/// a live place that no switch or hide keeps out of view; a description of
/// a live place. `None` otherwise: there is nothing to translate. A place
/// taken down is deleted with every place merged into it, so neither it nor
/// a review left on it before its community content is purged is read.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn original(pool: &PgPool, item: &Translatable) -> Result<Option<Original>, DbError> {
    match item {
        Translatable::Review(id) => Ok(sqlx::query!(
            r#"
            WITH RECURSIVE chain(id, merged_into, live, taken_down, depth) AS (
                SELECT p.id, p.merged_into, p.deleted_at IS NULL, p.taken_down_at IS NOT NULL, 0
                FROM reviews r JOIN places p ON p.id = r.place_id
                WHERE r.id = $1
                UNION ALL
                SELECT p.id, p.merged_into, p.deleted_at IS NULL, p.taken_down_at IS NOT NULL, c.depth + 1
                FROM chain c JOIN places p ON p.id = c.merged_into
                WHERE NOT c.live AND c.depth < 8
            )
            SELECT r.body AS "body!", r.lang
            FROM reviews r LEFT JOIN accounts a ON a.id = r.account_id
            WHERE r.id = $1 AND r.status = 'published' AND r.body IS NOT NULL
              AND a.banned_at IS NULL
              AND EXISTS (SELECT 1 FROM chain WHERE live)
              AND NOT EXISTS (SELECT 1 FROM chain WHERE taken_down)
            "#,
            id
        )
        .fetch_optional(pool)
        .await?
        .map(|r| Original {
            key: review_key(ItemKind::Review, *id),
            text: r.body,
            lang: r.lang,
        })),
        Translatable::ExternalReview(id) => {
            if let Some(found) = partner_review(pool, *id).await? {
                return Ok(Some(found));
            }
            open_review(pool, *id).await
        }
        Translatable::Description {
            place,
            source,
            lang,
        } => Ok(sqlx::query_scalar!(
            r#"
            SELECT d->>'text' AS "text!"
            FROM places p, jsonb_array_elements(p.descriptions) d
            WHERE p.id = $1 AND p.deleted_at IS NULL AND p.taken_down_at IS NULL
              AND d->>'sourceId' = $2 AND d->>'lang' = $3 AND d->>'text' IS NOT NULL
            LIMIT 1
            "#,
            place,
            source,
            lang
        )
        .fetch_optional(pool)
        .await?
        .map(|text| Original {
            key: description_key(ItemKind::PlaceDescription, *place, source, lang),
            text,
            lang: Some(lang.clone()),
        })),
        Translatable::ExternalDescription {
            place,
            source,
            lang,
        } => {
            let live = sqlx::query_scalar!(
                r#"SELECT EXISTS (SELECT 1 FROM places WHERE id = $1 AND deleted_at IS NULL
                                  AND taken_down_at IS NULL) AS "live!""#,
                place
            )
            .fetch_one(pool)
            .await?;
            if !live {
                return Ok(None);
            }
            Ok(crate::content::descriptions_of_place(pool, *place)
                .await?
                .into_iter()
                .find(|d| &d.source_id == source && &d.lang == lang)
                .map(|d| Original {
                    key: description_key(ItemKind::ContentDescription, *place, source, lang),
                    text: d.text,
                    lang: Some(d.lang),
                }))
        }
    }
}

/// A review of the external community source shown on a live place, read
/// through the same switch and hides as `extcom::reviews_of_place`.
async fn partner_review(pool: &PgPool, id: Uuid) -> Result<Option<Original>, DbError> {
    Ok(sqlx::query!(
        r#"
        SELECT e.body AS "body!", e.lang
        FROM external_reviews e
        LEFT JOIN source_switches w ON w.source_id = e.source_id
        WHERE e.id = $1 AND e.body IS NOT NULL AND w.hidden_at IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = e.source_id
                AND ((h.scope = 'review' AND h.key = e.external_id) OR h.scope = 'source'))
          AND EXISTS (
              SELECT 1 FROM place_sources ps JOIN places p ON p.id = ps.place_id
              WHERE ps.record_id = e.record_id AND p.deleted_at IS NULL
                AND p.taken_down_at IS NULL
                AND NOT EXISTS (
                    SELECT 1 FROM content_hides h
                    WHERE h.source_id = e.source_id AND h.scope = 'place'
                      AND h.key = p.id::text))
        "#,
        id
    )
    .fetch_optional(pool)
    .await?
    .map(|r| Original {
        key: review_key(ItemKind::ExternalReview, id),
        text: r.body,
        lang: r.lang,
    }))
}

/// A review of an open source (Mangrove), read through the same switch and
/// hides as `content::reviews_of_place` on the live place its place's
/// merges lead to: the card that shows it is that place's, and a hide of
/// the source on it, or on the review's own place, keeps it out.
async fn open_review(pool: &PgPool, id: Uuid) -> Result<Option<Original>, DbError> {
    Ok(sqlx::query!(
        r#"
        WITH RECURSIVE chain(id, merged_into, live, taken_down, depth) AS (
            SELECT p.id, p.merged_into, p.deleted_at IS NULL, p.taken_down_at IS NOT NULL, 0
            FROM content_reviews c JOIN places p ON p.id = c.place_id
            WHERE c.id = $1
            UNION ALL
            SELECT p.id, p.merged_into, p.deleted_at IS NULL, p.taken_down_at IS NOT NULL, ch.depth + 1
            FROM chain ch JOIN places p ON p.id = ch.merged_into
            WHERE NOT ch.live AND ch.depth < 8
        ),
        shown_on AS (
            SELECT id FROM chain WHERE live
              AND NOT EXISTS (SELECT 1 FROM chain WHERE taken_down)
            LIMIT 1
        )
        SELECT c.text AS "text!", c.lang
        FROM content_reviews c
        CROSS JOIN shown_on s
        LEFT JOIN source_switches w ON w.source_id = c.source_id
        WHERE c.id = $1 AND c.text IS NOT NULL AND w.hidden_at IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = c.source_id
                AND ((h.scope = 'review' AND h.key = c.external_id)
                  OR (h.scope = 'author' AND h.key = c.author_key)
                  OR (h.scope = 'place' AND h.key IN (c.place_id::text, s.id::text))
                  OR h.scope = 'source'))
        "#,
        id
    )
    .fetch_optional(pool)
    .await?
    .map(|r| Original {
        key: review_key(ItemKind::ContentReview, id),
        text: r.text,
        lang: r.lang,
    }))
}

fn review_key(kind: ItemKind, id: Uuid) -> ItemKey {
    ItemKey {
        kind,
        id,
        source: String::new(),
        lang: String::new(),
    }
}

fn description_key(kind: ItemKind, place: Uuid, source: &str, lang: &str) -> ItemKey {
    ItemKey {
        kind,
        id: place,
        source: source.to_owned(),
        lang: lang.to_owned(),
    }
}

/// A translation as kept.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Translation {
    /// The translated text.
    pub text: String,
    /// The language the original was taken to be in.
    pub source_lang: String,
    /// The SHA-256 of the original it was made from.
    pub source_sha256: Vec<u8>,
    /// The engine that made it (`opus-mt`).
    pub engine: String,
    /// The model of the language pair, with its release.
    pub model: String,
    /// When it was made.
    pub translated_at: DateTime<Utc>,
}

/// The translation of `key` into `target` kept from an earlier request, if
/// any; the caller checks it was made from the text as it stands.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn kept(
    pool: &PgPool,
    key: &ItemKey,
    target: &str,
) -> Result<Option<Translation>, DbError> {
    Ok(sqlx::query_as!(
        Translation,
        r#"
        SELECT text, source_lang, source_sha256, engine, model, translated_at
        FROM translations
        WHERE item_kind = $1 AND item_id = $2 AND item_source = $3 AND item_lang = $4
          AND target_lang = $5
        "#,
        key.kind.as_str(),
        key.id,
        key.source,
        key.lang,
        target,
    )
    .fetch_optional(pool)
    .await?)
}

/// Keeps `translation` of `key` into `target`, replacing an older one, and
/// says whether it was kept: only while the item still holds the text it
/// was made from (and a description its live place), so one deleted,
/// edited or taken down while the engine worked leaves nothing behind. A
/// review of Lunaway's community is locked for the write (`FOR SHARE`): its
/// deletion, edit or a ban waits for it, and its trigger then removes the
/// row. The API's role cannot lock the other sources' reviews: a deletion
/// by an import that commits in the instant between the check and the write
/// leaves a row its trigger did not see, never served, which
/// [`crate::retention::sweep`] removes the next day.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn keep(
    pool: &PgPool,
    key: &ItemKey,
    target: &str,
    translation: &Translation,
) -> Result<bool, DbError> {
    let written = sqlx::query!(
        r#"
        INSERT INTO translations (item_kind, item_id, item_source, item_lang, target_lang,
                                  source_lang, source_sha256, text, engine, model, translated_at)
        SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11
        WHERE CASE $1
            WHEN 'review' THEN EXISTS (
                SELECT 1 FROM reviews WHERE id = $2 AND sha256(convert_to(body, 'UTF8')) = $7
                FOR SHARE)
            WHEN 'external_review' THEN EXISTS (
                SELECT 1 FROM external_reviews
                WHERE id = $2 AND sha256(convert_to(body, 'UTF8')) = $7)
            WHEN 'content_review' THEN EXISTS (
                SELECT 1 FROM content_reviews
                WHERE id = $2 AND sha256(convert_to(text, 'UTF8')) = $7)
            WHEN 'place_description' THEN EXISTS (
                SELECT 1 FROM places p, jsonb_array_elements(p.descriptions) d
                WHERE p.id = $2 AND p.deleted_at IS NULL AND d->>'sourceId' = $3
                  AND d->>'lang' = $4 AND sha256(convert_to(d->>'text', 'UTF8')) = $7)
            WHEN 'content_description' THEN EXISTS (
                SELECT 1 FROM places p
                WHERE p.id = $2 AND p.deleted_at IS NULL)
              AND (EXISTS (
                  SELECT 1 FROM content_descriptions c
                  WHERE c.place_id = $2 AND c.source_id = $3 AND c.lang = $4
                    AND sha256(convert_to(c.text, 'UTF8')) = $7)
                OR EXISTS (
                  SELECT 1 FROM places m JOIN content_descriptions c ON c.place_id = m.id
                  WHERE m.merged_into = $2 AND c.source_id = $3 AND c.lang = $4
                    AND sha256(convert_to(c.text, 'UTF8')) = $7))
            ELSE false
        END
        ON CONFLICT (item_kind, item_id, item_source, item_lang, target_lang) DO UPDATE SET
            source_lang = excluded.source_lang, source_sha256 = excluded.source_sha256,
            text = excluded.text, engine = excluded.engine, model = excluded.model,
            translated_at = excluded.translated_at
        "#,
        key.kind.as_str(),
        key.id,
        key.source,
        key.lang,
        target,
        translation.source_lang,
        translation.source_sha256,
        translation.text,
        translation.engine,
        translation.model,
        translation.translated_at,
    )
    .execute(pool)
    .await?
    .rows_affected();
    Ok(written > 0)
}

/// Deletes the translations whose original is gone or no longer the text
/// they were made from: what a race with a deletion left
/// ([`keep`]), and the translations of descriptions a refresh replaced.
/// Run by the daily [`crate::retention::sweep`].
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn forget_stale(pool: &PgPool) -> Result<u64, DbError> {
    Ok(sqlx::query!(
        r#"
        DELETE FROM translations t
        WHERE CASE t.item_kind
            WHEN 'review' THEN NOT EXISTS (
                SELECT 1 FROM reviews r
                WHERE r.id = t.item_id AND sha256(convert_to(r.body, 'UTF8')) = t.source_sha256)
            WHEN 'external_review' THEN NOT EXISTS (
                SELECT 1 FROM external_reviews e
                WHERE e.id = t.item_id AND sha256(convert_to(e.body, 'UTF8')) = t.source_sha256)
            WHEN 'content_review' THEN NOT EXISTS (
                SELECT 1 FROM content_reviews c
                WHERE c.id = t.item_id AND sha256(convert_to(c.text, 'UTF8')) = t.source_sha256)
            WHEN 'place_description' THEN NOT EXISTS (
                SELECT 1 FROM places p, jsonb_array_elements(p.descriptions) d
                WHERE p.id = t.item_id AND p.deleted_at IS NULL
                  AND d->>'sourceId' = t.item_source AND d->>'lang' = t.item_lang
                  AND sha256(convert_to(d->>'text', 'UTF8')) = t.source_sha256)
            -- Two lookups, each by an index: the place's own descriptions,
            -- and those of the places merged into it.
            WHEN 'content_description' THEN NOT EXISTS (
                SELECT 1 FROM places p WHERE p.id = t.item_id AND p.deleted_at IS NULL)
              OR (NOT EXISTS (
                  SELECT 1 FROM content_descriptions c
                  WHERE c.place_id = t.item_id AND c.source_id = t.item_source
                    AND c.lang = t.item_lang
                    AND sha256(convert_to(c.text, 'UTF8')) = t.source_sha256)
                AND NOT EXISTS (
                  SELECT 1 FROM places m JOIN content_descriptions c ON c.place_id = m.id
                  WHERE m.merged_into = t.item_id AND c.source_id = t.item_source
                    AND c.lang = t.item_lang
                    AND sha256(convert_to(c.text, 'UTF8')) = t.source_sha256))
            ELSE true
        END
        "#
    )
    .execute(pool)
    .await?
    .rows_affected())
}
