//! Lunaway domain types and rules.
//!
//! Pure data and rules, no I/O: the database, the API and the ingestion
//! adapters depend on this crate, never the other way round.

pub mod community;
pub mod conflation;
pub mod enforcement;
pub mod fuel;
pub mod geo;
pub mod opening;
pub mod poi;
pub mod record;
pub mod region;
pub mod road_events;
pub mod routing;
pub mod source;
pub mod speed;
pub mod taxonomy;

pub use geo::{BBox, InvalidBBox, InvalidPosition, Position};
pub use opening::{OPENING_WINDOW_DAYS, OpeningInterval};
pub use record::{Address, NormalizedRecord, UNDETERMINED_LANGUAGE, is_language_tag};
pub use source::{InvalidSourceId, SourceId};
pub use taxonomy::{Activity, OvernightStatus, PlaceKind, Service, UnknownCode};
