//! What a search for points of interest and establishments asks, read from
//! its words.
//!
//! A query names points by their name or brand ("chez marcel", "lidl"), by
//! their kind in one of the app's six languages ("coiffeur", "Friseur",
//! "pizzeria"), or both ("boulangerie paul"), and may end on a town
//! ("pizzeria annecy", "lidl à lyon"). The words of a kind rank the points
//! of that kind first and filter nothing beside a name; a query made of the
//! words of kinds alone (articles and prepositions aside) asks for the
//! nearest points of those kinds, named so or not. The town, once the
//! database has found it among the towns of the search, becomes the point
//! the results are ranked around and leaves the words that filter.
//!
//! The words of a point are its folded name and brand, and three tokens no
//! word of a name can be (they hold `_`): `k_<kind>`, `g_<category>` and
//! `c_<cuisine>` for each cuisine it cooks (`lunaway_db::poi_search`). The
//! database turns a [`PoiQuery`] into text search queries over them, and
//! picks how to find the candidates with [`crate::search::lookup_path`].

use std::collections::BTreeSet;

use crate::{
    Position,
    poi::{PoiCategory, PoiKind},
    poi_words::{CATEGORY_PHRASES, CUISINE_PHRASES, KIND_PHRASES, STOP_WORDS},
    search::{LookupPath, QueryWord, WordShares, lexeme, lookup_path, within_reach},
};

/// Longest phrase of the vocabulary, in words ("expendedora de productos de
/// granja").
const MAX_PHRASE_WORDS: usize = 5;

/// Longest town a query may end on, in words ("aix en provence", "saint
/// jean de luz" is four).
pub const MAX_TOWN_WORDS: usize = 4;

/// One way a phrase of the query names points: some kinds, a cuisine of
/// some kinds, or a category.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Alternative {
    Kinds(Vec<PoiKind>),
    Cuisine(Vec<&'static str>, Vec<PoiKind>),
    Category(PoiCategory),
}

impl Alternative {
    /// The text search query of the alternative, over the tokens of the
    /// points' words.
    fn term(&self) -> String {
        match self {
            Self::Kinds(kinds) => any(kinds.iter().map(|k| kind_token(*k))),
            Self::Cuisine(cuisines, kinds) => format!(
                "{} & {}",
                any(cuisines.iter().map(|c| cuisine_token(c))),
                any(kinds.iter().map(|k| kind_token(*k)))
            ),
            Self::Category(c) => lexeme(&category_token(*c)),
        }
    }

    fn kinds(&self) -> Vec<PoiKind> {
        match self {
            Self::Kinds(kinds) | Self::Cuisine(_, kinds) => kinds.clone(),
            Self::Category(c) => c.kinds(),
        }
    }
}

/// `( 'a' | 'b' )`, or `'a'` alone.
fn any(tokens: impl Iterator<Item = String>) -> String {
    let quoted: Vec<String> = tokens.map(|t| lexeme(&t)).collect();
    if let [one] = quoted.as_slice() {
        return one.clone();
    }
    format!("( {} )", quoted.join(" | "))
}

/// The token of a kind among a point's words.
#[must_use]
pub fn kind_token(kind: PoiKind) -> String {
    format!("k_{}", kind.code())
}

/// The token of a category among a point's words.
#[must_use]
pub fn category_token(category: PoiCategory) -> String {
    format!("g_{}", category.code())
}

/// The token of a cuisine among a point's words.
#[must_use]
pub fn cuisine_token(cuisine: &str) -> String {
    format!("c_{cuisine}")
}

/// What one word of the query is.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Role {
    /// Part of a phrase that names points, the index of the phrase.
    Type(usize),
    /// An article, a preposition.
    Stop,
    /// A word of a name.
    Name,
}

/// One word of a query as it is matched: the typed word, as a prefix, or,
/// when no point has a word that starts with it, the words that look like
/// it.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Slot {
    words: Vec<String>,
    prefix: bool,
    role: Role,
}

impl Slot {
    fn term(&self, prefix: bool) -> String {
        if let [word] = self.words.as_slice() {
            let star = if prefix && self.prefix { ":*" } else { "" };
            return format!("{}{star}", lexeme(word));
        }
        let star = if prefix && self.prefix { ":*" } else { "" };
        let alternatives: Vec<String> = self
            .words
            .iter()
            .map(|w| format!("{}{star}", lexeme(w)))
            .collect();
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

/// The phrases of the vocabulary that start at `words[i]`, longest first:
/// each with its length in words and the ways it names points.
fn phrases_at(words: &[&str], i: usize) -> Option<(usize, Vec<Alternative>)> {
    for n in (1..=MAX_PHRASE_WORDS.min(words.len() - i)).rev() {
        let phrase = words[i..i + n].join(" ");
        let mut alternatives = Vec::new();
        if let Ok(at) = KIND_PHRASES.binary_search_by(|(p, _)| p.cmp(&phrase.as_str())) {
            alternatives.push(Alternative::Kinds(KIND_PHRASES[at].1.to_vec()));
        }
        if let Ok(at) = CUISINE_PHRASES.binary_search_by(|(p, _, _)| p.cmp(&phrase.as_str())) {
            let (_, cuisines, kinds) = CUISINE_PHRASES[at];
            alternatives.push(Alternative::Cuisine(cuisines.to_vec(), kinds.to_vec()));
        }
        if let Ok(at) = CATEGORY_PHRASES.binary_search_by(|(p, _)| p.cmp(&phrase.as_str())) {
            alternatives.push(Alternative::Category(CATEGORY_PHRASES[at].1));
        }
        if !alternatives.is_empty() {
            return Some((n, alternatives));
        }
    }
    None
}

/// What a search for points asks, built from the words of its text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PoiQuery {
    slots: Vec<Slot>,
    /// Per phrase that names points, the ways it does: a point must answer
    /// one way of every phrase.
    phrases: Vec<Vec<Alternative>>,
    by_kind: bool,
}

impl PoiQuery {
    /// The query of these words, in their order; `None` without a word.
    #[must_use]
    pub fn new(words: &[QueryWord]) -> Option<Self> {
        if words.is_empty() {
            return None;
        }
        let folded: Vec<&str> = words.iter().map(|w| w.word.as_str()).collect();
        let mut roles = vec![Role::Name; words.len()];
        let mut phrases = Vec::new();
        let mut i = 0;
        while i < folded.len() {
            if let Some((n, alternatives)) = phrases_at(&folded, i) {
                for role in &mut roles[i..i + n] {
                    *role = Role::Type(phrases.len());
                }
                phrases.push(alternatives);
                i += n;
            } else {
                if STOP_WORDS.contains(&folded[i]) {
                    roles[i] = Role::Stop;
                }
                i += 1;
            }
        }
        let last = words.len() - 1;
        let slots = words
            .iter()
            .zip(roles)
            .enumerate()
            .map(|(i, (w, role))| {
                if w.known || role != Role::Name {
                    return Slot {
                        words: vec![w.word.clone()],
                        prefix: true,
                        role,
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
                    role,
                }
            })
            .collect::<Vec<_>>();
        // A query of the words of kinds that ends on one asks for points of
        // those kinds; "boulangerie de la" is a name being typed.
        let by_kind = !phrases.is_empty()
            && !slots.iter().any(|s| s.role == Role::Name)
            && matches!(slots.last().map(|s| &s.role), Some(Role::Type(_)));
        Some(Self {
            slots,
            phrases,
            by_kind,
        })
    }

    /// The query of these words with every word of a name widened to
    /// itself and its lookalikes within reach (an edit up to six letters,
    /// two beyond, none under four): for a second look when the first found
    /// nothing, as a word some point bears may be a typo of the one meant
    /// ("boulangerei" for "boulangerie", which a shop also misspells), and
    /// another word of the text right ("mallet" kept, "malet" beside it).
    /// `None` without a word.
    #[must_use]
    pub fn widened(words: &[QueryWord]) -> Option<Self> {
        let mut query = Self::new(words)?;
        let last = query.slots.len() - 1;
        for (i, (slot, w)) in query.slots.iter_mut().zip(words).enumerate() {
            if slot.role != Role::Name {
                continue;
            }
            let len = w.word.chars().count();
            let reach = match len {
                0..=3 => continue,
                4..=6 => 1,
                _ => 2,
            };
            let mut near: Vec<(usize, &String)> = w
                .lookalikes
                .iter()
                .filter(|l| **l != w.word)
                .map(|l| (crate::search::edits(&w.word, l), l))
                .filter(|(d, _)| *d <= reach)
                .collect();
            near.sort();
            slot.words = std::iter::once(w.word.clone())
                .chain(near.into_iter().map(|(_, l)| l.clone()))
                .take(MAX_WIDENED)
                .collect();
            slot.prefix = i == last;
        }
        Some(query)
    }

    /// The words of the name a point must bear whole to bear the phrase:
    /// `None` when a word stands for several (a corrected one), any of
    /// which may be whole. When one of these is a whole word of no point,
    /// no point bears the phrase, nor the whole text.
    #[must_use]
    pub fn phrase_words(&self) -> Option<Vec<String>> {
        let mut out = Vec::new();
        for s in self.slots.iter().filter(|s| s.role == Role::Name) {
            match s.words.as_slice() {
                [word] => out.push(word.clone()),
                _ => return None,
            }
        }
        Some(out)
    }

    /// Whether the query asks for points of some kinds rather than by name.
    #[must_use]
    pub fn by_kind(&self) -> bool {
        self.by_kind
    }

    /// Whether some words of the query name a point (or are all it has).
    #[must_use]
    pub fn has_name(&self) -> bool {
        self.slots.iter().any(|s| s.role == Role::Name)
    }

    /// The kinds the query names, in their order, each once; empty for a
    /// query by name alone.
    #[must_use]
    pub fn kinds(&self) -> Vec<PoiKind> {
        let mut seen = BTreeSet::new();
        self.phrases
            .iter()
            .flatten()
            .flat_map(Alternative::kinds)
            .filter(|k| seen.insert(*k))
            .collect()
    }

    /// The words a point must hold to match by name: every word of a name,
    /// each as a prefix; the words of kinds and the articles when the query
    /// has nothing else (`"de la"` is a name being typed). Empty for a
    /// query by kind.
    #[must_use]
    pub fn filter(&self) -> String {
        if self.has_name() {
            self.and(|s| s.role == Role::Name)
        } else if self.by_kind {
            String::new()
        } else {
            self.and(|_| true)
        }
    }

    /// The tokens a point of the kinds the query names holds: one way of
    /// each phrase. Empty for a query by name alone.
    #[must_use]
    pub fn types(&self) -> String {
        // Kinds named twice are either ("boulangerie pâtisserie": a bakery
        // or a pastry shop), and so are cuisines ("pizza kebab"); a kind
        // and a cuisine are both ("restaurant pizza").
        let group = |cuisine: bool| -> Option<String> {
            let ways: Vec<String> = self
                .phrases
                .iter()
                .filter(|a| a.iter().any(|w| matches!(w, Alternative::Cuisine(..))) == cuisine)
                .flatten()
                .map(Alternative::term)
                .collect();
            match ways.as_slice() {
                [] => None,
                [one] => Some(one.clone()),
                _ => Some(format!(
                    "( {} )",
                    ways.iter()
                        .map(|w| format!("( {w} )"))
                        .collect::<Vec<_>>()
                        .join(" | ")
                )),
            }
        };
        match (group(false), group(true)) {
            (Some(kinds), Some(cuisines)) => format!("( {kinds} ) & ( {cuisines} )"),
            (Some(one), None) | (None, Some(one)) => one,
            (None, None) => String::new(),
        }
    }

    /// Every word that ranks by name, each as a prefix, in any order.
    #[must_use]
    pub fn every_word(&self) -> String {
        let (from, to) = self.ranked_span();
        self.and_in(from, to)
    }

    /// The words that rank by name in their order, each a whole word.
    #[must_use]
    pub fn phrase(&self) -> String {
        self.joined(false)
    }

    /// The words that rank by name in their order, the last one as a
    /// prefix: what is being typed.
    #[must_use]
    pub fn phrase_typed(&self) -> String {
        self.joined(true)
    }

    /// Every word of the query in its order, each a whole word: a point
    /// named exactly as typed ("Le Petit Bistrot") near the point asked
    /// comes before the others.
    #[must_use]
    pub fn whole_phrase(&self) -> String {
        let terms: Vec<String> = self.slots.iter().map(|s| s.term(false)).collect();
        terms.join(" <-> ")
    }

    /// The words the ranking by name reads, as a span of the query: from
    /// its first word of a name to its last when it also names kinds, so
    /// a bakery named "Paul" answers "boulangerie paul" as well as one
    /// named "Boulangerie Paul", and the nearer comes first (the kind
    /// ranks them both); every word otherwise.
    fn ranked_span(&self) -> (usize, usize) {
        let names: Vec<usize> = self
            .slots
            .iter()
            .enumerate()
            .filter(|(_, s)| s.role == Role::Name)
            .map(|(i, _)| i)
            .collect();
        match (names.first(), names.last()) {
            (Some(first), Some(last)) if !self.phrases.is_empty() => (*first, *last),
            _ => (0, self.slots.len() - 1),
        }
    }

    fn and_in(&self, from: usize, to: usize) -> String {
        let terms: Vec<String> = self.slots[from..=to].iter().map(|s| s.term(true)).collect();
        terms.join(" & ")
    }

    /// The words of [`Self::filter`] the index looks up: those held by few
    /// enough points for their lists to be read cheaply, or all of them
    /// when none is.
    #[must_use]
    pub fn lookup(&self, shares: &WordShares, points: f64) -> String {
        if !self.has_name() {
            return self.filter();
        }
        let rare = |s: &Slot| s.role == Role::Name && s.share(shares) * points <= LOOKUP_ROWS;
        if self.slots.iter().any(rare) {
            self.and(rare)
        } else {
            self.filter()
        }
    }

    /// How to find the candidates among `points`, `nearest` of them being
    /// wanted around a point when `near`. A query by kind is answered
    /// around a point only.
    #[must_use]
    pub fn path(&self, shares: &WordShares, points: f64, near: bool, nearest: u32) -> LookupPath {
        if self.by_kind {
            // The nearest of the kinds: from the index when few points are
            // of them, walking out from the point when many are.
            return match lookup_path(self.kind_rows(shares, points), points, true, nearest) {
                LookupPath::Index => LookupPath::Index,
                _ => LookupPath::Kind,
            };
        }
        lookup_path(self.estimated_rows(shares, points), points, near, nearest)
    }

    /// How many of `points` may match [`Self::filter`]: as many as hold its
    /// least common word.
    #[must_use]
    pub fn estimated_rows(&self, shares: &WordShares, points: f64) -> f64 {
        self.slots
            .iter()
            .filter(|s| !self.has_name() || s.role == Role::Name)
            .map(|s| s.share(shares))
            .fold(1.0, f64::min)
            * points
    }

    /// How many of `points` are of the kinds the query names: the shares
    /// of their tokens, the least common phrase deciding.
    #[must_use]
    pub fn kind_rows(&self, shares: &WordShares, points: f64) -> f64 {
        self.phrases
            .iter()
            .map(|alternatives| {
                alternatives
                    .iter()
                    .map(|a| match a {
                        Alternative::Kinds(kinds) => kinds
                            .iter()
                            .map(|k| shares.share(&kind_token(*k), false))
                            .sum::<f64>(),
                        Alternative::Cuisine(cuisines, _) => cuisines
                            .iter()
                            .map(|c| shares.share(&cuisine_token(c), false))
                            .sum::<f64>(),
                        Alternative::Category(c) => shares.share(&category_token(*c), false),
                    })
                    .sum::<f64>()
                    .min(1.0)
            })
            .fold(1.0, f64::min)
            * points
    }

    /// The trailing words that may be a town the query ends on, longest
    /// first, with how many words each takes: only when other words precede
    /// it that name a point ("pizzeria annecy", "lidl lyon"); never the
    /// whole query ("lyon" alone is the town, which the towns of the search
    /// list).
    #[must_use]
    pub fn town_candidates(&self) -> Vec<(String, usize)> {
        let n = self.slots.len();
        let mut out = Vec::new();
        for take in (1..=MAX_TOWN_WORDS.min(n.saturating_sub(1))).rev() {
            let rest = &self.slots[..n - take];
            let town = &self.slots[n - take..];
            if !rest
                .iter()
                .any(|s| matches!(s.role, Role::Name | Role::Type(_)))
            {
                continue;
            }
            // A town is typed words, not the end of a phrase of a kind.
            if town.iter().any(|s| matches!(s.role, Role::Type(_))) && take > 1 {
                continue;
            }
            let words: Vec<&str> = town
                .iter()
                .filter_map(|s| s.words.first().map(String::as_str))
                .collect();
            out.push((words.join(" "), take));
        }
        out
    }

    /// Whether a preposition of place stands right before the last `take`
    /// words ("lidl à lyon", "Friseur in Wien", "pizzeria near Dublin"):
    /// the text then says they are a place. An article or "de" says
    /// nothing: "Garage de la Gare" and "Café de Paris" are names.
    #[must_use]
    pub fn preposition_before(&self, take: usize) -> bool {
        self.slots
            .len()
            .checked_sub(take + 1)
            .and_then(|i| self.slots.get(i))
            .and_then(|s| s.words.first())
            .is_some_and(|w| PLACE_PREPOSITIONS.contains(&w.as_str()))
    }

    /// The query without its last `take` words, and the articles and
    /// prepositions before them ("pizzeria à annecy" without "annecy" is
    /// "pizzeria"); `None` when nothing is left.
    #[must_use]
    pub fn without_last(&self, take: usize) -> Option<Self> {
        let mut slots = self.slots[..self.slots.len().saturating_sub(take)].to_vec();
        while slots.last().is_some_and(|s| s.role == Role::Stop) {
            slots.pop();
        }
        if slots.is_empty() {
            return None;
        }
        let kept: BTreeSet<usize> = slots
            .iter()
            .filter_map(|s| match s.role {
                Role::Type(i) => Some(i),
                _ => None,
            })
            .collect();
        let phrases: Vec<Vec<Alternative>> = self
            .phrases
            .iter()
            .enumerate()
            .filter(|(i, _)| kept.contains(i))
            .map(|(_, a)| a.clone())
            .collect();
        // The phrases keep their order: renumber the slots' references.
        let remap: Vec<usize> = kept.iter().copied().collect();
        for s in &mut slots {
            if let Role::Type(i) = s.role {
                s.role = Role::Type(remap.iter().position(|j| *j == i).unwrap_or(0));
            }
        }
        let by_kind = !phrases.is_empty()
            && !slots.iter().any(|s| s.role == Role::Name)
            && matches!(slots.last().map(|s| &s.role), Some(Role::Type(_)));
        Some(Self {
            slots,
            phrases,
            by_kind,
        })
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
        let (from, to) = self.ranked_span();
        let last = self.slots.len() - 1;
        let terms: Vec<String> = self.slots[from..=to]
            .iter()
            .enumerate()
            .map(|(i, s)| s.term(typed && from + i == last))
            .collect();
        terms.join(" <-> ")
    }
}

/// The words one keystroke away from a typed one that trigrams miss: two
/// neighbouring letters swapped ("beuate" for "beaute" shares three
/// trigrams of eleven with it, under any useful threshold), or one letter
/// typed twice or by mistake ("garrage"). None under four letters, where
/// a word is more likely being typed.
#[must_use]
pub fn swaps_and_drops(word: &str) -> Vec<String> {
    let chars: Vec<char> = word.chars().collect();
    if chars.len() < 4 {
        return Vec::new();
    }
    let mut out = BTreeSet::new();
    for i in 0..chars.len() - 1 {
        if chars[i] != chars[i + 1] {
            let mut c = chars.clone();
            c.swap(i, i + 1);
            out.insert(c.into_iter().collect::<String>());
        }
    }
    if chars.len() >= 5 {
        for i in 0..chars.len() {
            let mut c = chars.clone();
            c.remove(i);
            out.insert(c.into_iter().collect::<String>());
        }
    }
    out.remove(word);
    out.into_iter().collect()
}

/// Most words a widened word stands for: itself and its nearest
/// lookalikes.
const MAX_WIDENED: usize = 6;

/// The prepositions that say the next words are a place, in the six
/// languages, folded ("à" is "a", "près" is "pres").
const PLACE_PREPOSITIONS: &[&str] = &[
    "a", "at", "au", "bei", "bij", "cerca", "dans", "en", "in", "nabij", "nahe", "near", "pres",
    "vicino",
];

/// Rows the GIN index reads cheaply for one word, as for the places
/// (`crate::search`): a word held by more points is checked on the rows
/// the others found, not looked up.
const LOOKUP_ROWS: f64 = 20_000.0;

/// The geohash lengths of the cells a point's words name (`h_<geohash>`,
/// `lunaway_poi_cells` in the database), finest first: cells of about 1.2
/// by 0.6 km, 4.9 by 4.9 km, 39 by 20 km and 156 by 156 km. A search
/// around a point reads the matches in the cells around it, from the
/// finest, before any farther: millions of points, and the matches of a
/// chain's name or a common kind across Europe, are never all read.
pub const CELL_LENGTHS: [usize; 4] = [6, 5, 4, 3];

const GEOHASH_ALPHABET: &[u8; 32] = b"0123456789bcdefghjkmnpqrstuvwxyz";

/// The geohash of `at` of `length` characters, as PostGIS's `ST_GeoHash`
/// writes it.
#[must_use]
pub fn geohash(at: Position, length: usize) -> String {
    let (mut lat, mut lon) = ((-90.0_f64, 90.0_f64), (-180.0_f64, 180.0_f64));
    let mut out = String::with_capacity(length);
    let (mut bits, mut value, mut on_lon) = (0, 0_usize, true);
    while out.len() < length {
        let (range, x) = if on_lon {
            (&mut lon, at.lon())
        } else {
            (&mut lat, at.lat())
        };
        let mid = f64::midpoint(range.0, range.1);
        value <<= 1;
        if x >= mid {
            value |= 1;
            range.0 = mid;
        } else {
            range.1 = mid;
        }
        on_lon = !on_lon;
        bits += 1;
        if bits == 5 {
            out.push(char::from(GEOHASH_ALPHABET[value]));
            bits = 0;
            value = 0;
        }
    }
    out
}

/// The size in degrees of a cell of `length` characters: latitude, then
/// longitude.
fn cell_degrees(length: usize) -> (f64, f64) {
    let bits = 5 * length;
    let lat_bits = i32::try_from(bits / 2).unwrap_or(i32::MAX);
    let lon_bits = i32::try_from(bits - bits / 2).unwrap_or(i32::MAX);
    (180.0 / 2_f64.powi(lat_bits), 360.0 / 2_f64.powi(lon_bits))
}

/// The text search query of the nine cells of `length` characters around
/// `at` (its own and its eight neighbours): `( 'h_u09tv' | ... )`.
#[must_use]
pub fn cells_around(at: Position, length: usize) -> String {
    let (dlat, dlon) = cell_degrees(length);
    let mut cells = BTreeSet::new();
    for dy in [-1.0, 0.0, 1.0] {
        for dx in [-1.0, 0.0, 1.0] {
            let lat = (at.lat() + dy * dlat).clamp(-89.999_999, 89.999_999);
            let lon = (at.lon() + dx * dlon + 540.0).rem_euclid(360.0) - 180.0;
            if let Ok(p) = Position::new(lat, lon) {
                cells.insert(format!("h_{}", geohash(p, length)));
            }
        }
    }
    let terms: Vec<String> = cells.iter().map(|c| lexeme(c)).collect();
    format!("( {} )", terms.join(" | "))
}

/// How far from `at` every point lies inside [`cells_around`]: a point
/// nearer than this is in one of the nine cells, so the nearest matches
/// found there within this distance are the nearest of all.
#[must_use]
pub fn cells_reach_m(at: Position, length: usize) -> f64 {
    let (dlat, dlon) = cell_degrees(length);
    // A degree of the sphere PostGIS measures distances on, a little short
    // of a degree at the equator, so the reach is never overstated.
    let metres_a_degree = 111_195.0;
    (dlat * metres_a_degree).min(dlon * metres_a_degree * at.lat().to_radians().cos())
}

/// How a search's points answer its text, for the app to order its
/// sections.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PoiMatch {
    /// The text asks for kinds: the nearest of them.
    Kind,
    /// The best point holds every word of the text, in order.
    Name,
    /// Points hold some of the words.
    Partial,
    /// None.
    None,
}

/// Words that start a postal address in the six languages: a text that
/// starts with one, or with a number, asks for an address, and a point
/// named after the street does not come before it.
const STREET_WORDS: &[&str] = &[
    "allee",
    "avenida",
    "avenue",
    "boulevard",
    "calle",
    "camino",
    "carrer",
    "chemin",
    "corso",
    "gasse",
    "impasse",
    "laan",
    "piazza",
    "place",
    "plaza",
    "plein",
    "quai",
    "road",
    "route",
    "rue",
    "strasse",
    "straat",
    "street",
    "via",
    "viale",
    "weg",
];

/// Whether a folded text reads as a postal address.
#[must_use]
pub fn looks_like_address(words: &[&str]) -> bool {
    words.first().is_some_and(|w| {
        w.chars().next().is_some_and(|c| c.is_ascii_digit()) || STREET_WORDS.contains(w)
    })
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

    fn query(words: &[&str]) -> PoiQuery {
        let words: Vec<QueryWord> = words.iter().map(|w| known(w)).collect();
        PoiQuery::new(&words).expect("words")
    }

    #[test]
    fn the_cells_around_a_point_are_its_own_and_its_neighbours() {
        let jutland = Position::new(57.64911, 10.40744).expect("position");
        assert_eq!(
            geohash(jutland, 11),
            "u4pruydqqvj",
            "the reference example of the geohash"
        );
        let paris = Position::new(48.85, 2.35).expect("position");
        let around = cells_around(paris, 5);
        assert_eq!(around.matches("'h_").count(), 9);
        assert!(around.contains(&format!("'h_{}'", geohash(paris, 5))));
        // Across the antimeridian, the neighbours wrap.
        let fiji = Position::new(-17.7, 179.99).expect("position");
        let wrapped = cells_around(fiji, 3);
        assert_eq!(wrapped.matches("'h_").count(), 9);
        assert!(
            wrapped.contains("'h_r") && wrapped.contains("'h_2"),
            "{wrapped}"
        );
        // Within the reach, every point is in one of the nine cells.
        let reach = cells_reach_m(paris, 5);
        assert!((3_000.0..5_000.0).contains(&reach), "{reach}");
        for (dlat, dlon) in [(0.03, 0.0), (-0.03, 0.0), (0.0, 0.04), (0.02, -0.03)] {
            let p = Position::new(48.85 + dlat, 2.35 + dlon).expect("position");
            if p.distance_m(paris) <= reach {
                assert!(around.contains(&format!("'h_{}'", geohash(p, 5))), "{p:?}");
            }
        }
    }

    #[test]
    fn the_vocabulary_is_sorted_folded_and_names_every_kind() {
        let sorted = |keys: Vec<&str>| keys.windows(2).all(|w| w[0] < w[1]);
        assert!(sorted(KIND_PHRASES.iter().map(|p| p.0).collect()));
        assert!(sorted(CUISINE_PHRASES.iter().map(|p| p.0).collect()));
        assert!(sorted(CATEGORY_PHRASES.iter().map(|p| p.0).collect()));
        let folded = |p: &str| {
            !p.is_empty()
                && p.split(' ').count() <= MAX_PHRASE_WORDS
                && p.split(' ').all(|w| {
                    !w.is_empty()
                        && w.chars()
                            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
                })
        };
        for (p, _) in KIND_PHRASES {
            assert!(
                folded(p),
                "{p}: folded as a query is, or a query never meets it"
            );
        }
        for (p, _, _) in CUISINE_PHRASES {
            assert!(folded(p), "{p}");
        }
        let named: BTreeSet<PoiKind> = KIND_PHRASES
            .iter()
            .flat_map(|(_, k)| k.iter().copied())
            .collect();
        for k in PoiKind::ALL {
            if *k != PoiKind::Shop {
                assert!(
                    named.contains(k),
                    "{k}: no word names it, a search by kind never finds it"
                );
            }
        }
    }

    #[test]
    fn a_kind_in_any_language_asks_for_the_nearest_of_it() {
        for w in [
            &["coiffeur"][..],
            &["friseur"],
            &["peluqueria"],
            &["parrucchiere"],
            &["kapper"],
            &["hairdresser"],
        ] {
            let q = query(w);
            assert!(q.by_kind(), "{w:?}");
            assert_eq!(q.kinds(), [PoiKind::Hairdresser], "{w:?}");
            assert_eq!(q.types(), "'k_hairdresser'");
            assert_eq!(q.filter(), "", "a query by kind filters no name");
        }
        let salon = query(&["salon", "de", "coiffure"]);
        assert!(salon.by_kind(), "a phrase of three words");
        assert_eq!(salon.kinds(), [PoiKind::Hairdresser]);
    }

    #[test]
    fn a_cuisine_asks_for_the_places_that_cook_it() {
        let q = query(&["pizzeria"]);
        assert!(q.by_kind());
        assert_eq!(
            q.types(),
            "'c_pizza' & ( 'k_restaurant' | 'k_fast_food' )",
            "a pizzeria is a restaurant or a fast food that cooks pizza"
        );
        let italian = query(&["restaurant", "italien"]);
        assert!(italian.by_kind());
        assert_eq!(
            italian.types(),
            "'c_italian' & 'k_restaurant'",
            "the longest phrase: an Italian restaurant"
        );
        let both = query(&["restaurant", "pizza"]);
        assert_eq!(
            both.types(),
            "( 'k_restaurant' ) & ( 'c_pizza' & ( 'k_restaurant' | 'k_fast_food' ) )",
            "a kind and a cuisine: both"
        );
        let either = query(&["boulangerie", "patisserie"]);
        assert_eq!(
            either.types(),
            "( ( 'k_bakery' ) | ( 'k_pastry' ) )",
            "two kinds: either, no shop is both"
        );
    }

    #[test]
    fn a_name_beside_a_kind_filters_and_the_kind_ranks() {
        let q = query(&["boulangerie", "paul"]);
        assert!(!q.by_kind());
        assert_eq!(
            q.filter(),
            "'paul':*",
            "a Paul that is no bakery still matches"
        );
        assert_eq!(q.types(), "'k_bakery'", "the bakeries rank first");
        assert_eq!(
            q.phrase(),
            "'paul'",
            "a bakery named Paul answers as well as one named Boulangerie Paul"
        );
        assert_eq!(q.phrase_typed(), "'paul':*");
        let gare = query(&["boulangerie", "de", "la", "gare"]);
        assert_eq!(gare.filter(), "'gare':*");
        assert_eq!(
            gare.phrase(),
            "'gare'",
            "the span of the name's words; the articles before it go with the kind"
        );
        let typed_name = query(&["lidl", "express"]);
        assert_eq!(
            typed_name.phrase_typed(),
            "'lidl' <-> 'express':*",
            "a name alone ranks whole"
        );
        let typed = query(&["boulangerie", "de", "la"]);
        assert!(
            !typed.by_kind(),
            "a text that ends on an article is a name being typed"
        );
        assert_eq!(typed.filter(), "'boulangerie':* & 'de':* & 'la':*");
        let name = query(&["chez", "marcel"]);
        assert!(!name.by_kind() && name.kinds().is_empty());
        assert_eq!(name.filter(), "'chez':* & 'marcel':*");
        assert_eq!(name.types(), "");
    }

    #[test]
    fn a_query_may_end_on_a_town() {
        let q = query(&["pizzeria", "a", "annecy"]);
        assert_eq!(
            q.town_candidates(),
            [("a annecy".to_owned(), 2), ("annecy".to_owned(), 1)],
            "longest first; the database finds which is a town"
        );
        let without = q.without_last(1).expect("a kind is left");
        assert!(without.by_kind(), "the preposition goes with the town");
        assert_eq!(
            without.types(),
            "'c_pizza' & ( 'k_restaurant' | 'k_fast_food' )"
        );
        let lidl = query(&["lidl", "lyon"]);
        assert_eq!(lidl.town_candidates(), [("lyon".to_owned(), 1)]);
        assert_eq!(lidl.without_last(1).expect("lidl").filter(), "'lidl':*");
        assert!(
            query(&["lyon"]).town_candidates().is_empty(),
            "the whole query is a town the towns of the search list"
        );
        assert!(
            query(&["saint", "jean", "de", "luz"])
                .town_candidates()
                .iter()
                .all(|(_, take)| *take < 4),
            "nothing would be left to search around it"
        );
    }

    #[test]
    fn a_typo_in_a_name_is_corrected_not_in_a_kind() {
        let words = [QueryWord {
            word: "carefour".into(),
            known: false,
            lookalikes: vec!["carrefour".into(), "carrefours".into()],
        }];
        assert_eq!(
            PoiQuery::new(&words).expect("words").filter(),
            "'carrefour'",
            "one edit away"
        );
    }

    #[test]
    fn a_second_look_widens_every_word_of_a_name_to_its_lookalikes() {
        let words = [
            QueryWord {
                word: "pharmaice".into(),
                known: false,
                lookalikes: vec!["pharmacie".into(), "pharmacies".into(), "pharma".into()],
            },
            QueryWord {
                word: "mallet".into(),
                known: false,
                lookalikes: vec![
                    "malet".into(),
                    "mallets".into(),
                    "mullet".into(),
                    "ballet".into(),
                ],
            },
        ];
        let q = PoiQuery::widened(&words).expect("words");
        assert_eq!(
            q.filter(),
            "( 'pharmaice' | 'pharmacie' | 'pharmacies' ) & ( 'mallet':* | 'ballet':* | 'malet':* | 'mallets':* | 'mullet':* )",
            "each word with what lies within an edit or two, itself first; the last as typed"
        );
    }

    #[test]
    fn a_swap_or_an_extra_letter_is_one_keystroke_away() {
        let v = swaps_and_drops("beuate");
        assert!(v.contains(&"beaute".to_owned()), "two letters swapped");
        assert!(
            swaps_and_drops("garrage").contains(&"garage".to_owned()),
            "a letter twice"
        );
        assert!(!v.contains(&"beuate".to_owned()));
        assert!(
            swaps_and_drops("bar").is_empty(),
            "a short word is being typed"
        );
    }

    #[test]
    fn the_cheaper_way_is_chosen_from_the_shares_of_the_tokens() {
        let shares = WordShares::new(
            vec!["k_restaurant".into(), "k_distillery".into()],
            &[0.15, 0.000_02],
        );
        let points = 7_000_000.0;
        assert_eq!(
            query(&["restaurant"]).path(&shares, points, true, 20),
            LookupPath::Kind,
            "a common kind: walking out from the point meets one point in seven"
        );
        assert_eq!(
            query(&["distillerie"]).path(&shares, points, true, 20),
            LookupPath::Index,
            "a rare one: every one of them from the index, the nearest first"
        );
    }

    #[test]
    fn an_address_is_told_from_a_name() {
        assert!(looks_like_address(&["10", "rue", "de", "la", "republique"]));
        assert!(looks_like_address(&["rue", "de", "la", "paix"]));
        assert!(!looks_like_address(&["chez", "marcel"]));
    }
}
