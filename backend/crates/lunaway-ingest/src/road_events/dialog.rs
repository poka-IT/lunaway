//! DiaLog, the national base of traffic orders (DGITM, Licence Ouverte
//! 2.0): DATEX II 3 `TrafficRegulationPublication` with DiaLog's GeoJSON
//! extension (`geoJsonGeometry`). Its temporary orders become road events
//! (closures, alternating traffic, temporary vehicle limits); its permanent
//! orders with a vehicle limit join the static restrictions every route is
//! checked against (`route_restrictions`, source `dialog`).
//!
//! DiaLog writes every maximum with `comparisonOperator =
//! lessThanOrEqualTo` (`templates/api/regulations.xml.twig`, commit
//! 60a7d9b of 2026-09-21: `<vehicleHeight>{{ vehicle.maxHeight }}`). Read as
//! DATEX II defines it, a "no entry for vehicles of 3.5 m or less" would
//! close a street to every car and open it to tall vehicles. The figures
//! agree with the OpenStreetMap and IGN maxima on the same sections far
//! beyond chance (`plan/research/21-backend-travaux.md`, part 3): the
//! figure is read as the maximum allowed. A weight DiaLog sets for heavy
//! goods vehicles concerns goods vehicles only, which a motorhome is not:
//! it warns.

use std::collections::BTreeMap;

use chrono::{DateTime, Utc, Weekday};
use lunaway_db::road_events::NewEvent;
use lunaway_domain::{
    Position,
    road_events::{
        AppliesTo, Carriageway, Confidence, EndReason, EventClass, EventDirection, MatchQuality,
        Schedule, SourceGeometry, VehicleLimits, road,
        schedule::{Window, Zone, day_bit},
    },
    routing::{
        Certainty, RestrictionFeature, RestrictionKind, RestrictionRecord, RestrictionSource,
        polyline,
    },
};

use super::{
    ParseError, cap_raw, instant, padded_version, past_end,
    xml::{self, Node},
};

/// Most points kept for one event: DiaLog's longest sections hold a few
/// thousand.
const MAX_POINTS: usize = 20_000;
/// The doubt on DiaLog's daily hours, minutes: they are written in UTC from
/// a local time converted on one date, so an hour off for half the year.
const UTC_DOUBT_MIN: u16 = 60;

/// What a DiaLog publication holds for road events.
#[derive(Debug, Clone, Default)]
pub struct Publication {
    /// Events of the temporary orders.
    pub events: Vec<NewEvent>,
    /// Orders read.
    pub orders: usize,
    /// Regulations left out, by reason.
    pub skipped: BTreeMap<String, usize>,
}

/// One condition of a regulation, flattened out of its condition sets.
fn leaf_conditions<'a>(node: &'a Node, out: &mut Vec<&'a Node>) {
    for c in node.children_named("conditions") {
        if c.xsi_type.as_deref() == Some("ConditionSet") {
            leaf_conditions(c, out);
        } else {
            out.push(c);
        }
    }
}

/// The lines, areas and points of a GeoJSON geometry.
#[derive(Default)]
struct Shapes {
    lines: Vec<Vec<Position>>,
    areas: Vec<Vec<Position>>,
    points: Vec<Position>,
}

fn position(c: &serde_json::Value) -> Option<Position> {
    Position::new(c.get(1)?.as_f64()?, c.get(0)?.as_f64()?).ok()
}

fn ring(c: &serde_json::Value) -> Vec<Position> {
    c.as_array()
        .map(|a| a.iter().filter_map(position).collect())
        .unwrap_or_default()
}

fn read_geojson(g: &serde_json::Value, out: &mut Shapes, depth: usize) {
    if depth > 4 {
        return;
    }
    let coords = g.get("coordinates");
    match g.get("type").and_then(serde_json::Value::as_str) {
        Some("Point") => out.points.extend(coords.and_then(position)),
        Some("MultiPoint") => out
            .points
            .extend(ring(coords.unwrap_or(&serde_json::Value::Null))),
        Some("LineString") => out
            .lines
            .push(ring(coords.unwrap_or(&serde_json::Value::Null))),
        Some("MultiLineString") => {
            for l in coords
                .and_then(serde_json::Value::as_array)
                .into_iter()
                .flatten()
            {
                out.lines.push(ring(l));
            }
        }
        Some("Polygon") => {
            if let Some(outer) = coords.and_then(|c| c.get(0)) {
                out.areas.push(ring(outer));
            }
        }
        Some("MultiPolygon") => {
            for p in coords
                .and_then(serde_json::Value::as_array)
                .into_iter()
                .flatten()
            {
                if let Some(outer) = p.get(0) {
                    out.areas.push(ring(outer));
                }
            }
        }
        Some("GeometryCollection") => {
            for sub in g
                .get("geometries")
                .and_then(serde_json::Value::as_array)
                .into_iter()
                .flatten()
            {
                read_geojson(sub, out, depth + 1);
            }
        }
        _ => {}
    }
}

fn shapes_of(conditions: &[&Node]) -> Shapes {
    let mut out = Shapes::default();
    for c in conditions {
        for g in c.find_all("geoJsonGeometry") {
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&g.text) {
                read_geojson(&v, &mut out, 0);
            }
        }
    }
    out.lines.retain(|l| l.len() >= 2);
    out.areas.retain(|a| a.len() >= 3);
    let mut budget = MAX_POINTS;
    for l in out.lines.iter_mut().chain(out.areas.iter_mut()) {
        l.truncate(budget);
        budget = budget.saturating_sub(l.len());
    }
    out.lines.retain(|l| l.len() >= 2);
    out.areas.retain(|a| a.len() >= 3);
    out
}

/// Minutes after midnight of a DiaLog time of day (`06:00:00+00:00`).
fn minutes(t: &str) -> Option<u16> {
    let mut parts = t.split([':', '+', '-', 'Z']);
    let h: u16 = parts.next()?.parse().ok()?;
    let m: u16 = parts.next()?.parse().ok()?;
    (h < 24 && m < 60).then_some(h * 60 + m)
}

fn weekday(day: &str) -> Option<Weekday> {
    Some(match day {
        "monday" => Weekday::Mon,
        "tuesday" => Weekday::Tue,
        "wednesday" => Weekday::Wed,
        "thursday" => Weekday::Thu,
        "friday" => Weekday::Fri,
        "saturday" => Weekday::Sat,
        "sunday" => Weekday::Sun,
        _ => return None,
    })
}

/// Validity of a regulation: the union of its validity conditions, within
/// the order's validity. The windows of every condition apply together:
/// wider than any one of them, never narrower.
fn validity(
    order: &Node,
    conditions: &[&Node],
) -> Option<(DateTime<Utc>, Option<DateTime<Utc>>, Schedule)> {
    let order_spec = order.at(&["validityByOrder", "validityTimeSpecification"]);
    let specs: Vec<&Node> = conditions
        .iter()
        .filter(|c| c.xsi_type.as_deref() == Some("ValidityCondition"))
        .filter_map(|c| c.at(&["validityByOrder", "validityTimeSpecification"]))
        .collect();
    let all: Vec<&Node> = if specs.is_empty() {
        order_spec.into_iter().collect()
    } else {
        specs
    };
    let from = all
        .iter()
        .filter_map(|s| s.text_at(&["overallStartTime"]).and_then(instant))
        .min()?;
    let ends: Vec<Option<DateTime<Utc>>> = all
        .iter()
        .map(|s| s.text_at(&["overallEndTime"]).and_then(instant))
        .collect();
    let to = if ends.iter().any(Option::is_none) {
        None
    } else {
        ends.into_iter().flatten().max()
    };
    let mut windows = Vec::new();
    let mut always = false;
    for s in &all {
        let periods: Vec<&Node> = s.children_named("validPeriod").collect();
        if periods.is_empty() {
            always = true;
        }
        for p in periods {
            let mut days = 0_u8;
            for d in p.find_all("applicableDay") {
                if let Some(w) = weekday(&d.text) {
                    days |= day_bit(w);
                }
            }
            if days == 0 {
                days = lunaway_domain::road_events::schedule::EVERY_DAY;
            }
            let times: Vec<&Node> = p.children_named("recurringTimePeriodOfDay").collect();
            if times.is_empty() {
                windows.push(Window {
                    days,
                    start_min: 0,
                    end_min: 0,
                });
            }
            for t in times {
                if let (Some(start_min), Some(end_min)) = (
                    t.text_at(&["startTimeOfPeriod"]).and_then(minutes),
                    t.text_at(&["endTimeOfPeriod"]).and_then(minutes),
                ) {
                    windows.push(Window {
                        days,
                        start_min,
                        end_min,
                    });
                }
            }
        }
    }
    let schedule = if always || windows.is_empty() {
        Schedule::default()
    } else {
        Schedule {
            windows,
            zone: Zone::Utc,
            widen_min: UTC_DOUBT_MIN,
            ..Schedule::default()
        }
    };
    Some((from, to.filter(|t| *t >= from), schedule))
}

/// What a regulation's vehicle conditions make of it: a closure to all
/// (none restricts a kind of vehicle, or only exemptions are listed), a
/// limit, or nothing for a motorhome (`None`: a ban of goods vehicles,
/// bicycles, hazardous loads).
enum Vehicles {
    All,
    Limits(VehicleLimits),
    Others,
}

fn vehicles(conditions: &[&Node]) -> Vehicles {
    let restricted: Vec<&Node> = conditions
        .iter()
        .copied()
        .filter(|c| {
            matches!(
                c.xsi_type.as_deref(),
                Some("VehicleCondition" | "NonVehicularRoadUserCondition")
            ) && c.text_at(&["negate"]) != Some("true")
        })
        .collect();
    if restricted.is_empty() {
        return Vehicles::All;
    }
    let mut limits = VehicleLimits::default();
    let mut goods_weight = None;
    for c in &restricted {
        let Some(v) = c.child("vehicleCharacteristics") else {
            continue;
        };
        let figure = |name: &str, value: &str| -> Option<f64> {
            v.child(name)?
                .text_at(&[value])?
                .parse::<f64>()
                .ok()
                .filter(|x| x.is_finite() && *x > 0.0)
        };
        let min = |a: Option<f64>, b: Option<f64>| match (a, b) {
            (Some(x), Some(y)) => Some(x.min(y)),
            (x, y) => x.or(y),
        };
        limits.max_height_m = min(
            limits.max_height_m,
            figure("heightCharacteristic", "vehicleHeight"),
        );
        limits.max_width_m = min(
            limits.max_width_m,
            figure("widthCharacteristic", "vehicleWidth"),
        );
        limits.max_length_m = min(
            limits.max_length_m,
            figure("lengthCharacteristic", "vehicleLength"),
        );
        let weight = figure("grossWeightCharacteristic", "grossVehicleWeight");
        let goods = v
            .children_named("vehicleType")
            .any(|t| t.text == "heavyGoodsVehicle");
        if goods {
            goods_weight = min(goods_weight, weight);
        } else {
            limits.max_weight_t = min(limits.max_weight_t, weight);
        }
    }
    if limits.is_empty() {
        return match goods_weight {
            Some(w) => Vehicles::Limits(VehicleLimits {
                max_weight_t: Some(w),
                applies_to: AppliesTo::GoodsVehicles,
                ..VehicleLimits::default()
            }),
            None => Vehicles::Others,
        };
    }
    Vehicles::Limits(limits)
}

/// The class and detail of a regulation, if it is one a route must know.
fn kind_of(regulation: &Node) -> Option<(EventClass, String)> {
    let t = regulation.child("typeOfRegulation")?;
    match t.xsi_type.as_deref()? {
        "AccessRestriction" => {
            let sub = t.text_at(&["accessRestrictionType"]).unwrap_or("noEntry");
            Some((EventClass::Closure, sub.to_owned()))
        }
        "RoadOrCarriagewayOrLaneManagement" => {
            let sub = t
                .text_at(&["roadOrCarriagewayOrLaneManagementType"])
                .unwrap_or("laneManagement");
            let class = if sub == "roadClosed" {
                EventClass::Closure
            } else {
                EventClass::LaneRestriction
            };
            Some((class, sub.to_owned()))
        }
        _ => None,
    }
}

fn road_info(conditions: &[&Node]) -> (Option<String>, Option<String>) {
    let mut number = None;
    let mut name = None;
    for c in conditions {
        for r in c.find_all("roadInformation") {
            number = number.or_else(|| r.text_at(&["roadNumber"]).and_then(road::normalize));
            name = name.or_else(|| r.text_at(&["roadName"]).map(str::to_owned));
        }
    }
    (number, name)
}

/// Whether an order is permanent: no end at the order's level.
fn permanent(order: &Node) -> bool {
    order
        .text_at(&[
            "validityByOrder",
            "validityTimeSpecification",
            "overallEndTime",
        ])
        .is_none()
}

/// Reads the temporary orders of a DiaLog publication as road events.
///
/// # Errors
///
/// [`ParseError`] when the document is not the expected DATEX II.
pub fn parse_temporary(body: &[u8], now: DateTime<Utc>) -> Result<Publication, ParseError> {
    let mut out = Publication::default();
    // Each order is read as the walk meets it: the document's tree is never
    // held whole.
    xml::walk(body, "trafficRegulationOrder", |order| {
        temporary_order(&order, body, now, &mut out);
        true
    })?;
    Ok(out)
}

/// One temporary order's events into `out`.
fn temporary_order(order: &Node, body: &[u8], now: DateTime<Utc>, out: &mut Publication) {
    let skip = |out: &mut Publication, why: &str| {
        *out.skipped.entry(why.to_owned()).or_default() += 1;
    };
    out.orders += 1;
    let Some(order_id) = order.attr("id").map(str::to_owned) else {
        skip(out, "order without id");
        return;
    };
    if permanent(order) {
        skip(out, "permanent order");
        return;
    }
    let version = padded_version(order.attr("version").unwrap_or("0"));
    let description = [
        order.child("description").and_then(Node::values_text),
        order.child("issuingAuthority").and_then(Node::values_text),
    ]
    .into_iter()
    .flatten()
    .collect::<Vec<_>>()
    .join(". ");
    let url = order.find("publicUrl").map(|n| n.text.clone());
    let raw = std::str::from_utf8(&body[order.span.0..order.span.1])
        .unwrap_or_default()
        .to_owned();
    for (i, regulation) in order.children_named("trafficRegulation").enumerate() {
        if regulation
            .text_at(&["status"])
            .is_some_and(|s| s != "active")
        {
            skip(out, "inactive regulation");
            continue;
        }
        let Some((class, detail)) = kind_of(regulation) else {
            skip(out, "speed, parking or overtaking rule");
            continue;
        };
        let mut conditions = Vec::new();
        if let Some(c) = regulation.child("condition") {
            if c.xsi_type.as_deref() == Some("ConditionSet") {
                leaf_conditions(c, &mut conditions);
            } else {
                conditions.push(c);
            }
        }
        let (class, limits) = match (class, vehicles(&conditions)) {
            (EventClass::Closure, Vehicles::All) => (EventClass::Closure, VehicleLimits::default()),
            (EventClass::Closure, Vehicles::Limits(l)) => (EventClass::VehicleLimit, l),
            (EventClass::Closure, Vehicles::Others) => {
                skip(out, "for other vehicles");
                continue;
            }
            (c, _) => (c, VehicleLimits::default()),
        };
        let Some((valid_from, valid_to, schedule)) = validity(order, &conditions) else {
            skip(out, "no validity");
            continue;
        };
        let shapes = shapes_of(&conditions);
        let (geometry, match_quality) = if !shapes.lines.is_empty() {
            (SourceGeometry::Lines(shapes.lines), MatchQuality::Pending)
        } else if !shapes.areas.is_empty() {
            (
                SourceGeometry::Polygons(shapes.areas),
                MatchQuality::Unmatched,
            )
        } else if let Some(p) = shapes.points.first() {
            // A point stands for a section DiaLog could not draw (a D949
            // stretch of 370 m rendered by one point): a warning.
            (SourceGeometry::Point(*p), MatchQuality::Unmatched)
        } else {
            skip(out, "no geometry");
            continue;
        };
        let (road_number, road_name) = road_info(&conditions);
        let ended = past_end(valid_to, now).then_some(EndReason::PastEnd);
        out.events.push(NewEvent {
            external_id: format!("{order_id}#{i}"),
            external_version: version.clone(),
            situation_id: Some(order_id.clone()),
            class,
            detail,
            carriageway: Carriageway::Main,
            direction: EventDirection::Both,
            road_number,
            road_name,
            limits,
            valid_from,
            valid_to,
            schedule,
            geometry,
            match_quality,
            confidence: Confidence::Official,
            description: (!description.is_empty()).then(|| description.clone()),
            detour: None,
            url: url.clone(),
            source_updated_at: None,
            raw: cap_raw(raw.clone()),
            ended,
        });
    }
}

/// What the permanent orders give the static restrictions.
#[derive(Debug, Clone, Default)]
pub struct Permanent {
    /// The restrictions, each with its points.
    pub records: Vec<(RestrictionRecord, Vec<Position>)>,
    /// Permanent orders read.
    pub orders: usize,
    /// Regulations left out, by reason.
    pub skipped: BTreeMap<String, usize>,
}

/// Reads the permanent orders of a DiaLog publication that set a height,
/// width, length or weight limit, as restrictions of source `dialog`.
///
/// # Errors
///
/// [`ParseError`] when the document is not the expected DATEX II.
pub fn parse_permanent(body: &[u8], fetched_at: DateTime<Utc>) -> Result<Permanent, ParseError> {
    let mut out = Permanent::default();
    // The 78 MB export is read order by order, never held as a tree.
    xml::walk(body, "trafficRegulationOrder", |order| {
        if permanent(&order) {
            permanent_order(&order, fetched_at, &mut out);
        }
        true
    })?;
    Ok(out)
}

/// One permanent order's restrictions into `out`.
fn permanent_order(order: &Node, fetched_at: DateTime<Utc>, out: &mut Permanent) {
    let skip = |out: &mut Permanent, why: &str| {
        *out.skipped.entry(why.to_owned()).or_default() += 1;
    };
    out.orders += 1;
    let Some(order_id) = order.attr("id") else {
        return;
    };
    for (i, regulation) in order.children_named("trafficRegulation").enumerate() {
        let is_no_entry = regulation.child("typeOfRegulation").is_some_and(|t| {
            t.xsi_type.as_deref() == Some("AccessRestriction")
                && t.text_at(&["accessRestrictionType"]).unwrap_or("noEntry") == "noEntry"
        });
        if !is_no_entry
            || regulation
                .text_at(&["status"])
                .is_some_and(|s| s != "active")
        {
            continue;
        }
        let mut conditions = Vec::new();
        if let Some(c) = regulation.child("condition") {
            leaf_conditions(c, &mut conditions);
        }
        let Vehicles::Limits(limits) = vehicles(&conditions) else {
            continue;
        };
        // A limit for some hours only (a goods vehicle ban from 7:00 to
        // 19:00) is not a physical limit: left to the road events.
        let timed = conditions.iter().any(|c| {
            c.xsi_type.as_deref() == Some("ValidityCondition") && c.find("validPeriod").is_some()
        });
        if timed {
            skip(out, "limited to some hours");
            continue;
        }
        let shapes = shapes_of(&conditions);
        let mut pieces = shapes.lines;
        pieces.extend(shapes.points.into_iter().map(|p| vec![p]));
        if pieces.is_empty() {
            skip(out, "no line or point");
            continue;
        }
        let (_, road_name) = road_info(&conditions);
        let road_name = road_name.filter(|n| n.chars().count() <= 200);
        let kinds = [
            (RestrictionKind::MaxHeight, limits.max_height_m),
            (RestrictionKind::MaxWidth, limits.max_width_m),
            (RestrictionKind::MaxLength, limits.max_length_m),
            (
                if limits.applies_to == AppliesTo::GoodsVehicles {
                    RestrictionKind::MaxWeightGoods
                } else {
                    RestrictionKind::MaxWeight
                },
                limits.max_weight_t,
            ),
        ];
        for (kind, value) in kinds {
            let Some(value) = value.filter(|v| *v <= 100.0) else {
                continue;
            };
            for points in &pieces {
                let record = RestrictionRecord {
                    source: RestrictionSource::Dialog,
                    external_id: format!("dialog/{order_id}#{i}"),
                    kind,
                    limit: Some(value),
                    certainty: Certainty::Known,
                    feature: RestrictionFeature::Road,
                    name: road_name.clone(),
                    other_value: None,
                    other_source: None,
                    shape: polyline::encode(points),
                    observed_at: fetched_at,
                };
                match record.check() {
                    Ok(p) => out.records.push((record, p)),
                    Err(_) => skip(out, "refused by the restriction rules"),
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn daily_hours_read_as_minutes() {
        assert_eq!(minutes("06:00:00+00:00"), Some(360));
        assert_eq!(minutes("16:30:00+00:00"), Some(990));
        assert_eq!(minutes("25:00:00"), None);
        assert_eq!(minutes("x"), None);
    }
}
