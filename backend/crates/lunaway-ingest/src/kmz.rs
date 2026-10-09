//! The KML document of a KMZ archive (a ZIP file, `doc.kml` and its
//! styles): Ireland's Garda zones are published so. The archive is read by
//! its central directory, which knows each entry's sizes even when a local
//! header defers them; only stored and deflated entries are read, and the
//! document is inflated up to a bound, so an archive cannot grow past it.

use std::io::Read as _;

use crate::IngestError;

/// Largest KML read: the Garda's current zones weigh 6.3 MB once inflated
/// (2026-10-09).
const MAX_KML_BYTES: u64 = 64 * 1024 * 1024;
/// Signature of the end of the central directory.
const EOCD: [u8; 4] = [0x50, 0x4b, 0x05, 0x06];
/// Signature of a central directory entry.
const CENTRAL: [u8; 4] = [0x50, 0x4b, 0x01, 0x02];
/// Signature of a local file header.
const LOCAL: [u8; 4] = [0x50, 0x4b, 0x03, 0x04];

fn bad(what: &str) -> IngestError {
    IngestError::Implausible {
        what: format!("KMZ archive: {what}"),
    }
}

fn u16_at(b: &[u8], at: usize) -> Option<usize> {
    let s = b.get(at..at + 2)?;
    Some(usize::from(u16::from_le_bytes([s[0], s[1]])))
}

fn u32_at(b: &[u8], at: usize) -> Option<usize> {
    let s = b.get(at..at + 4)?;
    usize::try_from(u32::from_le_bytes([s[0], s[1], s[2], s[3]])).ok()
}

/// The first `.kml` entry of the archive `kmz`, as text.
///
/// # Errors
///
/// [`IngestError::Implausible`] when the archive does not read, holds no
/// KML, compresses it otherwise than by deflate, or inflates it past
/// [`MAX_KML_BYTES`].
pub fn kml_of(kmz: &[u8]) -> Result<String, IngestError> {
    // The end of the central directory: 22 bytes and a comment of up to
    // 65 535 bytes at the end of the file.
    let from = kmz.len().saturating_sub(22 + 65_535);
    let eocd = (from..kmz.len().saturating_sub(21))
        .rev()
        .find(|i| kmz.get(*i..*i + 4) == Some(&EOCD[..]))
        .ok_or_else(|| bad("no end of central directory"))?;
    let entries = u16_at(kmz, eocd + 10).ok_or_else(|| bad("truncated"))?;
    let mut at = u32_at(kmz, eocd + 16).ok_or_else(|| bad("truncated"))?;
    for _ in 0..entries {
        if kmz.get(at..at + 4) != Some(&CENTRAL[..]) {
            return Err(bad("a central directory entry does not read"));
        }
        let field = |offset: usize| u16_at(kmz, at + offset).ok_or_else(|| bad("truncated"));
        let method = field(10)?;
        let compressed = u32_at(kmz, at + 20).ok_or_else(|| bad("truncated"))?;
        let (name_len, extra_len, comment_len) = (field(28)?, field(30)?, field(32)?);
        let local = u32_at(kmz, at + 42).ok_or_else(|| bad("truncated"))?;
        let name = kmz
            .get(at + 46..at + 46 + name_len)
            .ok_or_else(|| bad("truncated"))?;
        at += 46 + name_len + extra_len + comment_len;
        if !name.to_ascii_lowercase().ends_with(b".kml") {
            continue;
        }
        if kmz.get(local..local + 4) != Some(&LOCAL[..]) {
            return Err(bad("a local header does not read"));
        }
        let start = local
            + 30
            + u16_at(kmz, local + 26).ok_or_else(|| bad("truncated"))?
            + u16_at(kmz, local + 28).ok_or_else(|| bad("truncated"))?;
        let data = kmz
            .get(start..start + compressed)
            .ok_or_else(|| bad("an entry runs past the archive"))?;
        let mut out = Vec::new();
        let read = match method {
            0 => data.take(MAX_KML_BYTES + 1).read_to_end(&mut out),
            8 => flate2::read::DeflateDecoder::new(data)
                .take(MAX_KML_BYTES + 1)
                .read_to_end(&mut out),
            _ => return Err(bad("a KML compressed otherwise than by deflate")),
        };
        read.map_err(|_| bad("the KML does not inflate"))?;
        if u64::try_from(out.len()).unwrap_or(u64::MAX) > MAX_KML_BYTES {
            return Err(bad("the KML inflates past its bound"));
        }
        return String::from_utf8(out).map_err(|_| bad("the KML is not UTF-8"));
    }
    Err(bad("no KML in the archive"))
}

#[cfg(test)]
mod tests {
    use std::io::Write as _;

    use super::*;

    /// A one-entry archive of `name` holding `body`, deflated.
    fn zip(name: &str, body: &[u8]) -> Vec<u8> {
        let mut deflated =
            flate2::write::DeflateEncoder::new(Vec::new(), flate2::Compression::default());
        deflated.write_all(body).unwrap();
        let data = deflated.finish().unwrap();
        let size = |n: usize| u32::try_from(n).unwrap().to_le_bytes();
        let mut out = Vec::new();
        out.extend(LOCAL);
        out.extend([20, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
        out.extend(size(data.len()));
        out.extend(size(body.len()));
        out.extend(u16::try_from(name.len()).unwrap().to_le_bytes());
        out.extend([0, 0]);
        out.extend(name.as_bytes());
        out.extend(&data);
        let central = out.len();
        out.extend(CENTRAL);
        out.extend([20, 0, 20, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
        out.extend(size(data.len()));
        out.extend(size(body.len()));
        out.extend(u16::try_from(name.len()).unwrap().to_le_bytes());
        out.extend([0; 12]);
        out.extend(size(0));
        out.extend(name.as_bytes());
        let central_len = out.len() - central;
        out.extend(EOCD);
        out.extend([0, 0, 0, 0, 1, 0, 1, 0]);
        out.extend(size(central_len));
        out.extend(size(central));
        out.extend([0, 0]);
        out
    }

    #[test]
    fn the_kml_of_an_archive_reads_and_nothing_else_does() {
        let kml = "<kml><Placemark><name>1</name></Placemark></kml>";
        assert_eq!(kml_of(&zip("doc.kml", kml.as_bytes())).unwrap(), kml);
        assert!(kml_of(&zip("style.xsl", b"x")).is_err(), "no KML in it");
        assert!(kml_of(b"not an archive").is_err());
        let mut cut = zip("doc.kml", kml.as_bytes());
        cut.truncate(40);
        assert!(kml_of(&cut).is_err(), "a truncated archive");
    }
}
