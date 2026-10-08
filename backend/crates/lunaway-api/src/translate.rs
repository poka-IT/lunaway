//! Lunaway's translation server, behind `Query.translate`: open models
//! (OPUS-MT on CTranslate2) on the geocoding server, reached through Caddy
//! on the backend's loopback (`infra/caddy/geocoders.caddy`), so the API
//! itself connects to nothing outside the host. No third party sees a
//! text (`docs/deploy.md`, "Translation").
//!
//! The server is sent a stored text, its language and the language asked;
//! it keeps nothing and logs no text, and neither does this module.

use std::time::Duration;

use serde::{Deserialize, Serialize};
use tokio::sync::Semaphore;

use crate::config::TranslateConfig;

/// Largest answer read: the longest original (a review of 4 000
/// characters) translated is well under it.
const MAX_ANSWER_BYTES: usize = 128 * 1024;
/// Longest translation kept, in characters (`translations.text`).
const MAX_TEXT_CHARS: usize = 12_000;
/// How long an idle connection to the server is kept for the next text.
const POOL_IDLE: Duration = Duration::from_secs(5);

/// What the server made of a text.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub(crate) struct Translated {
    /// The translation.
    pub(crate) text: String,
    /// The engine (`opus-mt`).
    pub(crate) engine: String,
    /// The model of the language pair, with its release.
    pub(crate) model: String,
}

/// Why a text was not translated.
#[derive(Debug, thiserror::Error)]
pub(crate) enum TranslateError {
    /// No server is configured, or no HTTP client could start.
    #[error("no translation server")]
    Off,
    /// Every slot of the API stayed taken for the whole wait.
    #[error("every slot stayed taken")]
    QueueFull(#[source] tokio::time::error::Elapsed),
    /// The slots were closed (never: the semaphore lives as long as the
    /// translator).
    #[error("no slot")]
    Closed(#[source] tokio::sync::AcquireError),
    /// The server said it was busy (429, 503): it did no work.
    #[error("the translation server is busy")]
    Busy,
    /// The server has no model for the pair.
    #[error("no model for this pair of languages")]
    Unsupported,
    /// No connection, or the connection broke before an answer.
    #[error("unreachable")]
    Unreachable(#[source] reqwest::Error),
    /// The server answered another status: it failed.
    #[error("answered {0}")]
    Status(u16),
    /// The answer was larger than [`MAX_ANSWER_BYTES`].
    #[error("answer too large")]
    TooLarge,
    /// The answer was not the JSON expected.
    #[error("answer not understood")]
    NotJson(#[source] serde_json::Error),
    /// The answer's text, engine or model was empty or too long.
    #[error("answer out of bounds")]
    OutOfBounds,
    /// No answer within the configured time.
    #[error("out of time")]
    Timeout(#[source] tokio::time::error::Elapsed),
}

impl TranslateError {
    /// Whether the server did no work for the request, so the client's use
    /// of its quota goes back: nothing configured, no slot, a refusal before
    /// translating (busy, no model for the pair, no connection). A failure
    /// after the server worked (out of time, a bad answer, an error status)
    /// keeps the use, or slow texts would cost nothing and could be asked
    /// again without end.
    pub(crate) fn did_no_work(&self) -> bool {
        matches!(
            self,
            Self::Off
                | Self::QueueFull(_)
                | Self::Closed(_)
                | Self::Busy
                | Self::Unsupported
                | Self::Unreachable(_)
        )
    }
}

#[derive(Serialize)]
struct Ask<'a> {
    source: &'a str,
    target: &'a str,
    text: &'a str,
}

/// The translation server the API asks, or none.
#[derive(Debug)]
pub(crate) struct Translator {
    http: Option<reqwest::Client>,
    endpoint: Option<reqwest::Url>,
    timeout: Duration,
    queue_wait: Duration,
    slots: Semaphore,
}

impl Translator {
    /// The server of `config`. Without an HTTP client (a TLS stack that
    /// cannot start), translation is off and the error is logged.
    pub(crate) fn new(config: &TranslateConfig) -> Self {
        let http = reqwest::Client::builder()
            .user_agent(concat!(
                "Lunaway/",
                env!("CARGO_PKG_VERSION"),
                " (+https://lunaway.net)"
            ))
            // A proxy variable in the environment would send the text
            // elsewhere; a redirect could too.
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .connect_timeout(config.timeout)
            .timeout(config.timeout)
            .pool_idle_timeout(POOL_IDLE)
            .build()
            .inspect_err(|error| tracing::error!(%error, "no HTTP client: nothing is translated"))
            .ok();
        let endpoint = config.url.as_deref().and_then(|base| {
            let mut url = reqwest::Url::parse(base)
                .inspect_err(|error| {
                    tracing::error!(%error, "the translation server's URL does not parse; it is off");
                })
                .ok()?;
            url.path_segments_mut()
                .ok()?
                .pop_if_empty()
                .push("translate");
            Some(url)
        });
        Self {
            http,
            endpoint,
            timeout: config.timeout,
            queue_wait: config.queue_wait,
            slots: Semaphore::new(config.at_once),
        }
    }

    /// Whether a server is configured.
    pub(crate) fn enabled(&self) -> bool {
        self.http.is_some() && self.endpoint.is_some()
    }

    /// `text`, written in `source`, translated into `target`.
    pub(crate) async fn translate(
        &self,
        text: &str,
        source: &str,
        target: &str,
    ) -> Result<Translated, TranslateError> {
        let (Some(http), Some(endpoint)) = (&self.http, &self.endpoint) else {
            return Err(TranslateError::Off);
        };
        let _slot = tokio::time::timeout(self.queue_wait, self.slots.acquire())
            .await
            .map_err(TranslateError::QueueFull)?
            .map_err(TranslateError::Closed)?;
        let call = async {
            let mut response = http
                .post(endpoint.clone())
                .json(&Ask {
                    source,
                    target,
                    text,
                })
                .send()
                .await
                .map_err(|e| TranslateError::Unreachable(e.without_url()))?;
            match response.status().as_u16() {
                200 => {}
                422 => return Err(TranslateError::Unsupported),
                429 | 503 => return Err(TranslateError::Busy),
                status => return Err(TranslateError::Status(status)),
            }
            if response
                .content_length()
                .is_some_and(|n| n > MAX_ANSWER_BYTES as u64)
            {
                return Err(TranslateError::TooLarge);
            }
            let mut bytes = Vec::new();
            while let Some(chunk) = response
                .chunk()
                .await
                .map_err(|e| TranslateError::Unreachable(e.without_url()))?
            {
                bytes.extend_from_slice(&chunk);
                if bytes.len() > MAX_ANSWER_BYTES {
                    return Err(TranslateError::TooLarge);
                }
            }
            let answer: Translated =
                serde_json::from_slice(&bytes).map_err(TranslateError::NotJson)?;
            let chars = answer.text.chars().count();
            if chars == 0
                || chars > MAX_TEXT_CHARS
                || !(1..=64).contains(&answer.engine.chars().count())
                || !(1..=200).contains(&answer.model.chars().count())
            {
                return Err(TranslateError::OutOfBounds);
            }
            Ok(answer)
        };
        tokio::time::timeout(self.timeout, call)
            .await
            .unwrap_or_else(|elapsed| Err(TranslateError::Timeout(elapsed)))
    }
}
