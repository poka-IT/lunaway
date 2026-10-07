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
//!
//! A limit may spare local access ("sauf desserte"):
//! `maxweight:conditional=none @ destination`. Valhalla 3.9.0 honours four
//! texts of it, byte for byte, on the key it reads, and takes "sauf
//! livraisons" (`none @ delivery`) for one too. The graph build writes the
//! exception a motorhome may use in the one form Valhalla reads, under the
//! key it reads, and removes the one it may not use
//! (`plan/research/61-limites-urbaines.md`).

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

/// The exception for local access as the graph build writes it: the form
/// Valhalla 3.9.0 reads (`conditional_access_restriction` in
/// `lua/graph.lua`, which marks the limit `except_destination`).
pub const LOCAL_ACCESS: &str = "none @ destination";

/// The texts Valhalla 3.9.0 takes for an exception for local access, byte
/// for byte (`conditional_access_restriction` in `lua/graph.lua`). "Sauf
/// livraisons" is among them: it lets a delivery in, never a motorhome.
const VALHALLA_LOCAL_ACCESS: [&str; 4] = [
    "none @ destination",
    "none @ delivery",
    "no @ destination",
    "none @ (destination)",
];

/// The conditional keys of one direction's limit that Valhalla 3.9.0 reads
/// an exception on (`access_restriction_tags` in `lua/graph.lua`, the
/// directed ones).
const DIRECTED_CONDITIONALS: [(RestrictionKind, &str); 8] = [
    (RestrictionKind::MaxHeight, "maxheight:forward:conditional"),
    (RestrictionKind::MaxHeight, "maxheight:backward:conditional"),
    (RestrictionKind::MaxWidth, "maxwidth:forward:conditional"),
    (RestrictionKind::MaxWidth, "maxwidth:backward:conditional"),
    (RestrictionKind::MaxLength, "maxlength:forward:conditional"),
    (RestrictionKind::MaxLength, "maxlength:backward:conditional"),
    (RestrictionKind::MaxWeight, "maxweight:forward:conditional"),
    (RestrictionKind::MaxWeight, "maxweight:backward:conditional"),
];

/// Two figures closer than this, tonnes or metres, are one sign mapped
/// under two keys (`maxweight` and `maxweightrating` copied from each
/// other).
const SAME_FIGURE: f64 = 0.01;

/// Changes to an element's tags: the new value of a key, or `None` to
/// remove it.
pub type TagFixes = BTreeMap<String, Option<String>>;

/// Applies `fixes` to `tags`.
pub fn apply_fixes(tags: &mut BTreeMap<String, String>, fixes: TagFixes) {
    for (key, value) in fixes {
        match value {
            Some(v) => {
                tags.insert(key, v);
            }
            None => {
                tags.remove(&key);
            }
        }
    }
}

/// `s` cut at each `sep` outside parentheses.
fn split_outside_parentheses(s: &str, sep: char) -> Vec<&str> {
    let mut parts = Vec::new();
    let mut depth = 0_i32;
    let mut start = 0;
    for (i, c) in s.char_indices() {
        match c {
            '(' => depth += 1,
            ')' => depth -= 1,
            c if c == sep && depth == 0 => {
                parts.push(&s[start..i]);
                start = i + c.len_utf8();
            }
            _ => {}
        }
    }
    parts.push(&s[start..]);
    parts
}

/// Whether a `*:conditional` value lifts the limit for the traffic going
/// to a place beyond it: a rule `none @ destination` (or `no`), the
/// condition alone or among alternatives (`none @ (delivery; destination)`,
/// `none @ (destination OR delivery)`, `none@destination`). A condition
/// joined to another by `AND`, a time, a figure instead of `none`, or a
/// delivery alone lift nothing for a motorhome: the limit stays whole.
#[must_use]
pub fn spares_local_access(raw: &str) -> bool {
    split_outside_parentheses(raw, ';').into_iter().any(|rule| {
        let Some((value, condition)) = rule.split_once('@') else {
            return false;
        };
        let value = value.trim().to_ascii_lowercase();
        if value != "none" && value != "no" {
            return false;
        }
        let condition = condition.trim();
        let condition = condition
            .strip_prefix('(')
            .and_then(|c| c.strip_suffix(')'))
            .unwrap_or(condition)
            .to_ascii_lowercase();
        if condition.split_whitespace().any(|w| w == "and") {
            return false;
        }
        condition
            .split([',', ';'])
            .flat_map(|part| part.split(" or "))
            .any(|item| item.trim() == "destination")
    })
}

/// Whether the limit of `kind` on an element spares local access. Every
/// key that carries a figure must have the exception, its own or that of
/// the other key when both carry the same figure (one sign mapped twice);
/// with one figure, the exception on either key counts. A figure without
/// it is a sign without the plate, and the limit stays whole. A measured
/// figure (`maxwidth:physical`) is a structure: nothing lifts it, and a
/// plate on its conditional key is not read.
#[must_use]
pub fn limit_spares_local_access(tags: &BTreeMap<String, String>, kind: RestrictionKind) -> bool {
    if !kind.spares_local_access() {
        return false;
    }
    let physical = |key: &str| key.ends_with(":physical");
    let mut figures: Vec<(usize, f64)> = Vec::new();
    for (i, key) in kind.osm_keys().iter().enumerate() {
        let Some(figure) = tags.get(*key).and_then(|raw| parse_for(kind, raw).limit()) else {
            continue;
        };
        if physical(key) {
            return false;
        }
        figures.push((i, figure));
    }
    let spared: Vec<bool> = kind
        .osm_keys()
        .iter()
        .zip(kind.conditional_keys())
        .map(|(key, conditional)| {
            !physical(key)
                && tags
                    .get(*conditional)
                    .is_some_and(|v| spares_local_access(v))
        })
        .collect();
    match figures.as_slice() {
        [] => false,
        [_] => spared.contains(&true),
        many => many.iter().all(|(i, v)| {
            spared.get(*i).copied().unwrap_or(false)
                || many.iter().any(|(j, w)| {
                    j != i
                        && spared.get(*j).copied().unwrap_or(false)
                        && (v - w).abs() < SAME_FIGURE
                })
        }),
    }
}

/// Whether the limit of `kind` on an element spares local access once
/// another source's figure `extra` for it is known: a figure lower than
/// the mapped one beyond [`tolerance`] is another limit, without the plate.
/// A higher one leaves the plate: the router knows one figure per road,
/// and the check after each route still applies the other source's.
#[must_use]
pub fn spares_local_access_with(
    tags: &BTreeMap<String, String>,
    kind: RestrictionKind,
    extra: Option<f64>,
) -> bool {
    limit_spares_local_access(tags, kind)
        && match (read_limit(tags, kind).limit(), extra) {
            (Some(mapped), Some(other)) => other >= mapped - tolerance(kind),
            _ => true,
        }
}

/// The tag changes that make Valhalla's `auto` mode read a way or a node as
/// a motorhome does, given the extra limits another source (IGN) holds for
/// it. An empty map changes nothing.
///
/// - Each limit becomes the most restrictive of its keys and of `extra`, in
///   the [`canonical`] form, under the key Valhalla reads (`maxheight`,
///   `maxwidth`, `maxlength`, `maxweight`, `maxaxleload`): `maxweightrating`
///   is copied into `maxweight` this way, and `maxheight:physical` counts.
/// - The exception for local access a motorhome may use
///   ([`limit_spares_local_access`]) is written as [`LOCAL_ACCESS`] under
///   the conditional key Valhalla reads (`maxweight:conditional`), so that
///   a "sauf desserte" mapped on `maxweightrating:conditional` alone, or in
///   a form Valhalla does not know, still lets a trip start or end inside.
///   An `extra` figure lower than the mapped one beyond [`tolerance`] is
///   another limit, without the plate: the exception goes. One Valhalla
///   would read and a motorhome may not use (`none @ delivery`, or any on a
///   clearance) is removed.
/// - `motorhome=*` is copied into `motorcar`, which Valhalla's `auto` mode
///   reads first: on this graph the `auto` mode is the motorhome mode
///   (`plan/research/07-navigation.md`, A.4, correction 2, where the same
///   effect was tested by editing Valhalla's tag script).
#[must_use]
pub fn graph_fixes(
    tags: &BTreeMap<String, String>,
    extra: &BTreeMap<RestrictionKind, f64>,
) -> TagFixes {
    let mut out = TagFixes::new();
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
            out.insert(key.to_owned(), Some(value));
        }
        let Some(conditional) = kind.conditional_keys().first() else {
            continue;
        };
        let spared = spares_local_access_with(tags, kind, extra.get(&kind).copied());
        let current = tags.get(*conditional).map(String::as_str);
        let valhalla_spares = current.is_some_and(|c| VALHALLA_LOCAL_ACCESS.contains(&c));
        if spared {
            if !(valhalla_spares && current.is_some_and(spares_local_access)) {
                out.insert((*conditional).to_owned(), Some(LOCAL_ACCESS.to_owned()));
            }
        } else if valhalla_spares {
            out.insert((*conditional).to_owned(), None);
        }
    }
    // Valhalla also reads the exception on one direction's limit
    // (`maxweight:forward:conditional`, `lua/graph.lua`). Those limits are
    // left to the router, so only an exception a motorhome may not use goes.
    for (kind, key) in DIRECTED_CONDITIONALS {
        let Some(current) = tags.get(key) else {
            continue;
        };
        if VALHALLA_LOCAL_ACCESS.contains(&current.as_str())
            && !(kind.spares_local_access() && spares_local_access(current))
        {
            out.insert(key.to_owned(), None);
        }
    }
    if let Some(v) = tags.get("motorhome").map(|v| v.trim())
        && ACCESS_VALUES.contains(&v)
        && tags.get("motorcar").map(String::as_str) != Some(v)
    {
        out.insert("motorcar".to_owned(), Some(v.to_owned()));
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

    /// The value `fixes` sets for `key`, if it sets one.
    fn set<'a>(fixes: &'a TagFixes, key: &str) -> Option<&'a str> {
        fixes.get(key).and_then(|v| v.as_deref())
    }

    /// The tags Valhalla reads once `fixes` are applied.
    fn fixed(
        pairs: &[(&str, &str)],
        extra: &BTreeMap<RestrictionKind, f64>,
    ) -> BTreeMap<String, String> {
        let mut t = tags(pairs);
        let fixes = graph_fixes(&t, extra);
        apply_fixes(&mut t, fixes);
        t
    }

    #[test]
    fn local_access_reads_in_the_forms_mappers_use() {
        // Values counted on French ways by taginfo (Geofabrik, 2026-10-06),
        // `plan/research/61-limites-urbaines.md`.
        for raw in [
            "none @ destination",
            "no @ destination",
            "none@destination",
            "none @ (destination)",
            "None @ Destination",
            "none @ (destination; delivery)",
            "none @ (delivery, destination)",
            "none @ (delivery OR destination)",
            "none @ (service, destination)",
            "none @ destination; none @ agricultural",
            "none @ (agricultural, destination, psv)",
        ] {
            assert!(spares_local_access(raw), "{raw:?} spares local access");
        }
        for raw in [
            "none @ delivery",
            "none @ (delivery)",
            "none @ (delivery AND destination)",
            "none @ (destination AND agricultural)",
            "7.5 @ destination",
            "3.5 @ delivery",
            "yes @ destination",
            "none @ residents",
            "none @ 20:00-12:00",
            "no @ destination 06:00-11:00",
            "none @ (Apr-Nov); none @ (destination AND Dec-Mar)",
            "destination",
            "",
        ] {
            assert!(
                !spares_local_access(raw),
                "{raw:?} lets a delivery or another vehicle in, never a motorhome going to a campsite"
            );
        }
    }

    #[test]
    fn a_sauf_desserte_on_the_rating_reaches_the_key_valhalla_reads() {
        // The French B13 is mapped with maxweightrating since 2025; a "sauf
        // desserte" plate then sits on maxweightrating:conditional, which
        // Valhalla never reads: without the copy, the whole street was closed
        // to a 3.8 t motorhome, its own campsite included.
        let t = fixed(
            &[
                ("highway", "residential"),
                ("maxweightrating", "3.5"),
                ("maxweightrating:conditional", "none @ destination"),
            ],
            &BTreeMap::new(),
        );
        assert_eq!(t.get("maxweight").map(String::as_str), Some("3.5"));
        assert_eq!(
            t.get("maxweight:conditional").map(String::as_str),
            Some(LOCAL_ACCESS)
        );
        // A form Valhalla does not know is written in the one it knows.
        let t = fixed(
            &[
                ("maxweight", "3.5"),
                ("maxweight:conditional", "none @ (delivery, destination)"),
            ],
            &BTreeMap::new(),
        );
        assert_eq!(
            t.get("maxweight:conditional").map(String::as_str),
            Some(LOCAL_ACCESS)
        );
        // One sign mapped under both keys, the plate on one of them.
        let t = fixed(
            &[
                ("maxweight", "3.5"),
                ("maxweightrating", "3,5"),
                ("maxweightrating:conditional", "no @ destination"),
            ],
            &BTreeMap::new(),
        );
        assert_eq!(
            t.get("maxweight:conditional").map(String::as_str),
            Some(LOCAL_ACCESS)
        );
        assert!(
            graph_fixes(
                &tags(&[
                    ("maxweight", "3.5"),
                    ("maxweight:conditional", "none @ destination")
                ]),
                &BTreeMap::new()
            )
            .is_empty(),
            "what Valhalla already reads is left alone"
        );
    }

    #[test]
    fn an_exception_a_motorhome_may_not_use_leaves_the_graph() {
        // "Sauf livraisons": Valhalla 3.9.0 takes it for local access.
        let t = fixed(
            &[
                ("maxweight", "3.5"),
                ("maxweight:conditional", "none @ delivery"),
            ],
            &BTreeMap::new(),
        );
        assert_eq!(t.get("maxweight").map(String::as_str), Some("3.5"));
        assert!(
            !t.contains_key("maxweight:conditional"),
            "a delivery plate keeps a motorhome out: {t:?}"
        );
        // A clearance is a structure: no plate lifts it.
        let t = fixed(
            &[
                ("maxheight", "2.7"),
                ("maxheight:conditional", "none @ delivery"),
            ],
            &BTreeMap::new(),
        );
        assert!(!t.contains_key("maxheight:conditional"), "{t:?}");
        assert!(!limit_spares_local_access(
            &tags(&[
                ("maxheight", "2.7"),
                ("maxheight:conditional", "none @ destination")
            ]),
            RestrictionKind::MaxHeight
        ));
        // Two signs: 7.5 t without a plate, 3.5 t with one. The vehicle
        // between them is spared by one and not by the other: the limit
        // stays whole, as the stricter reading of the two.
        let two_signs = tags(&[
            ("maxweight", "7.5"),
            ("maxweightrating", "3.5"),
            ("maxweightrating:conditional", "none @ destination"),
        ]);
        assert!(!limit_spares_local_access(
            &two_signs,
            RestrictionKind::MaxWeight
        ));
        let t = fixed(
            &[
                ("maxweight", "7.5"),
                ("maxweightrating", "3.5"),
                ("maxweightrating:conditional", "none @ destination"),
            ],
            &BTreeMap::new(),
        );
        assert_eq!(t.get("maxweight").map(String::as_str), Some("3.5"));
        assert!(!t.contains_key("maxweight:conditional"));
    }

    #[test]
    fn a_measured_width_is_a_structure_no_plate_lifts() {
        // Valhalla falls back on maxwidth:physical and would read the plate
        // with it: a 2.3 m motorhome would be sent through a 2.0 m gap at a
        // stop. The physical figure keeps the limit whole.
        for pairs in [
            &[
                ("maxwidth:physical", "2.0"),
                ("maxwidth:conditional", "none @ destination"),
            ][..],
            &[
                ("maxwidth:physical", "2.0"),
                ("maxwidth:physical:conditional", "none @ destination"),
            ][..],
            &[
                ("maxwidth", "2.0"),
                ("maxwidth:physical", "2.0"),
                ("maxwidth:conditional", "none @ destination"),
            ][..],
            &[
                ("maxwidth", "2.0"),
                ("maxwidth:physical", "2.0"),
                ("maxwidth:physical:conditional", "none @ destination"),
            ][..],
        ] {
            assert!(
                !limit_spares_local_access(&tags(pairs), RestrictionKind::MaxWidth),
                "{pairs:?}"
            );
            let t = fixed(pairs, &BTreeMap::new());
            assert_eq!(
                t.get("maxwidth").map(String::as_str),
                Some("2"),
                "{pairs:?}"
            );
            assert!(
                !t.contains_key("maxwidth:conditional"),
                "Valhalla must not read the plate on a measured width: {t:?}"
            );
        }
        // A width sign alone, with its plate, is a traffic order.
        assert!(limit_spares_local_access(
            &tags(&[
                ("maxwidth", "2.0"),
                ("maxwidth:conditional", "none @ destination")
            ]),
            RestrictionKind::MaxWidth
        ));
    }

    #[test]
    fn a_delivery_plate_on_one_direction_leaves_the_graph_too() {
        let t = fixed(
            &[
                ("maxweight:backward", "3.5"),
                ("maxweight:backward:conditional", "none @ delivery"),
                ("maxheight:forward", "2.5"),
                ("maxheight:forward:conditional", "none @ delivery"),
            ],
            &BTreeMap::new(),
        );
        assert!(!t.contains_key("maxweight:backward:conditional"), "{t:?}");
        assert!(!t.contains_key("maxheight:forward:conditional"), "{t:?}");
        assert_eq!(
            t.get("maxweight:backward").map(String::as_str),
            Some("3.5"),
            "the directional limit itself is the router's"
        );
        let kept = tags(&[
            ("maxweight:forward", "3.5"),
            ("maxweight:forward:conditional", "none @ destination"),
        ]);
        assert!(
            graph_fixes(&kept, &BTreeMap::new()).is_empty(),
            "a local access plate on one direction stays as Valhalla reads it"
        );
    }

    #[test]
    fn a_lower_figure_from_ign_is_another_limit_without_the_plate() {
        let desserte = [
            ("maxweight", "3.5"),
            ("maxweight:conditional", "none @ destination"),
        ];
        let same = BTreeMap::from([(RestrictionKind::MaxWeight, 3.5)]);
        let t = fixed(&desserte, &same);
        assert_eq!(
            t.get("maxweight:conditional").map(String::as_str),
            Some(LOCAL_ACCESS),
            "IGN's figure for the same sign keeps the plate"
        );
        let lower = BTreeMap::from([(RestrictionKind::MaxWeight, 2.0)]);
        let t = fixed(&desserte, &lower);
        assert_eq!(t.get("maxweight").map(String::as_str), Some("2"));
        assert!(
            !t.contains_key("maxweight:conditional"),
            "a 2 t bridge IGN measures is not lifted by a 3.5 t zone's plate: {t:?}"
        );
    }

    #[test]
    fn weight_limits_for_goods_vehicles_never_reach_the_graph() {
        // B8 with a tonnage plate (IISR 4th part, art. 57) concerns goods
        // vehicles only; the French wiki maps it with the :hgv and :goods
        // suffixes. A motorhome is not a goods vehicle.
        for pairs in [
            &[("highway", "residential"), ("maxweight:hgv", "3.5")][..],
            &[("highway", "residential"), ("maxweightrating:hgv", "3.5")][..],
            &[("highway", "residential"), ("maxweightrating:goods", "3.5")][..],
            &[
                ("highway", "residential"),
                ("hgv:conditional", "no @ (weight>3.5)"),
            ][..],
            &[
                ("highway", "residential"),
                ("maxweight:hgv", "7.5"),
                ("maxweight:hgv:conditional", "none @ destination"),
            ][..],
        ] {
            let t = tags(pairs);
            assert!(
                graph_fixes(&t, &BTreeMap::new()).is_empty(),
                "{pairs:?} changes nothing a motorhome reads"
            );
            assert!(!has_key(&t, RestrictionKind::MaxWeight), "{pairs:?}");
        }
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
        assert_eq!(set(&fixes, "maxweight"), Some("3.5"));
        let both = graph_fixes(
            &tags(&[("maxweight", "7.5"), ("maxweightrating", "3,5")]),
            &BTreeMap::new(),
        );
        assert_eq!(set(&both, "maxweight"), Some("3.5"));
        let comma = graph_fixes(&tags(&[("maxweight", "3,5")]), &BTreeMap::new());
        assert_eq!(
            set(&comma, "maxweight"),
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
        assert_eq!(set(&fixes, "maxheight"), Some("3.2"));
        let ign = BTreeMap::from([(RestrictionKind::MaxHeight, 3.4)]);
        // Rue Braille, Limoges: a passage IGN gives at 3.4 m, nothing in OSM.
        let fixes = graph_fixes(
            &tags(&[("highway", "residential"), ("tunnel", "building_passage")]),
            &ign,
        );
        assert_eq!(set(&fixes, "maxheight"), Some("3.4"));
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
        assert_eq!(set(&fixes, "motorcar"), Some("no"));
        let allowed = graph_fixes(
            &tags(&[("motor_vehicle", "no"), ("motorhome", "yes")]),
            &BTreeMap::new(),
        );
        assert_eq!(set(&allowed, "motorcar"), Some("yes"));
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

        #[test]
        fn local_access_needs_a_none_rule_whose_condition_admits_destination_alone(
            rules in prop::collection::vec(
                (
                    prop::sample::select(vec!["none", "no", "3.5", "yes", "None"]),
                    prop::collection::vec(
                        prop::sample::select(vec![
                            "destination", "delivery", "agricultural", "psv", "08:00-18:00",
                        ]),
                        1..4,
                    ),
                    prop::sample::select(vec![", ", "; ", " OR ", " AND "]),
                    any::<bool>(),
                ),
                1..3,
            )
        ) {
            let text: Vec<String> = rules
                .iter()
                .map(|(value, items, join, wrap)| {
                    let condition = items.join(join);
                    if *wrap {
                        format!("{value} @ ({condition})")
                    } else {
                        format!("{value} @ {condition}")
                    }
                })
                .collect();
            let raw = text.join("; ");
            // What the rules say, read without the parser under test: a
            // rule with no figure whose condition lists destination among
            // alternatives. A semicolon outside parentheses ends a rule, so
            // an unwrapped "; " list is cut there.
            let expected = rules.iter().any(|(value, items, join, wrap)| {
                let free = value.eq_ignore_ascii_case("none") || value.eq_ignore_ascii_case("no");
                let first_only = !*wrap && *join == "; ";
                let alternatives = if first_only { &items[..1] } else { &items[..] };
                let and = *join == " AND " && alternatives.len() > 1;
                free && !and && alternatives.contains(&"destination")
            });
            prop_assert_eq!(spares_local_access(&raw), expected, "{}", raw);
        }

        #[test]
        fn a_conditional_never_panics(s in ".{0,40}") {
            let _ = spares_local_access(&s);
        }
    }
}
