//! OpenStreetMap values as a motorhome reads them, and the rule between two
//! sources of the same limit.
//!
//! French mappers write limits in many forms: `3.5`, `3,5`, `3.5 m`, `3,5 t`,
//! `3500 kg`, `11'6"`. Valhalla 3.9.0 stops at the decimal comma (`3,5`
//! reads 3) and ignores `maxweightrating`, the key the French B13 sign maps
//! to (`plan/research/07-navigation.md`, A.2 and B.1 bis). The graph build
//! rewrites those values with [`canonical`] before Valhalla reads them, and
//! the check after each route reads them with the same parsers, so both see
//! the same limit.

use std::collections::BTreeMap;

use super::restriction::RestrictionKind;

/// What a limit tag says.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum TagValue {
    /// A limit, in metres or tonnes.
    Limit(f64),
    /// `default`: the legal default applies, which is no limit for a road.
    Default,
    /// `below_default`: lower than the standard clearance, figure unknown.
    BelowDefault,
    /// `none` or `no`: no limit.
    NoLimit,
    /// Anything else, or a figure no sign carries (a height of 2900 m, a
    /// weight of 120 t): left for a human.
    Invalid,
}

impl TagValue {
    /// The limit, if the tag gives one.
    #[must_use]
    pub const fn limit(self) -> Option<f64> {
        match self {
            Self::Limit(v) => Some(v),
            _ => None,
        }
    }
}

/// Plausible length limits, metres: below, a sign would stop a bicycle;
/// above, no road needs one.
pub const PLAUSIBLE_LENGTH_M: std::ops::RangeInclusive<f64> = 1.0..=8.0;
/// Plausible vehicle length limits, metres.
pub const PLAUSIBLE_VEHICLE_LENGTH_M: std::ops::RangeInclusive<f64> = 2.0..=50.0;
/// Plausible weight limits, tonnes: values above 44 t (the heaviest legal
/// combination in France) are bridge classes or errors, 1 928 `maxweight=120`
/// in France among them (`plan/research/07-navigation.md`, B.1).
pub const PLAUSIBLE_WEIGHT_T: std::ops::RangeInclusive<f64> = 0.5..=44.0;

/// The leading number of `s` with a dot or a comma as decimal separator,
/// and the rest of the text.
fn leading_number(s: &str) -> Option<(f64, &str)> {
    let end = s
        .char_indices()
        .find(|(_, c)| !(c.is_ascii_digit() || *c == '.' || *c == ','))
        .map_or(s.len(), |(i, _)| i);
    let (digits, rest) = s.split_at(end);
    if digits.is_empty() || digits.matches(['.', ',']).count() > 1 {
        return None;
    }
    if digits.starts_with(['.', ',']) || digits.ends_with(['.', ',']) {
        return None;
    }
    digits
        .replace(',', ".")
        .parse::<f64>()
        .ok()
        .map(|v| (v, rest))
}

fn keyword(s: &str) -> Option<TagValue> {
    match s {
        "default" => Some(TagValue::Default),
        "below_default" => Some(TagValue::BelowDefault),
        "none" | "no" => Some(TagValue::NoLimit),
        _ => None,
    }
}

/// Reads a length (`maxheight`, `maxwidth`, `maxlength`), in metres:
/// metres with or without the unit, centimetres, feet and inches.
#[must_use]
pub fn parse_length(raw: &str) -> TagValue {
    let s = raw.trim().to_ascii_lowercase();
    if let Some(k) = keyword(&s) {
        return k;
    }
    // Feet and inches: 11'6" or 11' 6" or 11'.
    if let Some((feet, rest)) = s.split_once('\'') {
        let Ok(feet) = feet.trim().parse::<u32>() else {
            return TagValue::Invalid;
        };
        let rest = rest.trim();
        let inches = if rest.is_empty() {
            0.0
        } else {
            match rest.strip_suffix('"').map(str::trim).map(str::parse::<f64>) {
                Some(Ok(i)) if (0.0..12.0).contains(&i) => i,
                _ => return TagValue::Invalid,
            }
        };
        return TagValue::Limit(f64::from(feet) * 0.3048 + inches * 0.0254);
    }
    let Some((value, rest)) = leading_number(&s) else {
        return TagValue::Invalid;
    };
    let metres = match rest.trim() {
        "" | "m" => value,
        "cm" => value / 100.0,
        _ => return TagValue::Invalid,
    };
    if metres > 0.0 {
        TagValue::Limit(metres)
    } else {
        TagValue::Invalid
    }
}

/// Reads a weight (`maxweight`, `maxweightrating`, `maxaxleload`), in
/// tonnes: tonnes with or without the unit, kilograms, short tons, pounds.
#[must_use]
pub fn parse_weight(raw: &str) -> TagValue {
    let s = raw.trim().to_ascii_lowercase();
    if let Some(k) = keyword(&s) {
        return k;
    }
    let Some((value, rest)) = leading_number(&s) else {
        return TagValue::Invalid;
    };
    let tonnes = match rest.trim() {
        "" | "t" => value,
        "kg" => value / 1_000.0,
        "st" => value * 0.907_184_74,
        "lbs" => value * 0.000_453_592_37,
        _ => return TagValue::Invalid,
    };
    if tonnes > 0.0 {
        TagValue::Limit(tonnes)
    } else {
        TagValue::Invalid
    }
}

/// `v` unless it is a limit outside `plausible`, which becomes
/// [`TagValue::Invalid`].
#[must_use]
pub fn plausible(v: TagValue, plausible: &std::ops::RangeInclusive<f64>) -> TagValue {
    match v {
        TagValue::Limit(x) if !plausible.contains(&x) => TagValue::Invalid,
        other => other,
    }
}

/// A limit as the graph build writes it: metres or tonnes, a dot, at most
/// two decimals, no trailing zero (`3.5`, `2.7`, `13`). Valhalla reads this
/// form exactly.
#[must_use]
pub fn canonical(value: f64) -> String {
    // Down to the centimetre, never up: a limit rounded up would let a
    // vehicle through that the sign stops. The epsilon keeps 2.9 (stored as
    // 2.8999...) at 2.9.
    let s = format!("{:.2}", (value * 100.0 + 1e-6).floor() / 100.0);
    let s = s.trim_end_matches('0').trim_end_matches('.');
    s.to_owned()
}

/// The keys a motorhome's access is read from, most specific first, after
/// `motorhome` itself: the hierarchy of the OpenStreetMap wiki (Key:access),
/// where `motorhome` and `motorcar` are siblings under `motor_vehicle`, and
/// where `hgv` and `goods` target other vehicles.
const ACCESS_VALUES: [&str; 11] = [
    "yes",
    "no",
    "designated",
    "permissive",
    "destination",
    "private",
    "delivery",
    "customers",
    "permit",
    "discouraged",
    "agricultural",
];

/// The tag changes that make Valhalla's `auto` mode read a way or a node as
/// a motorhome does, given the extra limits another source (IGN) holds for
/// it. Keys to set, with their new value; an empty map changes nothing.
///
/// - Each limit becomes the most restrictive of its keys and of `extra`, in
///   the [`canonical`] form, under the key Valhalla reads (`maxheight`,
///   `maxwidth`, `maxlength`, `maxweight`, `maxaxleload`): `maxweightrating`
///   is copied into `maxweight` this way, and `maxheight:physical` counts.
/// - `motorhome=*` is copied into `motorcar`, which Valhalla's `auto` mode
///   reads first: on this graph the `auto` mode is the motorhome mode
///   (`plan/research/07-navigation.md`, A.4, correction 2, where the same
///   effect was tested by editing Valhalla's tag script).
#[must_use]
pub fn graph_fixes(
    tags: &BTreeMap<String, String>,
    extra: &BTreeMap<RestrictionKind, f64>,
) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    for kind in RestrictionKind::LIMITS {
        let read = read_limit(tags, kind);
        let target = match (read.limit(), extra.get(&kind)) {
            (Some(a), Some(b)) => Some(a.min(*b)),
            (Some(a), None) => Some(a),
            (None, Some(b)) => Some(*b),
            (None, None) => None,
        };
        let Some(target) = target else { continue };
        let key = kind.graph_key();
        let value = canonical(target);
        // Anything but the canonical text is rewritten, so what Valhalla
        // reads never depends on how its parser treats a unit or a comma.
        if tags.get(key).map(String::as_str) != Some(value.as_str()) {
            out.insert(key.to_owned(), value);
        }
    }
    if let Some(v) = tags.get("motorhome").map(|v| v.trim())
        && ACCESS_VALUES.contains(&v)
        && tags.get("motorcar").map(String::as_str) != Some(v)
    {
        out.insert("motorcar".to_owned(), v.to_owned());
    }
    out
}

fn parse_for(kind: RestrictionKind, raw: &str) -> TagValue {
    match kind {
        RestrictionKind::MaxHeight | RestrictionKind::MaxWidth => {
            plausible(parse_length(raw), &PLAUSIBLE_LENGTH_M)
        }
        RestrictionKind::MaxLength => plausible(parse_length(raw), &PLAUSIBLE_VEHICLE_LENGTH_M),
        _ => plausible(parse_weight(raw), &PLAUSIBLE_WEIGHT_T),
    }
}

/// The limit of `kind` on an element: the most restrictive figure among the
/// keys that carry it, or what the main key says when none has a figure.
/// Direction-specific keys (`maxheight:forward`) are left to the router,
/// which reads them.
#[must_use]
pub fn read_limit(tags: &BTreeMap<String, String>, kind: RestrictionKind) -> TagValue {
    let mut best: Option<f64> = None;
    let mut word: Option<TagValue> = None;
    for key in kind.osm_keys() {
        let Some(raw) = tags.get(*key) else { continue };
        match parse_for(kind, raw) {
            TagValue::Limit(v) => best = Some(best.map_or(v, |b| b.min(v))),
            other => {
                if word.is_none() {
                    word = Some(other);
                }
            }
        }
    }
    best.map_or(word.unwrap_or(TagValue::Invalid), TagValue::Limit)
}

/// Whether `tags` hold no key of `kind` at all.
#[must_use]
pub fn has_key(tags: &BTreeMap<String, String>, kind: RestrictionKind) -> bool {
    kind.osm_keys().iter().any(|k| tags.contains_key(*k))
}

/// The tolerance under which two sources agree on a limit: 10 cm for a
/// length (the step of IGN heights is 5 cm), half a tonne for a weight.
#[must_use]
pub const fn tolerance(kind: RestrictionKind) -> f64 {
    match kind {
        RestrictionKind::MaxHeight | RestrictionKind::MaxWidth | RestrictionKind::MaxLength => 0.10,
        _ => 0.5,
    }
}

/// Two sources of one limit, merged.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Merged {
    /// The limit that applies: the lower one.
    pub limit: f64,
    /// Whether it is the second source's.
    pub from_second: bool,
    /// Whether the sources disagree by more than [`tolerance`]: a human
    /// checks which is right (photos, a visit, an OpenStreetMap note).
    pub disputed: bool,
}

/// The most restrictive of two sources. A height too low makes a detour; a
/// height too high sends a vehicle into a bridge; so the lower value wins.
/// A word (`default`, `none`) yields to a figure, since IGN gives a height
/// only where it is below the network's standard; an explicit `none` against
/// a figure is a dispute.
#[must_use]
pub fn merge(kind: RestrictionKind, first: TagValue, second: Option<f64>) -> Option<Merged> {
    match (first, second) {
        (TagValue::Limit(a), Some(b)) => Some(Merged {
            limit: a.min(b),
            from_second: b < a,
            disputed: (a - b).abs() > tolerance(kind) + 1e-9,
        }),
        (TagValue::Limit(a), None) => Some(Merged {
            limit: a,
            from_second: false,
            disputed: false,
        }),
        (word, Some(b)) => Some(Merged {
            limit: b,
            from_second: true,
            disputed: word == TagValue::NoLimit,
        }),
        (_, None) => None,
    }
}

#[cfg(test)]
mod tests {
    use proptest::prelude::*;

    use super::*;

    fn tags(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect()
    }

    #[test]
    fn the_forms_french_mappers_use_read_as_the_sign_says() {
        for (raw, metres) in [
            ("2.7", 2.7),
            ("2,7", 2.7),
            ("2.7 m", 2.7),
            ("2m", 2.0),
            ("1.9 m", 1.9),
            (" 3.50 ", 3.5),
            ("270 cm", 2.7),
            ("11'6\"", 3.5052),
            ("12'", 3.6576),
        ] {
            let v = parse_length(raw).limit().unwrap_or(f64::NAN);
            assert!((v - metres).abs() < 1e-6, "{raw:?} read {v}");
        }
        for (raw, tonnes) in [
            ("3.5", 3.5),
            ("3,5", 3.5),
            ("3,5 t", 3.5),
            ("3500 kg", 3.5),
            ("19t", 19.0),
        ] {
            let v = parse_weight(raw).limit().unwrap_or(f64::NAN);
            assert!(
                (v - tonnes).abs() < 1e-9,
                "{raw:?} read {v}: Valhalla reads 3,5 as 3, the rewrite must not"
            );
        }
        assert_eq!(parse_length("default"), TagValue::Default);
        assert_eq!(parse_length("below_default"), TagValue::BelowDefault);
        assert_eq!(parse_length("none"), TagValue::NoLimit);
        for bad in ["a completer", "", "3.5.1", ",5", "2 ft", "-2"] {
            assert_eq!(parse_length(bad), TagValue::Invalid, "{bad:?}");
        }
        assert_eq!(
            plausible(parse_length("2900 m"), &PLAUSIBLE_LENGTH_M),
            TagValue::Invalid,
            "a figure no sign carries is left for a human"
        );
        assert_eq!(
            plausible(parse_weight("120"), &PLAUSIBLE_WEIGHT_T),
            TagValue::Invalid
        );
    }

    #[test]
    fn canonical_values_are_what_valhalla_reads() {
        assert_eq!(canonical(3.5), "3.5");
        assert_eq!(canonical(13.0), "13");
        assert_eq!(canonical(2.704), "2.7");
        assert_eq!(canonical(3.505_2), "3.5", "11'6\" rounds down, never up");
        assert_eq!(canonical(2.9), "2.9");
        assert_eq!(canonical(0.75), "0.75");
    }

    #[test]
    fn maxweightrating_is_copied_into_maxweight_and_the_lower_wins() {
        // Rue du Pas Redon, Ussel (way 169230141): maxweightrating alone,
        // invisible to Valhalla 3.9.0.
        let fixes = graph_fixes(
            &tags(&[("highway", "residential"), ("maxweightrating", "3.5")]),
            &BTreeMap::new(),
        );
        assert_eq!(fixes.get("maxweight").map(String::as_str), Some("3.5"));
        let both = graph_fixes(
            &tags(&[("maxweight", "7.5"), ("maxweightrating", "3,5")]),
            &BTreeMap::new(),
        );
        assert_eq!(both.get("maxweight").map(String::as_str), Some("3.5"));
        let comma = graph_fixes(&tags(&[("maxweight", "3,5")]), &BTreeMap::new());
        assert_eq!(
            comma.get("maxweight").map(String::as_str),
            Some("3.5"),
            "a decimal comma is rewritten"
        );
        assert!(
            graph_fixes(
                &tags(&[("maxweight", "3.5"), ("maxheight", "2.7")]),
                &BTreeMap::new()
            )
            .is_empty(),
            "canonical values are left alone"
        );
    }

    #[test]
    fn the_physical_height_and_an_ign_height_count_and_the_lowest_wins() {
        let fixes = graph_fixes(
            &tags(&[("maxheight", "default"), ("maxheight:physical", "3.2")]),
            &BTreeMap::new(),
        );
        assert_eq!(fixes.get("maxheight").map(String::as_str), Some("3.2"));
        let ign = BTreeMap::from([(RestrictionKind::MaxHeight, 3.4)]);
        // Rue Braille, Limoges: a passage IGN gives at 3.4 m, nothing in OSM.
        let fixes = graph_fixes(
            &tags(&[("highway", "residential"), ("tunnel", "building_passage")]),
            &ign,
        );
        assert_eq!(fixes.get("maxheight").map(String::as_str), Some("3.4"));
        // Rue Maurice Utrillo: OSM 2.7, IGN 3.1; the lower stays.
        let ign = BTreeMap::from([(RestrictionKind::MaxHeight, 3.1)]);
        assert!(graph_fixes(&tags(&[("maxheight", "2.7")]), &ign).is_empty());
    }

    #[test]
    fn motorhome_access_becomes_the_auto_mode_s_access() {
        // Route de Grandchamp (way 103140897): motorhome=no, used by the
        // stock auto mode.
        let fixes = graph_fixes(
            &tags(&[("highway", "unclassified"), ("motorhome", "no")]),
            &BTreeMap::new(),
        );
        assert_eq!(fixes.get("motorcar").map(String::as_str), Some("no"));
        let allowed = graph_fixes(
            &tags(&[("motor_vehicle", "no"), ("motorhome", "yes")]),
            &BTreeMap::new(),
        );
        assert_eq!(allowed.get("motorcar").map(String::as_str), Some("yes"));
        assert!(
            graph_fixes(&tags(&[("hgv", "no"), ("goods", "no")]), &BTreeMap::new()).is_empty(),
            "a B8 sign does not concern a motorhome"
        );
        assert!(graph_fixes(&tags(&[("motorhome", "no;yes")]), &BTreeMap::new()).is_empty());
    }

    #[test]
    fn the_lower_source_wins_and_a_gap_over_ten_centimetres_is_disputed() {
        let h = RestrictionKind::MaxHeight;
        let m = merge(h, TagValue::Limit(2.7), Some(3.1)).unwrap();
        assert!((m.limit - 2.7).abs() < 1e-9 && !m.from_second && m.disputed);
        let close = merge(h, TagValue::Limit(3.0), Some(3.1)).unwrap();
        assert!(!close.disputed, "10 cm is within the tolerance");
        let ign_lower = merge(h, TagValue::Limit(3.9), Some(3.8)).unwrap();
        assert!(ign_lower.from_second && (ign_lower.limit - 3.8).abs() < 1e-9);
        let word = merge(h, TagValue::Default, Some(3.0)).unwrap();
        assert!(word.from_second && !word.disputed);
        assert!(merge(h, TagValue::NoLimit, Some(3.0)).unwrap().disputed);
        assert_eq!(merge(h, TagValue::Default, None), None);
    }

    proptest! {
        #[test]
        fn a_canonical_value_reads_back_as_itself(cm in 50u32..5_000) {
            let v = f64::from(cm) / 100.0;
            let text = canonical(v);
            prop_assert_eq!(parse_length(&text), TagValue::Limit(text.parse::<f64>().unwrap()));
            prop_assert!((parse_weight(&text).limit().unwrap() - v).abs() < 0.005);
            prop_assert!(!text.contains(','));
        }

        #[test]
        fn parsing_never_panics(s in ".{0,20}") {
            let _ = parse_length(&s);
            let _ = parse_weight(&s);
        }
    }
}
