//! The integration tests of the importers: real fixtures, a local HTTP server, a real database.
//!
//! One binary for the crate: each file of `tests/` is a module declared
//! here (`autotests = false` in Cargo.toml), so a new file needs its line.

mod cameras;
mod content_fixtures;
mod content_worker;
mod enforcement_build;
mod fixtures_parse;
mod fuel_history;
mod http_fetch;
mod osm_extract;
mod poi_joins;
mod poi_osm;
mod road_events_parse;
mod road_events_poll;
mod store;
