//! What a search for places asks, read from its words.
//!
//! The words that name a place ("colmyr", "annecy") decide which places
//! match; the words that only say what kind of place is wanted ("aire",
//! "camping", "parking", "de") rank them, so a generic word never decides
//! alone what a query finds. A query made of kind words, articles and
//! prepositions only, that ends on a kind word ("aire de camping car",
//! "stellplatz"), asks for places of that kind: with a point to search
//! around, the nearest of them come first, named after the kind or not.
//! One that ends on an article ("camping la") is a name being typed.
//!
//! The database crate turns a [`PlaceQuery`] into text search queries
//! (`to_tsquery('simple', ..)` over `places.search_vector`) and picks how
//! to find the candidates with [`lookup_path`].

use std::collections::BTreeSet;

use crate::{
    PlaceKind, Position,
    conflation::normalize::{GENERIC_WORDS, normalize_name},
};

const AREA: &[PlaceKind] = &[
    PlaceKind::MotorhomeArea,
    PlaceKind::RestArea,
    PlaceKind::ServiceArea,
];
const MOTORHOME: &[PlaceKind] = &[PlaceKind::MotorhomeArea];
const CAMPSITE: &[PlaceKind] = &[PlaceKind::Campsite];
const PARKING: &[PlaceKind] = &[PlaceKind::Parking];
const SERVICES: &[PlaceKind] = &[PlaceKind::ServiceArea];

/// Words that name a kind of place, folded, and the kinds they mean. "aire",
/// "area" and "aires" name the French and Italian motorhome, rest and
/// service areas alike; "camping car" is read as one word, a motorhome area.
const KIND_WORDS: &[(&str, &[PlaceKind])] = &[
    ("aire", AREA),
    ("aires", AREA),
    ("area", AREA),
    ("camping", CAMPSITE),
    ("campings", CAMPSITE),
    ("campingplatz", CAMPSITE),
    ("campeggio", CAMPSITE),
    ("camp", CAMPSITE),
    ("campsite", CAMPSITE),
    ("caravan", CAMPSITE),
    ("caravane", CAMPSITE),
    ("caravanes", CAMPSITE),
    ("caravaning", CAMPSITE),
    ("campingcar", MOTORHOME),
    ("campingcars", MOTORHOME),
    ("camper", MOTORHOME),
    ("campers", MOTORHOME),
    ("camperplaats", MOTORHOME),
    ("motorhome", MOTORHOME),
    ("motorhomes", MOTORHOME),
    ("stellplatz", MOTORHOME),
    ("wohnmobil", MOTORHOME),
    ("wohnmobile", MOTORHOME),
    ("wohnmobilstellplatz", MOTORHOME),
    ("sosta", MOTORHOME),
    ("autocaravana", MOTORHOME),
    ("autocaravanas", MOTORHOME),
    ("cc", MOTORHOME),
    ("parking", PARKING),
    ("parkings", PARKING),
    ("parkplatz", PARKING),
    ("parcheggio", PARKING),
    ("aparcamiento", PARKING),
    (
        "stationnement",
        &[PlaceKind::Parking, PlaceKind::MotorhomeArea],
    ),
    ("service", SERVICES),
    ("services", SERVICES),
];

/// Generic words that narrow which places of a kind are wanted: "camping
/// municipal" asks for the municipal campsites, not for every campsite
/// around.
const QUALIFIERS: &[&str] = &[
    "accueil",
    "communal",
    "communale",
    "municipal",
    "municipale",
    "municipaux",
    "naturel",
    "naturelle",
];

/// What the database knows of one word of a query, folded and split as the
/// words of places are (`lunaway_search_words`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QueryWord {
    /// The folded word.
    pub word: String,
    /// Whether a word of some place starts with it.
    pub known: bool,
    /// Words of places that look like it, most similar first; asked only
    /// when it is not known.
    pub lookalikes: Vec<String>,
}

/// The share of places holding each of their most common words, from the
/// database's statistics (`pg_stats.most_common_elems` of
/// `places.search_vector`). A word missing from it is held by fewer places
/// than the least common word listed.
#[derive(Debug, Clone, Default)]
pub struct WordShares {
    words: Vec<(String, f64)>,
}

impl WordShares {
    /// The statistics as the database gives them: the words, and their
    /// frequencies (the extra trailing values the database appends are
    /// ignored).
    #[must_use]
    pub fn new(words: Vec<String>, freqs: &[f32]) -> Self {
        Self {
            words: words
                .into_iter()
                .zip(freqs.iter().map(|f| f64::from(*f)))
                .collect(),
        }
    }

    /// The estimated share of places holding `word`, or a word that starts
    /// with it when `prefix`; at most 1.
    #[must_use]
    pub fn share(&self, word: &str, prefix: bool) -> f64 {
        self.words
            .iter()
            .filter(|(w, _)| {
                if prefix {
                    w.starts_with(word)
                } else {
                    w == word
                }
            })
            .map(|(_, f)| f)
            .sum::<f64>()
            .min(1.0)
    }
}

/// One word of a query as it is matched: the typed word, as a prefix, or,
/// when no place has a word that starts with it, the words that look like
/// it.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Slot {
    words: Vec<String>,
    prefix: bool,
    core: bool,
}

impl Slot {
    /// `'word':*`, `'word'`, or `( 'a' | 'b' )` for the lookalikes.
    fn term(&self, prefix: bool) -> String {
        if let [word] = self.words.as_slice() {
            let star = if prefix && self.prefix { ":*" } else { "" };
            return format!("{}{star}", lexeme(word));
        }
        let alternatives: Vec<String> = self.words.iter().map(|w| lexeme(w)).collect();
        format!("( {} )", alternatives.join(" | "))
    }

    fn share(&self, shares: &WordShares) -> f64 {
        self.words
            .iter()
            .map(|w| shares.share(w, self.prefix))
            .sum::<f64>()
            .min(1.0)
    }
}

/// A word quoted for `to_tsquery`. The words of a query hold letters and
/// digits only; the quoting is for safety's sake.
pub(crate) fn lexeme(word: &str) -> String {
    format!("'{}'", word.replace('\\', "\\\\").replace('\'', "''"))
}

/// What a search for places asks, built from the words of its text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlaceQuery {
    slots: Vec<Slot>,
    kinds: Vec<PlaceKind>,
    by_kind: bool,
    only_generic: bool,
}

/// Rows the GIN index reads cheaply for one word: about 8 ms for 20,000
/// places on the 2-vCPU test server of 2026-10-07 (the list of
/// "camping", 96,000 places, took 42 ms). A word held by more places is
/// checked on the rows the others found, not looked up.
const LOOKUP_ROWS: f64 = 20_000.0;

impl PlaceQuery {
    /// The query of these words, in their order; `None` without a word.
    #[must_use]
    pub fn new(words: &[QueryWord]) -> Option<Self> {
        if words.is_empty() {
            return None;
        }
        let folded: Vec<&str> = words.iter().map(|w| w.word.as_str()).collect();
        let generic: Vec<bool> = folded.iter().map(|w| is_generic(w)).collect();
        let only_generic = generic.iter().all(|g| *g);
        let last = words.len() - 1;
        let slots = words
            .iter()
            .zip(&generic)
            .enumerate()
            .map(|(i, (w, g))| {
                let core = only_generic || !g;
                if w.known {
                    return Slot {
                        words: vec![w.word.clone()],
                        prefix: true,
                        core,
                    };
                }
                let near = within_reach(&w.word, &w.lookalikes, i == last);
                Slot {
                    words: if near.is_empty() {
                        vec![w.word.clone()]
                    } else {
                        near
                    },
                    prefix: false,
                    core,
                }
            })
            .collect();
        let kinds = implied_kinds(&folded);
        let by_kind = only_generic
            && !kinds.is_empty()
            && !folded.iter().any(|w| QUALIFIERS.contains(w))
            && ends_with_kind_word(&folded);
        Some(Self {
            slots,
            kinds,
            by_kind,
            only_generic,
        })
    }

    /// The kinds of place the query's words name, none when they name none.
    #[must_use]
    pub fn kinds(&self) -> &[PlaceKind] {
        &self.kinds
    }

    /// Whether the query asks for places of a kind rather than by name: its
    /// words are kind words, articles and prepositions only, the last one a
    /// kind word. A text that ends on an article is a name being typed
    /// ("camping la"), or a town that is one ("camping die", Die in the
    /// Drôme).
    #[must_use]
    pub fn by_kind(&self) -> bool {
        self.by_kind
    }

    /// The words a place must hold to match: every word that names a place,
    /// each as a prefix, or every word when all are generic.
    #[must_use]
    pub fn filter(&self) -> String {
        self.and(|s| s.core)
    }

    /// Every word of the query, each as a prefix, in any order.
    #[must_use]
    pub fn every_word(&self) -> String {
        self.and(|_| true)
    }

    /// The words that name a place, each a whole word. A place whose name
    /// holds them carries the text ("Camping-car Park Viviers" for
    /// "viviers"), where a place of Chapelle-Viviers holds it by its commune
    /// alone. A word being typed is no whole word yet: "carn" is carried by
    /// no name, rather than by every "Carnoët". None when the text names
    /// nothing as typed: generic words only, or a word corrected to its
    /// lookalikes, which may be a name or a town ("colmir": Colmyr, a
    /// motorhome area, or Colmar), where the nearest reading comes first.
    #[must_use]
    pub fn naming(&self) -> Option<String> {
        if !self.names_as_typed() {
            return None;
        }
        Some(
            self.naming_words()
                .map(lexeme)
                .collect::<Vec<_>>()
                .join(" & "),
        )
    }

    /// `LIKE` patterns a folded name holds when it holds the words of
    /// [`Self::naming`]: a cheap test that leaves out most names before
    /// their words are compared. The words hold letters and digits only; a
    /// wildcard in one would only let more names through to the exact test.
    #[must_use]
    pub fn naming_patterns(&self) -> Vec<String> {
        if !self.names_as_typed() {
            return Vec::new();
        }
        self.naming_words().map(|w| format!("%{w}%")).collect()
    }

    /// Whether the words naming a place are words of places as typed: some
    /// word is not generic, and none was corrected.
    fn names_as_typed(&self) -> bool {
        !self.only_generic && self.slots.iter().filter(|s| s.core).all(|s| s.prefix)
    }

    /// The words naming a place, as typed.
    fn naming_words(&self) -> impl Iterator<Item = &str> {
        self.slots
            .iter()
            .filter(|s| s.core)
            .flat_map(|s| s.words.first())
            .map(String::as_str)
    }

    /// The words of the query in their order, each a whole word.
    #[must_use]
    pub fn phrase(&self) -> String {
        self.joined(false)
    }

    /// The words of the query in their order, the last one as a prefix:
    /// what is being typed.
    #[must_use]
    pub fn phrase_typed(&self) -> String {
        self.joined(true)
    }

    /// The words of [`Self::filter`] the index looks up: those held by few
    /// enough places for their lists to be read cheaply, or all of them
    /// when none is.
    #[must_use]
    pub fn lookup(&self, shares: &WordShares, places: f64) -> String {
        let rare = |s: &Slot| s.core && s.share(shares) * places <= LOOKUP_ROWS;
        if self.slots.iter().any(rare) {
            self.and(rare)
        } else {
            self.filter()
        }
    }

    /// How to find the candidates among `places`, `nearest` of them being
    /// wanted around a point when `near`: by kind for a query of kind
    /// words around a point, else the cheaper way for as many places as
    /// may match ([`lookup_path`]).
    #[must_use]
    pub fn path(&self, shares: &WordShares, places: f64, near: bool, nearest: u32) -> LookupPath {
        if self.by_kind && near {
            LookupPath::Kind
        } else {
            lookup_path(self.estimated_rows(shares, places), places, near, nearest)
        }
    }

    /// The folded names of the towns the query names whole, as
    /// `lunaway_town_fold` writes them: each run of its words, in order,
    /// that holds every word naming a place ("camping viviers" and
    /// "viviers" for "camping viviers"; "saint malo de phily" alone for that
    /// text). A place in such a town is in the town the text names, where a
    /// town whose longer name only holds the words ("Chapelle-Viviers") is
    /// another one. The last word counts whole: a word being typed names no
    /// town yet ("chamo" is not Chamousset). None when the text names
    /// nothing as typed ([`Self::naming`]).
    #[must_use]
    pub fn town_names(&self) -> Vec<String> {
        if !self.names_as_typed() {
            return Vec::new();
        }
        let core: Vec<usize> = (0..self.slots.len())
            .filter(|&i| self.slots[i].core)
            .collect();
        let (Some(&first), Some(&last)) = (core.first(), core.last()) else {
            return Vec::new();
        };
        let words: Vec<&str> = self
            .slots
            .iter()
            .flat_map(|s| s.words.first())
            .map(String::as_str)
            .collect();
        let mut names = BTreeSet::new();
        for start in 0..=first {
            for end in last..words.len().min(start + MAX_TOWN_WORDS) {
                names.insert(words[start..=end].join(" "));
            }
        }
        names.into_iter().collect()
    }

    /// How many of `places` may match [`Self::filter`]: as many as hold its
    /// least common word.
    #[must_use]
    pub fn estimated_rows(&self, shares: &WordShares, places: f64) -> f64 {
        self.slots
            .iter()
            .filter(|s| s.core)
            .map(|s| s.share(shares))
            .fold(1.0, f64::min)
            * places
    }

    fn and(&self, keep: impl Fn(&Slot) -> bool) -> String {
        let terms: Vec<String> = self
            .slots
            .iter()
            .filter(|s| keep(s))
            .map(|s| s.term(true))
            .collect();
        terms.join(" & ")
    }

    fn joined(&self, typed: bool) -> String {
        let last = self.slots.len() - 1;
        let terms: Vec<String> = self
            .slots
            .iter()
            .enumerate()
            .map(|(i, s)| s.term(typed && i == last))
            .collect();
        terms.join(" <-> ")
    }
}

/// Whether the last of `words` names a kind of place, alone or as the end
/// of "camping car".
fn ends_with_kind_word(words: &[&str]) -> bool {
    match words {
        [.., "camping" | "campings", "car" | "cars"] => true,
        [.., last] => KIND_WORDS.iter().any(|(w, _)| w == last),
        [] => false,
    }
}

fn is_generic(word: &str) -> bool {
    GENERIC_WORDS.contains(&word) || KIND_WORDS.iter().any(|(w, _)| *w == word)
}

/// The kinds every kind word of `words` agrees on, or, when they agree on
/// none ("camping parking"), any of them.
fn implied_kinds(words: &[&str]) -> Vec<PlaceKind> {
    let mut sets: Vec<&[PlaceKind]> = Vec::new();
    let mut i = 0;
    while i < words.len() {
        let next = words.get(i + 1).copied();
        if matches!(words[i], "camping" | "campings") && matches!(next, Some("car" | "cars")) {
            sets.push(MOTORHOME);
            i += 2;
            continue;
        }
        if let Some((_, kinds)) = KIND_WORDS.iter().find(|(w, _)| *w == words[i]) {
            sets.push(kinds);
        }
        i += 1;
    }
    let Some((first, rest)) = sets.split_first() else {
        return Vec::new();
    };
    let common: BTreeSet<PlaceKind> = first
        .iter()
        .copied()
        .filter(|k| rest.iter().all(|s| s.contains(k)))
        .collect();
    if common.is_empty() {
        sets.iter()
            .flat_map(|s| s.iter().copied())
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect()
    } else {
        common.into_iter().collect()
    }
}

/// At most this many corrections are tried for one word.
const MAX_CORRECTIONS: usize = 8;

/// The longest run of words compared with the towns of the places found:
/// the longest names of French communes have eight
/// ("Saint-Remy-en-Bouzemont-Saint-Genest-et-Isson").
const MAX_TOWN_WORDS: usize = 10;

/// The lookalikes of `word` within the fewest edits, if that is close
/// enough for its length: none for three letters or fewer (a short word is
/// more likely the start of one being typed), one edit up to six letters,
/// two beyond. When no whole lookalike is that close and `word` is the
/// last of the query, the one being typed, the start of a lookalike counts
/// ("gerrardm" is one edit from the start of "gerardmer"); a whole word
/// comes first, so "bradere" is "bradiere", not the start of "brauerei".
pub(crate) fn within_reach(word: &str, lookalikes: &[String], last: bool) -> Vec<String> {
    let len = word.chars().count();
    let reach = match len {
        0..=3 => return Vec::new(),
        4..=6 => 1,
        _ => 2,
    };
    let whole = closest(lookalikes, reach, |c| edits(word, c));
    if !whole.is_empty() || !last {
        return whole;
    }
    closest(lookalikes, reach, |c| {
        let chars: Vec<char> = c.chars().collect();
        (len.saturating_sub(1)..=len + 1)
            .filter(|n| *n >= 1 && *n <= chars.len())
            .map(|n| edits(word, &chars[..n].iter().collect::<String>()))
            .min()
            .unwrap_or(usize::MAX)
    })
}

/// The candidates at the fewest edits, `reach` at most, in their order.
fn closest(candidates: &[String], reach: usize, distance: impl Fn(&str) -> usize) -> Vec<String> {
    let scored: Vec<(usize, &String)> = candidates.iter().map(|c| (distance(c), c)).collect();
    let Some(best) = scored.iter().map(|(d, _)| *d).min().filter(|d| *d <= reach) else {
        return Vec::new();
    };
    scored
        .into_iter()
        .filter(|(d, _)| *d == best)
        .map(|(_, c)| c.clone())
        .take(MAX_CORRECTIONS)
        .collect()
}

/// Edits between two words: insertions, deletions, substitutions and swaps
/// of two neighbouring letters (optimal string alignment).
fn edits(a: &str, b: &str) -> usize {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    let mut rows = vec![vec![0usize; b.len() + 1]; a.len() + 1];
    for (i, row) in rows.iter_mut().enumerate() {
        row[0] = i;
    }
    for (j, cell) in rows[0].iter_mut().enumerate() {
        *cell = j;
    }
    for i in 1..=a.len() {
        for j in 1..=b.len() {
            let cost = usize::from(a[i - 1] != b[j - 1]);
            let mut best = (rows[i - 1][j] + 1)
                .min(rows[i][j - 1] + 1)
                .min(rows[i - 1][j - 1] + cost);
            if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] {
                best = best.min(rows[i - 2][j - 2] + 1);
            }
            rows[i][j] = best;
        }
    }
    rows[a.len()][b.len()]
}

/// How the candidates of a query are found.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LookupPath {
    /// Every place holding the rare words, from the GIN index.
    Index,
    /// The places nearest the point that match, walking the spatial index
    /// outwards: cheap when many places match.
    Nearest,
    /// The first places that match, reading the table in order: cheap when
    /// many match and there is no point to search around.
    Scan,
    /// The places of the kinds a query of kind words names, nearest the
    /// point first, whatever their name: a place of another kind named
    /// after them would rank after every one of these.
    Kind,
}

/// Time to fetch and rank one place the index found, and to walk past one
/// place on the way out from a point, in microseconds: measured on the
/// 2-vCPU test server of 2026-10-07 at five times the production volume
/// (9,775 places found in 56 ms; 618 walked past in 2.4 ms).
const INDEX_ROW_US: f64 = 6.0;
const NEAREST_ROW_US: f64 = 4.0;
/// Without a point, past this many matches the first ones read in the
/// table are taken: their index lists alone would cost more.
const SCAN_ROWS: f64 = LOOKUP_ROWS;

/// The cheaper way to find the candidates of a query `estimated_rows` of
/// `places` match, `nearest` of them being wanted around a point when
/// `near`. Without statistics (`places` unknown, or zero), the index: it
/// is exact, and a table never analysed is a small one.
#[must_use]
pub fn lookup_path(estimated_rows: f64, places: f64, near: bool, nearest: u32) -> LookupPath {
    if places <= 0.0 {
        return LookupPath::Index;
    }
    let rows = estimated_rows.max(1.0);
    if near {
        // Walking out from the point passes `places / rows` places per
        // match on average.
        let walk = f64::from(nearest) * places / rows * NEAREST_ROW_US;
        if rows * INDEX_ROW_US <= walk {
            LookupPath::Index
        } else {
            LookupPath::Nearest
        }
    } else if rows <= SCAN_ROWS {
        LookupPath::Index
    } else {
        LookupPath::Scan
    }
}

/// Two results of one name farther apart than this are two places, metres.
/// A source that places a campsite by its postal address can put it a few
/// kilometres from where another source maps it (Camping du Mouchet,
/// Chapelle-Viviers: 2.5 km between Atout France and OpenStreetMap), past
/// the reach of the conflation, which then keeps two places.
pub const SAME_PLACE_M: f64 = 5_000.0;

/// One result of a search, as far as telling one place twice goes.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Listed<'a> {
    /// Its kind.
    pub kind: PlaceKind,
    /// Its name.
    pub name: Option<&'a str>,
    /// The commune it lies in.
    pub municipality: Option<&'a str>,
    /// Where it is.
    pub position: Position,
}

/// The pairs of results, an earlier and a later one, that may be one place
/// told twice: of one kind, in one commune, less than [`SAME_PLACE_M`]
/// apart, under one name once folded and stripped of its generic words. A
/// name of generic words alone ("Parking", "Camping municipal") tells two
/// places apart no better than no name, and leaves them two.
#[must_use]
pub fn alike(listed: &[Listed<'_>]) -> Vec<(usize, usize)> {
    let names: Vec<Option<String>> = listed
        .iter()
        .map(|l| l.name.map(normalize_name).filter(|n| !n.is_empty()))
        .collect();
    let mut pairs = Vec::new();
    for (b, later) in listed.iter().enumerate() {
        for (a, earlier) in listed[..b].iter().enumerate() {
            if earlier.kind == later.kind
                && names[a].is_some()
                && names[a] == names[b]
                && earlier.municipality.is_some()
                && earlier.municipality == later.municipality
                && earlier.position.distance_m(later.position) < SAME_PLACE_M
            {
                pairs.push((a, b));
            }
        }
    }
    pairs
}

/// A place whose every record is placed no better than this, metres, is
/// placed roughly: by its postal address (Atout France, 235 m of accuracy
/// on average) or by a tourist office (DATAtourisme, 240 m), while
/// OpenStreetMap and the community pin a place to tens of metres.
pub const ROUGH_POSITION_M: f64 = 200.0;

/// Where the records of a result say it is, as far as telling one place
/// twice goes.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Placement {
    /// The sources of its live records.
    pub sources: Vec<String>,
    /// The best accuracy of its live records, metres.
    pub accuracy_m: Option<f64>,
}

impl Placement {
    fn rough(&self) -> bool {
        self.accuracy_m.is_some_and(|a| a >= ROUGH_POSITION_M)
    }
}

/// Whether two results of [`alike`] are one place told twice: they share
/// no source (one source lists two places apart: two stations of a brand
/// in a town), and one of them is placed roughly, which accounts for the
/// distance between them. Two places pinned precisely a few kilometres
/// apart are two (the car parks of two beaches of one commune). Of the 299
/// pairs of alike places of production that share no source (2026-10-10),
/// 283 have a side placed roughly, Atout France or DATAtourisme in 282. A
/// place whose records are not known is never one of a pair.
#[must_use]
pub fn one_place(a: &Placement, b: &Placement) -> bool {
    !a.sources.is_empty()
        && !b.sources.is_empty()
        && !a.sources.iter().any(|s| b.sources.contains(s))
        && (a.rough() || b.rough())
}

/// The results to leave out, in their order: the later result of each pair
/// of [`alike`] that `one_place` says tell one place, unless the earlier
/// one is left out itself. `one_place` answers for two positions of the
/// list ([`one_place`] on their placements); it is asked only for the
/// pairs.
#[must_use]
pub fn repeated(pairs: &[(usize, usize)], one_place: impl Fn(usize, usize) -> bool) -> Vec<usize> {
    let mut out: Vec<usize> = Vec::new();
    for &(a, b) in pairs {
        if !out.contains(&a) && !out.contains(&b) && one_place(a, b) {
            out.push(b);
        }
    }
    out.sort_unstable();
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn known(word: &str) -> QueryWord {
        QueryWord {
            word: word.to_owned(),
            known: true,
            lookalikes: Vec::new(),
        }
    }

    fn query(words: &[&str]) -> PlaceQuery {
        let words: Vec<QueryWord> = words.iter().map(|w| known(w)).collect();
        PlaceQuery::new(&words).expect("words")
    }

    #[test]
    fn generic_words_rank_and_never_filter_beside_a_name() {
        let q = query(&["camping", "du", "lac", "annecy"]);
        assert_eq!(
            q.filter(),
            "'lac':* & 'annecy':*",
            "a place that is no campsite but by the lake of Annecy still matches"
        );
        assert_eq!(
            q.every_word(),
            "'camping':* & 'du':* & 'lac':* & 'annecy':*"
        );
        assert_eq!(q.phrase(), "'camping' <-> 'du' <-> 'lac' <-> 'annecy'");
        assert_eq!(
            q.phrase_typed(),
            "'camping' <-> 'du' <-> 'lac' <-> 'annecy':*"
        );
        assert_eq!(q.kinds(), [PlaceKind::Campsite]);
        assert!(!q.by_kind(), "a name is asked");
    }

    #[test]
    fn a_query_of_kind_words_asks_for_places_of_that_kind() {
        let q = query(&["aire", "de", "camping", "car"]);
        assert_eq!(
            q.filter(),
            "'aire':* & 'de':* & 'camping':* & 'car':*",
            "with no name, every word filters"
        );
        assert_eq!(
            q.kinds(),
            [PlaceKind::MotorhomeArea],
            "\"camping car\" is a motorhome, and \"aire\" agrees"
        );
        assert!(q.by_kind());
        assert_eq!(query(&["parking"]).kinds(), [PlaceKind::Parking]);
        assert_eq!(
            query(&["aire", "de", "services"]).kinds(),
            [PlaceKind::ServiceArea]
        );
        assert_eq!(
            query(&["camping", "parking"]).kinds(),
            [PlaceKind::Campsite, PlaceKind::Parking],
            "kinds that agree on none are all kept"
        );
        let municipal = query(&["camping", "municipal"]);
        assert!(
            !municipal.by_kind(),
            "a qualifier narrows the kind: the municipal campsites are asked, by name"
        );
        assert_eq!(municipal.kinds(), [PlaceKind::Campsite]);
        assert!(
            !query(&["camping", "die"]).by_kind(),
            "a text ending on an article is a name being typed, or the town of Die"
        );
        assert!(query(&["camping", "car"]).by_kind());
        assert!(query(&["de", "la"]).kinds().is_empty());
        assert!(!query(&["de", "la"]).by_kind());
    }

    #[test]
    fn a_word_no_place_starts_with_is_replaced_by_its_closest_lookalikes() {
        let words = [
            known("gorges"),
            QueryWord {
                word: "verdn".into(),
                known: false,
                lookalikes: vec![
                    "verd".into(),
                    "verde".into(),
                    "verdon".into(),
                    "vers".into(),
                ],
            },
        ];
        let q = PlaceQuery::new(&words).expect("words");
        assert_eq!(
            q.filter(),
            "'gorges':* & ( 'verd' | 'verde' | 'verdon' )",
            "one edit away, each a whole word; \"vers\" is two"
        );
        assert_eq!(
            q.phrase_typed(),
            "'gorges' <-> ( 'verd' | 'verde' | 'verdon' )"
        );
        let nothing_close = QueryWord {
            word: "zzzzqqq".into(),
            known: false,
            lookalikes: vec!["zuzu".into()],
        };
        assert_eq!(
            PlaceQuery::new(&[nothing_close]).expect("words").filter(),
            "'zzzzqqq'",
            "a word with nothing close stays, and matches nothing"
        );
    }

    #[test]
    fn corrections_need_fewer_edits_for_shorter_words() {
        let alike = |w: &str, c: &[&str], last: bool| {
            within_reach(
                w,
                &c.iter().map(|s| (*s).to_owned()).collect::<Vec<_>>(),
                last,
            )
        };
        assert_eq!(
            alike("bradere", &["braderup", "bradiere", "brades"], false),
            ["bradiere"]
        );
        assert_eq!(
            alike("bradere", &["braderup", "bradiere", "brauerei"], true),
            ["bradiere"],
            "a whole word one edit away beats the start of another, even while typing"
        );
        assert_eq!(
            alike("chamonis", &["chamois", "chamonix"], false),
            ["chamois", "chamonix"]
        );
        assert!(
            alike("lca", &["lac"], false).is_empty(),
            "three letters: being typed"
        );
        assert!(alike("colmr", &["colmyr", "colmar"], false).len() == 2);
        assert!(
            alike("gerrardm", &["gerardmer"], false).is_empty(),
            "two edits from the whole word, past the reach of an earlier word"
        );
        assert_eq!(
            alike("gerrardm", &["gerardmer"], true),
            ["gerardmer"],
            "one edit from its start, and it is being typed"
        );
    }

    #[test]
    fn edits_count_a_swap_as_one() {
        assert_eq!(edits("campign", "camping"), 1);
        assert_eq!(edits("lac", "lac"), 0);
        assert_eq!(edits("", "abc"), 3);
        assert_eq!(edits("verdn", "verdon"), 1);
        assert_eq!(edits("bradere", "braderup"), 2);
    }

    #[test]
    fn shares_add_up_the_words_a_prefix_starts() {
        let shares = WordShares::new(
            vec!["camping".into(), "campingplatz".into(), "lac".into()],
            &[0.2, 0.015, 0.003, 0.003, 0.2, 0.0],
        );
        assert!((shares.share("camping", true) - 0.215).abs() < 1e-6);
        assert!((shares.share("camping", false) - 0.2).abs() < 1e-6);
        assert!(
            shares.share("colmyr", true) == 0.0,
            "an unlisted word is rare"
        );
        let q = query(&["camping", "du", "lac"]);
        assert!(
            (q.estimated_rows(&shares, 100_000.0) - 300.0).abs() < 1e-3,
            "the name decides how many match"
        );
        assert_eq!(q.lookup(&shares, 100_000.0), "'lac':*");
        let generic = query(&["camping"]);
        assert_eq!(
            generic.lookup(&shares, 100_000.0),
            "'camping':*",
            "with no rare word, every word is looked up"
        );
    }

    #[test]
    fn the_nearest_are_walked_to_only_when_many_places_match() {
        assert_eq!(lookup_path(50.0, 444_000.0, true, 40), LookupPath::Index);
        assert_eq!(
            lookup_path(90_000.0, 444_000.0, true, 40),
            LookupPath::Nearest
        );
        assert_eq!(
            lookup_path(90_000.0, 444_000.0, false, 40),
            LookupPath::Scan
        );
        assert_eq!(
            lookup_path(2_000.0, 444_000.0, false, 40),
            LookupPath::Index
        );
        assert_eq!(
            lookup_path(90_000.0, 0.0, true, 40),
            LookupPath::Index,
            "without statistics, the exact way"
        );
        let shares = WordShares::default();
        assert_eq!(
            query(&["parking"]).path(&shares, 1_000.0, true, 40),
            LookupPath::Kind
        );
        assert_eq!(
            query(&["parking"]).path(&shares, 1_000.0, false, 40),
            LookupPath::Index,
            "without a point, no place of a kind is nearer than another: by name"
        );
        assert_eq!(
            query(&["camping", "municipal"]).path(&shares, 1_000.0, true, 40),
            LookupPath::Index,
            "a qualified kind is asked by name"
        );
    }

    #[test]
    fn a_text_names_the_towns_of_its_runs_of_words_that_hold_every_naming_word() {
        assert_eq!(query(&["viviers"]).town_names(), ["viviers"]);
        assert_eq!(
            query(&["camping", "viviers"]).town_names(),
            ["camping viviers", "viviers"],
            "the kind word may be part of the town's name or not"
        );
        assert_eq!(
            query(&["saint", "malo", "de", "phily"]).town_names(),
            ["saint malo de phily"],
            "\"saint malo\" alone leaves \"phily\" out: Saint-Malo is not named"
        );
        assert!(
            query(&["camping", "municipal"]).town_names().is_empty(),
            "generic words name no town"
        );
        let corrected = PlaceQuery::new(&[QueryWord {
            word: "colmir".into(),
            known: false,
            lookalikes: vec!["colmar".into(), "colmyr".into()],
        }])
        .expect("a word");
        assert!(
            corrected.town_names().is_empty() && corrected.naming().is_none(),
            "Colmar the town or Colmyr the area: a corrected word names neither, the nearest leads"
        );
    }

    #[test]
    fn the_naming_words_are_whole_words_and_generic_words_name_nothing() {
        assert_eq!(
            query(&["carn"]).naming().as_deref(),
            Some("'carn'"),
            "whole words, never a prefix: \"carn\" is no name's word in Carnoët"
        );
        assert_eq!(
            query(&["camping", "du", "lac", "annecy"])
                .naming()
                .as_deref(),
            Some("'lac' & 'annecy'"),
            "the words that name a place, without the generic ones"
        );
        assert_eq!(
            query(&["camping", "du", "lac", "annecy"]).naming_patterns(),
            ["%lac%", "%annecy%"]
        );
        assert_eq!(query(&["parking"]).naming(), None);
        assert!(query(&["parking"]).naming_patterns().is_empty());
    }

    fn at(lat: f64, lon: f64) -> Position {
        Position::new(lat, lon).expect("a valid test position")
    }

    fn listed<'a>(
        kind: PlaceKind,
        name: Option<&'a str>,
        municipality: Option<&'a str>,
        position: Position,
    ) -> Listed<'a> {
        Listed {
            kind,
            name,
            municipality,
            position,
        }
    }

    #[test]
    fn a_place_two_sources_put_kilometres_apart_is_listed_once() {
        // Chapelle-Viviers, 2026-10-10: OpenStreetMap maps the campsite,
        // Atout France places it 2.5 km away by its postal address.
        let commune = Some("Chapelle-Viviers");
        let list = [
            listed(
                PlaceKind::Campsite,
                Some("Camping du Mouchet"),
                commune,
                at(46.4839, 0.7352),
            ),
            listed(PlaceKind::Parking, None, commune, at(46.4841, 0.7342)),
            listed(
                PlaceKind::Campsite,
                Some("Camping Le Mouchet"),
                commune,
                at(46.4620, 0.7255),
            ),
        ];
        let pairs = alike(&list);
        assert_eq!(pairs, [(0, 2)], "one name once its generic words are gone");
        assert_eq!(
            repeated(&pairs, |_, _| true),
            [2],
            "one campsite told twice, the better ranked kept"
        );
        assert!(repeated(&pairs, |_, _| false).is_empty(), "two places");
    }

    #[test]
    fn two_sources_tell_one_place_when_one_places_it_roughly() {
        let placed = |sources: &[&str], accuracy_m: f64| Placement {
            sources: sources.iter().map(|s| (*s).to_owned()).collect(),
            accuracy_m: Some(accuracy_m),
        };
        let osm = placed(&["osm"], 92.0);
        assert!(
            one_place(&osm, &placed(&["atout-france"], 250.0)),
            "Atout France places the campsite by its postal address, which accounts for the gap"
        );
        assert!(
            !one_place(&osm, &placed(&["community"], 10.0)),
            "a beach car park a visitor pinned 2 km from another of its name is another one"
        );
        assert!(
            !one_place(
                &placed(&["osm", "datatourisme"], 92.0),
                &placed(&["datatourisme"], 240.0)
            ),
            "one source lists them apart: two places"
        );
        assert!(
            !one_place(&Placement::default(), &placed(&["atout-france"], 250.0)),
            "a place whose records are not known is never left out"
        );
    }

    #[test]
    fn places_of_a_generic_name_another_commune_or_far_apart_are_not_alike() {
        let p = at(46.48, 0.73);
        let far = at(46.48 + 0.06, 0.73);
        let pairs = alike;
        assert!(
            pairs(&[
                listed(PlaceKind::Parking, Some("Parking"), Some("A"), p),
                listed(PlaceKind::Parking, Some("Parking"), Some("A"), p),
            ])
            .is_empty(),
            "a name of generic words tells two car parks apart no better than none"
        );
        assert!(
            pairs(&[
                listed(PlaceKind::Campsite, Some("Les Pins"), Some("A"), p),
                listed(PlaceKind::Campsite, Some("Les Pins"), Some("B"), p),
            ])
            .is_empty(),
            "two communes"
        );
        assert!(
            pairs(&[
                listed(PlaceKind::Campsite, Some("Les Pins"), Some("A"), p),
                listed(PlaceKind::Campsite, Some("Les Pins"), Some("A"), far),
            ])
            .is_empty(),
            "6.7 km apart"
        );
        assert!(
            pairs(&[
                listed(PlaceKind::Campsite, Some("Les Pins"), None, p),
                listed(PlaceKind::Campsite, Some("Les Pins"), None, p),
            ])
            .is_empty(),
            "no commune known"
        );
        assert!(
            pairs(&[
                listed(PlaceKind::Campsite, Some("Les Pins"), Some("A"), p),
                listed(PlaceKind::Parking, Some("Les Pins"), Some("A"), p),
            ])
            .is_empty(),
            "the campsite and its car park"
        );
    }

    #[test]
    fn a_place_told_three_times_keeps_its_first() {
        let p = at(46.48, 0.73);
        let pins = || listed(PlaceKind::Campsite, Some("Les Pins"), Some("A"), p);
        let list = [pins(), pins(), pins()];
        let pairs = alike(&list);
        assert_eq!(pairs, [(0, 1), (0, 2), (1, 2)]);
        assert_eq!(
            repeated(&pairs, |a, b| (a, b) != (0, 1)),
            [2],
            "the second is another place than the first and stays; the third is the first \
             told again"
        );
    }
}
