//! Accounts without e-mail: a device key signs a challenge, the server hands
//! back an opaque session; a paper recovery code attaches a new key.
//!
//! - [`DevicePublicKey`]: a P-256 public key received as a JWK, and the
//!   ES256 check of a signature over [`challenge_message`].
//! - [`ChallengeKey`]: sign-in nonces the server checks without storing
//!   them; [`new_session_token`], [`token_hash`]: the session token and the
//!   only form a session is stored in.
//! - [`RecoveryCode`]: 128 random bits a person writes down, and the hash an
//!   account is found by.
//! - [`generate_pseudonym`]: the public name a new account starts with.
//!
//! Nothing here touches the database or the network: the API stores what
//! these functions return. `schema/auth-vectors.json` pins the formats for
//! the app's signer.

mod challenge;
mod der;
mod keys;
mod pseudonym;
mod recovery;
mod tokens;

pub use challenge::{ChallengeKey, CheckedNonce, NonceError};
pub use keys::{DevicePublicKey, MAX_JWK_BYTES, MAX_SIGNATURE_CHARS};
pub use pseudonym::{Locale, MAX_GENERATED_CHARS, generate_pseudonym};
pub use recovery::{RECOVERY_SYMBOLS, RecoveryCode};
pub use tokens::{
    CHALLENGE_PREFIX, NewSession, TOKEN_CHARS, challenge_message, is_token_shaped, new_nonce,
    new_session_token, token_hash,
};

/// What can go wrong with a key, a signature, or the server's own secrets.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum AuthError {
    /// The public key is malformed, of another curve, or not a point of
    /// P-256; the text says which rule it breaks.
    #[error("invalid public key: {0}")]
    InvalidKey(&'static str),
    /// The signature is malformed or does not verify.
    #[error("invalid signature")]
    InvalidSignature,
    /// The operating system could not supply random bytes.
    #[error("the system random source failed")]
    Random(#[source] getrandom::Error),
    /// Argon2 refused its parameters.
    #[error("cannot hash the recovery code")]
    Hash(#[source] argon2::Error),
    /// A pseudonym word list is empty: the lists are files of this crate,
    /// so only an edit of them can cause it, and a test catches that.
    #[error("a pseudonym word list is empty")]
    EmptyWordList,
}

/// Fills `buf` from the operating system's random source.
fn random(buf: &mut [u8]) -> Result<(), AuthError> {
    getrandom::fill(buf).map_err(AuthError::Random)
}
