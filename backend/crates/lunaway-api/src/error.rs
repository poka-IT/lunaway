//! Errors as the client sees them: a code it can act on in
//! `extensions.code`, and nothing of the server's internals.
//!
//! | code | the client |
//! |---|---|
//! | `INVALID_INPUT` | fixes the request: a page too large, a box too wide, a malformed cursor, a document too large or too complex |
//! | `RATE_LIMITED` | waits `extensions.retryAfterSeconds` (also the `Retry-After` header) and tries again |
//! | `RESYNC` | drops its cursor and syncs again from scratch (`since: null`) |
//! | `UNAUTHENTICATED` | signs in again (`authChallenge`, `signIn`): no session, or an expired or unknown one, on a field that needs an account; with `extensions.reason` `FRESH_SIGN_IN`, the action needs a session opened in the last ten minutes, so the device signs in again and retries |
//! | `FORBIDDEN` | does not offer the action: the account's level is below `extensions.requiredLevel` (its level is `extensions.level`), or the account is banned |
//! | `NOT_FOUND` | drops what it held: the place, list, review, photo or submission does not exist, or is not the caller's |
//! | `UNAVAILABLE` | tries again later: a service behind the API (the routing engine, or its data) is down or not installed; the request itself was fine |
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
/// No valid session on a field that needs one.
pub(crate) const UNAUTHENTICATED: &str = "UNAUTHENTICATED";
/// The account may not do this.
pub(crate) const FORBIDDEN: &str = "FORBIDDEN";
/// The target does not exist, or is not the caller's.
pub(crate) const NOT_FOUND: &str = "NOT_FOUND";
/// A service behind the API is down.
pub(crate) const UNAVAILABLE: &str = "UNAVAILABLE";

/// A service behind the API (the routing engine, its data) does not answer:
/// the client tries again later.
pub(crate) fn unavailable(what: &str) -> Error {
    Error::new(format!(
        "{what} is not available right now; try again later"
    ))
    .extend_with(|_, e| e.set("code", UNAVAILABLE))
}

/// No session, or one the server does not know.
pub(crate) fn unauthenticated() -> Error {
    Error::new("sign in first: this needs a valid session")
        .extend_with(|_, e| e.set("code", UNAUTHENTICATED))
}

/// The action needs a session opened by a recent signed sign-in.
pub(crate) fn fresh_sign_in() -> Error {
    Error::new("this action needs a recent sign-in: sign in again with the device key, then retry")
        .extend_with(|_, e| {
            e.set("code", UNAUTHENTICATED);
            e.set("reason", "FRESH_SIGN_IN");
        })
}

/// The account's level is below what the action needs.
pub(crate) fn level_too_low(required: u8, level: u8) -> Error {
    Error::new(format!(
        "this needs trust level {required}; the account is at level {level}"
    ))
    .extend_with(move |_, e| {
        e.set("code", FORBIDDEN);
        e.set("requiredLevel", i32::from(required));
        e.set("level", i32::from(level));
    })
}

/// The account may not do this (banned, or another rule).
pub(crate) fn forbidden(message: impl Into<String>) -> Error {
    Error::new(message.into()).extend_with(|_, e| e.set("code", FORBIDDEN))
}

/// The target does not exist or belongs to someone else.
pub(crate) fn not_found(what: &str) -> Error {
    Error::new(format!("no such {what}")).extend_with(|_, e| e.set("code", NOT_FOUND))
}

/// A per-account or per-client quota is spent: the same shape as the cost
/// budget's refusal, so the client waits `retryAfterSeconds`.
pub(crate) fn quota_spent(what: &str, wait: Duration) -> Error {
    let seconds = retry_after_seconds(wait);
    Error::new(format!("too many {what}; wait and try again")).extend_with(move |_, e| {
        e.set("code", RATE_LIMITED);
        e.set("retryAfterSeconds", seconds);
    })
}

/// The server cannot take the request now (every routing call is taken):
/// the same shape as a spent quota, so the client waits `retryAfterSeconds`.
pub(crate) fn rate_limited_error(message: &str, wait: Duration) -> Error {
    let seconds = retry_after_seconds(wait);
    Error::new(message.to_owned()).extend_with(move |_, e| {
        e.set("code", RATE_LIMITED);
        e.set("retryAfterSeconds", seconds);
    })
}

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
