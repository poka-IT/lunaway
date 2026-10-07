//! The resolvers of `Query.fuelNearby` and `Query.fuelAlongRoute`: they
//! check the arguments, read the stations (`lunaway_db::fuel`), and, along
//! a route, have the routing engine measure the detours of the best
//! candidates ([`lunaway_domain::fuel`]).

use std::{ops::RangeInclusive, sync::Arc, time::Duration};

use async_graphql::{Context, Result};
use chrono::{DateTime, Utc};
use lunaway_db::fuel::{self as db, FuelStationRow, StationPoint};
use lunaway_domain::{
    BBox, Position, TrimmedLine,
    fuel::{
        Corridor, Detour, Located, MAX_LINE_SPAN_DEG, MAX_PRICE_AGE_DAYS, Refuel, line_span_deg,
        runs,
    },
    poi::{FuelKind, open_state},
    routing::polyline,
    trim_ends,
};
use serde_json::{Value, json};

use crate::{
    client::ClientKey,
    error::{internal, invalid_input, quota_spent},
    fuel_types::{FuelAlongRoute, FuelAlongRouteInput, FuelDetour, FuelStationAddress, FuelStop},
    poi_types::{FuelShortage, GqlFuelKind},
    quota::{Action, Subject},
    routing::{
        RouteError,
        valhalla::{Avoid, EngineError, MatrixPoint, costing_options},
    },
    schema::{DB_FIELD_COST, ROUTE_FIELD_COST, RouteOnce, db, state},
    types::LatLonInput,
};

/// Farthest `fuelNearby` looks, kilometres.
pub(crate) const MAX_NEARBY_RADIUS_KM: f64 = 50.0;
/// Most stations `fuelNearby` returns.
pub(crate) const MAX_NEARBY_LIMIT: i32 = 50;
/// Most stations `fuelAlongRoute` returns.
pub(crate) const MAX_ALONG_LIMIT: i32 = 20;
/// Longest polyline accepted, characters: what fits in the 64 KiB body
/// with the rest of the request.
const MAX_POLYLINE_CHARS: usize = 48_000;
/// Most points accepted as a list.
const MAX_INPUT_POINTS: usize = 1_000;
/// Most points a polyline may decode to: 48 000 characters of six-decimal
/// deltas hold fewer.
const MAX_LINE_POINTS: usize = 20_000;
/// Longest route, kilometres: the engine's own limit for a route.
const MAX_ROUTE_KM: f64 = 2_500.0;
/// How much of each end of the line the search drops, metres: the start
/// is the device's position when a preview searches from it.
pub(crate) const END_CUT_M: f64 = 2_000.0;
/// Detours accepted, kilometres.
const DETOUR_KM: RangeInclusive<f64> = 0.5..=30.0;
/// Consumptions accepted, litres per 100 km.
const CONSUMPTION: RangeInclusive<f64> = 2.0..=50.0;
/// Fills accepted, litres.
const FILL: RangeInclusive<f64> = 5.0..=300.0;
/// Detours the engine measures at most for one search: twice the stations
/// asked, within this.
const MAX_MEASURED: usize = 20;
/// Longest run of stations one matrix call measures, metres along the
/// route: the engine computes every pair of a matrix and reads none but a
/// few short legs, so a call stays local. With the anchors (3 km each side)
/// and the band (15 km each side at most), its points lie less than 60 km
/// apart.
const MAX_RUN_M: f64 = 20_000.0;
/// How far the engine may look for a road around a station, metres: a
/// station sits beside its road, sometimes behind a car park.
const STATION_CUTOFF_M: u32 = 2_000;
/// How far around a point of the route: it lies on a road.
const ANCHOR_CUTOFF_M: u32 = 500;
/// Longest the engine's measurements of one search may take together:
/// under the API's request timeout (20 s by default), and what is not
/// measured by then is estimated.
const ENGINE_DEADLINE: Duration = Duration::from_secs(8);

/// The cost of `fuelNearby`: its stations, plus [`DB_FIELD_COST`].
pub(crate) fn nearby_cost(limit: i32, child: usize) -> usize {
    usize::try_from(limit.clamp(1, MAX_NEARBY_LIMIT))
        .unwrap_or(1)
        .saturating_mul(child)
        .saturating_add(DB_FIELD_COST)
}

/// The cost of `fuelAlongRoute`: its stations, plus a route's share
/// ([`ROUTE_FIELD_COST`]): it waits on the routing engine.
pub(crate) fn along_cost(limit: i32, child: usize) -> usize {
    usize::try_from(limit.clamp(1, MAX_ALONG_LIMIT))
        .unwrap_or(1)
        .saturating_mul(child)
        .saturating_add(ROUTE_FIELD_COST)
}

/// The oldest price offered at `now`.
fn fresh_since(now: DateTime<Utc>) -> DateTime<Utc> {
    now - chrono::Duration::days(MAX_PRICE_AGE_DAYS)
}

/// A station of `row` for `fuel`, at `distance_m`; none when it has no
/// price of the fuel.
fn stop_of(
    row: FuelStationRow,
    fuel: FuelKind,
    now: DateTime<Utc>,
    distance_m: f64,
    along: Option<(f64, Detour, Refuel)>,
) -> Option<FuelStop> {
    let price = row.station.price_of(fuel)?.clone();
    let (along_km, detour, effective_price_eur) = match along {
        None => (None, None, price.price_eur),
        Some((along_m, detour, refuel)) => {
            let e = refuel.effective(price.price_eur, detour.km);
            (
                Some(along_m / 1_000.0),
                Some(FuelDetour {
                    km: detour.km,
                    minutes: detour.minutes,
                    measured: detour.measured,
                    litres: e.detour_litres,
                    cost_eur: e.detour_cost_eur,
                }),
                e.price_eur,
            )
        }
    };
    let open = match &row.poi {
        Some(p) => open_state(
            p.always_open,
            p.opening_intervals.as_deref(),
            p.opening_intervals_until,
            now,
        ),
        None => open_state(false, None, None, now),
    };
    let shortage = row.station.shortage_of(fuel).map(|s| FuelShortage {
        fuel: s.fuel.into(),
        kind: s.kind.into(),
        since: s.since,
    });
    Some(FuelStop {
        station_id: row.station_ref.clone(),
        poi_id: row.poi.as_ref().map(|p| p.id),
        name_source_id: row.poi.as_ref().map(|p| p.source_id.clone()),
        name: row.poi.as_ref().and_then(|p| p.name.clone()),
        brand: row.poi.as_ref().and_then(|p| p.brand.clone()),
        lat: row.position.lat(),
        lon: row.position.lon(),
        address: row.station.address.as_ref().map(|a| FuelStationAddress {
            street: a.street.clone(),
            postcode: a.postcode.clone(),
            city: a.city.clone(),
        }),
        fuel: fuel.into(),
        price_eur: price.price_eur,
        price_updated_at: price.updated_at,
        shortage,
        open_now: open.into(),
        self_service_24h: row.station.automate_24_24,
        highway: row.station.highway,
        distance_m,
        along_km,
        detour,
        effective_price_eur,
        fetched_at: row.fetched_at,
        source_id: lunaway_domain::SourceId::FUEL_PRICES.as_str().to_owned(),
        station_ref: row.station_ref,
        kind: fuel,
    })
}

/// `Query.fuelNearby`.
pub(crate) async fn nearby(
    ctx: &Context<'_>,
    at: LatLonInput,
    fuel: GqlFuelKind,
    radius_km: f64,
    limit: i32,
) -> Result<Vec<FuelStop>> {
    // Kept on the grid only, before anything reads it; the error names no
    // coordinate.
    let at = Position::new(at.lat, at.lon)
        .map_err(|_| invalid_input("at: not a valid position"))?
        .coarsened();
    if !(radius_km.is_finite() && radius_km > 0.0 && radius_km <= MAX_NEARBY_RADIUS_KM) {
        return Err(invalid_input(format!(
            "radiusKm must be above 0 and at most {MAX_NEARBY_RADIUS_KM}"
        )));
    }
    if !(1..=MAX_NEARBY_LIMIT).contains(&limit) {
        return Err(invalid_input(format!(
            "limit must be between 1 and {MAX_NEARBY_LIMIT}"
        )));
    }
    let fuel: FuelKind = fuel.into();
    let now = Utc::now();
    let (pool, _permit) = db(ctx).await?;
    let rows = db::near(
        pool,
        fuel,
        at,
        radius_km * 1_000.0,
        fresh_since(now),
        i64::from(limit),
    )
    .await
    .map_err(|e| internal(&e))?;
    Ok(rows
        .into_iter()
        .filter_map(|r| {
            let d = r.distance_m.unwrap_or_default();
            stop_of(r, fuel, now, d, None)
        })
        .collect())
}

/// The search's settings, checked before anything is spent: every scalar,
/// and the size of the line as sent.
struct Search {
    fuel: FuelKind,
    max_detour_km: f64,
    refuel: Refuel,
    limit: usize,
    costing: Value,
}

fn search(input: &FuelAlongRouteInput) -> Result<Search> {
    if !DETOUR_KM.contains(&input.max_detour_km) {
        return Err(invalid_input(format!(
            "maxDetourKm must be between {} and {}",
            DETOUR_KM.start(),
            DETOUR_KM.end()
        )));
    }
    if !CONSUMPTION.contains(&input.litres_per_100km) {
        return Err(invalid_input(format!(
            "litresPer100Km must be between {} and {}",
            CONSUMPTION.start(),
            CONSUMPTION.end()
        )));
    }
    if !FILL.contains(&input.fill_litres) {
        return Err(invalid_input(format!(
            "fillLitres must be between {} and {}",
            FILL.start(),
            FILL.end()
        )));
    }
    if !(1..=MAX_ALONG_LIMIT).contains(&input.limit) {
        return Err(invalid_input(format!(
            "limit must be between 1 and {MAX_ALONG_LIMIT}"
        )));
    }
    match (&input.polyline, &input.points) {
        (Some(p), None) if p.len() > MAX_POLYLINE_CHARS => {
            return Err(invalid_input(format!(
                "polyline holds {} characters, more than the {MAX_POLYLINE_CHARS} allowed: \
                 simplify the line",
                p.len()
            )));
        }
        (None, Some(list)) if list.len() > MAX_INPUT_POINTS => {
            return Err(invalid_input(format!(
                "at most {MAX_INPUT_POINTS} points, got {}",
                list.len()
            )));
        }
        (Some(_), None) | (None, Some(_)) => {}
        _ => return Err(invalid_input("give either polyline or points")),
    }
    let costing = match &input.vehicle {
        Some(v) => costing_options(
            &crate::routing_query::vehicle(v)?.routing(),
            Avoid::default(),
        ),
        None => json!({ "auto": {} }),
    };
    Ok(Search {
        fuel: input.fuel.into(),
        max_detour_km: input.max_detour_km,
        refuel: Refuel {
            consumption_l_per_100km: input.litres_per_100km,
            fill_litres: input.fill_litres,
        },
        limit: usize::try_from(input.limit).unwrap_or(1),
        costing,
    })
}

/// The route's line from the input, checked: its points, the degrees it
/// covers (what the corridor's grid costs) and its length. Linear in the
/// points, which the size checks of [`search`] bound.
fn line_of(input: &FuelAlongRouteInput) -> Result<Vec<Position>> {
    let points = match (&input.polyline, &input.points) {
        (Some(p), _) => polyline::decode(p).map_err(|e| invalid_input(format!("polyline: {e}")))?,
        (None, Some(list)) => list
            .iter()
            .enumerate()
            .map(|(i, p)| {
                Position::new(p.lat, p.lon).map_err(|e| invalid_input(format!("points[{i}]: {e}")))
            })
            .collect::<Result<_>>()?,
        (None, None) => return Err(invalid_input("give either polyline or points")),
    };
    if points.len() < 2 || points.len() > MAX_LINE_POINTS {
        return Err(invalid_input(format!(
            "the route must hold 2 to {MAX_LINE_POINTS} points, got {}",
            points.len()
        )));
    }
    let span = line_span_deg(&points);
    if span > MAX_LINE_SPAN_DEG {
        return Err(invalid_input(format!(
            "the line covers {span:.0} degrees, more than the {MAX_LINE_SPAN_DEG:.0} a route covers"
        )));
    }
    let km: f64 = points
        .windows(2)
        .map(|w| w[0].distance_m(w[1]))
        .sum::<f64>()
        / 1_000.0;
    if km > MAX_ROUTE_KM {
        return Err(invalid_input(format!(
            "the route is {km:.0} km long, more than the {MAX_ROUTE_KM:.0} km allowed"
        )));
    }
    Ok(points)
}

/// The box around the corridor, for the database's index.
fn corridor_box(corridor: &Corridor) -> Result<BBox> {
    let points = corridor.points();
    let fold = |f: fn(Position) -> f64| {
        points
            .iter()
            .copied()
            .map(f)
            .fold((f64::INFINITY, f64::NEG_INFINITY), |(lo, hi), v| {
                (lo.min(v), hi.max(v))
            })
    };
    let (south, north) = fold(Position::lat);
    let (west, east) = fold(Position::lon);
    let margin_lat = corridor.half_width_m() / 111_195.0;
    let widest = south.abs().max(north.abs()) + margin_lat;
    let margin_lon = margin_lat / widest.min(85.0).to_radians().cos();
    BBox::new(
        (south - margin_lat).max(-90.0),
        (west - margin_lon).max(-180.0),
        (north + margin_lat).min(90.0),
        (east + margin_lon).min(180.0),
    )
    .map_err(|e| internal(&e))
}

/// A candidate of the corridor.
struct Candidate {
    point: StationPoint,
    located: Located,
    detour: Detour,
}

#[allow(
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    reason = "a heading between 0 and 360 degrees"
)]
fn heading(deg: f64) -> u16 {
    (deg.rem_euclid(360.0).round() as u16) % 360
}

/// Measures the detours of `shortlist`, sorted by distance along the route,
/// with the engine, a run of nearby stations per call. An engine that
/// refuses, is busy or is not set up is not asked again for this search,
/// and what it did not measure keeps its estimate.
async fn measure(ctx: &Context<'_>, corridor: &Corridor, s: &Search, shortlist: &mut [Candidate]) {
    let routing = &state(ctx).routing;
    let deadline = tokio::time::Instant::now() + ENGINE_DEADLINE;
    let alongs: Vec<f64> = shortlist.iter().map(|c| c.located.along_m).collect();
    for run in runs(&alongs, MAX_RUN_M) {
        let stations = &mut shortlist[run];
        let k = stations.len();
        let anchors: Vec<_> = stations
            .iter()
            .map(|c| corridor.anchors(c.located.along_m))
            .collect();
        let anchor = |a: &lunaway_domain::fuel::Anchor| MatrixPoint {
            at: a.at,
            heading: Some(heading(a.heading_deg)),
            search_cutoff_m: ANCHOR_CUTOFF_M,
        };
        let station = |c: &Candidate| MatrixPoint {
            at: c.point.position,
            heading: None,
            search_cutoff_m: STATION_CUTOFF_M,
        };
        // Sources: the anchors before, then the stations. Targets: the
        // stations, then the anchors after. Row i reads before->station
        // and before->after, row k+i station->after.
        let sources: Vec<MatrixPoint> = anchors
            .iter()
            .map(|(before, _)| anchor(before))
            .chain(stations.iter().map(station))
            .collect();
        let targets: Vec<MatrixPoint> = stations
            .iter()
            .map(station)
            .chain(anchors.iter().map(|(_, after)| anchor(after)))
            .collect();
        let cells =
            match tokio::time::timeout_at(deadline, routing.matrix(&sources, &targets, &s.costing))
                .await
            {
                Ok(Ok(cells)) => cells,
                Ok(Err(RouteError::NotSetUp)) => break,
                // A station far from any road makes the engine refuse its
                // whole run (Valhalla's 170 and 171): the other runs are
                // still worth measuring.
                Ok(Err(RouteError::Engine(EngineError::Refused { status: 400, code })))
                    if code.starts_with("170:") || code.starts_with("171:") =>
                {
                    tracing::warn!(%code, "a run of fuel detours estimated");
                    continue;
                }
                Ok(Err(error)) => {
                    warn_chain(&error);
                    break;
                }
                Err(_) => {
                    tracing::warn!("fuel detours ran out of time; the rest are estimated");
                    break;
                }
            };
        for (i, c) in stations.iter_mut().enumerate() {
            let get =
                |r: usize, t: usize| cells.get(r).and_then(|row| row.get(t)).copied().flatten();
            c.detour = match (get(i, i), get(k + i, k + i), get(i, k + i)) {
                (Some(to), Some(from), Some(direct)) => Detour::measured(to, from, direct),
                // No way to the station from the route: it is not one to
                // send a driver to.
                _ => Detour {
                    km: f64::INFINITY,
                    minutes: f64::INFINITY,
                    measured: true,
                },
            };
        }
    }
}

/// Logs why the engine did not measure, with its causes, at warning level:
/// the search answers anyway, with estimates. Never a position.
fn warn_chain(error: &(dyn std::error::Error + 'static)) {
    let mut chain = Vec::new();
    let mut cause: Option<&(dyn std::error::Error + 'static)> = Some(error);
    while let Some(c) = cause {
        chain.push(c.to_string());
        cause = c.source();
    }
    tracing::warn!(error = %chain.join(": "), "fuel detours estimated");
}

/// The candidates among `stations`, located in `corridor` on a blocking
/// thread: thousands of stations to place take milliseconds.
async fn place(corridor: Arc<Corridor>, stations: Vec<StationPoint>) -> Result<Vec<Candidate>> {
    tokio::task::spawn_blocking(move || {
        stations
            .into_iter()
            .filter_map(|point| {
                let located = corridor.locate(point.position)?;
                Some(Candidate {
                    detour: Detour::estimated(located.offset_m),
                    point,
                    located,
                })
            })
            .collect()
    })
    .await
    .map_err(|e| internal(&e))
}

/// `Query.fuelAlongRoute`.
pub(crate) async fn along_route(
    ctx: &Context<'_>,
    input: FuelAlongRouteInput,
) -> Result<FuelAlongRoute> {
    // One engine search per request, whether a route or this.
    if let Some(once) = ctx.data_opt::<RouteOnce>()
        && once.0.swap(true, std::sync::atomic::Ordering::SeqCst)
    {
        return Err(invalid_input(
            "one route or fuel search along a route per request",
        ));
    }
    let s = search(&input)?;
    let client = Subject::Client(
        ctx.data_opt::<ClientKey>()
            .copied()
            .unwrap_or(ClientKey::Unknown),
    );
    // Taken before the line is read: whatever it costs, the client pays.
    state(ctx)
        .quotas
        .take(Action::FuelRoute, client)
        .map_err(|wait| quota_spent("fuel searches along a route", wait))?;
    let points = line_of(&input)?;
    // The line's ends are where the device is and where it goes: they are
    // cut before anything reads the line, and the search runs on the rest.
    let Some(trimmed) = trim_ends(&points, END_CUT_M) else {
        let route_m: f64 = points.windows(2).map(|w| w[0].distance_m(w[1])).sum();
        return Ok(FuelAlongRoute {
            stations: Vec::new(),
            route_km: route_m / 1_000.0,
            candidates: 0,
            detours_measured: false,
        });
    };
    drop(points);
    let TrimmedLine {
        points,
        head_m,
        total_m,
    } = trimmed;
    let half_width_m = s.max_detour_km * 1_000.0 / 2.0;
    let corridor = Arc::new(
        tokio::task::spawn_blocking(move || Corridor::new(points, half_width_m))
            .await
            .map_err(|e| internal(&e))?
            .ok_or_else(|| {
                invalid_input("the line folds over itself too often to search along it")
            })?,
    );
    let now = Utc::now();
    let area = corridor_box(&corridor)?;
    let (pool, _permit) = db(ctx).await?;
    let points = db::in_box(pool, s.fuel, area, fresh_since(now))
        .await
        .map_err(|e| internal(&e))?;
    let mut candidates = place(Arc::clone(&corridor), points).await?;
    let found = candidates.len();
    // Stations out of the fuel last, and those whose estimate already
    // exceeds the detour accepted after the others: measured, a road may
    // be shorter than the estimate, estimated, they are dropped.
    let rank = |c: &Candidate| {
        (
            c.point.in_shortage,
            c.detour.km > s.max_detour_km,
            s.refuel.effective(c.point.price_eur, c.detour.km).price_eur,
        )
    };
    let by_rank = |a: &Candidate, b: &Candidate| {
        rank(a)
            .partial_cmp(&rank(b))
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(a.located.along_m.total_cmp(&b.located.along_m))
    };
    candidates.sort_by(by_rank);
    candidates.truncate(MAX_MEASURED.min(2 * s.limit));
    candidates.sort_by(|a, b| a.located.along_m.total_cmp(&b.located.along_m));
    measure(ctx, &corridor, &s, &mut candidates).await;
    candidates.retain(|c| c.detour.km <= s.max_detour_km);
    candidates.sort_by(by_rank);
    candidates.truncate(s.limit);
    let refs: Vec<String> = candidates
        .iter()
        .map(|c| c.point.station_ref.clone())
        .collect();
    let mut rows: std::collections::HashMap<String, FuelStationRow> = db::by_refs(pool, &refs)
        .await
        .map_err(|e| internal(&e))?
        .into_iter()
        .map(|r| (r.station_ref.clone(), r))
        .collect();
    let detours_measured = !candidates.is_empty() && candidates.iter().all(|c| c.detour.measured);
    let stations = candidates
        .into_iter()
        .filter_map(|c| {
            let row = rows.remove(&c.point.station_ref)?;
            stop_of(
                row,
                s.fuel,
                now,
                c.located.offset_m,
                Some((head_m + c.located.along_m, c.detour, s.refuel)),
            )
        })
        .collect();
    Ok(FuelAlongRoute {
        stations,
        route_km: total_m / 1_000.0,
        candidates: i32::try_from(found).unwrap_or(i32::MAX),
        detours_measured,
    })
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        reason = "a test states its preconditions with unwrap"
    )]
    use super::*;

    fn input() -> FuelAlongRouteInput {
        FuelAlongRouteInput {
            polyline: Some(polyline::encode(&[
                Position::new(45.0, 1.0).unwrap(),
                Position::new(45.1, 1.0).unwrap(),
            ])),
            points: None,
            fuel: GqlFuelKind::Diesel,
            max_detour_km: 5.0,
            litres_per_100km: 12.0,
            fill_litres: 60.0,
            limit: 10,
            vehicle: None,
        }
    }

    fn message<T>(r: Result<T>) -> String {
        r.err().map(|e| e.message).unwrap_or_default()
    }

    #[test]
    fn a_search_outside_its_bounds_is_refused_before_anything_is_spent() {
        assert!(search(&input()).is_ok());
        let mut far = input();
        far.max_detour_km = 31.0;
        assert!(message(search(&far)).contains("maxDetourKm"));
        let mut thirsty = input();
        thirsty.litres_per_100km = 80.0;
        assert!(message(search(&thirsty)).contains("litresPer100Km"));
        let mut many = input();
        many.limit = 21;
        assert!(message(search(&many)).contains("limit"));
        let mut both = input();
        both.points = Some(vec![
            LatLonInput {
                lat: 45.0,
                lon: 1.0
            };
            2
        ]);
        assert!(message(search(&both)).contains("either"));
        let mut long = input();
        long.polyline = Some("_".repeat(MAX_POLYLINE_CHARS + 1));
        assert!(message(search(&long)).contains("simplify"));
    }

    #[test]
    fn a_line_is_read_and_measured_before_its_corridor_is_built() {
        assert!(line_of(&input()).is_ok());
        let mut broken = input();
        broken.polyline = Some("~".to_owned());
        assert!(message(line_of(&broken)).contains("polyline"));
        let mut across = input();
        across.polyline = Some(polyline::encode(&[
            Position::new(36.0, -9.0).unwrap(),
            Position::new(60.0, 25.0).unwrap(),
        ]));
        assert!(message(line_of(&across)).contains("km long"));
        // Back and forth across the antimeridian: 2.2 km a segment, but
        // 360 degrees of grid each.
        let mut zigzag = input();
        zigzag.polyline = None;
        zigzag.points = Some(
            (0..1_000)
                .map(|i| LatLonInput {
                    lat: 0.0,
                    lon: if i % 2 == 0 { -179.99 } else { 179.99 },
                })
                .collect(),
        );
        assert!(search(&zigzag).is_ok(), "its size passes");
        assert!(message(line_of(&zigzag)).contains("degrees"));
    }

    #[test]
    fn the_box_holds_the_band_on_every_side() {
        let corridor = Corridor::new(line_of(&input()).unwrap(), 2_500.0).unwrap();
        let b = corridor_box(&corridor).unwrap();
        assert!(b.south() < 45.0 - 2_400.0 / 111_195.0);
        assert!(b.north() > 45.1 + 2_400.0 / 111_195.0);
        let lon_m = (1.0 - b.west()) * 111_195.0 * 45.1_f64.to_radians().cos();
        assert!(lon_m >= 2_500.0, "{lon_m}");
    }
}
