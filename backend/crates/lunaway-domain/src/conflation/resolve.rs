//! Resolving each field of a place from the records that describe it.
//!
//! For every field, the records that have a value are ranked by the trust
//! prior of their source for that field, then by freshness, and the first one
//! supplies the value. The values of the others are kept as alternatives
//! when they differ, so a conflict stays visible. Community votes will join
//! the ranking when contributions exist.

use std::cmp::Ordering;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::{
    Activity, OvernightStatus, PlaceKind, Service,
    geo::Position,
    record::{Address, NormalizedRecord, UNDETERMINED_LANGUAGE, is_language_tag},
    source::SourceId,
};

/// Declares [`Field`] with the name each field has in the API, which is also
/// the name stored in the provenance.
macro_rules! coded_field {
    ($($variant:ident => $name:literal,)+) => {
        /// A field of a place that a source can supply.
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
        pub enum Field {
            $(
                #[doc = concat!("`", $name, "`")]
                $variant,
            )+
        }

        impl Field {
            /// Every field.
            pub const ALL: &'static [Self] = &[$(Self::$variant,)+];

            /// The field's name in the GraphQL API and in the provenance.
            #[must_use]
            pub const fn api_name(self) -> &'static str {
                match self {
                    $(Self::$variant => $name,)+
                }
            }
        }
    };
}

coded_field! {
    Name => "name",
    Kind => "kind",
    Position => "position",
    Overnight => "overnight",
    Services => "services",
    Activities => "activities",
    Description => "description",
    Address => "address",
    PriceParking => "priceParkingEur",
    PriceServices => "priceServicesEur",
    MaxHeight => "maxHeightM",
    MaxLength => "maxLengthM",
    MaxWidth => "maxWidthM",
    MaxWeight => "maxWeightT",
    Capacity => "capacity",
    OpeningHours => "openingHours",
    Website => "website",
    Phone => "phone",
    Stars => "stars",
}

/// How much a source is trusted for a field, in [0, 1]. Sources not listed
/// get 0.5. The reasons, per source:
///
/// - OpenStreetMap: surveyed geometry and physical limits (height), well
///   structured opening hours; names in mixed case.
/// - Atout France: the legal classification (stars, pitches, the fact that it
///   is a campsite) and the postal address; positions are geocoded from that
///   address, so they lose to a mapped point; names are upper-case
///   commercial names.
/// - The community: what changes and what only a visitor knows (whether a
///   night is tolerated, the state of the services, the price).
/// - The external community source (`extcom`): a partner's community,
///   years of visits per spot. It ranks high on what visitors report
///   (overnight status, services, prices, activities, descriptions), just
///   below Lunaway's own users, whose contributions go through Lunaway's
///   moderation and are the most recent word; it ranks low on what a
///   visitor's phone measures badly or a free-text form mangles: the
///   position (a pin dropped on a phone, behind OpenStreetMap's mapped
///   geometry and Lunaway's reviewed pins), the vehicle limits (read off a
///   sign from memory, where OpenStreetMap maps the sign), the kind (the
///   partner's categories are coarser than the taxonomy), the address and
///   the opening periods (free text, converted), and the stars (not an
///   official classification).
#[must_use]
pub fn trust_prior(source: &SourceId, field: Field) -> f64 {
    let osm = *source == SourceId::OSM;
    let atout = *source == SourceId::ATOUT_FRANCE;
    let community = *source == SourceId::COMMUNITY;
    let extcom = *source == SourceId::EXTCOM;
    let pick = |o: f64, a: f64, c: f64, x: f64| {
        if osm {
            o
        } else if atout {
            a
        } else if community {
            c
        } else if extcom {
            x
        } else {
            0.5
        }
    };
    match field {
        Field::Name => pick(0.7, 0.6, 0.8, 0.65),
        Field::Kind => pick(0.8, 0.9, 0.85, 0.6),
        Field::Position => pick(0.9, 0.4, 0.7, 0.65),
        Field::Overnight => pick(0.6, 0.7, 1.0, 0.95),
        Field::Services => pick(0.8, 0.1, 0.9, 0.85),
        Field::Activities => pick(0.7, 0.1, 0.9, 0.8),
        Field::Description => pick(0.6, 0.5, 0.8, 0.75),
        Field::Address => pick(0.7, 0.9, 0.6, 0.5),
        Field::PriceParking | Field::PriceServices => pick(0.6, 0.5, 0.9, 0.85),
        Field::MaxHeight | Field::MaxLength | Field::MaxWidth | Field::MaxWeight => {
            pick(0.9, 0.1, 0.8, 0.5)
        }
        Field::Capacity => pick(0.7, 0.9, 0.6, 0.5),
        Field::OpeningHours => pick(0.8, 0.3, 0.7, 0.5),
        Field::Website => pick(0.7, 0.8, 0.6, 0.5),
        Field::Phone => pick(0.8, 0.5, 0.7, 0.5),
        Field::Stars => pick(0.5, 1.0, 0.3, 0.2),
    }
}

/// One record offered to the resolution.
#[derive(Debug, Clone, Copy)]
pub struct Contribution<'a> {
    /// Its source.
    pub source: &'a SourceId,
    /// Its identifier in the source, the last tie-break.
    pub external_id: &'a str,
    /// When the source was read.
    pub fetched_at: DateTime<Utc>,
    /// Page of the record at the source (`https://www.openstreetmap.org/way/1`).
    pub external_url: Option<&'a str>,
    /// What it says.
    pub record: &'a NormalizedRecord,
}

/// The resolved values of a place.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlaceContent {
    /// Display name.
    pub name: Option<String>,
    /// Kind.
    pub kind: PlaceKind,
    /// Position.
    pub position: Position,
    /// Whether a night may be spent there.
    pub overnight: OvernightStatus,
    /// Services, sorted.
    pub services: Vec<Service>,
    /// Activities, sorted.
    pub activities: Vec<Activity>,
    /// Free text.
    pub description: Option<String>,
    /// Address, from a single source.
    pub address: Address,
    /// Price of a night, euros.
    pub price_parking_eur: Option<f64>,
    /// Price of the services, euros.
    pub price_services_eur: Option<f64>,
    /// Maximum vehicle height, metres.
    pub max_height_m: Option<f64>,
    /// Maximum vehicle length, metres. Left out of the stored form when
    /// unknown, like the fields after it, so the digest of a place that
    /// has none stays what it was before they existed.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_length_m: Option<f64>,
    /// Maximum vehicle width, metres.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_width_m: Option<f64>,
    /// Maximum vehicle weight, tonnes.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_weight_t: Option<f64>,
    /// Pitches.
    pub capacity: Option<u32>,
    /// OSM `opening_hours`.
    pub opening_hours: Option<String>,
    /// Website.
    pub website: Option<String>,
    /// Phone.
    pub phone: Option<String>,
    /// Stars, campsites only.
    pub stars: Option<u8>,
}

/// A value another source gave for a field, different from the one kept.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AlternativeValue {
    /// The source that gave it.
    pub source_id: SourceId,
    /// The value, rendered as text.
    pub value: String,
}

/// Which source supplied a field, and what the others said.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FieldProvenance {
    /// The field's API name ([`Field::api_name`]).
    pub field: String,
    /// The source of the value kept.
    pub source_id: SourceId,
    /// Differing values from other sources.
    pub alternatives: Vec<AlternativeValue>,
}

/// A description in one language, with the source that wrote it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalizedText {
    /// BCP 47 tag, [`UNDETERMINED_LANGUAGE`] when the source does not say.
    pub lang: String,
    /// The text.
    pub text: String,
    /// The source that wrote it.
    pub source_id: SourceId,
}

/// A page about the place elsewhere: its record at a source, its Wikidata
/// item, its Wikipedia article.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExternalLink {
    /// The source that gave the link.
    pub source_id: SourceId,
    /// An `https` (or `http`) URL.
    pub url: String,
    /// A short neutral label (`OpenStreetMap`, `Wikidata`, `Wikipedia`).
    pub label: String,
}

/// A place with its values and their provenance.
#[derive(Debug, Clone, PartialEq)]
pub struct ResolvedPlace {
    /// The values.
    pub content: PlaceContent,
    /// One entry per field that has a value, in [`Field::ALL`] order.
    pub provenance: Vec<FieldProvenance>,
    /// Every description of every source, the source most trusted for
    /// descriptions first, one entry per language and text.
    pub descriptions: Vec<LocalizedText>,
    /// Links to the place's pages elsewhere, one per URL.
    pub external_links: Vec<ExternalLink>,
}

fn rank(field: Field, x: &Contribution<'_>, y: &Contribution<'_>) -> Ordering {
    trust_prior(y.source, field)
        .total_cmp(&trust_prior(x.source, field))
        .then(y.fetched_at.cmp(&x.fetched_at))
        .then(x.source.cmp(y.source))
        .then(x.external_id.cmp(y.external_id))
}

fn non_empty(s: Option<&String>) -> Option<String> {
    s.map(|v| v.trim())
        .filter(|v| !v.is_empty())
        .map(str::to_owned)
}

fn render_f64(v: f64) -> String {
    // Shortest text that reads back to the same number, as JSON writes it.
    let mut s = format!("{v}");
    if s.ends_with(".0") {
        s.truncate(s.len() - 2);
    }
    s
}

fn render_codes<T: std::fmt::Display>(v: &[T]) -> String {
    v.iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join(",")
}

fn render_address(a: &Address) -> String {
    let city = [a.postcode.as_deref(), a.city.as_deref()]
        .into_iter()
        .flatten()
        .collect::<Vec<_>>()
        .join(" ");
    [
        a.street.as_deref(),
        Some(city.as_str()),
        a.country_code.as_deref(),
    ]
    .into_iter()
    .flatten()
    .filter(|s| !s.is_empty())
    .collect::<Vec<_>>()
    .join(", ")
}

struct Resolver<'a, 'b> {
    contributions: &'b [Contribution<'a>],
    provenance: Vec<FieldProvenance>,
}

impl<'a> Resolver<'a, '_> {
    /// The best-ranked value of `field`, recording its provenance.
    fn pick<T>(
        &mut self,
        field: Field,
        get: impl Fn(&'a NormalizedRecord) -> Option<T>,
        render: impl Fn(&T) -> String,
    ) -> Option<T> {
        let mut ranked: Vec<&Contribution<'a>> = self.contributions.iter().collect();
        ranked.sort_by(|x, y| rank(field, x, y));
        let mut values = ranked
            .into_iter()
            .filter_map(|c| get(c.record).map(|v| (c.source, v)));
        let (source, chosen) = values.next()?;
        let chosen_text = render(&chosen);
        let mut alternatives: Vec<AlternativeValue> = Vec::new();
        for (s, v) in values {
            let text = render(&v);
            let known = alternatives
                .iter()
                .any(|a| a.source_id == *s && a.value == text);
            if text != chosen_text && !known {
                alternatives.push(AlternativeValue {
                    source_id: s.clone(),
                    value: text,
                });
            }
        }
        self.provenance.push(FieldProvenance {
            field: field.api_name().to_owned(),
            source_id: source.clone(),
            alternatives,
        });
        Some(chosen)
    }
}

/// Resolves a place from the records that describe it; `None` when there are
/// none.
#[must_use]
pub fn resolve(contributions: &[Contribution<'_>]) -> Option<ResolvedPlace> {
    let mut r = Resolver {
        contributions,
        provenance: Vec::new(),
    };
    let name = r.pick(Field::Name, |x| non_empty(x.name.as_ref()), Clone::clone);
    let kind = r.pick(Field::Kind, |x| Some(x.kind), |k| k.code().to_owned())?;
    let position = r.pick(
        Field::Position,
        |x| Some(x.position),
        |p| format!("{:.6},{:.6}", p.lat(), p.lon()),
    )?;
    let overnight = r
        .pick(
            Field::Overnight,
            |x| (x.overnight != OvernightStatus::Unknown).then_some(x.overnight),
            |o| o.code().to_owned(),
        )
        .unwrap_or(OvernightStatus::Unknown);
    let services = r
        .pick(
            Field::Services,
            |x| (!x.services.is_empty()).then(|| x.services.iter().copied().collect::<Vec<_>>()),
            |v| render_codes(v),
        )
        .unwrap_or_default();
    let activities = r
        .pick(
            Field::Activities,
            |x| {
                (!x.activities.is_empty()).then(|| x.activities.iter().copied().collect::<Vec<_>>())
            },
            |v| render_codes(v),
        )
        .unwrap_or_default();
    let description = r.pick(
        Field::Description,
        |x| non_empty(x.description.as_ref()),
        Clone::clone,
    );
    let address = r
        .pick(
            Field::Address,
            |x| (!x.address.is_empty()).then(|| x.address.clone()),
            render_address,
        )
        .unwrap_or_default();
    let price_parking_eur = r.pick(
        Field::PriceParking,
        |x| x.price_parking_eur,
        |v| render_f64(*v),
    );
    let price_services_eur = r.pick(
        Field::PriceServices,
        |x| x.price_services_eur,
        |v| render_f64(*v),
    );
    let max_height_m = r.pick(Field::MaxHeight, |x| x.max_height_m, |v| render_f64(*v));
    let max_length_m = r.pick(Field::MaxLength, |x| x.max_length_m, |v| render_f64(*v));
    let max_width_m = r.pick(Field::MaxWidth, |x| x.max_width_m, |v| render_f64(*v));
    let max_weight_t = r.pick(Field::MaxWeight, |x| x.max_weight_t, |v| render_f64(*v));
    let capacity = r.pick(Field::Capacity, |x| x.capacity, ToString::to_string);
    let opening_hours = r.pick(
        Field::OpeningHours,
        |x| non_empty(x.opening_hours.as_ref()),
        Clone::clone,
    );
    let website = r.pick(
        Field::Website,
        |x| non_empty(x.website.as_ref()),
        Clone::clone,
    );
    let phone = r.pick(Field::Phone, |x| non_empty(x.phone.as_ref()), Clone::clone);
    let stars = r.pick(Field::Stars, |x| x.stars, ToString::to_string);

    let mut provenance = r.provenance;
    provenance.sort_by_key(|p| Field::ALL.iter().position(|f| f.api_name() == p.field));
    let descriptions = descriptions(contributions);
    let external_links = external_links(contributions);
    Some(ResolvedPlace {
        content: PlaceContent {
            name,
            kind,
            position,
            overnight,
            services,
            activities,
            description,
            address,
            price_parking_eur,
            price_services_eur,
            max_height_m,
            max_length_m,
            max_width_m,
            max_weight_t,
            capacity,
            opening_hours,
            website,
            phone,
            stars,
        },
        provenance,
        descriptions,
        external_links,
    })
}

/// Longest description kept, in characters: OpenStreetMap allows 255, a
/// contributor 2000.
const MAX_DESCRIPTION_CHARS: usize = 2_000;

/// Every description, the source most trusted for descriptions first, then
/// by language; the same text in the same language is kept once. A record
/// stored before descriptions were kept by language gives its single
/// description as undetermined.
fn descriptions(contributions: &[Contribution<'_>]) -> Vec<LocalizedText> {
    let mut ranked: Vec<&Contribution<'_>> = contributions.iter().collect();
    ranked.sort_by(|x, y| rank(Field::Description, x, y));
    let mut out: Vec<LocalizedText> = Vec::new();
    for c in ranked {
        let legacy = c
            .record
            .description
            .as_ref()
            .filter(|_| c.record.descriptions.is_empty())
            .map(|d| (UNDETERMINED_LANGUAGE, d));
        let texts = c
            .record
            .descriptions
            .iter()
            .map(|(l, t)| (l.as_str(), t))
            .chain(legacy);
        for (lang, text) in texts {
            let text = text.trim();
            if text.is_empty() || !is_language_tag(lang) {
                continue;
            }
            let text: String = text.chars().take(MAX_DESCRIPTION_CHARS).collect();
            if out.iter().any(|d| d.lang == lang && d.text == text) {
                continue;
            }
            out.push(LocalizedText {
                lang: lang.to_owned(),
                text,
                source_id: c.source.clone(),
            });
        }
    }
    out
}

/// The label of a source's own record page.
fn source_label(source: &SourceId) -> String {
    if *source == SourceId::OSM {
        "OpenStreetMap".to_owned()
    } else if *source == SourceId::ATOUT_FRANCE {
        "Atout France".to_owned()
    } else if *source == SourceId::COMMUNITY {
        "Lunaway".to_owned()
    } else {
        source.as_str().to_owned()
    }
}

/// Whether `url` is a plain web link: `https://` or `http://`, then a host.
fn is_web_url(url: &str) -> bool {
    ["https://", "http://"].iter().any(|scheme| {
        url.get(..scheme.len())
            .is_some_and(|p| p.eq_ignore_ascii_case(scheme))
            && url.len() > scheme.len()
            && !url.chars().any(char::is_whitespace)
    })
}

/// Percent-encodes a Wikipedia title for a URL path, spaces as underscores.
fn encode_title(title: &str) -> String {
    let mut out = String::with_capacity(title.len());
    for b in title.trim().replace(' ', "_").bytes() {
        if b.is_ascii_alphanumeric() || b"_-.~()!,:'".contains(&b) {
            out.push(char::from(b));
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// The URL of an OpenStreetMap `wikipedia` value (`fr:Lac d'Annecy`).
#[must_use]
pub fn wikipedia_url(value: &str) -> Option<String> {
    let (lang, title) = value.split_once(':')?;
    let lang = lang.trim();
    let valid_lang = (2..=12).contains(&lang.len())
        && lang.bytes().all(|b| b.is_ascii_lowercase() || b == b'-')
        && !lang.starts_with('-');
    let title = title.trim();
    (valid_lang && !title.is_empty() && title.len() <= 255)
        .then(|| format!("https://{lang}.wikipedia.org/wiki/{}", encode_title(title)))
}

/// Links to the place elsewhere: each record's page at its source, then the
/// Wikidata items and Wikipedia articles the records cite, one per URL.
fn external_links(contributions: &[Contribution<'_>]) -> Vec<ExternalLink> {
    let mut ordered: Vec<&Contribution<'_>> = contributions.iter().collect();
    ordered.sort_by(|x, y| {
        x.source
            .cmp(y.source)
            .then(x.external_id.cmp(y.external_id))
    });
    let mut out: Vec<ExternalLink> = Vec::new();
    let mut push = |source: &SourceId, url: String, label: &str| {
        if is_web_url(&url) && !out.iter().any(|l| l.url == url) {
            out.push(ExternalLink {
                source_id: source.clone(),
                url,
                label: label.to_owned(),
            });
        }
    };
    for c in &ordered {
        if let Some(url) = c.external_url {
            push(c.source, url.trim().to_owned(), &source_label(c.source));
        }
    }
    for c in &ordered {
        if let Some(q) = c
            .record
            .wikidata
            .as_deref()
            .and_then(super::normalize::normalize_wikidata)
        {
            push(
                c.source,
                format!("https://www.wikidata.org/wiki/{q}"),
                "Wikidata",
            );
        }
    }
    for c in &ordered {
        if let Some(url) = c.record.wikipedia.as_deref().and_then(wikipedia_url) {
            push(c.source, url, "Wikipedia");
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone;

    use super::*;

    fn at(day: u32) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 10, day, 0, 0, 0).unwrap()
    }

    fn osm_campsite() -> NormalizedRecord {
        let mut r = NormalizedRecord::new(
            PlaceKind::Campsite,
            Position::new(47.4031, -0.5612).unwrap(),
        );
        r.name = Some("Camping des Varennes".into());
        r.overnight = OvernightStatus::Allowed;
        r.services = [Service::Toilets, Service::Showers].into();
        r.capacity = Some(80);
        r.phone = Some("+33 2 41 00 00 00".into());
        r.address.city = Some("Mûrs-Erigné".into());
        r.stars = Some(2);
        r
    }

    fn atout_campsite() -> NormalizedRecord {
        let mut r = NormalizedRecord::new(
            PlaceKind::Campsite,
            Position::new(47.4033, -0.5610).unwrap(),
        );
        r.name = Some("Agis - Camping des Varennes".into());
        r.overnight = OvernightStatus::Allowed;
        r.capacity = Some(90);
        r.stars = Some(1);
        r.website = Some("http://www.camping-varennes.com".into());
        r.address = Address {
            street: Some("Chemin de la Jubeaudière".into()),
            postcode: Some("49610".into()),
            city: Some("Mûrs-Erigné".into()),
            country_code: Some("FR".into()),
            city_code: Some("49223".into()),
        };
        r
    }

    #[test]
    fn each_field_comes_from_the_source_trusted_for_it() {
        let (o, a) = (osm_campsite(), atout_campsite());
        let contributions = [
            Contribution {
                source: &SourceId::OSM,
                external_id: "way/1",
                fetched_at: at(5),
                external_url: None,
                record: &o,
            },
            Contribution {
                source: &SourceId::ATOUT_FRANCE,
                external_id: "49610:varennes",
                fetched_at: at(5),
                external_url: None,
                record: &a,
            },
        ];
        let place = resolve(&contributions).unwrap();
        let c = &place.content;
        assert_eq!(
            c.name.as_deref(),
            Some("Camping des Varennes"),
            "OSM spells names in mixed case"
        );
        assert_eq!(
            c.position, o.position,
            "a mapped point beats a geocoded address"
        );
        assert_eq!(
            c.stars,
            Some(1),
            "the legal classification comes from Atout France"
        );
        assert_eq!(c.capacity, Some(90), "so does the number of pitches");
        assert_eq!(c.address.postcode.as_deref(), Some("49610"));
        assert_eq!(
            c.website.as_deref(),
            Some("http://www.camping-varennes.com")
        );
        assert_eq!(c.phone.as_deref(), Some("+33 2 41 00 00 00"));
        assert_eq!(c.services, vec![Service::Toilets, Service::Showers]);

        let stars = place
            .provenance
            .iter()
            .find(|p| p.field == "stars")
            .unwrap();
        assert_eq!(stars.source_id, SourceId::ATOUT_FRANCE);
        assert_eq!(
            stars.alternatives,
            vec![AlternativeValue {
                source_id: SourceId::OSM,
                value: "2".into()
            }],
            "the losing value stays visible"
        );
        let overnight = place
            .provenance
            .iter()
            .find(|p| p.field == "overnight")
            .unwrap();
        assert!(
            overnight.alternatives.is_empty(),
            "agreeing sources are not a conflict"
        );
        assert!(
            place.provenance.iter().all(|p| p.field != "description"),
            "no value, no provenance"
        );
        let order: Vec<&str> = place.provenance.iter().map(|p| p.field.as_str()).collect();
        let mut sorted = order.clone();
        sorted.sort_by_key(|f| Field::ALL.iter().position(|x| x.api_name() == *f));
        assert_eq!(order, sorted);
    }

    #[test]
    fn freshness_breaks_a_tie_between_equal_sources() {
        let mut old = osm_campsite();
        old.name = Some("Old name".into());
        let new = osm_campsite();
        let contributions = [
            Contribution {
                source: &SourceId::OSM,
                external_id: "node/1",
                fetched_at: at(1),
                external_url: None,
                record: &old,
            },
            Contribution {
                source: &SourceId::OSM,
                external_id: "node/2",
                fetched_at: at(4),
                external_url: None,
                record: &new,
            },
        ];
        let place = resolve(&contributions).unwrap();
        assert_eq!(place.content.name.as_deref(), Some("Camping des Varennes"));
    }

    #[test]
    fn the_result_does_not_depend_on_the_input_order() {
        let (o, a) = (osm_campsite(), atout_campsite());
        let x = Contribution {
            source: &SourceId::OSM,
            external_id: "way/1",
            fetched_at: at(5),
            external_url: None,
            record: &o,
        };
        let y = Contribution {
            source: &SourceId::ATOUT_FRANCE,
            external_id: "k",
            fetched_at: at(5),
            external_url: None,
            record: &a,
        };
        assert_eq!(resolve(&[x, y]), resolve(&[y, x]));
    }

    #[test]
    fn unknown_overnight_is_no_value() {
        let mut o = osm_campsite();
        o.overnight = OvernightStatus::Unknown;
        let place = resolve(&[Contribution {
            source: &SourceId::OSM,
            external_id: "n",
            fetched_at: at(1),
            external_url: None,
            record: &o,
        }])
        .unwrap();
        assert_eq!(place.content.overnight, OvernightStatus::Unknown);
        assert!(place.provenance.iter().all(|p| p.field != "overnight"));
    }

    #[test]
    fn nothing_to_resolve() {
        assert!(resolve(&[]).is_none());
    }

    #[test]
    fn descriptions_keep_every_language_and_their_source() {
        let mut o = osm_campsite();
        o.description = Some("Au bord de la Loire".into());
        o.descriptions = [
            ("und".to_owned(), "Au bord de la Loire".to_owned()),
            ("en".to_owned(), "On the Loire".to_owned()),
            ("payment".to_owned(), "cash".to_owned()),
        ]
        .into();
        let mut c = osm_campsite();
        c.descriptions = [("fr".to_owned(), "Calme, ombragé".to_owned())].into();
        let mut legacy = atout_campsite();
        legacy.description = Some("Classé trois étoiles".into());
        let place = resolve(&[
            Contribution {
                source: &SourceId::OSM,
                external_id: "way/1",
                fetched_at: at(5),
                external_url: Some("https://www.openstreetmap.org/way/1"),
                record: &o,
            },
            Contribution {
                source: &SourceId::COMMUNITY,
                external_id: "submission/1",
                fetched_at: at(5),
                external_url: None,
                record: &c,
            },
            Contribution {
                source: &SourceId::ATOUT_FRANCE,
                external_id: "k",
                fetched_at: at(5),
                external_url: None,
                record: &legacy,
            },
        ])
        .unwrap();
        let got: Vec<(&str, &str, &str)> = place
            .descriptions
            .iter()
            .map(|d| (d.lang.as_str(), d.text.as_str(), d.source_id.as_str()))
            .collect();
        assert_eq!(
            got,
            [
                ("fr", "Calme, ombragé", "community"),
                ("en", "On the Loire", "osm"),
                ("und", "Au bord de la Loire", "osm"),
                ("und", "Classé trois étoiles", "atout-france"),
            ],
            "the community leads on descriptions, a key that is not a language is dropped, \
             and a record stored before descriptions by language still gives its text"
        );
    }

    #[test]
    fn links_point_to_the_records_and_the_items_they_cite() {
        let mut o = osm_campsite();
        o.wikidata = Some("q42".into());
        o.wikipedia = Some("fr:Lac d'Annecy".into());
        let mut a = atout_campsite();
        a.wikidata = Some("Q42".into());
        let place = resolve(&[
            Contribution {
                source: &SourceId::ATOUT_FRANCE,
                external_id: "k",
                fetched_at: at(5),
                external_url: Some("javascript:alert(1)"),
                record: &a,
            },
            Contribution {
                source: &SourceId::OSM,
                external_id: "way/1",
                fetched_at: at(5),
                external_url: Some("https://www.openstreetmap.org/way/1"),
                record: &o,
            },
        ])
        .unwrap();
        let got: Vec<(&str, &str, &str)> = place
            .external_links
            .iter()
            .map(|l| (l.source_id.as_str(), l.url.as_str(), l.label.as_str()))
            .collect();
        assert_eq!(
            got,
            [
                (
                    "osm",
                    "https://www.openstreetmap.org/way/1",
                    "OpenStreetMap"
                ),
                (
                    "atout-france",
                    "https://www.wikidata.org/wiki/Q42",
                    "Wikidata"
                ),
                (
                    "osm",
                    "https://fr.wikipedia.org/wiki/Lac_d'Annecy",
                    "Wikipedia"
                ),
            ],
            "web links only, one per URL"
        );
        assert_eq!(
            wikipedia_url("en:AC/DC Lane?x#y"),
            Some("https://en.wikipedia.org/wiki/AC%2FDC_Lane%3Fx%23y".to_owned())
        );
        assert_eq!(wikipedia_url("no colon"), None);
        assert_eq!(wikipedia_url("FR:Title"), None);
    }

    #[test]
    fn every_field_name_is_unique_and_trust_is_bounded() {
        let mut names: Vec<&str> = Field::ALL.iter().map(|f| f.api_name()).collect();
        names.sort_unstable();
        names.dedup();
        assert_eq!(names.len(), Field::ALL.len());
        let other = SourceId::new("datatourisme").unwrap();
        for f in Field::ALL {
            for s in [
                &SourceId::OSM,
                &SourceId::ATOUT_FRANCE,
                &SourceId::COMMUNITY,
                &SourceId::EXTCOM,
                &other,
            ] {
                assert!((0.0..=1.0).contains(&trust_prior(s, *f)));
            }
        }
    }

    fn extcom_spot() -> NormalizedRecord {
        let mut r =
            NormalizedRecord::new(PlaceKind::Parking, Position::new(47.4035, -0.5608).unwrap());
        r.name = Some("Parking du lac, calme la nuit".into());
        r.overnight = OvernightStatus::Tolerated;
        r.services = [Service::DrinkingWater, Service::WasteBin].into();
        r.price_parking_eur = Some(0.0);
        r.max_height_m = Some(2.5);
        r
    }

    #[test]
    fn the_external_community_leads_on_what_visitors_report_and_osm_on_what_it_maps() {
        let mut o =
            NormalizedRecord::new(PlaceKind::Parking, Position::new(47.4031, -0.5612).unwrap());
        o.name = Some("Parking du Lac".into());
        o.overnight = OvernightStatus::Allowed;
        o.services = [Service::Toilets].into();
        o.max_height_m = Some(2.2);
        let x = extcom_spot();
        let contributions = [
            Contribution {
                source: &SourceId::OSM,
                external_id: "way/1",
                fetched_at: at(5),
                external_url: None,
                record: &o,
            },
            Contribution {
                source: &SourceId::EXTCOM,
                external_id: "spot-1",
                fetched_at: at(6),
                external_url: None,
                record: &x,
            },
        ];
        let place = resolve(&contributions).unwrap();
        let c = &place.content;
        assert_eq!(
            c.overnight,
            OvernightStatus::Tolerated,
            "visitors know whether a night is tolerated better than a map"
        );
        assert_eq!(
            c.services,
            vec![Service::DrinkingWater, Service::WasteBin],
            "the services visitors report win over the mapped ones"
        );
        assert_eq!(c.price_parking_eur, Some(0.0));
        assert_eq!(c.position, o.position, "OSM's mapped geometry wins");
        assert_eq!(
            c.max_height_m,
            Some(2.2),
            "a limit mapped from the sign wins over one remembered by a visitor"
        );
        assert_eq!(c.name.as_deref(), Some("Parking du Lac"));
    }

    #[test]
    fn lunaway_users_outrank_the_external_community_on_every_field_they_share() {
        for f in Field::ALL {
            assert!(
                trust_prior(&SourceId::COMMUNITY, *f) >= trust_prior(&SourceId::EXTCOM, *f),
                "{f:?}: a Lunaway contribution, moderated here and more recent, must not lose \
                 to a partner's copy"
            );
        }
    }

    #[test]
    fn numbers_render_without_a_useless_decimal() {
        assert_eq!(render_f64(12.0), "12");
        assert_eq!(render_f64(12.5), "12.5");
        assert_eq!(render_f64(0.0), "0");
    }
}
