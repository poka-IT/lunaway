//! `Query.alongRoute`: the places and points of interest along the route
//! ahead, by the time their detour adds ([`lunaway_domain::along`]). The
//! resolver checks the input, reads the candidates of the route's band
//! (`lunaway_db::along`), ranks them on an estimate, has the routing engine
//! measure the detours of the page asked ([`crate::detours`]), then reads
//! the page's rows.

use std::{collections::HashMap, ops::RangeInclusive, sync::Arc};

use async_graphql::{Context, Result};
use base64::Engine as _;
use lunaway_db::along::{self as db, AlongPlaces, AlongPoint, FirstPhoto};
use lunaway_domain::{
    OvernightStatus, PlaceKind, Position, Service, TrimmedLine,
    along::{Standing, head, length_m, order},
    fuel::{Corridor, Detour, Located},
    poi::PoiKind,
    trim_ends,
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::{
    along_types::{AlongRoute, AlongRouteDetour, AlongRouteInput, AlongRouteItem},
    client::ClientKey,
    detours::{self, END_CUT_M, Target, check_size, line_of},
    error::{internal, invalid_input, quota_spent},
    external_types::ExternalPhoto,
    poi_types::Poi,
    quota::{Action, Subject},
    routing::valhalla::{Avoid, costing_options},
    schema::{DB_FIELD_COST, ROUTE_FIELD_COST, RouteOnce, db as db_share, state},
    types::Place,
};

/// Most items a page holds: the engine measures the detours of a page
/// together.
pub(crate) const MAX_LIMIT: i32 = 20;
/// Detours accepted, kilometres.
const DETOUR_KM: RangeInclusive<f64> = 0.5..=30.0;
/// Distances of what comes first, kilometres.
const NEAR_KM: RangeInclusive<f64> = 1.0..=1_000.0;
/// How far along the line a search reads, metres from its first point: a
/// day's drive and more. What lies beyond is asked for again on the way.
const MAX_SEARCH_M: f64 = 1_000_000.0;
/// Candidates kept per cell of the corridor's grid (as wide as half the
/// band, 550 m at least): a town on the way holds hundreds of points of
/// interest within a few kilometres, which would crowd out the rest of the
/// route. Real densities keep under it at the app's bands (bakeries in
/// Paris, about 12 a square kilometre, 110 in a cell of 3 km).
const PER_CELL: i64 = 200;
/// Point-of-interest kinds and place filter values at most: each list is
/// one of a taxonomy, sent once.
const MAX_CODES: usize = 64;
/// The form of a cursor, so a cursor of another version reads as foreign.
const CURSOR_VERSION: &str = "a1";

/// The cost of `alongRoute`: its items, plus a route's share
/// ([`ROUTE_FIELD_COST`]), as it waits on the routing engine, plus a
/// database field's ([`DB_FIELD_COST`]).
pub(crate) fn cost(limit: i32, child: usize) -> usize {
    usize::try_from(limit.clamp(1, MAX_LIMIT))
        .unwrap_or(1)
        .saturating_mul(child)
        .saturating_add(ROUTE_FIELD_COST)
        .saturating_add(DB_FIELD_COST)
}

/// The search's settings, checked before anything is spent.
struct Search {
    poi_kinds: Vec<PoiKind>,
    places: Option<AlongPlaces>,
    max_detour_km: f64,
    near_m: f64,
    limit: usize,
    /// The cursor's page and the search it was issued for, checked once
    /// the line is cut.
    after: Option<(usize, String)>,
    costing: Value,
}

/// Each element of `list` once, in its first order, at most [`MAX_CODES`].
fn distinct<T: PartialEq + Copy, U: From<T>>(list: Option<&[T]>, what: &str) -> Result<Vec<U>> {
    let list = list.unwrap_or_default();
    if list.len() > MAX_CODES {
        return Err(invalid_input(format!("{what}: {MAX_CODES} at most")));
    }
    let mut out: Vec<T> = Vec::with_capacity(list.len());
    for v in list {
        if !out.contains(v) {
            out.push(*v);
        }
    }
    Ok(out.into_iter().map(U::from).collect())
}

fn search(input: &AlongRouteInput) -> Result<Search> {
    if !DETOUR_KM.contains(&input.max_detour_km) {
        return Err(invalid_input(format!(
            "maxDetourKm must be between {} and {}",
            DETOUR_KM.start(),
            DETOUR_KM.end()
        )));
    }
    if !NEAR_KM.contains(&input.near_km) {
        return Err(invalid_input(format!(
            "nearKm must be between {} and {}",
            NEAR_KM.start(),
            NEAR_KM.end()
        )));
    }
    if !(1..=MAX_LIMIT).contains(&input.limit) {
        return Err(invalid_input(format!(
            "limit must be between 1 and {MAX_LIMIT}"
        )));
    }
    check_size(input.polyline.as_deref(), input.points.as_deref())?;
    let poi_kinds: Vec<PoiKind> = distinct(input.poi_kinds.as_deref(), "poiKinds")?;
    // An empty list would keep no place while asking for places: absent
    // says "any".
    let some = |what: &str, empty: bool| {
        if empty {
            Err(invalid_input(format!(
                "{what}: give at least one, or leave it out for any"
            )))
        } else {
            Ok(())
        }
    };
    let places = match &input.places {
        None => None,
        Some(p) => Some(AlongPlaces {
            overnight: p
                .overnight
                .as_deref()
                .map(|o| {
                    some("places.overnight", o.is_empty())?;
                    distinct::<_, OvernightStatus>(Some(o), "places.overnight")
                })
                .transpose()?,
            kinds: p
                .kinds
                .as_deref()
                .map(|k| {
                    some("places.kinds", k.is_empty())?;
                    distinct::<_, PlaceKind>(Some(k), "places.kinds")
                })
                .transpose()?,
            any_service: distinct::<_, Service>(p.any_service.as_deref(), "places.anyService")?,
            ..AlongPlaces::default()
        }),
    };
    if poi_kinds.is_empty() && places.is_none() {
        return Err(invalid_input("give poiKinds, places, or both"));
    }
    let (costing, places) = match &input.vehicle {
        Some(v) => {
            let profile = crate::routing_query::vehicle(v)?;
            let places = places.map(|p| AlongPlaces {
                vehicle_height_m: Some(v.height_m),
                vehicle_width_m: Some(v.width_m),
                vehicle_length_m: Some(v.length_m),
                vehicle_weight_t: Some(v.weight_t),
                ..p
            });
            (
                costing_options(&profile.routing(), Avoid::default()),
                places,
            )
        }
        None => (json!({ "auto": {} }), places),
    };
    let after = input.after.as_deref().map(read_cursor).transpose()?;
    Ok(Search {
        poi_kinds,
        places,
        max_detour_km: input.max_detour_km,
        near_m: input.near_km * 1_000.0,
        limit: usize::try_from(input.limit).unwrap_or(1),
        after,
        costing,
    })
}

/// What a cursor is bound to: the line as the search reads it, its ends
/// cut, and every setting that orders the candidates, so a cursor never
/// pages another search.
fn fingerprint(line: &[Position], s: &Search) -> String {
    let mut h = Sha256::new();
    for p in line {
        h.update(p.lat().to_le_bytes());
        h.update(p.lon().to_le_bytes());
    }
    h.update(b"k");
    for k in &s.poi_kinds {
        h.update(k.code().as_bytes());
        h.update(b",");
    }
    if let Some(p) = &s.places {
        h.update(format!("{p:?}").as_bytes());
    }
    h.update(s.max_detour_km.to_le_bytes());
    h.update(s.near_m.to_le_bytes());
    let digest = h.finalize();
    digest
        .iter()
        .take(8)
        .fold(String::with_capacity(16), |mut s, b| {
            s.push(char::from_digit(u32::from(b >> 4), 16).unwrap_or('0'));
            s.push(char::from_digit(u32::from(b & 0xf), 16).unwrap_or('0'));
            s
        })
}

/// The cursor of the page starting at `offset`.
fn cursor_of(offset: usize, fingerprint: &str) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD
        .encode(format!("{CURSOR_VERSION}:{offset}:{fingerprint}"))
}

fn foreign_cursor() -> async_graphql::Error {
    invalid_input("after: not a cursor of this search; start again without it")
}

/// Where the page of `cursor` starts, and the search it was issued for;
/// refused when it is not a cursor this API wrote.
fn read_cursor(cursor: &str) -> Result<(usize, String)> {
    let text = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(cursor.as_bytes())
        .ok()
        .and_then(|b| String::from_utf8(b).ok())
        .ok_or_else(foreign_cursor)?;
    let mut parts = text.split(':');
    match (parts.next(), parts.next(), parts.next(), parts.next()) {
        (Some(CURSOR_VERSION), Some(offset), Some(f), None) => Ok((
            offset.parse::<usize>().map_err(|_| foreign_cursor())?,
            f.to_owned(),
        )),
        _ => Err(foreign_cursor()),
    }
}

/// Where the page asked starts: 0 without a cursor; refused for a cursor
/// issued for another search, which would skip or repeat items.
fn offset_of(after: Option<&(usize, String)>, fingerprint: &str) -> Result<usize> {
    match after {
        None => Ok(0),
        Some((offset, f)) if f == fingerprint => Ok(*offset),
        Some(_) => Err(foreign_cursor()),
    }
}

/// What a candidate is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Of {
    Poi,
    Place,
}

/// A candidate of the band.
#[derive(Debug, Clone, Copy)]
struct Candidate {
    of: Of,
    point: AlongPoint,
    located: Located,
    detour: Detour,
}

/// The order of the list ([`order`]), for a corridor starting `head_m`
/// along the line; ties by id, so a page is the same page each time.
fn by_order(a: &Candidate, b: &Candidate, head_m: f64, near_m: f64) -> std::cmp::Ordering {
    let standing = |c: &Candidate| Standing {
        along_m: head_m + c.located.along_m,
        minutes: c.detour.minutes,
    };
    order(standing(a), standing(b), near_m).then(a.point.id.cmp(&b.point.id))
}

/// The candidates among `found`, each once, located in `corridor` and
/// ranked on their estimates ([`by_order`]) on a blocking thread: tens of
/// thousands at most, which take milliseconds.
async fn locate(
    corridor: Arc<Corridor>,
    found: Vec<(Of, AlongPoint)>,
    head_m: f64,
    near_m: f64,
) -> Result<Vec<Candidate>> {
    tokio::task::spawn_blocking(move || {
        let mut seen = std::collections::HashSet::new();
        let mut out: Vec<Candidate> = found
            .into_iter()
            .filter(|(_, p)| seen.insert(p.id))
            .filter_map(|(of, point)| {
                let located = corridor.locate(point.position)?;
                Some(Candidate {
                    of,
                    point,
                    detour: Detour::estimated(located.offset_m),
                    located,
                })
            })
            .collect();
        out.sort_by(|a, b| by_order(a, b, head_m, near_m));
        out
    })
    .await
    .map_err(|e| internal(&e))
}

/// `Query.alongRoute`.
pub(crate) async fn along_route(ctx: &Context<'_>, input: AlongRouteInput) -> Result<AlongRoute> {
    // One engine search per request, whether a route, fuel or this.
    if let Some(once) = ctx.data_opt::<RouteOnce>()
        && once.0.swap(true, std::sync::atomic::Ordering::SeqCst)
    {
        return Err(invalid_input(
            "one route or search along a route per request",
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
        .take(Action::AlongRoute, client)
        .map_err(|wait| quota_spent("searches along a route", wait))?;
    let points = line_of(input.polyline.as_deref(), input.points.as_deref())?;
    // The line's ends are where the device is and where it goes: they are
    // cut before anything reads the line, and the search runs on the rest.
    let Some(trimmed) = trim_ends(&points, END_CUT_M) else {
        return Ok(AlongRoute {
            items: Vec::new(),
            route_km: length_m(&points) / 1_000.0,
            searched_km: 0.0,
            candidates: 0,
            next: None,
            detours_measured: false,
        });
    };
    drop(points);
    let TrimmedLine {
        points,
        head_m,
        total_m,
    } = trimmed;
    let fingerprint = fingerprint(&points, &s);
    let offset = offset_of(s.after.as_ref(), &fingerprint)?;
    let half_width_m = s.max_detour_km * 1_000.0 / 2.0;
    let (corridor, cells) = tokio::task::spawn_blocking(move || {
        let ahead = head(&points, (MAX_SEARCH_M - head_m).max(0.0));
        let corridor = Corridor::new(ahead, half_width_m);
        let cells = corridor.as_ref().map(Corridor::cell_boxes);
        (corridor, cells)
    })
    .await
    .map_err(|e| internal(&e))?;
    let (Some(corridor), Some(cells)) = (corridor, cells) else {
        return Err(invalid_input(
            "the line folds over itself too often to search along it",
        ));
    };
    let corridor = Arc::new(corridor);
    let searched_km = (head_m + corridor.length_m()) / 1_000.0;
    let (pool, _permit) = db_share(ctx).await?;
    let mut found: Vec<(Of, AlongPoint)> = db::pois(pool, &cells, &s.poi_kinds, PER_CELL)
        .await
        .map_err(|e| internal(&e))?
        .into_iter()
        .map(|p| (Of::Poi, p))
        .collect();
    if let Some(filter) = &s.places {
        found.extend(
            db::places(pool, &cells, filter, PER_CELL)
                .await
                .map_err(|e| internal(&e))?
                .into_iter()
                .map(|p| (Of::Place, p)),
        );
    }
    drop(cells);
    let mut candidates = locate(Arc::clone(&corridor), found, head_m, s.near_m).await?;
    let total = candidates.len();
    let start = offset.min(total);
    let end = start.saturating_add(s.limit).min(total);
    let next = (end < total).then(|| cursor_of(end, &fingerprint));
    let mut page: Vec<Candidate> = candidates.drain(start..end).collect();
    drop(candidates);
    let targets: Vec<Target> = page
        .iter()
        .map(|c| Target {
            at: c.point.position,
            along_m: c.located.along_m,
        })
        .collect();
    let measured = detours::measure(ctx, &corridor, &s.costing, &targets).await;
    for (c, m) in page.iter_mut().zip(measured) {
        if let Some(d) = m {
            c.detour = d;
        }
    }
    // Measured, a road may be longer than the estimate; estimated, the
    // straight line already says it is too far.
    page.retain(|c| c.detour.km <= s.max_detour_km);
    page.sort_by(|a, b| by_order(a, b, head_m, s.near_m));
    let items = items_of(ctx, pool, &page, head_m).await?;
    let detours_measured = !items.is_empty() && items.iter().all(|i| i.detour.measured);
    Ok(AlongRoute {
        items,
        route_km: total_m / 1_000.0,
        searched_km,
        candidates: i32::try_from(total).unwrap_or(i32::MAX),
        next,
        detours_measured,
    })
}

/// The rows of `page`, in its order; a candidate whose row went in the
/// meantime is left out.
async fn items_of(
    ctx: &Context<'_>,
    pool: &lunaway_db::PgPool,
    page: &[Candidate],
    head_m: f64,
) -> Result<Vec<AlongRouteItem>> {
    let ids = |of: Of| -> Vec<Uuid> {
        page.iter()
            .filter(|c| c.of == of)
            .map(|c| c.point.id)
            .collect()
    };
    let (poi_ids, place_ids) = (ids(Of::Poi), ids(Of::Place));
    let mut pois: HashMap<Uuid, _> = if poi_ids.is_empty() {
        HashMap::new()
    } else {
        lunaway_db::pois::by_ids(pool, &poi_ids)
            .await
            .map_err(|e| internal(&e))?
            .into_iter()
            .map(|r| (r.id, r))
            .collect()
    };
    let mut places: HashMap<Uuid, _> = db::places_by_ids(pool, &place_ids)
        .await
        .map_err(|e| internal(&e))?
        .into_iter()
        .map(|r| (r.id, r))
        .collect();
    let config = &state(ctx).config;
    let mut photos: HashMap<Uuid, ExternalPhoto> = db::first_photos(pool, &place_ids)
        .await
        .map_err(|e| internal(&e))?
        .into_iter()
        .map(|(id, photo)| {
            (
                id,
                match photo {
                    FirstPhoto::Partner(r) => {
                        ExternalPhoto::from_row(r, &config.media, &config.tiles.public_url)
                    }
                    FirstPhoto::Open(r) => ExternalPhoto::from_content(r, &config.media),
                },
            )
        })
        .collect();
    Ok(page
        .iter()
        .filter_map(|c| {
            let (place, poi, photo) = match c.of {
                Of::Poi => (None, Some(Poi::new(pois.remove(&c.point.id)?)), None),
                Of::Place => (
                    Some(Place(places.remove(&c.point.id)?)),
                    None,
                    photos.remove(&c.point.id),
                ),
            };
            Some(AlongRouteItem {
                along_km: (head_m + c.located.along_m) / 1_000.0,
                distance_m: c.located.offset_m.round(),
                detour: AlongRouteDetour {
                    km: c.detour.km,
                    minutes: c.detour.minutes,
                    measured: c.detour.measured,
                },
                place,
                poi,
                photo,
            })
        })
        .collect())
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        reason = "a test states its preconditions with unwrap"
    )]
    use lunaway_domain::{Position, routing::polyline};

    use super::*;
    use crate::{
        along_types::AlongRoutePlacesInput,
        poi_types::GqlPoiKind,
        types::{GqlOvernightStatus, LatLonInput},
    };

    fn input() -> AlongRouteInput {
        AlongRouteInput {
            polyline: Some(polyline::encode(&[
                Position::new(45.0, 1.0).unwrap(),
                Position::new(45.1, 1.0).unwrap(),
            ])),
            points: None,
            poi_kinds: Some(vec![GqlPoiKind::Toilets, GqlPoiKind::Toilets]),
            places: None,
            max_detour_km: 6.0,
            near_km: 50.0,
            limit: 20,
            after: None,
            vehicle: None,
        }
    }

    fn message<T>(r: Result<T>) -> String {
        r.err().map(|e| e.message).unwrap_or_default()
    }

    #[test]
    fn a_search_outside_its_bounds_is_refused_before_anything_is_spent() {
        let ok = search(&input()).unwrap();
        assert_eq!(ok.poi_kinds, vec![PoiKind::Toilets], "each kind once");
        let mut far = input();
        far.max_detour_km = 31.0;
        assert!(message(search(&far)).contains("maxDetourKm"));
        let mut near = input();
        near.near_km = 0.0;
        assert!(message(search(&near)).contains("nearKm"));
        let mut many = input();
        many.limit = 21;
        assert!(message(search(&many)).contains("limit"));
        let mut nothing = input();
        nothing.poi_kinds = Some(Vec::new());
        assert!(message(search(&nothing)).contains("poiKinds, places"));
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
        long.polyline = Some("_".repeat(detours::MAX_POLYLINE_CHARS + 1));
        assert!(message(search(&long)).contains("simplify"));
        let mut crowded = input();
        crowded.places = Some(AlongRoutePlacesInput {
            overnight: Some(vec![GqlOvernightStatus::Allowed; MAX_CODES + 1]),
            ..AlongRoutePlacesInput::default()
        });
        assert!(message(search(&crowded)).contains("places.overnight"));
        let mut none = input();
        none.poi_kinds = None;
        none.places = Some(AlongRoutePlacesInput {
            kinds: Some(Vec::new()),
            ..AlongRoutePlacesInput::default()
        });
        assert!(
            message(search(&none)).contains("places.kinds: give at least one"),
            "an empty list would ask for places and keep none"
        );
    }

    #[test]
    fn a_cursor_pages_its_own_search_only() {
        let line = [
            Position::new(45.0, 1.0).unwrap(),
            Position::new(45.1, 1.0).unwrap(),
        ];
        let first = fingerprint(&line, &search(&input()).unwrap());
        let cursor = cursor_of(20, &first);
        let mut second = input();
        second.after = Some(cursor.clone());
        let s = search(&second).unwrap();
        assert_eq!(
            offset_of(s.after.as_ref(), &fingerprint(&line, &s)).unwrap(),
            20
        );
        let mut other = input();
        other.near_km = 80.0;
        other.after = Some(cursor.clone());
        let o = search(&other).unwrap();
        assert!(
            message(offset_of(o.after.as_ref(), &fingerprint(&line, &o)))
                .contains("not a cursor of this search"),
            "a cursor of another order would skip or repeat items"
        );
        let elsewhere = [line[0], Position::new(45.1, 1.01).unwrap()];
        assert!(
            offset_of(s.after.as_ref(), &fingerprint(&elsewhere, &s)).is_err(),
            "nor one of another line"
        );
        let mut forged = input();
        forged.after = Some("bm90IGEgY3Vyc29y".to_owned());
        assert!(message(search(&forged)).contains("not a cursor"));
    }

    #[test]
    fn a_vehicle_leaves_out_the_places_it_does_not_fit() {
        let mut i = input();
        i.places = Some(AlongRoutePlacesInput {
            overnight: Some(vec![
                GqlOvernightStatus::Allowed,
                GqlOvernightStatus::Tolerated,
            ]),
            ..AlongRoutePlacesInput::default()
        });
        i.vehicle = Some(crate::routing_types::VehicleProfileInput {
            kind: crate::routing_types::GqlVehicleType::Overcab,
            height_m: 3.3,
            width_m: 2.3,
            length_m: 7.4,
            weight_t: 3.5,
            axle_load_t: None,
            trailer: None,
            cruise_speed_kph: Some(90),
        });
        let s = search(&i).unwrap();
        let p = s.places.unwrap();
        assert_eq!(
            p.overnight,
            Some(vec![OvernightStatus::Allowed, OvernightStatus::Tolerated])
        );
        assert_eq!(
            (
                p.vehicle_height_m,
                p.vehicle_width_m,
                p.vehicle_length_m,
                p.vehicle_weight_t
            ),
            (Some(3.3), Some(2.3), Some(7.4), Some(3.5))
        );
        assert_eq!(s.costing["auto"]["top_speed"], json!(90));
    }
}
