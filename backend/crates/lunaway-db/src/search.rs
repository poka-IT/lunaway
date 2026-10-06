//! Searching places by name and municipality.
//!
//! The search text of a place is its folded name, address city and the
//! commune that covers it. A query matches by words first: every word of the
//! query in order as whole words, then the same with the last word as a
//! prefix, then every word as a prefix anywhere; only then by trigram word
//! similarity, which forgives a typo. So "annecy" lists what is in Annecy
//! before a "Sainte-Anne", which shares four of its letters.

use lunaway_domain::Position;

use crate::{
    DbError, PgPool,
    places::{PlaceDb, PlaceRow},
};

/// Trigram word similarity a fuzzy result needs. A word sharing only the
/// first four letters of "annecy" ("anne") scores 0.57, so queries of up to
/// six letters keep pg_trgm's default of 0.6; a missing letter in a longer
/// word scores about 0.55 ("bradere" for "bradiere"), so longer queries
/// accept 0.5. Whole-word and prefix matches need no threshold.
#[must_use]
pub fn search_threshold(text: &str) -> f64 {
    let letters = text.chars().filter(|c| c.is_alphanumeric()).count();
    if letters <= 6 { 0.6 } else { 0.5 }
}

/// Live places whose name, city or municipality match `text` (accents and
/// case ignored): whole words first, then prefixes, then typos; among
/// matches of the same rank and similar quality, the nearest to `near`
/// first.
///
/// # Errors
///
/// [`DbError`] when the query fails or a row does not decode.
pub async fn search(
    pool: &PgPool,
    text: &str,
    near: Option<Position>,
    first: i64,
) -> Result<Vec<PlaceRow>, DbError> {
    let mut tx = pool.begin().await?;
    // `<%` reads its threshold from this setting; `set_config(.., true)`
    // scopes it to the transaction, and the GIN index still serves the
    // operator (and the regular expression).
    sqlx::query_scalar!(
        "SELECT set_config('pg_trgm.word_similarity_threshold', $1, true)",
        search_threshold(text).to_string(),
    )
    .fetch_one(&mut *tx)
    .await?;
    // Similarities are bucketed to one decimal before the distance breaks
    // the tie: "Camping du Lac" 2 km away beats the same name 300 km away,
    // a much better name match still wins.
    let rows = sqlx::query_as!(
        PlaceDb,
        r#"
        SELECT id, kind, name, ST_Y(geom::geometry) AS "lat!", ST_X(geom::geometry) AS "lon!",
               overnight, services, activities, description, street, postcode, city,
               country_code, price_parking_eur, price_services_eur, max_height_m, max_length_m,
               max_width_m, max_weight_t, capacity,
               opening_hours, opening_hours_parsed, opening_intervals, opening_intervals_until,
               website, phone, stars, last_confirmed_at, updated_at, updated_seq, provenance,
               deleted_at IS NOT NULL AS "deleted!", merged_into, municipality, descriptions,
               external_links, rating_avg, rating_count, review_count, photo_count, cover_photos,
               reported_issues, verification
        FROM places
        WHERE deleted_at IS NULL
          AND (lunaway_fold($1) <% search_text OR search_text ~ lunaway_search_phrase($1))
        ORDER BY
            CASE WHEN search_text ~ (lunaway_search_phrase($1) || '\M') THEN 3
                 WHEN search_text ~ lunaway_search_phrase($1) THEN 2
                 WHEN (SELECT bool_and(search_text ~ ('\m' || w))
                       FROM unnest(lunaway_search_words($1)) AS w) THEN 1
                 ELSE 0
            END DESC,
            round(word_similarity(lunaway_fold($1), search_text)::numeric, 1) DESC,
            CASE WHEN $2::float8 IS NULL OR $3::float8 IS NULL THEN 0
                 ELSE ST_Distance(geom, ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography)
            END,
            word_similarity(lunaway_fold($1), search_text) DESC,
            id
        LIMIT $4
        "#,
        text,
        near.map(Position::lat),
        near.map(Position::lon),
        first,
    )
    .fetch_all(&mut *tx)
    .await?;
    tx.commit().await?;
    rows.into_iter().map(PlaceRow::try_from).collect()
}
