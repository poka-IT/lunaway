//! New places and place edits a contributor sends: what they may say, how
//! it is checked, and how it becomes a record of the `community` source.
//!
//! A submission is stored as JSON (the revision history) and replayed into
//! the community record of the place, so its serialised form is part of the
//! database: fields are only added, with a serde default, never renamed.

use std::{collections::BTreeSet, fmt, str::FromStr};

use serde::{Deserialize, Serialize};

use crate::{
    Activity, NormalizedRecord, OvernightStatus, PlaceKind, Position, Service, UnknownCode,
    record::is_language_tag, taxonomy::coded_enum,
};

coded_enum! {
    /// A field of a place an edit can clear: the community stops stating
    /// it, and the value shown comes from the next source that does. The
    /// name and the kind cannot be cleared: a place only the community
    /// describes would be left without them.
    PlaceField {
        /// Every description of the community, in every language.
        Description => "description",
        /// Whether a night may be spent there (back to "nobody said").
        Overnight => "overnight",
        /// Services on site.
        Services => "services",
        /// Activities around.
        Activities => "activities",
        /// Price of a night.
        PriceParking => "price_parking",
        /// Price of the services.
        PriceServices => "price_services",
        /// Maximum vehicle height.
        MaxHeight => "max_height",
        /// Pitches.
        Capacity => "capacity",
        /// Opening hours.
        OpeningHours => "opening_hours",
        /// Website.
        Website => "website",
        /// Phone.
        Phone => "phone",
    }
}

/// A description in one language.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalizedDescription {
    /// BCP 47 tag.
    pub lang: String,
    /// The text.
    pub text: String,
}

/// What a contributor states about a place; every field is optional, and an
/// absent field says nothing (it never clears a value).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct PlacePatch {
    /// Display name.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// What the place is.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub kind: Option<PlaceKind>,
    /// Whether a night may be spent there.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub overnight: Option<OvernightStatus>,
    /// Services on site (the whole set).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub services: Option<BTreeSet<Service>>,
    /// Activities around (the whole set).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub activities: Option<BTreeSet<Activity>>,
    /// A description in one language.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<LocalizedDescription>,
    /// Price of a night, euros.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub price_parking_eur: Option<f64>,
    /// Price of the services, euros.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub price_services_eur: Option<f64>,
    /// Maximum vehicle height, metres.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_height_m: Option<f64>,
    /// Pitches for motorhomes.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub capacity: Option<u32>,
    /// OSM `opening_hours` syntax.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opening_hours: Option<String>,
    /// Website.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub website: Option<String>,
    /// Phone.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub phone: Option<String>,
    /// Fields the community stops stating (an edit only): a wrong phone
    /// removed, a closed website. Never with a value for the same field.
    #[serde(default, skip_serializing_if = "BTreeSet::is_empty")]
    pub clear: BTreeSet<PlaceField>,
}

impl PlacePatch {
    /// Whether the patch gives `field` a value.
    #[must_use]
    pub fn states(&self, field: PlaceField) -> bool {
        match field {
            PlaceField::Description => self.description.is_some(),
            PlaceField::Overnight => self.overnight.is_some(),
            PlaceField::Services => self.services.is_some(),
            PlaceField::Activities => self.activities.is_some(),
            PlaceField::PriceParking => self.price_parking_eur.is_some(),
            PlaceField::PriceServices => self.price_services_eur.is_some(),
            PlaceField::MaxHeight => self.max_height_m.is_some(),
            PlaceField::Capacity => self.capacity.is_some(),
            PlaceField::OpeningHours => self.opening_hours.is_some(),
            PlaceField::Website => self.website.is_some(),
            PlaceField::Phone => self.phone.is_some(),
        }
    }
}

/// A new place: where and what it is, and what else the contributor knows.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NewPlace {
    /// What it is.
    pub kind: PlaceKind,
    /// Where it is.
    pub position: Position,
    /// The rest.
    #[serde(default)]
    pub details: PlacePatch,
}

/// Why a submission is refused.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[non_exhaustive]
pub enum SubmissionError {
    /// The edit states nothing.
    #[error("the edit changes nothing")]
    Empty,
    /// A field is out of its bounds.
    #[error("{field}: {why}")]
    Field {
        /// The field, as the API names it.
        field: &'static str,
        /// What is wrong.
        why: &'static str,
    },
}

const fn bad(field: &'static str, why: &'static str) -> SubmissionError {
    SubmissionError::Field { field, why }
}

/// Longest name, in characters.
pub const NAME_MAX_CHARS: usize = 120;
/// Longest description, in characters.
pub const DESCRIPTION_MAX_CHARS: usize = 2_000;
/// Longest opening hours expression: the 255 characters OSM allows.
pub const OPENING_HOURS_MAX_CHARS: usize = 255;

fn trimmed(v: Option<&String>) -> Option<&str> {
    v.map(|s| s.trim())
}

/// Checks a patch and returns it trimmed.
///
/// # Errors
///
/// [`SubmissionError`] naming the first field out of bounds.
pub fn validate_patch(patch: &PlacePatch) -> Result<PlacePatch, SubmissionError> {
    if patch.clear.iter().any(|f| patch.states(*f)) {
        return Err(bad("clear", "a field is either given a value or cleared"));
    }
    let mut p = patch.clone();
    if let Some(name) = trimmed(patch.name.as_ref()) {
        let n = name.chars().count();
        if !(2..=NAME_MAX_CHARS).contains(&n) {
            return Err(bad("name", "2 to 120 characters"));
        }
        p.name = Some(name.to_owned());
    }
    if let Some(d) = &patch.description {
        let text = d.text.trim();
        if !is_language_tag(&d.lang) {
            return Err(bad(
                "description.lang",
                "a BCP 47 language tag such as fr or en",
            ));
        }
        if !(1..=DESCRIPTION_MAX_CHARS).contains(&text.chars().count()) {
            return Err(bad("description.text", "1 to 2000 characters"));
        }
        p.description = Some(LocalizedDescription {
            lang: d.lang.clone(),
            text: text.to_owned(),
        });
    }
    for (field, value) in [
        ("priceParkingEur", patch.price_parking_eur),
        ("priceServicesEur", patch.price_services_eur),
    ] {
        if value.is_some_and(|v| !(v.is_finite() && (0.0..=1_000.0).contains(&v))) {
            return Err(bad(field, "0 to 1000 euros"));
        }
    }
    if patch
        .max_height_m
        .is_some_and(|h| !(h.is_finite() && h > 0.5 && h <= 10.0))
    {
        return Err(bad("maxHeightM", "more than 0.5 and at most 10 metres"));
    }
    if patch.capacity.is_some_and(|c| c > 10_000) {
        return Err(bad("capacity", "at most 10000"));
    }
    if let Some(oh) = trimmed(patch.opening_hours.as_ref()) {
        if !(1..=OPENING_HOURS_MAX_CHARS).contains(&oh.chars().count()) {
            return Err(bad("openingHours", "1 to 255 characters"));
        }
        p.opening_hours = Some(oh.to_owned());
    }
    if let Some(w) = trimmed(patch.website.as_ref()) {
        let scheme_ok = ["https://", "http://"].iter().any(|s| {
            w.get(..s.len()).is_some_and(|x| x.eq_ignore_ascii_case(s)) && w.len() > s.len()
        });
        if !scheme_ok || w.len() > 500 || w.chars().any(char::is_whitespace) {
            return Err(bad(
                "website",
                "an http(s) address of at most 500 characters",
            ));
        }
        p.website = Some(w.to_owned());
    }
    if let Some(phone) = trimmed(patch.phone.as_ref()) {
        let digits = phone.chars().filter(char::is_ascii_digit).count();
        let allowed = phone
            .chars()
            .all(|c| c.is_ascii_digit() || " +-.()/".contains(c));
        if !allowed || !(6..=20).contains(&digits) || phone.len() > 40 {
            return Err(bad("phone", "6 to 20 digits, spaces and + - . ( ) /"));
        }
        p.phone = Some(phone.to_owned());
    }
    Ok(p)
}

/// Checks an edit: valid, and stating something.
///
/// # Errors
///
/// [`SubmissionError::Empty`] when it states nothing, or the field error.
pub fn validate_edit(patch: &PlacePatch) -> Result<PlacePatch, SubmissionError> {
    if *patch == PlacePatch::default() {
        return Err(SubmissionError::Empty);
    }
    validate_patch(patch)
}

/// Checks a new place.
///
/// # Errors
///
/// [`SubmissionError`] naming the field out of bounds; a new place needs a
/// name.
pub fn validate_new_place(place: &NewPlace) -> Result<NewPlace, SubmissionError> {
    if place
        .details
        .name
        .as_deref()
        .is_none_or(|n| n.trim().is_empty())
    {
        return Err(bad("name", "a new place needs a name"));
    }
    if !place.details.clear.is_empty() {
        return Err(bad("clear", "only an edit clears a field"));
    }
    Ok(NewPlace {
        kind: place.kind,
        position: place.position,
        details: validate_patch(&place.details)?,
    })
}

/// The texts of a patch the automatic rules read (name, description).
#[must_use]
pub fn texts(patch: &PlacePatch) -> Vec<&str> {
    let mut out = Vec::new();
    if let Some(n) = &patch.name {
        out.push(n.as_str());
    }
    if let Some(d) = &patch.description {
        out.push(d.text.as_str());
    }
    out
}

/// Writes what `patch` states into `record`, leaving the rest.
pub fn apply(record: &mut NormalizedRecord, patch: &PlacePatch) {
    if let Some(v) = &patch.name {
        record.name = Some(v.clone());
    }
    if let Some(v) = patch.kind {
        record.kind = v;
    }
    if let Some(v) = patch.overnight {
        record.overnight = v;
    }
    if let Some(v) = &patch.services {
        record.services.clone_from(v);
    }
    if let Some(v) = &patch.activities {
        record.activities.clone_from(v);
    }
    if let Some(d) = &patch.description {
        record.descriptions.insert(d.lang.clone(), d.text.clone());
        record.description = Some(d.text.clone());
    }
    if patch.price_parking_eur.is_some() {
        record.price_parking_eur = patch.price_parking_eur;
    }
    if patch.price_services_eur.is_some() {
        record.price_services_eur = patch.price_services_eur;
    }
    if patch.max_height_m.is_some() {
        record.max_height_m = patch.max_height_m;
    }
    if patch.capacity.is_some() {
        record.capacity = patch.capacity;
    }
    if let Some(v) = &patch.opening_hours {
        record.opening_hours = Some(v.clone());
    }
    if let Some(v) = &patch.website {
        record.website = Some(v.clone());
    }
    if let Some(v) = &patch.phone {
        record.phone = Some(v.clone());
    }
    for field in &patch.clear {
        match field {
            PlaceField::Description => {
                record.descriptions.clear();
                record.description = None;
            }
            PlaceField::Overnight => record.overnight = OvernightStatus::Unknown,
            PlaceField::Services => record.services.clear(),
            PlaceField::Activities => record.activities.clear(),
            PlaceField::PriceParking => record.price_parking_eur = None,
            PlaceField::PriceServices => record.price_services_eur = None,
            PlaceField::MaxHeight => record.max_height_m = None,
            PlaceField::Capacity => record.capacity = None,
            PlaceField::OpeningHours => record.opening_hours = None,
            PlaceField::Website => record.website = None,
            PlaceField::Phone => record.phone = None,
        }
    }
}

/// The community record of a new place.
#[must_use]
pub fn record_of(place: &NewPlace) -> NormalizedRecord {
    let mut r = NormalizedRecord::new(place.kind, place.position);
    apply(&mut r, &place.details);
    r
}

#[cfg(test)]
mod tests {
    use super::*;

    fn patch() -> PlacePatch {
        PlacePatch {
            name: Some("  Aire du Lac  ".into()),
            overnight: Some(OvernightStatus::Tolerated),
            description: Some(LocalizedDescription {
                lang: "fr".into(),
                text: "Calme la nuit".into(),
            }),
            max_height_m: Some(3.1),
            phone: Some("+33 4 50 00 00 00".into()),
            ..PlacePatch::default()
        }
    }

    #[test]
    fn a_patch_is_trimmed_and_written_into_a_record() {
        let p = validate_edit(&patch()).unwrap();
        assert_eq!(p.name.as_deref(), Some("Aire du Lac"));
        let mut r = NormalizedRecord::new(PlaceKind::Parking, Position::new(45.9, 6.1).unwrap());
        r.website = Some("https://example.org".into());
        apply(&mut r, &p);
        assert_eq!(r.name.as_deref(), Some("Aire du Lac"));
        assert_eq!(r.overnight, OvernightStatus::Tolerated);
        assert_eq!(
            r.descriptions.get("fr").map(String::as_str),
            Some("Calme la nuit")
        );
        assert_eq!(
            r.website.as_deref(),
            Some("https://example.org"),
            "an absent field says nothing and clears nothing"
        );
    }

    #[test]
    fn out_of_bounds_values_are_refused_by_name() {
        let refuse = |p: PlacePatch| validate_edit(&p).unwrap_err().to_string();
        assert_eq!(
            validate_edit(&PlacePatch::default()),
            Err(SubmissionError::Empty)
        );
        assert!(
            refuse(PlacePatch {
                name: Some("x".into()),
                ..patch()
            })
            .starts_with("name")
        );
        assert!(
            refuse(PlacePatch {
                website: Some("javascript:alert(1)".into()),
                ..patch()
            })
            .starts_with("website")
        );
        assert!(
            refuse(PlacePatch {
                max_height_m: Some(25.0),
                ..patch()
            })
            .starts_with("maxHeightM")
        );
        assert!(
            refuse(PlacePatch {
                price_parking_eur: Some(f64::NAN),
                ..patch()
            })
            .starts_with("priceParkingEur")
        );
        assert!(
            refuse(PlacePatch {
                phone: Some("call me".into()),
                ..patch()
            })
            .starts_with("phone")
        );
        let bad_lang = PlacePatch {
            description: Some(LocalizedDescription {
                lang: "French".into(),
                text: "x".into(),
            }),
            ..patch()
        };
        assert!(refuse(bad_lang).starts_with("description.lang"));
    }

    #[test]
    fn a_new_place_needs_a_name_and_becomes_a_record() {
        let at = Position::new(45.9, 6.1).unwrap();
        let unnamed = NewPlace {
            kind: PlaceKind::Nature,
            position: at,
            details: PlacePatch::default(),
        };
        assert!(validate_new_place(&unnamed).is_err());
        let named = validate_new_place(&NewPlace {
            details: patch(),
            ..unnamed
        })
        .unwrap();
        let r = record_of(&named);
        assert_eq!((r.kind, r.position), (PlaceKind::Nature, at));
        assert_eq!(r.max_height_m, Some(3.1));
    }

    #[test]
    fn an_edit_clears_what_the_community_stated_and_nothing_else() {
        let mut r = NormalizedRecord::new(PlaceKind::Parking, Position::new(45.9, 6.1).unwrap());
        apply(&mut r, &validate_edit(&patch()).unwrap());
        let clearing = validate_edit(&PlacePatch {
            clear: [PlaceField::Phone, PlaceField::Description].into(),
            ..PlacePatch::default()
        })
        .expect("an edit that only clears changes something");
        apply(&mut r, &clearing);
        assert_eq!(r.phone, None, "a wrong phone is removed");
        assert!(r.descriptions.is_empty() && r.description.is_none());
        assert_eq!(
            (r.name.as_deref(), r.max_height_m),
            (Some("Aire du Lac"), Some(3.1)),
            "the fields not named stay"
        );
    }

    #[test]
    fn a_field_is_cleared_in_an_edit_only_and_never_with_a_value() {
        let both = PlacePatch {
            clear: [PlaceField::Phone].into(),
            ..patch()
        };
        assert!(
            validate_edit(&both)
                .unwrap_err()
                .to_string()
                .starts_with("clear")
        );
        let new = NewPlace {
            kind: PlaceKind::Nature,
            position: Position::new(45.9, 6.1).unwrap(),
            details: PlacePatch {
                name: Some("Bord du lac".into()),
                clear: [PlaceField::Website].into(),
                ..PlacePatch::default()
            },
        };
        assert!(validate_new_place(&new).is_err());
    }

    #[test]
    fn a_patch_without_clear_is_stored_as_before() {
        let json = serde_json::to_value(validate_edit(&patch()).unwrap()).unwrap();
        assert!(
            json.get("clear").is_none(),
            "stored revisions of earlier edits must read back unchanged"
        );
        let cleared = PlacePatch {
            clear: [PlaceField::OpeningHours].into(),
            ..PlacePatch::default()
        };
        let json = serde_json::to_value(&cleared).unwrap();
        assert_eq!(json["clear"], serde_json::json!(["opening_hours"]));
        assert_eq!(serde_json::from_value::<PlacePatch>(json).unwrap(), cleared);
    }

    #[test]
    fn the_stored_form_reads_back() {
        let p = validate_edit(&patch()).unwrap();
        let json = serde_json::to_value(&p).unwrap();
        assert_eq!(serde_json::from_value::<PlacePatch>(json).unwrap(), p);
    }
}
