//! The Lunaway HTTP and GraphQL API.
//!
//! The router is assembled here so the server binary, the schema exporter and
//! the tests all serve the same thing. The API is public and anonymous: its
//! bounds are in [`config::Limits`] (per deployment) and in [`schema`] and
//! [`guard`] (the shape of a document).

mod address_query;
pub mod address_types;
mod auth;
mod client;
pub mod community_types;
pub mod config;
pub mod digest_query;
mod enforcement_query;
pub mod enforcement_types;
mod error;
pub mod external_photos;
pub mod external_types;
mod fuel_query;
pub mod fuel_types;
mod geocode;
pub mod guard;
mod http;
mod loaders;
pub mod mutation;
pub mod packs;
pub mod persisted;
mod poi_query;
pub mod poi_types;
mod quota;
mod rate;
pub mod region_types;
pub mod road_event_types;
mod road_events_query;
mod routing;
mod routing_query;
pub mod routing_types;
pub mod schema;
pub mod tiles;
pub mod types;
mod upload;

use std::{sync::Arc, time::Duration};

use axum::{
    Router,
    extract::DefaultBodyLimit,
    http::{Method, Request, header},
    routing::{get, post},
};
use tower_http::{
    compression::CompressionLayer,
    cors::{AllowOrigin, CorsLayer},
    trace::TraceLayer,
};

pub use config::{ApiConfig, Limits};
pub use routing::public::Refreshed;
pub use schema::{ApiState, LunawaySchema, build_schema};

/// The site that serves the web app.
const SITE_ORIGIN: &str = "https://lunaway.net";

/// Whether a browser page from `origin` may call the API: the web app's
/// site, and with `dev` a page served from this machine on any port.
#[must_use]
pub fn origin_allowed(origin: &str, dev: bool) -> bool {
    if origin == SITE_ORIGIN {
        return true;
    }
    dev && ["http://localhost", "http://127.0.0.1"].iter().any(|host| {
        match origin.strip_prefix(host) {
            Some("") => true,
            Some(rest) => rest.strip_prefix(':').is_some_and(|port| {
                (1..=5).contains(&port.len()) && port.bytes().all(|b| b.is_ascii_digit())
            }),
            None => false,
        }
    })
}

fn cors(dev: bool) -> CorsLayer {
    CorsLayer::new()
        .allow_origin(AllowOrigin::predicate(move |origin, _| {
            origin.to_str().is_ok_and(|o| origin_allowed(o, dev))
        }))
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_headers([header::CONTENT_TYPE, header::AUTHORIZATION])
        .expose_headers([header::RETRY_AFTER])
        .max_age(Duration::from_secs(86_400))
}

/// The span of a request: its method and path. Never the query string, nor
/// any header: a position or an address in a URL is personal data.
fn request_span<B>(request: &Request<B>) -> tracing::Span {
    tracing::info_span!(
        "request",
        method = %request.method(),
        path = %tiles::loggable_path(request.uri().path())
    )
}

/// The HTTP router: `/health` for probes, `POST /graphql` for the API,
/// `POST /upload` for photos, `GET /poi/...` and `GET /places/...` for the
/// map tiles of the points of interest and of the places,
/// `GET /external-photos/...` for the photo proxy of the external community
/// source. Responses are gzip-compressed when the client accepts it: a sync
/// page of 1000 places shrinks about thirteen times.
pub fn router(state: ApiState) -> Router {
    let limits = state.config.limits;
    let dev_cors = state.config.dev_cors;
    let rate = Arc::clone(&state.rate);
    let external_photos = Arc::new(external_photos::ExternalPhotoEndpoint::new(
        state.pool.clone(),
        Arc::clone(&state.rate),
        Arc::clone(&state.quotas),
        Arc::clone(&state.media),
        state.config.media.clone(),
        Arc::clone(&state.media_workers),
        state.config.external_photos,
        state.external_photos.clone(),
    ));
    let upload = Arc::new(upload::UploadEndpoint {
        pool: state.pool.clone(),
        config: Arc::new(state.config.clone()),
        rate: Arc::clone(&state.rate),
        quotas: Arc::clone(&state.quotas),
        media: Arc::clone(&state.media),
        workers: Arc::clone(&state.media_workers),
        slots: tokio::sync::Semaphore::new(upload::UPLOADS_AT_ONCE),
    });
    let max_upload = upload.max_body();
    let builders = Arc::new(tokio::sync::Semaphore::new(state.config.tiles.concurrency));
    let tiles = Arc::new(tiles::TileEndpoint::new(
        tiles::Layer::Points,
        state.pool.clone(),
        state.config.tiles.clone(),
        Arc::clone(&rate),
        Arc::clone(&builders),
    ));
    let place_tiles = Arc::new(tiles::TileEndpoint::new(
        tiles::Layer::Places,
        state.pool.clone(),
        state.config.tiles.clone(),
        Arc::clone(&rate),
        builders,
    ));
    let endpoint = Arc::new(http::Endpoint::new(build_schema(state), limits, rate));
    let graphql = post(http::graphql).with_state(endpoint);
    let upload = post(upload::upload)
        .with_state(upload)
        .layer(DefaultBodyLimit::max(max_upload));
    Router::new()
        .route("/health", get(health))
        .route("/graphql", graphql)
        .route("/upload", upload)
        .route(
            tiles::TILE_JSON_PATH,
            get(tiles::tile_json).with_state(Arc::clone(&tiles)),
        )
        .route(
            "/poi/{version}/{z}/{x}/{y}",
            get(tiles::tile).with_state(tiles),
        )
        .route(
            tiles::PLACES_TILE_JSON_PATH,
            get(tiles::tile_json).with_state(Arc::clone(&place_tiles)),
        )
        .route(
            "/places/{version}/{z}/{x}/{y}",
            get(tiles::tile).with_state(place_tiles),
        )
        .route(
            "/external-photos/{id}/{size}",
            get(external_photos::photo).with_state(external_photos),
        )
        .layer(CompressionLayer::new())
        .layer(cors(dev_cors))
        .layer(TraceLayer::new_for_http().make_span_with(request_span))
}

async fn health() -> &'static str {
    "ok"
}
