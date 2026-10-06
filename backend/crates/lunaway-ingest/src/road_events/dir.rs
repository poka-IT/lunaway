//! The DIR feed "Évènements routiers - Réseau routier non concédé"
//! (transport.data.gouv.fr, Licence Ouverte 2.0): DATEX II 2.x situations
//! of the national roads the State runs, an hourly aggregate
//! (`content.xml`) and numbered increments published as situations change
//! (2 645 in 24 hours, `plan/research/20-travaux-temps-reel.md`, M3).
//!
//! Each situation record becomes an event, or is left out when it does
//! nothing a route must know (a speed limit, a broken-down car on the hard
//! shoulder). The rules of the French profile (Cerema, "Partie 1 :
//! publication d'une situation de trafic", 2015) and of what the feed
//! actually carries (the snapshot of 2026-10-06):
//!
//! - a slip road event is located on the main road, the slip road named by
//!   `reroutingManagementType` (`doNotUseEntry`, `doNotUseExit`) or by
//!   `affectedCarriagewayAndLanes/carriageway`: it is kept as a point with
//!   its carriageway, and the route check closes slip roads only;
//! - a section runs from its `from` to its `to` point in the direction of
//!   traffic when `tpegDirection` names one (354 of 360 one-way sections
//!   agree in the snapshot); `bothWays` concerns both carriageways;
//! - `validPeriod` names a period without hours ("Uniquement de nuit"),
//!   mapped to the wide windows of [`Schedule::from_label`];
//! - `management/lifeCycleManagement/end` ends a record.

use std::collections::BTreeMap;

use chrono::{DateTime, Utc};
use lunaway_db::road_events::NewEvent;
use lunaway_domain::{
    Position,
    road_events::{
        AppliesTo, Carriageway, Confidence, EndReason, EventClass, EventDirection, MatchQuality,
        Schedule, SourceGeometry, VehicleLimits, road, schedule::Period,
    },
};

use super::{
    ParseError, instant, padded_version, past_end,
    xml::{self, Node},
};

/// What a DIR publication holds.
#[derive(Debug, Clone, Default)]
pub struct Publication {
    /// When it was published.
    pub published_at: Option<DateTime<Utc>>,
    /// The number of the publication in the feed's sequence (`feedType`):
    /// increments from this number on are newer than the aggregate.
    pub feed_number: Option<u64>,
    /// Whether it is the whole aggregate (`snapshot`) rather than an
    /// increment.
    pub snapshot: bool,
    /// The situations, in order.
    pub situations: Vec<Situation>,
    /// Records left out, by reason.
    pub skipped: BTreeMap<String, usize>,
}

/// One version of a situation.
#[derive(Debug, Clone, Default)]
pub struct Situation {
    /// The situation's id.
    pub id: String,
    /// The events of its records.
    pub events: Vec<NewEvent>,
    /// The ids of the records of this version that were kept: a stored
    /// record missing from them is over, whether this version left it out,
    /// suspended it, or describes it in a way no longer read (a closure
    /// that became a slowdown).
    pub record_ids: Vec<String>,
    /// Records this version ends, kept or not.
    pub ended: Vec<String>,
}

/// Incidents rather than planned works: an open one ages in hours.
const UNPLANNED: [&str; 10] = [
    "Accident",
    "VehicleObstruction",
    "GeneralObstruction",
    "EnvironmentalObstruction",
    "InfrastructureDamageObstruction",
    "AnimalPresenceObstruction",
    "AbnormalTraffic",
    "NonWeatherRelatedRoadConditions",
    "WeatherRelatedRoadConditions",
    "PoorEnvironmentConditions",
];

/// Reads a DIR publication: the aggregate or an increment.
///
/// # Errors
///
/// [`ParseError`] when the document is not the expected DATEX II.
pub fn parse(body: &[u8], now: DateTime<Utc>) -> Result<Publication, ParseError> {
    let mut out = Publication::default();
    // Each situation is read as the walk meets it: the document's tree is
    // never held whole.
    let outside = xml::walk(body, "situation", |s| {
        situation(&s, body, now, &mut out);
        true
    })?;
    out.published_at = outside.get("publicationTime").and_then(instant);
    out.feed_number = outside.get("feedType").and_then(|n| n.trim().parse().ok());
    out.snapshot = outside.get("updateMethod") == Some("snapshot");
    if out.published_at.is_none() {
        return Err(ParseError::Shape(
            "a DIR publication without publicationTime",
        ));
    }
    Ok(out)
}

/// One situation's records into `out`.
fn situation(s: &Node, body: &[u8], now: DateTime<Utc>, out: &mut Publication) {
    let Some(id) = s.attr("id").map(str::to_owned) else {
        *out.skipped
            .entry("situation without id".into())
            .or_default() += 1;
        return;
    };
    let mut situation = Situation {
        id: id.clone(),
        ..Situation::default()
    };
    for record in s.children_named("situationRecord") {
        let Some(record_id) = record.attr("id") else {
            *out.skipped.entry("record without id".into()).or_default() += 1;
            continue;
        };
        if record.text_at(&["management", "lifeCycleManagement", "end"]) == Some("true") {
            situation.ended.push(record_id.to_owned());
        }
        let raw = std::str::from_utf8(&body[record.span.0..record.span.1])
            .unwrap_or_default()
            .to_owned();
        match event(&id, record_id, record, raw, now) {
            Ok(e) => {
                situation.record_ids.push(record_id.to_owned());
                situation.events.push(e);
            }
            Err(reason) => *out.skipped.entry(reason.to_owned()).or_default() += 1,
        }
    }
    out.situations.push(situation);
}

/// What a record does, its detail, its carriageway, whether it is an
/// incident; `Err` with the reason it is left out.
fn classify(record: &Node) -> Result<(EventClass, String, Option<Carriageway>), &'static str> {
    let kind = record.xsi_type.as_deref().unwrap_or_default();
    let management = record.text_at(&["roadOrCarriagewayOrLaneManagementType"]);
    let rerouting = record.text_at(&["reroutingManagementType"]);
    let constriction = record.text_at(&["impact", "trafficConstrictionType"]);
    let lanes: Vec<&str> = record
        .find_all("lane")
        .into_iter()
        .map(|l| l.text.as_str())
        .collect();
    let whole = lanes.contains(&"allLanesCompleteCarriageway");
    let limited = record.child("forVehiclesWithCharacteristicsOf").is_some();
    let class = match (management, rerouting, constriction) {
        (Some(m @ ("roadClosed" | "closedPermanentlyForTheWinter")), _, _) => {
            (EventClass::Closure, m, None)
        }
        (_, Some(r @ "doNotUseEntry"), _) => (EventClass::Closure, r, Some(Carriageway::Entry)),
        (_, Some(r @ "doNotUseExit"), _) => (EventClass::Closure, r, Some(Carriageway::Exit)),
        (_, _, Some(c @ ("roadBlocked" | "carriagewayBlocked"))) => (EventClass::Closure, c, None),
        (Some(m @ "laneClosures"), _, _) if whole => (EventClass::Closure, m, None),
        (Some(m), _, _) if limited || m == "weightRestrictionInOperation" => {
            (EventClass::VehicleLimit, m, None)
        }
        (
            Some(
                m @ ("laneClosures"
                | "singleAlternateLineTraffic"
                | "contraflow"
                | "narrowLanes"
                | "useOfSpecifiedLanesOrCarriagewaysAllowed"
                | "lanesDeviated"),
            ),
            _,
            _,
        ) => (EventClass::LaneRestriction, m, None),
        (_, Some(r), _) => (EventClass::Detour, r, None),
        (_, _, Some(c @ ("lanesBlocked" | "lanesPartiallyObstructed"))) => {
            (EventClass::LaneRestriction, c, None)
        }
        _ if matches!(kind, "MaintenanceWorks" | "ConstructionWorks") => {
            (EventClass::Works, kind, None)
        }
        _ => return Err("nothing a route must know"),
    };
    Ok((class.0, class.1.to_owned(), class.2))
}

fn carriageway_of(record: &Node, from_rerouting: Option<Carriageway>, road: bool) -> Carriageway {
    if let Some(c) = from_rerouting {
        return c;
    }
    let location = record.child("groupOfLocations");
    let stated = location.and_then(|l| {
        l.at(&[
            "supplementaryPositionalDescription",
            "affectedCarriagewayAndLanes",
            "carriageway",
        ])
        .map(|n| n.text.as_str())
    });
    match stated {
        Some("exitSlipRoad") => return Carriageway::Exit,
        Some("entrySlipRoad") => return Carriageway::Entry,
        Some("slipRoads" | "connectingCarriageway") => return Carriageway::Ramps,
        Some("mainCarriageway" | "parallelCarriageway") => return Carriageway::Main,
        _ => {}
    }
    let on_connector = location.is_some_and(|l| {
        l.find_all("locationDescriptor")
            .into_iter()
            .any(|d| d.text == "onConnector")
    });
    if on_connector {
        Carriageway::Ramps
    } else if road {
        Carriageway::Main
    } else {
        Carriageway::Unknown
    }
}

fn coordinates(n: &Node) -> Option<Position> {
    let c = n.find("pointCoordinates")?;
    let lat = c.text_at(&["latitude"])?.parse().ok()?;
    let lon = c.text_at(&["longitude"])?.parse().ok()?;
    Position::new(lat, lon).ok()
}

/// The geometry and the direction of a record's location.
fn place(record: &Node) -> Option<(SourceGeometry, EventDirection)> {
    let location = record.child("groupOfLocations")?;
    if let Some(linear) = location.child("tpegLinearLocation") {
        let mut from = coordinates(linear.child("from")?)?;
        let mut to = coordinates(linear.child("to")?)?;
        let direction = match linear.text_at(&["tpegDirection"]) {
            Some("bothWays" | "allDirections") => EventDirection::Both,
            Some("unknown") | None => EventDirection::Unknown,
            // The traffic against the order of the points: the section is
            // turned round, so that its points follow the traffic.
            Some("oppositeDirection") => {
                std::mem::swap(&mut from, &mut to);
                EventDirection::Forward
            }
            // The section is written from its start to its end in the
            // direction of traffic.
            Some(_) => EventDirection::Forward,
        };
        if from.distance_m(to) < 1.0 {
            return Some((SourceGeometry::Point(from), direction));
        }
        return Some((SourceGeometry::Lines(vec![vec![from, to]]), direction));
    }
    let point = location.child("tpegPointLocation")?;
    let at = coordinates(point)?;
    let direction = match point.text_at(&["tpegDirection"]) {
        Some("bothWays" | "allDirections") => EventDirection::Both,
        Some("northBound") => EventDirection::North,
        Some("southBound") => EventDirection::South,
        Some("eastBound") => EventDirection::East,
        Some("westBound") => EventDirection::West,
        _ => EventDirection::Unknown,
    };
    Some((SourceGeometry::Point(at), direction))
}

/// The compass direction of a record's `tpegDirection`, when it names one.
fn compass(record: &Node) -> Option<EventDirection> {
    let d = record.child("groupOfLocations")?.find("tpegDirection")?;
    match d.text.as_str() {
        "northBound" => Some(EventDirection::North),
        "southBound" => Some(EventDirection::South),
        "eastBound" => Some(EventDirection::East),
        "westBound" => Some(EventDirection::West),
        _ => None,
    }
}

/// The road number of a record: its linear element, or the link name of
/// its points.
fn road_of(record: &Node) -> Option<String> {
    let location = record.child("groupOfLocations")?;
    if let Some(n) = location
        .find("roadNumber")
        .and_then(|n| road::normalize(&n.text))
    {
        return Some(n);
    }
    location
        .find_all("name")
        .into_iter()
        .filter(|n| n.text_at(&["tpegOtherPointDescriptorType"]) == Some("linkName"))
        .find_map(|n| n.values_text().and_then(|t| road::normalize(&t)))
}

/// The vehicle limits a record sets for the vehicles above a figure.
fn limits_of(record: &Node) -> Option<VehicleLimits> {
    let v = record.child("forVehiclesWithCharacteristicsOf")?;
    let goods = v.children_named("vehicleType").any(|t| {
        matches!(
            t.text.as_str(),
            "lorry" | "heavyLorry" | "articulatedVehicle" | "heavyGoodsVehicle" | "goodsVehicle"
        )
    });
    let others = v.children_named("vehicleType").any(|t| {
        !matches!(
            t.text.as_str(),
            "lorry"
                | "heavyLorry"
                | "articulatedVehicle"
                | "heavyGoodsVehicle"
                | "goodsVehicle"
                | "anyVehicle"
        )
    });
    if others && !goods {
        // A limit for buses or cars only: not a motorhome's concern.
        return None;
    }
    // "greaterThan 7.5": the vehicles above 7.5 t are concerned, so 7.5 t is
    // the most allowed. A "lessThan" figure concerns small vehicles only.
    let figure = |path: &str, value: &str| -> Option<f64> {
        let c = v.child(path)?;
        let x: f64 = c.text_at(&[value])?.parse().ok()?;
        match c.text_at(&["comparisonOperator"])? {
            "greaterThan" => Some(x),
            "greaterThanOrEqualTo" => Some(x - 0.001),
            _ => None,
        }
        .filter(|x| x.is_finite() && *x > 0.0)
    };
    let limits = VehicleLimits {
        max_height_m: figure("heightCharacteristic", "vehicleHeight"),
        max_width_m: figure("widthCharacteristic", "vehicleWidth"),
        max_length_m: figure("lengthCharacteristic", "vehicleLength"),
        max_weight_t: figure("grossWeightCharacteristic", "grossVehicleWeight"),
        applies_to: if goods {
            AppliesTo::GoodsVehicles
        } else {
            AppliesTo::All
        },
    };
    (!limits.is_empty()).then_some(limits)
}

/// The schedule of a record: the named periods, the dated exceptions.
fn schedule_of(record: &Node, kind: &str) -> Schedule {
    let spec = record.at(&["validity", "validityTimeSpecification"]);
    let labels: Vec<String> = spec
        .map(|s| {
            s.children_named("validPeriod")
                .filter_map(|p| p.child("periodName").and_then(Node::values_text))
                .collect()
        })
        .unwrap_or_default();
    let mut schedule = match labels.first() {
        Some(label) => Schedule::from_label(label),
        None => Schedule::default(),
    };
    if let Some(spec) = spec {
        for e in spec.children_named("exceptionPeriod") {
            match (
                e.text_at(&["startOfPeriod"]).and_then(instant),
                e.text_at(&["endOfPeriod"]).and_then(instant),
            ) {
                (Some(from), Some(to)) if to > from => {
                    schedule.exceptions.push(Period { from, to })
                }
                _ => {
                    // A named exception ("week-end et jours fériés") has no
                    // hours: it is kept for the driver and never lifts the
                    // event, so a closure is not missed on a Saturday.
                    if let Some(name) = e.child("periodName").and_then(Node::values_text) {
                        let label = schedule.label.take();
                        schedule.label = Some(match label {
                            Some(l) => format!("{l}; sauf {name}"),
                            None => format!("sauf {name}"),
                        });
                    }
                }
            }
        }
    }
    schedule.unplanned = UNPLANNED.contains(&kind);
    schedule
}

fn comments(record: &Node, kind: &str) -> Vec<String> {
    record
        .children_named("generalPublicComment")
        .filter(|c| c.text_at(&["commentType"]) == Some(kind))
        .filter_map(|c| c.child("comment").and_then(Node::values_text))
        .collect()
}

fn event(
    situation: &str,
    id: &str,
    record: &Node,
    raw: String,
    now: DateTime<Utc>,
) -> Result<NewEvent, &'static str> {
    if record.text_at(&["validity", "validityStatus"]) == Some("suspended") {
        return Err("suspended");
    }
    let (class, detail, from_rerouting) = classify(record)?;
    let (geometry, direction) = place(record).ok_or("no usable location")?;
    let road_number = road_of(record);
    let carriageway = carriageway_of(record, from_rerouting, road_number.is_some());
    let spec = record
        .at(&["validity", "validityTimeSpecification"])
        .ok_or("no validity")?;
    let valid_from = spec
        .text_at(&["overallStartTime"])
        .and_then(instant)
        .ok_or("no start")?;
    let valid_to = spec
        .text_at(&["overallEndTime"])
        .and_then(instant)
        .filter(|end| *end >= valid_from);
    let limits = if class == EventClass::VehicleLimit {
        limits_of(record).ok_or("a limit without a figure for the vehicles above it")?
    } else {
        VehicleLimits::default()
    };
    let kind = record.xsi_type.as_deref().unwrap_or_default();
    let schedule = schedule_of(record, kind);
    let match_quality = match (&geometry, carriageway) {
        (_, Carriageway::Entry | Carriageway::Exit | Carriageway::Ramps) => MatchQuality::Ramp,
        (SourceGeometry::Point(_), _) => MatchQuality::Point,
        _ => MatchQuality::Pending,
    };
    // A slip road event is placed at its point on the main road: the start
    // of a section on a connector, with the compass direction the section
    // gives (the slip road rule compares it with the route's heading).
    let (geometry, direction) = match (match_quality, geometry) {
        (MatchQuality::Ramp, SourceGeometry::Lines(lines)) => (
            lines
                .first()
                .and_then(|l| l.first())
                .map(|p| SourceGeometry::Point(*p))
                .ok_or("no usable location")?,
            compass(record).unwrap_or(direction),
        ),
        (_, g) => (g, direction),
    };
    let mut description = comments(record, "description");
    description.extend(comments(record, "locationDescriptor"));
    let description = (!description.is_empty()).then(|| description.join(". "));
    let detour = record
        .child("reroutingItineraryDescription")
        .and_then(Node::values_text);
    let ended = if record.text_at(&["management", "lifeCycleManagement", "end"]) == Some("true") {
        Some(EndReason::SourceEnd)
    } else if past_end(valid_to, now) {
        Some(EndReason::PastEnd)
    } else {
        None
    };
    let version = record.attr("version").unwrap_or("0");
    Ok(NewEvent {
        external_id: id.to_owned(),
        external_version: padded_version(version),
        situation_id: Some(situation.to_owned()),
        class,
        detail,
        carriageway,
        direction,
        road_number,
        road_name: None,
        limits,
        valid_from,
        valid_to,
        schedule,
        geometry,
        match_quality,
        confidence: Confidence::Official,
        description,
        detour,
        url: None,
        source_updated_at: record
            .text_at(&["situationRecordVersionTime"])
            .and_then(instant),
        raw: super::cap_raw(raw),
        ended,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_section_against_the_order_of_its_points_is_turned_round() {
        let xml = br#"<r><publicationTime>2026-10-06T12:00:00+02:00</publicationTime><situation id="s"><situationRecord id="s-1" version="1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="RoadOrCarriagewayOrLaneManagement"><validity><validityTimeSpecification><overallStartTime>2026-10-06T10:00:00+02:00</overallStartTime></validityTimeSpecification></validity><roadOrCarriagewayOrLaneManagementType>roadClosed</roadOrCarriagewayOrLaneManagementType><groupOfLocations><tpegLinearLocation><tpegDirection>oppositeDirection</tpegDirection><to><pointCoordinates><latitude>42.95</latitude><longitude>1.62</longitude></pointCoordinates></to><from><pointCoordinates><latitude>43.0</latitude><longitude>1.61</longitude></pointCoordinates></from></tpegLinearLocation></groupOfLocations></situationRecord></situation></r>"#;
        let p = parse(xml, Utc::now()).unwrap();
        let e = &p.situations[0].events[0];
        assert_eq!(e.direction, EventDirection::Forward);
        let SourceGeometry::Lines(lines) = &e.geometry else {
            panic!("a section is a line");
        };
        assert!(
            (lines[0][0].lat() - 42.95).abs() < 1e-9,
            "the traffic runs from the `to` point: the line starts there"
        );
    }

    #[test]
    fn a_record_without_a_usable_location_is_left_out() {
        let xml = br#"<r><publicationTime>2026-10-06T12:00:00+02:00</publicationTime><situation id="s"><situationRecord id="s-1" version="1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="RoadOrCarriagewayOrLaneManagement"><validity><validityTimeSpecification><overallStartTime>2026-10-06T10:00:00+02:00</overallStartTime></validityTimeSpecification></validity><roadOrCarriagewayOrLaneManagementType>roadClosed</roadOrCarriagewayOrLaneManagementType></situationRecord></situation></r>"#;
        let p = parse(xml, Utc::now()).unwrap();
        assert!(p.situations[0].events.is_empty());
        assert_eq!(p.skipped.get("no usable location"), Some(&1));
        assert!(
            p.situations[0].record_ids.is_empty(),
            "a stored version of a record this version cannot read must end"
        );
    }
}
