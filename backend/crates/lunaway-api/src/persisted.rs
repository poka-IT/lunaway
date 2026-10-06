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
//! ([`crate::guard::MAX_QUERY_BYTES`]), the oldest evicted first. A document
//! sent without a hash is served as before, under the same limits: the
//! schema is public and every document is bounded by the guard and its
//! cost, so an allowlist would refuse third-party and older clients without
//! bounding anything the limits do not already bound.

use std::{
    collections::{HashMap, VecDeque},
    sync::{Arc, Mutex},
};

use sha2::{Digest, Sha256};

/// Documents kept at most: the app sends about twenty.
pub const MAX_ENTRIES: usize = 512;

/// The code of the answer to an unknown hash, as Apollo clients expect it.
pub const NOT_FOUND: &str = "PERSISTED_QUERY_NOT_FOUND";
/// The message of that answer, which Apollo clients also match on.
pub const NOT_FOUND_MESSAGE: &str = "PersistedQueryNotFound";

/// The documents known by their hash, the oldest evicted first.
#[derive(Debug, Default)]
pub(crate) struct Registry {
    inner: Mutex<Inner>,
}

#[derive(Debug, Default)]
struct Inner {
    map: HashMap<String, Arc<str>>,
    order: VecDeque<String>,
}

impl Registry {
    /// The document of `hash`, if kept.
    pub(crate) fn get(&self, hash: &str) -> Option<Arc<str>> {
        self.inner.lock().ok()?.map.get(hash).cloned()
    }

    /// Keeps `document` under `hash` (its SHA-256, checked by the caller).
    pub(crate) fn put(&self, hash: &str, document: &str) {
        let Ok(mut inner) = self.inner.lock() else {
            return;
        };
        if inner.map.contains_key(hash) {
            return;
        }
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
    fn the_oldest_document_goes_first() {
        let r = Registry::default();
        for i in 0..=MAX_ENTRIES {
            let doc = format!("{{ q{i} }}");
            r.put(&hash(&doc), &doc);
        }
        assert!(
            r.get(&hash("{ q0 }")).is_none(),
            "the registry holds MAX_ENTRIES documents"
        );
        assert_eq!(
            r.get(&hash("{ q1 }")).as_deref(),
            Some("{ q1 }"),
            "the newer ones stay"
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
