//! The integration tests of the API: GraphQL and HTTP over a real database.
//!
//! One binary for the crate: each file of `tests/` is a module declared
//! here (`autotests = false` in Cargo.toml), so a new file needs its line.

mod budget;
mod community;
mod enforcement;
mod extcom;
mod fuel;
mod http;
mod mvt;
mod place_tiles;
mod poi;
mod regions;
mod road_events;
mod route;
mod route_reasons;
// Every test of it is ignored; infra/routing/e2e.sh runs them on the build
// server with `-E 'test(/^route_e2e::/)' --run-ignored only`.
mod route_e2e;
mod schema_drift;
