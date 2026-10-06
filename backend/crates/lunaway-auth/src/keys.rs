//! Device keys: P-256 public keys sent as JWK (RFC 7517, RFC 7518), and the
//! ES256 check of what they sign.

use base64::{
    Engine, alphabet,
    engine::{DecodePaddingMode, GeneralPurpose, GeneralPurposeConfig, general_purpose},
};
use p256::ecdsa::{Signature, VerifyingKey, signature::Verifier};
use serde::Deserialize;
use sha2::{Digest, Sha256};

use crate::{AuthError, der};

/// Longest JWK text read: a P-256 JWK with every optional member is under
/// 300 bytes, so anything far longer is not a key.
pub const MAX_JWK_BYTES: usize = 1024;

/// Longest signature text read: a DER signature is at most 72 bytes, 96
/// base64 characters with padding.
pub const MAX_SIGNATURE_CHARS: usize = 128;

/// base64url as JOSE writes it (RFC 7515, section 2): no padding, and only
/// the canonical encoding of the bytes.
const JWK_BASE64: GeneralPurpose = general_purpose::URL_SAFE_NO_PAD;

/// base64url with or without padding, for signatures: Dart's `base64Url`
/// pads by default, and a padded signature carries the same bytes.
const SIGNATURE_BASE64: GeneralPurpose = GeneralPurpose::new(
    &alphabet::URL_SAFE,
    GeneralPurposeConfig::new()
        .with_encode_padding(false)
        .with_decode_padding_mode(DecodePaddingMode::Indifferent),
);

/// The members of a JWK this server reads. Others (`alg`, `use`, `kid`,
/// `key_ops`, `ext`) are ignored.
#[derive(Deserialize)]
struct Jwk {
    kty: String,
    crv: String,
    x: String,
    y: String,
    /// The private scalar: present only when a client sends its whole key,
    /// which it must never do.
    #[serde(default)]
    d: Option<serde_json::Value>,
}

/// A device's public key: a point of P-256, checked on the curve.
#[derive(Clone)]
pub struct DevicePublicKey {
    key: VerifyingKey,
    x: [u8; 32],
    y: [u8; 32],
}

impl std::fmt::Debug for DevicePublicKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_tuple("DevicePublicKey")
            .field(&self.thumbprint())
            .finish()
    }
}

impl PartialEq for DevicePublicKey {
    fn eq(&self, other: &Self) -> bool {
        self.x == other.x && self.y == other.y
    }
}

impl Eq for DevicePublicKey {}

fn coordinate(encoded: &str) -> Result<[u8; 32], AuthError> {
    let Ok(bytes) = JWK_BASE64.decode(encoded) else {
        return Err(AuthError::InvalidKey(
            "a coordinate is not base64url without padding",
        ));
    };
    <[u8; 32]>::try_from(bytes.as_slice())
        .map_err(|_| AuthError::InvalidKey("a coordinate is not 32 bytes long"))
}

impl DevicePublicKey {
    /// Reads a public JWK: `kty` `EC`, `crv` `P-256`, `x` and `y` in
    /// base64url without padding, 32 bytes each (RFC 7518, section 6.2.1).
    ///
    /// # Errors
    ///
    /// [`AuthError::InvalidKey`] when the text is too long or not a JSON
    /// object, a member is missing or of another value, a coordinate is
    /// malformed, the point is not on the curve, or the JWK carries the
    /// private scalar `d`.
    pub fn from_jwk_json(json: &str) -> Result<Self, AuthError> {
        if json.len() > MAX_JWK_BYTES {
            return Err(AuthError::InvalidKey("the JWK is too long"));
        }
        // serde would also read a struct from a JSON array; a JWK is an
        // object.
        if !json.trim_start().starts_with('{') {
            return Err(AuthError::InvalidKey("the JWK is not a JSON object"));
        }
        let Ok(jwk) = serde_json::from_str::<Jwk>(json) else {
            return Err(AuthError::InvalidKey(
                "the JWK is not an object with string members kty, crv, x and y",
            ));
        };
        if jwk.d.is_some() {
            return Err(AuthError::InvalidKey(
                "the JWK holds a private key; send the public members only",
            ));
        }
        if jwk.kty != "EC" {
            return Err(AuthError::InvalidKey("kty is not EC"));
        }
        if jwk.crv != "P-256" {
            return Err(AuthError::InvalidKey("crv is not P-256"));
        }
        let x = coordinate(&jwk.x)?;
        let y = coordinate(&jwk.y)?;
        Self::from_coordinates(x, y)
    }

    /// Reads the stored form, SEC1 uncompressed (`0x04`, x, y).
    ///
    /// # Errors
    ///
    /// [`AuthError::InvalidKey`] when the bytes are not 65 long, do not
    /// start with `0x04`, or are not a point of the curve.
    pub fn from_sec1(bytes: &[u8]) -> Result<Self, AuthError> {
        let Some((&0x04, xy)) = bytes.split_first() else {
            return Err(AuthError::InvalidKey("not an uncompressed SEC1 point"));
        };
        if xy.len() != 64 {
            return Err(AuthError::InvalidKey("not an uncompressed SEC1 point"));
        }
        let mut x = [0u8; 32];
        let mut y = [0u8; 32];
        x.copy_from_slice(&xy[..32]);
        y.copy_from_slice(&xy[32..]);
        Self::from_coordinates(x, y)
    }

    fn from_coordinates(x: [u8; 32], y: [u8; 32]) -> Result<Self, AuthError> {
        let mut sec1 = [0u8; 65];
        sec1[0] = 0x04;
        sec1[1..33].copy_from_slice(&x);
        sec1[33..].copy_from_slice(&y);
        // The uncompressed form cannot name the point at infinity, and the
        // decoder checks the curve equation.
        let Ok(key) = VerifyingKey::from_sec1_bytes(&sec1) else {
            return Err(AuthError::InvalidKey("the point is not on P-256"));
        };
        Ok(Self { key, x, y })
    }

    /// The stored form: SEC1 uncompressed, 65 bytes.
    #[must_use]
    pub fn sec1_uncompressed(&self) -> [u8; 65] {
        let mut out = [0u8; 65];
        out[0] = 0x04;
        out[1..33].copy_from_slice(&self.x);
        out[33..].copy_from_slice(&self.y);
        out
    }

    /// The RFC 7638 thumbprint: SHA-256 of the required members in
    /// lexicographic order without whitespace, base64url without padding
    /// (43 characters). The same key gives the same thumbprint whatever
    /// member order or optional members the client sent.
    #[must_use]
    pub fn thumbprint(&self) -> String {
        let canonical = format!(
            r#"{{"crv":"P-256","kty":"EC","x":"{}","y":"{}"}}"#,
            JWK_BASE64.encode(self.x),
            JWK_BASE64.encode(self.y)
        );
        JWK_BASE64.encode(Sha256::digest(canonical.as_bytes()))
    }

    /// The public JWK, with its required members only.
    #[must_use]
    pub fn to_jwk_json(&self) -> String {
        format!(
            r#"{{"kty":"EC","crv":"P-256","x":"{}","y":"{}"}}"#,
            JWK_BASE64.encode(self.x),
            JWK_BASE64.encode(self.y)
        )
    }

    /// Checks an ES256 signature (ECDSA P-256 over the SHA-256 of
    /// `message`). `signature` is base64url, padded or not, of either the
    /// raw 64 bytes `r || s` (IEEE P1363, what WebCrypto and JOSE produce)
    /// or the ASN.1 DER sequence (what Android's `SHA256withECDSA`
    /// produces). A 64-byte value is read as raw first and, when it starts
    /// like a sequence, as DER too, since a DER signature can happen to be
    /// 64 bytes long. Both forms of `s` (low and high) are accepted, as
    /// ECDSA defines them: the signers in use do not normalise it.
    ///
    /// # Errors
    ///
    /// [`AuthError::InvalidSignature`] when the text is empty or too long,
    /// not base64url, not a signature in either form, or does not verify.
    pub fn verify(&self, message: &[u8], signature: &str) -> Result<(), AuthError> {
        if signature.is_empty() || signature.len() > MAX_SIGNATURE_CHARS {
            return Err(AuthError::InvalidSignature);
        }
        let Ok(bytes) = SIGNATURE_BASE64.decode(signature) else {
            return Err(AuthError::InvalidSignature);
        };
        let raw = if bytes.len() == 64 {
            Signature::from_slice(&bytes).ok()
        } else {
            None
        };
        let der = if bytes.first() == Some(&0x30) {
            der::parse_signature(&bytes).and_then(|(r, s)| Signature::from_scalars(r, s).ok())
        } else {
            None
        };
        let verified = [raw, der]
            .into_iter()
            .flatten()
            .any(|sig| self.key.verify(message, &sig).is_ok());
        if verified {
            Ok(())
        } else {
            Err(AuthError::InvalidSignature)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The base point of P-256 (SEC 2, section 2.4.2): a valid public key.
    const GX: &str = "6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296";
    const GY: &str = "4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5";

    fn hex32(s: &str) -> [u8; 32] {
        let mut out = [0u8; 32];
        for (i, byte) in out.iter_mut().enumerate() {
            *byte = u8::from_str_radix(&s[2 * i..2 * i + 2], 16).unwrap();
        }
        out
    }

    fn jwk(x: &[u8], y: &[u8]) -> String {
        format!(
            r#"{{"kty":"EC","crv":"P-256","x":"{}","y":"{}"}}"#,
            JWK_BASE64.encode(x),
            JWK_BASE64.encode(y)
        )
    }

    #[test]
    fn a_jwk_round_trips_through_its_stored_form() {
        let key = DevicePublicKey::from_jwk_json(&jwk(&hex32(GX), &hex32(GY))).unwrap();
        let again = DevicePublicKey::from_sec1(&key.sec1_uncompressed()).unwrap();
        assert_eq!(again, key);
        assert_eq!(
            DevicePublicKey::from_jwk_json(&key.to_jwk_json()).unwrap(),
            key
        );
        assert_eq!(key.thumbprint().len(), 43);
    }

    #[test]
    fn the_thumbprint_ignores_member_order_and_optional_members() {
        let x = JWK_BASE64.encode(hex32(GX));
        let y = JWK_BASE64.encode(hex32(GY));
        let a = DevicePublicKey::from_jwk_json(&jwk(&hex32(GX), &hex32(GY))).unwrap();
        let b = DevicePublicKey::from_jwk_json(&format!(
            r#"{{ "y": "{y}", "use": "sig", "x": "{x}", "crv": "P-256", "alg": "ES256", "kty": "EC", "ext": true }}"#
        ))
        .unwrap();
        assert_eq!(
            a.thumbprint(),
            b.thumbprint(),
            "one key is one account, however the client writes its JWK"
        );
    }

    #[test]
    fn malformed_keys_are_refused() {
        let x = hex32(GX);
        let y = hex32(GY);
        let mut off_curve = y;
        off_curve[31] ^= 1;
        let cases = [
            jwk(&x, &off_curve),
            jwk(&x[..31], &y),
            jwk(&x, &[y.as_slice(), &[0]].concat()),
            jwk(&x, &y).replace("P-256", "P-384"),
            jwk(&x, &y).replace(r#""EC""#, r#""RSA""#),
            jwk(&x, &y).replace('}', r#","d":"AAAA"}"#),
            jwk(&x, &y).replace(r#","y":"#, r#","z":"#),
            format!(
                r#"["EC","P-256","{}","{}"]"#,
                JWK_BASE64.encode(x),
                JWK_BASE64.encode(y)
            ),
            format!(
                r#"{{"kty":"EC","crv":"P-256","x":"{}=","y":"{}"}}"#,
                JWK_BASE64.encode(x),
                JWK_BASE64.encode(y)
            ),
            jwk(&x, &y).replace('}', &format!(r#","kid":"{}"}}"#, "a".repeat(2000))),
            String::from("not json"),
            String::new(),
        ];
        for case in &cases {
            assert!(
                DevicePublicKey::from_jwk_json(case).is_err(),
                "must be refused: {case}"
            );
        }
        assert!(DevicePublicKey::from_sec1(&[0x04; 64]).is_err());
        assert!(
            DevicePublicKey::from_sec1(&[0x02; 33]).is_err(),
            "compressed"
        );
    }

    #[test]
    fn signatures_of_other_lengths_or_alphabets_are_refused_without_a_panic() {
        let key = DevicePublicKey::from_jwk_json(&jwk(&hex32(GX), &hex32(GY))).unwrap();
        for sig in [
            "",
            "!!!!",
            &"A".repeat(MAX_SIGNATURE_CHARS + 1),
            &JWK_BASE64.encode([0u8; 64]),
            &JWK_BASE64.encode([0xffu8; 64]),
            &JWK_BASE64.encode([0x30u8; 70]),
        ] {
            assert!(key.verify(b"m", sig).is_err(), "{sig}");
        }
    }
}
