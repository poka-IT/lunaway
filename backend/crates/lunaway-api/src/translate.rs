//! Lunaway's translation server, behind `Query.translate`: open models
//! (OPUS-MT on CTranslate2) on the geocoding server, reached through Caddy
//! on the backend's loopback (`infra/caddy/geocoders.caddy`), so the API
//! itself connects to nothing outside the host. No third party sees a
//! text (`docs/deploy.md`, "Translation").
//!
//! The server is sent a stored text, its language and the language asked;
//! it keeps nothing and logs no text, and neither does this module.
//!
//! The API asks it [`TranslateConfig::at_once`] texts at a time for all
//! clients and [`PER_CLIENT`] for one client (an IPv4 address, an IPv6
//! /64), so that a client asking again and again for a text the server
//! always fails at cannot hold every slot; an IPv6 /48, whose /64s one
//! holder may rotate through, holds every slot but one.

use std::{
    collections::HashMap,
    sync::{Arc, Mutex, PoisonError},
    time::Duration,
};

use serde::{Deserialize, Serialize};
use tokio::{
    sync::{OwnedSemaphorePermit, Semaphore},
    time::Instant,
};

use crate::{client::ClientKey, config::TranslateConfig};

/// Largest answer read: the longest original (a review of 4 000
/// characters) translated is well under it.
const MAX_ANSWER_BYTES: usize = 128 * 1024;
/// Longest translation kept, in characters (`translations.text`).
const MAX_TEXT_CHARS: usize = 12_000;
/// How long an idle connection to the server is kept for the next text.
const POOL_IDLE: Duration = Duration::from_secs(5);
/// Texts one client has asked at once, waiting or translated: half the
/// API's slots (four by default) and as many as the server works on
/// together. A text the server always fails at, out of time after 14 s,
/// costs its client no use of the quota (only a translation made counts):
/// a client asking for it again and again holds two slots at most, and the
/// others stay for everyone else (`plan/research/82-suites-4.md`). The
/// reviews of a card that translate by themselves, asked together, take
/// their turns within the same wait as the API's slots.
pub(crate) const PER_CLIENT: usize = 2;

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
    /// The client's own slots ([`PER_CLIENT`]), or its IPv6 /48's, stayed
    /// taken for the whole wait.
    #[error("every slot of the client stayed taken")]
    ClientFull(#[source] tokio::time::error::Elapsed),
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
    /// The slots of the clients translating now, by client: a client is
    /// forgotten once none of its texts waits or runs, so no address stays
    /// here longer than its translations.
    clients: Mutex<HashMap<ClientKey, Arc<Semaphore>>>,
    /// The slots an IPv6 /48 holds at once: every slot of the API but one.
    site_at_once: usize,
}

/// The slots a client's text holds while it waits for the server and is
/// translated: its client's, and its IPv6 /48's.
struct ClientSlots {
    _own: OwnedSemaphorePermit,
    _site: Option<OwnedSemaphorePermit>,
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
            // No total timeout of the client: the one around each call is the
            // only one, so a server out of time is told apart from one that
            // could not be reached in the log of a failure.
            .connect_timeout(config.timeout)
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
            clients: Mutex::default(),
            site_at_once: config.at_once.saturating_sub(1).max(1),
        }
    }

    /// The slots of `key`, made when it starts translating.
    fn client_slots(&self, key: ClientKey) -> Arc<Semaphore> {
        let mut clients = self.clients.lock().unwrap_or_else(PoisonError::into_inner);
        // A client's texts waiting or running, and the slots they hold,
        // share its semaphore: alone in the map, it serves none.
        clients.retain(|_, slots| Arc::strong_count(slots) > 1);
        let size = if key.is_site() {
            self.site_at_once
        } else {
            PER_CLIENT
        };
        Arc::clone(
            clients
                .entry(key)
                .or_insert_with(|| Arc::new(Semaphore::new(size))),
        )
    }

    /// A slot of `client`'s and one of its IPv6 /48's, by `deadline`.
    async fn hold(
        &self,
        client: ClientKey,
        deadline: Instant,
    ) -> Result<ClientSlots, TranslateError> {
        let take = |key: ClientKey| {
            let slots = self.client_slots(key);
            async move {
                tokio::time::timeout_at(deadline, slots.acquire_owned())
                    .await
                    .map_err(TranslateError::ClientFull)?
                    .map_err(TranslateError::Closed)
            }
        };
        let own = take(client).await?;
        let site = match client.site() {
            Some(site) => Some(take(site).await?),
            None => None,
        };
        Ok(ClientSlots {
            _own: own,
            _site: site,
        })
    }

    /// Whether a server is configured.
    pub(crate) fn enabled(&self) -> bool {
        self.http.is_some() && self.endpoint.is_some()
    }

    /// `text`, written in `source`, translated into `target` for `client`.
    /// It waits for a slot of the client's and one of the API's within the
    /// same wait (`TranslateConfig::queue_wait`), and holds both until the
    /// server answers, whether the client still listens or not.
    pub(crate) async fn translate(
        &self,
        client: ClientKey,
        text: &str,
        source: &str,
        target: &str,
    ) -> Result<Translated, TranslateError> {
        let (Some(http), Some(endpoint)) = (&self.http, &self.endpoint) else {
            return Err(TranslateError::Off);
        };
        let deadline = Instant::now() + self.queue_wait;
        let _client = self.hold(client, deadline).await?;
        let _slot = tokio::time::timeout_at(deadline, self.slots.acquire())
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

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        reason = "a test states its preconditions with unwrap"
    )]

    use super::*;

    #[tokio::test]
    async fn a_client_is_forgotten_once_its_translations_end() {
        // A port nothing listens on: the text fails at once, after taking
        // the slots of its client and of its client's /48.
        let closed = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}/translator", closed.local_addr().unwrap());
        drop(closed);
        // What `ApiState::new` installs before the translator, with the
        // geocoders.
        let _ = rustls::crypto::ring::default_provider().install_default();
        let translator = Translator::new(&TranslateConfig {
            url: Some(url),
            ..TranslateConfig::default()
        });
        let v6 = ClientKey::of("2001:db8:1:1::1".parse().unwrap());
        let failed = translator.translate(v6, "Hallo", "de", "fr").await;
        assert!(
            matches!(failed, Err(TranslateError::Unreachable(_))),
            "{failed:?}"
        );
        let v4 = ClientKey::of("203.0.113.9".parse().unwrap());
        drop(translator.client_slots(v4));
        let clients = translator
            .clients
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        assert_eq!(
            clients.keys().copied().collect::<Vec<_>>(),
            [v4],
            "an address is kept no longer than its translations"
        );
    }
}
