//! The rules of the external community source (`extcom`): a partner's
//! feed of places, reviews and photos, received under a written agreement
//! (`docs/feeds.md`).
//!
//! The feed is untrusted input, whoever sends it: everything it says is
//! checked here before it reaches the database or a screen. The agreement
//! it names must be complete and in force; its texts are reduced to plain
//! text of bounded length; its photo URLs must point at a host the
//! agreement lists, over HTTPS, with nothing in the URL that could steer a
//! download elsewhere.

use std::collections::BTreeSet;

use chrono::NaiveDate;

use crate::taxonomy::{UnknownCode, coded_enum};
use std::{fmt, str::FromStr};

use serde::{Deserialize, Serialize};

coded_enum! {
    /// What an agreement lets Lunaway take from the feed.
    Scope {
        /// The places and what the feed says of them.
        Places => "places",
        /// The reviews and the rating summaries.
        Reviews => "reviews",
        /// The photos.
        Photos => "photos",
    }
}

/// Most hosts an agreement may list for its photos.
pub const MAX_PHOTO_HOSTS: usize = 16;
/// Longest agreement reference.
pub const MAX_REFERENCE_CHARS: usize = 64;
/// Longest attribution text.
pub const MAX_ATTRIBUTION_CHARS: usize = 300;
/// Longest name of a party to the agreement.
pub const MAX_PARTY_CHARS: usize = 200;
/// Longest pseudonym kept.
pub const MAX_PSEUDONYM_CHARS: usize = 64;

/// What the server is configured with for a source under agreement, at
/// deploy time and never from the repository nor the feed: the reference
/// of the signed agreement, and the hosts its photos may be downloaded
/// from. The feed is untrusted: it must name this agreement, and cannot
/// widen where the server downloads from.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Terms {
    reference: String,
    photo_hosts: Vec<String>,
}

impl Terms {
    /// The configured `reference` and `photo_hosts`, checked.
    ///
    /// # Errors
    ///
    /// [`AgreementError::Field`] for a malformed reference or too many
    /// hosts, [`AgreementError::PhotoHost`] for a host that is not a plain
    /// DNS name.
    pub fn new(reference: &str, photo_hosts: &[String]) -> Result<Self, AgreementError> {
        let reference = reference.trim();
        if !is_reference(reference) {
            return Err(AgreementError::Field("reference"));
        }
        if photo_hosts.len() > MAX_PHOTO_HOSTS {
            return Err(AgreementError::Field("photo_hosts"));
        }
        let mut hosts = Vec::with_capacity(photo_hosts.len());
        for h in photo_hosts {
            let host = h.trim().to_ascii_lowercase();
            if !is_dns_name(&host) {
                return Err(AgreementError::PhotoHost(h.clone()));
            }
            if !hosts.contains(&host) {
                hosts.push(host);
            }
        }
        Ok(Self {
            reference: reference.to_owned(),
            photo_hosts: hosts,
        })
    }

    /// The reference of the signed agreement.
    #[must_use]
    pub fn reference(&self) -> &str {
        &self.reference
    }

    /// The hosts photos may be downloaded from, lower case.
    #[must_use]
    pub fn photo_hosts(&self) -> &[String] {
        &self.photo_hosts
    }
}

/// Whether `reference` is an agreement reference: 1 to 64 characters,
/// ASCII letters, digits and `._/-`, a letter or a digit first.
fn is_reference(reference: &str) -> bool {
    (1..=MAX_REFERENCE_CHARS).contains(&reference.len())
        && reference.bytes().enumerate().all(|(i, b)| {
            b.is_ascii_alphanumeric() || (i > 0 && matches!(b, b'.' | b'_' | b'/' | b'-'))
        })
}

/// An agreement as a feed states it, before it is checked. Fields the
/// format does not name are ignored, a `photo_hosts` among them: the hosts
/// come from [`Terms`].
#[derive(Debug, Clone, Default, PartialEq, Eq, Deserialize)]
pub struct RawAgreement {
    /// The agreement's reference (`LUNAWAY-EXTCOM-2026-01`).
    #[serde(default)]
    pub reference: String,
    /// Who granted the rights.
    #[serde(default)]
    pub grantor: String,
    /// Who received them.
    #[serde(default)]
    pub grantee: String,
    /// The day it was signed.
    pub signed_on: Option<NaiveDate>,
    /// The last day it covers; none for an agreement without a term.
    pub valid_until: Option<NaiveDate>,
    /// What it covers.
    #[serde(default)]
    pub scope: Vec<String>,
    /// The text to show with the data.
    #[serde(default)]
    pub attribution: String,
    /// Where the agreement's public terms are, if anywhere.
    pub licence_url: Option<String>,
}

/// An agreement that passed [`Agreement::check`].
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Agreement {
    /// Its reference: what every row from the feed carries as its licence.
    pub reference: String,
    /// Who granted the rights.
    pub grantor: String,
    /// Who received them.
    pub grantee: String,
    /// The day it was signed.
    pub signed_on: NaiveDate,
    /// The last day it covers.
    pub valid_until: Option<NaiveDate>,
    /// What it covers.
    pub scope: BTreeSet<Scope>,
    /// The text shown with the data.
    pub attribution: String,
    /// Its public terms, an `https` URL.
    pub licence_url: Option<String>,
    /// The hosts the photos may be fetched from, lower case, from the
    /// server's [`Terms`].
    pub photo_hosts: Vec<String>,
}

/// Why a feed's agreement is refused.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[non_exhaustive]
pub enum AgreementError {
    /// The feed names no agreement.
    #[error("the feed names no agreement: a feed is received only under a written agreement")]
    Missing,
    /// A required field is empty or malformed.
    #[error("the agreement's {0} is missing or malformed")]
    Field(&'static str),
    /// The agreement is not signed yet on the day of the import.
    #[error("the agreement is signed on {0}, after today")]
    NotYetSigned(NaiveDate),
    /// The agreement ended before the day of the import.
    #[error("the agreement ended on {0}")]
    Expired(NaiveDate),
    /// The scope names something an agreement cannot cover.
    #[error("the agreement's scope names {0:?}")]
    Scope(String),
    /// A configured photo host is not a plain DNS name.
    #[error("the photo host {0:?} is not a DNS name")]
    PhotoHost(String),
    /// Photos are in the agreement's scope, and the server's terms name no
    /// host to download them from.
    #[error("photos are in the agreement's scope and the server's terms name no photo host")]
    NoPhotoHost,
    /// The feed names another agreement than the server's.
    #[error("the feed names the agreement {feed:?}, the server is configured with another")]
    OtherAgreement {
        /// The reference the feed names.
        feed: String,
    },
}

impl Agreement {
    /// Checks `raw` against the server's `terms` on `today`: the same
    /// reference, every field present and well formed, in force today, its
    /// scope known; photos in scope need a configured host.
    ///
    /// # Errors
    ///
    /// [`AgreementError`] naming the first problem found.
    pub fn check(
        raw: &RawAgreement,
        terms: &Terms,
        today: NaiveDate,
    ) -> Result<Self, AgreementError> {
        let reference = raw.reference.trim();
        if !is_reference(reference) {
            return Err(AgreementError::Field("reference"));
        }
        if reference != terms.reference {
            return Err(AgreementError::OtherAgreement {
                feed: reference.to_owned(),
            });
        }
        let grantor =
            sanitize_line(&raw.grantor, MAX_PARTY_CHARS).ok_or(AgreementError::Field("grantor"))?;
        let grantee =
            sanitize_line(&raw.grantee, MAX_PARTY_CHARS).ok_or(AgreementError::Field("grantee"))?;
        let attribution = sanitize_line(&raw.attribution, MAX_ATTRIBUTION_CHARS)
            .ok_or(AgreementError::Field("attribution"))?;
        let signed_on = raw.signed_on.ok_or(AgreementError::Field("signed_on"))?;
        if signed_on > today {
            return Err(AgreementError::NotYetSigned(signed_on));
        }
        if let Some(end) = raw.valid_until {
            if end < signed_on {
                return Err(AgreementError::Field("valid_until"));
            }
            if end < today {
                return Err(AgreementError::Expired(end));
            }
        }
        let mut scope = BTreeSet::new();
        for s in &raw.scope {
            scope.insert(
                s.parse::<Scope>()
                    .map_err(|_| AgreementError::Scope(s.clone()))?,
            );
        }
        if scope.is_empty() {
            return Err(AgreementError::Field("scope"));
        }
        let licence_url = match raw.licence_url.as_deref().map(str::trim) {
            None | Some("") => None,
            Some(u)
                if u.starts_with("https://")
                    && u.len() <= 500
                    && !u.contains(char::is_whitespace) =>
            {
                Some(u.to_owned())
            }
            Some(_) => return Err(AgreementError::Field("licence_url")),
        };
        let photo_hosts = terms.photo_hosts.clone();
        if scope.contains(&Scope::Photos) && photo_hosts.is_empty() {
            return Err(AgreementError::NoPhotoHost);
        }
        Ok(Self {
            reference: reference.to_owned(),
            grantor,
            grantee,
            signed_on,
            valid_until: raw.valid_until,
            scope,
            attribution,
            licence_url,
            photo_hosts,
        })
    }

    /// Whether the agreement covers `scope`.
    #[must_use]
    pub fn covers(&self, scope: Scope) -> bool {
        self.scope.contains(&scope)
    }
}

/// Whether `host` is a lower-case DNS name of at least two labels: letters,
/// digits and inner hyphens, no IP address, no `localhost`. An IP literal
/// or a single-label name could reach the server's own network.
#[must_use]
pub fn is_dns_name(host: &str) -> bool {
    if host.is_empty() || host.len() > 253 || host.ends_with('.') {
        return false;
    }
    let labels: Vec<&str> = host.split('.').collect();
    let labels_ok = labels.len() >= 2
        && labels.iter().all(|l| {
            (1..=63).contains(&l.len())
                && l.bytes()
                    .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
                && !l.starts_with('-')
                && !l.ends_with('-')
                // `0x7f`: URL parsers read a hexadecimal label as part of an
                // IPv4 address (`0x7f.0.0.0x1` is 127.0.0.1).
                && !l.starts_with("0x")
        });
    // A last label of digits only makes an IPv4 address of the name.
    let tld_ok = labels
        .last()
        .is_some_and(|tld| tld.bytes().any(|b| b.is_ascii_lowercase()));
    labels_ok && tld_ok && !host.ends_with(".localhost") && !host.ends_with(".internal")
}

/// The host of a photo URL, lower case, when the URL is one Lunaway may
/// download: `https`, a DNS name ([`is_dns_name`]), no user information,
/// no port but 443, no whitespace, backslash or control character, at most
/// 2048 bytes. Anything else is `None`.
#[must_use]
pub fn photo_url_host(url: &str) -> Option<String> {
    if url.len() > 2048
        || url
            .chars()
            .any(|c| c.is_whitespace() || c.is_control() || c == '\\')
    {
        return None;
    }
    let scheme_end = url.find("://")?;
    if !url[..scheme_end].eq_ignore_ascii_case("https") {
        return None;
    }
    let rest = &url[scheme_end + 3..];
    let authority_end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let authority = &rest[..authority_end];
    if authority.contains('@') || authority.contains('%') || authority.starts_with('[') {
        return None;
    }
    let host = match authority.rsplit_once(':') {
        Some((h, "443")) => h,
        Some(_) => return None,
        None => authority,
    };
    let host = host.to_ascii_lowercase();
    is_dns_name(&host).then_some(host)
}

/// Whether `url` is a photo URL ([`photo_url_host`]) on one of `hosts`.
#[must_use]
pub fn photo_url_allowed(url: &str, hosts: &[String]) -> bool {
    photo_url_host(url).is_some_and(|h| hosts.contains(&h))
}

/// Rows cut off the bottom of every photo of the external community source
/// before its files are made: the band the source stamps its mark in, which
/// the agreement lets Lunaway leave out (the source is shown under its
/// contractual mention only).
///
/// Measured on the 296 photos the proxy had stored in production on
/// 2026-10-10, sizes 665 x 1182 to 1374 x 572: the mark is a line of plain
/// white letters, without outline, at the same place in every one, its
/// letters 51 to 62 rows above the bottom edge and 52 to 176 columns from
/// the right edge, in pixels of the picture as the source serves it
/// (`plan/research/101-audit2-donnees.md`). The band keeps six rows above
/// the letters for the encoder's ringing around them.
pub const MARK_BAND_ROWS: u16 = 68;
const _: () = assert!(
    MARK_BAND_ROWS > 62,
    "the band covers the mark's letters, 51 to 62 rows above the bottom edge"
);

/// The rows cut off the bottom of the photos of `source` before their files
/// are made ([`MARK_BAND_ROWS`] for the external community source); 0 for a
/// source that stamps nothing on its photos.
#[must_use]
pub fn mark_band_rows(source: &str) -> u16 {
    if source == crate::SourceId::EXTCOM.as_str() {
        MARK_BAND_ROWS
    } else {
        0
    }
}

/// `url` as stored when it is a photo URL ([`photo_url_host`]): the scheme
/// and the host in lower case and no default port, so the database's check
/// (`^https://`) and a later comparison see one spelling.
#[must_use]
pub fn normalize_photo_url(url: &str) -> Option<String> {
    let host = photo_url_host(url)?;
    let rest = &url[url.find("://")? + 3..];
    let path = &rest[rest.find(['/', '?', '#']).unwrap_or(rest.len())..];
    Some(format!("https://{host}{path}"))
}

/// Characters that reorder or hide text: a review could otherwise display
/// something other than what it holds.
fn is_invisible_control(c: char) -> bool {
    matches!(
        c,
        '\u{200B}'..='\u{200F}' | '\u{202A}'..='\u{202E}' | '\u{2066}'..='\u{2069}' | '\u{FEFF}'
    ) && c != '\u{200D}'
}

/// Drops the HTML tags of `input` (a `<br>` or a `</p>` becomes a line
/// break) and decodes the five entities every exporter writes. The app
/// shows plain text; a partner's export may hold the markup of its site.
fn strip_markup(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut rest = input;
    while let Some(start) = rest.find('<') {
        out.push_str(&rest[..start]);
        let after = &rest[start..];
        match after.find('>') {
            Some(end) if end <= 200 => {
                let tag = after[1..end].trim_start_matches('/').to_ascii_lowercase();
                if tag.starts_with("br") || tag.starts_with('p') || tag.starts_with("li") {
                    out.push('\n');
                }
                rest = &after[end + 1..];
            }
            // A lone `<` is text ("< 3 m").
            _ => {
                out.push('<');
                rest = &after[1..];
            }
        }
    }
    out.push_str(rest);
    out.replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&nbsp;", " ")
        .replace("&amp;", "&")
}

/// `input` as plain text of at most `max_chars` characters, or `None` when
/// nothing remains: markup dropped, control and direction characters
/// dropped (line breaks kept, at most two in a row), spaces collapsed,
/// trimmed, cut at a character boundary.
#[must_use]
pub fn sanitize_text(input: &str, max_chars: usize) -> Option<String> {
    let plain = strip_markup(input);
    let mut out = String::with_capacity(plain.len().min(max_chars * 4));
    let mut newlines = 0;
    let mut space = false;
    for c in plain.chars() {
        if c == '\n' || c == '\r' {
            if c == '\n' {
                newlines += 1;
            }
            space = false;
            continue;
        }
        if c.is_control() || is_invisible_control(c) {
            continue;
        }
        if c.is_whitespace() {
            space = true;
            continue;
        }
        if !out.is_empty() {
            if newlines > 0 {
                while out.ends_with(' ') {
                    out.pop();
                }
                out.push_str(if newlines > 1 { "\n\n" } else { "\n" });
            } else if space {
                out.push(' ');
            }
        }
        newlines = 0;
        space = false;
        out.push(c);
    }
    let cut: String = out.chars().take(max_chars).collect();
    let cut = cut.trim().to_owned();
    (!cut.is_empty()).then_some(cut)
}

/// `input` on one line ([`sanitize_text`] with the line breaks as spaces).
#[must_use]
pub fn sanitize_line(input: &str, max_chars: usize) -> Option<String> {
    sanitize_text(input, max_chars).map(|t| t.split_whitespace().collect::<Vec<_>>().join(" "))
}

/// A pseudonym to show beside a review or a photo: one line of at most
/// [`MAX_PSEUDONYM_CHARS`] characters. One that looks like an e-mail
/// address is dropped: a partner's export may hold a login where it meant
/// a display name, and an address is personal data the agreement does not
/// hand over.
#[must_use]
pub fn sanitize_pseudonym(input: &str) -> Option<String> {
    let line = sanitize_line(input, MAX_PSEUDONYM_CHARS)?;
    let looks_like_mail = line
        .split_once('@')
        .is_some_and(|(user, domain)| !user.is_empty() && domain.contains('.'));
    (!looks_like_mail).then_some(line)
}

/// What an erasure keeps of a partner's author id: its SHA-256, lower-case
/// hexadecimal, so later feeds can be held back without the id itself
/// staying in the database.
#[must_use]
pub fn author_hash(author_id: &str) -> String {
    use sha2::{Digest, Sha256};
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let digest = Sha256::digest(author_id.trim().as_bytes());
    let mut hex = String::with_capacity(2 * digest.len());
    for b in digest {
        hex.push(char::from(HEX[usize::from(b >> 4)]));
        hex.push(char::from(HEX[usize::from(b & 0x0f)]));
    }
    hex
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_author_hash_is_the_sha256_of_the_trimmed_id() {
        assert_eq!(
            author_hash(" u-42 "),
            author_hash("u-42"),
            "an id is matched whatever spaces a feed puts around it"
        );
        assert_eq!(author_hash("abc").len(), 64);
        assert_eq!(
            author_hash("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn only_the_external_community_source_loses_a_band_of_its_photos() {
        assert_eq!(mark_band_rows("extcom"), MARK_BAND_ROWS);
        for other in [
            "osm",
            "community-cc-by",
            "wikimedia-commons",
            "panoramax",
            "",
        ] {
            assert_eq!(mark_band_rows(other), 0, "{other} stamps nothing");
        }
    }

    fn day(y: i32, m: u32, d: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(y, m, d).unwrap()
    }

    fn raw() -> RawAgreement {
        RawAgreement {
            reference: "LUNAWAY-EXTCOM-2026-01".into(),
            grantor: "Partner SAS".into(),
            grantee: "Lunaway".into(),
            signed_on: Some(day(2026, 10, 1)),
            valid_until: Some(day(2027, 9, 30)),
            scope: vec!["places".into(), "reviews".into(), "photos".into()],
            attribution: "Données : Source communautaire externe, avec l'accord du partenaire"
                .into(),
            licence_url: None,
        }
    }

    fn terms() -> Terms {
        Terms::new("LUNAWAY-EXTCOM-2026-01", &["Photos.Example.org".into()]).unwrap()
    }

    #[test]
    fn a_complete_agreement_in_force_is_accepted() {
        let a = Agreement::check(&raw(), &terms(), day(2026, 10, 7)).unwrap();
        assert_eq!(a.reference, "LUNAWAY-EXTCOM-2026-01");
        assert_eq!(
            a.photo_hosts,
            ["photos.example.org"],
            "the hosts are the server's, never the feed's"
        );
        assert!(a.covers(Scope::Photos));
    }

    #[test]
    fn a_feed_naming_another_agreement_is_refused() {
        let other = Terms::new("ANOTHER-REF", &["photos.example.org".into()]).unwrap();
        assert_eq!(
            Agreement::check(&raw(), &other, day(2026, 10, 7)),
            Err(AgreementError::OtherAgreement {
                feed: "LUNAWAY-EXTCOM-2026-01".into()
            })
        );
    }

    #[test]
    fn an_agreement_missing_a_field_or_out_of_date_is_refused() {
        let today = day(2026, 10, 7);
        let t = terms();
        let check = |r: &RawAgreement| Agreement::check(r, &t, today);
        let mut r = raw();
        r.reference = String::new();
        assert_eq!(check(&r), Err(AgreementError::Field("reference")));
        let mut r = raw();
        r.reference = "REF WITH SPACE".into();
        assert_eq!(check(&r), Err(AgreementError::Field("reference")));
        let mut r = raw();
        r.grantor = " <b></b> ".into();
        assert_eq!(check(&r), Err(AgreementError::Field("grantor")));
        let mut r = raw();
        r.signed_on = None;
        assert_eq!(check(&r), Err(AgreementError::Field("signed_on")));
        let mut r = raw();
        r.valid_until = Some(day(2026, 10, 6));
        assert_eq!(check(&r), Err(AgreementError::Expired(day(2026, 10, 6))));
        let mut r = raw();
        r.signed_on = Some(day(2026, 10, 8));
        r.valid_until = None;
        assert_eq!(
            check(&r),
            Err(AgreementError::NotYetSigned(day(2026, 10, 8)))
        );
        let mut r = raw();
        r.scope = vec!["everything".into()];
        assert!(matches!(check(&r), Err(AgreementError::Scope(_))));
        let mut r = raw();
        r.scope = vec![];
        assert_eq!(check(&r), Err(AgreementError::Field("scope")));
        let no_hosts = Terms::new("LUNAWAY-EXTCOM-2026-01", &[]).unwrap();
        assert_eq!(
            Agreement::check(&raw(), &no_hosts, today),
            Err(AgreementError::NoPhotoHost),
            "photos in scope need a configured host to fetch them from"
        );
        let mut r = raw();
        r.scope = vec!["places".into()];
        assert!(
            Agreement::check(&r, &no_hosts, today).is_ok(),
            "places alone need no photo host"
        );
    }

    #[test]
    fn configured_terms_take_plain_dns_names_only() {
        for bad in [
            "127.0.0.1",
            "localhost",
            "10.0.0.1",
            "metadata.internal",
            "a..b",
            "*.x.org",
        ] {
            assert!(
                matches!(
                    Terms::new("REF", &[bad.into()]),
                    Err(AgreementError::PhotoHost(_))
                ),
                "{bad} must not be a photo host"
            );
        }
        assert_eq!(Terms::new("", &[]), Err(AgreementError::Field("reference")));
    }

    #[test]
    fn photo_urls_are_held_to_the_agreement_s_hosts() {
        let hosts = vec!["photos.example.org".to_owned()];
        assert!(photo_url_allowed(
            "https://photos.example.org/a/b.jpg?w=2048",
            &hosts
        ));
        assert!(photo_url_allowed(
            "HTTPS://PHOTOS.example.org:443/a.jpg",
            &hosts
        ));
        for bad in [
            "http://photos.example.org/a.jpg",
            "https://photos.example.org.evil.net/a.jpg",
            "https://evil.net/photos.example.org/a.jpg",
            "https://photos.example.org@evil.net/a.jpg",
            "https://evil.net@photos.example.org/a.jpg",
            "https://photos.example.org:8443/a.jpg",
            "https://127.0.0.1/a.jpg",
            "https://[::1]/a.jpg",
            "https://photos%2eexample.org/a.jpg",
            "https://photos.example.org/a b.jpg",
            "https://photos.example.org\\@evil.net/",
            "file:///etc/passwd",
            "photos.example.org/a.jpg",
            "",
        ] {
            assert!(!photo_url_allowed(bad, &hosts), "{bad} must be refused");
        }
    }

    #[test]
    fn a_photo_url_is_stored_in_one_spelling() {
        assert_eq!(
            normalize_photo_url("HTTPS://Img.Example.org:443/A/b.JPG?w=1").as_deref(),
            Some("https://img.example.org/A/b.JPG?w=1")
        );
        assert_eq!(normalize_photo_url("http://img.example.org/a.jpg"), None);
        assert!(
            !is_dns_name("0x7f.0.0.0x1"),
            "a hexadecimal label is an IPv4 address to a URL parser"
        );
    }

    #[test]
    fn texts_become_bounded_plain_text() {
        assert_eq!(
            sanitize_text("<p>Calme <b>la nuit</b></p><p>Eau &amp; vidange</p>", 100).as_deref(),
            Some("Calme la nuit\n\nEau & vidange")
        );
        assert_eq!(
            sanitize_text("hauteur < 3 m", 100).as_deref(),
            Some("hauteur < 3 m")
        );
        assert_eq!(
            sanitize_text("a\u{202E}b\u{0007}c\u{200B}d", 100).as_deref(),
            Some("abcd"),
            "direction overrides, controls and zero-width spaces are dropped"
        );
        assert_eq!(
            sanitize_text("famille 👨\u{200D}👩\u{200D}👧", 100).as_deref(),
            Some("famille 👨\u{200D}👩\u{200D}👧"),
            "the joiner of an emoji sequence stays"
        );
        assert_eq!(
            sanitize_text("un\n\n\n\ndeux   trois", 100).as_deref(),
            Some("un\n\ndeux trois")
        );
        assert_eq!(sanitize_text("ééééé", 3).as_deref(), Some("ééé"));
        assert_eq!(sanitize_text("  <br/> ", 10), None);
    }

    #[test]
    fn a_pseudonym_is_one_short_line_and_never_an_address() {
        assert_eq!(
            sanitize_pseudonym(" Marie\net Paul ").as_deref(),
            Some("Marie et Paul")
        );
        assert_eq!(sanitize_pseudonym("jean.dupont@example.org"), None);
        assert_eq!(sanitize_pseudonym("@vanlife").as_deref(), Some("@vanlife"));
        assert_eq!(
            sanitize_pseudonym(&"x".repeat(100)).map(|p| p.chars().count()),
            Some(MAX_PSEUDONYM_CHARS)
        );
    }

    #[test]
    fn scope_codes_round_trip() {
        for s in Scope::ALL {
            assert_eq!(s.code().parse::<Scope>().unwrap(), *s);
        }
    }
}
