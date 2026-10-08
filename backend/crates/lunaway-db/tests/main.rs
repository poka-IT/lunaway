//! The integration tests of the database layer, each over a fresh database.
//!
//! One binary for the crate: each file of `tests/` is a module declared
//! here (`autotests = false` in Cargo.toml), so a new file needs its line.

mod content;
mod fuel;
mod idempotency;
mod locks_and_roles;
mod migrations_on_data;
mod place_ratings;
mod place_tiles;
mod places;
mod pois;
mod regions;
mod retention;
mod road_events;
mod routing;
mod schema_and_records;
mod towns;
mod worker_signal;
