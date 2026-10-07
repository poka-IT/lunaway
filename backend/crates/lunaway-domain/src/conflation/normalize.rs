//! Normalisation of the values the conflation compares: names, phone numbers,
//! websites, Wikidata items.
//!
//! The app runs the same rules on the device (`schema/conflation-vectors.json`
//! carries test cases for each), so every rule here is spelled so that it can
//! be reimplemented without this crate: no locale tables, no regex flavour.

use unicode_normalization::{UnicodeNormalization, char::is_combining_mark};

/// Words that say what kind of spot a place is rather than which one it is.
/// They are dropped before names are compared, so "Aire de camping-car du Lac"
/// and "Camping du Lac" both reduce to "lac" and the kind matrix, not the
/// name, decides whether a motorhome area and a campsite can be one spot.
/// Folded forms (lower case, no accents); French first, with the common
/// English, German, Dutch and Italian equivalents.
pub const GENERIC_WORDS: &[&str] = &[
    // articles, prepositions and conjunctions
    "a",
    "au",
    "aux",
    "d",
    "de",
    "des",
    "du",
    "en",
    "et",
    "l",
    "la",
    "le",
    "les",
    "sur",
    "sous",
    "and",
    "of",
    "the",
    // the German, Spanish and Italian ones, which a community's names
    // abroad are written with (measured in `tests/extcom_synthetic.rs`)
    "am",
    "an",
    "auf",
    "bei",
    "beim",
    "das",
    "dem",
    "den",
    "der",
    "die",
    "im",
    "in",
    "und",
    "zum",
    "zur",
    "al",
    "del",
    "el",
    "las",
    "los",
    "y",
    "da",
    "dei",
    "della",
    "delle",
    "dello",
    "di",
    "il",
    // what the place is
    "aire",
    "aires",
    "area",
    "camp",
    "camper",
    "campers",
    "camperplaats",
    "camping",
    "campings",
    "campingcar",
    "campingcars",
    "car",
    "cars",
    "caravan",
    "caravane",
    "caravanes",
    "caravaning",
    "cc",
    "motorhome",
    "motorhomes",
    "parking",
    "parkings",
    "site",
    "sosta",
    "stationnement",
    "stellplatz",
    "aparcamiento",
    "autocaravana",
    "autocaravanas",
    "campeggio",
    "campingplatz",
    "parcheggio",
    "parkplatz",
    "wohnmobil",
    "wohnmobile",
    "wohnmobilstellplatz",
    // who runs it and what it offers, not which one it is
    "accueil",
    "communal",
    "communale",
    "municipal",
    "municipale",
    "municipaux",
    "naturel",
    "naturelle",
    "service",
    "services",
];

/// Abbreviations expanded before comparison, so "St-Malo" meets "Saint-Malo".
pub const ABBREVIATIONS: &[(&str, &str)] = &[("st", "saint"), ("ste", "sainte")];

/// Letters that canonical decomposition leaves whole, mapped to the ASCII a
/// French or European keyboard would type for them.
pub const LIGATURES: &[(char, &str)] = &[
    ('æ', "ae"),
    ('Æ', "ae"),
    ('œ', "oe"),
    ('Œ', "oe"),
    ('ß', "ss"),
    // The capital lowers to `ß`, after this table is read: without its own
    // entry a second fold would expand what the first one left.
    ('ẞ', "ss"),
    ('ø', "o"),
    ('Ø', "o"),
    ('đ', "d"),
    ('Đ', "d"),
    ('ł', "l"),
    ('Ł', "l"),
    ('ı', "i"),
];

/// Folds `s` for comparison: compatibility decomposition (NFKD), combining
/// marks dropped (accents), ligatures expanded, lower case, every character
/// that is neither a letter nor a digit turned into a space, spaces collapsed.
///
/// `fold("L'Île-d'Yeu  (Port)") == "l ile d yeu port"`.
#[must_use]
pub fn fold(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut pending_space = false;
    for c in s.nfkd() {
        if is_combining_mark(c) {
            continue;
        }
        let expanded = LIGATURES.iter().find(|(l, _)| *l == c).map(|(_, r)| *r);
        let mut push = |c: char| {
            if c.is_alphanumeric() {
                if pending_space && !out.is_empty() {
                    out.push(' ');
                }
                pending_space = false;
                out.extend(c.to_lowercase());
            } else {
                pending_space = true;
            }
        };
        match expanded {
            Some(r) => r.chars().for_each(&mut push),
            None => push(c),
        }
    }
    out
}

/// The identifying words of an already folded name: abbreviations expanded,
/// generic words removed, order kept.
#[must_use]
pub fn core_tokens(folded: &str) -> Vec<&str> {
    folded
        .split(' ')
        .filter(|t| !t.is_empty())
        .map(|t| {
            ABBREVIATIONS
                .iter()
                .find(|(short, _)| *short == t)
                .map_or(t, |(_, long)| *long)
        })
        .filter(|t| !GENERIC_WORDS.contains(t))
        .collect()
}

/// The normalised name: folded, abbreviations expanded, generic words
/// removed. Empty when the name is only generic words ("Camping municipal").
#[must_use]
pub fn normalize_name(raw: &str) -> String {
    core_tokens(&fold(raw)).join(" ")
}

/// A phone number reduced to `+<country><number>`, or `None` when fewer than
/// eight digits remain. Only the first number of a list (`;`, `,` or `/`) is
/// kept. A ten-digit number starting with 0 is read as French, the only
/// national format the sources of the MVP use.
#[must_use]
pub fn normalize_phone(raw: &str) -> Option<String> {
    let first = raw.split([';', ',', '/']).next().unwrap_or_default().trim();
    let plus = first.starts_with('+');
    let mut digits: String = first.chars().filter(char::is_ascii_digit).collect();
    let international = if plus {
        true
    } else if let Some(rest) = digits.strip_prefix("00") {
        digits = rest.to_owned();
        true
    } else {
        false
    };
    let normalised = if international {
        // "+33 (0)1 23 ..." keeps a trunk zero that dialling drops.
        if let Some(rest) = digits.strip_prefix("330") {
            format!("+33{rest}")
        } else {
            format!("+{digits}")
        }
    } else if digits.len() == 10 && digits.starts_with('0') {
        format!("+33{}", &digits[1..])
    } else {
        return None;
    };
    (normalised.len() > 8).then_some(normalised)
}

/// Hosts that serve pages for many unrelated places: their bare address says
/// nothing about which place it is.
pub const PLATFORM_HOSTS: &[&str] = &[
    "facebook.com",
    "fb.com",
    "instagram.com",
    "google.com",
    "sites.google.com",
    "booking.com",
    "airbnb.fr",
    "airbnb.com",
    "tripadvisor.fr",
    "tripadvisor.com",
];

/// A website reduced to `host/path`: scheme, `www.`, query, fragment and
/// trailing slash removed, lower case. `None` when it has no dotted host, or
/// when it is the bare address of a platform hosting many places.
#[must_use]
pub fn normalize_website(raw: &str) -> Option<String> {
    let first = raw.split([';', ' ']).find(|s| !s.is_empty())?.trim();
    let lower = first.to_lowercase();
    let no_scheme = lower
        .strip_prefix("https://")
        .or_else(|| lower.strip_prefix("http://"))
        .unwrap_or(&lower);
    let no_www = no_scheme.strip_prefix("www.").unwrap_or(no_scheme);
    let end = no_www.find(['?', '#']).unwrap_or(no_www.len());
    let trimmed = no_www[..end].trim_end_matches('/');
    let (host, path) = trimmed.split_once('/').unwrap_or((trimmed, ""));
    if !host.contains('.') || host.starts_with('.') || host.ends_with('.') {
        return None;
    }
    if path.is_empty() && PLATFORM_HOSTS.contains(&host) {
        return None;
    }
    Some(trimmed.to_owned())
}

/// A Wikidata item id (`Q42`), upper-cased, or `None` when it is not one.
#[must_use]
pub fn normalize_wikidata(raw: &str) -> Option<String> {
    let t = raw.trim();
    let digits = t.strip_prefix('Q').or_else(|| t.strip_prefix('q'))?;
    (!digits.is_empty() && digits.bytes().all(|b| b.is_ascii_digit())).then(|| format!("Q{digits}"))
}

#[cfg(test)]
mod tests {
    use proptest::prelude::*;

    use super::*;

    #[test]
    fn fold_removes_accents_case_and_punctuation() {
        assert_eq!(fold("L'Île-d'Yeu  (Port)"), "l ile d yeu port");
        assert_eq!(fold("MÛRS-ERIGNÉ"), "murs erigne");
        assert_eq!(
            fold("Œuvre ÆSOP Straße Øresund Łódź"),
            "oeuvre aesop strasse oresund lodz"
        );
        assert_eq!(
            fold("GROẞE STRAẞE"),
            "grosse strasse",
            "the capital sharp s folds like the small one, in one pass"
        );
        assert_eq!(fold("  ** Camping ***  "), "camping");
        assert_eq!(
            fold("ﬁlet"),
            "filet",
            "compatibility decomposition splits the fi ligature"
        );
        assert_eq!(fold(""), "");
    }

    #[test]
    fn generic_words_and_abbreviations_are_normalised_away() {
        assert_eq!(normalize_name("Aire de camping-car du Lac"), "lac");
        assert_eq!(normalize_name("Camping du Lac"), "lac");
        assert_eq!(
            normalize_name("AGIS - CAMPING DES VARENNES"),
            "agis varennes"
        );
        assert_eq!(normalize_name("Parking St-Malo"), "saint malo");
        assert_eq!(normalize_name("Camping municipal"), "");
        assert_eq!(
            normalize_name("Aire naturelle de camping à la ferme"),
            "ferme",
            "\"a\" is the folded \"à\" and goes with the other prepositions"
        );
    }

    #[test]
    fn generic_words_are_folded_forms() {
        for w in GENERIC_WORDS {
            assert_eq!(
                &fold(w),
                w,
                "a generic word that is not folded can never match"
            );
        }
        for (short, long) in ABBREVIATIONS {
            assert_eq!(&fold(short), short);
            assert_eq!(&fold(long), long);
        }
    }

    #[test]
    fn phones_reduce_to_one_international_form() {
        let want = Some("+33241000000".to_owned());
        assert_eq!(normalize_phone("02 41 00 00 00"), want);
        assert_eq!(normalize_phone("+33 2 41 00 00 00"), want);
        assert_eq!(normalize_phone("+33 (0)2 41 00 00 00"), want);
        assert_eq!(normalize_phone("0033 2.41.00.00.00"), want);
        assert_eq!(
            normalize_phone("+33 2 41 00 00 00; +33 6 00 00 00 00"),
            want
        );
        assert_eq!(
            normalize_phone("+49 30 1234567"),
            Some("+49301234567".into())
        );
        assert_eq!(
            normalize_phone("12 34"),
            None,
            "too short to identify anything"
        );
        assert_eq!(
            normalize_phone("41 00 00 00"),
            None,
            "a national number of 8 digits is ambiguous"
        );
        assert_eq!(normalize_phone(""), None);
    }

    #[test]
    fn websites_reduce_to_host_and_path() {
        let want = Some("camping-varennes.com".to_owned());
        assert_eq!(normalize_website("http://www.camping-varennes.com"), want);
        assert_eq!(normalize_website("https://www.Camping-Varennes.com/"), want);
        assert_eq!(
            normalize_website("camping-varennes.com/?utm_source=x#top"),
            want
        );
        assert_eq!(
            normalize_website("https://example.org/campings/12/"),
            Some("example.org/campings/12".into())
        );
        assert_eq!(normalize_website("https://www.facebook.com/"), None);
        assert_eq!(
            normalize_website("https://facebook.com/campingdulac"),
            Some("facebook.com/campingdulac".into()),
            "a page on a platform does identify one place"
        );
        assert_eq!(normalize_website("-"), None);
        assert_eq!(normalize_website(""), None);
    }

    #[test]
    fn wikidata_ids_are_validated() {
        assert_eq!(normalize_wikidata(" q42 "), Some("Q42".into()));
        assert_eq!(normalize_wikidata("Q"), None);
        assert_eq!(normalize_wikidata("Q12a"), None);
        assert_eq!(normalize_wikidata("42"), None);
    }

    proptest! {
        #[test]
        fn fold_is_idempotent_and_canonical(s in "\\PC{0,40}") {
            let once = fold(&s);
            prop_assert_eq!(&fold(&once), &once);
            prop_assert!(!once.starts_with(' ') && !once.ends_with(' ') && !once.contains("  "));
            prop_assert!(once.chars().all(|c| c == ' ' || c.is_alphanumeric()));
        }

        #[test]
        fn normalize_name_is_idempotent(s in "\\PC{0,40}") {
            let once = normalize_name(&s);
            prop_assert_eq!(normalize_name(&once), once);
        }

        #[test]
        fn normalisers_never_panic(s in "\\PC{0,60}") {
            let _ = normalize_phone(&s);
            let _ = normalize_website(&s);
            let _ = normalize_wikidata(&s);
        }
    }
}
