//! The pseudonym an account starts with: an animal, an adjective and a
//! place of French nature, in the language of the app that asked ("Hérisson
//! curieux du Vercors", "Curious Hedgehog of the Vercors", "Neugieriger
//! Igel vom Vercors", "Erizo curioso del Vercors", "Riccio curioso del
//! Vercors", "Nieuwsgierige egel uit de Vercors"). The user may change it.
//!
//! The words are data files in `words/`, one entry per line, `#` for
//! comments. Where the adjective agrees with the animal (French, German,
//! Spanish, Italian), animals carry their gender and adjectives a form for
//! each; places carry their preposition and article.

use std::sync::OnceLock;

use crate::{AuthError, random};

/// Longest generated pseudonym, in characters: the longest name a user may
/// choose, so a generated name always passes the same validation.
pub const MAX_GENERATED_CHARS: usize = 32;

/// The language of a generated pseudonym: the app's six.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Locale {
    /// French.
    Fr,
    /// English.
    En,
    /// German.
    De,
    /// Spanish.
    Es,
    /// Italian.
    It,
    /// Dutch.
    Nl,
}

impl Locale {
    /// Every locale, for the tests of the word lists.
    #[cfg(test)]
    const ALL: [Self; 6] = [Self::Fr, Self::En, Self::De, Self::Es, Self::It, Self::Nl];

    /// The locale a client names (`en`, `en-GB`, `fr-FR`, `de`): French for
    /// a `fr` tag or none, French being the app's first language; each of
    /// the app's other languages for its own tag; English for any other.
    #[must_use]
    pub fn parse(tag: &str) -> Self {
        let tag = tag.trim().to_ascii_lowercase();
        match tag.split(['-', '_']).next().unwrap_or_default() {
            "" | "fr" => Self::Fr,
            "de" => Self::De,
            "es" => Self::Es,
            "it" => Self::It,
            "nl" => Self::Nl,
            _ => Self::En,
        }
    }
}

/// The grammatical gender of an animal, which its adjective agrees with.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Gender {
    Masculine,
    Feminine,
    Neuter,
}

impl Gender {
    /// The column of its form in an adjective's line.
    const fn index(self) -> usize {
        match self {
            Self::Masculine => 0,
            Self::Feminine => 1,
            Self::Neuter => 2,
        }
    }
}

/// How a language writes its lists and orders a name.
struct Grammar {
    /// The genders an animal's line names (`Igel|m`); none where the
    /// adjective has one form (English, and Dutch, whose animals are all
    /// of the same gender).
    genders: &'static [(&'static str, Gender)],
    /// Whether the adjective comes before the animal ("Curious Hedgehog")
    /// or after it ("Hérisson curieux").
    adjective_first: bool,
}

const MF: &[(&str, Gender)] = &[("m", Gender::Masculine), ("f", Gender::Feminine)];
const MFN: &[(&str, Gender)] = &[
    ("m", Gender::Masculine),
    ("f", Gender::Feminine),
    ("n", Gender::Neuter),
];

/// The parsed word lists of one language.
#[derive(Debug)]
struct Lexicon {
    animals: Vec<(&'static str, Gender)>,
    /// Each adjective in the masculine, feminine and neuter, the same form
    /// repeated where the language has fewer.
    adjectives: Vec<[&'static str; 3]>,
    places: Vec<&'static str>,
    adjective_first: bool,
}

/// The entries of a word file: non-empty lines that are not comments.
fn entries(file: &'static str) -> impl Iterator<Item = &'static str> {
    file.lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
}

impl Lexicon {
    /// Reads the three files of a language. A line without its gender or
    /// with the wrong number of forms is skipped, and the tests check that
    /// none is.
    fn read(
        grammar: &Grammar,
        animals: &'static str,
        adjectives: &'static str,
        places: &'static str,
    ) -> Self {
        let forms = grammar.genders.len().max(1);
        Self {
            animals: entries(animals)
                .filter_map(|line| {
                    if grammar.genders.is_empty() {
                        return Some((line, Gender::Masculine));
                    }
                    let (name, gender) = line.split_once('|')?;
                    let (_, gender) = grammar.genders.iter().find(|(g, _)| *g == gender)?;
                    Some((name, *gender))
                })
                .collect(),
            adjectives: entries(adjectives)
                .filter_map(|line| {
                    let f: Vec<&str> = line.split('|').collect();
                    match (forms, f.as_slice()) {
                        (1, &[one]) => Some([one, one, one]),
                        (2, &[m, f]) => Some([m, f, m]),
                        (3, &[m, f, n]) => Some([m, f, n]),
                        _ => None,
                    }
                })
                .collect(),
            places: entries(places).collect(),
            adjective_first: grammar.adjective_first,
        }
    }

    /// The name of these three words, the adjective agreeing.
    fn name(&self, animal: (&str, Gender), adjective: [&str; 3], place: &str) -> String {
        let (animal, gender) = animal;
        let adjective = adjective[gender.index()];
        if self.adjective_first {
            format!("{adjective} {animal} {place}")
        } else {
            format!("{animal} {adjective} {place}")
        }
    }
}

/// The word lists of the six languages.
#[derive(Debug)]
struct Lexicons([Lexicon; 6]);

impl Lexicons {
    fn of(&self, locale: Locale) -> &Lexicon {
        let [fr, en, de, es, it, nl] = &self.0;
        match locale {
            Locale::Fr => fr,
            Locale::En => en,
            Locale::De => de,
            Locale::Es => es,
            Locale::It => it,
            Locale::Nl => nl,
        }
    }
}

macro_rules! lexicon {
    ($grammar:expr, $code:literal) => {
        Lexicon::read(
            &$grammar,
            include_str!(concat!("../words/", $code, "-animals.txt")),
            include_str!(concat!("../words/", $code, "-adjectives.txt")),
            include_str!(concat!("../words/", $code, "-places.txt")),
        )
    };
}

fn lexicon(locale: Locale) -> &'static Lexicon {
    static WORDS: OnceLock<Lexicons> = OnceLock::new();
    WORDS
        .get_or_init(|| {
            let after = Grammar {
                genders: MF,
                adjective_first: false,
            };
            let before = Grammar {
                genders: &[],
                adjective_first: true,
            };
            Lexicons([
                lexicon!(after, "fr"),
                lexicon!(before, "en"),
                lexicon!(
                    Grammar {
                        genders: MFN,
                        adjective_first: true,
                    },
                    "de"
                ),
                lexicon!(after, "es"),
                lexicon!(after, "it"),
                lexicon!(before, "nl"),
            ])
        })
        .of(locale)
}

/// A uniformly chosen entry of `list`. The modulo bias of a 64-bit draw
/// over a list of fifty is below one in 10^17.
fn pick<T: Copy>(list: &[T]) -> Result<T, AuthError> {
    let len = u64::try_from(list.len()).unwrap_or(u64::MAX);
    if len == 0 {
        return Err(AuthError::EmptyWordList);
    }
    let mut bytes = [0u8; 8];
    random(&mut bytes)?;
    let index = usize::try_from(u64::from_le_bytes(bytes) % len).unwrap_or(0);
    list.get(index).copied().ok_or(AuthError::EmptyWordList)
}

/// A fresh pseudonym in `locale`, at most [`MAX_GENERATED_CHARS`]
/// characters.
///
/// # Errors
///
/// [`AuthError::Random`] when the system cannot supply random bytes.
pub fn generate_pseudonym(locale: Locale) -> Result<String, AuthError> {
    let w = lexicon(locale);
    Ok(w.name(pick(&w.animals)?, pick(&w.adjectives)?, pick(&w.places)?))
}

#[cfg(test)]
mod tests {
    use lunaway_domain::community::{moderation::contains_banned_word, pseudonym};

    use super::*;

    /// The names that put every pair of words side by side, in every
    /// language: each pair of lists in full, the third word fixed, and the
    /// adjective in each of its forms. A banned phrase or a forbidden
    /// character across a word boundary shows up in one of them; the full
    /// product (about 130 000 names a language) takes half a minute in a
    /// debug build.
    fn every_pair(w: &Lexicon) -> Vec<String> {
        let mut out = Vec::new();
        let (adjective, place) = (w.adjectives[0], w.places[0]);
        for &an in &w.animals {
            for &ad in &w.adjectives {
                out.push(w.name(an, ad, place));
            }
            for pl in &w.places {
                out.push(w.name(an, adjective, pl));
            }
        }
        // One animal of each gender, so every form of each adjective meets
        // every place.
        let mut genders: Vec<(&str, Gender)> = Vec::new();
        for &an in &w.animals {
            if !genders.iter().any(|(_, g)| *g == an.1) {
                genders.push(an);
            }
        }
        for &ad in &w.adjectives {
            for pl in &w.places {
                for &an in &genders {
                    out.push(w.name(an, ad, pl));
                }
            }
        }
        out
    }

    fn longest<'a>(words: impl IntoIterator<Item = &'a str>) -> usize {
        words
            .into_iter()
            .map(|x| x.chars().count())
            .max()
            .unwrap_or(0)
    }

    /// The three files of a language, as written.
    fn files(locale: Locale) -> [&'static str; 3] {
        macro_rules! of {
            ($code:literal) => {
                [
                    include_str!(concat!("../words/", $code, "-animals.txt")),
                    include_str!(concat!("../words/", $code, "-adjectives.txt")),
                    include_str!(concat!("../words/", $code, "-places.txt")),
                ]
            };
        }
        match locale {
            Locale::Fr => of!("fr"),
            Locale::En => of!("en"),
            Locale::De => of!("de"),
            Locale::Es => of!("es"),
            Locale::It => of!("it"),
            Locale::Nl => of!("nl"),
        }
    }

    #[test]
    fn every_line_of_the_lists_is_read() {
        for locale in Locale::ALL {
            let w = lexicon(locale);
            let [animals, adjectives, places] = files(locale).map(|f| entries(f).count());
            assert_eq!(
                w.animals.len(),
                animals,
                "{locale:?}: every animal needs its gender where the adjective agrees"
            );
            assert_eq!(
                w.adjectives.len(),
                adjectives,
                "{locale:?}: every adjective needs a form for each gender"
            );
            assert_eq!(w.places.len(), places);
            for list in [w.animals.len(), w.adjectives.len(), w.places.len()] {
                assert!(
                    list >= 40,
                    "{locale:?}: a list this short makes names repeat"
                );
            }
        }
    }

    #[test]
    fn no_word_is_listed_twice() {
        for locale in Locale::ALL {
            for file in files(locale) {
                let mut seen = std::collections::HashSet::new();
                for line in entries(file) {
                    assert!(seen.insert(line), "{locale:?}: {line} twice");
                }
            }
        }
    }

    #[test]
    fn every_combination_fits_and_passes_the_rules_of_a_chosen_name() {
        for locale in Locale::ALL {
            let w = lexicon(locale);
            let most = longest(w.animals.iter().map(|a| a.0))
                + longest(w.adjectives.iter().flatten().copied())
                + longest(w.places.iter().copied())
                + 2;
            assert!(
                most <= MAX_GENERATED_CHARS,
                "{locale:?}: the longest words together make {most} characters"
            );
            for name in every_pair(w) {
                assert_eq!(
                    pseudonym::normalize_pseudonym(&name).as_deref(),
                    Ok(name.as_str()),
                    "a generated name must pass the rules a chosen one passes"
                );
                assert!(!contains_banned_word(&name), "{name}");
            }
        }
    }

    #[test]
    fn the_adjective_agrees_with_the_animal() {
        let fr = lexicon(Locale::Fr);
        let curious = ["curieux", "curieuse", "curieux"];
        assert_eq!(
            fr.name(("Chouette", Gender::Feminine), curious, "du Vercors"),
            "Chouette curieuse du Vercors"
        );
        assert_eq!(
            fr.name(("Hérisson", Gender::Masculine), curious, "du Vercors"),
            "Hérisson curieux du Vercors"
        );
        let de = lexicon(Locale::De);
        let neugierig = ["Neugieriger", "Neugierige", "Neugieriges"];
        assert_eq!(
            de.name(("Igel", Gender::Masculine), neugierig, "vom Jura"),
            "Neugieriger Igel vom Jura"
        );
        assert_eq!(
            de.name(("Eule", Gender::Feminine), neugierig, "der Loire"),
            "Neugierige Eule der Loire"
        );
        assert_eq!(
            de.name(("Reh", Gender::Neuter), neugierig, "von Korsika"),
            "Neugieriges Reh von Korsika"
        );
        let es = lexicon(Locale::Es);
        assert_eq!(
            es.name(
                ("Lechuza", Gender::Feminine),
                ["curioso", "curiosa", "curioso"],
                "del Jura"
            ),
            "Lechuza curiosa del Jura"
        );
        let it = lexicon(Locale::It);
        assert_eq!(
            it.name(
                ("Lontra", Gender::Feminine),
                ["curioso", "curiosa", "curioso"],
                "della Loira"
            ),
            "Lontra curiosa della Loira"
        );
        let nl = lexicon(Locale::Nl);
        let vrolijke = ["Vrolijke"; 3];
        assert_eq!(
            nl.name(("egel", Gender::Masculine), vrolijke, "uit de Vercors"),
            "Vrolijke egel uit de Vercors"
        );
        let en = lexicon(Locale::En);
        assert_eq!(
            en.name(
                ("Hedgehog", Gender::Masculine),
                ["Curious"; 3],
                "of the Vercors"
            ),
            "Curious Hedgehog of the Vercors"
        );
    }

    #[test]
    fn a_line_reads_into_the_forms_of_its_language() {
        let one = |grammar: &Grammar, animal: &'static str, adjective: &'static str, place| {
            let w = Lexicon::read(grammar, animal, adjective, place);
            w.name(w.animals[0], w.adjectives[0], w.places[0])
        };
        let after = Grammar {
            genders: MF,
            adjective_first: false,
        };
        assert_eq!(
            one(&after, "Loutre|f", "curieux|curieuse", "du Jura"),
            "Loutre curieuse du Jura"
        );
        assert_eq!(
            one(&after, "Renard|m", "curieux|curieuse", "du Jura"),
            "Renard curieux du Jura"
        );
        let german = Grammar {
            genders: MFN,
            adjective_first: true,
        };
        for (animal, name) in [
            ("Igel|m", "Neugieriger Igel vom Jura"),
            ("Eule|f", "Neugierige Eule vom Jura"),
            ("Reh|n", "Neugieriges Reh vom Jura"),
        ] {
            assert_eq!(
                one(
                    &german,
                    animal,
                    "Neugieriger|Neugierige|Neugieriges",
                    "vom Jura"
                ),
                name
            );
        }
        let before = Grammar {
            genders: &[],
            adjective_first: true,
        };
        assert_eq!(
            one(&before, "egel", "Vrolijke", "uit de Jura"),
            "Vrolijke egel uit de Jura"
        );
        // A line without its gender or its forms is left out, which the
        // count of every list catches.
        let w = Lexicon::read(&after, "Loutre\nRenard|x", "curieux", "du Jura");
        assert!(w.animals.is_empty() && w.adjectives.is_empty());
    }

    #[test]
    fn the_german_lists_name_three_genders() {
        let de = lexicon(Locale::De);
        for gender in [Gender::Masculine, Gender::Feminine, Gender::Neuter] {
            assert!(
                de.animals.iter().any(|a| a.1 == gender),
                "{gender:?}: each form of the adjectives is used"
            );
        }
        assert!(
            de.adjectives.iter().all(|[m, f, n]| m != f && f != n),
            "a German adjective has three forms"
        );
    }

    #[test]
    fn each_language_draws_from_its_own_lists() {
        for locale in Locale::ALL {
            let w = lexicon(locale);
            let name = generate_pseudonym(locale).unwrap();
            assert!(
                w.places.iter().any(|p| name.ends_with(&format!(" {p}"))),
                "{locale:?}: {name}"
            );
            assert!(
                w.animals
                    .iter()
                    .any(|a| name.contains(&format!("{} ", a.0))
                        || name.contains(&format!(" {} ", a.0))),
                "{locale:?}: {name}"
            );
        }
    }

    #[test]
    fn a_tag_names_its_language() {
        for (tag, locale) in [
            ("fr-FR", Locale::Fr),
            ("", Locale::Fr),
            ("en-GB", Locale::En),
            ("EN", Locale::En),
            ("de", Locale::De),
            ("de-AT", Locale::De),
            ("es-ES", Locale::Es),
            ("it", Locale::It),
            ("nl_BE", Locale::Nl),
            ("pt-BR", Locale::En),
        ] {
            assert_eq!(
                Locale::parse(tag),
                locale,
                "{tag}: each of the app's languages gets its own words, any other English ones"
            );
        }
    }
}
