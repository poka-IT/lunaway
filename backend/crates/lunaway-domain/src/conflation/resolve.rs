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
    record::{Address, NormalizedRecord},
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
#[must_use]
pub fn trust_prior(source: &SourceId, field: Field) -> f64 {
    let osm = *source == SourceId::OSM;
    let atout = *source == SourceId::ATOUT_FRANCE;
    let community = *source == SourceId::COMMUNITY;
    let pick = |o: f64, a: f64, c: f64| {
        if osm {
            o
        } else if atout {
            a
        } else if community {
            c
        } else {
            0.5
        }
    };
    match field {
        Field::Name => pick(0.7, 0.6, 0.8),
        Field::Kind => pick(0.8, 0.9, 0.85),
        Field::Position => pick(0.9, 0.4, 0.7),
        Field::Overnight => pick(0.6, 0.7, 1.0),
        Field::Services => pick(0.8, 0.1, 0.9),
        Field::Activities => pick(0.7, 0.1, 0.9),
        Field::Description => pick(0.6, 0.5, 0.8),
        Field::Address => pick(0.7, 0.9, 0.6),
        Field::PriceParking | Field::PriceServices => pick(0.6, 0.5, 0.9),
        Field::MaxHeight => pick(0.9, 0.1, 0.8),
        Field::Capacity => pick(0.7, 0.9, 0.6),
        Field::OpeningHours => pick(0.8, 0.3, 0.7),
        Field::Website => pick(0.7, 0.8, 0.6),
        Field::Phone => pick(0.8, 0.5, 0.7),
        Field::Stars => pick(0.5, 1.0, 0.3),
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

/// A place with its values and their provenance.
#[derive(Debug, Clone, PartialEq)]
pub struct ResolvedPlace {
    /// The values.
    pub content: PlaceContent,
    /// One entry per field that has a value, in [`Field::ALL`] order.
    pub provenance: Vec<FieldProvenance>,
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
            capacity,
            opening_hours,
            website,
            phone,
            stars,
        },
        provenance,
    })
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
                record: &o,
            },
            Contribution {
                source: &SourceId::ATOUT_FRANCE,
                external_id: "49610:varennes",
                fetched_at: at(5),
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
                record: &old,
            },
            Contribution {
                source: &SourceId::OSM,
                external_id: "node/2",
                fetched_at: at(4),
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
            record: &o,
        };
        let y = Contribution {
            source: &SourceId::ATOUT_FRANCE,
            external_id: "k",
            fetched_at: at(5),
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
                &other,
            ] {
                assert!((0.0..=1.0).contains(&trust_prior(s, *f)));
            }
        }
    }

    #[test]
    fn numbers_render_without_a_useless_decimal() {
        assert_eq!(render_f64(12.0), "12");
        assert_eq!(render_f64(12.5), "12.5");
        assert_eq!(render_f64(0.0), "0");
    }
}
