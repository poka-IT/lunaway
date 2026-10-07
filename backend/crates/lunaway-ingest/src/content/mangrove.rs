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
//!
//! Each review's signature is checked against the key it names (`kid`),
//! and what Lunaway reads of it comes from the signed token (`jwt`), not
//! from the copy the API lays out beside it: the age of a key ranks its
//! reviews (`lunaway_domain::content::reviews`), so a review must not
//! borrow an older key, whatever the server it came through checked.

use base64::{
    Engine, alphabet,
    engine::{DecodePaddingMode, GeneralPurpose, GeneralPurposeConfig, general_purpose::STANDARD},
};
use chrono::{DateTime, Utc};
use lunaway_domain::content::{self, GeoSubject};
use p256::ecdsa::{Signature, VerifyingKey, signature::Verifier};
use reqwest::Url;
use serde::Deserialize;
use serde_json::Value;

use crate::IngestError;

/// Base64url, padded or not, as JOSE writes it.
const BASE64URL: GeneralPurpose = GeneralPurpose::new(
    &alphabet::URL_SAFE,
    GeneralPurposeConfig::new()
        .with_encode_padding(false)
        .with_decode_padding_mode(DecodePaddingMode::Indifferent),
);

/// The DER prefix of a P-256 public key in SubjectPublicKeyInfo form,
/// before its 65-byte uncompressed point: the only kind of key Mangrove
/// signs with (ES256).
const SPKI_P256_PREFIX: [u8; 26] = [
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a,
    0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
];

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
    /// The signed token; the API's `payload` beside it is a copy that
    /// nothing checks, so it is not read.
    #[serde(default)]
    jwt: Option<String>,
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
    /// No signed token, or a signature the key it names does not verify.
    Unverified,
}

/// What the key `kid` signed in `jwt`, once the signature, which must be
/// the review's `signature`, verifies against it; with the key as one
/// line of PEM, its identity whatever line breaks `kid` carries. The API
/// serves keys on one line, so that text is the one releases before the
/// check hashed, and the reviews they stored keep their author.
fn verified_payload(
    signature: &str,
    kid: Option<&str>,
    jwt: Option<&str>,
) -> Option<(Payload, String)> {
    let mut parts = jwt?.split('.');
    let (Some(header), Some(payload), Some(sig), None) =
        (parts.next(), parts.next(), parts.next(), parts.next())
    else {
        return None;
    };
    if sig != signature {
        return None;
    }
    let pem: String = kid?
        .replace("-----BEGIN PUBLIC KEY-----", "")
        .replace("-----END PUBLIC KEY-----", "")
        .chars()
        .filter(|c| !c.is_whitespace())
        .collect();
    let der = STANDARD.decode(&pem).ok()?;
    // Uncompressed only, as the prefix's length says: a compressed copy of
    // the same key would give its holder a second identity.
    let point = der
        .strip_prefix(SPKI_P256_PREFIX.as_slice())
        .filter(|p| p.len() == 65 && p.first() == Some(&0x04))?;
    let key = VerifyingKey::from_sec1_bytes(point).ok()?;
    let sig = Signature::from_slice(&BASE64URL.decode(sig).ok()?).ok()?;
    key.verify(format!("{header}.{payload}").as_bytes(), &sig)
        .ok()?;
    let payload = serde_json::from_slice(&BASE64URL.decode(payload).ok()?).ok()?;
    Some((
        payload,
        format!("-----BEGIN PUBLIC KEY-----{pem}-----END PUBLIC KEY-----"),
    ))
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
    let signature_ok = (20..=300).contains(&r.signature.len())
        && r.signature
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_' || b == b'=');
    if !signature_ok {
        return Err(ReviewSkip::Malformed);
    }
    let (payload, key_pem) = verified_payload(&r.signature, r.kid.as_deref(), r.jwt.as_deref())
        .ok_or(ReviewSkip::Unverified)?;
    let m = &payload.metadata;
    if m.get("is_generated").and_then(Value::as_bool) == Some(true) {
        return Err(ReviewSkip::Generated);
    }
    let subject = GeoSubject::parse(&payload.sub).ok_or(ReviewSkip::NotGeo)?;
    let licence = match m.get("license").and_then(Value::as_str) {
        // "When no license is specified, CC-BY-4.0 applies" (Mangrove's
        // terms, section 8).
        None => content::accepted_licence("CC-BY-4.0"),
        Some(l) => content::accepted_licence(l),
    }
    .ok_or(ReviewSkip::Licence)?;
    let written_at = DateTime::from_timestamp(payload.iat, 0).ok_or(ReviewSkip::Malformed)?;
    // The reviewer sets the date: one in the future would hold the newest
    // places on the card for good.
    if written_at > chrono::Utc::now() + chrono::Duration::days(1) {
        return Err(ReviewSkip::Malformed);
    }
    let stars = content::mangrove_stars(payload.rating);
    let text = payload
        .opinion
        .as_deref()
        .and_then(|o| content::plain_text(o, content::MAX_REVIEW_CHARS));
    if stars.is_none() && text.is_none() {
        return Err(ReviewSkip::Empty);
    }
    let author_key = Some(hex_sha256(key_pem.as_bytes()));
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
    use p256::ecdsa::{SigningKey, signature::Signer};
    use serde_json::json;

    use super::*;

    /// The public key of `key` as Mangrove's API names it: a PEM SubjectPublicKeyInfo
    /// on one line.
    fn kid(key: &SigningKey) -> String {
        let mut der = SPKI_P256_PREFIX.to_vec();
        der.extend_from_slice(&key.verifying_key().to_sec1_bytes());
        format!(
            "-----BEGIN PUBLIC KEY-----{}-----END PUBLIC KEY-----",
            STANDARD.encode(der)
        )
    }

    fn key(seed: u8) -> SigningKey {
        SigningKey::from_slice(&[seed; 32]).unwrap()
    }

    /// A review as the API lists it, signed by `key`.
    fn signed(key: &SigningKey, payload: &Value) -> Value {
        let kid = kid(key);
        let header = BASE64URL.encode(json!({"alg": "ES256", "kid": kid}).to_string());
        let body = BASE64URL.encode(payload.to_string());
        let sig: Signature = key.sign(format!("{header}.{body}").as_bytes());
        let sig = BASE64URL.encode(sig.to_bytes());
        json!({"signature": sig, "kid": kid, "jwt": format!("{header}.{body}.{sig}"),
               "payload": payload})
    }

    #[test]
    fn only_human_reviews_of_places_on_the_map_are_kept() {
        let k = key(7);
        let payloads = [
            json!({"iat": 1791369177, "sub": "geo:45.53,1.79?q=Aire%20de%20Treignac&u=30",
                   "rating": 75, "opinion": "Calme, au bord du lac.",
                   "metadata": {"nickname": "Surreality", "client_id": "https://mangrove.reviews"}}),
            json!({"iat": 1791369177, "sub": "https://example.org", "rating": 100, "metadata": {}}),
            json!({"iat": 1791369177, "sub": "geo:45.53,1.79", "rating": 80,
                   "metadata": {"is_generated": true, "nickname": "Review Summarizer"}}),
            json!({"iat": 1791369177, "sub": "geo:45.53,1.79", "opinion": "ok",
                   "metadata": {"license": "CC-BY-NC-4.0"}}),
            json!({"iat": 1791369177, "sub": "geo:45.53,1.79", "metadata": {}}),
            json!({"iat": 1791369177, "sub": "geo:45.53,1.79", "opinion": "Bien",
                   "metadata": {"license": "CC-BY-SA-4.0"}}),
        ];
        let reviews: Vec<Value> = payloads.iter().map(|p| signed(&k, p)).collect();
        let body = json!({ "reviews": reviews });
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
        let p = json!({"iat": 4_102_444_800_i64, "sub": "geo:45.53,1.79", "rating": 100,
                       "metadata": {}});
        let body = json!({ "reviews": [signed(&key(7), &p)] });
        let (kept, skipped, _) = parse_page(body.to_string().as_bytes()).unwrap();
        assert!(
            kept.is_empty(),
            "a date in 2100 would hold the top of a card for good"
        );
        assert_eq!(skipped, [ReviewSkip::Malformed]);
    }

    #[test]
    fn a_review_must_be_signed_by_the_key_it_names() {
        let p = json!({"iat": 1791369177, "sub": "geo:45.53,1.79", "rating": 100,
                       "opinion": "Parfait.", "metadata": {}});
        let (old, attacker) = (key(1), key(2));
        // Signed by a fresh key, but naming an older one to take its rank.
        let mut borrowed = signed(&attacker, &p);
        borrowed["kid"] = json!(kid(&old));
        // Signed properly, then laid out by the API with another text.
        let mut altered = signed(&old, &p);
        altered["payload"]["opinion"] = json!("Arnaque.");
        // No signed token at all.
        let mut bare = signed(&old, &p);
        bare.as_object_mut().unwrap().remove("jwt");
        // The same key, its PEM text cut into lines.
        let mut wrapped = signed(&old, &p);
        let pem = kid(&old).replace("KEY-----", "KEY-----\n");
        wrapped["kid"] = json!(pem);
        let body = json!({ "reviews": [borrowed, altered, bare, wrapped] });
        let (kept, skipped, _) = parse_page(body.to_string().as_bytes()).unwrap();
        assert_eq!(
            skipped,
            [ReviewSkip::Unverified, ReviewSkip::Unverified],
            "a review that borrows a key, or carries no token, is left out"
        );
        assert_eq!(
            kept.iter().map(|r| r.text.as_deref()).collect::<Vec<_>>(),
            [Some("Parfait."), Some("Parfait.")],
            "what is read is what the key signed, not the API's copy"
        );
        assert_eq!(
            kept[0].author_key, kept[1].author_key,
            "one key is one author, however its text is laid out"
        );
        assert_eq!(
            kept[0].author_key,
            Some(hex_sha256(kid(&old).as_bytes())),
            "the hash of the one-line key the API serves, as releases before the check stored it"
        );
    }

    #[test]
    fn the_reviews_of_the_api_carry_signatures_that_verify() {
        let page = include_bytes!("../../tests/fixtures/content/mangrove_reviews_page.json");
        let (kept, skipped, total) = parse_page(page).unwrap();
        assert!(
            !skipped.contains(&ReviewSkip::Unverified),
            "real reviews verify: {skipped:?}"
        );
        assert_eq!(kept.len() + skipped.len(), total);
        assert!(
            !kept.is_empty(),
            "the signed payloads of real reviews parse: {skipped:?}"
        );
    }
}
