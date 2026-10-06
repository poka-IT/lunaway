//! Automatic rules on contributed text: links, contact details, repetition,
//! a word list. A text that trips one is held for a moderator.
//!
//! The rules hold a text back rather than refuse it, so they lean towards
//! flagging: a false alarm costs a moderator a glance, a missed spam costs
//! every reader. They still leave alone what reviews of a motorhome spot are
//! full of: prices, heights ("2,80 m"), dates, years, postcodes, opening
//! hours ("8h-20h") and GPS coordinates.

use std::{fmt, str::FromStr, sync::OnceLock};

use serde::{Deserialize, Serialize};

use crate::{UnknownCode, conflation::normalize::fold, taxonomy::coded_enum};

coded_enum! {
    /// Why the automatic rules hold a text.
    TextFlag {
        /// A web address.
        Link => "link",
        /// An e-mail address or a phone number.
        ContactDetails => "contact",
        /// Characters, words or a short chunk repeated over and over.
        Repetition => "repetition",
        /// A word of the insult and slur list.
        BannedWord => "word",
    }
}

/// Top-level domains a link in a review would use. Two-letter ones that are
/// common words after a missing space ("propre.De plus", "great.It") are
/// left out: `de`, `es`, `it`, `to`, `me`, `us`, `at`, `be`, `in`, `is`,
/// `on`, `no`, `so`, `do`, `my`, `by`, `as`.
const TLDS: &[&str] = &[
    "com", "fr", "net", "org", "io", "eu", "ch", "nl", "uk", "info", "biz", "app", "ly", "gl",
    "xyz", "site", "online", "shop", "top", "club", "page", "tv", "pt", "lu", "ca", "ru", "bzh",
    "paris", "corsica", "alsace", "camp", "travel",
];

/// Mail providers named in a spelt-out address ("jean arobase gmail").
const MAIL_PROVIDERS: &[&str] = &[
    "gmail",
    "hotmail",
    "yahoo",
    "outlook",
    "orange",
    "free",
    "wanadoo",
    "laposte",
    "sfr",
    "icloud",
    "protonmail",
    "proton",
];

/// Consecutive identical characters that count as repetition.
const CHAR_RUN: usize = 7;
/// Consecutive identical words that count as repetition.
const WORD_RUN: usize = 4;

/// The flags `text` trips, sorted and without duplicates; empty when it may
/// be published as it is.
#[must_use]
pub fn check_text(text: &str) -> Vec<TextFlag> {
    let lower = deobfuscate(&text.to_lowercase());
    let folded = fold(text);
    let words: Vec<&str> = folded.split(' ').filter(|w| !w.is_empty()).collect();
    let mut flags = Vec::new();
    if has_link(&lower, &words) {
        flags.push(TextFlag::Link);
    }
    if has_email(&lower, &words) || has_phone(text) {
        flags.push(TextFlag::ContactDetails);
    }
    if has_repetition(text, &words) {
        flags.push(TextFlag::Repetition);
    }
    if contains_banned_word(text) {
        flags.push(TextFlag::BannedWord);
    }
    flags
}

/// Undoes the usual ways of writing a dot or an at sign so a filter
/// misses them: `[.]`, `(dot)`, `[at]`.
fn deobfuscate(lower: &str) -> String {
    let mut s = lower.to_owned();
    for (from, to) in [
        ("[.]", "."),
        ("(.)", "."),
        ("{.}", "."),
        ("[dot]", "."),
        ("(dot)", "."),
        ("{dot}", "."),
        ("[at]", "@"),
        ("(at)", "@"),
        ("{at}", "@"),
    ] {
        s = s.replace(from, to);
    }
    s
}

/// The tokens of `lower`, split on whitespace, without the punctuation
/// that surrounds a word in a sentence.
fn tokens(lower: &str) -> impl Iterator<Item = &str> {
    lower.split_whitespace().map(|t| {
        t.trim_matches(|c: char| {
            matches!(
                c,
                '(' | ')'
                    | '['
                    | ']'
                    | '{'
                    | '}'
                    | '<'
                    | '>'
                    | '"'
                    | '\''
                    | ','
                    | ';'
                    | ':'
                    | '!'
                    | '?'
                    | '.'
                    | '«'
                    | '»'
            )
        })
    })
}

/// Whether `host` looks like a domain name: two labels or more of ASCII
/// letters, digits and hyphens, the last one a known top-level domain, the
/// one before it holding a letter.
fn is_domain(host: &str) -> bool {
    let labels: Vec<&str> = host.split('.').collect();
    let [.., second, tld] = labels.as_slice() else {
        return false;
    };
    labels.iter().all(|l| {
        !l.is_empty()
            && l.bytes()
                .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
    }) && TLDS.contains(tld)
        && second.bytes().any(|b| b.is_ascii_lowercase())
}

fn has_link(lower: &str, words: &[&str]) -> bool {
    let explicit = tokens(lower).any(|t| {
        if t.contains("://") || t.starts_with("www.") {
            return true;
        }
        if t.contains('@') {
            return false;
        }
        let host = t.split(['/', '?', '#']).next().unwrap_or_default();
        let host = host.split(':').next().unwrap_or_default();
        is_domain(host)
    });
    // "monsite point com", "my site dot fr".
    let spelt = words
        .windows(3)
        .any(|w| matches!(w[1], "point" | "dot") && TLDS.contains(&w[2]));
    explicit || spelt
}

fn has_email(lower: &str, words: &[&str]) -> bool {
    let explicit = tokens(lower).any(|t| {
        t.split_once('@')
            .is_some_and(|(local, host)| !local.is_empty() && is_domain(host.trim_end_matches('.')))
    });
    // "jean at site dot com", "jean arobase gmail".
    let spelt = words.windows(4).any(|w| {
        matches!(w[0], "at" | "arobase") && matches!(w[2], "dot" | "point") && TLDS.contains(&w[3])
    }) || words
        .windows(2)
        .any(|w| matches!(w[0], "at" | "arobase") && MAIL_PROVIDERS.contains(&w[1]));
    explicit || spelt
}

/// Characters allowed between the digits of a phone number.
fn is_phone_separator(c: char) -> bool {
    matches!(c, ' ' | '.' | '-' | '/' | '(' | ')')
}

/// Whether `text` holds a phone number. Digits separated by at most two of
/// `space . - / ( )` form a run of digit groups; the run is a phone number
/// when it starts with `+` and holds 8 digits or more, starts with `00` and
/// holds 10 to 15, or holds a French number: 10 digits starting with `0`
/// then a non-zero digit, written in one group or in groups of two
/// ("06 12 34 56 78"). Two numbers in a row still show the second one. A
/// comma ends a run, so coordinates ("45.8992, 6.1294") and prices do not
/// read as one; dates, years and postcodes have too few digits or groups of
/// other sizes.
fn has_phone(text: &str) -> bool {
    let chars: Vec<char> = text.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        let plus = chars[i] == '+';
        let mut first = if plus { i + 1 } else { i };
        // "+ 33" as well as "+33".
        if plus && chars.get(first) == Some(&' ') {
            first += 1;
        }
        if !chars.get(first).is_some_and(char::is_ascii_digit) {
            i += 1;
            continue;
        }
        let (groups, end) = digit_groups(&chars, first);
        if is_phone(plus, &groups) {
            return true;
        }
        i = end.max(i + 1);
    }
    false
}

/// The digit groups of the run starting at `start` (a digit), and the index
/// after it.
fn digit_groups(chars: &[char], start: usize) -> (Vec<String>, usize) {
    let mut groups = vec![String::new()];
    let mut j = start;
    loop {
        match chars.get(j) {
            Some(c) if c.is_ascii_digit() => {
                if let Some(g) = groups.last_mut() {
                    g.push(*c);
                }
                j += 1;
            }
            Some(c) if is_phone_separator(*c) => {
                let mut k = j;
                while k < chars.len() && k - j < 3 && is_phone_separator(chars[k]) {
                    k += 1;
                }
                if k - j <= 2 && chars.get(k).is_some_and(char::is_ascii_digit) {
                    groups.push(String::new());
                    j = k;
                } else {
                    break;
                }
            }
            _ => break,
        }
    }
    (groups, j)
}

fn is_phone(plus: bool, groups: &[String]) -> bool {
    let total: usize = groups.iter().map(String::len).sum();
    if plus && total >= 8 {
        return true;
    }
    if groups.first().is_some_and(|g| g.starts_with("00")) && (10..=15).contains(&total) {
        return true;
    }
    let french = |digits: &str| {
        digits.len() == 10 && digits.starts_with('0') && !digits[1..].starts_with('0')
    };
    (0..groups.len()).any(|s| {
        if french(&groups[s]) {
            return true;
        }
        // Five groups of two digits.
        groups
            .get(s..s + 5)
            .is_some_and(|w| w.iter().all(|g| g.len() == 2) && french(&w.concat()))
    })
}

fn has_repetition(text: &str, words: &[&str]) -> bool {
    // One character over and over: "!!!!!!!", "trooooooop".
    let mut run = 0;
    let mut previous = None;
    for c in text.chars().flat_map(char::to_lowercase) {
        if c.is_whitespace() {
            previous = None;
            run = 0;
            continue;
        }
        run = if previous == Some(c) { run + 1 } else { 1 };
        previous = Some(c);
        if run >= CHAR_RUN {
            return true;
        }
    }
    // One word over and over: "super super super super".
    if words
        .windows(WORD_RUN)
        .any(|w| w.iter().all(|x| *x == w[0]))
    {
        return true;
    }
    // One longer word making up most of the text.
    if words.len() >= 8 {
        let mut counts: std::collections::HashMap<&str, usize> = std::collections::HashMap::new();
        for w in words.iter().filter(|w| w.chars().count() >= 4) {
            *counts.entry(*w).or_default() += 1;
        }
        let top = counts.values().copied().max().unwrap_or(0);
        if top >= 5 && top * 5 > words.len() * 2 {
            return true;
        }
    }
    is_periodic(text)
}

/// Whether `text`, spaces aside, is mostly one short chunk repeated
/// ("abcabcabcabc"): natural text agrees with itself shifted by a few
/// characters about one time in twelve, a repeated chunk nine times in ten.
fn is_periodic(text: &str) -> bool {
    let chars: Vec<char> = text
        .chars()
        .filter(|c| !c.is_whitespace())
        .flat_map(char::to_lowercase)
        .collect();
    let n = chars.len();
    if n < 20 {
        return false;
    }
    (1..=12).filter(|k| n >= 3 * k).any(|k| {
        let same = chars
            .iter()
            .zip(&chars[k..])
            .filter(|(a, b)| a == b)
            .count();
        same * 10 >= (n - k) * 9
    })
}

/// The banned entries, each as its folded words.
fn banned() -> &'static [Vec<String>] {
    static BANNED: OnceLock<Vec<Vec<String>>> = OnceLock::new();
    BANNED.get_or_init(|| {
        include_str!("../../words/banned.txt")
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty() && !l.starts_with('#'))
            .map(|l| fold(l).split(' ').map(str::to_owned).collect())
            .collect()
    })
}

/// Whether `text` holds a word (or a sequence of words) of the insult and
/// slur list, compared as whole folded words: "Bitche" (Moselle) is not
/// "bitch", "Puteaux" is not "pute".
#[must_use]
pub fn contains_banned_word(text: &str) -> bool {
    let folded = fold(text);
    let words: Vec<&str> = folded.split(' ').filter(|w| !w.is_empty()).collect();
    banned().iter().any(|entry| {
        !entry.is_empty()
            && words
                .windows(entry.len())
                .any(|w| w.iter().zip(entry).all(|(a, b)| *a == b))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn flags(text: &str) -> Vec<TextFlag> {
        check_text(text)
    }

    #[test]
    fn an_ordinary_review_passes() {
        for text in [
            "Super aire, calme la nuit. Vidange 2 €, eau 10 min pour 2 €. Hauteur max 2,80 m.",
            "Ouvert de 8h-20h du 01/04 au 30/09, 12,50 € la nuit en 2024.",
            "Parking au 74000 Annecy, à 300 m du lac. GPS 45.899212, 6.129412.",
            "Coordonnées : N 45.8992 E 6.1294, sortie A41 puis D1508.",
            "Très très bien, on reviendra en 2025 et 2026 ! Merci...",
            "Great spot, quiet at night. Dump station works, water 2 euros.",
            "We stayed 3 nights (2023-07-12 to 2023-07-15) with our 7.5 m motorhome.",
            "Le camping de Condom, l'aire de Bitche et Montcuq, puis Puteaux et Scunthorpe.",
            "Un retard de 10 minutes, du pain bâtard, un raton laveur et une tapette à mouches.",
            "Café con leche et vino negro à Twatt, dans les Orcades.",
            "Fermé du 01/02/2024-03/02/2024, réouverture le 04.03.2024.",
            "Prix 2019 2020 2021 2022 : 8 10 12 15 euros.",
        ] {
            assert_eq!(flags(text), [], "{text}");
        }
    }

    #[test]
    fn links_are_held() {
        for text in [
            "Voir https://example.org/aire pour les tarifs",
            "infos sur www.mon-aire.fr",
            "réservez sur camping-du-lac.fr/reservation",
            "allez sur bit.ly/abc",
            "tout est sur monsite point com",
            "see my-site[.]com",
        ] {
            assert_eq!(flags(text), [TextFlag::Link], "{text}");
        }
    }

    #[test]
    fn contact_details_are_held() {
        for text in [
            "écrivez à jean.dupont@example.fr",
            "mail: jean[at]example.com",
            "jean arobase gmail",
            "contact jean at example dot com",
            "appelez le 06 12 34 56 78",
            "appelez le 06.12.34.56.78 ou le 0612345678",
            "tel +33 6 12 34 56 78",
            "tel +33 (0)6 12 34 56 78",
            "call 0044 20 7946 0958",
            "+49 30 1234567",
            "le 0612345678 0698765432",
            "emplacements 12 34 06 12 34 56 78",
        ] {
            let got = flags(text);
            assert!(got.contains(&TextFlag::ContactDetails), "{text}: {got:?}");
        }
    }

    #[test]
    fn repetition_is_held() {
        for text in [
            "Génial !!!!!!!!!!",
            "trooooooooop bien",
            "super super super super endroit",
            "camping camping camping camping camping bien camping camping",
            "abcabcabcabcabcabcabcabc",
            "lol lol lol lol lol lol",
        ] {
            assert!(
                flags(text).contains(&TextFlag::Repetition),
                "{text}: {:?}",
                flags(text)
            );
        }
        assert_eq!(
            flags("Le camping est propre, le camping est calme, et le camping est bien placé."),
            [],
            "a word said three times in a sentence is not spam"
        );
    }

    #[test]
    fn banned_words_match_whole_folded_words() {
        assert!(contains_banned_word("Quel CONNARD ce gérant"));
        assert!(contains_banned_word("espèce d'enculé"), "accents fold away");
        assert!(
            contains_banned_word("fils-de-pute"),
            "punctuation splits words"
        );
        assert!(contains_banned_word("you asshole"));
        assert!(!contains_banned_word("Bitche"));
        assert!(!contains_banned_word("Condom, Gers"));
        assert!(!contains_banned_word("Montcuq"));
        assert!(!contains_banned_word("Puteaux"));
        assert!(!contains_banned_word("Scunthorpe"));
        assert!(!contains_banned_word("sale"), "only the slur phrase");
        assert_eq!(flags("salope"), [TextFlag::BannedWord]);
    }

    #[test]
    fn every_banned_entry_is_folded_and_matches_itself() {
        for entry in banned() {
            let text = entry.join(" ");
            assert_eq!(
                fold(&text),
                text,
                "write entries folded, or they never match: {text}"
            );
            assert!(contains_banned_word(&text), "{text}");
        }
        assert!(banned().len() > 50);
    }

    #[test]
    fn flags_come_sorted_and_once() {
        let got = flags("www.a.fr www.b.fr 0612345678 0698765432 connard !!!!!!!!");
        assert_eq!(
            got,
            [
                TextFlag::Link,
                TextFlag::ContactDetails,
                TextFlag::Repetition,
                TextFlag::BannedWord
            ]
        );
        assert_eq!(TextFlag::ContactDetails.code(), "contact");
        assert_eq!(TextFlag::BannedWord.code(), "word");
    }
}
