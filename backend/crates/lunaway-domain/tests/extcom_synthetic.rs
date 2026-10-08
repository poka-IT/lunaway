//! How the conflation treats the external community source on synthetic
//! data shaped like a community platform's: spots in four countries, names
//! in French, German, Spanish and Italian written the way visitors write
//! them, pins a few tens of metres off, car parks close to each other in
//! towns, a share of the spots also mapped in OpenStreetMap under its own
//! names, and duplicates inside the feed. No real data: the generator is
//! seeded and deterministic, so the figures it prints are reproducible
//! (`cargo test -p lunaway-domain extcom_synthetic -- --nocapture`), and the
//! bounds below keep the conflation from drifting on this population.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::cast_precision_loss,
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    reason = "a test states its preconditions with unwrap; the generator draws numbers"
)]

use std::collections::{BTreeMap, HashMap};

use lunaway_domain::{
    NormalizedRecord, PlaceKind, Position, SourceId,
    conflation::{Decision, MatchCandidate, MergeEdge, Reason, cluster, score},
};

/// splitmix64: a fixed sequence, no dependency.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }
    fn unit(&mut self) -> f64 {
        (self.next() >> 11) as f64 / (1_u64 << 53) as f64
    }
    fn below(&mut self, n: usize) -> usize {
        (self.next() % n as u64) as usize
    }
    fn chance(&mut self, p: f64) -> bool {
        self.unit() < p
    }
    fn pick<'a, T>(&mut self, items: &'a [T]) -> &'a T {
        &items[self.below(items.len())]
    }
    /// A normal draw (Box-Muller).
    fn normal(&mut self) -> f64 {
        let u = self.unit().max(1e-12);
        let v = self.unit();
        (-2.0 * u.ln()).sqrt() * (2.0 * std::f64::consts::PI * v).cos()
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Lang {
    Fr,
    De,
    Es,
    It,
}

struct Country {
    lang: Lang,
    /// South-west corner of the area towns are drawn in, and its size in
    /// degrees.
    origin: (f64, f64),
    span: (f64, f64),
    towns: &'static [&'static str],
    landmarks: &'static [&'static str],
    /// Names of campsites and farms, which have one of their own.
    proper: &'static [&'static str],
}

const COUNTRIES: [Country; 4] = [
    Country {
        lang: Lang::Fr,
        origin: (43.5, -1.0),
        span: (5.0, 7.0),
        towns: &[
            "Annecy",
            "Saint-Malo",
            "Collioure",
            "Gérardmer",
            "Sarlat",
            "Étretat",
            "Honfleur",
            "Carnac",
            "Millau",
            "Vaison-la-Romaine",
            "Saint-Jean-de-Luz",
            "Riquewihr",
        ],
        landmarks: &[
            "lac",
            "port",
            "plage",
            "château",
            "stade",
            "cimetière",
            "moulin",
            "église",
        ],
        proper: &[
            "Les Pins",
            "La Rivière",
            "Le Lac Bleu",
            "Les Saules",
            "La Forêt",
            "Les Mimosas",
            "Le Moulin",
            "Les Chênes",
            "La Prairie",
            "Le Soleil",
        ],
    },
    Country {
        lang: Lang::De,
        origin: (47.5, 7.0),
        span: (5.0, 6.0),
        towns: &[
            "Füssen",
            "Cochem",
            "Bernkastel",
            "Lindau",
            "Rüdesheim",
            "Wernigerode",
            "Quedlinburg",
            "Bad Tölz",
            "Meersburg",
            "Rothenburg",
        ],
        landmarks: &[
            "See",
            "Hafen",
            "Freibad",
            "Burg",
            "Kirche",
            "Sportplatz",
            "Mühle",
        ],
        proper: &[
            "Seeblick",
            "Sonnenwiese",
            "Alpenblick",
            "Waldfrieden",
            "Lindenhof",
            "Bergblick",
            "Rheinufer",
            "Tannenhof",
        ],
    },
    Country {
        lang: Lang::Es,
        origin: (36.5, -6.0),
        span: (5.0, 8.0),
        towns: &[
            "Cambrils",
            "Peñíscola",
            "Ronda",
            "Cudillero",
            "Nerja",
            "Tarifa",
            "Altea",
            "Cuenca",
            "Llanes",
            "Sigüenza",
        ],
        landmarks: &[
            "playa",
            "puerto",
            "castillo",
            "iglesia",
            "polideportivo",
            "río",
        ],
        proper: &[
            "El Pinar",
            "La Ribera",
            "Los Olivos",
            "Las Dunas",
            "Mar Azul",
            "Sierra Verde",
            "La Almadraba",
            "El Molino",
        ],
    },
    Country {
        lang: Lang::It,
        origin: (40.5, 8.0),
        span: (5.0, 7.0),
        towns: &[
            "Bardolino",
            "Sirmione",
            "Cefalù",
            "Alghero",
            "Bellagio",
            "Orvieto",
            "Tropea",
            "Vernazza",
            "Matera",
            "Assisi",
        ],
        landmarks: &[
            "lago", "porto", "spiaggia", "castello", "chiesa", "stadio", "fiume",
        ],
        proper: &[
            "Il Pino",
            "La Quercia",
            "Lago Blu",
            "Le Dune",
            "Il Sole",
            "Bella Vista",
            "Le Palme",
            "San Marco",
        ],
    },
];

/// Kinds as a community platform holds them, by weight.
const KINDS: [(PlaceKind, u32); 8] = [
    (PlaceKind::Parking, 35),
    (PlaceKind::MotorhomeArea, 25),
    (PlaceKind::Nature, 15),
    (PlaceKind::Campsite, 12),
    (PlaceKind::ServiceArea, 5),
    (PlaceKind::Farm, 4),
    (PlaceKind::RestArea, 3),
    (PlaceKind::PicnicArea, 1),
];

fn draw_kind(rng: &mut Rng) -> PlaceKind {
    let total: u32 = KINDS.iter().map(|(_, w)| w).sum();
    let mut x = (rng.next() % u64::from(total)) as u32;
    for (k, w) in KINDS {
        if x < w {
            return k;
        }
        x -= w;
    }
    PlaceKind::Parking
}

/// What a spot's names are made of: its town, what it is next to, and its
/// own name when it has one (a campsite, a farm).
struct Words<'a> {
    town: &'a str,
    mark: &'a str,
    proper: &'a str,
}

/// A name as OpenStreetMap maps it (an official or a sign's name).
fn osm_name(rng: &mut Rng, lang: Lang, kind: PlaceKind, w: &Words<'_>) -> Option<String> {
    let named = match kind {
        PlaceKind::Parking | PlaceKind::Nature | PlaceKind::PicnicArea => 0.4,
        _ => 0.9,
    };
    if !rng.chance(named) {
        return None;
    }
    let Words { town, mark, proper } = w;
    Some(match (lang, kind) {
        (Lang::Fr, PlaceKind::Campsite) => format!("Camping {proper}"),
        (Lang::Fr, PlaceKind::Farm) => format!("Ferme {proper}"),
        (Lang::Fr, PlaceKind::MotorhomeArea | PlaceKind::ServiceArea) => {
            format!("Aire de camping-car de {town}")
        }
        (Lang::Fr, _) => format!("Parking du {mark}"),
        (Lang::De, PlaceKind::Campsite) => format!("Campingplatz {proper}"),
        (Lang::De, PlaceKind::Farm) => format!("Hof {proper}"),
        (Lang::De, PlaceKind::MotorhomeArea | PlaceKind::ServiceArea) => {
            format!("Wohnmobilstellplatz {town}")
        }
        (Lang::De, _) => format!("Parkplatz am {mark}"),
        (Lang::Es, PlaceKind::Campsite) => format!("Camping {proper}"),
        (Lang::Es, PlaceKind::Farm) => format!("Bodega {proper}"),
        (Lang::Es, PlaceKind::MotorhomeArea | PlaceKind::ServiceArea) => {
            format!("Área de autocaravanas de {town}")
        }
        (Lang::Es, _) => format!("Aparcamiento del {mark}"),
        (Lang::It, PlaceKind::Campsite) => format!("Campeggio {proper}"),
        (Lang::It, PlaceKind::Farm) => format!("Agriturismo {proper}"),
        (Lang::It, PlaceKind::MotorhomeArea | PlaceKind::ServiceArea) => {
            format!("Area sosta camper {town}")
        }
        (Lang::It, _) => format!("Parcheggio del {mark}"),
    })
}

/// A name as a visitor types it on a community platform: the spot's own
/// name or its town, what it is next to, sometimes a sentence.
fn community_name(rng: &mut Rng, lang: Lang, kind: PlaceKind, w: &Words<'_>) -> String {
    let style = rng.below(5);
    let Words { town, mark, proper } = w;
    if matches!(kind, PlaceKind::Campsite | PlaceKind::Farm) {
        // The campsite with a different name: one in four goes by its town.
        return if style == 0 {
            format!("Camping {town}")
        } else {
            format!("Camping {proper}")
        };
    }
    match lang {
        Lang::Fr => match (kind, style) {
            (PlaceKind::MotorhomeArea | PlaceKind::ServiceArea, 0..=2) => {
                format!("Aire camping-car {town}")
            }
            (_, 0 | 1) => format!("Parking du {mark}"),
            (_, 2) => format!("{town} - parking {mark}"),
            (_, 3) => format!("Parking calme près du {mark}"),
            _ => format!("Spot {town}"),
        },
        Lang::De => match (kind, style) {
            (PlaceKind::MotorhomeArea | PlaceKind::ServiceArea, 0..=2) => {
                format!("Stellplatz {town}")
            }
            (_, 0 | 1) => format!("Parkplatz am {mark}"),
            (_, 2) => format!("{town} Parkplatz {mark}"),
            _ => format!("Ruhiger Platz am {mark}"),
        },
        Lang::Es => match (kind, style) {
            (PlaceKind::MotorhomeArea | PlaceKind::ServiceArea, 0..=2) => {
                format!("Area autocaravanas {town}")
            }
            (_, 0 | 1) => format!("Parking {mark} {town}"),
            _ => format!("Aparcamiento junto al {mark}"),
        },
        Lang::It => match (kind, style) {
            (PlaceKind::MotorhomeArea | PlaceKind::ServiceArea, 0..=2) => {
                format!("Area di sosta {town}")
            }
            (_, 0 | 1) => format!("Parcheggio {mark}"),
            _ => format!("Sosta tranquilla vicino al {mark}"),
        },
    }
}

/// `p` moved by `north` and `east` metres.
fn offset(p: (f64, f64), north: f64, east: f64) -> (f64, f64) {
    let dlat = north / 111_320.0;
    let dlon = east / (111_320.0 * p.0.to_radians().cos());
    (p.0 + dlat, p.1 + dlon)
}

struct Rec {
    /// The real spot it describes.
    truth: usize,
    source: SourceId,
    record: NormalizedRecord,
}

fn record(
    source: &SourceId,
    kind: PlaceKind,
    at: (f64, f64),
    name: Option<String>,
    acc: f64,
) -> (SourceId, NormalizedRecord) {
    let mut r = NormalizedRecord::new(kind, Position::new(at.0, at.1).unwrap());
    r.name = name;
    r.accuracy_m = acc;
    (source.clone(), r)
}

/// The population: true spots in towns, the feed's records, and the OSM
/// records of the share OSM maps.
fn population(seed: u64, towns_per_country: usize) -> Vec<Rec> {
    let mut rng = Rng(seed);
    let mut out = Vec::new();
    let mut truth = 0;
    for c in &COUNTRIES {
        for _ in 0..towns_per_country {
            let centre = (
                c.origin.0 + rng.unit() * c.span.0,
                c.origin.1 + rng.unit() * c.span.1,
            );
            let town = *rng.pick(c.towns);
            // A town holds one to six spots, spread over a kilometre: car
            // parks a hundred metres apart are the hard negatives.
            let spots = 1 + rng.below(6);
            // A town has one municipal motorhome area at most, and its
            // campsites and farms have names of their own.
            let mut area_taken = false;
            let mut proper_taken: Vec<&str> = Vec::new();
            for _ in 0..spots {
                let at = offset(
                    centre,
                    (rng.unit() - 0.5) * 1_000.0,
                    (rng.unit() - 0.5) * 1_000.0,
                );
                let mut kind = draw_kind(&mut rng);
                if matches!(kind, PlaceKind::MotorhomeArea | PlaceKind::ServiceArea) {
                    if area_taken {
                        kind = PlaceKind::Parking;
                    }
                    area_taken = true;
                }
                let mark = *rng.pick(c.landmarks);
                let mut proper = *rng.pick(c.proper);
                while proper_taken.contains(&proper) {
                    proper = *rng.pick(c.proper);
                }
                proper_taken.push(proper);
                let words = Words { town, mark, proper };
                // OSM maps two spots of three, at the spot.
                if rng.chance(0.65) {
                    let (source, r) = record(
                        &SourceId::OSM,
                        kind,
                        at,
                        osm_name(&mut rng, c.lang, kind, &words),
                        if kind == PlaceKind::Campsite {
                            80.0
                        } else {
                            15.0
                        },
                    );
                    out.push(Rec {
                        truth,
                        source,
                        record: r,
                    });
                }
                // The visitor's pin: a few tens of metres off, sometimes far.
                let err = if rng.chance(0.05) {
                    60.0 + rng.unit() * 100.0
                } else {
                    rng.normal().abs() * 15.0
                };
                let angle = rng.unit() * std::f64::consts::TAU;
                let pin = offset(at, err * angle.sin(), err * angle.cos());
                // The platform's category is coarser: a motorhome area is
                // sometimes filed as a car park.
                let feed_kind = if kind == PlaceKind::MotorhomeArea && rng.chance(0.15) {
                    PlaceKind::Parking
                } else {
                    kind
                };
                let name = community_name(&mut rng, c.lang, kind, &words);
                let (source, r) =
                    record(&SourceId::EXTCOM, feed_kind, pin, Some(name.clone()), 20.0);
                out.push(Rec {
                    truth,
                    source,
                    record: r,
                });
                // Two in a hundred spots are in the feed twice.
                if rng.chance(0.02) {
                    let dup = offset(pin, rng.unit() * 30.0, rng.unit() * 30.0);
                    let (source, r) = record(
                        &SourceId::EXTCOM,
                        feed_kind,
                        dup,
                        Some(format!("{name} (bis)")),
                        20.0,
                    );
                    out.push(Rec {
                        truth,
                        source,
                        record: r,
                    });
                }
                truth += 1;
            }
        }
    }
    out
}

#[derive(Debug, Default)]
struct Measure {
    records: usize,
    spots: usize,
    pairs_scored: usize,
    /// Pairs of two sources describing the same spot.
    same_spot_cross: usize,
    merged_true: usize,
    reviewed_true: usize,
    missed_true: usize,
    merged_false: usize,
    reviewed_false: usize,
    /// Pairs of the feed describing the same spot (its duplicates).
    duplicates: usize,
    duplicates_reviewed: usize,
    /// Of them, scored as a merge and held back because the source is
    /// the same.
    duplicates_same_source: usize,
    /// Places of more than one spot after grouping.
    places_wrong: usize,
    places: usize,
    /// Spots with an OSM record whose feed record ended in another place.
    spots_split: usize,
    /// The same spot's pairs left unmerged, and the different spots'
    /// pairs merged, by decision and score components: what to read when
    /// a bound below fails.
    outcomes: BTreeMap<String, usize>,
}

fn measure(recs: &[Rec]) -> Measure {
    let mut m = Measure {
        records: recs.len(),
        spots: recs.iter().map(|r| r.truth).max().map_or(0, |t| t + 1),
        ..Measure::default()
    };
    let cands: Vec<MatchCandidate> = recs
        .iter()
        .map(|r| MatchCandidate::new(&r.source, &r.record))
        .collect();
    // A grid of about 500 m cells: every pair the server would score lies
    // in the same or a neighbouring cell.
    let cell = |r: &NormalizedRecord| {
        (
            (r.position.lat() / 0.0045).floor() as i64,
            (r.position.lon() / 0.0065).floor() as i64,
        )
    };
    let mut grid: HashMap<(i64, i64), Vec<usize>> = HashMap::new();
    for (i, r) in recs.iter().enumerate() {
        grid.entry(cell(&r.record)).or_default().push(i);
    }
    let mut edges = Vec::new();
    for (i, r) in recs.iter().enumerate() {
        let (y, x) = cell(&r.record);
        for dy in -1..=1 {
            for dx in -1..=1 {
                for &j in grid.get(&(y + dy, x + dx)).map_or(&[][..], Vec::as_slice) {
                    if j <= i {
                        continue;
                    }
                    let s = score(&cands[i], &cands[j]);
                    m.pairs_scored += 1;
                    let same = r.truth == recs[j].truth;
                    let cross = r.source != recs[j].source;
                    match (same, cross, s.decision) {
                        (true, true, Decision::Merge) => m.merged_true += 1,
                        (true, true, Decision::Review) => m.reviewed_true += 1,
                        (true, true, Decision::Distinct) => m.missed_true += 1,
                        (false, _, Decision::Merge) => m.merged_false += 1,
                        (false, _, Decision::Review) => m.reviewed_false += 1,
                        (true, false, Decision::Review) => {
                            m.duplicates_reviewed += 1;
                            if s.reason == Reason::SameSource {
                                m.duplicates_same_source += 1;
                            }
                        }
                        _ => {}
                    }
                    if same && cross {
                        m.same_spot_cross += 1;
                        if s.decision != Decision::Merge {
                            let named = r.record.name.is_some() && recs[j].record.name.is_some();
                            let key = format!(
                                "{:?} named={named} name={:.1} dist={:.1} kind={:.1}",
                                s.decision,
                                s.components.name,
                                s.components.distance,
                                s.components.kind
                            );
                            *m.outcomes.entry(key).or_insert(0) += 1;
                        }
                    }
                    if !same && s.decision == Decision::Merge {
                        let key = format!(
                            "{:?} {:?}/{:?} name={:.2} dist={:.2}",
                            s.decision,
                            r.record.name,
                            recs[j].record.name,
                            s.components.name,
                            s.components.distance
                        );
                        *m.outcomes.entry(key).or_insert(0) += 1;
                    }
                    if same && !cross {
                        m.duplicates += 1;
                    }
                    if s.decision == Decision::Merge {
                        edges.push(MergeEdge {
                            a: i,
                            b: j,
                            score: s.score,
                            distance_m: s.components.distance_m,
                            name: s.components.name,
                        });
                    }
                }
            }
        }
    }
    let nodes: Vec<(usize, &SourceId)> = recs
        .iter()
        .enumerate()
        .map(|(i, r)| (i, &r.source))
        .collect();
    let groups = cluster(&nodes, &edges, &[]).groups;
    m.places = groups.len();
    let mut place_of: BTreeMap<usize, usize> = BTreeMap::new();
    for (g, members) in groups.iter().enumerate() {
        let mut truths: Vec<usize> = members.iter().map(|&i| recs[i].truth).collect();
        truths.sort_unstable();
        truths.dedup();
        if truths.len() > 1 {
            m.places_wrong += 1;
        }
        for &i in members {
            place_of.insert(i, g);
        }
    }
    let mut by_truth: BTreeMap<usize, Vec<usize>> = BTreeMap::new();
    for (i, r) in recs.iter().enumerate() {
        by_truth.entry(r.truth).or_default().push(i);
    }
    for members in by_truth.values() {
        let osm: Vec<usize> = members
            .iter()
            .copied()
            .filter(|&i| recs[i].source == SourceId::OSM)
            .collect();
        let feed: Vec<usize> = members
            .iter()
            .copied()
            .filter(|&i| recs[i].source == SourceId::EXTCOM)
            .collect();
        if let (Some(&o), Some(&f)) = (osm.first(), feed.first())
            && place_of[&o] != place_of[&f]
        {
            m.spots_split += 1;
        }
    }
    m
}

#[test]
fn the_feed_merges_with_osm_without_joining_neighbours() {
    let recs = population(0x00C0_FFEE, 60);
    let m = measure(&recs);
    let true_pairs = m.same_spot_cross as f64;
    let merge_precision = m.merged_true as f64 / (m.merged_true + m.merged_false).max(1) as f64;
    let merge_recall = m.merged_true as f64 / true_pairs;
    let found = (m.merged_true + m.reviewed_true) as f64 / true_pairs;
    println!("synthetic extcom population: {m:#?}");
    println!(
        "{} records of {} spots: merge precision {merge_precision:.4}, merge recall \
         {merge_recall:.4}, merged or reviewed {found:.4}, duplicates reviewed {}/{}",
        m.records, m.spots, m.duplicates_reviewed, m.duplicates
    );
    // Measured 0.982 on this population since a missing name leaves the
    // mean: 9 merge edges between two spots of a town, 8 of them refused
    // by the grouping, 1 place of 911 holding two spots.
    assert!(
        merge_precision >= 0.97,
        "a merge joins two different spots too often: {merge_precision}"
    );
    assert!(
        m.places_wrong * 100 <= m.places,
        "more than one place in a hundred holds two spots: {} of {}",
        m.places_wrong,
        m.places
    );
    // Measured 0.870 (0.498 while a missing name counted 0.5 and capped an
    // unnamed car park beside a named pin at review).
    assert!(
        merge_recall >= 0.8,
        "too few of the same spots merge: {merge_recall}"
    );
    assert!(
        found >= 0.85,
        "too many of the same spots go unnoticed: {found}"
    );
    assert_eq!(
        m.duplicates_reviewed, m.duplicates,
        "every duplicate inside the feed reaches the review queue, none merges"
    );
}
