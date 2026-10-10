//! The open content shown on a place's card, and on a point of interest's:
//! photos, descriptions and reviews from open sources, each kept with its
//! author, its licence and a link to where it was published
//! (`docs/data-sources.md`, "Open content").
//!
//! Only what a licence lets anyone reuse and redistribute with attribution
//! is kept: [`accepted_licence`] decides from what the source says of each
//! item, and refuses whatever it does not recognise.

use std::fmt;

use crate::{
    PlaceKind, Position,
    conflation::{
        normalize::{core_tokens, fold},
        similarity::{token_containment, trigram_similarity, trigrams},
    },
    poi::PoiKind,
};

pub mod reviews;

/// Photos of one place kept at most, every source together: the card shows
/// a strip, and each photo costs a download and two files.
pub const MAX_PHOTOS_PER_PLACE: usize = 8;

/// Photos found only by their position kept at most per place: they show
/// the surroundings, so they come after those that show the place itself.
pub const MAX_NEARBY_PHOTOS: usize = 4;

/// Longest description kept, characters: a card shows a paragraph, and
/// the full text is one tap away on its source.
pub const MAX_DESCRIPTION_CHARS: usize = 1_200;

/// Longest review text kept, characters.
pub const MAX_REVIEW_CHARS: usize = 4_000;

/// Longest author or title kept, characters.
pub const MAX_LABEL_CHARS: usize = 200;

/// Why a photo is shown on a place.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum PhotoRelation {
    /// The place's own data names the file: OpenStreetMap's
    /// `wikimedia_commons`, `image` or `panoramax`, or the Wikidata item's
    /// image (P18).
    Linked,
    /// A street-level picture taken near the place, its camera pointing at
    /// it.
    Facing,
    /// A picture taken near the place, in no particular direction: it shows
    /// the surroundings, perhaps the place.
    Nearby,
}

impl PhotoRelation {
    /// The code stored in the database.
    #[must_use]
    pub const fn code(self) -> &'static str {
        match self {
            Self::Linked => "linked",
            Self::Facing => "facing",
            Self::Nearby => "nearby",
        }
    }

    /// The relation a stored code names.
    #[must_use]
    pub fn from_code(code: &str) -> Option<Self> {
        match code {
            "linked" => Some(Self::Linked),
            "facing" => Some(Self::Facing),
            "nearby" => Some(Self::Nearby),
            _ => None,
        }
    }
}

/// A licence under which an item may be reused and redistributed, with
/// attribution where it asks for it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Licence {
    /// Its short name as shown (`CC BY-SA 4.0`).
    pub name: String,
    /// Its text.
    pub url: String,
    /// Whether the author must be credited. CC0 and the public domain do
    /// not ask for it; Lunaway credits the author whenever it is known.
    pub attribution_required: bool,
    /// Whether an adaptation must keep the same licence (BY-SA).
    pub share_alike: bool,
}

/// The CC version and jurisdiction suffix of a licence name, as in
/// `4.0`, `2.0 de` or `3.0 igo`: digits and dots, then an optional port.
fn cc_version(rest: &str) -> Option<(String, Option<String>)> {
    let mut parts = rest.split_whitespace();
    let version = parts.next()?;
    let valid = version.contains('.')
        && version.bytes().all(|b| b.is_ascii_digit() || b == b'.')
        && ["1.0", "2.0", "2.5", "3.0", "4.0"].contains(&version);
    if !valid {
        return None;
    }
    let port = parts.next().map(str::to_ascii_lowercase);
    if parts.next().is_some() || (port.is_some() && version == "4.0") {
        return None;
    }
    if port
        .as_deref()
        .is_some_and(|p| !(2..=3).contains(&p.len()) || !p.bytes().all(|b| b.is_ascii_lowercase()))
    {
        return None;
    }
    Some((version.to_owned(), port))
}

fn cc_url(kind: &str, version: &str, port: Option<&str>) -> String {
    match port {
        Some(p) => format!("https://creativecommons.org/licenses/{kind}/{version}/{p}/"),
        None => format!("https://creativecommons.org/licenses/{kind}/{version}/"),
    }
}

/// The licence a short name designates, if it allows reuse and
/// redistribution with attribution at most: CC0, the public domain, the
/// Creative Commons BY and BY-SA licences (every version and port), the
/// Licence Ouverte (Etalab) 1.0 and 2.0, and the ODbL. Anything else is
/// refused, the non-commercial and no-derivatives licences first: the
/// first forbids a use the app cannot exclude, the second the resizing
/// every photo goes through. The GFDL alone is refused too: it asks for its
/// full text beside each copy.
///
/// Names are read the way Wikimedia Commons (`LicenseShortName`), Panoramax
/// (`etalab-2.0`, `CC-BY-SA-4.0`) and Mangrove write them.
#[must_use]
pub fn accepted_licence(short_name: &str) -> Option<Licence> {
    let raw = short_name.trim();
    let upper = raw.to_ascii_uppercase().replace(['_', '-'], " ");
    let upper = upper.split_whitespace().collect::<Vec<_>>().join(" ");
    let licence = |name: String, url: String, attribution_required, share_alike| {
        Some(Licence {
            name,
            url,
            attribution_required,
            share_alike,
        })
    };
    if upper == "CC0" || upper == "CC0 1.0" || upper == "CC ZERO" {
        return licence(
            "CC0 1.0".to_owned(),
            "https://creativecommons.org/publicdomain/zero/1.0/".to_owned(),
            false,
            false,
        );
    }
    if upper == "PUBLIC DOMAIN" || upper == "PD" {
        return licence(
            "Public domain".to_owned(),
            "https://commons.wikimedia.org/wiki/Commons:Copyright_tags/Public_domain".to_owned(),
            false,
            false,
        );
    }
    if upper == "ETALAB 2.0" || upper == "LICENCE OUVERTE 2.0" || upper == "LO 2.0" {
        return licence(
            "Licence Ouverte 2.0".to_owned(),
            "https://www.etalab.gouv.fr/licence-ouverte-open-licence/".to_owned(),
            true,
            false,
        );
    }
    if upper == "ETALAB 1.0" || upper == "LICENCE OUVERTE 1.0" || upper == "LICENCE OUVERTE" {
        return licence(
            "Licence Ouverte".to_owned(),
            "https://www.etalab.gouv.fr/licence-ouverte-open-licence/".to_owned(),
            true,
            false,
        );
    }
    if upper == "ODBL" || upper == "ODBL 1.0" {
        return licence(
            "ODbL 1.0".to_owned(),
            "https://opendatacommons.org/licenses/odbl/1-0/".to_owned(),
            true,
            true,
        );
    }
    let (kind, rest) = if let Some(rest) = upper.strip_prefix("CC BY SA ") {
        ("by-sa", rest)
    } else {
        ("by", upper.strip_prefix("CC BY ")?)
    };
    let (version, port) = cc_version(rest)?;
    let display = match &port {
        Some(p) => format!(
            "CC {} {version} {p}",
            if kind == "by" { "BY" } else { "BY-SA" }
        ),
        None => format!("CC {} {version}", if kind == "by" { "BY" } else { "BY-SA" }),
    };
    licence(
        display,
        cc_url(kind, &version, port.as_deref()),
        true,
        kind == "by-sa",
    )
}

/// Plain text from a field that may hold HTML (Wikimedia Commons writes an
/// author as a link): tags dropped, the common entities decoded, white
/// space collapsed, cut at `max_chars` on a character boundary. Empty
/// input gives `None`.
#[must_use]
pub fn plain_text(html: &str, max_chars: usize) -> Option<String> {
    let mut text = String::with_capacity(html.len());
    let mut in_tag = false;
    for c in html.chars() {
        match c {
            '<' => {
                in_tag = true;
                // A tag separates words as a space would.
                text.push(' ');
            }
            '>' if in_tag => in_tag = false,
            c if !in_tag => text.push(c),
            _ => {}
        }
    }
    let decoded = decode_entities(&text);
    let collapsed = decoded.split_whitespace().collect::<Vec<_>>().join(" ");
    let cut = truncate_chars(&collapsed, max_chars);
    (!cut.is_empty()).then_some(cut)
}

fn decode_entities(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(amp) = rest.find('&') {
        out.push_str(&rest[..amp]);
        let after = &rest[amp..];
        let Some(semi) = after.find(';').filter(|i| *i <= 10) else {
            out.push('&');
            rest = &after[1..];
            continue;
        };
        let entity = &after[1..semi];
        let decoded = match entity {
            "amp" => Some('&'),
            "lt" => Some('<'),
            "gt" => Some('>'),
            "quot" => Some('"'),
            "apos" => Some('\''),
            "nbsp" => Some(' '),
            _ => entity
                .strip_prefix("#x")
                .or_else(|| entity.strip_prefix("#X"))
                .and_then(|h| u32::from_str_radix(h, 16).ok())
                .or_else(|| entity.strip_prefix('#').and_then(|d| d.parse().ok()))
                .and_then(char::from_u32)
                .filter(|c| !c.is_control()),
        };
        if let Some(c) = decoded {
            out.push(c);
            rest = &after[semi + 1..];
        } else {
            out.push('&');
            rest = &after[1..];
        }
    }
    out.push_str(rest);
    out
}

/// `s` cut to at most `max_chars` characters; a cut text ends at the last
/// sentence end or word boundary in its second half, and always with an
/// ellipsis, which is how a reader sees that it was shortened (CC BY-SA
/// asks to show a change).
#[must_use]
pub fn truncate_chars(s: &str, max_chars: usize) -> String {
    let s = s.trim();
    if s.chars().count() <= max_chars {
        return s.to_owned();
    }
    if max_chars < 2 {
        return String::new();
    }
    let head: String = s.chars().take(max_chars - 1).collect();
    let half = head.len() / 2;
    // A sentence end leaves room for a space and the ellipsis after it.
    let sentence = head
        .rfind(". ")
        .filter(|i| *i >= half && head[..=*i].chars().count() + 2 <= max_chars)
        .map(|i| format!("{} \u{2026}", &head[..=i]));
    if let Some(sentence) = sentence {
        return sentence;
    }
    let word = head
        .rfind(' ')
        .filter(|i| *i >= half)
        .map_or(head.as_str(), |i| &head[..i]);
    format!("{}\u{2026}", word.trim_end_matches([',', ';', ':', ' ']))
}

/// The title of a Wikimedia Commons file (`File:Aire de Saint-Malo.jpg`) an
/// OpenStreetMap `wikimedia_commons` or `image` value names: `File:...`,
/// the file's page URL, or its URL on `upload.wikimedia.org`. A category,
/// a gallery or another site gives `None`.
#[must_use]
pub fn commons_file_title(value: &str) -> Option<String> {
    let v = value.split(';').next()?.trim();
    let name = if let Some(rest) = strip_prefix_ci(v, "File:") {
        rest.to_owned()
    } else if let Some(rest) = strip_prefix_ci(v, "Image:") {
        rest.to_owned()
    } else if let Some(path) = strip_prefix_ci(v, "https://commons.wikimedia.org/wiki/")
        .or_else(|| strip_prefix_ci(v, "http://commons.wikimedia.org/wiki/"))
        .or_else(|| strip_prefix_ci(v, "https://commons.m.wikimedia.org/wiki/"))
    {
        let decoded = percent_decode(path.split(['?', '#']).next()?)?;
        strip_prefix_ci(&decoded, "File:")
            .or_else(|| strip_prefix_ci(&decoded, "Image:"))?
            .to_owned()
    } else {
        // `a/ab/Name.jpg`, or `thumb/a/ab/Name.jpg/800px-Name.jpg`.
        let path = strip_prefix_ci(v, "https://upload.wikimedia.org/wikipedia/commons/")?;
        let path = path.split(['?', '#']).next()?;
        let parts: Vec<&str> = path.split('/').collect();
        let file = match parts.as_slice() {
            ["thumb", _, _, file, ..] | [_, _, file] => *file,
            _ => return None,
        };
        percent_decode(file)?
    };
    let name = name.replace('_', " ");
    let name = name.trim();
    let has_extension = name
        .rsplit_once('.')
        .is_some_and(|(stem, ext)| !stem.is_empty() && (2..=5).contains(&ext.len()));
    (has_extension && !name.contains(['|', '#', '<', '>', '[', ']', '{', '}', '\n']))
        .then(|| format!("File:{name}"))
}

fn strip_prefix_ci<'a>(s: &'a str, prefix: &str) -> Option<&'a str> {
    let head = s.get(..prefix.len())?;
    head.eq_ignore_ascii_case(prefix)
        .then(|| &s[prefix.len()..])
}

/// `%XX` sequences decoded as UTF-8; `None` when the result is not UTF-8.
fn percent_decode(s: &str) -> Option<String> {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%'
            && let Some(hex) = s.get(i + 1..i + 3)
            && hex.bytes().all(|b| b.is_ascii_hexdigit())
            && let Ok(b) = u8::from_str_radix(hex, 16)
        {
            out.push(b);
            i += 3;
            continue;
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8(out).ok()
}

/// A Panoramax picture id an OpenStreetMap `panoramax` value names: a UUID,
/// the first of a `;` list.
#[must_use]
pub fn panoramax_picture_id(value: &str) -> Option<String> {
    lowercase_uuid(value.split(';').next()?)
}

/// A UUID in its hyphenated form, lower-cased; `None` for anything else.
#[must_use]
pub fn lowercase_uuid(value: &str) -> Option<String> {
    let v = value.trim().to_ascii_lowercase();
    let parts: Vec<&str> = v.split('-').collect();
    let shape = [8, 4, 4, 4, 12];
    let valid = parts.len() == 5
        && parts
            .iter()
            .zip(shape)
            .all(|(p, n)| p.len() == n && p.bytes().all(|b| b.is_ascii_hexdigit()));
    valid.then_some(v)
}

/// A Wikipedia article an OpenStreetMap `wikipedia` value names
/// (`fr:Lac d'Annecy`): its language, as [`content_language`] keeps it,
/// and its title. A Wikipedia whose code is no language tag (`simple`,
/// `zh-classical`) and a URL (`https://...`) give `None`: their text could
/// not be stored under a language.
#[must_use]
pub fn wikipedia_article(value: &str) -> Option<(String, String)> {
    let (lang, title) = value.split_once(':')?;
    let raw = lang.trim().to_ascii_lowercase();
    let lang = content_language(&raw).filter(|l| *l == raw)?;
    if title.starts_with("//") {
        return None;
    }
    let title = title.trim().replace('_', " ");
    (!title.is_empty() && title.chars().count() <= 255 && !title.contains(['|', '#']))
        .then_some((lang, title))
}

/// How far around a place a picture found by its position may have been
/// taken, metres: a campsite spreads over hectares, a car park does not.
#[must_use]
pub const fn nearby_radius_m(kind: PlaceKind) -> f64 {
    match kind {
        PlaceKind::Campsite => 250.0,
        PlaceKind::MotorhomeArea | PlaceKind::ServiceArea | PlaceKind::RestArea => 120.0,
        _ => 80.0,
    }
}

/// The initial bearing from `from` to `to`, degrees clockwise from north,
/// in `[0, 360)`.
#[must_use]
pub fn bearing_deg(from: Position, to: Position) -> f64 {
    let (lat1, lat2) = (from.lat().to_radians(), to.lat().to_radians());
    let dlon = (to.lon() - from.lon()).to_radians();
    let y = dlon.sin() * lat2.cos();
    let x = lat1.cos() * lat2.sin() - lat1.sin() * lat2.cos() * dlon.cos();
    y.atan2(x).to_degrees().rem_euclid(360.0)
}

/// Smallest angle between two headings, degrees, in `[0, 180]`.
#[must_use]
pub fn heading_gap_deg(a: f64, b: f64) -> f64 {
    let d = (a - b).rem_euclid(360.0);
    d.min(360.0 - d)
}

/// Whether a camera at `camera`, pointing at `azimuth_deg`, looks at
/// `target` within `half_field_deg` of the centre of its picture. A
/// 360-degree picture looks everywhere.
#[must_use]
pub fn looks_at(camera: Position, azimuth_deg: f64, half_field_deg: f64, target: Position) -> bool {
    if half_field_deg >= 180.0 {
        return true;
    }
    heading_gap_deg(bearing_deg(camera, target), azimuth_deg) <= half_field_deg
}

/// Stars, 1 to 5, from a Mangrove rating (0 to 100, as the protocol
/// writes it: 0 is one star, 100 five, 25 a step). `None` stays `None`: a
/// review may be an opinion without a rating.
#[must_use]
pub fn mangrove_stars(rating: Option<i64>) -> Option<u8> {
    let r = rating?.clamp(0, 100);
    u8::try_from((r + 12) / 25 + 1).ok().map(|s| s.min(5))
}

/// A `geo:` URI as Mangrove subjects write it (RFC 5870 with the `q` and
/// `u` parameters): `geo:47.1,2.3?q=Camping%20du%20Lac&u=30`.
#[derive(Debug, Clone, PartialEq)]
pub struct GeoSubject {
    /// The position.
    pub position: Position,
    /// The name the reviewer's app gave the place.
    pub name: Option<String>,
    /// Uncertainty, metres.
    pub uncertainty_m: Option<f64>,
}

impl GeoSubject {
    /// Reads a `geo:` URI; `None` for anything else.
    #[must_use]
    pub fn parse(uri: &str) -> Option<Self> {
        let rest = strip_prefix_ci(uri.trim(), "geo:")?;
        let (coords, query) = rest.split_once('?').unwrap_or((rest, ""));
        let coords = coords.split(';').next()?;
        let mut it = coords.split(',');
        let lat: f64 = it.next()?.trim().parse().ok()?;
        let lon: f64 = it.next()?.trim().parse().ok()?;
        let position = Position::new(lat, lon).ok()?;
        let mut name = None;
        let mut uncertainty_m = None;
        for pair in query.split('&') {
            let Some((k, v)) = pair.split_once('=') else {
                continue;
            };
            let v = percent_decode(&v.replace('+', " "));
            match k {
                "q" => {
                    name = v
                        .map(|n| truncate_chars(&n, MAX_LABEL_CHARS))
                        .filter(|n| !n.is_empty());
                }
                "u" => {
                    uncertainty_m = v
                        .and_then(|u| u.trim().parse::<f64>().ok())
                        .filter(|u| u.is_finite() && *u >= 0.0);
                }
                _ => {}
            }
        }
        Some(Self {
            position,
            name,
            uncertainty_m,
        })
    }
}

/// A place a review could be about.
#[derive(Debug, Clone, Copy)]
pub struct ReviewCandidate<'a> {
    /// The place's position.
    pub position: Position,
    /// Its kind.
    pub kind: PlaceKind,
    /// Its name.
    pub name: Option<&'a str>,
}

/// How well two names agree, 0 to 1: the better of the trigram similarity
/// and the containment of the identifying words, as the conflation compares
/// names (`docs/conflation.md`).
#[must_use]
pub fn name_agreement(a: &str, b: &str) -> f64 {
    let (fa, fb) = (fold(a), fold(b));
    let (mut ta, mut tb) = (core_tokens(&fa), core_tokens(&fb));
    ta.sort_unstable();
    ta.dedup();
    tb.sort_unstable();
    tb.dedup();
    let words = token_containment(&ta, &tb);
    let grams = trigram_similarity(&trigrams(&ta.join(" ")), &trigrams(&tb.join(" ")));
    words.max(grams)
}

/// Name agreement from which a review placed a little off is still the
/// place's.
const NAMED_MATCH: f64 = 0.6;

/// The place, among `candidates` (in any order), a review of `subject` is
/// about: the nearest within the uncertainty the reviewer's app gave
/// (counted between 30 and 100 m), or, when the review names the place,
/// the nearest whose name agrees within the larger of that and the place's
/// [`nearby_radius_m`]. A review that two places could equally claim (no
/// name, two places within 5 m of the same distance from it) goes to none.
#[must_use]
pub fn review_place(subject: &GeoSubject, candidates: &[ReviewCandidate<'_>]) -> Option<usize> {
    let tight = subject.uncertainty_m.unwrap_or(30.0).clamp(30.0, 100.0);
    let mut order: Vec<usize> = (0..candidates.len()).collect();
    // Nearest first: the ambiguity test compares each place with the best
    // one before it.
    order.sort_by(|a, b| {
        let d = |i: usize| subject.position.distance_m(candidates[i].position);
        d(*a).total_cmp(&d(*b))
    });
    let mut best: Option<(usize, f64)> = None;
    let mut ambiguous = false;
    for i in order {
        let c = &candidates[i];
        let d = subject.position.distance_m(c.position);
        let named = match (subject.name.as_deref(), c.name) {
            (Some(a), Some(b)) => name_agreement(a, b) >= NAMED_MATCH,
            _ => false,
        };
        let within = if named {
            d <= nearby_radius_m(c.kind).max(tight)
        } else {
            d <= tight
        };
        if !within {
            continue;
        }
        // A place whose name agrees ranks before any other, then distance.
        let rank = if named { d - 1_000.0 } else { d };
        match best {
            Some((_, r)) if (r - rank).abs() < 5.0 && !named => ambiguous = true,
            Some((_, r)) if rank < r => {
                ambiguous = false;
                best = Some((i, rank));
            }
            None => best = Some((i, rank)),
            Some(_) => {}
        }
    }
    if ambiguous {
        None
    } else {
        best.map(|(i, _)| i)
    }
}

/// Photos of one point of interest shown at most (`Poi.externalPhotos`),
/// and kept at most from each source: a point shows what its own tags
/// name, never its surroundings. Panoramax gives the one picture a tag
/// names, so a point keeps five photos at most for the four it shows.
pub const MAX_PHOTOS_PER_POI: usize = 4;

/// Whether a review may reach a point of this kind. Never a practice where
/// a person treats patients under their own name (a doctor, a dentist, a
/// nurse, a therapist): a review there speaks of a named person, and often
/// of the reviewer's health, which the GDPR puts in a special category
/// (art. 9). A clinic, a hospital, a laboratory or a pharmacy is an
/// establishment, reviewed as a shop is.
#[must_use]
pub const fn poi_takes_reviews(kind: PoiKind) -> bool {
    !matches!(
        kind,
        PoiKind::Doctor
            | PoiKind::Dentist
            | PoiKind::Physiotherapist
            | PoiKind::Nurse
            | PoiKind::Midwife
            | PoiKind::Podiatrist
            | PoiKind::Psychologist
            | PoiKind::SpeechTherapist
            | PoiKind::AlternativeMedicine
    )
}

/// Least distance a review is looked for around a point, metres: what the
/// reviewer's app gives when it says no uncertainty, as for a place.
pub const POI_REVIEW_MIN_M: f64 = 30.0;

/// Most distance a review is looked for around a point, metres, whatever
/// uncertainty the reviewer's app gave.
pub const POI_REVIEW_MAX_M: f64 = 300.0;

/// A named point of interest a review could be about.
#[derive(Debug, Clone, Copy)]
pub struct PoiCandidate<'a> {
    /// The point's position.
    pub position: Position,
    /// Its kind: some never take a review ([`poi_takes_reviews`]).
    pub kind: PoiKind,
    /// Its name: a point without one is never a candidate.
    pub name: &'a str,
}

/// How far from where a review says it is a point may stand to be its
/// subject: the uncertainty the reviewer's app gave, counted between
/// [`POI_REVIEW_MIN_M`] and [`POI_REVIEW_MAX_M`].
#[must_use]
pub fn poi_review_radius_m(subject: &GeoSubject) -> f64 {
    subject
        .uncertainty_m
        .unwrap_or(POI_REVIEW_MIN_M)
        .clamp(POI_REVIEW_MIN_M, POI_REVIEW_MAX_M)
}

/// The point of interest, among `candidates` (in any order), a review of
/// `subject` that no place took is about: the nearest within
/// [`poi_review_radius_m`] whose name agrees with the one the review gives
/// ([`name_agreement`], as for a place). A review that names nothing goes to
/// no point: the shops of a street stand metres apart, and only the name
/// tells them apart. A point of a kind that takes no review
/// ([`poi_takes_reviews`]) is passed over. Two agreeing points within 5 m
/// of the same distance from it (two branches of one chain) take none.
#[must_use]
pub fn review_poi(subject: &GeoSubject, candidates: &[PoiCandidate<'_>]) -> Option<usize> {
    let name = subject.name.as_deref()?;
    let radius = poi_review_radius_m(subject);
    let mut agreeing: Vec<(usize, f64)> = candidates
        .iter()
        .enumerate()
        .filter(|(_, c)| poi_takes_reviews(c.kind) && name_agreement(name, c.name) >= NAMED_MATCH)
        .map(|(i, c)| (i, subject.position.distance_m(c.position)))
        .filter(|(_, d)| *d <= radius)
        .collect();
    agreeing.sort_by(|a, b| a.1.total_cmp(&b.1));
    match agreeing.as_slice() {
        [] => None,
        [(i, _)] => Some(*i),
        [(i, d), (_, next), ..] => (next - d >= 5.0).then_some(*i),
    }
}

/// A language tag as the content tables keep it: lower-case, two or three
/// letters, an optional region or script; `None` otherwise.
#[must_use]
pub fn content_language(tag: &str) -> Option<String> {
    let t = tag.trim().replace('_', "-");
    let mut parts = t.split('-');
    let primary = parts.next()?.to_ascii_lowercase();
    if !(2..=3).contains(&primary.len()) || !primary.bytes().all(|b| b.is_ascii_lowercase()) {
        return None;
    }
    let rest: Vec<&str> = parts.collect();
    if rest
        .iter()
        .any(|p| !(2..=8).contains(&p.len()) || !p.bytes().all(|b| b.is_ascii_alphanumeric()))
    {
        return None;
    }
    if rest.is_empty() {
        Some(primary)
    } else {
        Some(format!("{primary}-{}", rest.join("-")))
    }
}

impl fmt::Display for PhotoRelation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.code())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pos(lat: f64, lon: f64) -> Position {
        Position::new(lat, lon).unwrap()
    }

    #[test]
    fn only_licences_that_allow_reuse_with_attribution_are_accepted() {
        for (name, shown, sa) in [
            ("CC BY-SA 4.0", "CC BY-SA 4.0", true),
            ("CC BY-SA 3.0", "CC BY-SA 3.0", true),
            ("CC BY-SA 2.0 de", "CC BY-SA 2.0 de", true),
            ("CC BY 2.5", "CC BY 2.5", false),
            ("cc-by-sa-4.0", "CC BY-SA 4.0", true),
            ("CC-BY-SA-4.0", "CC BY-SA 4.0", true),
            ("CC0", "CC0 1.0", false),
            ("Public domain", "Public domain", false),
            ("etalab-2.0", "Licence Ouverte 2.0", false),
        ] {
            let l = accepted_licence(name).unwrap_or_else(|| panic!("{name} is open"));
            assert_eq!(l.name, shown);
            assert_eq!(l.share_alike, sa, "{name}");
            assert!(l.url.starts_with("https://"), "{name}");
        }
        assert_eq!(
            accepted_licence("CC BY-SA 2.0 de").unwrap().url,
            "https://creativecommons.org/licenses/by-sa/2.0/de/"
        );
        for refused in [
            "CC BY-NC 4.0",
            "CC BY-NC-SA 3.0",
            "CC BY-ND 4.0",
            "GFDL",
            "GFDL 1.2",
            "Copyrighted",
            "All rights reserved",
            "CC BY-SA 9.9",
            "CC BY 4.0 fr",
            "PD-US-not renewed",
            "CC BY-SA 4.0 <script>",
            "",
        ] {
            assert_eq!(
                accepted_licence(refused),
                None,
                "{refused:?} does not allow every reuse with attribution"
            );
        }
    }

    #[test]
    fn html_authors_read_as_plain_text() {
        assert_eq!(
            plain_text(
                "<a href=\"//commons.wikimedia.org/wiki/User:Pierre\" title=\"User:Pierre\">Pierre &amp; Marie</a>",
                200
            )
            .as_deref(),
            Some("Pierre & Marie")
        );
        assert_eq!(
            plain_text("  <span>\n</span> ", 200),
            None,
            "an author made of markup only is no author"
        );
        assert_eq!(
            plain_text("Jos&#233; &#x41;", 200).as_deref(),
            Some("José A")
        );
        assert_eq!(
            plain_text("a &unknown; b & c", 200).as_deref(),
            Some("a &unknown; b & c")
        );
        assert_eq!(
            plain_text("<script>x</script>y", 200).as_deref(),
            Some("x y"),
            "a script's body is text: nothing of it runs once tags are gone"
        );
    }

    #[test]
    fn long_texts_are_cut_at_a_sentence_or_a_word() {
        let text = "Une aire calme. Au bord du canal, avec des services complets et un accueil chaleureux.";
        assert_eq!(truncate_chars(text, 200), text);
        assert_eq!(
            truncate_chars(text, 40),
            "Une aire calme. Au bord du canal, avec\u{2026}"
        );
        assert_eq!(truncate_chars(text, 20), "Une aire calme. \u{2026}");
        assert_eq!(truncate_chars(text, 0), "", "nothing fits in nothing");
        let cut = truncate_chars(&"é".repeat(50), 10);
        assert_eq!(
            cut.chars().count(),
            10,
            "the cut counts characters, not bytes"
        );
    }

    #[test]
    fn commons_files_are_read_from_every_form_osm_uses() {
        for (value, title) in [
            ("File:Aire de Saint-Malo.jpg", "File:Aire de Saint-Malo.jpg"),
            ("file:Aire_de_Saint-Malo.JPG", "File:Aire de Saint-Malo.JPG"),
            (
                "https://commons.wikimedia.org/wiki/File:Camping_les_Pins_%C3%A9t%C3%A9.jpg",
                "File:Camping les Pins été.jpg",
            ),
            (
                "https://upload.wikimedia.org/wikipedia/commons/a/ab/Camping_X.jpg",
                "File:Camping X.jpg",
            ),
            (
                "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Camping_X.jpg/800px-Camping_X.jpg",
                "File:Camping X.jpg",
            ),
            ("File:A.jpg;File:B.jpg", "File:A.jpg"),
        ] {
            assert_eq!(commons_file_title(value).as_deref(), Some(title), "{value}");
        }
        for other in [
            "Category:Campsites in Brittany",
            "https://commons.wikimedia.org/wiki/Category:X",
            "https://www.flickr.com/photos/1/2",
            "https://example.org/File:X.jpg",
            "File:no extension",
            "File:a|b.jpg",
            "",
        ] {
            assert_eq!(commons_file_title(other), None, "{other}");
        }
    }

    #[test]
    fn panoramax_ids_and_wikipedia_values_are_checked() {
        assert_eq!(
            panoramax_picture_id("1D1C3B6E-0B9C-4B3A-9C5B-8E2F1A0B3C4D").as_deref(),
            Some("1d1c3b6e-0b9c-4b3a-9c5b-8e2f1a0b3c4d")
        );
        assert_eq!(panoramax_picture_id("not-a-uuid"), None);
        assert_eq!(
            wikipedia_article("fr:Lac d'Annecy"),
            Some(("fr".to_owned(), "Lac d'Annecy".to_owned()))
        );
        assert_eq!(
            wikipedia_article("de:Campingplatz_X"),
            Some(("de".to_owned(), "Campingplatz X".to_owned()))
        );
        assert_eq!(wikipedia_article("Lac d'Annecy"), None);
        assert_eq!(
            wikipedia_article("simple:France"),
            None,
            "a Wikipedia whose code is no language: its text has no language to be stored under"
        );
        assert_eq!(wikipedia_article("https://fr.wikipedia.org/wiki/X"), None);
        assert_eq!(wikipedia_article("fr:"), None);
        assert_eq!(wikipedia_article("fr:a|b"), None);
    }

    #[test]
    fn a_camera_looks_at_a_place_ahead_of_it() {
        let camera = pos(48.0, 2.0);
        let north = pos(48.001, 2.0);
        let east = pos(48.0, 2.0015);
        assert!(bearing_deg(camera, north) < 0.01 || bearing_deg(camera, north) > 359.99);
        assert!((bearing_deg(camera, east) - 90.0).abs() < 0.1);
        assert!(looks_at(camera, 10.0, 30.0, north));
        assert!(
            looks_at(camera, 350.0, 30.0, north),
            "headings wrap at north"
        );
        assert!(!looks_at(camera, 180.0, 30.0, north));
        assert!(
            looks_at(camera, 180.0, 180.0, north),
            "a sphere looks everywhere"
        );
        assert!((heading_gap_deg(355.0, 5.0) - 10.0).abs() < 1e-9);
    }

    #[test]
    fn mangrove_ratings_become_stars() {
        assert_eq!(mangrove_stars(Some(0)), Some(1));
        assert_eq!(mangrove_stars(Some(25)), Some(2));
        assert_eq!(mangrove_stars(Some(50)), Some(3));
        assert_eq!(mangrove_stars(Some(75)), Some(4));
        assert_eq!(mangrove_stars(Some(100)), Some(5));
        assert_eq!(mangrove_stars(Some(60)), Some(3));
        assert_eq!(mangrove_stars(Some(-5)), Some(1));
        assert_eq!(mangrove_stars(Some(400)), Some(5));
        assert_eq!(mangrove_stars(None), None);
    }

    #[test]
    fn geo_subjects_are_read() {
        let s = GeoSubject::parse("geo:47.123,2.5?q=Camping%20du%20Lac&u=30").unwrap();
        assert!((s.position.lat() - 47.123).abs() < 1e-9);
        assert_eq!(s.name.as_deref(), Some("Camping du Lac"));
        assert_eq!(s.uncertainty_m, Some(30.0));
        let bare = GeoSubject::parse("geo:-33.5,151.2").unwrap();
        assert_eq!(bare.name, None);
        assert_eq!(GeoSubject::parse("https://example.org"), None);
        assert_eq!(
            GeoSubject::parse("geo:95,2"),
            None,
            "a latitude past the pole"
        );
        assert_eq!(GeoSubject::parse("geo:a,b"), None);
    }

    #[test]
    fn a_review_goes_to_the_place_it_names_or_to_none() {
        let lake = ReviewCandidate {
            position: pos(47.0, 2.0),
            kind: PlaceKind::Campsite,
            name: Some("Camping du Lac"),
        };
        let car_park = ReviewCandidate {
            position: pos(47.0012, 2.0),
            kind: PlaceKind::Parking,
            name: Some("Parking de la Gare"),
        };
        let both = [lake, car_park];
        let named = GeoSubject::parse("geo:47.0011,2.0?q=Camping%20du%20Lac&u=20").unwrap();
        assert_eq!(
            review_place(&named, &both),
            Some(0),
            "the campsite it names, though the car park is nearer"
        );
        let unnamed = GeoSubject::parse("geo:47.0011,2.0?u=20").unwrap();
        assert_eq!(review_place(&unnamed, &both), Some(1), "the nearest");
        let far = GeoSubject::parse("geo:47.01,2.0?q=Camping%20du%20Lac").unwrap();
        assert_eq!(
            review_place(&far, &both),
            None,
            "a kilometre off is another place"
        );
        let twin = ReviewCandidate {
            position: pos(47.0012, 2.00001),
            kind: PlaceKind::Parking,
            name: None,
        };
        assert_eq!(
            review_place(&unnamed, &[car_park, twin]),
            None,
            "two places as near as each other: the review belongs to neither"
        );
    }

    #[test]
    fn a_review_goes_to_the_point_whose_name_it_gives_and_never_to_a_nameless_one() {
        let bakery = PoiCandidate {
            position: pos(47.0, 2.0),
            kind: PoiKind::Bakery,
            name: "Boulangerie Dupont",
        };
        let pharmacy = PoiCandidate {
            position: pos(47.0002, 2.0),
            kind: PoiKind::Pharmacy,
            name: "Pharmacie du Centre",
        };
        let both = [pharmacy, bakery];
        let named = GeoSubject::parse("geo:47.0003,2.0?q=Boulangerie%20Dupont&u=50").unwrap();
        assert_eq!(
            review_poi(&named, &both),
            Some(1),
            "the bakery it names, though the pharmacy is nearer"
        );
        let folded = GeoSubject::parse("geo:47.0003,2.0?q=BOULANGERIE%20dupont&u=50").unwrap();
        assert_eq!(review_poi(&folded, &both), Some(1), "names compare folded");
        let unnamed = GeoSubject::parse("geo:47.0,2.0?u=50").unwrap();
        assert_eq!(
            review_poi(&unnamed, &both),
            None,
            "a review that names nothing goes to no point, however near"
        );
        let other = GeoSubject::parse("geo:47.0,2.0?q=Le%20Bistrot&u=50").unwrap();
        assert_eq!(
            review_poi(&other, &both),
            None,
            "a name that agrees with no point"
        );
        let generic = GeoSubject::parse("geo:47.0,2.0?q=Parking&u=50").unwrap();
        assert_eq!(
            review_poi(
                &generic,
                &[PoiCandidate {
                    position: pos(47.0, 2.0),
                    kind: PoiKind::Bakery,
                    name: "Parking du Centre",
                }]
            ),
            None,
            "a name made of generic words names nothing"
        );
    }

    #[test]
    fn a_review_reaches_a_point_within_its_uncertainty_and_never_past_300_m() {
        let bakery = [PoiCandidate {
            position: pos(47.0, 2.0),
            kind: PoiKind::Bakery,
            name: "Boulangerie Dupont",
        }];
        // About 111 m north of the bakery.
        let at = |u: &str| {
            GeoSubject::parse(&format!("geo:47.001,2.0?q=Boulangerie%20Dupont{u}")).unwrap()
        };
        assert_eq!(review_poi(&at("&u=150"), &bakery), Some(0));
        assert_eq!(
            review_poi(&at("&u=50"), &bakery),
            None,
            "beyond the uncertainty the reviewer's app gave"
        );
        assert_eq!(
            review_poi(&at(""), &bakery),
            None,
            "no uncertainty counts as 30 m"
        );
        // About 333 m north of it, with an uncertainty of 2 km.
        let far = GeoSubject::parse("geo:47.003,2.0?q=Boulangerie%20Dupont&u=2000").unwrap();
        assert!((poi_review_radius_m(&far) - POI_REVIEW_MAX_M).abs() < f64::EPSILON);
        assert_eq!(review_poi(&far, &bakery), None, "never past 300 m");
    }

    #[test]
    fn a_review_never_reaches_a_person_s_health_practice() {
        let review = GeoSubject::parse("geo:47.0,2.0?q=Docteur%20Martin&u=50").unwrap();
        let doctor = PoiCandidate {
            position: pos(47.0, 2.0),
            kind: PoiKind::Doctor,
            name: "Docteur Martin",
        };
        assert_eq!(
            review_poi(&review, &[doctor]),
            None,
            "a review of a named doctor would publish what a patient says of a person"
        );
        let clinic = PoiCandidate {
            kind: PoiKind::Clinic,
            name: "Clinique Martin",
            ..doctor
        };
        // "Martin" agrees with both names, and the two stand as near: were
        // the doctor a candidate, the review would go to neither.
        let both = GeoSubject::parse("geo:47.0,2.0?q=Martin&u=50").unwrap();
        assert_eq!(
            review_poi(&both, &[doctor, clinic]),
            Some(1),
            "a clinic is an establishment, the doctor beside it no candidate"
        );
        for kind in PoiKind::ALL {
            let individual = matches!(kind.category(), crate::poi::PoiCategory::Health)
                && !matches!(
                    kind,
                    PoiKind::Pharmacy
                        | PoiKind::Hospital
                        | PoiKind::Veterinary
                        | PoiKind::Clinic
                        | PoiKind::Laboratory
                        | PoiKind::Optician
                        | PoiKind::HearingAids
                        | PoiKind::MedicalSupply
                );
            assert_eq!(
                poi_takes_reviews(*kind),
                !individual,
                "{kind}: every health kind is either an establishment or a person's practice"
            );
        }
    }

    #[test]
    fn two_points_of_the_same_name_as_near_take_no_review() {
        let a = PoiCandidate {
            position: pos(47.0, 2.0),
            kind: PoiKind::Supermarket,
            name: "Carrefour Market",
        };
        let b = PoiCandidate {
            position: pos(47.0, 2.00002),
            ..a
        };
        let far = PoiCandidate {
            position: pos(47.0015, 2.0),
            ..a
        };
        let review = GeoSubject::parse("geo:47.0,2.00001?q=Carrefour%20Market&u=300").unwrap();
        assert_eq!(review_poi(&review, &[a, b]), None);
        assert_eq!(
            review_poi(&review, &[far, a]),
            Some(1),
            "the nearer of two branches far apart"
        );
    }

    #[test]
    fn language_tags_are_normalised() {
        assert_eq!(content_language("FR").as_deref(), Some("fr"));
        assert_eq!(content_language("pt_BR").as_deref(), Some("pt-BR"));
        assert_eq!(content_language("und").as_deref(), Some("und"));
        assert_eq!(content_language("french"), None);
        assert_eq!(content_language(""), None);
    }

    #[test]
    fn relations_round_trip_their_codes() {
        for r in [
            PhotoRelation::Linked,
            PhotoRelation::Facing,
            PhotoRelation::Nearby,
        ] {
            assert_eq!(PhotoRelation::from_code(r.code()), Some(r));
        }
        assert!(
            PhotoRelation::Linked < PhotoRelation::Nearby,
            "linked photos come first"
        );
    }
}
