//! The rules of machine translation that do not depend on the engine: the
//! language a stored text is in, when its source did not say, and the
//! fingerprint a cached translation is checked against.
//!
//! The translation itself runs on Lunaway's own server with open models
//! (`docs/deploy.md`, "Translation"); nothing here sends a text anywhere.
//! The guess of a language needs the feature `language-detection`.

#[cfg(feature = "language-detection")]
use std::sync::LazyLock;

#[cfg(feature = "language-detection")]
use lingua::{Language, LanguageDetector, LanguageDetectorBuilder};
use sha2::{Digest, Sha256};

use crate::record::UNDETERMINED_LANGUAGE;

/// The languages the detector chooses among: the app's and those of most
/// reviews and descriptions (French, German, English, Spanish, Dutch,
/// Italian, then Portuguese, measured on 6 000 reviews of the external
/// community source on 2026-10-08). A text in another language is taken
/// for the nearest of them, so the list stays short and close to what the
/// texts hold: each language added costs memory and makes the others less
/// certain.
#[cfg(feature = "language-detection")]
const DETECTED: [Language; 7] = [
    Language::French,
    Language::English,
    Language::German,
    Language::Dutch,
    Language::Spanish,
    Language::Italian,
    Language::Portuguese,
];

/// Fewest letters a text needs for its language to be guessed: below, a
/// name or a word ("Top !", "Parking") says nothing reliable, and nobody
/// needs it translated. The app offers a translation of a text of unknown
/// language only from the same length.
pub const MIN_LETTERS: usize = 12;

/// Built once, with every model loaded: a process holding it measured
/// 40 MB resident, and a guess took about 0.2 ms for a review of 150
/// characters (M2 Ultra, 2026-10-08).
#[cfg(feature = "language-detection")]
static DETECTOR: LazyLock<LanguageDetector> = LazyLock::new(|| {
    LanguageDetectorBuilder::from_languages(&DETECTED)
        .with_preloaded_language_models()
        .build()
});

/// Loads the detector's models now, so the loading does not fall on the
/// first request that needs a guess.
#[cfg(feature = "language-detection")]
pub fn warm_up() {
    LazyLock::force(&DETECTOR);
}

/// The primary language of a BCP 47 tag, lower case (`pt` for `pt-BR`), or
/// `None` for the undetermined `und`, an empty tag or one that is not a
/// language.
#[must_use]
pub fn primary_language(tag: &str) -> Option<String> {
    let primary = tag.trim().split(['-', '_']).next()?.to_ascii_lowercase();
    let valid = (2..=3).contains(&primary.len()) && primary.bytes().all(|b| b.is_ascii_lowercase());
    (valid && primary != UNDETERMINED_LANGUAGE).then_some(primary)
}

/// The language `text` is written in, guessed from its words: `None` when
/// it is too short to say, or when no language stands out.
#[cfg(feature = "language-detection")]
#[must_use]
pub fn detect_language(text: &str) -> Option<&'static str> {
    if text.chars().filter(|c| c.is_alphabetic()).count() < MIN_LETTERS {
        return None;
    }
    DETECTOR.detect_language_of(text).map(code)
}

/// The language a stored text is in: the one its source or its author's
/// app gave, else the one guessed from its words. A source's label is
/// trusted over a guess: on 13 059 descriptions labelled by the external
/// community source, the detector disagreed with 1.5 %, nearly all short
/// texts it got wrong ("Parking gratuit." taken for English).
#[cfg(feature = "language-detection")]
#[must_use]
pub fn source_language(stored: Option<&str>, text: &str) -> Option<String> {
    stored
        .and_then(primary_language)
        .or_else(|| detect_language(text).map(str::to_owned))
}

/// Whether `lang` may name the language a translation is asked into: two
/// lower-case letters (`fr`, `en`).
#[must_use]
pub fn is_target_language(lang: &str) -> bool {
    lang.len() == 2 && lang.bytes().all(|b| b.is_ascii_lowercase())
}

/// The fingerprint of a text a translation was made from: the SHA-256 of
/// its UTF-8 bytes. A cached translation is served only while the text it
/// came from still has this fingerprint, so an edited review or a refreshed
/// description is translated again.
#[must_use]
pub fn text_fingerprint(text: &str) -> [u8; 32] {
    Sha256::digest(text.as_bytes()).into()
}

#[cfg(feature = "language-detection")]
fn code(language: Language) -> &'static str {
    match language {
        Language::French => "fr",
        Language::English => "en",
        Language::German => "de",
        Language::Dutch => "nl",
        Language::Spanish => "es",
        Language::Italian => "it",
        Language::Portuguese => "pt",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_tag_gives_its_primary_language_and_und_gives_none() {
        assert_eq!(primary_language("pt-BR").as_deref(), Some("pt"));
        assert_eq!(primary_language(" DE ").as_deref(), Some("de"));
        assert_eq!(
            primary_language("und"),
            None,
            "und says the source did not know"
        );
        assert_eq!(primary_language(""), None);
        assert_eq!(primary_language("payment"), None, "not a language subtag");
    }

    #[cfg(feature = "language-detection")]
    #[test]
    fn the_language_of_a_review_is_guessed_from_its_words() {
        let cases = [
            (
                "Sehr schöner Platz. Sanitär war sauber, Reservierung online.",
                "de",
            ),
            ("Ideale plek om te overnachten als je de ferry neemt.", "nl"),
            (
                "Esta bien si pasas por ahi, es tranquilo y a la sombra.",
                "es",
            ),
            ("Très bien, bon emplacement et jolie région au calme.", "fr"),
            (
                "Lovely place to stay and enjoy the town and the lake.",
                "en",
            ),
            (
                "Spettacolare il panorama, vale il costo del parcheggio.",
                "it",
            ),
        ];
        for (text, lang) in cases {
            assert_eq!(detect_language(text), Some(lang), "{text}");
        }
    }

    #[cfg(feature = "language-detection")]
    #[test]
    fn a_text_too_short_has_no_guessed_language() {
        assert_eq!(detect_language("Top !"), None);
        assert_eq!(detect_language("12 € la nuit"), None);
    }

    #[cfg(feature = "language-detection")]
    #[test]
    fn a_stored_language_wins_over_a_guess() {
        assert_eq!(
            source_language(Some("fr"), "Parking gratuit, very quiet place").as_deref(),
            Some("fr"),
            "the source's label is trusted: a short text fools the detector"
        );
        assert_eq!(
            source_language(Some("und"), "Sehr schöner Platz, sauber und ruhig.").as_deref(),
            Some("de"),
            "an undetermined label is guessed"
        );
        assert_eq!(source_language(None, "Top !"), None);
    }

    #[test]
    fn a_target_language_is_two_lower_case_letters() {
        assert!(is_target_language("fr"));
        assert!(!is_target_language("FR"));
        assert!(!is_target_language("fra"));
        assert!(!is_target_language("f1"));
    }

    #[test]
    fn the_fingerprint_changes_with_the_text() {
        assert_eq!(text_fingerprint("a"), text_fingerprint("a"));
        assert_ne!(text_fingerprint("a"), text_fingerprint("a "));
    }
}
