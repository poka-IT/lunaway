//! The alternatives of a route, computed after the best route was sent.
//!
//! A route whose document selects `RouteResult.alternativesToken` asks the
//! engine for the best route alone and answers with it at once; a task then
//! asks the same request with the alternatives, checks and traces them, and
//! keeps the result here under a token drawn at random, bound to the client
//! that received it, for [`KEEP`]. `Query.routeAlternatives(token)` takes it
//! once, waiting for the task within the route's deadline. The alternatives
//! weighed 20 to 47 % of the engine's time of the trips that have them, and
//! the best route waited for them, their check and their traces
//! (`plan/research/126-algorithmes-itineraire.md`, 4.4).
//!
//! Nothing here counts in the client's quota of routes: the route that
//! issued the token did. The store is bounded in entries and in the bytes of
//! the results it holds; a token is never logged, nor a position.

use std::{
    collections::HashMap,
    sync::{Arc, Mutex, PoisonError},
    time::Duration,
};

use tokio::{sync::watch, time::Instant};

use crate::{client::ClientKey, routing_types::RouteAlternatives};

/// How long a token stays good after the route that issued it.
pub(crate) const KEEP: Duration = Duration::from_secs(60);
/// Tokens kept at once, all clients together: past it, a route is computed
/// with its alternatives in one go, as before the tokens.
const MAX_ENTRIES: usize = 256;
/// Bytes of the results kept at once: the alternatives of a trip of
/// 2 000 km weigh about 9 MB (two routes of 4.6 MB, 2.3 kB per kilometre of
/// straight line, `routing::MAX_OSRM_BYTES`); a result that would go past
/// this is dropped and told as `BUSY`. The API runs under 1.5 GB.
const MAX_BYTES: usize = 64 * 1024 * 1024;

/// What a task leaves for the token's reader: none until it is done.
type Result = Option<Arc<RouteAlternatives>>;

struct Entry {
    client: ClientKey,
    expires: Instant,
    /// When the reader stops waiting for the task.
    deadline: Instant,
    /// The bytes of the result counted against [`MAX_BYTES`], once filled.
    bytes: usize,
    result: watch::Receiver<Result>,
}

/// The tokens issued and their results.
#[derive(Default)]
pub(crate) struct Later {
    entries: Mutex<HashMap<String, Entry>>,
}

/// Where a task puts its result.
pub(crate) struct Slot {
    token: String,
    sender: watch::Sender<Result>,
    later: Arc<Later>,
}

/// Why a token gives nothing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Refused {
    /// Unknown, expired, already taken, or issued to another client: the
    /// same answer for each, so that a token says nothing of another's.
    Unknown,
}

impl Later {
    /// Whether a token may be issued now; a few routes running at once may
    /// pass it by as many.
    pub(crate) fn has_room(&self) -> bool {
        let mut entries = self.lock();
        sweep(&mut entries, Instant::now());
        entries.len() < MAX_ENTRIES
    }

    /// A new token for `client`, good for [`KEEP`], whose reader waits for
    /// the task until `deadline`; `None` when the system's random source
    /// fails.
    pub(crate) fn open(
        self: &Arc<Self>,
        client: ClientKey,
        deadline: Instant,
    ) -> Option<(String, Slot)> {
        let token = lunaway_auth::new_nonce()
            .inspect_err(|error| tracing::error!(%error, "no token for a route's alternatives"))
            .ok()?;
        let (sender, result) = watch::channel(None);
        let now = Instant::now();
        let mut entries = self.lock();
        sweep(&mut entries, now);
        entries.insert(
            token.clone(),
            Entry {
                client,
                expires: now + KEEP,
                deadline,
                bytes: 0,
                result,
            },
        );
        drop(entries);
        Some((
            token.clone(),
            Slot {
                token,
                sender,
                later: Arc::clone(self),
            },
        ))
    }

    /// The result of `token` for `client`, waited for until the task's
    /// deadline; once per token. A task that ended without a result (it
    /// stopped, or ran out of time) gives `None`.
    pub(crate) async fn take(
        &self,
        token: &str,
        client: ClientKey,
    ) -> std::result::Result<Result, Refused> {
        let (mut result, deadline) = {
            let mut entries = self.lock();
            sweep(&mut entries, Instant::now());
            match entries.get(token) {
                Some(e) if e.client == client => {}
                _ => return Err(Refused::Unknown),
            }
            let Some(e) = entries.remove(token) else {
                return Err(Refused::Unknown);
            };
            (e.result, e.deadline)
        };
        match tokio::time::timeout_at(deadline, result.wait_for(Option::is_some)).await {
            Ok(Ok(r)) => Ok(r.clone()),
            Ok(Err(_)) | Err(_) => Ok(None),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<String, Entry>> {
        self.entries.lock().unwrap_or_else(PoisonError::into_inner)
    }

    #[cfg(test)]
    fn bytes(&self) -> usize {
        self.lock().values().map(|e| e.bytes).sum()
    }
}

/// Drops the entries past their time.
fn sweep(entries: &mut HashMap<String, Entry>, now: Instant) {
    entries.retain(|_, e| e.expires > now);
}

impl Slot {
    /// Leaves `result` for the token's reader: kept while its bytes fit in
    /// [`MAX_BYTES`] with the others', else replaced by `busy`.
    pub(crate) fn fill(self, result: RouteAlternatives, busy: impl FnOnce() -> RouteAlternatives) {
        let bytes = result.bytes();
        let mut entries = self.later.lock();
        let held: usize = entries.values().map(|e| e.bytes).sum();
        let result = match entries.get_mut(&self.token) {
            // Taken already: its reader waits on the channel, and the bytes
            // go with the answer.
            None => result,
            Some(_) if held.saturating_add(bytes) > MAX_BYTES => {
                tracing::warn!(
                    bytes,
                    held,
                    "the alternatives of a route do not fit in memory"
                );
                busy()
            }
            Some(e) => {
                e.bytes = bytes;
                result
            }
        };
        drop(entries);
        self.sender.send_replace(Some(Arc::new(result)));
    }
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        reason = "a test states its preconditions with unwrap"
    )]

    use super::*;
    use crate::routing_types::RouteAlternativesStatus;

    fn found(bytes: usize) -> RouteAlternatives {
        RouteAlternatives {
            status: RouteAlternativesStatus::Ok,
            osrm_json: Some("x".repeat(bytes)),
            routes: Vec::new(),
        }
    }

    fn busy() -> RouteAlternatives {
        RouteAlternatives {
            status: RouteAlternativesStatus::Busy,
            osrm_json: None,
            routes: Vec::new(),
        }
    }

    const ME: ClientKey = ClientKey::V4(0x0a00_0001);
    const OTHER: ClientKey = ClientKey::V4(0x0a00_0002);

    fn soon() -> Instant {
        Instant::now() + Duration::from_secs(5)
    }

    #[tokio::test(start_paused = true)]
    async fn a_token_gives_its_result_once_and_to_its_client_only() {
        let later = Arc::new(Later::default());
        let (token, slot) = later.open(ME, soon()).unwrap();
        assert!(
            lunaway_auth::is_token_shaped(&token),
            "256 random bits, base64url"
        );
        slot.fill(found(10), busy);
        assert_eq!(
            later.take(&token, OTHER).await.err(),
            Some(Refused::Unknown),
            "another client's request never reads it"
        );
        let r = later.take(&token, ME).await.unwrap().unwrap();
        assert_eq!(r.status, RouteAlternativesStatus::Ok);
        assert_eq!(
            later.take(&token, ME).await.err(),
            Some(Refused::Unknown),
            "once per token"
        );
        assert_eq!(later.bytes(), 0, "a result taken is no longer held");
    }

    #[tokio::test(start_paused = true)]
    async fn a_token_expires_after_a_minute() {
        let later = Arc::new(Later::default());
        let (token, slot) = later.open(ME, soon()).unwrap();
        slot.fill(found(10), busy);
        tokio::time::advance(KEEP + Duration::from_millis(1)).await;
        assert_eq!(later.take(&token, ME).await.err(), Some(Refused::Unknown));
        assert_eq!(later.bytes(), 0, "an expired result is no longer held");
    }

    #[tokio::test(start_paused = true)]
    async fn the_reader_waits_for_the_task_until_its_deadline() {
        let later = Arc::new(Later::default());
        let (token, slot) = later.open(ME, soon()).unwrap();
        let filler = tokio::spawn(async move {
            tokio::time::sleep(Duration::from_secs(2)).await;
            slot.fill(found(10), busy);
        });
        let r = later.take(&token, ME).await.unwrap();
        assert_eq!(
            r.map(|r| r.status),
            Some(RouteAlternativesStatus::Ok),
            "a token read before the task ends gets its result"
        );
        filler.await.unwrap();

        let (token, slot) = later.open(ME, soon()).unwrap();
        let late = tokio::spawn(async move {
            tokio::time::sleep(Duration::from_secs(10)).await;
            slot.fill(found(10), busy);
        });
        assert!(
            later.take(&token, ME).await.unwrap().is_none(),
            "past the deadline the reader gets nothing"
        );
        late.await.unwrap();

        let (token, slot) = later.open(ME, soon()).unwrap();
        drop(slot);
        assert!(
            later.take(&token, ME).await.unwrap().is_none(),
            "a task that stopped without a result gives nothing"
        );
    }

    #[tokio::test(start_paused = true)]
    async fn results_past_the_memory_cap_are_told_busy() {
        let later = Arc::new(Later::default());
        let (first, slot) = later.open(ME, soon()).unwrap();
        slot.fill(found(MAX_BYTES - 100), busy);
        let (second, slot) = later.open(ME, soon()).unwrap();
        slot.fill(found(1_000), busy);
        let r = later.take(&second, ME).await.unwrap().unwrap();
        assert_eq!(r.status, RouteAlternativesStatus::Busy);
        assert!(r.osrm_json.is_none(), "the result dropped is not held");
        assert!(later.take(&first, ME).await.unwrap().is_some());
    }

    #[tokio::test(start_paused = true)]
    async fn the_store_has_no_room_past_its_entries() {
        let later = Arc::new(Later::default());
        let mut slots = Vec::new();
        for _ in 0..MAX_ENTRIES {
            assert!(later.has_room());
            slots.push(later.open(ME, soon()).unwrap());
        }
        assert!(
            !later.has_room(),
            "past its entries a route takes the old path"
        );
        tokio::time::advance(KEEP + Duration::from_millis(1)).await;
        assert!(later.has_room(), "expired entries make room");
    }
}
