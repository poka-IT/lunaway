//! The integration tests of the database layer, each over a fresh database.
//!
//! One binary for the crate: each file of `tests/` is a module declared
//! here (`autotests = false` in Cargo.toml), so a new file needs its line.

mod along;
mod content;
mod content_pois;
mod fuel;
mod idempotency;
mod locks_and_roles;
mod migrations_on_data;
mod place_addresses;
mod place_ratings;
mod place_tiles;
mod places;
mod poi_search;
mod pois;
mod regions;
mod retention;
mod road_events;
mod routing;
mod schema_and_records;
mod season;
mod towns;
mod translations;
mod worker_signal;
