//! Persisted queries, the Apollo convention (APQ): a client sends the
//! SHA-256 of its document in `extensions.persistedQuery` instead of the
//! document; the server answers `PERSISTED_QUERY_NOT_FOUND` when it does not
//! know the hash, and the client sends the document once more with the hash,
//! which the server checks and keeps.
//!
//! The app's sync request carries 1 047 bytes of document in a body of
//! 1 280; with the hash instead the body is 298 bytes, on every page of
//! every sync (`plan/research/23-backend-europe-packs.md`). The answer, a
//! page of up to a thousand places, stays the bulk of a sync.
//!
//! A document is kept only once it ran without any error, so a client cannot
//! fill the registry with documents that do not even validate; the registry
//! is bounded in entries, each document by the guard's size limit
//! ([`crate::guard::MAX_QUERY_BYTES`]), the least recently used evicted
//! first, and it takes at most [`NEW_PER_MINUTE`] new documents a minute,
//! [`NEW_PER_CLIENT_MINUTE`] of them from one client (an IPv4 address, an
//! IPv6 /48): one address could otherwise register throwaway documents fast
//! enough to push the app's out, or spend the minute's budget before the
//! app's first devices after a restart (security audits of 2026-10-06). The
//! app's documents, used by every device, stay the most recent. Clients on
//! three or more addresses can still spend a minute's budget; the app then
//! sends its document with the hash on each request, as without the
//! registry, until a later minute keeps it. A document
//! sent without a hash is served as before, under the same limits: the
//! schema is public and every document is bounded by the guard and its
//! cost, so an allowlist would refuse third-party and older clients without
//! bounding anything the limits do not already bound.

use std::{
    collections::{HashMap, VecDeque},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use sha2::{Digest, Sha256};

use crate::client::ClientKey;

/// Documents kept at most: the app names 41 operations (`app/lib`,
/// 2026-10-06).
pub const MAX_ENTRIES: usize = 512;
/// New documents kept per minute, all clients together: a flood needs over
/// eight minutes to replace the whole registry, and the documents the app's
/// devices keep using stay the most recent.
pub const NEW_PER_MINUTE: u32 = 60;
/// New documents kept per minute from one client: a device that runs more
/// new operations in a minute sends the others whole until a later minute
/// keeps them.
pub const NEW_PER_CLIENT_MINUTE: u32 = 20;

/// The code of the answer to an unknown hash, as Apollo clients expect it.
pub const NOT_FOUND: &str = "PERSISTED_QUERY_NOT_FOUND";
/// The message of that answer, which Apollo clients also match on.
pub const NOT_FOUND_MESSAGE: &str = "PersistedQueryNotFound";

/// The documents known by their hash, the least recently used evicted
/// first.
#[derive(Debug, Default)]
pub(crate) struct Registry {
    inner: Mutex<Inner>,
}

#[derive(Debug, Default)]
struct Inner {
    map: HashMap<String, Arc<str>>,
    /// Least recently used first.
    order: VecDeque<String>,
    /// The minute new documents are counted in, and how many it took.
    minute: Option<(Instant, u32)>,
    /// How many each client added in that minute: at most
    /// [`NEW_PER_MINUTE`] entries, one per client that added one.
    by_client: HashMap<ClientKey, u32>,
}

impl Registry {
    /// The document of `hash`, if kept; it becomes the most recently used.
    pub(crate) fn get(&self, hash: &str) -> Option<Arc<str>> {
        let mut inner = self.inner.lock().ok()?;
        let doc = inner.map.get(hash).cloned()?;
        if let Some(i) = inner.order.iter().position(|h| h == hash)
            && let Some(h) = inner.order.remove(i)
        {
            inner.order.push_back(h);
        }
        Some(doc)
    }

    /// Keeps `document` under `hash` (its SHA-256, checked by the caller),
    /// sent by `client`, unless the minute's new documents, or that
    /// client's, are spent.
    pub(crate) fn put(&self, hash: &str, document: &str, client: ClientKey) {
        self.put_at(hash, document, client, Instant::now());
    }

    fn put_at(&self, hash: &str, document: &str, client: ClientKey, now: Instant) {
        let Ok(mut inner) = self.inner.lock() else {
            return;
        };
        if inner.map.contains_key(hash) {
            return;
        }
        let count = match inner.minute {
            Some((start, n)) if now.duration_since(start) < Duration::from_secs(60) => n,
            _ => {
                inner.minute = Some((now, 0));
                inner.by_client.clear();
                0
            }
        };
        // An IPv6 holder counts by its /48, which it may rotate through.
        let client = client.site().unwrap_or(client);
        let of_client = inner.by_client.get(&client).copied().unwrap_or(0);
        if count >= NEW_PER_MINUTE || of_client >= NEW_PER_CLIENT_MINUTE {
            return;
        }
        inner.minute = inner.minute.map(|(start, n)| (start, n + 1));
        inner.by_client.insert(client, of_client + 1);
        inner.map.insert(hash.to_owned(), Arc::from(document));
        inner.order.push_back(hash.to_owned());
        while inner.order.len() > MAX_ENTRIES {
            if let Some(old) = inner.order.pop_front() {
                inner.map.remove(&old);
            }
        }
    }
}

/// The lowercase hexadecimal SHA-256 of `document`.
#[must_use]
pub fn hash(document: &str) -> String {
    Sha256::digest(document.as_bytes())
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// Whether `hash` reads as a SHA-256 in hexadecimal.
#[must_use]
pub fn well_formed(hash: &str) -> bool {
    hash.len() == 64 && hash.bytes().all(|b| b.is_ascii_hexdigit())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_least_recently_used_document_goes_first() {
        let r = Registry::default();
        let start = Instant::now();
        // A minute apart in batches, as the per-minute caps allow.
        for i in 0..=MAX_ENTRIES {
            let doc = format!("{{ q{i} }}");
            let minute = u64::try_from(i).unwrap() / u64::from(NEW_PER_CLIENT_MINUTE);
            r.put_at(
                &hash(&doc),
                &doc,
                ClientKey::Unknown,
                start + Duration::from_secs(61 * minute),
            );
            if i == 10 {
                assert!(r.get(&hash("{ q0 }")).is_some(), "used: q0 is recent again");
            }
        }
        assert!(
            r.get(&hash("{ q0 }")).is_some(),
            "a document in use outlives the ones registered after it"
        );
        assert!(
            r.get(&hash("{ q1 }")).is_none(),
            "the registry holds MAX_ENTRIES documents, the least recently used goes"
        );
    }

    fn kept(r: &Registry, prefix: &str, n: u32) -> u32 {
        let kept = (0..n)
            .filter(|i| r.get(&hash(&format!("{{ {prefix}{i} }}"))).is_some())
            .count();
        u32::try_from(kept).unwrap()
    }

    #[test]
    fn a_flood_of_new_documents_is_capped_per_client_and_per_minute() {
        let r = Registry::default();
        let now = Instant::now();
        let flooder = ClientKey::of("203.0.113.9".parse().unwrap());
        for i in 0..200 {
            let doc = format!("{{ flood{i} }}");
            r.put_at(&hash(&doc), &doc, flooder, now);
        }
        assert_eq!(kept(&r, "flood", 200), NEW_PER_CLIENT_MINUTE);
        // Another /64 of the same /48 shares its budget.
        let rotated = ClientKey::of("2001:db8:1:1::1".parse().unwrap());
        let sibling = ClientKey::of("2001:db8:1:2::1".parse().unwrap());
        for i in 0..30 {
            let doc = format!("{{ v6{i} }}");
            let client = if i % 2 == 0 { rotated } else { sibling };
            r.put_at(&hash(&doc), &doc, client, now);
        }
        assert_eq!(kept(&r, "v6", 30), NEW_PER_CLIENT_MINUTE);
        let app = ClientKey::of("198.51.100.7".parse().unwrap());
        for i in 0..30 {
            let doc = format!("{{ app{i} }}");
            r.put_at(&hash(&doc), &doc, app, now);
        }
        assert_eq!(
            kept(&r, "app", 30),
            NEW_PER_MINUTE - 2 * NEW_PER_CLIENT_MINUTE,
            "what is left of the minute goes to the next client"
        );
        let late = ClientKey::of("192.0.2.44".parse().unwrap());
        for i in 0..5 {
            let doc = format!("{{ late{i} }}");
            r.put_at(&hash(&doc), &doc, late, now);
        }
        assert_eq!(
            kept(&r, "late", 5),
            0,
            "the minute's budget is spent, whoever asks"
        );
        r.put_at(
            &hash("{ next }"),
            "{ next }",
            flooder,
            now + Duration::from_secs(61),
        );
        assert!(
            r.get(&hash("{ next }")).is_some(),
            "the next minute takes new ones"
        );
    }

    #[test]
    fn hashes_are_sha256_in_lowercase_hex() {
        // FIPS 180-2, appendix B.1: the clients compute the same.
        assert_eq!(
            hash("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert!(well_formed(&hash("x")));
        assert!(!well_formed("abc"));
        assert!(!well_formed(&"g".repeat(64)));
    }
}
