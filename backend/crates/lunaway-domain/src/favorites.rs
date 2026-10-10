//! Points a user saves in a favourite list outside the places of the data:
//! an address the search found, a town, a bare point of the map, or a shop
//! or a service. A saved point carries what the device knew when it was
//! saved (a name the user may change, a short note, the postal address)
//! and its coordinates. It is private to the account: nothing here is ever
//! published, so its texts follow no rule of a published text, only bounds
//! that keep a row small and free of characters that would garble a screen.

use std::{fmt, str::FromStr};

use serde::{Deserialize, Serialize};

use crate::{UnknownCode, geo::Position, poi::PoiKind, taxonomy::coded_enum};

coded_enum! {
    /// What a saved point is, for its icon and for what opens it again.
    FavoritePointKind {
        /// A postal address or a street the search found.
        Address => "address",
        /// A town or a postcode.
        Town => "town",
        /// A bare point of the map.
        Point => "point",
        /// A shop or a service: a point of interest.
        Poi => "poi",
    }
}

/// Length of a saved point's name, in characters once its whitespace is
/// folded.
pub const NAME_CHARS: std::ops::RangeInclusive<usize> = 1..=120;

/// Longest note, in characters once trimmed.
pub const MAX_NOTE_CHARS: usize = 280;

/// Longest postal address, in characters once its whitespace is folded.
pub const MAX_ADDRESS_CHARS: usize = 200;

/// Why a saved point is refused. Each message names the field, so the API
/// returns it as is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
#[non_exhaustive]
pub enum SavedPointError {
    /// The name is empty or longer than [`NAME_CHARS`].
    #[error("name: 1 to 120 characters")]
    NameLength,
    /// The note is longer than [`MAX_NOTE_CHARS`].
    #[error("note: 280 characters at most")]
    NoteLength,
    /// The address is longer than [`MAX_ADDRESS_CHARS`].
    #[error("address: 200 characters at most")]
    AddressLength,
    /// A control character (a line break is allowed in the note only) or a
    /// bidirectional override in the named field.
    #[error("{0}: no control characters")]
    Control(&'static str),
    /// The coordinates are not a position on Earth.
    #[error("lat, lon: a position on Earth")]
    Position,
    /// A point of interest without both its id and its kind, or a point of
    /// another kind that names one.
    #[error("poiId and poiKind: both for a shop or a service, neither otherwise")]
    Poi,
}

/// The point of interest a saved shop or service is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SavedPoi<Id> {
    /// Its identifier.
    pub id: Id,
    /// What it is.
    pub kind: PoiKind,
}

/// A saved point as received, before its checks. `Id` is the type of a
/// point of interest's identifier, which this crate does not name.
#[derive(Debug, Clone, Copy)]
pub struct SavedPointInput<'a, Id> {
    /// What it is.
    pub kind: FavoritePointKind,
    /// The name the user gave it.
    pub name: &'a str,
    /// A short note.
    pub note: Option<&'a str>,
    /// Its postal address.
    pub address: Option<&'a str>,
    /// Latitude, degrees.
    pub lat: f64,
    /// Longitude, degrees.
    pub lon: f64,
    /// The point of interest, for a shop or a service.
    pub poi_id: Option<Id>,
    /// The kind of that point of interest.
    pub poi_kind: Option<PoiKind>,
}

/// A saved point as stored: its texts normalised and within bounds, its
/// position checked, and a point of interest exactly when it is one.
#[derive(Debug, Clone, PartialEq)]
pub struct SavedPoint<Id> {
    /// What it is.
    pub kind: FavoritePointKind,
    /// Its name, inner whitespace as one space.
    pub name: String,
    /// Its note, trimmed, line breaks as `\n`; `None` when empty.
    pub note: Option<String>,
    /// Its postal address on one line; `None` when empty.
    pub address: Option<String>,
    /// Where it is.
    pub position: Position,
    /// The point of interest, for [`FavoritePointKind::Poi`] only.
    pub poi: Option<SavedPoi<Id>>,
}

impl<Id> SavedPoint<Id> {
    /// Checks and normalises `input`.
    ///
    /// # Errors
    ///
    /// [`SavedPointError`] names the first field that is refused.
    pub fn parse(input: SavedPointInput<'_, Id>) -> Result<Self, SavedPointError> {
        let name = folded(input.name);
        if !NAME_CHARS.contains(&name.chars().count()) {
            return Err(SavedPointError::NameLength);
        }
        if name.chars().any(forbidden) {
            return Err(SavedPointError::Control("name"));
        }
        let note = input.note.map(note_text).filter(|n| !n.is_empty());
        if let Some(n) = &note {
            if n.chars().count() > MAX_NOTE_CHARS {
                return Err(SavedPointError::NoteLength);
            }
            if n.chars().any(|c| c != '\n' && forbidden(c)) {
                return Err(SavedPointError::Control("note"));
            }
        }
        let address = input.address.map(folded).filter(|a| !a.is_empty());
        if let Some(a) = &address {
            if a.chars().count() > MAX_ADDRESS_CHARS {
                return Err(SavedPointError::AddressLength);
            }
            if a.chars().any(forbidden) {
                return Err(SavedPointError::Control("address"));
            }
        }
        // The cause is left out: it holds the coordinates, and the API
        // returns this message to the caller and may log it.
        let position =
            Position::new(input.lat, input.lon).map_err(|_| SavedPointError::Position)?;
        let poi = match (input.kind, input.poi_id, input.poi_kind) {
            (FavoritePointKind::Poi, Some(id), Some(kind)) => Some(SavedPoi { id, kind }),
            (FavoritePointKind::Poi, _, _) | (_, Some(_), _) | (_, _, Some(_)) => {
                return Err(SavedPointError::Poi);
            }
            _ => None,
        };
        Ok(Self {
            kind: input.kind,
            name,
            note,
            address,
            position,
            poi,
        })
    }
}

/// `text` with its whitespace (line breaks and tabs included) folded into
/// single spaces and trimmed.
fn folded(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// A note trimmed, every line break written `\n`.
fn note_text(text: &str) -> String {
    text.replace("\r\n", "\n")
        .replace('\r', "\n")
        .trim()
        .to_owned()
}

/// A character no saved text may hold: a control character, or an override
/// of the text's direction, which would turn the rest of a line around on
/// the screens that show it.
fn forbidden(c: char) -> bool {
    c.is_control() || matches!(c, '\u{202A}'..='\u{202E}' | '\u{2066}'..='\u{2069}')
}

#[cfg(test)]
mod tests {
    use super::*;

    fn input(name: &str) -> SavedPointInput<'_, u32> {
        SavedPointInput {
            kind: FavoritePointKind::Address,
            name,
            note: None,
            address: None,
            lat: 48.85,
            lon: 2.31,
            poi_id: None,
            poi_kind: None,
        }
    }

    #[test]
    fn a_name_folds_its_whitespace_and_holds_1_to_120_characters() {
        let p = SavedPoint::parse(input("  20  avenue\tde\nSégur  ")).unwrap();
        assert_eq!(p.name, "20 avenue de Ségur");
        let at_most = "é".repeat(120);
        assert_eq!(SavedPoint::parse(input(&at_most)).unwrap().name, at_most);
        let over = "é".repeat(121);
        assert_eq!(
            SavedPoint::parse(input(&over)),
            Err(SavedPointError::NameLength)
        );
        assert_eq!(
            SavedPoint::parse(input(" \n\t ")),
            Err(SavedPointError::NameLength),
            "a name of whitespace only is empty"
        );
    }

    #[test]
    fn a_note_is_trimmed_keeps_its_line_breaks_and_holds_280_characters() {
        let mut i = input("Chez Paul");
        i.note = Some("  Portail vert\r\nsonner deux fois\rmerci  ");
        let p = SavedPoint::parse(i).unwrap();
        assert_eq!(
            p.note.as_deref(),
            Some("Portail vert\nsonner deux fois\nmerci")
        );
        let at_most = "a".repeat(280);
        i.note = Some(&at_most);
        assert_eq!(
            SavedPoint::parse(i).unwrap().note.as_deref(),
            Some(&*at_most)
        );
        let over = "a".repeat(281);
        i.note = Some(&over);
        assert_eq!(SavedPoint::parse(i), Err(SavedPointError::NoteLength));
        i.note = Some("  \r\n ");
        assert_eq!(
            SavedPoint::parse(i).unwrap().note,
            None,
            "an empty note is none"
        );
    }

    #[test]
    fn an_address_is_one_line_of_200_characters_at_most() {
        let mut i = input("Bureau");
        i.address = Some(" 20 avenue de Ségur\n75007   Paris ");
        assert_eq!(
            SavedPoint::parse(i).unwrap().address.as_deref(),
            Some("20 avenue de Ségur 75007 Paris")
        );
        let over = "a".repeat(201);
        i.address = Some(&over);
        assert_eq!(SavedPoint::parse(i), Err(SavedPointError::AddressLength));
        i.address = Some("   ");
        assert_eq!(SavedPoint::parse(i).unwrap().address, None);
    }

    #[test]
    fn control_characters_and_direction_overrides_are_refused() {
        assert_eq!(
            SavedPoint::parse(input("abc\u{202E}def")),
            Err(SavedPointError::Control("name"))
        );
        assert_eq!(
            SavedPoint::parse(input("abc\u{0007}")),
            Err(SavedPointError::Control("name"))
        );
        let mut i = input("Chez Paul");
        i.note = Some("ligne\u{2066}isolée");
        assert_eq!(SavedPoint::parse(i), Err(SavedPointError::Control("note")));
        i.note = Some("tab\there");
        assert_eq!(
            SavedPoint::parse(i),
            Err(SavedPointError::Control("note")),
            "only a line break is allowed in a note"
        );
    }

    #[test]
    fn the_position_must_be_on_earth() {
        let mut i = input("Ici");
        i.lat = 91.0;
        assert_eq!(SavedPoint::parse(i), Err(SavedPointError::Position));
        i.lat = f64::NAN;
        assert_eq!(SavedPoint::parse(i), Err(SavedPointError::Position));
    }

    #[test]
    fn a_point_of_interest_names_its_id_and_kind_and_no_other_point_does() {
        let mut i = input("Boulangerie");
        i.kind = FavoritePointKind::Poi;
        assert_eq!(SavedPoint::parse(i), Err(SavedPointError::Poi));
        i.poi_id = Some(7);
        assert_eq!(SavedPoint::parse(i), Err(SavedPointError::Poi));
        i.poi_kind = Some(PoiKind::Bakery);
        assert_eq!(
            SavedPoint::parse(i).unwrap().poi,
            Some(SavedPoi {
                id: 7,
                kind: PoiKind::Bakery
            })
        );
        i.kind = FavoritePointKind::Address;
        assert_eq!(SavedPoint::parse(i), Err(SavedPointError::Poi));
        i.poi_id = None;
        assert_eq!(SavedPoint::parse(i), Err(SavedPointError::Poi));
    }

    #[test]
    fn every_kind_has_a_stable_code() {
        for k in FavoritePointKind::ALL {
            assert_eq!(k.code().parse::<FavoritePointKind>().unwrap(), *k);
        }
        assert_eq!(
            FavoritePointKind::ALL
                .iter()
                .map(|k| k.code())
                .collect::<Vec<_>>(),
            ["address", "town", "point", "poi"],
            "the codes are stored and match the table's check"
        );
    }
}
