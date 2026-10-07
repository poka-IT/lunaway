//! The area the routing graph covers, and the countries in it.
//!
//! The graph is built from a list of Geofabrik extracts
//! (`infra/routing/europe-extracts.txt`), each one everything OpenStreetMap
//! holds inside Geofabrik's cut of a country. The cuts themselves are
//! embedded (`data/routing-coverage.poly`), so the API claims exactly the
//! area the graph was cut from: a point inside a cut has the graph's roads
//! around it, a point outside has none (Bosnia between Croatia's two parts,
//! Serbia, Algeria). A cut runs a few kilometres out to sea and over the
//! borders, as the extract does; the engine answers for those points (a
//! road within reach, or none).
//!
//! The tests hold the embedded cuts, the extracts list and the country
//! table below together: an extract added to the graph without its cut
//! fails them.

use std::sync::LazyLock;

use crate::{BBox, Position};

/// The cuts of the graph's extracts, in the order of the extracts list.
const CUTS: &str = include_str!("../../data/routing-coverage.poly");

/// The extract of metropolitan France and Corsica (with Monaco inside its
/// cut): the area of the French sources (IGN, the local road event
/// feeds), whatever else the graph covers.
pub const FRANCE: &str = "europe/france";

/// The countries each extract holds (ISO 3166-1 alpha-2), for the app to
/// name what routing covers. A cut that also holds a territory names it:
/// Monaco in France's, Gibraltar in Spain's, San Marino and the Vatican in
/// Italy's, Svalbard in Norway's, Åland in Finland's; Morocco's runs south
/// to Mauritania's border, Western Sahara included (`EH`, read on the cut,
/// 2026-10-07). Ceuta and Melilla lie in both Spain's and Morocco's cuts.
pub const COUNTRIES: &[(&str, &[&str])] = &[
    ("europe/france", &["FR", "MC"]),
    ("europe/spain", &["ES", "GI"]),
    ("africa/canary-islands", &["ES"]),
    ("europe/portugal", &["PT"]),
    ("europe/italy", &["IT", "SM", "VA"]),
    ("europe/germany", &["DE"]),
    ("europe/austria", &["AT"]),
    ("europe/switzerland", &["CH"]),
    ("europe/liechtenstein", &["LI"]),
    ("europe/belgium", &["BE"]),
    ("europe/netherlands", &["NL"]),
    ("europe/luxembourg", &["LU"]),
    ("europe/united-kingdom", &["GB"]),
    ("europe/ireland-and-northern-ireland", &["IE", "GB"]),
    ("europe/denmark", &["DK"]),
    ("europe/norway", &["NO", "SJ"]),
    ("europe/sweden", &["SE"]),
    ("europe/finland", &["FI", "AX"]),
    ("europe/croatia", &["HR"]),
    ("europe/slovenia", &["SI"]),
    ("europe/greece", &["GR"]),
    ("europe/poland", &["PL"]),
    ("europe/czech-republic", &["CZ"]),
    ("europe/andorra", &["AD"]),
    ("africa/morocco", &["MA", "EH"]),
];

/// One ring of a cut, longitude and latitude in degrees.
#[derive(Debug, Clone, PartialEq)]
struct Ring {
    /// A hole in the cut rather than a part of it.
    hole: bool,
    /// `(lon, lat)`, the closing point not repeated.
    points: Vec<(f64, f64)>,
    /// `[west, south, east, north]`.
    bounds: [f64; 4],
}

impl Ring {
    fn new(hole: bool, points: Vec<(f64, f64)>) -> Self {
        let mut bounds = [f64::MAX, f64::MAX, f64::MIN, f64::MIN];
        for &(lon, lat) in &points {
            bounds[0] = bounds[0].min(lon);
            bounds[1] = bounds[1].min(lat);
            bounds[2] = bounds[2].max(lon);
            bounds[3] = bounds[3].max(lat);
        }
        Self {
            hole,
            points,
            bounds,
        }
    }

    /// Whether `(lon, lat)` lies inside, by the even-odd rule.
    fn contains(&self, lon: f64, lat: f64) -> bool {
        let [west, south, east, north] = self.bounds;
        if lon < west || lon > east || lat < south || lat > north {
            return false;
        }
        let mut inside = false;
        let n = self.points.len();
        for i in 0..n {
            let (x1, y1) = self.points[i];
            let (x2, y2) = self.points[(i + 1) % n];
            if (y1 > lat) != (y2 > lat) && lon < (x2 - x1) * (lat - y1) / (y2 - y1) + x1 {
                inside = !inside;
            }
        }
        inside
    }
}

/// The cut of one extract.
#[derive(Debug, Clone, PartialEq)]
pub struct Region {
    path: String,
    rings: Vec<Ring>,
}

impl Region {
    /// The extract's path under Geofabrik (`europe/france`).
    #[must_use]
    pub fn path(&self) -> &str {
        &self.path
    }

    /// Whether `p` lies inside the cut: in one of its parts and in none of
    /// its holes.
    #[must_use]
    pub fn contains(&self, p: Position) -> bool {
        let (lon, lat) = (p.lon(), p.lat());
        self.rings.iter().any(|r| !r.hole && r.contains(lon, lat))
            && !self.rings.iter().any(|r| r.hole && r.contains(lon, lat))
    }

    /// `[west, south, east, north]` of its parts.
    fn bounds(&self) -> [f64; 4] {
        self.rings.iter().filter(|r| !r.hole).fold(
            [f64::MAX, f64::MAX, f64::MIN, f64::MIN],
            |b, r| {
                [
                    b[0].min(r.bounds[0]),
                    b[1].min(r.bounds[1]),
                    b[2].max(r.bounds[2]),
                    b[3].max(r.bounds[3]),
                ]
            },
        )
    }
}

/// Why the embedded cuts do not read.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[non_exhaustive]
pub enum InvalidCuts {
    /// A line the format does not allow there.
    #[error("line {line}: {what}")]
    Line {
        /// 1-based line number.
        line: usize,
        /// What was expected.
        what: &'static str,
    },
    /// The text ends inside a cut.
    #[error("the text ends inside a cut")]
    Truncated,
}

/// Reads cuts: a line `extract <path>` before each, then the cut in the
/// Osmosis polygon format (a name line, rings of `lon lat` lines each
/// opened by a name, `!name` for a hole, closed by `END`, and a last
/// `END`). Lines starting with `#` between cuts are comments.
///
/// # Errors
///
/// [`InvalidCuts`] on a line out of place, a coordinate that does not
/// read, a ring of fewer than three points, or a text that ends inside a
/// cut.
pub fn parse(text: &str) -> Result<Vec<Region>, InvalidCuts> {
    let bad = |line: usize, what| InvalidCuts::Line { line, what };
    let mut regions = Vec::new();
    let mut lines = text.lines().enumerate().map(|(i, l)| (i + 1, l.trim()));
    while let Some((n, line)) = lines.next() {
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let path = line
            .strip_prefix("extract ")
            .map(str::trim)
            .filter(|p| !p.is_empty())
            .ok_or_else(|| bad(n, "expected `extract <path>`"))?;
        // The polygon's own name, unused.
        lines.next().ok_or(InvalidCuts::Truncated)?;
        let mut rings = Vec::new();
        loop {
            let (n, head) = lines.next().ok_or(InvalidCuts::Truncated)?;
            if head == "END" {
                break;
            }
            let hole = head.starts_with('!');
            let mut points = Vec::new();
            loop {
                let (n, l) = lines.next().ok_or(InvalidCuts::Truncated)?;
                if l == "END" {
                    break;
                }
                let mut it = l.split_whitespace().map(str::parse::<f64>);
                match (it.next(), it.next()) {
                    (Some(Ok(lon)), Some(Ok(lat)))
                        if (-180.0..=180.0).contains(&lon) && (-90.0..=90.0).contains(&lat) =>
                    {
                        points.push((lon, lat));
                    }
                    _ => return Err(bad(n, "expected a longitude and a latitude")),
                }
            }
            if points.first() == points.last() {
                points.pop();
            }
            if points.len() < 3 {
                return Err(bad(n, "a ring needs three points"));
            }
            rings.push(Ring::new(hole, points));
        }
        if !rings.iter().any(|r| !r.hole) {
            return Err(bad(n, "a cut without a part"));
        }
        regions.push(Region {
            path: path.to_owned(),
            rings,
        });
    }
    Ok(regions)
}

/// The embedded cuts, read once.
///
/// # Panics
///
/// Never: the embedded file is a constant the tests of this module read.
static REGIONS: LazyLock<Vec<Region>> = LazyLock::new(|| {
    #[allow(
        clippy::expect_used,
        reason = "an embedded constant, read by the tests of this module"
    )]
    parse(CUTS).expect("the embedded routing coverage reads")
});

/// The cut of every extract of the graph, in the extracts list's order.
#[must_use]
pub fn regions() -> &'static [Region] {
    &REGIONS
}

/// The cut of the extract at `path`.
#[must_use]
pub fn region(path: &str) -> Option<&'static Region> {
    REGIONS.iter().find(|r| r.path == path)
}

/// Whether the routing graph covers `p`: it lies in the cut of one of its
/// extracts.
#[must_use]
pub fn covers(p: Position) -> bool {
    REGIONS.iter().any(|r| r.contains(p))
}

/// Whether `p` lies in metropolitan France or Corsica, as Geofabrik cuts
/// them ([`FRANCE`]).
#[must_use]
pub fn in_france(p: Position) -> bool {
    region(FRANCE).is_some_and(|r| r.contains(p))
}

/// The smallest box around every cut.
///
/// # Panics
///
/// Never: the cuts' coordinates are checked within the WGS 84 range when
/// read, and there is at least one.
#[must_use]
pub fn bounding_box() -> BBox {
    let [west, south, east, north] = REGIONS.iter().map(Region::bounds).fold(
        [f64::MAX, f64::MAX, f64::MIN, f64::MIN],
        |b, r| {
            [
                b[0].min(r[0]),
                b[1].min(r[1]),
                b[2].max(r[2]),
                b[3].max(r[3]),
            ]
        },
    );
    #[allow(
        clippy::expect_used,
        reason = "coordinates checked when read, at least one cut (tests)"
    )]
    BBox::new(south, west, north, east).expect("the cuts lie within WGS 84")
}

/// The countries the graph covers (ISO 3166-1 alpha-2), sorted, each once.
#[must_use]
pub fn countries() -> Vec<&'static str> {
    let mut all: Vec<&str> = COUNTRIES
        .iter()
        .flat_map(|(_, codes)| codes.iter().copied())
        .collect();
    all.sort_unstable();
    all.dedup();
    all
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(lat: f64, lon: f64) -> Position {
        Position::new(lat, lon).unwrap()
    }

    /// The paths of `infra/routing/europe-extracts.txt`, in order.
    fn extracts_list() -> Vec<&'static str> {
        include_str!("../../../../../infra/routing/europe-extracts.txt")
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty() && !l.starts_with('#'))
            .collect()
    }

    #[test]
    fn the_cuts_are_those_of_the_extracts_the_graph_is_built_from() {
        let embedded: Vec<&str> = regions().iter().map(Region::path).collect();
        assert_eq!(
            embedded,
            extracts_list(),
            "an extract added to the graph without its cut would be refused by the API, \
             a cut without its extract would claim roads the graph lacks"
        );
        let named: Vec<&str> = COUNTRIES.iter().map(|(p, _)| *p).collect();
        assert_eq!(named, embedded, "every cut names its countries");
    }

    #[test]
    fn the_graph_covers_its_countries_and_nothing_between_them() {
        for (name, lat, lon) in [
            ("Limoges", 45.8472, 1.2848),
            ("Ajaccio", 41.92, 8.74),
            ("Madrid", 40.42, -3.70),
            ("Berlin", 52.52, 13.40),
            ("Nordkapp", 71.17, 25.78),
            ("Las Palmas", 28.12, -15.43),
            ("Agadir", 30.42, -9.60),
            ("Dakhla", 23.68, -15.96),
            ("Ceuta", 35.889, -5.32),
            ("Belfast", 54.6, -5.93),
            ("Monaco", 43.738, 7.42),
            ("the Venice lagoon", 45.430_38, 12.347_57),
        ] {
            assert!(covers(at(lat, lon)), "{name}");
        }
        for (name, lat, lon) in [
            (
                "Neum, Bosnia, between the two parts of Croatia",
                42.92,
                17.61,
            ),
            ("Sarajevo", 43.86, 18.41),
            ("Tirana", 41.33, 19.82),
            ("Belgrade", 44.8, 20.46),
            ("Budapest", 47.5, 19.04),
            ("Oran", 35.7, -0.63),
            ("Douglas, Isle of Man (its own extract)", 54.15, -4.48),
            ("St Helier, Jersey (its own extract)", 49.186, -2.107),
            ("Tórshavn (its own extract)", 62.01, -6.77),
            ("the middle of the Bay of Biscay", 45.0, -6.0),
        ] {
            assert!(!covers(at(lat, lon)), "{name}");
        }
    }

    #[test]
    fn france_is_its_own_cut() {
        assert!(in_france(at(45.8472, 1.2848)), "Limoges");
        assert!(in_france(at(41.92, 8.74)), "Ajaccio");
        assert!(in_france(at(51.03, 2.37)), "Dunkerque");
        assert!(!in_france(at(40.42, -3.70)), "Madrid");
        assert!(!in_france(at(50.85, 4.35)), "Brussels");
    }

    #[test]
    fn the_box_holds_every_cut() {
        let b = bounding_box();
        for r in regions() {
            let [west, south, east, north] = r.bounds();
            assert!(
                b.west() <= west && b.south() <= south && b.east() >= east && b.north() >= north
            );
        }
        assert!(b.south() < 24.0, "Western Sahara, in Morocco's cut");
        assert!(b.north() > 71.0, "Svalbard, in Norway's");
        assert!(countries().contains(&"MA"));
        assert!(!countries().contains(&"BA"));
    }

    #[test]
    fn a_cut_reads_its_parts_and_its_holes() {
        let text = "# a comment\nextract test/square\nnone\n1\n 0 0\n 10 0\n 10 10\n 0 10\n 0 0\nEND\n\
                    !2\n 4 4\n 6 4\n 6 6\n 4 6\nEND\nEND\n";
        let regions = parse(text).unwrap();
        assert_eq!(regions.len(), 1);
        let r = &regions[0];
        assert_eq!(r.path(), "test/square");
        assert!(r.contains(at(2.0, 2.0)));
        assert!(!r.contains(at(5.0, 5.0)), "inside the hole");
        assert!(!r.contains(at(11.0, 5.0)));
    }

    #[test]
    fn a_broken_cut_is_refused() {
        assert_eq!(
            parse("extract a\nnone\n1\n 0 0\n"),
            Err(InvalidCuts::Truncated)
        );
        assert!(matches!(
            parse("square\n"),
            Err(InvalidCuts::Line { line: 1, .. })
        ));
        assert!(matches!(
            parse("extract a\nnone\n1\n 0 0\n 1 x\nEND\nEND\n"),
            Err(InvalidCuts::Line { line: 5, .. })
        ));
        assert!(matches!(
            parse("extract a\nnone\n1\n 0 0\n 1 1\nEND\nEND\n"),
            Err(InvalidCuts::Line { .. })
        ));
        assert!(matches!(
            parse("extract a\nnone\n1\n 0 0\n 200 1\n 1 1\nEND\nEND\n"),
            Err(InvalidCuts::Line { .. })
        ));
    }
}
