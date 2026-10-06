//! The photo pipeline: an upload is decoded within bounds, turned upright,
//! re-encoded from its pixels (so no metadata survives), resized, and
//! stored under a content-addressed path.
//!
//! Nothing of the uploaded file reaches the disk: [`process`] decodes it to
//! pixels and encodes new files from them, so EXIF (the GPS position of the
//! phone included), XMP, ICC profiles and comments are gone by construction,
//! not by a stripping step that could miss a block. The encoder is lossy
//! WebP (libwebp), which every app platform and browser decodes.
//!
//! [`process`] is CPU work of up to a second on a phone-sized picture: the
//! caller runs it on a blocking thread. [`MediaStore`] writes the results
//! where the web server serves them (`/media/` on the API host maps to the
//! media root).

mod pipeline;
mod store;

pub use pipeline::process;
pub use store::MediaStore;

/// Bounds on an upload, checked before any pixel is allocated.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Limits {
    /// Largest file accepted, bytes.
    pub max_bytes: usize,
    /// Widest image accepted, pixels.
    pub max_width: u32,
    /// Tallest image accepted, pixels.
    pub max_height: u32,
    /// Most pixels accepted (width times height).
    pub max_pixels: u64,
    /// Most memory a decoder may allocate, bytes: a second guard behind the
    /// dimension checks, for what a header does not announce.
    pub max_alloc: u64,
}

impl Default for Limits {
    /// 10 MiB, 12 000 pixels a side, 50 megapixels (a 48 MP phone sensor
    /// fits), 512 MiB of decoder memory.
    fn default() -> Self {
        Self {
            max_bytes: 10 * 1024 * 1024,
            max_width: 12_000,
            max_height: 12_000,
            max_pixels: 50_000_000,
            max_alloc: 512 * 1024 * 1024,
        }
    }
}

/// Long side of the stored photo, pixels; a smaller photo keeps its size.
pub const FULL_LONG_SIDE: u32 = 2048;
/// Long side of the thumbnail, pixels.
pub const THUMB_LONG_SIDE: u32 = 512;
/// Extension of every stored file.
pub const EXTENSION: &str = "webp";
/// Content type of every stored file.
pub const CONTENT_TYPE: &str = "image/webp";

/// The format an upload arrived in, read from its first bytes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SourceFormat {
    /// JPEG (`FF D8 FF`).
    Jpeg,
    /// PNG (the eight-byte PNG signature).
    Png,
    /// WebP (`RIFF`, a size, `WEBP`).
    WebP,
}

impl SourceFormat {
    /// The format of `bytes`, from their signature only: what a client says
    /// the file is never counts.
    #[must_use]
    pub fn sniff(bytes: &[u8]) -> Option<Self> {
        if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
            Some(Self::Jpeg)
        } else if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
            Some(Self::Png)
        } else if bytes.len() >= 12 && bytes.starts_with(b"RIFF") && &bytes[8..12] == b"WEBP" {
            Some(Self::WebP)
        } else {
            None
        }
    }
}

/// One encoded file, named by the SHA-256 of its bytes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Encoded {
    /// The file.
    pub bytes: Vec<u8>,
    /// Width, pixels.
    pub width: u32,
    /// Height, pixels.
    pub height: u32,
    /// SHA-256 of `bytes`, lower-case hexadecimal.
    pub sha256_hex: String,
}

impl Encoded {
    /// Where the file lives under the media root:
    /// `photos/<2 hex>/<2 hex>/<sha256>.webp`. Two levels of 256 shards keep
    /// every directory small, and the same picture always lands on the same
    /// path, so storing it twice writes nothing.
    #[must_use]
    pub fn relative_path(&self) -> String {
        let h = &self.sha256_hex;
        // `get` rather than indexing: a hash edited by hand yields a path
        // the store refuses, not a panic.
        format!(
            "photos/{}/{}/{h}.{EXTENSION}",
            h.get(..2).unwrap_or_default(),
            h.get(2..4).unwrap_or_default()
        )
    }
}

/// What [`process`] makes of an upload.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Processed {
    /// The photo, at most [`FULL_LONG_SIDE`] on its long side.
    pub full: Encoded,
    /// The thumbnail, at most [`THUMB_LONG_SIDE`] on its long side.
    pub thumb: Encoded,
    /// A ThumbHash of the photo (about 25 bytes): the placeholder the app
    /// paints while the thumbnail downloads.
    pub thumbhash: Vec<u8>,
    /// The format the upload arrived in.
    pub source: SourceFormat,
}

/// Why the encoder failed.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
#[non_exhaustive]
pub enum EncodeFailure {
    /// libwebp refused its default configuration.
    #[error("the WebP encoder could not be configured")]
    Configuration,
    /// libwebp returned an error code.
    #[error("the WebP encoder failed: {0:?}")]
    Encoder(webp::WebPEncodingError),
}

/// What can go wrong with an upload or with the media directory.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum MediaError {
    /// The file is larger than [`Limits::max_bytes`].
    #[error("the file holds {size} bytes, more than the {max} allowed")]
    TooLarge {
        /// Bytes received.
        size: usize,
        /// Bytes allowed.
        max: usize,
    },
    /// The file is not a JPEG, a PNG or a WebP.
    #[error("only JPEG, PNG and WebP images are accepted")]
    Unsupported,
    /// The file claims a supported format but does not decode.
    #[error("the image cannot be decoded")]
    Malformed(#[source] image::ImageError),
    /// The image is wider, taller or larger than [`Limits`] allows.
    #[error("the image measures {width} x {height} pixels, more than allowed")]
    DimensionsTooLarge {
        /// Width announced by the file.
        width: u32,
        /// Height announced by the file.
        height: u32,
    },
    /// Decoding would allocate more than [`Limits::max_alloc`].
    #[error("decoding the image would need more memory than allowed")]
    TooMuchMemory(#[source] image::ImageError),
    /// The pixels could not be encoded.
    #[error("the image cannot be encoded")]
    Encode(#[source] EncodeFailure),
    /// Reading or writing the media directory failed.
    #[error("media storage failed")]
    Io(#[source] std::io::Error),
    /// A path that this crate never produces (another shape, a traversal).
    #[error("not a media path")]
    InvalidPath,
}

impl MediaError {
    /// Whether the uploader caused the failure (size, format, content,
    /// dimensions), as opposed to the server.
    #[must_use]
    pub fn is_client_error(&self) -> bool {
        matches!(
            self,
            Self::TooLarge { .. }
                | Self::Unsupported
                | Self::Malformed(_)
                | Self::DimensionsTooLarge { .. }
                | Self::TooMuchMemory(_)
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_are_read_from_the_signature() {
        assert_eq!(
            SourceFormat::sniff(&[0xFF, 0xD8, 0xFF, 0xE0]),
            Some(SourceFormat::Jpeg)
        );
        assert_eq!(
            SourceFormat::sniff(b"\x89PNG\r\n\x1a\n...."),
            Some(SourceFormat::Png)
        );
        assert_eq!(
            SourceFormat::sniff(b"RIFF\x10\x00\x00\x00WEBPVP8 "),
            Some(SourceFormat::WebP)
        );
        for other in [
            &b"GIF89a"[..],
            b"\x00\x00\x00\x18ftypheic",
            b"<svg",
            b"RIFF\x10\x00\x00\x00WAVE",
            b"",
        ] {
            assert_eq!(SourceFormat::sniff(other), None, "{other:?}");
        }
    }

    #[test]
    fn a_path_is_sharded_by_the_hash() {
        let e = Encoded {
            bytes: Vec::new(),
            width: 1,
            height: 1,
            sha256_hex: "ab".repeat(32),
        };
        let path = e.relative_path();
        assert_eq!(path, format!("photos/ab/ab/{}.webp", "ab".repeat(32)));
        assert!(MediaStore::is_valid_relative_path(&path));
    }
}
