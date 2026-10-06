//! The ASN.1 DER form of an ECDSA signature, `SEQUENCE { INTEGER r,
//! INTEGER s }`, which Android's `SHA256withECDSA` returns. Read here
//! rather than through the `der` crate: two integers are all there is, and
//! the strict rules fit in a page.

/// The two scalars of a DER signature, as 32 big-endian bytes each, or
/// `None` when the encoding is not strict DER: long-form lengths (a P-256
/// signature is at most 72 bytes, so they are never needed), a negative or
/// non-minimal integer, an integer over 32 bytes, or bytes after the
/// sequence. Whether the scalars are in range is the verifier's business.
pub(crate) fn parse_signature(der: &[u8]) -> Option<([u8; 32], [u8; 32])> {
    let (body, rest) = take(der, 0x30)?;
    if !rest.is_empty() {
        return None;
    }
    let (r, after_r) = take(body, 0x02)?;
    let (s, after_s) = take(after_r, 0x02)?;
    if !after_s.is_empty() {
        return None;
    }
    Some((integer(r)?, integer(s)?))
}

/// One tag-length-value of `tag` at the start of `input`: its value and
/// what follows it.
fn take(input: &[u8], tag: u8) -> Option<(&[u8], &[u8])> {
    let (&t, rest) = input.split_first()?;
    if t != tag {
        return None;
    }
    let (&len, rest) = rest.split_first()?;
    if len >= 0x80 {
        return None;
    }
    let len = usize::from(len);
    (rest.len() >= len).then(|| rest.split_at(len))
}

/// A positive DER integer, left-padded to 32 bytes.
fn integer(bytes: &[u8]) -> Option<[u8; 32]> {
    let (&first, tail) = bytes.split_first()?;
    if first & 0x80 != 0 {
        // A negative number: never a scalar.
        return None;
    }
    let value = match tail.first() {
        // A leading zero is allowed only to keep the next byte's high bit
        // from reading as a sign.
        Some(&next) if first == 0 => {
            if next & 0x80 == 0 {
                return None;
            }
            tail
        }
        _ => bytes,
    };
    if value.len() > 32 {
        return None;
    }
    let mut out = [0u8; 32];
    out[32 - value.len()..].copy_from_slice(value);
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn der(r: &[u8], s: &[u8]) -> Vec<u8> {
        let mut body = vec![0x02, u8::try_from(r.len()).unwrap()];
        body.extend_from_slice(r);
        body.extend([0x02, u8::try_from(s.len()).unwrap()]);
        body.extend_from_slice(s);
        let mut out = vec![0x30, u8::try_from(body.len()).unwrap()];
        out.extend(body);
        out
    }

    #[test]
    fn strict_der_is_read() {
        let mut high = [0x11; 32];
        high[0] = 0x80;
        let mut r_padded = vec![0x00];
        r_padded.extend_from_slice(&high);
        let (r, s) = parse_signature(&der(&r_padded, &[0x01, 0x02])).unwrap();
        assert_eq!(r, high, "the sign byte is dropped");
        let mut expected_s = [0u8; 32];
        expected_s[30..].copy_from_slice(&[0x01, 0x02]);
        assert_eq!(s, expected_s, "a short integer is left-padded");
    }

    #[test]
    fn loose_encodings_are_refused() {
        let ok = der(&[0x01], &[0x02]);
        assert!(parse_signature(&ok).is_some());
        let mut trailing = ok.clone();
        trailing.push(0);
        assert!(
            parse_signature(&trailing).is_none(),
            "bytes after the sequence"
        );
        assert!(
            parse_signature(&der(&[0x00, 0x01], &[0x02])).is_none(),
            "a leading zero before a byte without the high bit"
        );
        assert!(
            parse_signature(&der(&[0x81], &[0x02])).is_none(),
            "a negative integer"
        );
        assert!(
            parse_signature(&der(&[0x01; 33], &[0x02])).is_none(),
            "33 bytes of value"
        );
        assert!(
            parse_signature(&der(&[], &[0x02])).is_none(),
            "an empty integer"
        );
        assert!(
            parse_signature(&[0x30, 0x81, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01]).is_none(),
            "a long-form length"
        );
        assert!(parse_signature(&ok[..ok.len() - 1]).is_none(), "truncated");
        assert!(parse_signature(&[]).is_none());
    }
}
