//! The integration tests of the API: GraphQL and HTTP over a real database.
//!
//! One binary for the crate: each file of `tests/` is a module declared
//! here (`autotests = false` in Cargo.toml), so a new file needs its line.

mod budget;
mod community;
mod enforcement;
mod fuel;
mod http;
mod poi;
mod regions;
mod road_events;
mod route;
mod schema_drift;
