//! Pseudonyms a user chooses: length, characters, and no insult.
//!
//! A pseudonym is public on every contribution, so it follows the rules of
//! a published text (no insult, no link, no contact details) and a few of
//! its own: letters of any script, digits, spaces and `' - _ .`, at least
//! two letters, 3 to 32 characters once normalised.

use unicode_normalization::{UnicodeNormalization, char::is_combining_mark};

use super::moderation::{TextFlag, check_text, contains_banned_word};

/// Length of a pseudonym, in characters after normalisation.
pub const PSEUDONYM_CHARS: std::ops::RangeInclusive<usize> = 3..=32;

/// Longest input looked at, in bytes: 32 characters of four bytes each,
/// with room for surrounding spaces. Anything longer is refused before any
/// normalisation work.
const MAX_INPUT_BYTES: usize = 512;

/// Why a pseudonym is refused.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
#[non_exhaustive]
pub enum PseudonymError {
    /// Shorter than 3 or longer than 32 characters.
    #[error("a pseudonym holds 3 to 32 characters")]
    Length,
    /// A character other than letters, digits, spaces and `' - _ .`, or
    /// fewer than two letters.
    #[error(
        "a pseudonym holds letters, digits, spaces and ' - _ . only, with two letters at least"
    )]
    Characters,
    /// An insult or a slur.
    #[error("a pseudonym may not hold an insult")]
    BannedWord,
    /// A web address, an e-mail address or a phone number.
    #[error("a pseudonym may not hold a link or contact details")]
    LinkOrContact,
    /// A word that would pass for the project or its moderators.
    #[error("a pseudonym may not pass for Lunaway or its moderators")]
    Reserved,
}

/// Words a pseudonym may not hold, folded: a name such as "Lunaway" or
/// "Modération" on a review would pass for the project speaking.
const RESERVED: &[&str] = &[
    "lunaway",
    "admin",
    "administrateur",
    "administratrice",
    "administrator",
    "moderateur",
    "moderatrice",
    "moderation",
    "moderator",
    "support",
    "staff",
    "officiel",
    "official",
];

fn reserved(name: &str) -> bool {
    let folded = crate::conflation::normalize::fold(name);
    folded.split(' ').any(|w| {
        RESERVED
            .iter()
            .any(|r| w == *r || (w.len() > 4 && w.starts_with("lunaway")))
    })
}

fn allowed(c: char) -> bool {
    c.is_alphabetic()
        || c.is_ascii_digit()
        || is_combining_mark(c)
        || matches!(c, ' ' | '\'' | '-' | '_' | '.')
}

/// The pseudonym as stored: NFC, the typographic apostrophe as `'`, trimmed,
/// inner whitespace as one space; or why it is refused.
///
/// # Errors
///
/// [`PseudonymError`] naming the first rule the input breaks, in the order
/// length, characters, insult, link or contact.
pub fn normalize_pseudonym(input: &str) -> Result<String, PseudonymError> {
    // Bounded before any work: the API may hand over a long string.
    if input.len() > MAX_INPUT_BYTES {
        return Err(PseudonymError::Length);
    }
    let composed: String = input
        .nfc()
        .map(|c| {
            if matches!(c, '\u{2019}' | '\u{02bc}') {
                '\''
            } else {
                c
            }
        })
        .collect();
    let name = composed.split_whitespace().collect::<Vec<_>>().join(" ");
    if !PSEUDONYM_CHARS.contains(&name.chars().count()) {
        return Err(PseudonymError::Length);
    }
    if !name.chars().all(allowed) || name.chars().filter(|c| c.is_alphabetic()).count() < 2 {
        return Err(PseudonymError::Characters);
    }
    if contains_banned_word(&name) {
        return Err(PseudonymError::BannedWord);
    }
    if reserved(&name) {
        return Err(PseudonymError::Reserved);
    }
    if check_text(&name)
        .iter()
        .any(|f| matches!(f, TextFlag::Link | TextFlag::ContactDetails))
    {
        return Err(PseudonymError::LinkOrContact);
    }
    Ok(name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_name_may_not_pass_for_the_project() {
        for name in [
            "Lunaway",
            "Équipe Modération",
            "lunaway officiel",
            "Admin",
            "LunawayTeam",
        ] {
            assert_eq!(
                normalize_pseudonym(name),
                Err(PseudonymError::Reserved),
                "{name}"
            );
        }
        assert!(
            normalize_pseudonym("Supporter du Vercors").is_ok(),
            "a whole word only"
        );
    }

    #[test]
    fn a_name_is_normalised() {
        assert_eq!(
            normalize_pseudonym("  Hérisson   curieux\tdu Vercors "),
            Ok("Hérisson curieux du Vercors".to_owned())
        );
        assert_eq!(
            normalize_pseudonym("Chouette d\u{2019}Aubrac"),
            Ok("Chouette d'Aubrac".to_owned()),
            "the typographic apostrophe a phone keyboard types"
        );
        assert_eq!(
            normalize_pseudonym("He\u{301}ron"),
            Ok("Héron".to_owned()),
            "a decomposed accent is stored composed, so one name has one form"
        );
        assert_eq!(
            normalize_pseudonym("Jean-Luc_74"),
            Ok("Jean-Luc_74".to_owned())
        );
        assert_eq!(normalize_pseudonym("Влад"), Ok("Влад".to_owned()));
    }

    #[test]
    fn lengths_count_characters() {
        assert_eq!(normalize_pseudonym("Al"), Err(PseudonymError::Length));
        assert_eq!(normalize_pseudonym("   Al   "), Err(PseudonymError::Length));
        assert!(
            normalize_pseudonym(&"é".repeat(32)).is_ok(),
            "32 characters, 64 bytes"
        );
        assert_eq!(
            normalize_pseudonym(&"a".repeat(33)),
            Err(PseudonymError::Length)
        );
        assert_eq!(
            normalize_pseudonym(&"a".repeat(10_000)),
            Err(PseudonymError::Length)
        );
    }

    #[test]
    fn odd_characters_are_refused() {
        for bad in [
            "Bob 🚐",
            "Bob\u{200b}by",
            "Bob<script>",
            "Bob@home",
            "12345",
            "a.1",
            "Bob\u{0}",
        ] {
            assert_eq!(
                normalize_pseudonym(bad),
                Err(PseudonymError::Characters),
                "{bad:?}"
            );
        }
    }

    #[test]
    fn insults_links_and_contacts_are_refused() {
        assert_eq!(
            normalize_pseudonym("Gros Connard"),
            Err(PseudonymError::BannedWord)
        );
        assert_eq!(
            normalize_pseudonym("camping.fr"),
            Err(PseudonymError::LinkOrContact)
        );
        assert_eq!(
            normalize_pseudonym("Bob 06 12 34 56 78"),
            Err(PseudonymError::LinkOrContact)
        );
        assert!(normalize_pseudonym("Fan de Bitche").is_ok());
    }
}
