//! What a row of a list of places shows beyond the place's summary
//! (`Query.placeDigests`): the opening of its description.

/// Longest excerpt, in characters, its ellipsis included: about two lines
/// of a phone's list row, one of a side panel's.
pub const EXCERPT_CHARS: usize = 140;

/// The opening of `text` for a list row, at most `max` characters: its
/// whitespace, line breaks included, collapsed to single spaces; when it is
/// longer, cut after the last whole word that fits (a word longer than half
/// the room is cut inside), its trailing punctuation dropped and an
/// ellipsis added. `None` for a text with nothing to show.
#[must_use]
pub fn excerpt(text: &str, max: usize) -> Option<String> {
    let flat = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if flat.is_empty() || max == 0 {
        return None;
    }
    if flat.chars().count() <= max {
        return Some(flat);
    }
    // One character for the ellipsis.
    let room = max - 1;
    let head: String = flat.chars().take(room).collect();
    // The text goes on after the cut: when the next character is a space,
    // the cut fell between two words and the last one is whole.
    let next_is_space = flat.chars().nth(room).is_some_and(char::is_whitespace);
    let whole = if next_is_space {
        head.as_str()
    } else {
        match head.rfind(' ') {
            Some(at) if head[..at].chars().count() >= room / 2 => &head[..at],
            _ => head.as_str(),
        }
    };
    let trimmed = whole.trim_end_matches(|c: char| c.is_whitespace() || ",;:.-(".contains(c));
    Some(format!("{trimmed}…"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_short_text_is_kept_whole_on_one_line() {
        assert_eq!(
            excerpt("Calme la nuit.\nEau au cimetière.", 140).as_deref(),
            Some("Calme la nuit. Eau au cimetière.")
        );
    }

    #[test]
    fn a_long_text_stops_after_a_whole_word_with_an_ellipsis() {
        let text = "Cadre naturel à moins d'un km du village et des commerces, \
                    à proximité de la ViaRhôna.";
        let cut = excerpt(text, 40).unwrap();
        assert_eq!(cut, "Cadre naturel à moins d'un km du…");
        assert!(cut.chars().count() <= 40);
    }

    #[test]
    fn the_punctuation_before_the_cut_goes() {
        assert_eq!(
            excerpt("Aire calme, ombragée, au bord du Rhône", 14).as_deref(),
            Some("Aire calme…")
        );
    }

    #[test]
    fn a_cut_between_two_words_keeps_the_last_one() {
        assert_eq!(excerpt("un deux trois", 9).as_deref(), Some("un deux…"));
    }

    #[test]
    fn a_word_longer_than_half_the_room_is_cut_inside() {
        let cut = excerpt("Ab Rheinuferpromenadenparkplatzanlage", 20).unwrap();
        assert_eq!(cut.chars().count(), 20);
        assert!(cut.ends_with('…'));
        assert!(cut.starts_with("Ab Rheinufer"));
    }

    #[test]
    fn nothing_to_show_is_none() {
        assert_eq!(excerpt(" \n\t ", 140), None);
        assert_eq!(excerpt("Texte", 0), None);
    }
}
