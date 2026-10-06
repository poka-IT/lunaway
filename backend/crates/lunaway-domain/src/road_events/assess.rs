//! What a road event met on a route means for one vehicle, at the time the
//! vehicle gets there.
//!
//! A closure or a vehicle limit the vehicle exceeds blocks, and the route
//! is computed again around it. A block needs four things: the event is on
//! the road the route takes (matched to the graph, or found by the slip
//! road and point rules of [`super::along`]), its source was read recently,
//! a user report is confirmed by a second account, and the event is not an
//! old record without an end. Without one of them the event warns. A lane
//! restriction warns; works and detours inform.

use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};

use super::{
    AppliesTo, Confidence, EventClass, MatchQuality, VehicleLimits,
    schedule::{Activity, Schedule},
};
use crate::routing::{
    RoutingDimensions,
    restriction::{HEIGHT_MARGIN_M, WIDTH_MARGIN_M},
};

/// An event without an end date whose last version is older than this
/// stops blocking: works records the DIR leave open for years exist (41
/// records with an end long past were still published on 2026-10-06).
/// Threshold: an assumption to adjust on real use.
pub const PLANNED_AGE: Duration = Duration::days(30);
/// The same for an incident (accident, obstacle, broken-down vehicle): an
/// open one older than this is most likely cleared.
pub const UNPLANNED_AGE: Duration = Duration::hours(12);

/// How a road event weighs on a route.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum EventSeverity {
    /// The vehicle may not pass: the route goes around it.
    Blocking,
    /// The vehicle may pass; the driver is told.
    Warning,
    /// Worth knowing: works, a detour advised for others.
    Info,
}

/// Why an event weighs the way it does.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum EventReason {
    /// The road is closed.
    Closed,
    /// A limit below the vehicle's figure.
    LimitExceeded,
    /// A height or width limit the vehicle passes with little margin.
    NearLimit,
    /// Lanes closed, alternating traffic, narrow lanes.
    LaneRestriction,
    /// Works without a measure that stops the vehicle.
    Works,
    /// A detour is signposted or advised.
    Detour,
    /// The event could not be placed on the road network, or a slip road
    /// it closes could not be told apart from the carriageway beside it:
    /// it may or may not be on the route.
    Unmatched,
    /// Its source has not been read for longer than it stays trusted.
    Stale,
    /// Outside the hours assumed for a period the source names without
    /// hours ("de nuit"): it may still apply.
    OutsideAssumedHours,
    /// A limit for heavy goods vehicles, which a motorhome is not.
    GoodsVehiclesOnly,
    /// One user reported it; a second account confirms it.
    Unconfirmed,
    /// An open record whose last version is old.
    Aged,
    /// The route starts or ends inside it: no route avoids it.
    AlreadyInside,
}

/// Which figure of a limit is compared.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum LimitKind {
    /// Height, metres.
    Height,
    /// Width, metres.
    Width,
    /// Length, metres.
    Length,
    /// Total authorised mass, tonnes.
    Weight,
}

/// What an event means for the vehicle.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct EventFinding {
    /// Whether the vehicle may pass.
    pub severity: EventSeverity,
    /// Why.
    pub reason: EventReason,
    /// The figure compared, for a vehicle limit.
    pub limit: Option<(LimitKind, f64)>,
    /// The vehicle's figure it was compared with.
    pub vehicle_value: Option<f64>,
}

/// The facts of an event the weighing reads.
#[derive(Debug, Clone, PartialEq)]
pub struct EventFacts<'a> {
    /// What it does.
    pub class: EventClass,
    /// Its limits, for a vehicle limit.
    pub limits: VehicleLimits,
    /// Validity start.
    pub valid_from: DateTime<Utc>,
    /// Validity end, if any.
    pub valid_to: Option<DateTime<Utc>>,
    /// When within the validity.
    pub schedule: &'a Schedule,
    /// How far it is to be believed.
    pub confidence: Confidence,
    /// How it was placed on the graph.
    pub match_quality: MatchQuality,
    /// Its source's last version of it.
    pub updated_at: DateTime<Utc>,
}

/// The circumstances of the meeting.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EventContext {
    /// Now.
    pub now: DateTime<Utc>,
    /// When the vehicle gets there.
    pub arrival: DateTime<Utc>,
    /// Whether the event's source was read recently enough.
    pub source_fresh: bool,
    /// Whether the route starts or ends inside the event: no route avoids
    /// it, so it warns.
    pub at_an_end: bool,
}

/// The first limit of `limits` the vehicle exceeds, or else the first it
/// passes with less than the height or width margin.
fn weigh_limits(limits: &VehicleLimits, dims: &RoutingDimensions) -> Option<EventFinding> {
    let figures = [
        (LimitKind::Height, limits.max_height_m, dims.height_m),
        (LimitKind::Width, limits.max_width_m, dims.width_m),
        (LimitKind::Length, limits.max_length_m, dims.length_m),
        (LimitKind::Weight, limits.max_weight_t, dims.weight_t),
    ];
    let exceeded = figures
        .iter()
        .find_map(|(k, l, v)| l.filter(|l| *v > *l + 1e-9).map(|l| (*k, l, *v)));
    if let Some((kind, limit, value)) = exceeded {
        let (severity, reason) = match limits.applies_to {
            AppliesTo::All => (EventSeverity::Blocking, EventReason::LimitExceeded),
            AppliesTo::GoodsVehicles => (EventSeverity::Warning, EventReason::GoodsVehiclesOnly),
        };
        return Some(EventFinding {
            severity,
            reason,
            limit: Some((kind, limit)),
            vehicle_value: Some(value),
        });
    }
    let close = [
        (
            LimitKind::Height,
            limits.max_height_m,
            dims.height_m,
            HEIGHT_MARGIN_M,
        ),
        (
            LimitKind::Width,
            limits.max_width_m,
            dims.width_m,
            WIDTH_MARGIN_M,
        ),
    ];
    close.iter().find_map(|(k, l, v, m)| {
        l.filter(|l| l - v < *m).map(|l| EventFinding {
            severity: EventSeverity::Warning,
            reason: EventReason::NearLimit,
            limit: Some((*k, l)),
            vehicle_value: Some(*v),
        })
    })
}

/// What `event` means for a vehicle of `dims` arriving at `ctx.arrival`:
/// `None` when it does not apply then, or does not concern the vehicle.
#[must_use]
pub fn assess(
    event: &EventFacts<'_>,
    dims: &RoutingDimensions,
    ctx: &EventContext,
) -> Option<EventFinding> {
    let activity = event
        .schedule
        .activity(event.valid_from, event.valid_to, ctx.arrival);
    let outside_assumed = match activity {
        Activity::Active => false,
        Activity::OutsideWindow if event.schedule.assumed => true,
        _ => return None,
    };
    let base = match event.class {
        EventClass::Closure => EventFinding {
            severity: EventSeverity::Blocking,
            reason: EventReason::Closed,
            limit: None,
            vehicle_value: None,
        },
        EventClass::VehicleLimit => weigh_limits(&event.limits, dims)?,
        EventClass::LaneRestriction => EventFinding {
            severity: EventSeverity::Warning,
            reason: EventReason::LaneRestriction,
            limit: None,
            vehicle_value: None,
        },
        EventClass::Works => EventFinding {
            severity: EventSeverity::Info,
            reason: EventReason::Works,
            limit: None,
            vehicle_value: None,
        },
        EventClass::Detour => EventFinding {
            severity: EventSeverity::Info,
            reason: EventReason::Detour,
            limit: None,
            vehicle_value: None,
        },
    };
    if base.severity != EventSeverity::Blocking {
        return Some(base);
    }
    let age_limit = if event.schedule.unplanned {
        UNPLANNED_AGE
    } else {
        PLANNED_AGE
    };
    let demoted = if !matches!(
        event.match_quality,
        MatchQuality::Matched | MatchQuality::Ramp | MatchQuality::Point
    ) {
        Some(EventReason::Unmatched)
    } else if !ctx.source_fresh {
        Some(EventReason::Stale)
    } else if event.confidence == Confidence::Reported {
        Some(EventReason::Unconfirmed)
    } else if event.valid_to.is_none() && ctx.now - event.updated_at > age_limit {
        Some(EventReason::Aged)
    } else if ctx.at_an_end {
        Some(EventReason::AlreadyInside)
    } else if outside_assumed {
        Some(EventReason::OutsideAssumedHours)
    } else {
        None
    };
    Some(match demoted {
        Some(reason) => EventFinding {
            severity: EventSeverity::Warning,
            reason,
            ..base
        },
        None => base,
    })
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone as _;

    use super::*;

    fn dims() -> RoutingDimensions {
        RoutingDimensions {
            height_m: 3.3,
            width_m: 2.35,
            length_m: 7.4,
            weight_t: 3.5,
            axle_load_t: None,
            trailer_weight_t: None,
            top_speed_kph: None,
        }
    }

    fn now() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 10, 6, 10, 0, 0).unwrap()
    }

    fn ctx(arrival: DateTime<Utc>) -> EventContext {
        EventContext {
            now: now(),
            arrival,
            source_fresh: true,
            at_an_end: false,
        }
    }

    fn closure(schedule: &Schedule) -> EventFacts<'_> {
        EventFacts {
            class: EventClass::Closure,
            limits: VehicleLimits::default(),
            valid_from: now() - Duration::hours(1),
            valid_to: Some(now() + Duration::hours(3)),
            schedule,
            confidence: Confidence::Official,
            match_quality: MatchQuality::Matched,
            updated_at: now() - Duration::hours(2),
        }
    }

    #[test]
    fn a_closure_blocks_only_while_the_vehicle_would_meet_it() {
        let s = Schedule::default();
        let e = closure(&s);
        assert_eq!(
            assess(&e, &dims(), &ctx(now() + Duration::hours(1))).map(|f| f.severity),
            Some(EventSeverity::Blocking)
        );
        assert_eq!(
            assess(&e, &dims(), &ctx(now() + Duration::hours(5))),
            None,
            "a vehicle arriving after the reopening is not sent around"
        );
        let later = EventFacts {
            valid_from: now() + Duration::hours(2),
            ..closure(&s)
        };
        assert_eq!(
            assess(&later, &dims(), &ctx(now() + Duration::hours(1))),
            None,
            "nor one arriving before it closes"
        );
        assert_eq!(
            assess(&later, &dims(), &ctx(now() + Duration::hours(2))).map(|f| f.severity),
            Some(EventSeverity::Blocking),
            "the time that counts is the arrival, not the departure"
        );
    }

    #[test]
    fn a_closure_never_blocks_on_weak_evidence() {
        let s = Schedule::default();
        let arrival = now() + Duration::minutes(30);
        let reason = |e: &EventFacts<'_>, c: &EventContext| {
            assess(e, &dims(), c).map(|f| (f.severity, f.reason))
        };
        let warning = |r| Some((EventSeverity::Warning, r));
        let unmatched = EventFacts {
            match_quality: MatchQuality::Unmatched,
            ..closure(&s)
        };
        assert_eq!(
            reason(&unmatched, &ctx(arrival)),
            warning(EventReason::Unmatched)
        );
        let stale = EventContext {
            source_fresh: false,
            ..ctx(arrival)
        };
        assert_eq!(reason(&closure(&s), &stale), warning(EventReason::Stale));
        let reported = EventFacts {
            confidence: Confidence::Reported,
            ..closure(&s)
        };
        assert_eq!(
            reason(&reported, &ctx(arrival)),
            warning(EventReason::Unconfirmed)
        );
        let confirmed = EventFacts {
            confidence: Confidence::Confirmed,
            ..closure(&s)
        };
        assert_eq!(
            reason(&confirmed, &ctx(arrival)).map(|r| r.0),
            Some(EventSeverity::Blocking)
        );
        let old = EventFacts {
            valid_to: None,
            updated_at: now() - Duration::days(31),
            ..closure(&s)
        };
        assert_eq!(reason(&old, &ctx(arrival)), warning(EventReason::Aged));
        let inside = EventContext {
            at_an_end: true,
            ..ctx(arrival)
        };
        assert_eq!(
            reason(&closure(&s), &inside),
            warning(EventReason::AlreadyInside)
        );
    }

    #[test]
    fn an_incident_without_an_end_ages_in_hours() {
        let s = Schedule {
            unplanned: true,
            ..Schedule::default()
        };
        let e = EventFacts {
            valid_to: None,
            updated_at: now() - Duration::hours(13),
            ..closure(&s)
        };
        assert_eq!(
            assess(&e, &dims(), &ctx(now())).map(|f| f.reason),
            Some(EventReason::Aged)
        );
    }

    #[test]
    fn a_night_closure_met_by_day_warns() {
        let night = Schedule::from_label("Uniquement de nuit");
        let e = EventFacts {
            valid_from: now() - Duration::days(1),
            valid_to: Some(now() + Duration::days(5)),
            ..closure(&night)
        };
        // 10:00 UTC is noon in Paris.
        assert_eq!(
            assess(&e, &dims(), &ctx(now())).map(|f| (f.severity, f.reason)),
            Some((EventSeverity::Warning, EventReason::OutsideAssumedHours))
        );
        // 21:00 UTC is 23:00 in Paris.
        assert_eq!(
            assess(&e, &dims(), &ctx(now() + Duration::hours(11))).map(|f| f.severity),
            Some(EventSeverity::Blocking)
        );
    }

    #[test]
    fn a_vehicle_limit_blocks_the_vehicles_it_names() {
        let s = Schedule::default();
        let limit = |limits| EventFacts {
            class: EventClass::VehicleLimit,
            limits,
            ..closure(&s)
        };
        let width = limit(VehicleLimits {
            max_width_m: Some(2.3),
            ..VehicleLimits::default()
        });
        let f = assess(&width, &dims(), &ctx(now())).unwrap();
        assert_eq!(f.severity, EventSeverity::Blocking);
        assert_eq!(f.limit, Some((LimitKind::Width, 2.3)));
        let lorries = limit(VehicleLimits {
            max_weight_t: Some(3.5),
            applies_to: AppliesTo::GoodsVehicles,
            ..VehicleLimits::default()
        });
        let heavy = RoutingDimensions {
            weight_t: 4.5,
            ..dims()
        };
        assert_eq!(
            assess(&lorries, &heavy, &ctx(now())).map(|f| (f.severity, f.reason)),
            Some((EventSeverity::Warning, EventReason::GoodsVehiclesOnly)),
            "a lorry ban does not close the road to a motorhome"
        );
        assert_eq!(assess(&lorries, &dims(), &ctx(now())), None);
        let clearance = limit(VehicleLimits {
            max_height_m: Some(3.5),
            ..VehicleLimits::default()
        });
        assert_eq!(
            assess(&clearance, &dims(), &ctx(now())).map(|f| f.reason),
            Some(EventReason::NearLimit),
            "20 cm under a temporary clearance is told"
        );
    }

    #[test]
    fn lanes_works_and_detours_never_block() {
        let s = Schedule::default();
        for (class, severity) in [
            (EventClass::LaneRestriction, EventSeverity::Warning),
            (EventClass::Works, EventSeverity::Info),
            (EventClass::Detour, EventSeverity::Info),
        ] {
            let e = EventFacts {
                class,
                ..closure(&s)
            };
            assert_eq!(
                assess(&e, &dims(), &ctx(now())).map(|f| f.severity),
                Some(severity),
                "{class}"
            );
        }
    }
}
