//! The GraphQL schema. Resolvers stay thin: they check and parse their
//! arguments, call a repository of `lunaway-db`, and map the rows; the rules
//! live in the domain and the conflation, so the GraphQL library can be
//! replaced without touching them.

use std::sync::Arc;

use async_graphql::{
    Context, EmptySubscription, Object, Result, Schema, SchemaBuilder, dataloader::DataLoader,
};
use lunaway_db::{PgPool, places, search, sources};
use lunaway_domain::{BBox, PlaceKind, Position};
use tokio::sync::{OwnedSemaphorePermit, Semaphore, SemaphorePermit};
use uuid::Uuid;

use crate::{
    auth::{self, Challenges},
    community_types::{Account, FavoriteList},
    config::ApiConfig,
    enforcement_types::EnforcementDelta,
    error::{internal, invalid_input, resync},
    guard::DocumentGuard,
    loaders::PlaceSourcesLoader,
    mutation::MutationRoot,
    poi_query,
    poi_types::{
        GqlPoiCategory, GqlPoiKind, NearbyPois, Poi, PoiCategoryInfo, PoiConnection, PoiLayer,
    },
    quota::QuotaLimiter,
    rate::RateLimiter,
    road_event_types::{GqlRoadEventClass, RoadEventDelta, RoadEventSourceStatus},
    routing_types::{RouteInput, RouteResult, RoutingInfo},
    types::{
        AppConfig, BBoxInput, ChangeSet, GqlPlaceKind, LatLonInput, Place, PlaceConnection,
        PlaceFilterInput, Source,
    },
};

/// The schema served by the API.
pub type LunawaySchema = Schema<QueryRoot, MutationRoot, EmptySubscription>;

/// Deepest selection accepted: the deepest legitimate one,
/// `changes { places { sources { source { id } } } }`, is 5.
const MAX_DEPTH: usize = 12;
/// Cost budget of one request. The app's sync page (`changes` with 1000
/// places and every field it stores, sources, provenance, descriptions,
/// ratings and links included) costs 67 000 (`tests/budget.rs`), with room
/// for the other feed fields (cover photos, counts, issues, verification,
/// municipality: about 82 000 with all of them); two pages in one request
/// do not fit.
pub const MAX_COMPLEXITY: usize = 90_000;
/// Cost of a root field that queries the database, on top of what it
/// returns: a page size bounds the rows, not the work (a two-letter search
/// scans every name), so each such field takes a fixed share of the budget
/// and a request holds at most 11 of them.
pub const DB_FIELD_COST: usize = 5_000;
/// Cost of `route`, whatever it returns, in the client's budget and in the
/// API's cost in flight. Kept small: a route waits on the engine, and a
/// large share held while it waits would hold back every other request
/// (security audit of 2026-10-06). What bounds routes is elsewhere: one per
/// request (`RouteOnce`), the per-client quota (`Quotas::route`), and the
/// engine slots, held until an answer is checked, which bound the memory of
/// the answers in hand.
pub const ROUTE_FIELD_COST: usize = 10_000;

/// Set by the first `route` of a request: a second one is refused, so a
/// document cannot fan one request out into many engine calls.
#[derive(Debug, Default)]
pub(crate) struct RouteOnce(pub(crate) std::sync::atomic::AtomicBool);
/// Largest page of `changes`.
pub const MAX_CHANGES_PAGE: i32 = 1_000;
/// Largest page of `places`.
pub const MAX_PLACES_PAGE: i32 = 500;
/// Most results of `search`.
pub const MAX_SEARCH_RESULTS: i32 = 50;
/// Largest viewport of `places`, in square degrees: about 500 km by 500 km
/// in France. A wider map shows the places' tiles. With `near`, any
/// viewport is accepted: the page is the nearest `first` places, and
/// counting the 86 111 places of a European viewport took 38 ms
/// (`docs/deploy.md`, "Places layer").
pub const MAX_PLACES_AREA_DEG2: f64 = 25.0;
/// Most groups in `PlaceFilter.serviceGroups`, and most services in one:
/// as many as there are services.
const MAX_SERVICE_GROUPS: usize = 17;
/// Largest region of `changes`, in square degrees: metropolitan France and
/// Corsica (about 165) fit with room to spare.
pub const MAX_CHANGES_AREA_DEG2: f64 = 400.0;
/// Shortest and longest search text, in characters.
const SEARCH_TEXT_CHARS: std::ops::RangeInclusive<usize> = 2..=100;

/// What the resolvers share. A clone shares the same budgets and caches.
#[derive(Clone)]
pub struct ApiState {
    /// The database.
    pub pool: PgPool,
    /// The policy the app is told about, and the server's limits.
    pub config: ApiConfig,
    /// The clients' budgets.
    pub(crate) rate: Arc<RateLimiter>,
    /// Cost of the requests running, across clients
    /// (`Limits::max_cost_in_flight`): what bounds the memory they hold.
    pub(crate) in_flight: Arc<Semaphore>,
    /// Per-account and per-client quotas of actions.
    pub(crate) quotas: Arc<QuotaLimiter>,
    /// Sign-in challenges handed out.
    pub(crate) challenges: Arc<Challenges>,
    /// The photo files.
    pub(crate) media: Arc<lunaway_media::MediaStore>,
    /// Photos processed at once (`MediaConfig::workers`).
    pub(crate) media_workers: Arc<Semaphore>,
    /// The routing engine and its calls in flight.
    pub(crate) routing: Arc<crate::routing::Routing>,
    /// The road events feed's head and first pages, in memory.
    pub(crate) road_events: Arc<crate::road_events_query::RoadEventsCache>,
    /// The speed cameras feed's head and first pages, in memory.
    pub(crate) enforcement: Arc<crate::enforcement_query::EnforcementCache>,
    /// Where the photo proxy gets a partner's photos.
    pub(crate) external_photos: crate::external_photos::PhotoSource,
}

impl ApiState {
    /// The state over `pool`, with fresh budgets sized by `config`.
    #[must_use]
    pub fn new(pool: PgPool, config: ApiConfig) -> Self {
        let rate = Arc::new(RateLimiter::new(
            config.limits.rate_burst,
            config.limits.rate_per_second,
        ));
        let in_flight = Arc::new(Semaphore::new(config.limits.max_cost_in_flight));
        let quotas = Arc::new(QuotaLimiter::new(config.quotas));
        // A key from the system's random source; without one no sign-in
        // could work, and the process cannot serve its purpose.
        #[allow(
            clippy::expect_used,
            reason = "the API cannot sign anyone in without a random source"
        )]
        let challenges = Arc::new(
            Challenges::new(config.auth.challenge_ttl, config.auth.max_challenges)
                .expect("the system random source must supply a challenge key"),
        );
        let media = Arc::new(lunaway_media::MediaStore::new(config.media.dir.clone()));
        let media_workers = Arc::new(Semaphore::new(config.media.workers));
        let routing = Arc::new(crate::routing::Routing::new(&config.routing));
        let external_photos = crate::external_photos::PhotoSource::network(
            config.external_photos.timeout,
        )
        .unwrap_or_else(|error| {
            tracing::error!(%error, "no HTTPS client: the partner's photos are not fetched");
            crate::external_photos::PhotoSource::Memory(Arc::default())
        });
        Self {
            pool,
            config,
            rate,
            in_flight,
            quotas,
            challenges,
            media,
            media_workers,
            routing,
            road_events: Arc::default(),
            enforcement: Arc::default(),
            external_photos,
        }
    }

    /// Computes again the restrictions a trip's first engine call excludes,
    /// found by routes between the capitals of the graph's countries
    /// (`routing::public`), when the restrictions changed since the last
    /// time: what it did, `None` when nothing changed or it failed (the
    /// failure is logged, the lists stay as they were). Takes minutes of
    /// one engine slot at a time, never one a client's trip waits for.
    pub async fn refresh_route_blockers(&self) -> Option<crate::routing::public::Refreshed> {
        let seeds = crate::routing::public::SEEDS.map(|(_, lat, lon)| (lat, lon));
        self.refresh_route_blockers_from(&seeds).await
    }

    /// [`Self::refresh_route_blockers`] from `seeds`, latitude and
    /// longitude: a test's own points.
    pub async fn refresh_route_blockers_from(
        &self,
        seeds: &[(f64, f64)],
    ) -> Option<crate::routing::public::Refreshed> {
        let seeds: Vec<lunaway_domain::Position> = seeds
            .iter()
            .filter_map(|&(lat, lon)| lunaway_domain::Position::new(lat, lon).ok())
            .collect();
        match self.routing.refresh_public(&self.pool, &seeds).await {
            Ok(done) => done,
            Err(error) => {
                tracing::warn!(%error, "the restrictions kept ahead could not be computed again");
                None
            }
        }
    }

    /// The same state with the partner's photos read from `source`
    /// instead of the network: for the tests, and for a development server
    /// that must not reach a partner.
    #[must_use]
    pub fn with_external_photos(mut self, source: crate::external_photos::PhotoSource) -> Self {
        self.external_photos = source;
        self
    }
}

/// The database share of one request: at most
/// `Limits::db_queries_per_request` of its fields query at once, so a
/// request of many aliases waits on itself instead of taking the pool.
pub(crate) struct RequestDb(pub(crate) Semaphore);

/// The share of `ApiState::in_flight` a request holds once its cost is
/// known, released when the request ends.
#[derive(Default)]
pub(crate) struct CostShare(pub(crate) std::sync::Mutex<Option<OwnedSemaphorePermit>>);

/// The schema's builder with its limits, before any data is attached: what
/// the SDL export needs.
#[must_use]
pub fn schema_builder() -> SchemaBuilder<QueryRoot, MutationRoot, EmptySubscription> {
    Schema::build(QueryRoot, MutationRoot, EmptySubscription)
        .limit_depth(MAX_DEPTH)
        .limit_complexity(MAX_COMPLEXITY)
        .extension(DocumentGuard)
}

/// Builds the schema served over `state`.
#[must_use]
pub fn build_schema(state: ApiState) -> LunawaySchema {
    let loader = DataLoader::new(PlaceSourcesLoader::Pool(state.pool.clone()), tokio::spawn);
    let trends = DataLoader::new(
        crate::loaders::FuelTrendLoader(state.pool.clone()),
        tokio::spawn,
    );
    let points = DataLoader::new(crate::loaders::PoiLoader(state.pool.clone()), tokio::spawn);
    schema_builder()
        .data(state)
        .data(loader)
        .data(trends)
        .data(points)
        .finish()
}

fn bbox(input: BBoxInput, max_area: f64) -> Result<BBox> {
    let b = BBox::new(input.south, input.west, input.north, input.east)
        .map_err(|e| invalid_input(format!("bbox: {e}")))?;
    if b.area_deg2() > max_area {
        return Err(invalid_input(format!(
            "bbox covers {:.1} square degrees, more than the {max_area} allowed",
            b.area_deg2()
        )));
    }
    Ok(b)
}

/// Page size of `places` when the client does not say.
const DEFAULT_PLACES_PAGE: i32 = 200;
/// Results of `search` when the client does not say.
const DEFAULT_SEARCH_RESULTS: i32 = 20;

/// The cost of a list field read from the database: its page size times the
/// cost of one item, plus [`DB_FIELD_COST`]. An explicit `null` costs as the
/// default page it falls back to.
pub(crate) fn cost(first: Option<i32>, default: i32, child: usize) -> usize {
    usize::try_from(first.unwrap_or(default))
        .unwrap_or(0)
        .saturating_mul(child)
        .saturating_add(DB_FIELD_COST)
}

fn page(first: i32, max: i32) -> Result<i64> {
    if (1..=max).contains(&first) {
        Ok(i64::from(first))
    } else {
        Err(invalid_input(format!(
            "first must be between 1 and {max}, got {first}"
        )))
    }
}

/// A change cursor: `c2.<identity>.<position>`. The identity names the copy
/// of the database that issued it (`places::FeedHead::identity`: its random
/// epoch and its own identifier), so a cursor from before a restore is
/// answered with `RESYNC` instead of skipping changes; so is a cursor past
/// the end of the feed, which no copy of this feed issued.
const CHANGES_CURSOR: &str = "c2.";
/// Cursors issued before the epoch existed.
const CHANGES_CURSOR_V1: &str = "c1.";
const PLACES_CURSOR: &str = "p1.";
/// The cursor of `places(near:)`: the last place's distance (the bits of
/// the database's float, so the next page starts exactly after it) and id.
const PLACES_NEAR_CURSOR: &str = "n1.";

pub(crate) fn changes_cursor(head: &places::FeedHead, seq: i64) -> String {
    format!("{CHANGES_CURSOR}{}.{seq}", head.identity())
}

/// What a sync page covers.
enum FeedArea {
    BBox(lunaway_domain::BBox),
    Region(&'static str),
}

/// A `since` cursor, read before the database is asked anything.
#[derive(Debug, PartialEq, Eq)]
enum Since {
    /// From the start of the feed.
    Start,
    /// After `seq` of the feed named `identity`.
    After { identity: String, seq: i64 },
    /// A cursor older than identities: always another copy.
    Legacy,
}

fn parse_since(since: Option<&str>) -> Result<Since> {
    let Some(s) = since else {
        return Ok(Since::Start);
    };
    let malformed = || invalid_input("since is not a cursor this API returned");
    let position = |n: &str| n.parse::<i64>().ok().filter(|n| *n >= 0);
    if let Some(seq) = s.strip_prefix(CHANGES_CURSOR_V1) {
        return position(seq).map(|_| Since::Legacy).ok_or_else(malformed);
    }
    let (identity, seq) = s
        .strip_prefix(CHANGES_CURSOR)
        .and_then(|rest| rest.split_once('.'))
        .ok_or_else(malformed)?;
    if identity.len() != 40 || !identity.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(malformed());
    }
    let seq = position(seq).ok_or_else(malformed)?;
    Ok(Since::After {
        identity: identity.to_ascii_lowercase(),
        seq,
    })
}

/// The feed position to read after, once the feed's head is known.
fn since_seq(since: &Since, head: &places::FeedHead) -> Result<i64> {
    match since {
        Since::Start => Ok(0),
        Since::After { identity, seq } if *identity == head.identity() && *seq <= head.last_seq => {
            Ok(*seq)
        }
        Since::After { .. } | Since::Legacy => Err(resync()),
    }
}

/// The filter of `places`, checked: positive vehicle sizes, and lists no
/// longer than what the enums hold.
fn place_filter(f: PlaceFilterInput) -> Result<places::PlaceFilter> {
    for (name, v) in [
        ("vehicleHeightM", f.vehicle_height_m),
        ("vehicleLengthM", f.vehicle_length_m),
        ("vehicleWidthM", f.vehicle_width_m),
        ("vehicleWeightT", f.vehicle_weight_t),
    ] {
        if let Some(v) = v
            && !(v.is_finite() && v > 0.0)
        {
            return Err(invalid_input(format!("{name} must be a positive number")));
        }
    }
    if f.overnight
        .as_ref()
        .is_some_and(|o| o.is_empty() || o.len() > lunaway_domain::OvernightStatus::ALL.len())
    {
        // Empty would keep nothing: absent means every status.
        return Err(invalid_input(
            "overnight lists 1 to 5 statuses; leave it out for every status",
        ));
    }
    let groups = f.service_groups.unwrap_or_default();
    if groups.len() > MAX_SERVICE_GROUPS
        || groups
            .iter()
            .any(|g| g.is_empty() || g.len() > lunaway_domain::Service::ALL.len())
    {
        return Err(invalid_input(format!(
            "serviceGroups holds 1 to {MAX_SERVICE_GROUPS} groups of 1 to {} services",
            lunaway_domain::Service::ALL.len()
        )));
    }
    Ok(places::PlaceFilter {
        kinds: f.kinds.map(|k| k.into_iter().map(Into::into).collect()),
        services: f
            .services
            .unwrap_or_default()
            .into_iter()
            .map(Into::into)
            .collect(),
        overnight_ok: f.overnight_ok.unwrap_or(false),
        vehicle_height_m: f.vehicle_height_m,
        vehicle_length_m: f.vehicle_length_m,
        vehicle_width_m: f.vehicle_width_m,
        vehicle_weight_t: f.vehicle_weight_t,
        overnight: f.overnight.map(|o| o.into_iter().map(Into::into).collect()),
        service_groups: groups
            .into_iter()
            .map(|g| g.into_iter().map(Into::into).collect())
            .collect(),
        free_only: f.free_only.unwrap_or(false),
    })
}

fn near_cursor(distance_m: f64, id: Uuid) -> String {
    format!("{PLACES_NEAR_CURSOR}{:016x}.{id}", distance_m.to_bits())
}

fn parse_near_after(after: Option<&str>) -> Result<Option<places::NearAfter>> {
    after
        .map(|s| {
            s.strip_prefix(PLACES_NEAR_CURSOR)
                .and_then(|rest| rest.split_once('.'))
                .and_then(|(bits, id)| {
                    let distance_m = f64::from_bits(u64::from_str_radix(bits, 16).ok()?);
                    (distance_m.is_finite() && distance_m >= 0.0).then_some(())?;
                    Some(places::NearAfter {
                        distance_m,
                        id: Uuid::parse_str(id).ok()?,
                    })
                })
                .ok_or_else(|| invalid_input("after is not a cursor this API returned"))
        })
        .transpose()
}

fn parse_after(after: Option<&str>) -> Result<Option<Uuid>> {
    after
        .map(|s| {
            s.strip_prefix(PLACES_CURSOR)
                .and_then(|u| Uuid::parse_str(u).ok())
                .ok_or_else(|| invalid_input("after is not a cursor this API returned"))
        })
        .transpose()
}

pub(crate) fn state<'a>(ctx: &Context<'a>) -> &'a ApiState {
    ctx.data_unchecked::<ApiState>()
}

/// The pool, once this request may run one more query.
pub(crate) async fn db<'a>(ctx: &Context<'a>) -> Result<(&'a PgPool, Option<SemaphorePermit<'a>>)> {
    let permit = match ctx.data_opt::<RequestDb>() {
        Some(share) => Some(share.0.acquire().await.map_err(|e| internal(&e))?),
        None => None,
    };
    Ok((&state(ctx).pool, permit))
}

/// Root of every read.
#[derive(Debug, Default)]
pub struct QueryRoot;

#[Object(name = "Query")]
impl QueryRoot {
    /// Version of the running API.
    async fn api_version(&self) -> &'static str {
        env!("CARGO_PKG_VERSION")
    }

    /// The server's policy for the app.
    async fn config(&self, ctx: &Context<'_>) -> AppConfig {
        AppConfig {
            min_app_version: state(ctx).config.min_app_version.clone(),
        }
    }

    /// Every kind of place, in display order.
    async fn place_kinds(&self) -> Vec<GqlPlaceKind> {
        PlaceKind::ALL
            .iter()
            .copied()
            .map(GqlPlaceKind::from)
            .collect()
    }

    /// Every data source, with its licence and attribution.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn sources(&self, ctx: &Context<'_>) -> Result<Vec<Source>> {
        let (pool, _permit) = db(ctx).await?;
        let rows = sources::list(pool).await.map_err(|e| internal(&e))?;
        Ok(rows
            .into_iter()
            .map(|s| Source {
                id: s.id.to_string(),
                name: s.name,
                licence: s.licence,
                attribution: s.attribution,
                url: s.url,
            })
            .collect())
    }

    /// Syncs a region: the places inside `bbox`, or of the sync region
    /// `region` (`Query.regions`, one of the two), created or changed since
    /// the cursor `since` (null for everything), oldest change first, at
    /// most `first` (1000 at most), the places deleted since and, by
    /// `region`, the places that left it (at most `first` more). A device
    /// that imported a region's pack continues with `region` and the pack's
    /// cursor. A cursor issued by another copy of the database (after a
    /// restore) is refused with the code `RESYNC`: sync again with `since:
    /// null`, or from the region's current pack.
    #[graphql(complexity = "cost(first, MAX_CHANGES_PAGE, child_complexity)")]
    async fn changes(
        &self,
        ctx: &Context<'_>,
        bbox: Option<BBoxInput>,
        region: Option<String>,
        since: Option<String>,
        #[graphql(default = 1000)] first: Option<i32>,
    ) -> Result<ChangeSet> {
        let area = match (bbox, region.as_deref()) {
            (Some(b), None) => FeedArea::BBox(self::bbox(b, MAX_CHANGES_AREA_DEG2)?),
            (None, Some(r)) => FeedArea::Region(
                lunaway_domain::region::sync_region(r)
                    .ok_or_else(|| invalid_input(format!("region {r:?} is not a sync region")))?
                    .code,
            ),
            _ => return Err(invalid_input("give either bbox or region")),
        };
        let first = page(first.unwrap_or(MAX_CHANGES_PAGE), MAX_CHANGES_PAGE)?;
        let since = parse_since(since.as_deref())?;
        let (pool, _permit) = db(ctx).await?;
        let head = places::feed_head(pool).await.map_err(|e| internal(&e))?;
        let since_seq = since_seq(&since, &head)?;
        let with_deletions = since != Since::Start;
        let (changes, has_more) = match area {
            FeedArea::BBox(area) => {
                places::changes(pool, area, since_seq, first, with_deletions).await
            }
            FeedArea::Region(code) => {
                places::changes_in_region(pool, code, since_seq, first, with_deletions).await
            }
        }
        .map_err(|e| internal(&e))?;
        let cursor_seq = changes.last().map_or(since_seq, places::Change::seq);
        let mut out = Vec::new();
        let mut deleted = Vec::new();
        let mut left = Vec::new();
        for c in changes {
            match c {
                places::Change::Upsert(p) => out.push(Place(*p)),
                places::Change::Delete { id, .. } => deleted.push(id),
                places::Change::Left { id, .. } => left.push(id),
            }
        }
        Ok(ChangeSet {
            places: out,
            deleted,
            left,
            cursor: changes_cursor(&head, cursor_seq),
            has_more,
        })
    }

    /// The regions a device can keep offline, with the pack to download
    /// first for each (`docs/region-packs.md`).
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn regions(&self, ctx: &Context<'_>) -> Result<Vec<crate::region_types::SyncRegion>> {
        let (pool, _permit) = db(ctx).await?;
        let head = places::feed_head(pool).await.map_err(|e| internal(&e))?;
        let packs = lunaway_db::packs::all(pool)
            .await
            .map_err(|e| internal(&e))?;
        let public_url = &state(ctx).config.tiles.public_url;
        Ok(lunaway_domain::region::SYNC_REGIONS
            .iter()
            .map(|r| crate::region_types::SyncRegion {
                code: r.code.to_owned(),
                country: r.country.to_owned(),
                name: r.name_en.to_owned(),
                name_fr: r.name_fr.to_owned(),
                pack: packs
                    .iter()
                    .find(|p| p.region == r.code)
                    .and_then(|p| crate::region_types::pack_of(p, &head, public_url)),
            })
            .collect())
    }

    /// The places of a viewport (500 per page at most), for the web or a
    /// device that has not synced yet. Without `near`, by id, the viewport
    /// 25 square degrees at most. With `near` (the map's centre, never the
    /// device's position), nearest first, any viewport; `near` is rounded by
    /// the server to 0.01 degree (about 1 km) before any use, and the cursor
    /// of a page continues the same order. `filter` keeps the same places
    /// as the map's filter on the places' tiles (`GET /places/tiles.json`).
    #[graphql(complexity = "cost(first, DEFAULT_PLACES_PAGE, child_complexity)")]
    async fn places(
        &self,
        ctx: &Context<'_>,
        bbox: BBoxInput,
        filter: Option<PlaceFilterInput>,
        #[graphql(default = 200)] first: Option<i32>,
        after: Option<String>,
        near: Option<LatLonInput>,
    ) -> Result<PlaceConnection> {
        // On the grid only; the error names no coordinate.
        let near = near
            .map(|p| Position::new(p.lat, p.lon).map(Position::on_list_grid))
            .transpose()
            .map_err(|_| invalid_input("near: not a valid position"))?;
        let max_area = if near.is_some() {
            f64::INFINITY
        } else {
            MAX_PLACES_AREA_DEG2
        };
        let area = self::bbox(bbox, max_area)?;
        let first = page(first.unwrap_or(DEFAULT_PLACES_PAGE), MAX_PLACES_PAGE)?;
        let filter = place_filter(filter.unwrap_or_default())?;
        let page = if let Some(near) = near {
            let after = parse_near_after(after.as_deref())?;
            let (pool, _permit) = db(ctx).await?;
            places::near_in_bbox(pool, area, &filter, near, first, after).await
        } else {
            let after = parse_after(after.as_deref())?;
            let (pool, _permit) = db(ctx).await?;
            places::in_bbox(pool, area, &filter, first, after).await
        }
        .map_err(|e| internal(&e))?;
        let end_cursor = match (page.end_near, page.nodes.last()) {
            (Some(n), _) => Some(near_cursor(n.distance_m, n.id)),
            (None, Some(p)) => Some(format!("{PLACES_CURSOR}{}", p.id)),
            (None, None) => None,
        };
        Ok(PlaceConnection {
            end_cursor,
            nodes: page.nodes.into_iter().map(Place).collect(),
            has_next_page: page.has_next_page,
            total_count: i32::try_from(page.total_count).unwrap_or(i32::MAX),
        })
    }

    /// One place. A place merged into another answers with the place that
    /// absorbed it (whose id differs); a deleted place answers null.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn place(&self, ctx: &Context<'_>, id: Uuid) -> Result<Option<Place>> {
        let (pool, _permit) = db(ctx).await?;
        Ok(places::by_id(pool, id)
            .await
            .map_err(|e| internal(&e))?
            .map(Place))
    }

    /// Searches names, address cities and municipalities, without accents:
    /// whole words first, then word prefixes, then typo-tolerant matches;
    /// among equal matches, the nearest to `near` first, `near` rounded by
    /// the server to the nearest 0.05 degree (about 5 km) before any use.
    #[graphql(complexity = "cost(first, DEFAULT_SEARCH_RESULTS, child_complexity)")]
    async fn search(
        &self,
        ctx: &Context<'_>,
        text: String,
        near: Option<LatLonInput>,
        #[graphql(default = 20)] first: Option<i32>,
    ) -> Result<Vec<Place>> {
        let first = page(first.unwrap_or(DEFAULT_SEARCH_RESULTS), MAX_SEARCH_RESULTS)?;
        let text = text.trim();
        if !SEARCH_TEXT_CHARS.contains(&text.chars().count()) {
            return Err(invalid_input("text must hold 2 to 100 characters"));
        }
        // On the grid only, as every point a search ranks from; the error
        // names no coordinate.
        let near = near
            .map(|p| Position::new(p.lat, p.lon).map(Position::coarsened))
            .transpose()
            .map_err(|_| invalid_input("near: not a valid position"))?;
        let (pool, _permit) = db(ctx).await?;
        let rows = search::search(pool, text, near, first)
            .await
            .map_err(|e| internal(&e))?;
        Ok(rows.into_iter().map(Place).collect())
    }

    /// The signed-in account, with its level and what the next one needs.
    /// `UNAUTHENTICATED` without a valid session.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn my_account(&self, ctx: &Context<'_>) -> Result<Account> {
        let viewer = auth::require(ctx).await?;
        Account::load(ctx, viewer).await
    }

    /// A route for a motorhome or a van, from `origin` to `destination`
    /// through `waypoints`, checked against every height, width, length,
    /// weight and access limit known on the way (OpenStreetMap, IGN): a
    /// route that meets a limit the vehicle exceeds is never returned. Up to
    /// 30 routes every ten minutes per client, recalculations included
    /// (`RATE_LIMITED` beyond); `UNAVAILABLE` while the routing engine or
    /// its data is down.
    #[graphql(complexity = "ROUTE_FIELD_COST + child_complexity")]
    async fn route(&self, ctx: &Context<'_>, input: RouteInput) -> Result<RouteResult> {
        crate::routing_query::route(ctx, input).await
    }

    /// Whether routing works now, the date of its data, the bounds of a
    /// route request and the typical vehicles to offer.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn routing(&self, ctx: &Context<'_>) -> Result<RoutingInfo> {
        crate::routing_query::routing_info(ctx).await
    }

    /// The road events of the countries the routing graph covers and a
    /// feed serves (France, the Netherlands, Spain: closures, works, lane
    /// restrictions, temporary vehicle limits, detours) in force or
    /// starting within the next 48 hours, changed since the cursor `since`
    /// (null for the whole set), of `classes` (closures and vehicle limits
    /// by default), with `blockingOnly` (the default) only those that can
    /// block a route (placed on the graph, official or confirmed, for every
    /// vehicle), at most `first` (1000 by default, 2000 at most); `hasMore`
    /// asks for the next page at once. An event starting later comes in the
    /// changes once it enters those 48 hours; one leaving the selection or
    /// postponed past them comes back in `removals`. `route` reads every
    /// event, whatever its start. No position is sent: a phone in guidance polls
    /// this every `pollIntervalSeconds` and checks its remaining route
    /// itself. A cursor of another copy of the database, or too old, gets
    /// the whole set again (`full`).
    #[graphql(complexity = "cost(first, crate::road_events_query::DEFAULT_PAGE, child_complexity)")]
    async fn road_events(
        &self,
        ctx: &Context<'_>,
        since: Option<String>,
        classes: Option<Vec<GqlRoadEventClass>>,
        #[graphql(default = true)] blocking_only: bool,
        #[graphql(default = 1000)] first: Option<i32>,
    ) -> Result<RoadEventDelta> {
        crate::road_events_query::road_events(
            ctx,
            since,
            classes,
            blocking_only,
            first.unwrap_or(crate::road_events_query::DEFAULT_PAGE),
        )
        .await
    }

    /// The speed cameras of the countries asked (`countries`, ISO codes;
    /// every country when null) changed since the cursor `since` (null for
    /// the whole set), each in the only form its country allows: danger
    /// zones (a stretch of road, never a camera's point) where positions
    /// may not be shown, cameras where they may, nothing where the country
    /// is off (Switzerland never has data). With the rules of every
    /// country, which the app applies by the country it is in, and the
    /// lists the items come from with their last read. At most `first`
    /// items (1000 by default, 2000 at most); `hasMore` asks for the next
    /// page at once. No position is sent. A cursor of another copy of the
    /// database, or issued for other countries, gets the whole set again
    /// (`full`).
    #[graphql(complexity = "cost(first, crate::enforcement_query::DEFAULT_PAGE, child_complexity)")]
    async fn enforcement(
        &self,
        ctx: &Context<'_>,
        since: Option<String>,
        countries: Option<Vec<String>>,
        #[graphql(default = 1000)] first: Option<i32>,
    ) -> Result<EnforcementDelta> {
        crate::enforcement_query::enforcement(
            ctx,
            since,
            countries,
            first.unwrap_or(crate::enforcement_query::DEFAULT_PAGE),
        )
        .await
    }

    /// The sources of road events, their licence and attribution, and how
    /// fresh their data is.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn road_event_sources(&self, ctx: &Context<'_>) -> Result<Vec<RoadEventSourceStatus>> {
        crate::road_events_query::road_event_sources(ctx).await
    }

    /// The families of points of interest and their kinds, in display
    /// order: the map's chips.
    async fn poi_categories(&self) -> Vec<PoiCategoryInfo> {
        poi_query::categories()
    }

    /// Fuel stations within `radiusKm` of `at` (10 by default, 50 at most)
    /// with a price of `fuel` updated in the last 90 days, at most `limit`
    /// (10 by default, 50 at most): those not out of it first, then the
    /// cheapest, then the nearest. `at` is rounded by the server to the
    /// nearest 0.05 degree (about 5 km) before any use, and `distanceM`
    /// is measured from that point.
    #[graphql(complexity = "crate::fuel_query::nearby_cost(limit, child_complexity)")]
    async fn fuel_nearby(
        &self,
        ctx: &Context<'_>,
        at: LatLonInput,
        fuel: crate::poi_types::GqlFuelKind,
        #[graphql(default = 10.0)] radius_km: f64,
        #[graphql(default = 10)] limit: i32,
    ) -> Result<Vec<crate::fuel_types::FuelStop>> {
        crate::fuel_query::nearby(ctx, at, fuel, radius_km, limit).await
    }

    /// Fuel stations along a route: those within half `maxDetourKm` of its
    /// line with a price of the fuel updated in the last 90 days, the best
    /// candidates' detours measured by the routing engine (from the route
    /// before the station, to the route after it), ranked by the price with
    /// the detour's fuel in it. One per request, like `route`, and counted
    /// in its own quota (`RATE_LIMITED` when spent). A detour the engine
    /// could not measure in time is estimated (`detour.measured` false).
    /// The server drops the line's ends before any use: the search runs
    /// along the line from where it first gets 2 km away from its first
    /// point to where it is last 2 km away from its last point (none when
    /// nothing is left), so neither end is read; a station within half
    /// `maxDetourKm` of what is left may still lie near an end. `alongKm`
    /// and `routeKm` still count from the line's first point.
    #[graphql(complexity = "crate::fuel_query::along_cost(input.limit, child_complexity)")]
    async fn fuel_along_route(
        &self,
        ctx: &Context<'_>,
        input: crate::fuel_types::FuelAlongRouteInput,
    ) -> Result<crate::fuel_types::FuelAlongRoute> {
        crate::fuel_query::along_route(ctx, input).await
    }

    /// One point of interest; null when it is gone or hidden.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn poi(&self, ctx: &Context<'_>, id: Uuid) -> Result<Option<Poi>> {
        poi_query::poi(ctx, id).await
    }

    /// "Around this place": for each category (all six when `categories`
    /// is absent), the nearest points to the place `placeId`, or to the
    /// point `at` (give one), nearest first, with their distance; open or
    /// closed alike (`openNow` says which). Within `radiusM` (20 km at
    /// most), or the category's default (`poiCategories`); `perCategory`
    /// points each (1 by default, 10 at most); `kinds` narrows them. `at`
    /// is rounded by the server to the nearest 0.05 degree (about 5 km)
    /// before any use, and the distances are measured from that point.
    #[graphql(
        complexity = "poi_query::nearby_cost(per_category, categories.as_ref(), child_complexity)"
    )]
    #[allow(
        clippy::too_many_arguments,
        reason = "each argument is an argument of the GraphQL field"
    )]
    async fn nearby_pois(
        &self,
        ctx: &Context<'_>,
        place_id: Option<Uuid>,
        at: Option<LatLonInput>,
        categories: Option<Vec<GqlPoiCategory>>,
        kinds: Option<Vec<GqlPoiKind>>,
        #[graphql(default = 1)] per_category: Option<i32>,
        radius_m: Option<f64>,
    ) -> Result<Vec<NearbyPois>> {
        poi_query::nearby(
            ctx,
            poi_query::NearbyArgs {
                place_id,
                at,
                categories,
                kinds,
                per_category,
                radius_m,
            },
        )
        .await
    }

    /// Searches the names and brands of the points of interest, without
    /// accents, typos tolerated; among equal matches the nearest to `near`
    /// first, `near` rounded by the server to the nearest 0.05 degree
    /// (about 5 km) before any use. `categories` narrows them.
    #[graphql(complexity = "cost(first, 20, child_complexity)")]
    async fn search_pois(
        &self,
        ctx: &Context<'_>,
        text: String,
        near: Option<LatLonInput>,
        categories: Option<Vec<GqlPoiCategory>>,
        #[graphql(default = 20)] first: Option<i32>,
    ) -> Result<Vec<Poi>> {
        poi_query::search(ctx, &text, near, categories, first.unwrap_or(20)).await
    }

    /// The points of interest of an area (4 square degrees at most, about a
    /// French département per square degree), by id, 1000 per page at
    /// most: what a device downloads to keep a region offline. The map
    /// itself reads the tiles (`poiLayer`).
    #[graphql(complexity = "cost(first, 500, child_complexity)")]
    async fn pois(
        &self,
        ctx: &Context<'_>,
        bbox: BBoxInput,
        categories: Option<Vec<GqlPoiCategory>>,
        #[graphql(default = 500)] first: Option<i32>,
        after: Option<String>,
    ) -> Result<PoiConnection> {
        poi_query::in_area(
            ctx,
            bbox,
            categories,
            first.unwrap_or(500),
            after.as_deref(),
        )
        .await
    }

    /// Where the map tiles of the points of interest are, and their
    /// version.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn poi_layer(&self, ctx: &Context<'_>) -> Result<PoiLayer> {
        poi_query::layer(ctx).await
    }

    /// The signed-in account's favourite lists, by name, with their places.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn my_favorite_lists(&self, ctx: &Context<'_>) -> Result<Vec<FavoriteList>> {
        let viewer = auth::require(ctx).await?;
        let (pool, _permit) = db(ctx).await?;
        Ok(lunaway_db::lists::lists(pool, viewer.id())
            .await
            .map_err(|e| internal(&e))?
            .into_iter()
            .map(Into::into)
            .collect())
    }
}

const SDL_HEADER: &str =
    "# Generated by `cargo run -p lunaway-api --bin export-schema` from backend/. Do not edit.\n\n";

/// The content of `schema/lunaway.graphql`: a header, then the schema as SDL.
#[must_use]
pub fn sdl_file() -> String {
    format!("{SDL_HEADER}{}", schema_builder().finish().sdl())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn code(e: &async_graphql::Error) -> String {
        e.extensions
            .as_ref()
            .and_then(|x| x.get("code"))
            .map(ToString::to_string)
            .unwrap_or_default()
    }

    #[test]
    fn a_cursor_names_the_copy_of_the_feed_that_issued_it() {
        let head = places::FeedHead {
            epoch: Uuid::now_v7(),
            database: 16_384,
            last_seq: 100,
        };
        let against =
            |s: &str, h: &places::FeedHead| parse_since(Some(s)).and_then(|p| since_seq(&p, h));
        let cursor = changes_cursor(&head, 42);
        assert_eq!(against(&cursor, &head).unwrap(), 42);
        assert_eq!(since_seq(&parse_since(None).unwrap(), &head).unwrap(), 0);
        let restored = places::FeedHead {
            epoch: Uuid::now_v7(),
            ..head
        };
        assert_eq!(
            code(&against(&cursor, &restored).unwrap_err()),
            "\"RESYNC\"",
            "a cursor from before a restore must not skip the changes made since the dump"
        );
        let other_database = places::FeedHead {
            database: 16_385,
            ..head
        };
        assert_eq!(
            code(&against(&cursor, &other_database).unwrap_err()),
            "\"RESYNC\"",
            "a restore into a new database changes the identity without any step"
        );
        assert_eq!(
            code(&against(&changes_cursor(&head, 101), &head).unwrap_err()),
            "\"RESYNC\"",
            "a cursor past the end of the feed was issued by another copy"
        );
        assert_eq!(code(&against("c1.42", &head).unwrap_err()), "\"RESYNC\"");
        for forged in [
            "c2.42",
            "c2.zz.42",
            &format!("c2.{}.-1", head.identity()),
            "c1.-4",
            "p1.x",
            "",
        ] {
            assert_eq!(
                code(&parse_since(Some(forged)).unwrap_err()),
                "\"INVALID_INPUT\"",
                "{forged}"
            );
        }
    }
}
