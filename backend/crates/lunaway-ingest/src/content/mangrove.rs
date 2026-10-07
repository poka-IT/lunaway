//! Mangrove Reviews: open reviews (CC BY 4.0 unless a review says
//! otherwise), read whole through the server's API
//! (`api.mangrove.reviews/reviews`, pages of 1 000, the latest edit of
//! each review only) and matched to places by the `geo:` URI of their
//! subject.
//!
//! Reviews written by a machine (`metadata.is_generated`: summaries of
//! other reviews) are left out: they are no one's opinion. A review keeps
//! the pseudonym its author chose (`metadata.nickname`) and a link to it
//! on mangrove.reviews; neither the author's key nor anything else of
//! the signature is shown.

use chrono::{DateTime, Utc};
use lunaway_domain::content::{self, GeoSubject};
use reqwest::Url;
use serde::Deserialize;
use serde_json::Value;

use crate::IngestError;

/// The reviews endpoint.
pub const REVIEWS_URL: &str = "https://api.mangrove.reviews/reviews";

/// Hosts the API is asked on.
pub const API_HOSTS: &[&str] = &["api.mangrove.reviews"];

/// Reviews per page. The API documents 3 500 at most, but answers 413
/// when a page passes its host's 5.8 MB (3 500 reviews weighed 6.6 MB on
/// 2026-10-07): 1 000 stay well under it.
pub const PAGE_SIZE: usize = 1_000;

/// The page of reviews from `offset`, on the endpoint `reviews`
/// ([`REVIEWS_URL`]).
///
/// # Errors
///
/// [`IngestError::UntrustedUrl`] when `reviews` is not a URL.
pub fn page_url(reviews: &str, offset: usize) -> Result<String, IngestError> {
    let limit = PAGE_SIZE.to_string();
    let offset = offset.to_string();
    Url::parse_with_params(
        reviews,
        [
            ("limit", limit.as_str()),
            ("offset", offset.as_str()),
            ("latest_edits_only", "true"),
        ],
    )
    .map(String::from)
    .map_err(|_| IngestError::UntrustedUrl {
        url: reviews.to_owned(),
        reason: "not a URL",
    })
}

#[derive(Debug, Deserialize)]
struct Page {
    #[serde(default)]
    reviews: Vec<Raw>,
}

#[derive(Debug, Deserialize)]
struct Raw {
    signature: String,
    #[serde(default)]
    kid: Option<String>,
    payload: Payload,
}

#[derive(Debug, Deserialize)]
struct Payload {
    sub: String,
    #[serde(default)]
    rating: Option<i64>,
    #[serde(default)]
    opinion: Option<String>,
    iat: i64,
    #[serde(default)]
    metadata: Value,
}

/// A review of a place on the map.
#[derive(Debug, Clone, PartialEq)]
pub struct GeoReview {
    /// Its signature, its identity on Mangrove.
    pub signature: String,
    /// What it is about.
    pub subject: GeoSubject,
    /// Stars, 1 to 5.
    pub stars: Option<u8>,
    /// Its text.
    pub text: Option<String>,
    /// The pseudonym its author chose.
    pub author: Option<String>,
    /// The SHA-256 of the key that signed it, hexadecimal: every review of
    /// one author can be hidden at once, without keeping the key.
    pub author_key: Option<String>,
    /// When it was written.
    pub written_at: DateTime<Utc>,
    /// Its licence.
    pub licence: content::Licence,
    /// Its page on mangrove.reviews.
    pub page_url: String,
}

/// Why a review is left out.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum ReviewSkip {
    /// About something else than a place on the map (a website, a book).
    NotGeo,
    /// Written by a machine.
    Generated,
    /// A licence [`content::accepted_licence`] refuses.
    Licence,
    /// Neither a rating nor a text.
    Empty,
    /// A signature or a date no real review has.
    Malformed,
}

/// The reviews of a page about places on the map, and the reasons for the
/// others, with the number of reviews the page held.
///
/// # Errors
///
/// [`IngestError::Json`] when the page is not the API's JSON.
pub fn parse_page(body: &[u8]) -> Result<(Vec<GeoReview>, Vec<ReviewSkip>, usize), IngestError> {
    let page: Page = serde_json::from_slice(body).map_err(|source| IngestError::Json {
        what: "mangrove reviews".into(),
        source,
    })?;
    let total = page.reviews.len();
    let mut kept = Vec::new();
    let mut skipped = Vec::new();
    for r in page.reviews {
        match review_of(r) {
            Ok(r) => kept.push(r),
            Err(s) => skipped.push(s),
        }
    }
    Ok((kept, skipped, total))
}

fn review_of(r: Raw) -> Result<GeoReview, ReviewSkip> {
    let m = &r.payload.metadata;
    if m.get("is_generated").and_then(Value::as_bool) == Some(true) {
        return Err(ReviewSkip::Generated);
    }
    let subject = GeoSubject::parse(&r.payload.sub).ok_or(ReviewSkip::NotGeo)?;
    let licence = match m.get("license").and_then(Value::as_str) {
        // "When no license is specified, CC-BY-4.0 applies" (Mangrove's
        // terms, section 8).
        None => content::accepted_licence("CC-BY-4.0"),
        Some(l) => content::accepted_licence(l),
    }
    .ok_or(ReviewSkip::Licence)?;
    let signature_ok = (20..=300).contains(&r.signature.len())
        && r.signature
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_' || b == b'=');
    if !signature_ok {
        return Err(ReviewSkip::Malformed);
    }
    let written_at = DateTime::from_timestamp(r.payload.iat, 0).ok_or(ReviewSkip::Malformed)?;
    // The reviewer sets the date: one in the future would hold the newest
    // places on the card for good.
    if written_at > chrono::Utc::now() + chrono::Duration::days(1) {
        return Err(ReviewSkip::Malformed);
    }
    let stars = content::mangrove_stars(r.payload.rating);
    let text = r
        .payload
        .opinion
        .as_deref()
        .and_then(|o| content::plain_text(o, content::MAX_REVIEW_CHARS));
    if stars.is_none() && text.is_none() {
        return Err(ReviewSkip::Empty);
    }
    let author_key = r
        .kid
        .as_deref()
        .map(str::trim)
        .filter(|k| !k.is_empty())
        .map(|k| hex_sha256(k.as_bytes()));
    let author = m
        .get("nickname")
        .and_then(Value::as_str)
        .and_then(|n| content::plain_text(n, content::MAX_LABEL_CHARS));
    let page_url = Url::parse_with_params(
        "https://mangrove.reviews/list",
        [("signature", r.signature.as_str())],
    )
    .map(String::from)
    .map_err(|_| ReviewSkip::Malformed)?;
    Ok(GeoReview {
        signature: r.signature,
        subject,
        stars,
        text,
        author,
        author_key,
        written_at,
        licence,
        page_url,
    })
}

fn hex_sha256(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_human_reviews_of_places_on_the_map_are_kept() {
        let sig = "rjhotUKoW0-AIDRyhOFFPtHIn2YgPij6OJknmksBdqaIJdH3qs4J5T0MiqOAm";
        let body = serde_json::json!({"reviews": [
            {"signature": sig, "kid": "-----BEGIN PUBLIC KEY-----abc", "payload": {"iat": 1791369177,
              "sub": "geo:45.53,1.79?q=Aire%20de%20Treignac&u=30", "rating": 75,
              "opinion": "Calme, au bord du lac.",
              "metadata": {"nickname": "Surreality", "client_id": "https://mangrove.reviews"}}},
            {"signature": format!("{sig}A"), "payload": {"iat": 1791369177,
              "sub": "https://example.org", "rating": 100, "metadata": {}}},
            {"signature": format!("{sig}B"), "payload": {"iat": 1791369177,
              "sub": "geo:45.53,1.79", "rating": 80,
              "metadata": {"is_generated": true, "nickname": "Review Summarizer"}}},
            {"signature": format!("{sig}C"), "payload": {"iat": 1791369177,
              "sub": "geo:45.53,1.79", "opinion": "ok",
              "metadata": {"license": "CC-BY-NC-4.0"}}},
            {"signature": format!("{sig}D"), "payload": {"iat": 1791369177,
              "sub": "geo:45.53,1.79", "metadata": {}}},
            {"signature": format!("{sig}E"), "payload": {"iat": 1791369177,
              "sub": "geo:45.53,1.79", "opinion": "Bien", "metadata": {"license": "CC-BY-SA-4.0"}}}
        ]});
        let (kept, skipped, total) = parse_page(body.to_string().as_bytes()).unwrap();
        assert_eq!(total, 6);
        assert_eq!(kept.len(), 2);
        let r = &kept[0];
        assert_eq!(r.stars, Some(4));
        assert_eq!(r.author.as_deref(), Some("Surreality"));
        assert_eq!(
            r.author_key.as_deref().map(str::len),
            Some(64),
            "the key is kept as its hash, to hide an author, never as itself"
        );
        assert_eq!(
            r.licence.name, "CC BY 4.0",
            "no licence stated is CC BY 4.0"
        );
        assert_eq!(r.subject.name.as_deref(), Some("Aire de Treignac"));
        assert!(
            r.page_url
                .starts_with("https://mangrove.reviews/list?signature=")
        );
        assert_eq!(kept[1].licence.name, "CC BY-SA 4.0");
        assert_eq!(
            skipped,
            [
                ReviewSkip::NotGeo,
                ReviewSkip::Generated,
                ReviewSkip::Licence,
                ReviewSkip::Empty
            ]
        );
    }

    #[test]
    fn a_review_dated_in_the_future_is_refused() {
        let body = serde_json::json!({"reviews": [
            {"signature": "rjhotUKoW0-AIDRyhOFFPtHIn2YgPij6OJknmksBdqaIJdH3qs4J5T0Mi",
             "payload": {"iat": 4_102_444_800_i64, "sub": "geo:45.53,1.79", "rating": 100,
                         "metadata": {}}}
        ]});
        let (kept, skipped, _) = parse_page(body.to_string().as_bytes()).unwrap();
        assert!(
            kept.is_empty(),
            "a date in 2100 would hold the top of a card for good"
        );
        assert_eq!(skipped, [ReviewSkip::Malformed]);
    }
}
