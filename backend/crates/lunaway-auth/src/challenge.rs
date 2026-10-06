//! Sign-in nonces the server can check without having stored them.
//!
//! A nonce is 32 bytes in base64url: 16 random bytes, the expiry (seconds
//! since the Unix epoch, 8 bytes big-endian), and the first 8 bytes of an
//! HMAC-SHA-256 of both under a key the server draws at start. The server
//! keeps nothing per challenge it hands out, so a flood of `authChallenge`
//! fills no table; it keeps only the nonces already answered, until they
//! expire, so each answers once. A restart draws a new key: outstanding
//! challenges stop working and the client asks again.

use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use hmac::{Hmac, KeyInit, Mac};
use sha2::Sha256;

use crate::{AuthError, random};

const RANDOM: usize = 16;
const EXPIRY: usize = 8;
const TAG: usize = 8;

/// Why a nonce is refused.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
#[non_exhaustive]
pub enum NonceError {
    /// Not 32 bytes of base64url.
    #[error("not a nonce this server issued")]
    Malformed,
    /// The tag does not match: forged, or issued before a restart.
    #[error("not a nonce this server issued")]
    Forged,
    /// Past its expiry.
    #[error("the challenge expired")]
    Expired,
}

/// The server's key for nonces.
pub struct ChallengeKey([u8; 32]);

impl std::fmt::Debug for ChallengeKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("ChallengeKey(..)")
    }
}

/// A checked nonce: what identifies it among the answered ones, and until
/// when it must be remembered.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CheckedNonce {
    /// Its random part.
    pub id: [u8; RANDOM],
    /// Its expiry, seconds since the Unix epoch.
    pub expires: u64,
}

impl ChallengeKey {
    /// A fresh key from the system's random source.
    ///
    /// # Errors
    ///
    /// [`AuthError::Random`] when the system cannot supply random bytes.
    pub fn generate() -> Result<Self, AuthError> {
        let mut key = [0u8; 32];
        random(&mut key)?;
        Ok(Self(key))
    }

    /// A key from fixed bytes, for tests.
    #[must_use]
    pub const fn from_bytes(key: [u8; 32]) -> Self {
        Self(key)
    }

    /// The MAC over this key. HMAC takes keys of any length, so the error
    /// branch is never taken; it is still reported rather than unwrapped.
    fn mac(&self) -> Option<Hmac<Sha256>> {
        <Hmac<Sha256> as KeyInit>::new_from_slice(&self.0).ok()
    }

    /// A nonce valid until `expires` (seconds since the Unix epoch).
    ///
    /// # Errors
    ///
    /// [`AuthError::Random`] when the system cannot supply random bytes.
    pub fn issue(&self, expires: u64) -> Result<String, AuthError> {
        let mut raw = [0u8; RANDOM + EXPIRY + TAG];
        random(&mut raw[..RANDOM])?;
        raw[RANDOM..RANDOM + EXPIRY].copy_from_slice(&expires.to_be_bytes());
        let mut mac = self.mac().ok_or(AuthError::InvalidKey("challenge key"))?;
        mac.update(&raw[..RANDOM + EXPIRY]);
        let tag = mac.finalize().into_bytes();
        raw[RANDOM + EXPIRY..].copy_from_slice(&tag[..TAG]);
        Ok(URL_SAFE_NO_PAD.encode(raw))
    }

    /// Checks that `nonce` was issued with this key and has not expired at
    /// `now` (seconds since the Unix epoch).
    ///
    /// # Errors
    ///
    /// [`NonceError`] saying why it is refused.
    pub fn check(&self, nonce: &str, now: u64) -> Result<CheckedNonce, NonceError> {
        if !crate::is_token_shaped(nonce) {
            return Err(NonceError::Malformed);
        }
        let raw = URL_SAFE_NO_PAD
            .decode(nonce)
            .map_err(|_| NonceError::Malformed)?;
        let raw: [u8; RANDOM + EXPIRY + TAG] = raw.try_into().map_err(|_| NonceError::Malformed)?;
        let mut mac = self.mac().ok_or(NonceError::Forged)?;
        mac.update(&raw[..RANDOM + EXPIRY]);
        // Constant-time comparison of the truncated tag.
        mac.verify_truncated_left(&raw[RANDOM + EXPIRY..])
            .map_err(|_| NonceError::Forged)?;
        let mut expiry = [0u8; EXPIRY];
        expiry.copy_from_slice(&raw[RANDOM..RANDOM + EXPIRY]);
        let expires = u64::from_be_bytes(expiry);
        if expires <= now {
            return Err(NonceError::Expired);
        }
        let mut id = [0u8; RANDOM];
        id.copy_from_slice(&raw[..RANDOM]);
        Ok(CheckedNonce { id, expires })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_nonce_checks_until_it_expires_and_only_under_its_key() {
        let key = ChallengeKey::from_bytes([7; 32]);
        let nonce = key.issue(1_000).unwrap();
        assert!(
            crate::is_token_shaped(&nonce),
            "the shape of the contract: 43 characters"
        );
        let checked = key.check(&nonce, 999).unwrap();
        assert_eq!(checked.expires, 1_000);
        assert_eq!(key.check(&nonce, 1_000), Err(NonceError::Expired));
        let other = ChallengeKey::from_bytes([8; 32]);
        assert_eq!(
            other.check(&nonce, 999),
            Err(NonceError::Forged),
            "a nonce of another key (before a restart) is refused"
        );
        assert_eq!(key.check("short", 0), Err(NonceError::Malformed));
    }

    #[test]
    fn a_nonce_whose_expiry_was_pushed_back_is_refused() {
        let key = ChallengeKey::from_bytes([7; 32]);
        let nonce = key.issue(1_000).unwrap();
        let mut raw = URL_SAFE_NO_PAD.decode(&nonce).unwrap();
        raw[RANDOM..RANDOM + EXPIRY].copy_from_slice(&u64::MAX.to_be_bytes());
        let forged = URL_SAFE_NO_PAD.encode(raw);
        assert_eq!(key.check(&forged, 2_000), Err(NonceError::Forged));
    }

    #[test]
    fn two_nonces_differ() {
        let key = ChallengeKey::generate().unwrap();
        assert_ne!(key.issue(5).unwrap(), key.issue(5).unwrap());
    }
}
