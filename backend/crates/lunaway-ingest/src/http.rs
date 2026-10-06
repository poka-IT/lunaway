//! The HTTP client every adapter uses: an honest User-Agent, bounded
//! timeouts, HTTPS only, bounded answers, and retries with exponential
//! backoff on transient failures only, never sooner than the server's
//! `Retry-After`.

use std::{future::Future, sync::Once, time::Duration};

use backon::{ExponentialBuilder, Retryable};
use chrono::{DateTime, Utc};
use reqwest::{StatusCode, header::RETRY_AFTER};

use crate::IngestError;

/// `Lunaway/<version> (+https://lunaway.net)`: who is asking and where to
/// find out more, as the Overpass and data.gouv.fr usage policies ask.
#[must_use]
pub fn user_agent() -> String {
    format!(
        "Lunaway/{} (+https://lunaway.net)",
        env!("CARGO_PKG_VERSION")
    )
}

/// Redirects followed at most: the sources answer directly or through one
/// redirect to a dated file.
const MAX_REDIRECTS: usize = 5;

/// Hosts a redirect may lead to, besides the host first asked: where the
/// sources of `docs/data-sources.md` publish. A link in a source's metadata
/// can point anywhere; a redirect from it reaches no other server.
pub const REDIRECT_HOSTS: &[&str] = &[
    "download.geofabrik.de",
    "download.openstreetmap.fr",
    "overpass-api.de",
    "www.data.gouv.fr",
    "static.data.gouv.fr",
    "object.files.data.gouv.fr",
    "data.classement.atout-france.fr",
    "data.geopf.fr",
];

/// Follows a redirect to the host first asked or to [`REDIRECT_HOSTS`], at
/// most [`MAX_REDIRECTS`] times; any other redirect is returned as the
/// answer, which the caller refuses as a non-success status.
fn redirect_policy() -> reqwest::redirect::Policy {
    reqwest::redirect::Policy::custom(|attempt| {
        if attempt.previous().len() > MAX_REDIRECTS {
            return attempt.error("too many redirects");
        }
        let first = attempt.previous().first().and_then(|u| u.host_str());
        let allowed = attempt.url().host_str().is_some_and(|next| {
            first.is_some_and(|f| f.eq_ignore_ascii_case(next))
                || REDIRECT_HOSTS.iter().any(|h| h.eq_ignore_ascii_case(next))
        });
        if allowed {
            attempt.follow()
        } else {
            attempt.stop()
        }
    })
}

/// Builds the shared client. It speaks HTTPS only, redirects included, so
/// a source or a link in its metadata cannot downgrade a request to plain
/// HTTP, and follows redirects only to the sources' hosts
/// ([`REDIRECT_HOSTS`]) or within the host first asked.
///
/// # Errors
///
/// [`IngestError::Client`] when the TLS stack cannot be initialised.
pub fn client() -> Result<reqwest::Client, IngestError> {
    build(true)
}

/// A client that also accepts plain HTTP, for tests against a local server.
/// Imports use [`client`].
///
/// # Errors
///
/// [`IngestError::Client`] when the TLS stack cannot be initialised.
pub fn client_allowing_plain_http() -> Result<reqwest::Client, IngestError> {
    build(false)
}

fn build(https_only: bool) -> Result<reqwest::Client, IngestError> {
    install_crypto_provider();
    reqwest::Client::builder()
        .user_agent(user_agent())
        .https_only(https_only)
        .redirect(redirect_policy())
        .connect_timeout(Duration::from_secs(30))
        // An Overpass query over a whole region takes minutes on a busy
        // server; the server-side timeout of the query is below this.
        .timeout(Duration::from_secs(1_200))
        .build()
        .map_err(IngestError::Client)
}

/// reqwest is built without a bundled crypto provider (see the workspace
/// manifest); ring is installed once per process.
fn install_crypto_provider() {
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        // An error means another provider is already installed, which is
        // just as good for this process.
        let _ = rustls::crypto::ring::default_provider().install_default();
    });
}

/// How hard to retry a transient failure.
#[derive(Debug, Clone, Copy)]
pub struct RetryPolicy {
    /// First delay.
    pub min_delay: Duration,
    /// Longest delay between two attempts.
    pub max_delay: Duration,
    /// Retries after the first attempt.
    pub max_retries: usize,
}

impl RetryPolicy {
    /// For public services under load: Overpass sheds load with 429 and 504
    /// for minutes at a time, so the waits grow to five minutes.
    pub const PATIENT: Self = Self {
        min_delay: Duration::from_secs(15),
        max_delay: Duration::from_secs(300),
        max_retries: 6,
    };
}

/// Longest wait a `Retry-After` may ask for. A source that wants us away
/// for longer is not waited for: the import stops and reports, and the next
/// scheduled run tries again.
pub const MAX_RETRY_AFTER: Duration = Duration::from_secs(3_600);

/// The delay before the next attempt: the backoff's, or the server's
/// `Retry-After` when it asks for longer; `None` (stop) when the backoff is
/// spent or the server asks for more than [`MAX_RETRY_AFTER`].
fn next_delay(error: &IngestError, backoff: Option<Duration>) -> Option<Duration> {
    let backoff = backoff?;
    match error {
        IngestError::Status {
            retry_after: Some(asked),
            ..
        } => {
            if *asked > MAX_RETRY_AFTER {
                tracing::warn!(
                    ?asked,
                    "the server asks to wait longer than an hour; stopping"
                );
                None
            } else {
                Some(backoff.max(*asked))
            }
        }
        _ => Some(backoff),
    }
}

/// Runs `attempt` until it succeeds, fails permanently, or the retries of
/// `policy` are spent. Each wait is the backoff's, or longer when the server
/// says so in `Retry-After`. `what` names the operation in the logs.
///
/// # Errors
///
/// The last error of `attempt`.
pub async fn with_retry<T, F, Fut>(
    what: &str,
    policy: RetryPolicy,
    attempt: F,
) -> Result<T, IngestError>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T, IngestError>>,
{
    let backoff = ExponentialBuilder::default()
        .with_min_delay(policy.min_delay)
        .with_max_delay(policy.max_delay)
        .with_max_times(policy.max_retries)
        .with_jitter();
    attempt
        .retry(backoff)
        .sleep(tokio::time::sleep)
        .when(IngestError::is_transient)
        .adjust(next_delay)
        .notify(|error, delay| {
            tracing::warn!(what, %error, ?delay, "transient failure, retrying");
        })
        .await
}

/// Whether an HTTP status is worth a retry: rate limiting and the gateway
/// errors a loaded server answers with. `501 Not Implemented` and the other
/// server errors describe the request or the server's setup, which a second
/// try does not change.
#[must_use]
pub fn is_transient_status(status: StatusCode) -> bool {
    matches!(
        status,
        StatusCode::TOO_MANY_REQUESTS
            | StatusCode::REQUEST_TIMEOUT
            | StatusCode::INTERNAL_SERVER_ERROR
            | StatusCode::BAD_GATEWAY
            | StatusCode::SERVICE_UNAVAILABLE
            | StatusCode::GATEWAY_TIMEOUT
    )
}

/// A `Retry-After` value: delay-seconds, or an HTTP-date measured from
/// `now` (a date already past is no wait).
#[must_use]
pub fn parse_retry_after(value: &str, now: DateTime<Utc>) -> Option<Duration> {
    let value = value.trim();
    if let Ok(seconds) = value.parse::<u64>() {
        return Some(Duration::from_secs(seconds));
    }
    let at = DateTime::parse_from_rfc2822(value)
        .ok()?
        .with_timezone(&Utc);
    Some((at - now).to_std().unwrap_or(Duration::ZERO))
}

/// Most of an error body kept for the message.
const ERROR_BODY_BYTES: usize = 64 * 1024;

/// Turns a non-success status into an error carrying what the body says,
/// which is where Overpass and the BAN explain themselves, and when the
/// server asks to come back.
pub(crate) async fn check_status(
    url: &str,
    response: reqwest::Response,
) -> Result<reqwest::Response, IngestError> {
    let status = response.status();
    if status.is_success() {
        return Ok(response);
    }
    let retry_after = response
        .headers()
        .get(RETRY_AFTER)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| parse_retry_after(v, Utc::now()));
    let body = read_prefix(response, ERROR_BODY_BYTES).await;
    Err(IngestError::Status {
        url: url.to_owned(),
        status,
        body: readable(&String::from_utf8_lossy(&body)),
        retry_after,
    })
}

/// The first `limit` bytes of an error body, whatever happens to the rest.
async fn read_prefix(mut response: reqwest::Response, limit: usize) -> Vec<u8> {
    let mut body = Vec::new();
    while body.len() < limit {
        let Ok(Some(chunk)) = response.chunk().await else {
            break;
        };
        let room = limit - body.len();
        body.extend_from_slice(&chunk[..chunk.len().min(room)]);
    }
    body
}

/// The body of `response`, refused once it passes `limit` bytes: a source
/// that sends more than any real answer is broken or hostile, and holding
/// it in memory would take the importer down.
///
/// # Errors
///
/// [`IngestError::TooLarge`] past `limit`, and [`IngestError::Http`] when
/// the transfer fails.
pub(crate) async fn read_capped(
    url: &str,
    mut response: reqwest::Response,
    limit: usize,
) -> Result<Vec<u8>, IngestError> {
    let too_large = || IngestError::TooLarge {
        url: url.to_owned(),
        limit,
    };
    if response
        .content_length()
        .is_some_and(|n| n > u64::try_from(limit).unwrap_or(u64::MAX))
    {
        return Err(too_large());
    }
    let mut body = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|source| IngestError::Http {
        url: url.to_owned(),
        source,
    })? {
        if body.len() + chunk.len() > limit {
            return Err(too_large());
        }
        body.extend_from_slice(&chunk);
    }
    Ok(body)
}

/// The text of an error body, at most 300 characters. Overpass answers
/// errors with an HTML page whose head fills the first lines; the reason is
/// in the body, so the head and the tags are dropped.
fn readable(body: &str) -> String {
    let start = body.find("<body>").map_or(0, |i| i + "<body>".len());
    let mut text = String::new();
    let mut in_tag = false;
    for c in body[start..].chars() {
        match c {
            '<' => in_tag = true,
            '>' => in_tag = false,
            c if !in_tag => text.push(c),
            _ => {}
        }
    }
    text.split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .chars()
        .take(300)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_user_agent_names_the_project_and_its_site() {
        let ua = user_agent();
        assert!(ua.starts_with("Lunaway/"), "{ua}");
        assert!(ua.ends_with("(+https://lunaway.net)"), "{ua}");
    }

    #[test]
    fn an_overpass_error_page_reads_as_its_message() {
        let page = "<?xml version=\"1.0\"?>\n<html><head><title>OSM3S Response</title></head>\n<body>\n<p>The data is made available under ODbL.</p>\n<p><strong style=\"color:#FF0000\">Error</strong>: runtime error: The server is probably too busy to handle your request. </p>\n</body></html>";
        assert_eq!(
            readable(page),
            "The data is made available under ODbL. Error: runtime error: The server is probably too busy to handle your request."
        );
        assert_eq!(readable("plain text"), "plain text");
    }

    #[test]
    fn only_load_shedding_statuses_are_retried() {
        assert!(is_transient_status(StatusCode::TOO_MANY_REQUESTS));
        assert!(is_transient_status(StatusCode::GATEWAY_TIMEOUT));
        assert!(is_transient_status(StatusCode::SERVICE_UNAVAILABLE));
        assert!(!is_transient_status(StatusCode::BAD_REQUEST));
        assert!(!is_transient_status(StatusCode::NOT_FOUND));
        assert!(
            !is_transient_status(StatusCode::NOT_IMPLEMENTED),
            "a server that does not implement the request will not on the next try"
        );
        assert!(!is_transient_status(StatusCode::HTTP_VERSION_NOT_SUPPORTED));
    }

    #[test]
    fn retry_after_reads_seconds_and_dates() {
        let now = DateTime::parse_from_rfc2822("Tue, 06 Oct 2026 10:00:00 GMT")
            .unwrap()
            .with_timezone(&Utc);
        assert_eq!(
            parse_retry_after("120", now),
            Some(Duration::from_secs(120))
        );
        assert_eq!(
            parse_retry_after("Tue, 06 Oct 2026 10:05:00 GMT", now),
            Some(Duration::from_secs(300))
        );
        assert_eq!(
            parse_retry_after("Tue, 06 Oct 2026 09:00:00 GMT", now),
            Some(Duration::ZERO),
            "a date already past is no wait"
        );
        assert_eq!(parse_retry_after("soon", now), None);
    }

    fn status(retry_after: Option<Duration>) -> IngestError {
        IngestError::Status {
            url: "u".into(),
            status: StatusCode::TOO_MANY_REQUESTS,
            body: String::new(),
            retry_after,
        }
    }

    #[test]
    fn the_wait_is_never_shorter_than_retry_after_and_stops_past_the_ceiling() {
        let backoff = Some(Duration::from_secs(15));
        assert_eq!(next_delay(&status(None), backoff), backoff);
        assert_eq!(
            next_delay(&status(Some(Duration::from_secs(90))), backoff),
            Some(Duration::from_secs(90))
        );
        assert_eq!(
            next_delay(&status(Some(Duration::from_secs(5))), backoff),
            backoff,
            "the backoff still applies when the server asks for less"
        );
        assert_eq!(
            next_delay(&status(Some(Duration::from_secs(7_200))), backoff),
            None
        );
        assert_eq!(
            next_delay(&status(Some(Duration::from_secs(1))), None),
            None,
            "a spent backoff stays spent"
        );
    }
}
