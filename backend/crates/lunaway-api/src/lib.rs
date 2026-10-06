//! The Lunaway HTTP and GraphQL API.
//!
//! The router is assembled here so the server binary, the schema exporter and
//! the tests all serve the same thing. The API is public and anonymous: its
//! bounds are in [`config::Limits`] (per deployment) and in [`schema`] and
//! [`guard`] (the shape of a document).

mod client;
pub mod config;
mod error;
pub mod guard;
mod http;
mod loaders;
mod rate;
pub mod schema;
pub mod types;

use std::{sync::Arc, time::Duration};

use axum::{
    Router,
    http::{Method, Request, header},
    routing::{get, post},
};
use tower_http::{
    compression::CompressionLayer,
    cors::{AllowOrigin, CorsLayer},
    trace::TraceLayer,
};

pub use config::{ApiConfig, Limits};
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
        .allow_methods([Method::POST, Method::OPTIONS])
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
        path = %request.uri().path()
    )
}

/// The HTTP router: `/health` for probes, `POST /graphql` for the API.
/// Responses are gzip-compressed when the client accepts it: a sync page of
/// 1000 places shrinks about thirteen times.
pub fn router(state: ApiState) -> Router {
    let limits = state.config.limits;
    let dev_cors = state.config.dev_cors;
    let rate = Arc::clone(&state.rate);
    let endpoint = Arc::new(http::Endpoint::new(build_schema(state), limits, rate));
    let graphql = post(http::graphql).with_state(endpoint);
    Router::new()
        .route("/health", get(health))
        .route("/graphql", graphql)
        .layer(CompressionLayer::new())
        .layer(cors(dev_cors))
        .layer(TraceLayer::new_for_http().make_span_with(request_span))
}

async fn health() -> &'static str {
    "ok"
}
