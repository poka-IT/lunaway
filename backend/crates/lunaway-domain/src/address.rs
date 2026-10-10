//! Postal addresses found by a geocoder for the map's search: what a match
//! is, and how the matches of several geocoders become one short list under
//! the places.
//!
//! The places always come first; the addresses follow, without the towns
//! the search already lists (the app shows those as towns), and without the
//! same address twice. A match in the town the text names comes before a
//! match elsewhere, and in that town the exact house number before its
//! street; a match of another country than that town's, or than the one the
//! text ends on, is left out; what the text does not decide keeps the
//! geocoders' own order, the nearest geocoder's answer to the point the
//! search ranks from first.

use std::{collections::HashMap, ops::Range};

use crate::{Position, conflation::normalize::fold};

/// What an address match designates, from the most precise to the widest.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AddressKind {
    /// A house number on a street.
    HouseNumber,
    /// A street, at its middle.
    Street,
    /// A named place smaller than a town: a hamlet, a "lieu-dit", a
    /// district.
    Locality,
    /// A town, a village, a municipality.
    Town,
    /// The area of a postcode.
    Postcode,
    /// A county, a region, a state, a country.
    Region,
}

/// Where an address match comes from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AddressSource {
    /// The Base Adresse Nationale (France), through IGN's Géoplateforme.
    Ban,
    /// OpenStreetMap, through Lunaway's Photon geocoder.
    Osm,
}

/// One match of a geocoder.
#[derive(Debug, Clone, PartialEq)]
pub struct AddressMatch {
    /// What it designates.
    pub kind: AddressKind,
    /// The first line: the house number and street, the street, or the
    /// name of the locality, town or area.
    pub name: String,
    /// Postcode, when known.
    pub postcode: Option<String>,
    /// The town, when the match is inside one (null for a town itself).
    pub city: Option<String>,
    /// The wider area, for telling two matches of the same name apart
    /// ("77, Seine-et-Marne, Île-de-France").
    pub context: Option<String>,
    /// ISO 3166-1 alpha-2 country code, upper case, when known.
    pub country_code: Option<String>,
    /// Where it is.
    pub position: Position,
    /// Its source.
    pub source: AddressSource,
    /// How well it matches the text, 0 to 1, as its geocoder rates it;
    /// null when the geocoder gives no rating.
    pub score: Option<f64>,
}

impl AddressMatch {
    /// The town this match stands for, when it is one: a town, or the area
    /// of a postcode.
    fn as_town(&self) -> Option<&str> {
        match self.kind {
            AddressKind::Town => Some(&self.name),
            AddressKind::Postcode => Some(self.city.as_deref().unwrap_or(&self.name)),
            _ => None,
        }
    }

    /// The town the match lies in, or is: what a text naming a town is
    /// compared with.
    fn town(&self) -> Option<&str> {
        match self.kind {
            AddressKind::Town => Some(&self.name),
            AddressKind::Region => None,
            _ => self.city.as_deref(),
        }
    }
}

/// A town the search already lists: the app shows it among the towns,
/// so the addresses leave it out.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShownTown {
    folded: String,
    postcode: Option<String>,
    country_code: Option<String>,
}

impl ShownTown {
    /// The town `name`, with its postcode and its country (ISO 3166-1
    /// alpha-2) when known.
    #[must_use]
    pub fn new(name: &str, postcode: Option<&str>, country_code: Option<&str>) -> Self {
        Self {
            folded: fold(name),
            postcode: postcode.map(str::to_owned),
            country_code: country_code.map(str::to_owned),
        }
    }
}

/// Two matches closer than this, of the same kind and the same folded
/// name, are the same address told by two sources, metres.
const SAME_ADDRESS_M: f64 = 150.0;

/// A rating below this share of the best rating of the same geocoder is a
/// weak match: the geocoder fills its list with them when the text names
/// one address precisely ("6 Rue de Rome" for "6 rue du Dôme").
const WEAK_SHARE: f64 = 0.75;

/// A rating below this is no match at all, whatever the others: the BAN
/// answers a text naming a street abroad with a French one of a remote
/// likeness ("Neuhof Hinter Den Gaerten, Berling" rated 0.34 for "unter den
/// linden 77 berlin"), while a text still being typed rates its right
/// match low ("Boulevard du Port, Amiens" 0.42 for "bd du po amiens");
/// measured on 2026-10-07. Wrong partial answers reach 0.39: the threshold
/// trades some of them shown against right ones lost.
const MIN_SCORE: f64 = 0.35;

/// Two postcodes of the same area ([`area`]), each with its country: a
/// French department tells the homonyms apart (Viviers 07220, 89700,
/// 57590) where a town of several postcodes (Lyon 69001 to 69009) stays
/// one. Unknown on either side, the same.
fn same_area(
    a: Option<&str>,
    a_country: Option<&str>,
    b: Option<&str>,
    b_country: Option<&str>,
) -> bool {
    match (a, b) {
        (Some(a), Some(b)) => area(a, a_country) == area(b, b_country),
        _ => true,
    }
}

/// The area of a postcode: in France (or a country unknown) a postcode of
/// five digits gives its department as the towns of the search name it
/// (`lunaway-db/src/towns.rs`): three digits overseas (97410 La Réunion,
/// 97250 Martinique), 2A or 2B in Corsica (20000 to 20199 the south);
/// any other postcode, its first two characters.
fn area<'a>(postcode: &'a str, country: Option<&str>) -> Option<&'a str> {
    department(postcode, country).or_else(|| postcode.get(..2))
}

/// The French department of a postcode of five digits in France (or a
/// country unknown): its first two digits, three overseas, 2A or 2B in
/// Corsica; none for any other postcode.
fn department<'a>(postcode: &'a str, country: Option<&str>) -> Option<&'a str> {
    let french = country.is_none_or(|c| c.eq_ignore_ascii_case("FR"));
    if !french || postcode.len() != 5 || !postcode.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    if postcode.starts_with("97") {
        return postcode.get(..3);
    }
    if postcode.starts_with("20") {
        return Some(if postcode < "20200" { "2A" } else { "2B" });
    }
    postcode.get(..2)
}

/// The farthest apart two matches of one street name in one town are still
/// segments of that street, metres: OpenStreetMap cuts a street where its
/// tags change, a few kilometres at most, and two towns of one name are
/// farther apart.
const SAME_STREET_M: f64 = 10_000.0;

/// The list shown under the places, at most `max`, from `answers`, the
/// matches of each geocoder in that geocoder's own order:
///
/// 1. without the weak matches of a rated geocoder (under [`MIN_SCORE`], or
///    far below its best), the towns already in `towns`, and the same
///    address twice, the segments of one street included (the first kept);
/// 2. the answers merged, the one whose next match is nearest to `near`
///    first (one after the other without a point): a geocoder ranks its
///    own matches better than a distance does, and the nearest answer
///    leads when the text names no place;
/// 3. without the matches of another country than the one the text names
///    ([`elsewhere`]): when it names a town some matches lie in, or a
///    country some lie in, a match of another country is none of them;
/// 4. then ordered by what the text says ([`TextFit`]): the town it names
///    first, then the matches whose every word it holds, the matches of one
///    town together (a town by its name and postcode area, in the order it
///    first appears; a match without a town is a group of its own), a
///    house number before its street.
///
/// Measured on 65 addresses of France and Europe typed with their town,
/// the map on Viviers, on 2026-10-08: the town typed came first 61 times
/// instead of 43, and the exact address 49 times instead of 30, against
/// the nearest-first order this replaced.
#[must_use]
pub fn rank(
    answers: Vec<Vec<AddressMatch>>,
    text: &str,
    towns: &[ShownTown],
    near: Option<Position>,
    max: usize,
) -> Vec<AddressMatch> {
    let best = |source: AddressSource| {
        answers
            .iter()
            .flatten()
            .filter(|m| m.source == source)
            .filter_map(|m| m.score)
            .fold(None, |acc: Option<f64>, s| {
                Some(acc.map_or(s, |a| a.max(s)))
            })
    };
    let best_ban = best(AddressSource::Ban);
    let best_osm = best(AddressSource::Osm);
    let kept = |m: &AddressMatch| {
        let top = match m.source {
            AddressSource::Ban => best_ban,
            AddressSource::Osm => best_osm,
        };
        if let Some(score) = m.score
            && (score < MIN_SCORE || top.is_some_and(|top| score < top * WEAK_SHARE))
        {
            return false;
        }
        m.as_town().is_none_or(|town| {
            let folded = fold(town);
            !towns.iter().any(|t| {
                t.folded == folded
                    && same_area(
                        t.postcode.as_deref(),
                        t.country_code.as_deref(),
                        m.postcode.as_deref(),
                        m.country_code.as_deref(),
                    )
            })
        })
    };
    let answers: Vec<Vec<AddressMatch>> = answers
        .into_iter()
        .map(|a| a.into_iter().filter(|m| kept(m)).collect())
        .collect();
    // Each with its folded name and town, folded once.
    let mut unique: Vec<(AddressMatch, String, Option<String>)> = Vec::new();
    for m in merge(answers, near) {
        let key = fold(&m.name);
        let town = m.town().map(fold);
        let twice = unique.iter().any(|(k, k_key, k_town)| {
            k.kind == m.kind
                && *k_key == key
                && (k.position.distance_m(m.position) < SAME_ADDRESS_M
                    || (m.kind == AddressKind::Street
                        && town.is_some()
                        && *k_town == town
                        && same_area(
                            k.postcode.as_deref(),
                            k.country_code.as_deref(),
                            m.postcode.as_deref(),
                            m.country_code.as_deref(),
                        )
                        && k.position.distance_m(m.position) < SAME_STREET_M))
        });
        if !twice {
            unique.push((m, key, town));
        }
    }
    let words = TextWords::new(text);
    let read: Vec<Reading> = unique.iter().map(|(m, ..)| words.read(m)).collect();
    let away = elsewhere(&unique.iter().map(|(m, ..)| m).collect::<Vec<_>>(), &read);
    let mut groups: HashMap<(String, Option<String>), usize> = HashMap::new();
    let mut next_group = 0;
    let mut keyed: Vec<(TextFit, usize, u8, usize, AddressMatch)> = unique
        .into_iter()
        .zip(read)
        .enumerate()
        .filter(|(i, _)| !away.contains(i))
        .map(|(i, ((m, _, town), reading))| {
            let fit = reading.fit;
            let mut new_group = || {
                next_group += 1;
                next_group
            };
            // A town by its name and, in France, its department: the
            // homonyms of two departments are two groups. Abroad the name
            // alone, the postcodes of one city starting apart (Copenhagen
            // 1074 and 1100), and a match without a postcode with the
            // others of its town (a square of Florence beside its house
            // numbers): measured on production, a group per postcode put
            // the street before its house number in both. A match without
            // a town is a group of its own, in the order it comes.
            let group = match town {
                Some(t) => {
                    let department = m
                        .postcode
                        .as_deref()
                        .and_then(|p| department(p, m.country_code.as_deref()))
                        .map(str::to_owned);
                    *groups.entry((t, department)).or_insert_with(new_group)
                }
                None => new_group(),
            };
            (fit, group, kind_rank(m.kind), i, m)
        })
        .collect();
    keyed.sort_by_key(|k| (k.0, k.1, k.2, k.3));
    keyed.truncate(max);
    keyed.into_iter().map(|(.., m)| m).collect()
}

/// The answers merged into one list, each keeping its order: the answer
/// whose next match is nearest to `near` gives the next one (the earlier
/// answer on a tie), or, without a point, one answer after the other.
fn merge(answers: Vec<Vec<AddressMatch>>, near: Option<Position>) -> Vec<AddressMatch> {
    let Some(near) = near else {
        return answers.into_iter().flatten().collect();
    };
    let mut answers: Vec<std::collections::VecDeque<AddressMatch>> =
        answers.into_iter().map(Into::into).collect();
    let mut out = Vec::new();
    loop {
        let next = answers
            .iter()
            .enumerate()
            .filter_map(|(i, a)| a.front().map(|m| (m.position.distance_m(near), i)))
            .min_by(|a, b| a.0.total_cmp(&b.0).then(a.1.cmp(&b.1)));
        let Some((_, i)) = next else { break };
        if let Some(m) = answers
            .get_mut(i)
            .and_then(std::collections::VecDeque::pop_front)
        {
            out.push(m);
        }
    }
    out
}

/// The order of the kinds in one town: the most precise first.
fn kind_rank(kind: AddressKind) -> u8 {
    match kind {
        AddressKind::HouseNumber => 0,
        AddressKind::Street => 1,
        AddressKind::Locality => 2,
        AddressKind::Town | AddressKind::Postcode => 3,
        AddressKind::Region => 4,
    }
}

/// How well a match fits the text, best first: the town it lies in named
/// by the text (in the words its own name does not account for, so that
/// "Rue de Bruxelles" in Toulouse is not in the Brussels the text names),
/// exactly or in another language ([`close_word`]), then whether the text
/// holds every word of its name.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
struct TextFit {
    town: TownNamed,
    name_missing_words: bool,
}

/// Whether the text names the town of a match.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum TownNamed {
    Exactly,
    Closely,
    No,
}

/// What the text says of one match: how well it fits, the country it names
/// in the words the match's name leaves, the positions of the words its
/// town is read from, and those its name accounts for.
#[derive(Debug, Clone)]
struct Reading {
    fit: TextFit,
    country: Option<&'static str>,
    town_words: Option<Range<usize>>,
    taken: Vec<bool>,
}

/// The positions of the matches of another country than the one the text
/// names, when some match lies in it: the country of the town the text
/// names (Lyon, France), or the country it ends on ("... Maroc"). A match
/// of an unknown country stays, and so does one in a town or a country the
/// text names ("... Andorra": Andorra, a town of Spain, and the country
/// Andorra). So does a match whose
/// name holds the words a town is read from: for "rue de Rome", the BAN's
/// Rue de Rome in Marseille beside the city of Rome. For "10 rue de la
/// Republique Lyon", the Photon of Morocco answered the houses of three
/// embassies of Rabat, found by the "République" of the embassies' names,
/// which filled the list after Lyon's two addresses (audit of
/// 2026-10-10).
fn elsewhere(matches: &[&AddressMatch], read: &[Reading]) -> Vec<usize> {
    let present = |code: &str| {
        matches
            .iter()
            .any(|m| m.country_code.as_deref() == Some(code))
    };
    let named: Vec<(&str, &Range<usize>)> = matches
        .iter()
        .zip(read)
        .filter(|(_, r)| r.fit.town != TownNamed::No)
        .filter_map(|(m, r)| m.country_code.as_deref().zip(r.town_words.as_ref()))
        .collect();
    matches
        .iter()
        .zip(read)
        .enumerate()
        .filter(|(_, (m, r))| {
            let Some(country) = m.country_code.as_deref() else {
                return false;
            };
            if r.fit.town != TownNamed::No || r.country == Some(country) {
                return false;
            }
            let other_country = r.country.is_some_and(|c| c != country && present(c));
            let other_town = !named.is_empty()
                && named.iter().all(|(c, _)| *c != country)
                && !named
                    .iter()
                    .any(|(_, words)| r.taken[words.start..words.end].iter().any(|t| *t));
            other_country || other_town
        })
        .map(|(i, _)| i)
        .collect()
}

/// The most words of a country's name ([`COUNTRY_NAMES`]).
const MAX_COUNTRY_WORDS: usize = 3;

/// The countries the geocoders cover (Europe and Morocco), by their names
/// folded, in the six languages of the app and their own, and their ISO
/// 3166-1 alpha-2 codes. A name that is a common word of another of these
/// languages is left out: "Island", Iceland in German, ends many a text
/// that names an island.
const COUNTRY_NAMES: &[(&str, &str)] = &[
    ("albania", "AL"),
    ("albanie", "AL"),
    ("albanien", "AL"),
    ("shqiperia", "AL"),
    ("andorra", "AD"),
    ("andorre", "AD"),
    ("austria", "AT"),
    ("autriche", "AT"),
    ("osterreich", "AT"),
    ("oostenrijk", "AT"),
    ("belgium", "BE"),
    ("belgique", "BE"),
    ("belgien", "BE"),
    ("belgio", "BE"),
    ("belgica", "BE"),
    ("belgie", "BE"),
    ("bosnia", "BA"),
    ("bosnie", "BA"),
    ("bosnien", "BA"),
    ("bosnia and herzegovina", "BA"),
    ("bosnie herzegovine", "BA"),
    ("bosnia ed erzegovina", "BA"),
    ("bosnia y herzegovina", "BA"),
    ("bosnie en herzegovina", "BA"),
    ("bosnien und herzegowina", "BA"),
    ("bulgaria", "BG"),
    ("bulgarie", "BG"),
    ("bulgarien", "BG"),
    ("bulgarije", "BG"),
    ("croatia", "HR"),
    ("croatie", "HR"),
    ("kroatien", "HR"),
    ("croazia", "HR"),
    ("croacia", "HR"),
    ("kroatie", "HR"),
    ("hrvatska", "HR"),
    ("cyprus", "CY"),
    ("chypre", "CY"),
    ("zypern", "CY"),
    ("cipro", "CY"),
    ("chipre", "CY"),
    ("czechia", "CZ"),
    ("czech republic", "CZ"),
    ("tchequie", "CZ"),
    ("republique tcheque", "CZ"),
    ("tschechien", "CZ"),
    ("cechia", "CZ"),
    ("repubblica ceca", "CZ"),
    ("chequia", "CZ"),
    ("republica checa", "CZ"),
    ("tsjechie", "CZ"),
    ("cesko", "CZ"),
    ("denmark", "DK"),
    ("danemark", "DK"),
    ("danimarca", "DK"),
    ("dinamarca", "DK"),
    ("denemarken", "DK"),
    ("danmark", "DK"),
    ("estonia", "EE"),
    ("estonie", "EE"),
    ("estland", "EE"),
    ("eesti", "EE"),
    ("finland", "FI"),
    ("finlande", "FI"),
    ("finnland", "FI"),
    ("finlandia", "FI"),
    ("suomi", "FI"),
    ("france", "FR"),
    ("frankreich", "FR"),
    ("francia", "FR"),
    ("frankrijk", "FR"),
    ("germany", "DE"),
    ("allemagne", "DE"),
    ("deutschland", "DE"),
    ("germania", "DE"),
    ("alemania", "DE"),
    ("duitsland", "DE"),
    ("greece", "GR"),
    ("grece", "GR"),
    ("griechenland", "GR"),
    ("grecia", "GR"),
    ("griekenland", "GR"),
    ("hungary", "HU"),
    ("hongrie", "HU"),
    ("ungarn", "HU"),
    ("ungheria", "HU"),
    ("hungria", "HU"),
    ("hongarije", "HU"),
    ("magyarorszag", "HU"),
    ("iceland", "IS"),
    ("islande", "IS"),
    ("islanda", "IS"),
    ("islandia", "IS"),
    ("ijsland", "IS"),
    ("ireland", "IE"),
    ("irlande", "IE"),
    ("irland", "IE"),
    ("irlanda", "IE"),
    ("ierland", "IE"),
    ("eire", "IE"),
    ("italy", "IT"),
    ("italie", "IT"),
    ("italien", "IT"),
    ("italia", "IT"),
    ("latvia", "LV"),
    ("lettonie", "LV"),
    ("lettland", "LV"),
    ("lettonia", "LV"),
    ("letonia", "LV"),
    ("letland", "LV"),
    ("latvija", "LV"),
    ("liechtenstein", "LI"),
    ("lithuania", "LT"),
    ("lituanie", "LT"),
    ("litauen", "LT"),
    ("lituania", "LT"),
    ("litouwen", "LT"),
    ("lietuva", "LT"),
    ("luxembourg", "LU"),
    ("luxemburg", "LU"),
    ("lussemburgo", "LU"),
    ("luxemburgo", "LU"),
    ("malta", "MT"),
    ("malte", "MT"),
    ("monaco", "MC"),
    ("montenegro", "ME"),
    ("crna gora", "ME"),
    ("morocco", "MA"),
    ("maroc", "MA"),
    ("marokko", "MA"),
    ("marocco", "MA"),
    ("marruecos", "MA"),
    ("netherlands", "NL"),
    ("pays bas", "NL"),
    ("niederlande", "NL"),
    ("paesi bassi", "NL"),
    ("paises bajos", "NL"),
    ("nederland", "NL"),
    ("north macedonia", "MK"),
    ("macedoine du nord", "MK"),
    ("nordmazedonien", "MK"),
    ("macedonia del nord", "MK"),
    ("macedonia del norte", "MK"),
    ("noord macedonie", "MK"),
    ("norway", "NO"),
    ("norvege", "NO"),
    ("norwegen", "NO"),
    ("norvegia", "NO"),
    ("noruega", "NO"),
    ("noorwegen", "NO"),
    ("norge", "NO"),
    ("poland", "PL"),
    ("pologne", "PL"),
    ("polen", "PL"),
    ("polonia", "PL"),
    ("polska", "PL"),
    ("portugal", "PT"),
    ("portogallo", "PT"),
    ("romania", "RO"),
    ("roumanie", "RO"),
    ("rumanien", "RO"),
    ("rumania", "RO"),
    ("roemenie", "RO"),
    ("san marino", "SM"),
    ("saint marin", "SM"),
    ("serbia", "RS"),
    ("serbie", "RS"),
    ("serbien", "RS"),
    ("servie", "RS"),
    ("srbija", "RS"),
    ("slovakia", "SK"),
    ("slovaquie", "SK"),
    ("slowakei", "SK"),
    ("slovacchia", "SK"),
    ("eslovaquia", "SK"),
    ("slowakije", "SK"),
    ("slovensko", "SK"),
    ("slovenia", "SI"),
    ("slovenie", "SI"),
    ("slowenien", "SI"),
    ("eslovenia", "SI"),
    ("slovenija", "SI"),
    ("spain", "ES"),
    ("espagne", "ES"),
    ("spanien", "ES"),
    ("spagna", "ES"),
    ("espana", "ES"),
    ("spanje", "ES"),
    ("sweden", "SE"),
    ("suede", "SE"),
    ("schweden", "SE"),
    ("svezia", "SE"),
    ("suecia", "SE"),
    ("zweden", "SE"),
    ("sverige", "SE"),
    ("switzerland", "CH"),
    ("suisse", "CH"),
    ("schweiz", "CH"),
    ("svizzera", "CH"),
    ("suiza", "CH"),
    ("zwitserland", "CH"),
    ("united kingdom", "GB"),
    ("royaume uni", "GB"),
    ("vereinigtes konigreich", "GB"),
    ("regno unito", "GB"),
    ("reino unido", "GB"),
    ("verenigd koninkrijk", "GB"),
    ("great britain", "GB"),
    ("grande bretagne", "GB"),
    ("grossbritannien", "GB"),
    ("england", "GB"),
    ("angleterre", "GB"),
    ("inghilterra", "GB"),
    ("inglaterra", "GB"),
    ("engeland", "GB"),
    ("scotland", "GB"),
    ("ecosse", "GB"),
    ("schottland", "GB"),
    ("scozia", "GB"),
    ("escocia", "GB"),
    ("schotland", "GB"),
    ("wales", "GB"),
    ("pays de galles", "GB"),
    ("northern ireland", "GB"),
    ("irlande du nord", "GB"),
    ("nordirland", "GB"),
    ("irlanda del nord", "GB"),
    ("irlanda del norte", "GB"),
    ("noord ierland", "GB"),
];

/// The folded words of the search text.
struct TextWords(Vec<String>);

impl TextWords {
    fn new(text: &str) -> Self {
        Self(
            fold(text)
                .split(' ')
                .filter(|w| !w.is_empty())
                .map(str::to_owned)
                .collect(),
        )
    }

    fn read(&self, m: &AddressMatch) -> Reading {
        let name = fold(&m.name);
        let name_words: Vec<&str> = name.split(' ').filter(|w| !w.is_empty()).collect();
        // A town's own name is the town: it takes no word from it.
        let taken = if m.kind == AddressKind::Town {
            vec![false; self.0.len()]
        } else {
            self.taken_by(&name_words)
        };
        let (town, town_words) = m
            .town()
            .map_or((TownNamed::No, None), |t| self.names(&fold(t), &taken));
        Reading {
            fit: TextFit {
                town,
                name_missing_words: name_words.is_empty()
                    || !name_words.iter().all(|w| self.0.iter().any(|q| q == w)),
            },
            country: self.country(&taken),
            town_words,
            taken,
        }
    }

    /// The country the text ends on, in words not `taken` ("... Lyon
    /// France", "... Rabat Maroc"), as an ISO 3166-1 alpha-2 code, the
    /// longest name first ("... Belfast Northern Ireland" is not Ireland).
    /// A country word a match's name accounts for names its street ("Rue de
    /// France"), no country.
    fn country(&self, taken: &[bool]) -> Option<&'static str> {
        (1..=MAX_COUNTRY_WORDS.min(self.0.len()))
            .rev()
            .find_map(|n| {
                let start = self.0.len() - n;
                if taken[start..].iter().any(|t| *t) {
                    return None;
                }
                let name = self.0[start..].join(" ");
                COUNTRY_NAMES
                    .iter()
                    .find(|(n, _)| *n == name)
                    .map(|(_, code)| *code)
            })
    }

    /// The positions of the text's words a name accounts for: each of its
    /// words takes the first free equal one.
    fn taken_by(&self, name_words: &[&str]) -> Vec<bool> {
        let mut taken = vec![false; self.0.len()];
        for w in name_words {
            if let Some(i) = (0..self.0.len()).find(|&i| !taken[i] && self.0[i] == *w) {
                taken[i] = true;
            }
        }
        taken
    }

    /// Whether the folded `town` follows itself among the words not
    /// `taken`, word by word exactly or closely, and the positions of the
    /// words it is read from.
    fn names(&self, town: &str, taken: &[bool]) -> (TownNamed, Option<Range<usize>>) {
        let town: Vec<&str> = town.split(' ').filter(|w| !w.is_empty()).collect();
        if town.is_empty() || town.len() > self.0.len() {
            return (TownNamed::No, None);
        }
        let mut best = (TownNamed::No, None);
        for start in 0..=self.0.len() - town.len() {
            let span = start..start + town.len();
            if taken[span.clone()].iter().any(|t| *t) {
                continue;
            }
            let mut fit = TownNamed::Exactly;
            for (q, t) in self.0[span.clone()].iter().zip(&town) {
                if q == t {
                    continue;
                }
                if close_word(q, t) {
                    fit = TownNamed::Closely;
                } else {
                    fit = TownNamed::No;
                    break;
                }
            }
            if fit < best.0 {
                best = (fit, Some(span));
            }
        }
        best
    }
}

/// A typed word that names a town's word in another language or spelling:
/// the town's word starts it, of four letters or more ("milano" for
/// Milan, the French name the geocoder gives), or both, of six letters or
/// more, share their first five ("salamanca" for Salamanque). Never the
/// typed word a mere start of the town's ("lille" is not Lillebonne).
fn close_word(typed: &str, town: &str) -> bool {
    let (t, w) = (typed.chars().count(), town.chars().count());
    if w >= 4 && typed.starts_with(town) {
        return true;
    }
    t >= 6 && w >= 6 && typed.chars().take(5).eq(town.chars().take(5))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(lat: f64, lon: f64) -> Position {
        Position::new(lat, lon).expect("a valid test position")
    }

    /// Viviers, the map's centre for the addresses measured.
    fn viviers() -> Position {
        at(44.5, 4.7)
    }

    fn town(name: &str, postcode: Option<&str>, p: Position) -> AddressMatch {
        AddressMatch {
            kind: AddressKind::Town,
            name: name.to_owned(),
            postcode: postcode.map(str::to_owned),
            city: None,
            context: None,
            country_code: Some("FR".to_owned()),
            position: p,
            source: AddressSource::Ban,
            score: Some(0.9),
        }
    }

    /// A street in a town named after its position: two streets at two
    /// places are in two towns.
    fn street(name: &str, p: Position, source: AddressSource, score: Option<f64>) -> AddressMatch {
        AddressMatch {
            kind: AddressKind::Street,
            name: name.to_owned(),
            postcode: None,
            city: Some(format!("Town at {:.1} {:.1}", p.lat(), p.lon())),
            context: None,
            country_code: None,
            position: p,
            source,
            score,
        }
    }

    fn found(
        kind: AddressKind,
        name: &str,
        city: &str,
        p: Position,
        source: AddressSource,
        score: Option<f64>,
    ) -> AddressMatch {
        AddressMatch {
            kind,
            name: name.to_owned(),
            postcode: None,
            city: Some(city.to_owned()),
            context: None,
            country_code: None,
            position: p,
            source,
            score,
        }
    }

    fn house(name: &str, city: &str, p: Position) -> AddressMatch {
        found(
            AddressKind::HouseNumber,
            name,
            city,
            p,
            AddressSource::Osm,
            None,
        )
    }

    fn lines(out: &[AddressMatch]) -> Vec<String> {
        out.iter()
            .map(|m| format!("{}, {}", m.name, m.city.as_deref().unwrap_or("-")))
            .collect()
    }

    #[test]
    fn a_town_the_search_already_lists_is_left_out() {
        let towns = [ShownTown::new("Vaux-le-Pénil", Some("77000"), Some("FR"))];
        let matches = vec![
            town("Vaux-le-Pénil", Some("77000"), at(48.52, 2.68)),
            town("Vaux-le-Vicomte", None, at(48.56, 2.71)),
        ];
        let out = rank(vec![matches], "vaux le", &towns, None, 5);
        assert_eq!(
            out.iter().map(|m| m.name.as_str()).collect::<Vec<_>>(),
            ["Vaux-le-Vicomte"],
            "the app lists Vaux-le-Pénil among the towns already"
        );
    }

    #[test]
    fn a_town_of_the_same_name_elsewhere_stays_and_another_postcode_of_it_does_not() {
        let towns = [
            ShownTown::new("Saint-Denis", Some("93200"), Some("FR")),
            ShownTown::new("Lyon", Some("69007"), Some("FR")),
        ];
        let out = rank(
            vec![vec![
                town("Saint-Denis", Some("97400"), at(-20.88, 55.45)),
                town("Lyon", Some("69001"), at(45.76, 4.83)),
            ]],
            "saint",
            &towns,
            None,
            5,
        );
        assert_eq!(
            out.iter().map(|m| m.name.as_str()).collect::<Vec<_>>(),
            ["Saint-Denis"],
            "La Réunion's Saint-Denis is another town; Lyon 69001 is the Lyon listed"
        );
    }

    #[test]
    fn the_geocoders_order_beats_the_distance_when_the_text_decides_nothing_else() {
        // Photon's own order for "Via del Corso 10 Roma": Rome first. Its
        // French name ("Rome") is not the typed one, and Castiglione dei
        // Pepoli and Malalbergo are nearer Viviers: sorted by distance, as
        // before, Rome came third.
        let out = rank(
            vec![vec![
                house("Via del Corso 10", "Rome", at(41.90, 12.48)),
                house("Via del Corso 10", "Malalbergo", at(44.72, 11.53)),
                house(
                    "Via del Corso - Lagaro 10",
                    "Castiglione dei Pepoli",
                    at(44.15, 11.15),
                ),
            ]],
            "Via del Corso 10 Roma",
            &[],
            Some(viviers()),
            5,
        );
        assert_eq!(out[0].city.as_deref(), Some("Rome"));
    }

    #[test]
    fn the_town_typed_comes_first() {
        // Photon's order for "Hauptstraße 5 Heidelberg" put a bank in
        // Walldorf among Heidelberg's matches.
        let out = rank(
            vec![vec![
                house("Hauptstraße 5", "Walldorf", at(49.30, 8.64)),
                house("Hauptstraße 5", "Heidelberg", at(49.41, 8.69)),
            ]],
            "Hauptstraße 5 Heidelberg",
            &[],
            Some(viviers()),
            5,
        );
        assert_eq!(
            lines(&out),
            ["Hauptstraße 5, Heidelberg", "Hauptstraße 5, Walldorf"]
        );
    }

    #[test]
    fn a_town_whose_name_only_starts_like_the_one_typed_is_not_it() {
        let ban = |name: &str, city: &str, score: f64| {
            found(
                AddressKind::HouseNumber,
                name,
                city,
                at(49.5, 0.5),
                AddressSource::Ban,
                Some(score),
            )
        };
        let out = rank(
            vec![vec![
                ban("5 Rue Victor Hugo", "Lillebonne", 0.80),
                ban("5 Rue Victor Hugo (Lomme)", "Lille", 0.66),
            ]],
            "5 rue Victor Hugo Lille",
            &[],
            Some(viviers()),
            5,
        );
        assert_eq!(out[0].city.as_deref(), Some("Lille"));
    }

    #[test]
    fn the_town_typed_in_its_own_language_is_close_to_the_name_given() {
        let out = rank(
            vec![vec![
                house("Via Dante 5", "Pero", at(45.51, 9.09)),
                house("Via Dante 5n10", "Milan", at(45.47, 9.18)),
            ]],
            "Via Dante 5 Milano",
            &[],
            Some(viviers()),
            5,
        );
        assert_eq!(out[0].city.as_deref(), Some("Milan"));
    }

    #[test]
    fn a_street_named_after_the_town_typed_is_not_in_it() {
        let ban = found(
            AddressKind::HouseNumber,
            "12 Rue de Bruxelles",
            "Toulouse",
            at(43.57, 1.41),
            AddressSource::Ban,
            Some(0.59),
        );
        let out = rank(
            vec![
                vec![ban],
                vec![house("12 Rue Neuve", "Bruxelles", at(50.85, 4.35))],
            ],
            "12 Rue Neuve Bruxelles",
            &[],
            Some(viviers()),
            5,
        );
        assert_eq!(out[0].city.as_deref(), Some("Bruxelles"));
    }

    #[test]
    fn the_exact_house_number_comes_before_its_street() {
        let lyon = at(45.76, 4.83);
        let out = rank(
            vec![vec![
                found(
                    AddressKind::Street,
                    "Rue de la République",
                    "Lyon",
                    lyon,
                    AddressSource::Ban,
                    Some(0.88),
                ),
                found(
                    AddressKind::HouseNumber,
                    "10 Rue de la République",
                    "Lyon",
                    lyon,
                    AddressSource::Ban,
                    Some(0.86),
                ),
            ]],
            "10 rue de la Republique Lyon",
            &[],
            Some(viviers()),
            5,
        );
        assert_eq!(
            lines(&out),
            [
                "10 Rue de la République, Lyon",
                "Rue de la République, Lyon"
            ]
        );
    }

    #[test]
    fn a_house_number_of_another_street_stays_behind_the_street_typed() {
        let colmar = at(48.08, 7.36);
        let out = rank(
            vec![vec![
                found(
                    AddressKind::HouseNumber,
                    "8 Place de la Gare",
                    "Colmar",
                    colmar,
                    AddressSource::Ban,
                    Some(0.73),
                ),
                found(
                    AddressKind::Street,
                    "Rue de la Gare",
                    "Colmar",
                    colmar,
                    AddressSource::Ban,
                    Some(0.73),
                ),
            ]],
            "8 rue de la Gare Colmar",
            &[],
            None,
            5,
        );
        assert_eq!(out[0].name, "Rue de la Gare");
    }

    #[test]
    fn without_a_town_typed_the_nearest_answer_leads() {
        let near = at(48.85, 2.35);
        let out = rank(
            vec![
                vec![street(
                    "Rue de la Gare",
                    at(43.3, 5.4),
                    AddressSource::Ban,
                    Some(0.9),
                )],
                vec![street(
                    "Rue de la Gare",
                    at(50.8, 4.3),
                    AddressSource::Osm,
                    None,
                )],
            ],
            "rue de la gare",
            &[],
            Some(near),
            5,
        );
        let lats: Vec<f64> = out.iter().map(|m| m.position.lat()).collect();
        assert_eq!(
            lats,
            [50.8, 43.3],
            "Brussels is nearer Paris than Marseille"
        );
    }

    #[test]
    fn without_a_point_the_geocoders_order_stays() {
        let out = rank(
            vec![vec![
                street("B", at(43.3, 5.4), AddressSource::Ban, Some(0.9)),
                street("A", at(48.8, 2.3), AddressSource::Ban, Some(0.9)),
            ]],
            "rue",
            &[],
            None,
            5,
        );
        assert_eq!(out[0].name, "B");
    }

    #[test]
    fn weak_matches_of_a_rated_geocoder_are_dropped() {
        let p = at(48.58, 7.75);
        let out = rank(
            vec![
                vec![
                    street("Rue du Dôme", p, AddressSource::Ban, Some(0.83)),
                    street("6 Rue de Rome", p, AddressSource::Ban, Some(0.6)),
                ],
                vec![street(
                    "Rue du Dôme",
                    at(48.0, 7.0),
                    AddressSource::Osm,
                    None,
                )],
            ],
            "rue du dome",
            &[],
            None,
            5,
        );
        assert_eq!(
            out.iter().map(|m| m.name.as_str()).collect::<Vec<_>>(),
            ["Rue du Dôme", "Rue du Dôme"],
            "an unrated match is never judged weak"
        );
    }

    #[test]
    fn a_rating_too_low_is_no_match_even_alone() {
        let out = rank(
            vec![vec![street(
                "Neuhof Hinter Den Gaerten",
                at(49.25, 6.5),
                AddressSource::Ban,
                Some(0.34),
            )]],
            "unter den linden 77 berlin",
            &[],
            None,
            5,
        );
        assert!(out.is_empty(), "the best of nothing is still nothing");
    }

    #[test]
    fn the_same_address_from_two_sources_shows_once() {
        let out = rank(
            vec![
                vec![street(
                    "Rue de Siam",
                    at(48.3900, -4.4860),
                    AddressSource::Ban,
                    Some(0.9),
                )],
                vec![street(
                    "Rue de  SIAM",
                    at(48.3905, -4.4862),
                    AddressSource::Osm,
                    None,
                )],
            ],
            "rue de siam",
            &[],
            None,
            5,
        );
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].source, AddressSource::Ban, "the first told is kept");
    }

    #[test]
    fn the_segments_of_one_street_show_once() {
        let segment = |lat: f64| {
            found(
                AddressKind::Street,
                "Drottninggatan",
                "Stockholm",
                at(lat, 18.06),
                AddressSource::Osm,
                None,
            )
        };
        let out = rank(
            vec![vec![segment(59.33), segment(59.335), segment(59.34)]],
            "Drottninggatan Stockholm",
            &[],
            None,
            5,
        );
        assert_eq!(out.len(), 1, "a street a kilometre long is one street");
    }

    #[test]
    fn overseas_departments_and_corsica_are_areas_apart() {
        let towns = [ShownTown::new("Saint-Pierre", Some("97410"), Some("FR"))];
        let out = rank(
            vec![vec![
                town("Saint-Pierre", Some("97250"), at(14.74, -61.18)),
                town("Saint-Pierre", Some("97410"), at(-21.34, 55.48)),
            ]],
            "saint pierre",
            &towns,
            None,
            5,
        );
        assert_eq!(
            out.iter()
                .map(|m| m.postcode.as_deref().unwrap_or(""))
                .collect::<Vec<_>>(),
            ["97250"],
            "Martinique's Saint-Pierre is not La Réunion's, listed already"
        );
        assert_ne!(area("20000", Some("FR")), area("20250", Some("FR")));
        assert_eq!(
            area("20095", Some("DE")),
            area("20457", Some("DE")),
            "Hamburg is one area"
        );
    }

    #[test]
    fn the_homonyms_of_a_town_listed_come_before_the_streets_of_its_name() {
        // The BAN's answer for "Viviers" from Viviers in Ardèche, whose
        // places the search lists already.
        let commune = |postcode: &str, p: Position| town("Viviers", Some(postcode), p);
        let lieu = |kind: AddressKind, city: &str, p: Position| {
            found(kind, "Viviers", city, p, AddressSource::Ban, Some(0.86))
        };
        let out = rank(
            vec![vec![
                commune("07220", at(44.48, 4.69)),
                lieu(AddressKind::Street, "Juvigné", at(48.23, -1.03)),
                lieu(AddressKind::Locality, "Estivareilles", at(45.42, 4.0)),
                commune("57590", at(48.95, 6.43)),
                commune("89700", at(47.88, 3.93)),
            ]],
            "Viviers",
            &[ShownTown::new("Viviers", Some("07220"), Some("FR"))],
            Some(viviers()),
            5,
        );
        assert_eq!(
            out.iter()
                .map(|m| (m.kind, m.postcode.as_deref().unwrap_or("")))
                .take(2)
                .collect::<Vec<_>>(),
            [(AddressKind::Town, "57590"), (AddressKind::Town, "89700")],
            "Viviers in Moselle and in Yonne, then the streets named Viviers"
        );
    }

    #[test]
    fn abroad_a_town_is_one_group_whatever_its_postcodes() {
        let florence = at(43.77, 11.26);
        let mut square = found(
            AddressKind::Locality,
            "Piazza del Duomo",
            "Florence",
            florence,
            AddressSource::Osm,
            None,
        );
        square.country_code = Some("IT".to_owned());
        let mut house = house("Piazza del Duomo 1", "Florence", florence);
        house.country_code = Some("IT".to_owned());
        house.postcode = Some("50123".to_owned());
        let out = rank(
            vec![vec![square, house]],
            "Piazza del Duomo 1 Firenze",
            &[],
            None,
            5,
        );
        assert_eq!(
            out[0].name, "Piazza del Duomo 1",
            "the house number before the square, in one Florence"
        );
        let copenhagen = |kind: AddressKind, name: &str, postcode: &str| {
            let mut m = found(
                kind,
                name,
                "Copenhague",
                at(55.68, 12.58),
                AddressSource::Osm,
                None,
            );
            m.country_code = Some("DK".to_owned());
            m.postcode = Some(postcode.to_owned());
            m
        };
        let out = rank(
            vec![vec![
                copenhagen(AddressKind::Street, "Østergade", "1074"),
                copenhagen(AddressKind::HouseNumber, "Østergade 1", "1100"),
            ]],
            "Ostergade 1 Kobenhavn",
            &[],
            None,
            5,
        );
        assert_eq!(
            out[0].name, "Østergade 1",
            "one Copenhagen whatever its postcodes"
        );
    }

    #[test]
    fn matches_without_a_town_keep_their_order() {
        let region = |name: &str, lat: f64| AddressMatch {
            kind: AddressKind::Region,
            name: name.to_owned(),
            postcode: None,
            city: None,
            context: None,
            country_code: Some("BE".to_owned()),
            position: at(lat, 5.0),
            source: AddressSource::Osm,
            score: None,
        };
        let out = rank(
            vec![vec![
                region("A", 49.0),
                region("B", 10.0),
                region("C", 20.0),
            ]],
            "limburg",
            &[],
            None,
            5,
        );
        assert_eq!(
            out.iter().map(|m| m.name.as_str()).collect::<Vec<_>>(),
            ["A", "B", "C"],
            "what the text does not decide keeps the geocoder's order"
        );
    }

    #[test]
    fn streets_of_two_towns_of_one_name_both_stay() {
        let gare = |postcode: &str, p: Position| AddressMatch {
            kind: AddressKind::Street,
            name: "Rue de la Gare".to_owned(),
            postcode: Some(postcode.to_owned()),
            city: Some("Viviers".to_owned()),
            context: None,
            country_code: Some("FR".to_owned()),
            position: p,
            source: AddressSource::Ban,
            score: Some(0.8),
        };
        let out = rank(
            vec![vec![
                gare("07220", at(44.48, 4.69)),
                gare("89700", at(47.88, 3.93)),
            ]],
            "rue de la gare viviers",
            &[],
            None,
            5,
        );
        assert_eq!(
            out.iter()
                .map(|m| m.postcode.as_deref().unwrap_or(""))
                .collect::<Vec<_>>(),
            ["07220", "89700"],
            "Viviers in Ardèche and Viviers in Yonne each have their street"
        );
    }

    #[test]
    fn the_list_is_cut_at_its_size() {
        let out = rank(
            vec![
                (0..9)
                    .map(|i| {
                        street(
                            &format!("Rue {i}"),
                            at(45.0, 1.0 + f64::from(i)),
                            AddressSource::Osm,
                            None,
                        )
                    })
                    .collect(),
            ],
            "rue",
            &[],
            None,
            3,
        );
        assert_eq!(out.len(), 3);
    }

    /// A match of `kind` named `name` in `city`, of `country`.
    fn abroad(
        kind: AddressKind,
        name: &str,
        city: &str,
        country: &str,
        p: Position,
        source: AddressSource,
    ) -> AddressMatch {
        let mut m = found(kind, name, city, p, source, None);
        m.country_code = Some(country.to_owned());
        m
    }

    #[test]
    fn an_address_of_another_country_than_the_town_typed_is_left_out() {
        // The answers of 2026-10-10: the BAN's two Lyon matches, and the
        // houses of three embassies of Rabat, which Photon found by the
        // "République" of the embassies' names; the API shows their
        // streets.
        let lyon = at(45.76, 4.83);
        let rabat = at(34.0, -6.84);
        let ban = |kind: AddressKind, name: &str, score: f64| {
            let mut m = abroad(kind, name, "Lyon", "FR", lyon, AddressSource::Ban);
            m.score = Some(score);
            m
        };
        let answers = vec![
            vec![
                ban(AddressKind::HouseNumber, "10 Rue de la République", 0.96),
                ban(AddressKind::Street, "Rue de la République", 0.79),
            ],
            vec![
                abroad(
                    AddressKind::HouseNumber,
                    "7 Rue Zankat Madnine",
                    "Rabat",
                    "MA",
                    rabat,
                    AddressSource::Osm,
                ),
                abroad(
                    AddressKind::HouseNumber,
                    "10 Rue Ait Melloul",
                    "Rabat",
                    "MA",
                    rabat,
                    AddressSource::Osm,
                ),
                abroad(
                    AddressKind::HouseNumber,
                    "34 Rue Saadiyine",
                    "Rabat",
                    "MA",
                    rabat,
                    AddressSource::Osm,
                ),
            ],
        ];
        let out = rank(
            answers,
            "10 rue de la Republique Lyon",
            &[],
            Some(viviers()),
            5,
        );
        assert_eq!(
            lines(&out),
            [
                "10 Rue de la République, Lyon",
                "Rue de la République, Lyon"
            ],
            "Lyon is in France: Rabat's addresses are none of the ones asked"
        );
    }

    #[test]
    fn a_match_of_an_unknown_country_or_without_a_town_typed_stays() {
        let lyon = at(45.76, 4.83);
        let out = rank(
            vec![vec![
                abroad(
                    AddressKind::Street,
                    "Rue de la République",
                    "Lyon",
                    "FR",
                    lyon,
                    AddressSource::Osm,
                ),
                found(
                    AddressKind::Street,
                    "Rue de la République",
                    "Somewhere",
                    at(46.0, 5.0),
                    AddressSource::Osm,
                    None,
                ),
            ]],
            "rue de la Republique Lyon",
            &[],
            None,
            5,
        );
        assert_eq!(out.len(), 2, "a match whose country is unknown is kept");
        let out = rank(
            vec![vec![
                abroad(
                    AddressKind::Street,
                    "Rue de la République",
                    "Valence",
                    "FR",
                    at(44.93, 4.89),
                    AddressSource::Osm,
                ),
                abroad(
                    AddressKind::Street,
                    "Rue de la République",
                    "Bruxelles",
                    "BE",
                    at(50.85, 4.35),
                    AddressSource::Osm,
                ),
            ]],
            "rue de la Republique",
            &[],
            None,
            5,
        );
        assert_eq!(out.len(), 2, "no town typed, no country left out");
    }

    #[test]
    fn a_street_named_after_a_town_abroad_stays_beside_that_town() {
        let mut marseille = abroad(
            AddressKind::Street,
            "Rue de Rome",
            "Marseille",
            "FR",
            at(43.29, 5.38),
            AddressSource::Ban,
        );
        marseille.score = Some(0.9);
        let mut rome = abroad(
            AddressKind::Town,
            "Rome",
            "",
            "IT",
            at(41.9, 12.5),
            AddressSource::Osm,
        );
        rome.city = None;
        let out = rank(
            vec![vec![marseille], vec![rome]],
            "rue de Rome",
            &[],
            None,
            5,
        );
        assert_eq!(
            out.iter().map(|m| m.name.as_str()).collect::<Vec<_>>(),
            ["Rome", "Rue de Rome"],
            "the street's name holds the word Rome is read from: it is no address of \
             another country than the town typed"
        );
    }

    #[test]
    fn a_town_that_bears_a_country_s_name_stays_and_the_longest_country_wins() {
        let main = |city: &str, country: &str, p: Position| {
            abroad(
                AddressKind::Street,
                "Calle Mayor",
                city,
                country,
                p,
                AddressSource::Osm,
            )
        };
        let out = rank(
            vec![vec![
                main("Andorra la Vella", "AD", at(42.51, 1.52)),
                main("Andorra", "ES", at(40.98, -0.45)),
            ]],
            "Calle Mayor Andorra",
            &[],
            None,
            5,
        );
        assert_eq!(
            lines(&out),
            ["Calle Mayor, Andorra", "Calle Mayor, Andorra la Vella"],
            "Andorra in Teruel is the town typed, not an address of another country"
        );
        let high = |city: &str, country: &str, p: Position| {
            abroad(
                AddressKind::Street,
                "High Street",
                city,
                country,
                p,
                AddressSource::Osm,
            )
        };
        let out = rank(
            vec![vec![
                high("Belfast", "GB", at(54.6, -5.93)),
                high("Dublin", "IE", at(53.35, -6.26)),
            ]],
            "High Street Northern Ireland",
            &[],
            None,
            5,
        );
        assert_eq!(
            lines(&out),
            ["High Street, Belfast"],
            "Northern Ireland, not Ireland"
        );
    }

    #[test]
    fn the_country_the_text_ends_on_leaves_the_others_out_when_it_has_matches() {
        let mayor = |city: &str, country: &str, p: Position| {
            abroad(
                AddressKind::HouseNumber,
                "Calle Mayor 5",
                city,
                country,
                p,
                AddressSource::Osm,
            )
        };
        let both = || {
            vec![vec![
                mayor("Andorra la Vella", "AD", at(42.51, 1.52)),
                mayor("Madrid", "ES", at(40.42, -3.70)),
            ]]
        };
        let out = rank(both(), "Calle Mayor 5 España", &[], None, 5);
        assert_eq!(lines(&out), ["Calle Mayor 5, Madrid"]);
        let out = rank(both(), "Calle Mayor 5 Portugal", &[], None, 5);
        assert_eq!(
            out.len(),
            2,
            "no match in the country named: the text says nothing the matches could follow"
        );
        let france = |city: &str, country: &str, p: Position| {
            abroad(
                AddressKind::Street,
                "Rue de France",
                city,
                country,
                p,
                AddressSource::Osm,
            )
        };
        let out = rank(
            vec![vec![
                france("Nice", "FR", at(43.70, 7.26)),
                france("Bruxelles", "BE", at(50.83, 4.35)),
            ]],
            "rue de France",
            &[],
            None,
            5,
        );
        assert_eq!(
            out.len(),
            2,
            "the street's own name takes the word: it names no country"
        );
    }

    #[test]
    fn close_words_are_other_spellings_never_a_mere_start() {
        assert!(close_word("milano", "milan"));
        assert!(close_word("salamanca", "salamanque"));
        assert!(!close_word("lille", "lillebonne"), "a start being typed");
        assert!(!close_word("roma", "rome"), "too short to tell");
        assert!(!close_word("nice", "nic"));
    }
}
