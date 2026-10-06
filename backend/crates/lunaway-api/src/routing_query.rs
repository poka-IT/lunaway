//! The resolvers of `Query.route` and `Query.routing`: they check the
//! request, take the client's quota, and hand the work to [`crate::routing`].

use async_graphql::{Context, Result};
use lunaway_db::routing as db;
use lunaway_domain::{
    Position,
    routing::{InvalidVehicle, Trailer, VehicleInput, VehicleProfile, covered_area, is_covered},
};

use crate::{
    client::ClientKey,
    error::{internal, invalid_input, quota_spent, rate_limited_error, unavailable},
    quota::{Action, Subject},
    routing::{
        MAX_ATTEMPTS, NoRoute, Outcome, RouteError, RouteRequest,
        valhalla::{Avoid, EngineError, Stop},
    },
    routing_types::{
        CoveredArea, DISCLAIMER_KEY, RerouteParameters, RouteInput, RouteOptions, RoutePointInput,
        RouteResult, RouteStatus, RouteSummary, RouteWarning, RoutingGraph, RoutingInfo,
        VehicleBounds, VehicleProfileInput, presets,
    },
    schema::{RouteOnce, db as db_share, state},
};

/// Longest trip accepted, straight line from stop to stop, metres: the
/// engine refuses more than its `auto` limit (2 500 km in
/// `infra/routing/valhalla.json`), and such a refusal is the client's
/// request, not the server's failure.
const MAX_TRIP_M: f64 = 2_500_000.0;
/// Waypoints accepted between the origin and the destination.
pub(crate) const MAX_WAYPOINTS: usize = 5;
/// Alternatives accepted besides the best route.
pub(crate) const MAX_ALTERNATIVES: i32 = 2;

fn stop(name: &str, p: RoutePointInput) -> Result<Stop> {
    let at = Position::new(p.lat, p.lon).map_err(|e| invalid_input(format!("{name}: {e}")))?;
    if !is_covered(at) {
        return Err(invalid_input(format!(
            "{name} is outside the area routes are computed in (metropolitan France and Corsica)"
        )));
    }
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

fn vehicle(v: &VehicleProfileInput) -> Result<VehicleProfile> {
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
    })
    .map_err(bad)
}

/// Checks the input and builds the request, before anything is spent.
fn request(input: &RouteInput) -> Result<(RouteRequest, RouteOptions)> {
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
    if trip > MAX_TRIP_M {
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
    let client = Subject::Client(
        ctx.data_opt::<ClientKey>()
            .copied()
            .unwrap_or(ClientKey::Unknown),
    );
    let st = state(ctx);
    st.quotas
        .take(Action::Route, client)
        .map_err(|wait| quota_spent("routes", wait))?;
    // A route the server could not compute does not count against the
    // client: a driver recalculating every 10 s while the engine is busy
    // would otherwise spend the quota on nothing.
    let refund = || st.quotas.give_back(Action::Route, client);
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
    let outcome = match st.routing.route(pool, &graph.id, &request).await {
        Ok(o) => o,
        Err(RouteError::Busy) => {
            refund();
            return Err(rate_limited_error(
                "the routing engine is busy; try again in a moment",
                std::time::Duration::from_secs(2),
            ));
        }
        Err(RouteError::NotSetUp) => {
            refund();
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
            refund();
            log_chain(&e);
            return Err(unavailable("routing"));
        }
        Err(RouteError::Deadline) => {
            refund();
            tracing::warn!("a route ran out of time");
            return Err(unavailable("routing"));
        }
        Err(e @ RouteError::TooLarge) => return Err(invalid_input(e.to_string())),
        Err(e) => {
            refund();
            return Err(internal(&e));
        }
    };
    let reroute = RerouteParameters {
        vehicle: input.vehicle,
        options,
        language: input.language,
        costing_options_json: crate::routing::valhalla::costing_options(
            &request.vehicle.routing(),
            request.avoid,
        )
        .to_string(),
    };
    let base = |status, recalculations: usize| RouteResult {
        status,
        osrm_json: None,
        routes: Vec::new(),
        blockers: Vec::new(),
        recalculations: i32::try_from(recalculations.min(MAX_ATTEMPTS)).unwrap_or(0),
        reroute: reroute.clone(),
        graph: RoutingGraph::from(graph.clone()),
        disclaimer_key: DISCLAIMER_KEY.to_owned(),
    };
    Ok(match outcome {
        Outcome::Found {
            osrm,
            routes,
            recalculations,
        } => RouteResult {
            osrm_json: Some(osrm.to_string()),
            routes: routes.iter().map(RouteSummary::from).collect(),
            ..base(RouteStatus::Ok, recalculations)
        },
        Outcome::NoRoute(NoRoute::Unreachable) => base(RouteStatus::NoRoute, 0),
        Outcome::NoRoute(NoRoute::OffNetwork) => base(RouteStatus::OffNetwork, 0),
        Outcome::NoSafeRoute {
            blockers,
            recalculations,
        } => RouteResult {
            blockers: blockers.iter().map(RouteWarning::from).collect(),
            ..base(RouteStatus::NoSafeRoute, recalculations)
        },
    })
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
    let area = covered_area();
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
            },
            options: None,
            alternatives: 0,
            language: RouteLanguage::Fr,
        }
    }

    fn message(r: Result<(RouteRequest, RouteOptions)>) -> String {
        r.err().map(|e| e.message).unwrap_or_default()
    }

    #[test]
    fn a_request_outside_its_bounds_is_refused_before_anything_is_spent() {
        assert!(request(&input()).is_ok());
        let mut far = input();
        far.destination = RoutePointInput {
            lat: 52.52,
            lon: 13.40,
            heading_deg: None,
        };
        assert!(message(request(&far)).contains("outside the area"));
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
