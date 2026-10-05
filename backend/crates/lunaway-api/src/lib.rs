//! The Lunaway HTTP and GraphQL API.
//!
//! The router is assembled here so the server binary, the schema exporter and
//! the tests all serve the same thing.

pub mod schema;

use async_graphql_axum::GraphQL;
use axum::{Router, routing::get};
use tower_http::trace::TraceLayer;

pub use schema::{LunawaySchema, build_schema};

/// The HTTP router: `/health` for probes, `/graphql` for the API.
pub fn router(schema: LunawaySchema) -> Router {
    Router::new()
        .route("/health", get(health))
        .route_service("/graphql", GraphQL::new(schema))
        .layer(TraceLayer::new_for_http())
}

async fn health() -> &'static str {
    "ok"
}
