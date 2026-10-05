//! Lunaway domain types.
//!
//! Pure data and rules, no I/O: the database, the API and the ingestion
//! adapters depend on this crate, never the other way round.

pub mod taxonomy;

pub use taxonomy::{Activity, OvernightStatus, PlaceKind, Service, UnknownCode};
