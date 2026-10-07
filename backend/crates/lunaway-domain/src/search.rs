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

use crate::{PlaceKind, conflation::normalize::GENERIC_WORDS};

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
fn lexeme(word: &str) -> String {
    format!("'{}'", word.replace('\\', "\\\\").replace('\'', "''"))
}

/// What a search for places asks, built from the words of its text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlaceQuery {
    slots: Vec<Slot>,
    kinds: Vec<PlaceKind>,
    by_kind: bool,
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

/// The lookalikes of `word` within the fewest edits, if that is close
/// enough for its length: none for three letters or fewer (a short word is
/// more likely the start of one being typed), one edit up to six letters,
/// two beyond. When no whole lookalike is that close and `word` is the
/// last of the query, the one being typed, the start of a lookalike counts
/// ("gerrardm" is one edit from the start of "gerardmer"); a whole word
/// comes first, so "bradere" is "bradiere", not the start of "brauerei".
fn within_reach(word: &str, lookalikes: &[String], last: bool) -> Vec<String> {
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
}
