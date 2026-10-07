//! The resolvers of `Query.route` and `Query.routing`: they check the
//! request, take the client's quota, and hand the work to [`crate::routing`].

use async_graphql::{Context, Result};
use lunaway_db::routing as db;
use lunaway_domain::{
    Position,
    routing::{InvalidVehicle, Trailer, VehicleInput, VehicleProfile, coverage},
};

use crate::{
    client::ClientKey,
    error::{internal, invalid_input, quota_spent, rate_limited_error, unavailable},
    quota::{Action, Subject},
    road_event_types::{RoadEvent, RoadEventSourceStatus},
    routing::{
        MAX_ATTEMPTS, NoRoute, Outcome, RouteError, RouteRequest, Routed, Spent,
        events::Freshness,
        valhalla::{Avoid, EngineError, Stop},
    },
    routing_types::{
        CoveredArea, DISCLAIMER_KEY, NoRouteReason, NoRouteReasonKind, RerouteParameters,
        RouteInput, RouteOptions, RoutePointInput, RouteResult, RouteStatus, RouteSummary,
        RouteWarning, RoutingGraph, RoutingInfo, SpeedLimitSpan, VehicleBounds,
        VehicleProfileInput, presets, road_event_warning,
    },
    schema::{RouteOnce, db as db_share, state},
};

/// The vehicle as its speed ceilings see it: its gross weight and its
/// trailer's.
fn speed_vehicle(v: &VehicleProfile) -> lunaway_domain::speed::Vehicle {
    lunaway_domain::speed::Vehicle {
        weight_t: v.weight_t(),
        trailer_weight_t: v.trailer().map(Trailer::weight_t),
    }
}

/// Longest trip accepted, straight line from stop to stop, metres: Lille
/// to the south of Morocco (Dakhla, 3 415 km) and Andalusia to the North
/// Cape (4 166 km) fit. The engine refuses more than its `auto` limit
/// (`infra/routing/valhalla.json`, at least this, a test reads it), and
/// such a refusal is the client's request, not the server's failure.
/// Measured on 2026-10-07 (`plan/research/40-backend-routage-europe.md`,
/// part 3): the engine takes at most 1.06 s for the ten longest trips on a
/// server faster than the backend (2.3 to 2.85 times, calibrated on shorter
/// trips), and their corridor queries up to 2.7 s on the backend itself;
/// [`crate::routing::valhalla::alternates_for`] keeps the answer's size
/// within bounds.
pub(crate) const MAX_TRIP_M: f64 = 3_000_000.0;
/// Waypoints accepted between the origin and the destination.
pub(crate) const MAX_WAYPOINTS: usize = 5;
/// Alternatives accepted besides the best route.
pub(crate) const MAX_ALTERNATIVES: i32 = 2;
/// How far ahead a trip may be planned: the feeds publish works weeks
/// ahead, but a route is computed on today's graph.
const MAX_DEPART_AHEAD_DAYS: i64 = 14;

fn stop(name: &str, p: RoutePointInput) -> Result<Stop> {
    let at = Position::new(p.lat, p.lon).map_err(|e| invalid_input(format!("{name}: {e}")))?;
    let heading = match p.heading_deg {
        None => None,
        Some(h) if h.is_finite() && (0.0..=360.0).contains(&h) => {
            #[allow(
                clippy::cast_possible_truncation,
                clippy::cast_sign_loss,
                reason = "a course between 0 and 360 degrees"
            )]
            let deg = (h.round() as u16) % 360;
            Some(deg)
        }
        Some(_) => {
            return Err(invalid_input(format!(
                "{name}.headingDeg must be between 0 and 360"
            )));
        }
    };
    Ok(Stop { at, heading })
}

pub(crate) fn vehicle(v: &VehicleProfileInput) -> Result<VehicleProfile> {
    let bad = |e: InvalidVehicle| invalid_input(format!("vehicle: {e}"));
    let trailer = v
        .trailer
        .map(|t| Trailer::new(t.length_m, t.weight_t, t.height_m, t.width_m))
        .transpose()
        .map_err(bad)?;
    VehicleProfile::new(VehicleInput {
        kind: v.kind.into(),
        height_m: v.height_m,
        width_m: v.width_m,
        length_m: v.length_m,
        weight_t: v.weight_t,
        axle_load_t: v.axle_load_t,
        trailer,
        cruise_speed_kph: v.cruise_speed_kph.map(i64::from),
    })
    .map_err(bad)
}

/// Checks the input and builds the request, before anything is spent.
fn request(input: &RouteInput) -> Result<(RouteRequest, RouteOptions)> {
    let now = chrono::Utc::now();
    let depart_at = match input.depart_at {
        None => now,
        Some(t)
            if t < now - chrono::Duration::hours(1)
                || t > now + chrono::Duration::days(MAX_DEPART_AHEAD_DAYS) =>
        {
            return Err(invalid_input(format!(
                "departAt must lie between an hour ago and {MAX_DEPART_AHEAD_DAYS} days ahead"
            )));
        }
        Some(t) => t,
    };
    let waypoints = input.waypoints.as_deref().unwrap_or_default();
    if waypoints.len() > MAX_WAYPOINTS {
        return Err(invalid_input(format!(
            "at most {MAX_WAYPOINTS} waypoints, got {}",
            waypoints.len()
        )));
    }
    if !(0..=MAX_ALTERNATIVES).contains(&input.alternatives) {
        return Err(invalid_input(format!(
            "alternatives must be between 0 and {MAX_ALTERNATIVES}"
        )));
    }
    let mut stops = Vec::with_capacity(waypoints.len() + 2);
    stops.push(stop("origin", input.origin)?);
    for (i, w) in waypoints.iter().enumerate() {
        stops.push(stop(&format!("waypoints[{i}]"), *w)?);
    }
    stops.push(stop("destination", input.destination)?);
    let trip: f64 = stops.windows(2).map(|w| w[0].at.distance_m(w[1].at)).sum();
    if !trip.is_finite() || trip > MAX_TRIP_M {
        return Err(invalid_input(format!(
            "the stops are {:.0} km apart in a straight line, more than the {:.0} km a route may cover",
            trip / 1_000.0,
            MAX_TRIP_M / 1_000.0
        )));
    }
    let options = RouteOptions::from(input.options.unwrap_or_default());
    Ok((
        RouteRequest {
            stops,
            vehicle: vehicle(&input.vehicle)?,
            avoid: Avoid {
                tolls: options.avoid_tolls,
                motorways: options.avoid_motorways,
                ferries: options.avoid_ferries,
                unpaved: options.avoid_unpaved,
            },
            alternatives: u8::try_from(input.alternatives).unwrap_or(0),
            language: input.language.tag(),
            depart_at,
        },
        options,
    ))
}

/// `Query.route`.
pub(crate) async fn route(ctx: &Context<'_>, input: RouteInput) -> Result<RouteResult> {
    if let Some(once) = ctx.data_opt::<RouteOnce>()
        && once.0.swap(true, std::sync::atomic::Ordering::SeqCst)
    {
        return Err(invalid_input("one route per request"));
    }
    let (request, options) = request(&input)?;
    let started = std::time::Instant::now();
    let client = Subject::Client(
        ctx.data_opt::<ClientKey>()
            .copied()
            .unwrap_or(ClientKey::Unknown),
    );
    let st = state(ctx);
    // A stop where the graph has no road: the engine is not asked, and the
    // quota not taken.
    let outside: Vec<usize> = request
        .stops
        .iter()
        .enumerate()
        .filter(|(_, s)| !coverage::covers(s.at))
        .map(|(i, _)| i)
        .collect();
    let charged = outside.is_empty();
    if charged {
        st.quotas
            .take(Action::Route, client)
            .map_err(|wait| quota_spent("routes", wait))?;
    }
    // A route the server could not compute does not count against the
    // client: a driver recalculating every 10 s while the engine is busy
    // would otherwise spend the quota on nothing.
    let refund = || {
        if charged {
            st.quotas.give_back(Action::Route, client);
        }
    };
    let (pool, _permit) = db_share(ctx).await?;
    let graph = match db::active_graph(pool).await {
        Ok(Some(g)) => g,
        Ok(None) => {
            refund();
            return Err(unavailable("routing"));
        }
        Err(e) => {
            refund();
            return Err(internal(&e));
        }
    };
    // The freshness of each feed of road events: a closure whose feed is
    // stale warns instead of blocking.
    let sources = match lunaway_db::road_events::sources(pool).await {
        Ok(s) => s,
        Err(e) => {
            refund();
            return Err(internal(&e));
        }
    };
    let now = chrono::Utc::now();
    let fresh = Freshness::of(&sources, now);
    // Only when asked: each route costs the engine a trace or more.
    let limits = ctx
        .look_ahead()
        .field("routes")
        .field("speedLimits")
        .exists()
        .then(|| speed_vehicle(&request.vehicle));
    let routed = if charged {
        st.routing
            .route(pool, &graph.id, &request, &fresh, limits)
            .await
    } else {
        Routed {
            result: Ok(Outcome::NoRoute(NoRoute::OutsideCoverage(outside))),
            engine_answered: false,
            spent: Spent::default(),
        }
    };
    // Once the engine has answered, the work was done: a failure after it
    // (a recalculation out of time, the engine gone silent) is not given
    // back, or a trip made slow on purpose would cost its client nothing.
    let refund_unworked = || {
        if !routed.engine_answered {
            refund();
        }
    };
    let spent = routed.spent;
    let outcome = match routed.result {
        Ok(o) => o,
        Err(RouteError::Busy) => {
            refund_unworked();
            return Err(rate_limited_error(
                "the routing engine is busy; try again in a moment",
                std::time::Duration::from_secs(2),
            ));
        }
        Err(RouteError::NotSetUp) => {
            refund_unworked();
            return Err(unavailable("routing"));
        }
        // The engine refused the request itself (a limit of its own): the
        // client's request, kept in the quota.
        Err(RouteError::Engine(EngineError::Refused { status, code }))
            if (400..500).contains(&status) =>
        {
            tracing::warn!(status, %code, "the routing engine refused a request");
            return Err(invalid_input(
                "the routing engine cannot compute this route",
            ));
        }
        Err(RouteError::Engine(e)) => {
            refund_unworked();
            log_chain(&e);
            return Err(unavailable("routing"));
        }
        Err(RouteError::Deadline) => {
            refund_unworked();
            // The phase the deadline cut is not counted: its time is the
            // route's deadline less the sum of these.
            tracing::warn!(
                queue_ms = spent.queue.as_millis(),
                engine_ms = spent.engine.as_millis(),
                engine_calls = spent.engine_calls,
                corridor_ms = spent.corridor.as_millis(),
                check_ms = spent.check.as_millis(),
                "a route ran out of time"
            );
            return Err(unavailable("routing"));
        }
        Err(e @ RouteError::TooLarge) => return Err(invalid_input(e.to_string())),
        Err(e) => {
            refund_unworked();
            return Err(internal(&e));
        }
    };
    let dims = request.vehicle.routing();
    let reroute = RerouteParameters {
        vehicle: input.vehicle,
        options,
        language: input.language,
        top_speed_kph: dims.top_speed_kph.and_then(|s| i32::try_from(s).ok()),
        costing_options_json: crate::routing::valhalla::costing_options(&dims, request.avoid)
            .to_string(),
    };
    let road_event_sources: Vec<RoadEventSourceStatus> = sources
        .iter()
        .map(|s| RoadEventSourceStatus::of(s, now))
        .collect();
    let last_stop = request.stops.len().saturating_sub(1);
    let mut osrm_bytes = 0;
    let base = |status, recalculations: usize| RouteResult {
        status,
        no_route_reasons: Vec::new(),
        osrm_json: None,
        routes: Vec::new(),
        blockers: Vec::new(),
        road_event_blockers: Vec::new(),
        avoided_road_events: Vec::new(),
        road_event_sources: road_event_sources.clone(),
        recalculations: i32::try_from(recalculations.min(MAX_ATTEMPTS)).unwrap_or(0),
        reroute: reroute.clone(),
        graph: RoutingGraph::from(graph.clone()),
        disclaimer_key: DISCLAIMER_KEY.to_owned(),
    };
    let result = match outcome {
        Outcome::Found {
            osrm,
            routes,
            recalculations,
            avoided,
            limits,
        } => RouteResult {
            routes: routes
                .iter()
                .map(|r| RouteSummary {
                    speed_limits: limits
                        .get(r.index)
                        .cloned()
                        .flatten()
                        .map(|spans| spans.iter().map(SpeedLimitSpan::from).collect()),
                    ..RouteSummary::of(r, &fresh, now)
                })
                .collect(),
            osrm_json: Some({
                let text = osrm.to_string();
                osrm_bytes = text.len();
                text
            }),
            avoided_road_events: avoided.iter().map(|e| RoadEvent::of(e, now)).collect(),
            ..base(RouteStatus::Ok, recalculations)
        },
        Outcome::NoRoute(NoRoute::Unreachable(reasons)) => RouteResult {
            no_route_reasons: reasons
                .iter()
                .map(|r| NoRouteReason::of(r, last_stop))
                .collect(),
            ..base(RouteStatus::NoRoute, 0)
        },
        Outcome::NoRoute(NoRoute::OffNetwork(stops)) => RouteResult {
            no_route_reasons: NoRouteReason::at_stops(
                NoRouteReasonKind::NoRoadNearby,
                &stops,
                last_stop,
            ),
            ..base(RouteStatus::OffNetwork, 0)
        },
        Outcome::NoRoute(NoRoute::OutsideCoverage(stops)) => RouteResult {
            no_route_reasons: NoRouteReason::at_stops(
                NoRouteReasonKind::OutsideCoverage,
                &stops,
                last_stop,
            ),
            ..base(RouteStatus::NoRoute, 0)
        },
        Outcome::NoSafeRoute {
            blockers,
            event_blockers,
            recalculations,
        } => RouteResult {
            blockers: blockers.iter().map(RouteWarning::from).collect(),
            road_event_blockers: event_blockers
                .iter()
                .map(|h| road_event_warning(h, &fresh, now))
                .collect(),
            ..base(RouteStatus::NoSafeRoute, recalculations)
        },
    };
    tracing::info!(
        status = ?result.status,
        total_ms = started.elapsed().as_millis(),
        queue_ms = spent.queue.as_millis(),
        engine_ms = spent.engine.as_millis(),
        engine_calls = spent.engine_calls,
        corridor_ms = spent.corridor.as_millis(),
        check_ms = spent.check.as_millis(),
        limits_ms = spent.limits.as_millis(),
        routes = result.routes.len(),
        osrm_bytes,
        "route computed"
    );
    Ok(result)
}

/// Logs an engine failure with its causes (a timeout, a refused
/// connection), never a position.
fn log_chain(error: &(dyn std::error::Error + 'static)) {
    let mut chain = Vec::new();
    let mut cause: Option<&(dyn std::error::Error + 'static)> = Some(error);
    while let Some(c) = cause {
        chain.push(c.to_string());
        cause = c.source();
    }
    tracing::error!(error = %chain.join(": "), "routing engine failure");
}

/// `Query.routing`.
pub(crate) async fn routing_info(ctx: &Context<'_>) -> Result<RoutingInfo> {
    let (pool, _permit) = db_share(ctx).await?;
    let graph = db::active_graph(pool).await.map_err(|e| internal(&e))?;
    let available = graph.is_some() && state(ctx).routing.alive_cached().await;
    let area = coverage::bounding_box();
    let (vehicle_presets, trailer_presets) = presets();
    Ok(RoutingInfo {
        available,
        graph: graph.map(RoutingGraph::from),
        disclaimer_key: DISCLAIMER_KEY.to_owned(),
        covered_area: CoveredArea {
            south: area.south(),
            west: area.west(),
            north: area.north(),
            east: area.east(),
        },
        covered_countries: coverage::countries()
            .into_iter()
            .map(str::to_owned)
            .collect(),
        road_event_report_countries: lunaway_domain::road_events::community::report_countries()
            .into_iter()
            .map(str::to_owned)
            .collect(),
        max_trip_km: MAX_TRIP_M / 1_000.0,
        max_waypoints: i32::try_from(MAX_WAYPOINTS).unwrap_or(0),
        max_alternatives: MAX_ALTERNATIVES,
        vehicle_bounds: VehicleBounds::current(),
        vehicle_presets,
        trailer_presets,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::routing_types::{GqlVehicleType, RouteLanguage, TrailerInput};

    fn input() -> RouteInput {
        RouteInput {
            origin: RoutePointInput {
                lat: 45.84719,
                lon: 1.28476,
                heading_deg: None,
            },
            destination: RoutePointInput {
                lat: 45.8451,
                lon: 1.28637,
                heading_deg: None,
            },
            waypoints: None,
            vehicle: VehicleProfileInput {
                kind: GqlVehicleType::Overcab,
                height_m: 3.3,
                width_m: 2.3,
                length_m: 7.4,
                weight_t: 3.5,
                axle_load_t: None,
                trailer: None,
                cruise_speed_kph: None,
            },
            options: None,
            alternatives: 0,
            language: RouteLanguage::Fr,
            depart_at: None,
        }
    }

    #[test]
    fn the_engine_accepts_every_trip_the_api_does() {
        // The configuration the backend serves the engine with.
        let config: serde_json::Value =
            serde_json::from_str(include_str!("../../../../infra/routing/valhalla.json")).unwrap();
        let engine = config["service_limits"]["auto"]["max_distance"]
            .as_f64()
            .unwrap();
        assert!(
            MAX_TRIP_M <= engine,
            "a trip the API accepts and the engine refuses fails as INVALID_INPUT"
        );
    }

    fn message(r: Result<(RouteRequest, RouteOptions)>) -> String {
        r.err().map(|e| e.message).unwrap_or_default()
    }

    #[test]
    fn a_request_outside_its_bounds_is_refused_before_anything_is_spent() {
        assert!(request(&input()).is_ok());
        let mut berlin = input();
        berlin.destination = RoutePointInput {
            lat: 52.52,
            lon: 13.40,
            heading_deg: None,
        };
        assert!(
            request(&berlin).is_ok(),
            "Berlin is 1 000 km away, in the graph"
        );
        let mut far = input();
        far.origin = RoutePointInput {
            lat: 27.75,
            lon: -18.0,
            heading_deg: None,
        };
        far.destination = RoutePointInput {
            lat: 70.98,
            lon: 25.97,
            heading_deg: None,
        };
        assert!(
            message(request(&far)).contains("more than the 3000 km"),
            "El Hierro to the North Cape: {}",
            message(request(&far))
        );
        let mut many = input();
        many.waypoints = Some(vec![input().origin; 6]);
        assert!(message(request(&many)).contains("at most 5 waypoints"));
        let mut alts = input();
        alts.alternatives = 3;
        assert!(message(request(&alts)).contains("alternatives"));
        let mut cm = input();
        cm.vehicle.height_m = 330.0;
        assert!(message(request(&cm)).contains("heightM"));
        let mut heading = input();
        heading.origin.heading_deg = Some(400.0);
        assert!(message(request(&heading)).contains("headingDeg"));
        let mut later = input();
        later.depart_at = Some(chrono::Utc::now() + chrono::Duration::days(30));
        assert!(message(request(&later)).contains("departAt"));
        let mut trailer = input();
        trailer.vehicle.trailer = Some(TrailerInput {
            length_m: 4.78,
            weight_t: 1.5,
            height_m: None,
            width_m: None,
        });
        let (r, _) = request(&trailer).unwrap();
        assert_eq!(r.vehicle.routing().trailer_weight_t, Some(1.5));
    }
}
