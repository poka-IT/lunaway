//! The pseudonym an account starts with: an animal, an adjective and a
//! place of French nature, in the user's language ("Hérisson curieux du
//! Vercors", "Curious Hedgehog of the Vercors"). The user may change it.
//!
//! The words are data files in `words/`, one entry per line, `#` for
//! comments. French animals carry their gender and adjectives both forms,
//! so the adjective agrees; places carry their article.

use std::sync::OnceLock;

use crate::{AuthError, random};

/// Longest generated pseudonym, in characters: the longest name a user may
/// choose, so a generated name always passes the same validation.
pub const MAX_GENERATED_CHARS: usize = 32;

/// The language of a generated pseudonym.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Locale {
    /// French.
    Fr,
    /// English.
    En,
}

impl Locale {
    /// The locale a client names (`en`, `en-GB`, `fr-FR`, `de`): French for
    /// a `fr` tag or none, French being the app's first language; English
    /// for any other, the app's other languages (German, Spanish, Italian,
    /// Dutch) having no word lists yet.
    #[must_use]
    pub fn parse(tag: &str) -> Self {
        let tag = tag.trim().to_ascii_lowercase();
        if tag.is_empty() || tag.starts_with("fr") {
            Self::Fr
        } else {
            Self::En
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Gender {
    Masculine,
    Feminine,
}

/// The parsed word lists of both languages.
#[derive(Debug)]
struct Words {
    fr_animals: Vec<(&'static str, Gender)>,
    fr_adjectives: Vec<(&'static str, &'static str)>,
    fr_places: Vec<&'static str>,
    en_adjectives: Vec<&'static str>,
    en_animals: Vec<&'static str>,
    en_places: Vec<&'static str>,
}

/// The entries of a word file: non-empty lines that are not comments.
fn entries(file: &'static str) -> impl Iterator<Item = &'static str> {
    file.lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
}

/// Entries of the form `a|b`; a line without the separator is skipped, and
/// the tests check that none is.
fn pairs(file: &'static str) -> impl Iterator<Item = (&'static str, &'static str)> {
    entries(file).filter_map(|l| l.split_once('|'))
}

fn words() -> &'static Words {
    static WORDS: OnceLock<Words> = OnceLock::new();
    WORDS.get_or_init(|| Words {
        fr_animals: pairs(include_str!("../words/fr-animals.txt"))
            .filter_map(|(name, gender)| match gender {
                "m" => Some((name, Gender::Masculine)),
                "f" => Some((name, Gender::Feminine)),
                _ => None,
            })
            .collect(),
        fr_adjectives: pairs(include_str!("../words/fr-adjectives.txt")).collect(),
        fr_places: entries(include_str!("../words/fr-places.txt")).collect(),
        en_adjectives: entries(include_str!("../words/en-adjectives.txt")).collect(),
        en_animals: entries(include_str!("../words/en-animals.txt")).collect(),
        en_places: entries(include_str!("../words/en-places.txt")).collect(),
    })
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

fn french(animal: (&str, Gender), adjective: (&str, &str), place: &str) -> String {
    let (name, gender) = animal;
    let adjective = match gender {
        Gender::Masculine => adjective.0,
        Gender::Feminine => adjective.1,
    };
    format!("{name} {adjective} {place}")
}

fn english(adjective: &str, animal: &str, place: &str) -> String {
    format!("{adjective} {animal} {place}")
}

/// A fresh pseudonym in `locale`, at most [`MAX_GENERATED_CHARS`]
/// characters.
///
/// # Errors
///
/// [`AuthError::Random`] when the system cannot supply random bytes.
pub fn generate_pseudonym(locale: Locale) -> Result<String, AuthError> {
    let w = words();
    Ok(match locale {
        Locale::Fr => french(
            pick(&w.fr_animals)?,
            pick(&w.fr_adjectives)?,
            pick(&w.fr_places)?,
        ),
        Locale::En => english(
            pick(&w.en_adjectives)?,
            pick(&w.en_animals)?,
            pick(&w.en_places)?,
        ),
    })
}

#[cfg(test)]
mod tests {
    use lunaway_domain::community::{moderation::contains_banned_word, pseudonym};

    use super::*;

    /// The names that put every pair of words side by side: each pair of
    /// lists in full, the third word fixed. A banned phrase or a forbidden
    /// character across a word boundary shows up in one of them; the full
    /// product (about 200 000 names) takes half a minute in a debug build.
    fn every_pair() -> Vec<String> {
        let w = words();
        let mut out = Vec::new();
        let (animal, adjective, place) = (w.fr_animals[0], w.fr_adjectives[0], w.fr_places[0]);
        for &an in &w.fr_animals {
            for &ad in &w.fr_adjectives {
                out.push(french(an, ad, place));
            }
            for pl in &w.fr_places {
                out.push(french(an, adjective, pl));
            }
        }
        for &ad in &w.fr_adjectives {
            for pl in &w.fr_places {
                out.push(french(animal, ad, pl));
                out.push(french(("Chouette", Gender::Feminine), ad, pl));
            }
        }
        let (adjective, animal, place) = (w.en_adjectives[0], w.en_animals[0], w.en_places[0]);
        for ad in &w.en_adjectives {
            for an in &w.en_animals {
                out.push(english(ad, an, place));
            }
            for pl in &w.en_places {
                out.push(english(ad, animal, pl));
            }
        }
        for an in &w.en_animals {
            for pl in &w.en_places {
                out.push(english(adjective, an, pl));
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

    #[test]
    fn every_line_of_the_lists_is_read() {
        let w = words();
        let count = |file: &'static str| entries(file).count();
        assert_eq!(
            w.fr_animals.len(),
            count(include_str!("../words/fr-animals.txt")),
            "every French animal needs its gender, m or f"
        );
        assert_eq!(
            w.fr_adjectives.len(),
            count(include_str!("../words/fr-adjectives.txt")),
            "every French adjective needs both forms"
        );
        for list in [
            w.fr_places.len(),
            w.en_adjectives.len(),
            w.en_animals.len(),
            w.en_places.len(),
            w.fr_animals.len(),
            w.fr_adjectives.len(),
        ] {
            assert!(list >= 40, "a list this short makes names repeat");
        }
    }

    #[test]
    fn every_combination_fits_and_passes_the_rules_of_a_chosen_name() {
        let w = words();
        let fr = longest(w.fr_animals.iter().map(|a| a.0))
            + longest(w.fr_adjectives.iter().flat_map(|a| [a.0, a.1]))
            + longest(w.fr_places.iter().copied())
            + 2;
        let en = longest(w.en_adjectives.iter().copied())
            + longest(w.en_animals.iter().copied())
            + longest(w.en_places.iter().copied())
            + 2;
        assert!(
            fr <= MAX_GENERATED_CHARS && en <= MAX_GENERATED_CHARS,
            "the longest words together make {fr} (fr) and {en} (en) characters"
        );
        for name in every_pair() {
            assert_eq!(
                pseudonym::normalize_pseudonym(&name).as_deref(),
                Ok(name.as_str()),
                "a generated name must pass the rules a chosen one passes"
            );
            assert!(!contains_banned_word(&name), "{name}");
        }
    }

    #[test]
    fn the_adjective_agrees_with_the_animal() {
        assert_eq!(
            french(
                ("Chouette", Gender::Feminine),
                ("curieux", "curieuse"),
                "du Vercors"
            ),
            "Chouette curieuse du Vercors"
        );
        assert_eq!(
            french(
                ("Hérisson", Gender::Masculine),
                ("curieux", "curieuse"),
                "du Vercors"
            ),
            "Hérisson curieux du Vercors"
        );
    }

    #[test]
    fn both_languages_generate() {
        let w = words();
        let fr = generate_pseudonym(Locale::Fr).unwrap();
        let en = generate_pseudonym(Locale::En).unwrap();
        assert!(
            w.fr_animals
                .iter()
                .any(|a| fr.starts_with(&format!("{} ", a.0))),
            "{fr}"
        );
        assert!(
            w.fr_places.iter().any(|p| fr.ends_with(&format!(" {p}"))),
            "{fr}"
        );
        assert!(
            w.en_places.iter().any(|p| en.ends_with(&format!(" {p}"))),
            "{en}"
        );
        assert_eq!(Locale::parse("en-GB"), Locale::En);
        assert_eq!(Locale::parse("EN"), Locale::En);
        assert_eq!(Locale::parse("fr-FR"), Locale::Fr);
        assert_eq!(Locale::parse(""), Locale::Fr);
        for tag in ["de", "es-ES", "it", "nl"] {
            assert_eq!(
                Locale::parse(tag),
                Locale::En,
                "a reader of the app's other languages gets English words, not French ones"
            );
        }
    }
}
