//! `Query.searchAll`: the places of `search`, the towns of the search
//! (`lunaway_db::towns`) and, asked at the same time, the addresses of the
//! geocoders (`crate::geocode`), ranked under them by
//! `lunaway_domain::address::rank`.

use async_graphql::{Context, Result};
use lunaway_db::{search, towns};
use lunaway_domain::{Position, address};

use crate::{
    address_types::{AddressMatchResult, GqlPoiMatch, SearchAnswer, SearchTown},
    client::ClientKey,
    error::internal,
    geocode::Ask,
    poi_types::{GqlPoiKind, Poi},
    quota::{Action, Subject},
    schema::{GeocodeOnce, db, state},
    types::Place,
};

/// Most towns a search lists: the homonyms of a common name (three
/// Viviers, two Parisot) and the towns that start like it.
const MAX_TOWNS: i64 = 6;

/// The places of `text` near `near` (already on the coarse grid), `first`
/// at most, the towns whose name starts like it when selected, and
/// `addresses` addresses at most, named in `language` where the geocoder
/// knows it, asked of the geocoders at the same time. The geocoders are
/// asked once per request and within the client's quota; beyond either,
/// or when one fails, the places come alone or with some addresses, and
/// `addressesComplete` says so.
pub(crate) async fn search_all(
    ctx: &Context<'_>,
    text: &str,
    near: Option<Position>,
    first: i64,
    addresses: usize,
    language: Option<&str>,
    pois: i64,
) -> Result<SearchAnswer> {
    let st = state(ctx);
    let once = ctx
        .data_opt::<GeocodeOnce>()
        .is_none_or(|o| !o.0.swap(true, std::sync::atomic::Ordering::SeqCst));
    let client = Subject::Client(
        ctx.data_opt::<ClientKey>()
            .copied()
            .unwrap_or(ClientKey::Unknown),
    );
    // The quota last: a text no geocoder is asked for costs nothing.
    let geocode = addresses > 0
        && st.geocoder.would_ask(text)
        && once
        && st.quotas.take(Action::Geocode, client).is_ok();
    // A device that searches its own places asks the addresses alone: the
    // places and the towns are skipped, and the device leaves out its own.
    let look = ctx.look_ahead();
    let wants_places = look.field("places").exists();
    let wants_towns = look.field("towns").exists();
    let places = async {
        if !wants_places {
            return Ok(Vec::new());
        }
        let (pool, _permit) = db(ctx).await?;
        search::search(pool, text, near, first)
            .await
            .map_err(|e| internal(&e))
    };
    let towns = async {
        if !wants_towns {
            return Ok(Vec::new());
        }
        let (pool, _permit) = db(ctx).await?;
        towns::search(pool, text, MAX_TOWNS)
            .await
            .map_err(|e| internal(&e))
    };
    let points = async {
        if pois == 0 {
            return Ok(None);
        }
        crate::poi_query::find(ctx, text, near, None, pois)
            .await
            .map(Some)
    };
    let lookup = async {
        if geocode {
            Some(
                st.geocoder
                    .lookup(Ask {
                        text,
                        near,
                        max: addresses,
                        language,
                    })
                    .await,
            )
        } else {
            None
        }
    };
    let (places, towns, points, lookup) = tokio::join!(places, towns, points, lookup);
    let (places, towns, points) = (places?, towns?, points?);
    let points = PointsFound::from(points);
    let Some(lookup) = lookup else {
        return Ok(SearchAnswer {
            places: places.into_iter().map(Place).collect(),
            towns: towns.into_iter().map(SearchTown::from).collect(),
            addresses: Vec::new(),
            // Nothing was asked: complete only when nothing could have been.
            addresses_complete: addresses == 0 || !st.geocoder.would_ask(text),
            pois: points.pois,
            poi_match: points.matched,
            poi_kinds: points.kinds,
            poi_town: points.town,
        });
    };
    let shown: Vec<address::ShownTown> = towns
        .iter()
        .map(|t| address::ShownTown::new(&t.name, t.postcode.as_deref(), t.country_code.as_deref()))
        .collect();
    let ranked = address::rank(lookup.answers, text, &shown, near, addresses);
    Ok(SearchAnswer {
        places: places.into_iter().map(Place).collect(),
        towns: towns.into_iter().map(SearchTown::from).collect(),
        addresses: ranked.into_iter().map(AddressMatchResult::from).collect(),
        addresses_complete: lookup.complete,
        pois: points.pois,
        poi_match: points.matched,
        poi_kinds: points.kinds,
        poi_town: points.town,
    })
}

/// The points of a search, as the answer carries them.
struct PointsFound {
    pois: Vec<Poi>,
    matched: GqlPoiMatch,
    kinds: Vec<GqlPoiKind>,
    town: Option<SearchTown>,
}

impl From<Option<lunaway_db::poi_search::PoiSearch>> for PointsFound {
    fn from(found: Option<lunaway_db::poi_search::PoiSearch>) -> Self {
        let Some(found) = found else {
            return Self {
                pois: Vec::new(),
                matched: GqlPoiMatch::None,
                kinds: Vec::new(),
                town: None,
            };
        };
        Self {
            pois: found.rows.into_iter().map(Poi::new).collect(),
            matched: found.matched.into(),
            kinds: found.kinds.into_iter().map(Into::into).collect(),
            town: found.town.map(SearchTown::from),
        }
    }
}
