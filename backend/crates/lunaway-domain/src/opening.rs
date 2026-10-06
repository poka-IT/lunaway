//! Opening hours as intervals, for clients that cannot evaluate the OSM
//! `opening_hours` syntax themselves.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// How many days of intervals a place carries, from local midnight of the
/// day they were computed: two weeks of answers for a device that stays
/// offline.
pub const OPENING_WINDOW_DAYS: i64 = 14;

/// A span of time during which a place is open, in UTC, end excluded.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct OpeningInterval {
    /// Opening time.
    pub start: DateTime<Utc>,
    /// Closing time.
    pub end: DateTime<Utc>,
}
