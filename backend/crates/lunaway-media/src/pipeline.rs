//! Decoding within bounds, orientation, resizing and encoding.

use std::io::Cursor;

use image::{
    DynamicImage, ImageDecoder, ImageError, ImageFormat, ImageReader, RgbImage, imageops,
    imageops::FilterType,
};
use sha2::{Digest, Sha256};

use crate::{
    EncodeFailure, Encoded, FULL_LONG_SIDE, Limits, MediaError, Processed, SourceFormat,
    THUMB_LONG_SIDE,
};

/// Quality of the stored photo (libwebp scale, 0 to 100): close to the
/// source on a phone screen at a fraction of its size.
const FULL_QUALITY: f32 = 80.0;
/// Quality of the thumbnail, seen small in lists.
const THUMB_QUALITY: f32 = 75.0;
/// Long side of the picture a ThumbHash is computed from: the format takes
/// at most 100 pixels a side.
const THUMBHASH_LONG_SIDE: u32 = 100;

/// Turns an upload into the stored photo, its thumbnail and its ThumbHash.
///
/// The checks run cheapest first: the size of the file, its signature, the
/// dimensions its header announces (a decompression bomb is refused here,
/// before a pixel is allocated), then the decoder runs with an allocation
/// limit. The image is turned upright from its EXIF orientation, flattened
/// onto white, resized and encoded anew: no byte of the upload's metadata
/// can reach the output.
///
/// # Errors
///
/// [`MediaError::TooLarge`], [`MediaError::Unsupported`],
/// [`MediaError::DimensionsTooLarge`], [`MediaError::Malformed`] and
/// [`MediaError::TooMuchMemory`] for what the uploader sent;
/// [`MediaError::Encode`] when the encoder fails.
pub fn process(input: &[u8], limits: &Limits) -> Result<Processed, MediaError> {
    if input.len() > limits.max_bytes {
        return Err(MediaError::TooLarge {
            size: input.len(),
            max: limits.max_bytes,
        });
    }
    let source = SourceFormat::sniff(input).ok_or(MediaError::Unsupported)?;
    if source == SourceFormat::Jpeg && !jpeg_has_end(input) {
        // The JPEG decoder is lenient and paints what is missing grey: a cut
        // upload would be published half grey.
        return Err(MediaError::Malformed(ImageError::Decoding(
            image::error::DecodingError::new(
                image::error::ImageFormatHint::Exact(ImageFormat::Jpeg),
                "the file ends before its end-of-image marker",
            ),
        )));
    }
    let upright = decode_upright(input, source, limits)?;
    let pixels = flatten_onto_white(upright);

    // The decoded picture is released as soon as its reduction exists: the
    // two never need to be held longer than the resize.
    let full_pixels = match fit(&pixels, FULL_LONG_SIDE, FilterType::Lanczos3) {
        Some(reduced) => {
            drop(pixels);
            reduced
        }
        None => pixels,
    };
    // The thumbnail and the hash come from the already reduced picture:
    // the result is the same to the eye and the work is a fraction.
    let thumb_pixels = fit(&full_pixels, THUMB_LONG_SIDE, FilterType::Lanczos3)
        .unwrap_or_else(|| full_pixels.clone());
    let thumbhash = thumbhash_of(&thumb_pixels);
    Ok(Processed {
        full: encode(&full_pixels, FULL_QUALITY)?,
        thumb: encode(&thumb_pixels, THUMB_QUALITY)?,
        thumbhash,
        source,
    })
}

/// Whether a JPEG reaches its end-of-image marker after its first scan.
/// The header segments are skipped by their lengths (an EXIF thumbnail
/// holds its own end marker); in the scan data a `FF` byte is always
/// followed by `00` or a restart marker, so `FF D9` there is the real end.
/// Bytes after it (a phone's motion clip) are allowed: the decoder stops at
/// the marker and nothing of them reaches the output.
fn jpeg_has_end(bytes: &[u8]) -> bool {
    let mut at = 2;
    loop {
        let (Some(&0xFF), Some(&marker)) = (bytes.get(at), bytes.get(at + 1)) else {
            return false;
        };
        match marker {
            // Fill bytes before a marker.
            0xFF => at += 1,
            // Start of scan: the end marker must follow somewhere.
            0xDA => {
                return bytes
                    .get(at + 2..)
                    .is_some_and(|rest| rest.windows(2).any(|w| w == [0xFF, 0xD9]));
            }
            // A marker without a length.
            0x01 | 0xD0..=0xD8 => at += 2,
            _ => {
                let (Some(&hi), Some(&lo)) = (bytes.get(at + 2), bytes.get(at + 3)) else {
                    return false;
                };
                at += 2 + usize::from(u16::from_be_bytes([hi, lo]));
            }
        }
    }
}

fn image_format(source: SourceFormat) -> ImageFormat {
    match source {
        SourceFormat::Jpeg => ImageFormat::Jpeg,
        SourceFormat::Png => ImageFormat::Png,
        SourceFormat::WebP => ImageFormat::WebP,
    }
}

fn decode_error(e: ImageError) -> MediaError {
    match e {
        ImageError::Limits(_) => MediaError::TooMuchMemory(e),
        ImageError::Unsupported(_) => MediaError::Unsupported,
        other => MediaError::Malformed(other),
    }
}

/// Decodes `input` and applies its orientation, refusing dimensions over
/// `limits` from the header alone.
fn decode_upright(
    input: &[u8],
    source: SourceFormat,
    limits: &Limits,
) -> Result<DynamicImage, MediaError> {
    let mut reader = ImageReader::with_format(Cursor::new(input), image_format(source));
    // Only the allocation bound while the header is read: the dimension
    // check below wants the announced size to report it.
    let mut alloc_only = image::Limits::default();
    alloc_only.max_alloc = Some(limits.max_alloc);
    reader.limits(alloc_only);
    let mut decoder = reader.into_decoder().map_err(decode_error)?;
    let (width, height) = decoder.dimensions();
    let pixels = u64::from(width) * u64::from(height);
    if width > limits.max_width || height > limits.max_height || pixels > limits.max_pixels {
        return Err(MediaError::DimensionsTooLarge { width, height });
    }
    if width == 0 || height == 0 {
        return Err(MediaError::DimensionsTooLarge { width, height });
    }
    let mut strict = image::Limits::default();
    strict.max_image_width = Some(limits.max_width);
    strict.max_image_height = Some(limits.max_height);
    strict.max_alloc = Some(limits.max_alloc);
    // The output buffer counts against the allocation bound, as in
    // `ImageReader::decode`: decoding through `into_decoder` skips that step.
    strict
        .reserve(decoder.total_bytes())
        .map_err(decode_error)?;
    decoder.set_limits(strict).map_err(decode_error)?;
    // A broken EXIF block does not make the picture unusable: it is shown as
    // stored rather than refused.
    let orientation = decoder
        .orientation()
        .unwrap_or(image::metadata::Orientation::NoTransforms);
    let mut image = DynamicImage::from_decoder(decoder).map_err(decode_error)?;
    image.apply_orientation(orientation);
    Ok(image)
}

/// 8-bit RGB, transparent areas painted white: a photo of a place has no
/// transparency worth keeping, and a transparent pixel's colour is
/// undefined, so resizing it as is would bleed that colour into its
/// neighbours.
fn flatten_onto_white(image: DynamicImage) -> RgbImage {
    if !image.color().has_alpha() {
        return image.into_rgb8();
    }
    let rgba = image.into_rgba8();
    let (w, h) = rgba.dimensions();
    let mut out = RgbImage::new(w, h);
    for (src, dst) in rgba.pixels().zip(out.pixels_mut()) {
        let [r, g, b, a] = src.0;
        let a = u16::from(a);
        let blend = |c: u8| {
            // (c * a + 255 * (255 - a)) / 255, rounded; at most 255.
            let v = (u16::from(c) * a + 255 * (255 - a) + 127) / 255;
            u8::try_from(v).unwrap_or(u8::MAX)
        };
        dst.0 = [blend(r), blend(g), blend(b)];
    }
    out
}

/// Width and height that fit `long_side` with the aspect ratio of
/// `(width, height)`, never larger than the input.
fn fitted(width: u32, height: u32, long_side: u32) -> (u32, u32) {
    let long = width.max(height);
    if long <= long_side {
        return (width, height);
    }
    let scale = |side: u32| {
        let scaled =
            (u64::from(side) * u64::from(long_side) + u64::from(long) / 2) / u64::from(long);
        u32::try_from(scaled).unwrap_or(long_side).max(1)
    };
    (scale(width), scale(height))
}

/// `image` reduced to fit `long_side`; `None` when it already fits, so the
/// caller keeps the buffer it has instead of a copy.
fn fit(image: &RgbImage, long_side: u32, filter: FilterType) -> Option<RgbImage> {
    let (w, h) = image.dimensions();
    let (fw, fh) = fitted(w, h, long_side);
    ((fw, fh) != (w, h)).then(|| imageops::resize(image, fw, fh, filter))
}

fn thumbhash_of(image: &RgbImage) -> Vec<u8> {
    let small =
        fit(image, THUMBHASH_LONG_SIDE, FilterType::Triangle).unwrap_or_else(|| image.clone());
    let rgba = DynamicImage::ImageRgb8(small).into_rgba8();
    let (w, h) = rgba.dimensions();
    thumbhash::rgba_to_thumb_hash(
        usize::try_from(w).unwrap_or(1),
        usize::try_from(h).unwrap_or(1),
        rgba.as_raw(),
    )
}

/// Lossy WebP of `image`, with no metadata chunk: libwebp writes only what
/// it is given, and it is given pixels.
fn encode(image: &RgbImage, quality: f32) -> Result<Encoded, MediaError> {
    let (width, height) = image.dimensions();
    let mut config =
        webp::WebPConfig::new().map_err(|()| MediaError::Encode(EncodeFailure::Configuration))?;
    config.lossless = 0;
    config.quality = quality;
    // Method 4 is libwebp's default balance of speed and size.
    config.method = 4;
    let memory = webp::Encoder::from_rgb(image.as_raw(), width, height)
        .encode_advanced(&config)
        .map_err(|e| MediaError::Encode(EncodeFailure::Encoder(e)))?;
    let bytes = memory.to_vec();
    let sha256_hex = Sha256::digest(&bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();
    Ok(Encoded {
        bytes,
        width,
        height,
        sha256_hex,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_jpeg_is_complete_only_with_its_end_marker_after_the_scan() {
        // SOI, an APP1 segment holding a thumbnail's end marker, SOS, data.
        let mut cut = vec![0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x06, 0xFF, 0xD9, 0x00, 0x00];
        cut.extend([0xFF, 0xDA, 0x00, 0x02, 0x12, 0xFF, 0x00, 0x34]);
        assert!(
            !jpeg_has_end(&cut),
            "the thumbnail's end marker does not end the file"
        );
        let mut whole = cut.clone();
        whole.extend([0xFF, 0xD9]);
        assert!(jpeg_has_end(&whole));
        let mut with_clip = whole.clone();
        with_clip.extend(b"ftypmp42 a motion clip");
        assert!(jpeg_has_end(&with_clip));
        assert!(!jpeg_has_end(&[0xFF, 0xD8]));
        assert!(!jpeg_has_end(&[0xFF, 0xD8, 0xFF, 0xE0, 0xFF]));
    }

    #[test]
    fn fitting_keeps_the_ratio_and_never_upscales() {
        assert_eq!(fitted(4032, 3024, 2048), (2048, 1536));
        assert_eq!(fitted(3024, 4032, 2048), (1536, 2048));
        assert_eq!(fitted(800, 600, 2048), (800, 600), "no upscaling");
        assert_eq!(fitted(2048, 10, 512), (512, 3));
        assert_eq!(fitted(12_000, 1, 512), (512, 1), "never zero");
    }

    #[test]
    fn transparency_becomes_white_and_opaque_pixels_stay() {
        let mut rgba = image::RgbaImage::new(3, 1);
        rgba.put_pixel(0, 0, image::Rgba([10, 20, 30, 255]));
        rgba.put_pixel(1, 0, image::Rgba([10, 20, 30, 0]));
        rgba.put_pixel(2, 0, image::Rgba([0, 0, 0, 128]));
        let out = flatten_onto_white(DynamicImage::ImageRgba8(rgba));
        assert_eq!(out.get_pixel(0, 0).0, [10, 20, 30]);
        assert_eq!(out.get_pixel(1, 0).0, [255, 255, 255]);
        assert_eq!(out.get_pixel(2, 0).0, [127, 127, 127]);
    }
}
