//! The random values the server hands out: sign-in nonces and session
//! tokens, 32 bytes each in base64url.

use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use sha2::{Digest, Sha256};

use crate::{AuthError, random};

/// What the device signs before the nonce: the protocol and its version,
/// so a signature made for something else never passes for a sign-in.
pub const CHALLENGE_PREFIX: &str = "lunaway-auth:v1:";

/// Length of a nonce or a session token: 32 bytes in base64url without
/// padding.
pub const TOKEN_CHARS: usize = 43;

/// The exact text a device signs for `nonce`; its UTF-8 bytes are the
/// signed message.
#[must_use]
pub fn challenge_message(nonce: &str) -> String {
    format!("{CHALLENGE_PREFIX}{nonce}")
}

fn random_token() -> Result<String, AuthError> {
    let mut bytes = [0u8; 32];
    random(&mut bytes)?;
    Ok(URL_SAFE_NO_PAD.encode(bytes))
}

/// A fresh sign-in nonce: 32 random bytes, base64url without padding.
///
/// # Errors
///
/// [`AuthError::Random`] when the system cannot supply random bytes.
pub fn new_nonce() -> Result<String, AuthError> {
    random_token()
}

/// Whether `s` has the shape of a nonce or a session token: 43 base64url
/// characters. Checked before any lookup, so a malformed header or argument
/// costs no database query.
#[must_use]
pub fn is_token_shaped(s: &str) -> bool {
    s.len() == TOKEN_CHARS
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

/// A session as created: the token goes to the client once, only its hash
/// is stored.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewSession {
    /// The bearer token, 43 base64url characters.
    pub token: String,
    /// SHA-256 of the token's text: the stored key of the session.
    pub hash: [u8; 32],
}

/// A fresh session token and its hash.
///
/// # Errors
///
/// [`AuthError::Random`] when the system cannot supply random bytes.
pub fn new_session_token() -> Result<NewSession, AuthError> {
    let token = random_token()?;
    let hash = Sha256::digest(token.as_bytes()).into();
    Ok(NewSession { token, hash })
}

/// The stored key of a session token, or `None` when `token` is not shaped
/// like one. A plain SHA-256 suffices: the token holds 256 random bits, so
/// nobody can guess one from a stolen hash.
#[must_use]
pub fn token_hash(token: &str) -> Option<[u8; 32]> {
    is_token_shaped(token).then(|| Sha256::digest(token.as_bytes()).into())
}

#[cfg(test)]
mod tests {
    use proptest::prelude::*;

    use super::*;

    #[test]
    fn a_session_is_stored_by_the_hash_of_its_token() {
        let s = new_session_token().unwrap();
        assert!(is_token_shaped(&s.token));
        assert_eq!(token_hash(&s.token), Some(s.hash));
        assert_ne!(
            new_session_token().unwrap().token,
            s.token,
            "two sessions never share a token"
        );
        assert!(is_token_shaped(&new_nonce().unwrap()));
    }

    #[test]
    fn the_message_is_the_prefix_and_the_nonce() {
        assert_eq!(challenge_message("abc"), "lunaway-auth:v1:abc");
    }

    #[test]
    fn garbage_is_not_a_token() {
        for bad in [
            "",
            "Bearer",
            &"a".repeat(42),
            &"a".repeat(44),
            &format!("{}=", "a".repeat(42)),
            &format!("{}+", "a".repeat(42)),
            &format!("{}é", "a".repeat(41)),
        ] {
            assert!(!is_token_shaped(bad), "{bad:?}");
            assert_eq!(token_hash(bad), None);
        }
    }

    proptest! {
        #[test]
        fn any_32_bytes_encode_to_a_token_shape(bytes in proptest::array::uniform32(any::<u8>())) {
            prop_assert!(is_token_shaped(&URL_SAFE_NO_PAD.encode(bytes)));
        }

        #[test]
        fn strings_of_another_length_are_never_tokens(s in "[A-Za-z0-9_-]{0,80}") {
            prop_assert_eq!(is_token_shaped(&s), s.len() == TOKEN_CHARS);
        }
    }
}
