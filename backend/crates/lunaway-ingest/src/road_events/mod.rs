//! Road events: closures, works, lane restrictions, temporary vehicle
//! limits and detours from the open feeds of `docs/data-sources.md` ("Road
//! events"), read by the server only, paced, cached, resumed from each
//! feed's stored cursor, and matched to the routing graph
//! (`plan/research/21-backend-travaux.md`).
//!
//! - [`dir`]: the DIR's DATEX II 2.x feed of the national roads;
//! - [`dialog`]: DiaLog's traffic orders (DATEX II 3);
//! - [`local`]: the city and département datasets;
//! - [`fetch`]: the HTTP side, HTTPS only, on each feed's hosts;
//! - [`matching`]: lines placed on the graph by the routing engine;
//! - [`poll`]: one pass of the poller (`lunaway road-events poll`).

pub mod dialog;
pub mod dir;
pub mod fetch;
pub mod local;
pub mod matching;
pub mod poll;
pub mod xml;

use chrono::{DateTime, Duration, Utc};

/// Largest raw record kept with an event: the column's bound.
const RAW_MAX_CHARS: usize = 65_536;

/// Why a feed's payload could not be read.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum ParseError {
    /// The XML does not read.
    #[error(transparent)]
    Xml(#[from] xml::XmlError),
    /// The JSON does not read.
    #[error("the payload is not the expected JSON")]
    Json(#[from] serde_json::Error),
    /// It reads but is not the expected document.
    #[error("unexpected payload: {0}")]
    Shape(&'static str),
}

/// A DATEX II or ISO 8601 date-time with its offset, in UTC.
#[must_use]
pub fn instant(text: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(text.trim())
        .ok()
        .map(|d| d.with_timezone(&Utc))
}

/// A version number padded to ten digits, so that text order is number
/// order; anything else as it is.
#[must_use]
pub fn padded_version(v: &str) -> String {
    match v.trim().parse::<u64>() {
        Ok(n) => format!("{n:010}"),
        Err(_) => v.trim().chars().take(100).collect(),
    }
}

/// Whether an end lies more than an hour in the past: the DIR aggregate
/// still published 41 records ended up to 347 days before (2026-10-06).
#[must_use]
pub fn past_end(valid_to: Option<DateTime<Utc>>, now: DateTime<Utc>) -> bool {
    valid_to.is_some_and(|end| end < now - Duration::hours(1))
}

/// A raw record cut to what its column holds, on a character boundary.
#[must_use]
pub fn cap_raw(raw: String) -> String {
    if raw.chars().count() <= RAW_MAX_CHARS {
        raw
    } else {
        raw.chars().take(RAW_MAX_CHARS).collect()
    }
}

/// A digest of parts, for a source that gives no version.
#[must_use]
pub fn digest(parts: &[&str]) -> String {
    use sha2::{Digest as _, Sha256};
    let mut h = Sha256::new();
    for p in parts {
        h.update(p.as_bytes());
        h.update([0]);
    }
    h.finalize()
        .iter()
        .take(12)
        .map(|b| format!("{b:02x}"))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions_sort_as_numbers() {
        assert!(padded_version("10") > padded_version("9"));
        assert_eq!(padded_version("7"), "0000000007");
        assert_eq!(padded_version("v2"), "v2");
    }

    #[test]
    fn dates_read_with_their_offset() {
        assert_eq!(
            instant("2026-10-06T12:57:45.691+02:00").map(|d| d.to_rfc3339()),
            Some("2026-10-06T10:57:45.691+00:00".to_owned())
        );
        assert_eq!(instant("hier"), None);
    }

    #[test]
    fn a_raw_record_is_capped_on_a_character_boundary() {
        let long = "é".repeat(RAW_MAX_CHARS + 10);
        assert_eq!(cap_raw(long).chars().count(), RAW_MAX_CHARS);
    }
}
