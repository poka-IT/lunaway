//! `schema/auth-vectors.json`: the formats the app's signer and this crate
//! must agree on, replayed case by case, and checked to be exactly what the
//! generator below writes.
//!
//! The signatures are RFC 6979 (deterministic), so the file is reproducible.
//! After a deliberate change of the generator:
//!
//! ```text
//! LUNAWAY_WRITE_AUTH_VECTORS=1 cargo test -p lunaway-auth --test vectors
//! ```

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use base64::{
    Engine,
    engine::general_purpose::{STANDARD_NO_PAD, URL_SAFE, URL_SAFE_NO_PAD},
};
use lunaway_auth::{CHALLENGE_PREFIX, DevicePublicKey, challenge_message};
use p256::{
    ecdsa::{Signature, SigningKey, signature::Signer},
    elliptic_curve::scalar::IsHigh,
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

const VECTORS_PATH: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../../schema/auth-vectors.json"
);

/// A DER signature of key-1 over nonce-1's message made by another
/// implementation (Python `cryptography` 46.0.4, OpenSSL backend, random
/// nonce), so the vectors do not only agree with the code that wrote them.
const EXTERNAL_DER: &str = "MEYCIQC7JeTdGExAE-EbpPrYQ3aOZYCE4kn2RaQncvzP39jyegIhAOzpSg-bEkkAtihPJp5_h1IPtXU7yJS-5EzgigcDJ5VJ";

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn b64(bytes: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(bytes)
}

/// A deterministic private scalar from a label.
fn signing_key(label: &str) -> SigningKey {
    SigningKey::from_slice(&Sha256::digest(label.as_bytes())).unwrap()
}

fn nonce(label: &str) -> String {
    b64(&Sha256::digest(label.as_bytes()))
}

/// The DER form written independently of the parser under test.
fn der(sig: &Signature) -> Vec<u8> {
    let integer = |bytes: &[u8]| {
        let start = bytes
            .iter()
            .position(|b| *b != 0)
            .unwrap_or(bytes.len() - 1);
        let mut v = bytes[start..].to_vec();
        if v[0] & 0x80 != 0 {
            v.insert(0, 0);
        }
        let mut out = vec![0x02, u8::try_from(v.len()).unwrap()];
        out.extend(v);
        out
    };
    let raw = sig.to_bytes();
    let mut body = integer(&raw[..32]);
    body.extend(integer(&raw[32..]));
    let mut out = vec![0x30, u8::try_from(body.len()).unwrap()];
    out.extend(body);
    out
}

fn key_entry(key: &SigningKey) -> Value {
    let d = key.to_bytes();
    let sec1 = key.verifying_key().to_sec1_bytes();
    let public = DevicePublicKey::from_sec1(&sec1).unwrap();
    json!({
        "dHex": hex(&d),
        "dBase64url": b64(&d),
        "jwk": {
            "kty": "EC",
            "crv": "P-256",
            "x": b64(&sec1[1..33]),
            "y": b64(&sec1[33..]),
        },
        "sec1Hex": hex(&sec1),
        "thumbprint": public.thumbprint(),
    })
}

fn jwk_text(x: &str, y: &str) -> String {
    format!(r#"{{"kty":"EC","crv":"P-256","x":"{x}","y":"{y}"}}"#)
}

/// What the file must hold.
fn generate() -> Value {
    let k1 = signing_key("lunaway auth vector key 1");
    let k2 = signing_key("lunaway auth vector key 2");
    let n1 = nonce("lunaway auth vector nonce 1");
    let n2 = nonce("lunaway auth vector nonce 2");
    let m1 = challenge_message(&n1);
    let m2 = challenge_message(&n2);

    let s1: Signature = k1.sign(m1.as_bytes());
    let s2: Signature = k2.sign(m1.as_bytes());
    let s1_other_s = Signature::from_scalars(s1.r(), -s1.s()).unwrap();
    let s1_over_n2: Signature = k1.sign(m2.as_bytes());
    let s1_nonce_only: Signature = k1.sign(n1.as_bytes());
    let s1_over_digest: Signature = k1.sign(&Sha256::digest(m1.as_bytes()));

    let mut padded = URL_SAFE.encode(s1.to_bytes());
    if !padded.ends_with('=') {
        padded.push_str("==");
    }
    // A signature whose base64url holds `-` or `_`, so its standard form
    // differs.
    let standard = [
        s1.to_bytes().to_vec(),
        der(&s1),
        s2.to_bytes().to_vec(),
        der(&s2),
    ]
    .into_iter()
    .find(|b| b64(b).contains(['-', '_']))
    .expect("one of four signatures uses the url-safe characters");
    let mut trailing = der(&s1);
    trailing.push(0);
    let mut non_minimal = der(&s1);
    // Pad r with a zero it does not need: strict DER refuses it.
    let r_len = usize::from(non_minimal[3]);
    if non_minimal[4] == 0 {
        // r already starts with a sign byte; drop it instead, which makes r
        // read as negative.
        non_minimal.remove(4);
        non_minimal[3] = u8::try_from(r_len - 1).unwrap();
        non_minimal[1] -= 1;
    } else {
        non_minimal.insert(4, 0);
        non_minimal[3] = u8::try_from(r_len + 1).unwrap();
        non_minimal[1] += 1;
    }

    let key1 = key_entry(&k1);
    let x1 = key1["jwk"]["x"].as_str().unwrap().to_owned();
    let y1 = key1["jwk"]["y"].as_str().unwrap().to_owned();
    let sec1 = k1.verifying_key().to_sec1_bytes();
    let mut off_curve_y = sec1[33..].to_vec();
    off_curve_y[31] ^= 1;
    let coordinate_with_url_chars = [&x1, &y1]
        .into_iter()
        .find(|c| c.contains(['-', '_']))
        .map(String::as_str);

    let mut invalid_keys = vec![
        json!({"name": "another curve", "reason": "crv must be P-256",
               "jwk": jwk_text(&x1, &y1).replace("P-256", "P-384")}),
        json!({"name": "another key type", "reason": "kty must be EC",
               "jwk": jwk_text(&x1, &y1).replace(r#""EC""#, r#""RSA""#)}),
        json!({"name": "private key sent", "reason": "a JWK carrying d is refused: the private key never leaves the device",
               "jwk": jwk_text(&x1, &y1).replace('}', &format!(r#","d":"{}"}}"#, b64(&k1.to_bytes())))}),
        json!({"name": "x of 31 bytes", "reason": "each coordinate is exactly 32 bytes, leading zeros kept",
               "jwk": jwk_text(&b64(&sec1[2..33]), &y1)}),
        json!({"name": "point not on the curve", "reason": "the point must satisfy the P-256 equation",
               "jwk": jwk_text(&x1, &b64(&off_curve_y))}),
        json!({"name": "coordinates swapped", "reason": "the point must satisfy the P-256 equation",
               "jwk": jwk_text(&y1, &x1)}),
        json!({"name": "x padded", "reason": "base64url without padding (RFC 7515)",
               "jwk": jwk_text(&format!("{x1}="), &y1)}),
        json!({"name": "y missing", "reason": "kty, crv, x and y are required",
               "jwk": format!(r#"{{"kty":"EC","crv":"P-256","x":"{x1}"}}"#)}),
        json!({"name": "not an object", "reason": "a JWK is a JSON object",
               "jwk": format!(r#"["EC","P-256","{x1}","{y1}"]"#)}),
    ];
    if let Some(c) = coordinate_with_url_chars {
        let standard_coordinate = STANDARD_NO_PAD.encode(URL_SAFE_NO_PAD.decode(c).unwrap());
        invalid_keys.push(json!({
            "name": "standard base64 alphabet",
            "reason": "base64url only: - and _ rather than + and /",
            "jwk": jwk_text(&x1, &y1).replace(c, &standard_coordinate),
        }));
    }

    json!({
        "_doc": [
            "Shared vectors of the Lunaway sign-in. The app's signer and backend/crates/lunaway-auth both replay them.",
            "Device key: ECDSA on P-256 with SHA-256 (ES256). The client sends its public key as a JWK with kty \"EC\", crv \"P-256\", x and y; x and y are the 32-byte big-endian coordinates (leading zeros kept) in base64url without padding. Other members (alg, use, kid, key_ops, ext) are ignored; a JWK holding d is refused.",
            "The server identifies a key by its RFC 7638 thumbprint: SHA-256 of {\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"...\",\"y\":\"...\"} (that member order, no whitespace), base64url without padding. The client never sends it.",
            "Message: the UTF-8 bytes of challengePrefix followed by the nonce exactly as authChallenge returned it (43 base64url characters). The device signs those bytes; ES256 hashes them with SHA-256 itself, so the client must not hash them first (see the invalid case 'signed the digest').",
            "Signature, in base64url: the raw 64 bytes r || s (IEEE P1363, what WebCrypto and JOSE produce) is preferred; ASN.1 DER (what Android's SHA256withECDSA produces) is accepted. Padding is tolerated on signatures; the standard base64 alphabet (+ and /) is not. Both forms of s (low and high) verify.",
            "keys: two fixed key pairs (d is a test value, never a real key). validSignatures must verify, invalidSignatures and invalidKeys must be refused, each with its reason.",
            "Regenerate after a deliberate change: LUNAWAY_WRITE_AUTH_VECTORS=1 cargo test -p lunaway-auth --test vectors (from backend/)."
        ],
        "version": 1,
        "challengePrefix": CHALLENGE_PREFIX,
        "keys": {
            "key-1": key1,
            "key-2": key_entry(&k2),
        },
        "nonces": {
            "nonce-1": n1,
            "nonce-2": n2,
        },
        "messages": {
            "nonce-1": m1,
            "nonce-2": m2,
        },
        "validSignatures": [
            {"name": "key-1 raw", "key": "key-1", "message": m1, "encoding": "raw",
             "signature": b64(&s1.to_bytes())},
            {"name": "key-1 der", "key": "key-1", "message": m1, "encoding": "der",
             "signature": b64(&der(&s1))},
            {"name": "key-1 raw, the other s", "key": "key-1", "message": m1, "encoding": "raw",
             "note": format!("n - s of 'key-1 raw' (s is {}): ECDSA accepts both, signers do not normalise", if bool::from(s1.s().is_high()) { "high there, low here" } else { "low there, high here" }),
             "signature": b64(&s1_other_s.to_bytes())},
            {"name": "key-1 raw, padded", "key": "key-1", "message": m1, "encoding": "raw",
             "note": "Dart's base64Url pads by default; the server tolerates it",
             "signature": padded},
            {"name": "key-1 der from another implementation", "key": "key-1", "message": m1, "encoding": "der",
             "note": "Python cryptography (OpenSSL), random nonce",
             "signature": EXTERNAL_DER},
            {"name": "key-2 raw", "key": "key-2", "message": m1, "encoding": "raw",
             "signature": b64(&s2.to_bytes())},
            {"name": "key-2 der", "key": "key-2", "message": m1, "encoding": "der",
             "signature": b64(&der(&s2))},
        ],
        "invalidSignatures": [
            {"name": "signed another nonce", "key": "key-1", "message": m1,
             "reason": "a signature answers one nonce only",
             "signature": b64(&s1_over_n2.to_bytes())},
            {"name": "signed by the other key", "key": "key-1", "message": m1,
             "reason": "made by key-2",
             "signature": b64(&s2.to_bytes())},
            {"name": "signed the nonce without the prefix", "key": "key-1", "message": m1,
             "reason": "the message is challengePrefix + nonce",
             "signature": b64(&s1_nonce_only.to_bytes())},
            {"name": "signed the digest", "key": "key-1", "message": m1,
             "reason": "the client hashed the message before an ES256 signer that hashes again",
             "signature": b64(&s1_over_digest.to_bytes())},
            {"name": "truncated", "key": "key-1", "message": m1,
             "reason": "63 bytes: neither raw nor DER",
             "signature": b64(&s1.to_bytes()[..63])},
            {"name": "standard base64 alphabet", "key": "key-1", "message": m1,
             "reason": "base64url only",
             "signature": STANDARD_NO_PAD.encode(&standard)},
            {"name": "zero scalars", "key": "key-1", "message": m1,
             "reason": "r and s must be in 1..n-1",
             "signature": b64(&[0u8; 64])},
            {"name": "der with a trailing byte", "key": "key-1", "message": m1,
             "reason": "strict DER: nothing after the sequence",
             "signature": b64(&trailing)},
            {"name": "der with a non-minimal integer", "key": "key-1", "message": m1,
             "reason": "strict DER: minimal positive integers",
             "signature": b64(&non_minimal)},
            {"name": "empty", "key": "key-1", "message": m1,
             "reason": "no signature",
             "signature": ""},
        ],
        "invalidKeys": invalid_keys,
    })
}

fn committed() -> Value {
    let text = std::fs::read_to_string(VECTORS_PATH).expect("schema/auth-vectors.json exists");
    serde_json::from_str(&text).unwrap()
}

#[test]
fn the_committed_vectors_are_what_the_generator_writes() {
    let generated = generate();
    if std::env::var_os("LUNAWAY_WRITE_AUTH_VECTORS").is_some() {
        let mut text = serde_json::to_string_pretty(&generated).unwrap();
        text.push('\n');
        std::fs::write(VECTORS_PATH, text).unwrap();
    }
    assert_eq!(
        committed(),
        generated,
        "schema/auth-vectors.json is stale; regenerate it (see the top of this file)"
    );
}

fn key_of(v: &Value, name: &str) -> DevicePublicKey {
    let jwk = serde_json::to_string(&v["keys"][name]["jwk"]).unwrap();
    DevicePublicKey::from_jwk_json(&jwk).unwrap()
}

#[test]
fn every_valid_signature_verifies() {
    let v = committed();
    let cases = v["validSignatures"].as_array().unwrap();
    assert!(cases.len() >= 7);
    for case in cases {
        let key = key_of(&v, case["key"].as_str().unwrap());
        let message = case["message"].as_str().unwrap();
        assert!(message.starts_with(CHALLENGE_PREFIX));
        key.verify(message.as_bytes(), case["signature"].as_str().unwrap())
            .unwrap_or_else(|e| panic!("{}: {e}", case["name"]));
    }
}

#[test]
fn every_invalid_signature_is_refused() {
    let v = committed();
    let cases = v["invalidSignatures"].as_array().unwrap();
    assert!(cases.len() >= 10);
    for case in cases {
        let key = key_of(&v, case["key"].as_str().unwrap());
        let message = case["message"].as_str().unwrap();
        assert!(
            key.verify(message.as_bytes(), case["signature"].as_str().unwrap())
                .is_err(),
            "must be refused: {} ({})",
            case["name"],
            case["reason"]
        );
    }
}

#[test]
fn every_invalid_key_is_refused() {
    let v = committed();
    let cases = v["invalidKeys"].as_array().unwrap();
    assert!(cases.len() >= 9);
    for case in cases {
        assert!(
            DevicePublicKey::from_jwk_json(case["jwk"].as_str().unwrap()).is_err(),
            "must be refused: {} ({})",
            case["name"],
            case["reason"]
        );
    }
}

#[test]
fn the_keys_of_the_file_are_the_code_s_keys() {
    let v = committed();
    for (name, entry) in v["keys"].as_object().unwrap() {
        let key = key_of(&v, name);
        assert_eq!(
            key.thumbprint(),
            entry["thumbprint"].as_str().unwrap(),
            "{name}: the account of a key is found by this thumbprint"
        );
        assert_eq!(
            hex(&key.sec1_uncompressed()),
            entry["sec1Hex"].as_str().unwrap()
        );
        let d = URL_SAFE_NO_PAD
            .decode(entry["dBase64url"].as_str().unwrap())
            .unwrap();
        assert_eq!(hex(&d), entry["dHex"].as_str().unwrap());
        let public = SigningKey::from_slice(&d)
            .unwrap()
            .verifying_key()
            .to_sec1_bytes();
        assert_eq!(
            DevicePublicKey::from_sec1(&public).unwrap(),
            key,
            "{name}: d and the JWK are one key pair"
        );
    }
    for (name, message) in v["messages"].as_object().unwrap() {
        assert_eq!(
            message.as_str().unwrap(),
            challenge_message(v["nonces"][name].as_str().unwrap())
        );
    }
}
