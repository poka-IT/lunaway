//! The national feeds of the Netherlands and Spain, both DATEX II 3
//! situation publications read whole (`docs/data-sources.md`, "Road
//! events"; `plan/research/27-backend-communaute-travaux2.md`):
//!
//! - NDW's planning feed: every Dutch road authority's works and events,
//!   their closures and lane measures drawn as lines (WGS 84, latitude
//!   first), their vehicle limits, and the detour routes as lines;
//! - the DGT's incidents: Spanish closures, lane measures and limits on
//!   sections from one point to another, with their road names.
//!
//! The routing graph covers France only, so these events are not matched
//! to it (`road_event_sources.routed`); they are kept with their source
//! geometry, ready for the day it covers them, and shown as they are.
//!
//! Both feeds write a record per measure (`situationRecord`) with an id, a
//! version and a validity; a complete snapshot each time, so a record
//! missing from the next one ended.

use std::collections::BTreeMap;

use chrono::{DateTime, Duration, Utc};
use lunaway_db::road_events::NewEvent;
use lunaway_domain::{
    Position,
    road_events::{
        AppliesTo, Carriageway, Confidence, EventClass, EventDirection, MatchQuality, Schedule,
        SourceGeometry, VehicleLimits, road, schedule::Period,
    },
};

use super::{
    ParseError, cap_raw, instant, padded_version, past_end,
    xml::{self, Node},
};

/// How far ahead the Dutch planning is kept: a route starts at most 14 days
/// ahead (`RouteInput.departAt`), and the feed plans months of works.
pub const NDW_HORIZON: Duration = Duration::days(14);
/// Most lifted periods kept between the valid periods of one record: a
/// record of a thousand nights is kept as one span (it blocks between
/// them too, which a route can live with).
const MAX_GAPS: usize = 50;
/// Smallest gap between two valid periods kept as a lifted period.
const MIN_GAP: Duration = Duration::hours(1);
/// Below these, a limit is a typing slip (the DGT's 1.0 m widths on
/// motorways, 2026-10-06) and would close the road to every vehicle.
const MIN_WIDTH_M: f64 = 1.5;
const MIN_HEIGHT_M: f64 = 1.5;
const MIN_WEIGHT_T: f64 = 1.0;

/// What a feed's publication gave.
#[derive(Debug, Clone, Default)]
pub struct Publication {
    /// When it was published.
    pub published_at: Option<DateTime<Utc>>,
    /// The events kept.
    pub events: Vec<NewEvent>,
    /// Records read.
    pub records: usize,
    /// Records left out, by reason.
    pub skipped: BTreeMap<String, usize>,
}

impl Publication {
    fn skip(&mut self, why: &str) {
        *self.skipped.entry(why.to_owned()).or_default() += 1;
    }
}

/// Whom a record's vehicle conditions concern, for a motorhome.
#[derive(Debug, PartialEq, Eq)]
enum Concern {
    /// Every vehicle, or one a motorhome is among.
    All,
    /// Goods vehicles only: it warns a motorhome.
    Goods,
    /// Not a motor vehicle a motorhome is (bicycles, mopeds, buses).
    Others,
    /// An exception for some users (buses, emergency services) to the
    /// closure written beside it.
    Exception,
}

/// Vehicle types a motorhome is, or travels like.
const LIKE_A_MOTORHOME: [&str; 12] = [
    "anyVehicle",
    "car",
    "carOrLightVehicle",
    "carWithTrailer",
    "carWithCaravan",
    "camperVan",
    "motorhome",
    "van",
    "highSidedVehicle",
    "heavyVehicle",
    "fourWheelDrive",
    "vehicleWithCaravan",
];
/// Goods vehicles: a limit for them warns a motorhome.
const GOODS: [&str; 4] = ["lorry", "heavyLorry", "articulatedVehicle", "goodsVehicle"];

/// A positive figure at `path` below `node`.
fn figure(node: &Node, path: &[&str]) -> Option<f64> {
    node.text_at(path)?
        .trim()
        .parse::<f64>()
        .ok()
        .filter(|x| x.is_finite() && *x > 0.0)
}

/// The limits and whom they concern, from `forVehiclesWithCharacteristicsOf`
/// (every one of them: a record may list several). A figure is a limit
/// when its comparison says the vehicles above it are concerned; one too
/// small to be real (the DGT's 1.0 m widths on motorways) is dropped, and
/// the measure stays without it.
fn vehicles(record: &Node) -> (Concern, VehicleLimits) {
    let conditions = record.find_all("forVehiclesWithCharacteristicsOf");
    if conditions.is_empty() {
        return (Concern::All, VehicleLimits::default());
    }
    let mut types: Vec<&str> = Vec::new();
    let mut exception = false;
    let mut limits = VehicleLimits::default();
    let above = |c: &Node, characteristic: &str, value: &str| -> Option<f64> {
        let ch = c.child(characteristic)?;
        let op = ch.text_at(&["comparisonOperator"]).unwrap_or("greaterThan");
        matches!(op, "greaterThan" | "greaterThanOrEqualTo")
            .then(|| figure(ch, &[value]))
            .flatten()
    };
    let min = |a: Option<f64>, b: Option<f64>| match (a, b) {
        (Some(x), Some(y)) => Some(x.min(y)),
        (x, y) => x.or(y),
    };
    for c in &conditions {
        types.extend(c.children_named("vehicleType").map(|t| t.text.as_str()));
        if c.children_named("vehicleUsage").any(|u| {
            matches!(
                u.attr("_extendedValue").unwrap_or(u.text.as_str()),
                "emergencyServices" | "publicTransportation" | "patrol" | "roadOperator"
            )
        }) {
            exception = true;
        }
        let height = above(c, "heightCharacteristic", "vehicleHeight");
        let width = above(c, "widthCharacteristic", "vehicleWidth");
        let length = above(c, "lengthCharacteristic", "vehicleLength");
        let weight = above(c, "grossWeightCharacteristic", "grossVehicleWeight");
        limits.max_height_m = min(limits.max_height_m, height.filter(|h| *h >= MIN_HEIGHT_M));
        limits.max_width_m = min(limits.max_width_m, width.filter(|w| *w >= MIN_WIDTH_M));
        limits.max_length_m = min(limits.max_length_m, length);
        limits.max_weight_t = min(limits.max_weight_t, weight.filter(|w| *w >= MIN_WEIGHT_T));
    }
    let concern = if exception {
        Concern::Exception
    } else if types.is_empty() || types.iter().any(|t| LIKE_A_MOTORHOME.contains(t)) {
        Concern::All
    } else if types.iter().any(|t| GOODS.contains(t)) {
        Concern::Goods
    } else {
        Concern::Others
    };
    if matches!(concern, Concern::Goods) {
        limits.applies_to = AppliesTo::GoodsVehicles;
    }
    (concern, limits)
}

/// The validity of a record: its overall start and end, and the gaps
/// between its valid periods as lifted periods.
fn validity(record: &Node) -> Option<(DateTime<Utc>, Option<DateTime<Utc>>, Schedule)> {
    let spec = record.at(&["validity", "validityTimeSpecification"])?;
    let start = spec.text_at(&["overallStartTime"]).and_then(instant)?;
    let end = spec.text_at(&["overallEndTime"]).and_then(instant);
    let mut periods: Vec<(DateTime<Utc>, DateTime<Utc>)> = spec
        .children_named("validPeriod")
        .filter_map(|p| {
            Some((
                p.text_at(&["startOfPeriod"]).and_then(instant)?,
                p.text_at(&["endOfPeriod"]).and_then(instant)?,
            ))
        })
        .collect();
    periods.sort();
    // Valid periods, when there are any, are the only times the measure
    // applies within its overall start and end. A gap is a time no period
    // covers, counted from the end reached so far, not the previous
    // period's (a long period may cover shorter ones after it), and from
    // the overall start before the first period and up to the overall end
    // after the last.
    let mut exceptions = Vec::new();
    let mut covered_to: Option<DateTime<Utc>> = (!periods.is_empty()).then_some(start);
    for (from, to) in periods {
        if let Some(end) = covered_to
            && from - end >= MIN_GAP
        {
            exceptions.push(Period {
                from: end,
                to: from,
            });
        }
        covered_to = Some(covered_to.map_or(to, |end| end.max(to)));
    }
    if let (Some(covered), Some(overall_end)) = (covered_to, end)
        && overall_end - covered >= MIN_GAP
    {
        exceptions.push(Period {
            from: covered,
            to: overall_end,
        });
    }
    if exceptions.len() > MAX_GAPS {
        exceptions.clear();
    }
    Some((
        start,
        end,
        Schedule {
            exceptions,
            ..Schedule::default()
        },
    ))
}

/// Pairs of `posList` numbers, latitude first, as positions.
fn pos_list(text: &str) -> Vec<Position> {
    let numbers: Vec<f64> = text
        .split_whitespace()
        .filter_map(|n| n.parse().ok())
        .collect();
    numbers
        .as_chunks::<2>()
        .0
        .iter()
        .filter_map(|[lat, lon]| Position::new(*lat, *lon).ok())
        .collect()
}

/// Every line drawn below `node` (`gmlLineString/posList`), two points at
/// least each.
fn lines_below(node: &Node) -> Vec<Vec<Position>> {
    node.find_all("posList")
        .into_iter()
        .map(|p| pos_list(&p.text))
        .filter(|l| l.len() >= 2)
        .take(32)
        .collect()
}

/// The point of a `pointCoordinates` element.
fn coordinates(node: &Node) -> Option<Position> {
    let lat = figure_signed(node, "latitude")?;
    let lon = figure_signed(node, "longitude")?;
    Position::new(lat, lon).ok()
}

fn figure_signed(node: &Node, name: &str) -> Option<f64> {
    node.text_at(&[name])?
        .trim()
        .parse::<f64>()
        .ok()
        .filter(|x| x.is_finite())
}

/// The public comments of a record, internal notes left out.
fn public_comment(record: &Node) -> Option<String> {
    let texts: Vec<String> = record
        .children_named("generalPublicComment")
        .filter(|c| c.text_at(&["commentType"]) != Some("internalNote"))
        .filter_map(|c| c.child("comment").and_then(Node::values_text))
        .collect();
    (!texts.is_empty()).then(|| texts.join(". ").chars().take(2_000).collect())
}

fn raw_of(record: &Node, body: &[u8]) -> String {
    cap_raw(
        std::str::from_utf8(&body[record.span.0..record.span.1])
            .unwrap_or_default()
            .to_owned(),
    )
}

/// The facts both feeds give a record, before its geometry.
struct Base {
    id: String,
    version: String,
    situation: String,
    valid_from: DateTime<Utc>,
    valid_to: Option<DateTime<Utc>>,
    schedule: Schedule,
    updated_at: Option<DateTime<Utc>>,
}

fn base(situation: &str, record: &Node) -> Result<Base, &'static str> {
    let id = record.attr("id").ok_or("record without id")?;
    let (valid_from, valid_to, schedule) = validity(record).ok_or("no validity")?;
    Ok(Base {
        id: id.chars().take(200).collect(),
        version: padded_version(record.attr("version").unwrap_or("0")),
        situation: situation.chars().take(200).collect(),
        valid_from,
        valid_to: valid_to.filter(|t| *t >= valid_from),
        schedule,
        updated_at: record
            .text_at(&["situationRecordVersionTime"])
            .and_then(instant),
    })
}

/// The class of a lane or carriageway measure for whom it concerns: a
/// closure of the road or a carriageway, a limit when figures come with
/// it, a lane restriction otherwise. `Err` with the reason it is left out:
/// a measure that only lets some users through (the exception written
/// beside a closure), or one for goods vehicles without a figure (a
/// motorhome is not one, and a limit without a figure says nothing).
/// Goods vehicles' figures stay, as limits that warn a motorhome.
fn measure_class(
    term: &str,
    concern: &Concern,
    limits: &VehicleLimits,
) -> Result<EventClass, &'static str> {
    if term == "useOfSpecifiedLanesOrCarriagewaysAllowed" {
        return Err("an exception for some users");
    }
    if !limits.is_empty() {
        return Ok(EventClass::VehicleLimit);
    }
    if matches!(concern, Concern::Goods) {
        return Err("for goods vehicles only, without a figure");
    }
    Ok(match term {
        "roadClosed" | "carriagewayClosures" => EventClass::Closure,
        _ => EventClass::LaneRestriction,
    })
}

/// What a record says, beside its [`Base`].
struct Measure {
    class: EventClass,
    detail: String,
    geometry: SourceGeometry,
    limits: VehicleLimits,
    road_number: Option<String>,
    road_name: Option<String>,
    description: Option<String>,
}

fn new_event(b: Base, m: Measure, raw: String, now: DateTime<Utc>) -> NewEvent {
    NewEvent {
        external_id: b.id,
        external_version: b.version,
        situation_id: Some(b.situation),
        class: m.class,
        detail: m.detail.chars().take(100).collect(),
        carriageway: Carriageway::Main,
        // Neither feed ties a direction to the order of its points in a way
        // checked here; both directions, until the graph covers them and
        // the reading can be checked on routes.
        direction: EventDirection::Both,
        road_number: m.road_number,
        road_name: m.road_name,
        limits: m.limits,
        valid_from: b.valid_from,
        valid_to: b.valid_to,
        schedule: b.schedule,
        match_quality: match m.geometry {
            SourceGeometry::Lines(_) => MatchQuality::Pending,
            _ => MatchQuality::Unmatched,
        },
        geometry: m.geometry,
        confidence: Confidence::Official,
        description: m.description,
        detour: None,
        url: None,
        source_updated_at: b.updated_at,
        raw,
        ended: past_end(b.valid_to, now).then_some(lunaway_domain::road_events::EndReason::PastEnd),
    }
}

/// Reads NDW's planning feed: the closures, limits and lane measures
/// active at `now` or starting within [`NDW_HORIZON`], and the detour
/// routes drawn as lines.
///
/// # Errors
///
/// [`ParseError`] when the document is not the expected DATEX II 3.
pub fn parse_ndw(body: &[u8], now: DateTime<Utc>) -> Result<Publication, ParseError> {
    let mut out = Publication::default();
    let outside = xml::walk(body, "situation", |s| {
        ndw_situation(&s, body, now, &mut out);
        true
    })?;
    out.published_at = outside.get("publicationTime").and_then(instant);
    if out.published_at.is_none() {
        return Err(ParseError::Shape(
            "an NDW publication without publicationTime",
        ));
    }
    Ok(out)
}

fn ndw_situation(s: &Node, body: &[u8], now: DateTime<Utc>, out: &mut Publication) {
    let situation = s.attr("id").unwrap_or_default();
    for record in s.children_named("situationRecord") {
        out.records += 1;
        match ndw_record(situation, record, body, now) {
            Ok(e) => out.events.push(e),
            Err(why) => out.skip(why),
        }
    }
}

fn ndw_record(
    situation: &str,
    record: &Node,
    body: &[u8],
    now: DateTime<Utc>,
) -> Result<NewEvent, &'static str> {
    let kind = record.xsi_type.as_deref().unwrap_or_default();
    if !matches!(
        kind,
        "RoadOrCarriagewayOrLaneManagement" | "ReroutingManagement"
    ) {
        return Err("nothing a route must know");
    }
    let b = base(situation, record)?;
    if b.valid_to.is_some_and(|end| end < now - Duration::hours(1)) {
        return Err("over");
    }
    if b.valid_from > now + NDW_HORIZON {
        return Err("starts after the 14 days a route can start in");
    }
    let (concern, limits) = vehicles(record);
    match concern {
        Concern::Others => return Err("not for a motorhome (bicycles, mopeds, buses)"),
        Concern::Exception => return Err("an exception for buses or emergency services"),
        Concern::All | Concern::Goods => {}
    }
    let comment = public_comment(record);
    let source_name = record
        .at(&["source", "sourceName"])
        .and_then(Node::values_text);
    if kind == "ReroutingManagement" {
        let lines = record
            .child("alternativeRoute")
            .map(lines_below)
            .unwrap_or_default();
        if lines.is_empty() {
            return Err("a detour without its route");
        }
        let road = record
            .text_at(&["roadOrJunctionNumber"])
            .map(|r| r.chars().take(200).collect::<String>());
        let description = [
            record
                .child("reroutingItineraryDescription")
                .and_then(Node::values_text),
            road.clone(),
            comment,
            source_name,
        ];
        let description: Vec<String> = description.into_iter().flatten().collect();
        let mut e = new_event(
            b,
            Measure {
                class: EventClass::Detour,
                detail: record
                    .text_at(&["reroutingManagementType"])
                    .unwrap_or("detour")
                    .to_owned(),
                geometry: SourceGeometry::Lines(lines),
                limits: VehicleLimits::default(),
                road_number: road.as_deref().and_then(road::normalize),
                road_name: road,
                description: (!description.is_empty()).then(|| description.join(". ")),
            },
            raw_of(record, body),
            now,
        );
        // A detour is shown with its route, never placed on the graph: it
        // is advice for drivers of every vehicle, and Lunaway computes its
        // own way round.
        e.match_quality = MatchQuality::Unmatched;
        return Ok(e);
    }
    let term = record
        .text_at(&["roadOrCarriagewayOrLaneManagementType"])
        .ok_or("no measure")?;
    let class = measure_class(term, &concern, &limits)?;
    let reference = record.child("locationReference").ok_or("no location")?;
    let lines = lines_below(reference);
    let geometry = if lines.is_empty() {
        let point = reference
            .find("pointCoordinates")
            .and_then(coordinates)
            .ok_or("no geometry")?;
        SourceGeometry::Point(point)
    } else {
        SourceGeometry::Lines(lines)
    };
    let mut e = new_event(
        b,
        Measure {
            class,
            detail: term.to_owned(),
            geometry,
            limits,
            road_number: None,
            road_name: None,
            description: [comment, source_name]
                .into_iter()
                .flatten()
                .reduce(|a, b| format!("{a}. {b}")),
        },
        raw_of(record, body),
        now,
    );
    e.carriageway = match reference.find("carriageway").and_then(|c| {
        c.text_at(&["carriageway"])
            .or_else(|| (!c.text.is_empty()).then_some(c.text.as_str()))
    }) {
        Some("entrySlipRoad") => Carriageway::Entry,
        Some("exitSlipRoad") => Carriageway::Exit,
        Some("mainCarriageway") => Carriageway::Main,
        _ => Carriageway::Unknown,
    };
    Ok(e)
}

/// Reads the DGT's incidents: the closures, limits and lane measures on
/// sections from one point to another, or at a point.
///
/// # Errors
///
/// [`ParseError`] when the document is not the expected DATEX II 3.
pub fn parse_dgt(body: &[u8], now: DateTime<Utc>) -> Result<Publication, ParseError> {
    let mut out = Publication::default();
    let outside = xml::walk(body, "situation", |s| {
        let situation = s.attr("id").unwrap_or_default().to_owned();
        for record in s.children_named("situationRecord") {
            out.records += 1;
            match dgt_record(&situation, record, body, now) {
                Ok(e) => out.events.push(e),
                Err(why) => out.skip(why),
            }
        }
        true
    })?;
    out.published_at = outside.get("publicationTime").and_then(instant);
    if out.published_at.is_none() {
        return Err(ParseError::Shape(
            "a DGT publication without publicationTime",
        ));
    }
    Ok(out)
}

fn dgt_record(
    situation: &str,
    record: &Node,
    body: &[u8],
    now: DateTime<Utc>,
) -> Result<NewEvent, &'static str> {
    if record.xsi_type.as_deref() != Some("RoadOrCarriagewayOrLaneManagement") {
        return Err("nothing a route must know");
    }
    // The same element name also names a cause (`cause/detailedCauseType`):
    // only the record's own child is its measure.
    let term = record
        .child("roadOrCarriagewayOrLaneManagementType")
        .map(|t| t.text.as_str())
        .filter(|t| !t.is_empty())
        .ok_or("no measure")?;
    let b = base(situation, record)?;
    if b.valid_to.is_some_and(|end| end < now - Duration::hours(1)) {
        return Err("over");
    }
    let (concern, limits) = vehicles(record);
    match concern {
        Concern::Others => return Err("not for a motorhome (bicycles, mopeds, buses)"),
        Concern::Exception => return Err("an exception for buses or emergency services"),
        Concern::All | Concern::Goods => {}
    }
    let class = measure_class(term, &concern, &limits)?;
    let reference = record.child("locationReference").ok_or("no location")?;
    let geometry = if let Some(linear) = reference.child("tpegLinearLocation") {
        let from = linear
            .at(&["from", "pointCoordinates"])
            .and_then(coordinates);
        let to = linear.at(&["to", "pointCoordinates"]).and_then(coordinates);
        match (from, to) {
            (Some(a), Some(b)) if a.distance_m(b) >= 1.0 => SourceGeometry::Lines(vec![vec![a, b]]),
            (Some(a), _) | (None, Some(a)) => SourceGeometry::Point(a),
            (None, None) => return Err("no geometry"),
        }
    } else {
        SourceGeometry::Point(
            reference
                .find("pointCoordinates")
                .and_then(coordinates)
                .ok_or("no geometry")?,
        )
    };
    let info = reference.at(&["supplementaryPositionalDescription", "roadInformation"]);
    let road_name = info
        .and_then(|i| i.text_at(&["roadName"]))
        .map(|r| r.chars().take(200).collect::<String>());
    let place = reference
        .find("municipality")
        .map(|m| m.text.clone())
        .filter(|m| !m.is_empty());
    let description = [
        road_name.clone(),
        info.and_then(|i| i.text_at(&["roadDestination"]))
            .map(str::to_owned),
        place,
        public_comment(record),
    ];
    let description: Vec<String> = description.into_iter().flatten().collect();
    Ok(new_event(
        b,
        Measure {
            class,
            detail: term.to_owned(),
            geometry,
            limits,
            road_number: road_name.as_deref().and_then(road::normalize),
            road_name,
            description: (!description.is_empty()).then(|| description.join(". ")),
        },
        raw_of(record, body),
        now,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record(xml: &str) -> Node {
        let mut node = None;
        xml::walk(xml.as_bytes(), "r", |n| {
            node = Some(n);
            true
        })
        .unwrap();
        node.unwrap()
    }

    #[test]
    fn whom_a_measure_concerns_is_read_for_a_motorhome() {
        let of = |inner: &str| {
            let r = record(&format!(
                "<r><forVehiclesWithCharacteristicsOf>{inner}</forVehiclesWithCharacteristicsOf></r>"
            ));
            vehicles(&r)
        };
        let (concern, limits) = of("<vehicleType>lorry</vehicleType>");
        assert!(matches!(concern, Concern::Goods), "lorries only: it warns");
        assert_eq!(limits.applies_to, AppliesTo::GoodsVehicles);
        assert!(matches!(
            of("<vehicleType>bicycle</vehicleType><vehicleType>moped</vehicleType>").0,
            Concern::Others
        ));
        assert!(matches!(
            of("<vehicleType>bicycle</vehicleType><vehicleType>car</vehicleType>").0,
            Concern::All
        ));
        assert!(matches!(
            of(r#"<vehicleUsage _extendedValue="publicTransportation">_extended</vehicleUsage>"#).0,
            Concern::Exception
        ));
        let (concern, limits) = of(
            "<heightCharacteristic><comparisonOperator>greaterThan</comparisonOperator><vehicleHeight>4.5</vehicleHeight></heightCharacteristic>",
        );
        assert!(matches!(concern, Concern::All));
        assert_eq!(limits.max_height_m, Some(4.5));
        let (_, limits) = of(
            "<vehicleType>anyVehicle</vehicleType><widthCharacteristic><comparisonOperator>greaterThan</comparisonOperator><vehicleWidth>1.0</vehicleWidth></widthCharacteristic>",
        );
        assert_eq!(
            limits.max_width_m, None,
            "a 1.0 m width would close a motorway to every vehicle: a typing slip"
        );
        let (_, limits) = of(
            "<heightCharacteristic><comparisonOperator>lessThan</comparisonOperator><vehicleHeight>4.5</vehicleHeight></heightCharacteristic>",
        );
        assert_eq!(
            limits.max_height_m, None,
            "only vehicles above a figure are barred"
        );
    }

    #[test]
    fn a_closure_for_lorries_only_does_not_stop_a_motorhome() {
        let none = VehicleLimits::default();
        assert_eq!(
            measure_class("roadClosed", &Concern::Goods, &none),
            Err("for goods vehicles only, without a figure")
        );
        let weight = VehicleLimits {
            max_weight_t: Some(7.5),
            applies_to: AppliesTo::GoodsVehicles,
            ..VehicleLimits::default()
        };
        assert_eq!(
            measure_class("roadClosed", &Concern::Goods, &weight),
            Ok(EventClass::VehicleLimit),
            "a lorry's weight limit stays, to warn"
        );
        assert_eq!(
            measure_class("roadClosed", &Concern::All, &none),
            Ok(EventClass::Closure)
        );
    }

    #[test]
    fn a_long_period_covers_the_short_ones_after_it() {
        let (_, _, schedule) = validity(&record(
            "<r><validity><validityTimeSpecification>
            <overallStartTime>2026-10-06T00:00:00Z</overallStartTime>
            <validPeriod><startOfPeriod>2026-10-06T00:00:00Z</startOfPeriod><endOfPeriod>2026-10-06T10:00:00Z</endOfPeriod></validPeriod>
            <validPeriod><startOfPeriod>2026-10-06T02:00:00Z</startOfPeriod><endOfPeriod>2026-10-06T03:00:00Z</endOfPeriod></validPeriod>
            <validPeriod><startOfPeriod>2026-10-06T05:00:00Z</startOfPeriod><endOfPeriod>2026-10-06T08:00:00Z</endOfPeriod></validPeriod>
            <validPeriod><startOfPeriod>2026-10-06T12:00:00Z</startOfPeriod><endOfPeriod>2026-10-06T13:00:00Z</endOfPeriod></validPeriod>
            </validityTimeSpecification></validity></r>",
        ))
        .unwrap();
        assert_eq!(
            schedule.exceptions,
            [Period {
                from: instant("2026-10-06T10:00:00Z").unwrap(),
                to: instant("2026-10-06T12:00:00Z").unwrap(),
            }],
            "03:00 to 05:00 lies within 00:00 to 10:00: not lifted"
        );
    }

    #[test]
    fn the_time_outside_the_periods_is_lifted_up_to_the_overall_bounds() {
        let (_, _, schedule) = validity(&record(
            "<r><validity><validityTimeSpecification>
            <overallStartTime>2026-10-06T00:00:00Z</overallStartTime>
            <overallEndTime>2026-10-08T00:00:00Z</overallEndTime>
            <validPeriod><startOfPeriod>2026-10-06T20:00:00Z</startOfPeriod><endOfPeriod>2026-10-07T05:00:00Z</endOfPeriod></validPeriod>
            </validityTimeSpecification></validity></r>",
        ))
        .unwrap();
        assert_eq!(
            schedule.exceptions,
            [
                Period {
                    from: instant("2026-10-06T00:00:00Z").unwrap(),
                    to: instant("2026-10-06T20:00:00Z").unwrap(),
                },
                Period {
                    from: instant("2026-10-07T05:00:00Z").unwrap(),
                    to: instant("2026-10-08T00:00:00Z").unwrap(),
                },
            ],
            "one night within two days: the rest of the two days is lifted"
        );
        let (_, _, open) = validity(&record(
            "<r><validity><validityTimeSpecification>
            <overallStartTime>2026-10-06T00:00:00Z</overallStartTime>
            <overallEndTime>2026-10-08T00:00:00Z</overallEndTime>
            </validityTimeSpecification></validity></r>",
        ))
        .unwrap();
        assert!(
            open.exceptions.is_empty(),
            "without periods, the whole overall time applies"
        );
    }

    #[test]
    fn a_pos_list_is_read_latitude_first() {
        let l = pos_list("52.58548 6.128689 52.584437 6.129386 52.58");
        assert_eq!(l.len(), 2, "an odd number is left out");
        assert!((l[0].lat() - 52.585_48).abs() < 1e-9);
        assert!((l[0].lon() - 6.128_689).abs() < 1e-9);
    }

    #[test]
    fn gaps_between_valid_periods_are_lifted() {
        let xml = br#"<r><validity><validityTimeSpecification>
            <overallStartTime>2026-10-06T20:00:00Z</overallStartTime>
            <overallEndTime>2026-10-08T05:00:00Z</overallEndTime>
            <validPeriod><startOfPeriod>2026-10-07T20:00:00Z</startOfPeriod><endOfPeriod>2026-10-08T05:00:00Z</endOfPeriod></validPeriod>
            <validPeriod><startOfPeriod>2026-10-06T20:00:00Z</startOfPeriod><endOfPeriod>2026-10-07T05:00:00Z</endOfPeriod></validPeriod>
            </validityTimeSpecification></validity></r>"#;
        let (_, end, schedule) = validity(&record(std::str::from_utf8(xml).unwrap())).unwrap();
        assert!(end.is_some());
        assert_eq!(
            schedule.exceptions,
            [Period {
                from: instant("2026-10-07T05:00:00Z").unwrap(),
                to: instant("2026-10-07T20:00:00Z").unwrap(),
            }],
            "two nights: the day between is lifted"
        );
    }
}
