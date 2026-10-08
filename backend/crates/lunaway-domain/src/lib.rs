//! Lunaway domain types and rules.
//!
//! Pure data and rules, no I/O: the database, the API and the ingestion
//! adapters depend on this crate, never the other way round.

pub mod address;
pub mod community;
pub mod conflation;
pub mod content;
pub mod enforcement;
pub mod extcom;
pub mod fuel;
pub mod geo;
pub mod listing;
pub mod opening;
pub mod poi;
pub mod record;
pub mod region;
pub mod road_events;
pub mod routing;
pub mod search;
pub mod source;
pub mod speed;
pub mod takedown;
pub mod taxonomy;

pub use geo::{BBox, InvalidBBox, InvalidPosition, Position, TrimmedLine, trim_ends};
pub use opening::{OPENING_WINDOW_DAYS, OpeningInterval};
pub use record::{Address, NormalizedRecord, UNDETERMINED_LANGUAGE, is_language_tag};
pub use source::{InvalidSourceId, SourceId};
pub use taxonomy::{Activity, OvernightStatus, PlaceKind, PriceInclusion, Service, UnknownCode};
