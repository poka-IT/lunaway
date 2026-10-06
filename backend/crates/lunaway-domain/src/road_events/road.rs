//! Road numbers as the feeds and the routing engine write them: the DIR
//! pads them (`N0020`, `A0075`), DiaLog and the engine space them (`D 949`,
//! `A 20; E 09`), local feeds prefix them (`RN 20`, `RD949`). One canonical
//! form (`N20`, `A75`, `D949`, `E9`) lets an event and a route agree on the
//! road they are on.

/// Longest number kept: French road numbers have at most four digits.
const MAX_DIGITS: usize = 4;

/// The canonical form of one road number: its letters (a leading `R` of
/// `RN`/`RD` dropped), its number without leading zeros, and a trailing
/// letter of a branch (`N20A`). `None` when it is not a road number.
#[must_use]
pub fn normalize(raw: &str) -> Option<String> {
    let compact: String = raw
        .chars()
        .filter(|c| !c.is_whitespace() && *c != '.' && *c != '-' && *c != '_')
        .map(|c| c.to_ascii_uppercase())
        .collect();
    let letters: String = compact
        .chars()
        .take_while(char::is_ascii_alphabetic)
        .collect();
    let rest = &compact[letters.len()..];
    let digits: String = rest.chars().take_while(char::is_ascii_digit).collect();
    let suffix = &rest[digits.len()..];
    if letters.is_empty() || letters.len() > 3 || digits.is_empty() {
        return None;
    }
    if suffix.len() > 1 || !suffix.chars().all(|c| c.is_ascii_alphabetic()) {
        return None;
    }
    let letters = match letters.as_str() {
        "RN" => "N",
        "RD" => "D",
        "RC" => "C",
        "RM" => "M",
        other => other,
    };
    let number = digits.trim_start_matches('0');
    if number.is_empty() || number.len() > MAX_DIGITS {
        return None;
    }
    Some(format!("{letters}{number}{suffix}"))
}

/// Every road number of a list as the engine writes it (`A 20; E 09`,
/// `D 947/D 2`), canonical, in order, each once.
#[must_use]
pub fn numbers(raw: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for part in raw.split([';', '/', ',']) {
        if let Some(n) = normalize(part)
            && !out.contains(&n)
        {
            out.push(n);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_spelling_of_a_road_number_reads_the_same() {
        for (raw, want) in [
            ("N0020", "N20"),
            ("N 20", "N20"),
            ("RN20", "N20"),
            ("rn 20", "N20"),
            ("A0075", "A75"),
            ("D 949", "D949"),
            ("RD949", "D949"),
            ("E 09", "E9"),
            ("N165", "N165"),
            ("N20A", "N20A"),
            ("M 383", "M383"),
        ] {
            assert_eq!(normalize(raw).as_deref(), Some(want), "{raw}");
        }
    }

    #[test]
    fn a_name_is_not_a_road_number() {
        for raw in [
            "Rue de Jarménil",
            "",
            "N",
            "20",
            "N0",
            "ABCD12",
            "N20AB",
            "N12345",
        ] {
            assert_eq!(normalize(raw), None, "{raw}");
        }
    }

    #[test]
    fn a_list_reads_each_number_once() {
        assert_eq!(numbers("A 20; E 09"), ["A20", "E9"]);
        assert_eq!(numbers("D 947/D 2; D 947"), ["D947", "D2"]);
        assert!(numbers("Avenue de Limoges").is_empty());
    }

    #[test]
    fn road_numbers_compare_whatever_their_spelling() {
        assert!(super::super::same_road("N0165", "N 165"));
        assert!(!super::super::same_road("N165", "N16"));
        assert!(!super::super::same_road("Rue", "Rue"));
    }
}
