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
//! first, and it takes at most [`NEW_PER_MINUTE`] new documents a minute:
//! one address could otherwise register throwaway documents fast enough to
//! push the app's out (security audit of 2026-10-06), and the app's, used
//! by every device, stay the most recent. A document
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

/// Documents kept at most: the app sends about twenty.
pub const MAX_ENTRIES: usize = 512;
/// New documents kept per minute, all clients together: the app's twenty
/// after a restart fit in the first minute; a flood needs over eight
/// minutes to replace the whole registry.
pub const NEW_PER_MINUTE: u32 = 60;

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
    /// unless the minute's new documents are spent.
    pub(crate) fn put(&self, hash: &str, document: &str) {
        self.put_at(hash, document, Instant::now());
    }

    fn put_at(&self, hash: &str, document: &str, now: Instant) {
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
                0
            }
        };
        if count >= NEW_PER_MINUTE {
            return;
        }
        inner.minute = inner.minute.map(|(start, n)| (start, n + 1));
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
        // A minute apart in batches, as the per-minute cap allows.
        for i in 0..=MAX_ENTRIES {
            let doc = format!("{{ q{i} }}");
            let minute = u64::try_from(i).unwrap() / u64::from(NEW_PER_MINUTE);
            r.put_at(&hash(&doc), &doc, start + Duration::from_secs(61 * minute));
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

    #[test]
    fn a_flood_of_new_documents_is_capped_per_minute() {
        let r = Registry::default();
        let now = Instant::now();
        for i in 0..200 {
            let doc = format!("{{ flood{i} }}");
            r.put_at(&hash(&doc), &doc, now);
        }
        let kept = (0..200)
            .filter(|i| r.get(&hash(&format!("{{ flood{i} }}"))).is_some())
            .count();
        assert_eq!(kept, usize::try_from(NEW_PER_MINUTE).unwrap());
        r.put_at(&hash("{ next }"), "{ next }", now + Duration::from_secs(61));
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
