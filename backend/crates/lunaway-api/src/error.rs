//! Errors as the client sees them: a code it can act on in
//! `extensions.code`, and nothing of the server's internals.
//!
//! | code | the client |
//! |---|---|
//! | `INVALID_INPUT` | fixes the request: a page too large, a box too wide, a malformed cursor, a document too large or too complex |
//! | `RATE_LIMITED` | waits `extensions.retryAfterSeconds` (also the `Retry-After` header) and tries again |
//! | `RESYNC` | drops its cursor and syncs again from scratch (`since: null`) |
//! | `INTERNAL` | tries again later; the server logged the cause |

use std::time::Duration;

use async_graphql::{Error, ErrorExtensions, ServerError};

/// The request is malformed or asks too much.
pub(crate) const INVALID_INPUT: &str = "INVALID_INPUT";
/// The client spent its budget, or the server is saturated.
pub(crate) const RATE_LIMITED: &str = "RATE_LIMITED";
/// The cursor belongs to another copy of the change feed.
pub(crate) const RESYNC: &str = "RESYNC";
/// The server failed.
pub(crate) const INTERNAL: &str = "INTERNAL";

/// The client sent something the API refuses: a page too large, a box too
/// wide, a malformed cursor.
pub(crate) fn invalid_input(message: impl Into<String>) -> Error {
    Error::new(message.into()).extend_with(|_, e| e.set("code", INVALID_INPUT))
}

/// The cursor was issued by another copy of the database (a restore): the
/// client must sync again from scratch.
pub(crate) fn resync() -> Error {
    Error::new("since comes from another copy of the change feed; sync again with since: null")
        .extend_with(|_, e| e.set("code", RESYNC))
}

/// Whole seconds to tell a client to wait, at least one.
pub(crate) fn retry_after_seconds(wait: Duration) -> u64 {
    wait.as_secs() + u64::from(wait.subsec_nanos() > 0)
}

/// The client must wait `wait` before asking again.
pub(crate) fn rate_limited(message: &str, wait: Duration) -> ServerError {
    let mut e = ServerError::new(message, None);
    let mut ext = async_graphql::ErrorExtensionValues::default();
    ext.set("code", RATE_LIMITED);
    ext.set("retryAfterSeconds", retry_after_seconds(wait));
    e.extensions = Some(ext);
    e
}

/// A failure of the server: logged with its cause, returned as a generic
/// message so no query text or table name leaks to the client.
pub(crate) fn internal(error: &(dyn std::error::Error + 'static)) -> Error {
    let mut chain = Vec::new();
    let mut cause: Option<&(dyn std::error::Error + 'static)> = Some(error);
    while let Some(c) = cause {
        chain.push(c.to_string());
        cause = c.source();
    }
    tracing::error!(error = %chain.join(": "), "request failed");
    Error::new("internal error").extend_with(|_, e| e.set("code", INTERNAL))
}
