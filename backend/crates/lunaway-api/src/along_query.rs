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
    OvernightStatus, PlaceKind, Service, TrimmedLine,
    along::{PIECE_M, Standing, head, length_m, order, pieces, wkt},
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
/// Candidates kept per piece of the line ([`PIECE_M`]), the nearest to it:
/// a town on the way holds hundreds of points of interest within a few
/// kilometres, which would crowd out the rest of the route.
const PER_PIECE: i64 = 60;
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
    offset: usize,
    fingerprint: String,
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
    let places = match &input.places {
        None => None,
        Some(p) => Some(AlongPlaces {
            overnight: p
                .overnight
                .as_deref()
                .map(|o| distinct::<_, OvernightStatus>(Some(o), "places.overnight"))
                .transpose()?,
            kinds: p
                .kinds
                .as_deref()
                .map(|k| distinct::<_, PlaceKind>(Some(k), "places.kinds"))
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
    let fingerprint = fingerprint(input, &poi_kinds, places.as_ref());
    let offset = match &input.after {
        None => 0,
        Some(cursor) => offset_of(cursor, &fingerprint)?,
    };
    Ok(Search {
        poi_kinds,
        places,
        max_detour_km: input.max_detour_km,
        near_m: input.near_km * 1_000.0,
        limit: usize::try_from(input.limit).unwrap_or(1),
        offset,
        fingerprint,
        costing,
    })
}

/// What a cursor is bound to: the line and every setting that orders the
/// candidates, so a cursor never pages another search.
fn fingerprint(input: &AlongRouteInput, kinds: &[PoiKind], places: Option<&AlongPlaces>) -> String {
    let mut h = Sha256::new();
    if let Some(p) = &input.polyline {
        h.update(b"p");
        h.update(p.as_bytes());
    }
    for p in input.points.iter().flatten() {
        h.update(p.lat.to_le_bytes());
        h.update(p.lon.to_le_bytes());
    }
    h.update(b"k");
    for k in kinds {
        h.update(k.code().as_bytes());
        h.update(b",");
    }
    if let Some(p) = places {
        h.update(format!("{p:?}").as_bytes());
    }
    h.update(input.max_detour_km.to_le_bytes());
    h.update(input.near_km.to_le_bytes());
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

/// Where the page of `cursor` starts; refused when it was not issued for
/// this search.
fn offset_of(cursor: &str, fingerprint: &str) -> Result<usize> {
    let foreign = || invalid_input("after: not a cursor of this search; start again without it");
    let text = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(cursor.as_bytes())
        .ok()
        .and_then(|b| String::from_utf8(b).ok())
        .ok_or_else(foreign)?;
    let mut parts = text.split(':');
    match (parts.next(), parts.next(), parts.next(), parts.next()) {
        (Some(CURSOR_VERSION), Some(offset), Some(f), None) if f == fingerprint => {
            offset.parse::<usize>().map_err(|_| foreign())
        }
        _ => Err(foreign()),
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

/// The candidates among `found`, located in `corridor` on a blocking
/// thread, each once.
async fn locate(corridor: Arc<Corridor>, found: Vec<(Of, AlongPoint)>) -> Result<Vec<Candidate>> {
    tokio::task::spawn_blocking(move || {
        let mut seen = std::collections::HashSet::new();
        found
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
            .collect()
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
    let half_width_m = s.max_detour_km * 1_000.0 / 2.0;
    let (corridor, texts) = tokio::task::spawn_blocking(move || {
        let ahead = head(&points, (MAX_SEARCH_M - head_m).max(0.0));
        let texts: Vec<String> = pieces(&ahead, PIECE_M).iter().map(|p| wkt(p)).collect();
        (Corridor::new(ahead, half_width_m), texts)
    })
    .await
    .map_err(|e| internal(&e))?;
    let corridor =
        Arc::new(corridor.ok_or_else(|| {
            invalid_input("the line folds over itself too often to search along it")
        })?);
    let searched_km = (head_m + corridor.length_m()) / 1_000.0;
    let (pool, _permit) = db_share(ctx).await?;
    let mut found: Vec<(Of, AlongPoint)> =
        db::pois(pool, &texts, &s.poi_kinds, half_width_m, PER_PIECE)
            .await
            .map_err(|e| internal(&e))?
            .into_iter()
            .map(|p| (Of::Poi, p))
            .collect();
    if let Some(filter) = &s.places {
        found.extend(
            db::places(pool, &texts, filter, half_width_m, PER_PIECE)
                .await
                .map_err(|e| internal(&e))?
                .into_iter()
                .map(|p| (Of::Place, p)),
        );
    }
    drop(texts);
    let mut candidates = locate(Arc::clone(&corridor), found).await?;
    let standing = |c: &Candidate| Standing {
        along_m: head_m + c.located.along_m,
        minutes: c.detour.minutes,
    };
    let by_order = |a: &Candidate, b: &Candidate| {
        order(standing(a), standing(b), s.near_m).then(a.point.id.cmp(&b.point.id))
    };
    candidates.sort_by(by_order);
    let total = candidates.len();
    let start = s.offset.min(total);
    let end = start.saturating_add(s.limit).min(total);
    let next = (end < total).then(|| cursor_of(end, &s.fingerprint));
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
    page.sort_by(by_order);
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
    }

    #[test]
    fn a_cursor_pages_its_own_search_only() {
        let first = search(&input()).unwrap();
        let cursor = cursor_of(20, &first.fingerprint);
        let mut second = input();
        second.after = Some(cursor.clone());
        assert_eq!(search(&second).unwrap().offset, 20);
        let mut other = input();
        other.near_km = 80.0;
        other.after = Some(cursor);
        assert!(
            message(search(&other)).contains("not a cursor of this search"),
            "a cursor of another order would skip or repeat items"
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
