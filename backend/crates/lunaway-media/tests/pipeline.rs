//! The pipeline on real files: what a phone sends, what an attacker sends.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::{
    io::Cursor,
    time::{Duration, Instant},
};

use image::{
    ExtendedColorType, ImageDecoder, ImageEncoder, RgbImage,
    codecs::{jpeg::JpegEncoder, webp::WebPDecoder},
};
use lunaway_media::{
    EXTENSION, Encoded, FULL_LONG_SIDE, Limits, MediaError, Options, SourceFormat, THUMB_LONG_SIDE,
    process, process_with,
};

const GPS_JPEG: &[u8] = include_bytes!("fixtures/gps_orientation6.jpg");
const ALPHA_PNG: &[u8] = include_bytes!("fixtures/alpha.png");
const WEBP: &[u8] = include_bytes!("fixtures/photo.webp");
const LARGE_JPEG: &[u8] = include_bytes!("fixtures/large_12mp.jpg");
const PNG_BOMB: &[u8] = include_bytes!("fixtures/bomb_100000.png");
const JPEG_BOMB: &[u8] = include_bytes!("fixtures/bomb_60000.jpg");
const GIF: &[u8] = include_bytes!("fixtures/animation.gif");
const HEIC: &[u8] = include_bytes!("fixtures/photo.heic");
const SVG: &[u8] = include_bytes!("fixtures/not_an_image.svg");

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    haystack.windows(needle.len()).any(|w| w == needle)
}

/// The FourCC of every chunk of a RIFF WebP file.
fn webp_chunks(bytes: &[u8]) -> Vec<String> {
    assert_eq!(&bytes[..4], b"RIFF");
    assert_eq!(&bytes[8..12], b"WEBP");
    let mut chunks = Vec::new();
    let mut at = 12;
    while at + 8 <= bytes.len() {
        chunks.push(String::from_utf8_lossy(&bytes[at..at + 4]).into_owned());
        let size = u32::from_le_bytes(bytes[at + 4..at + 8].try_into().unwrap()) as usize;
        at += 8 + size + (size % 2);
    }
    chunks
}

fn decode(e: &Encoded) -> image::RgbImage {
    image::load_from_memory_with_format(&e.bytes, image::ImageFormat::WebP)
        .unwrap()
        .into_rgb8()
}

/// Checks that `e` is a plain lossy WebP carrying pixels and nothing else.
fn assert_pixels_only(e: &Encoded) {
    assert_eq!(
        webp_chunks(&e.bytes),
        ["VP8 "],
        "a lossy WebP made from pixels has one image chunk: no EXIF, XMP or ICCP chunk"
    );
    let mut decoder = WebPDecoder::new(Cursor::new(&e.bytes)).unwrap();
    assert_eq!(decoder.exif_metadata().unwrap(), None);
    assert_eq!(decoder.xmp_metadata().unwrap(), None);
    assert_eq!(decoder.icc_profile().unwrap(), None);
    assert_eq!(decoder.dimensions(), (e.width, e.height));
}

fn is_red(p: [u8; 3]) -> bool {
    p[0] > 200 && p[1] < 60 && p[2] < 60
}

#[test]
fn a_phone_photo_is_turned_upright_and_keeps_no_byte_of_its_metadata() {
    // What the fixture carries, so the checks below cannot pass vacuously.
    // The latitude as the fixture stores it: three big-endian rationals,
    // 45/1 53/1 143223/2500 (45.899247 N).
    let gps_seconds_of_latitude: Vec<u8> = [45u32, 1, 53, 1, 143_223, 2_500]
        .iter()
        .flat_map(|n| n.to_be_bytes())
        .collect();
    let markers: [&[u8]; 5] = [
        b"Exif\0\0",
        b"LunawayTestCam",
        b"LunawayFixture",
        b"LunawayFixtureComment",
        b"http://ns.adobe.com/xap/1.0/",
    ];
    for m in markers {
        assert!(contains(GPS_JPEG, m), "fixture lacks {m:?}");
    }
    assert!(contains(GPS_JPEG, &gps_seconds_of_latitude));
    let mut source = image::codecs::jpeg::JpegDecoder::new(Cursor::new(GPS_JPEG)).unwrap();
    assert_eq!(source.dimensions(), (640, 480));
    assert_eq!(
        source.orientation().unwrap(),
        image::metadata::Orientation::Rotate90
    );

    let out = process(GPS_JPEG, &Limits::default()).unwrap();
    assert_eq!(out.source, SourceFormat::Jpeg);
    assert_eq!(
        (out.full.width, out.full.height),
        (480, 640),
        "orientation 6 turns a landscape sensor image into a portrait"
    );
    assert_eq!((out.thumb.width, out.thumb.height), (384, 512));
    for e in [&out.full, &out.thumb] {
        assert_pixels_only(e);
        for m in markers {
            assert!(!contains(&e.bytes, m), "{m:?} survived");
        }
        assert!(
            !contains(&e.bytes, &gps_seconds_of_latitude),
            "the GPS position survived"
        );
    }
    // The red block is in the stored top-left corner; a quarter turn
    // clockwise brings it to the top right.
    let full = decode(&out.full);
    assert!(is_red(full.get_pixel(470, 10).0), "top right is red");
    assert!(!is_red(full.get_pixel(10, 10).0), "top left is not");
    assert!(!is_red(full.get_pixel(470, 630).0), "bottom right is not");
}

#[test]
fn transparency_is_painted_white() {
    let out = process(ALPHA_PNG, &Limits::default()).unwrap();
    assert_eq!(out.source, SourceFormat::Png);
    assert_eq!((out.full.width, out.full.height), (300, 200));
    assert_pixels_only(&out.full);
    let full = decode(&out.full);
    let opaque = full.get_pixel(40, 100).0;
    assert!(
        opaque[1] > 90 && opaque[0] < 60 && opaque[2] < 90,
        "the opaque half keeps its green: {opaque:?}"
    );
    let clear = full.get_pixel(260, 100).0;
    assert!(
        clear.iter().all(|c| *c > 240),
        "the transparent half is white, not the black its pixels hold: {clear:?}"
    );
}

#[test]
fn a_webp_upload_is_accepted() {
    let out = process(WEBP, &Limits::default()).unwrap();
    assert_eq!(out.source, SourceFormat::WebP);
    assert_eq!((out.full.width, out.full.height), (400, 300));
    assert_pixels_only(&out.full);
}

#[test]
fn a_phone_sized_picture_is_reduced_to_the_stored_sizes() {
    let out = process(LARGE_JPEG, &Limits::default()).unwrap();
    assert_eq!((out.full.width, out.full.height), (FULL_LONG_SIDE, 1536));
    assert_eq!((out.thumb.width, out.thumb.height), (THUMB_LONG_SIDE, 384));
    assert!(
        out.full.bytes.len() < LARGE_JPEG.len() * 2,
        "{} bytes",
        out.full.bytes.len()
    );
    assert!(out.thumb.bytes.len() < out.full.bytes.len());
    // The ThumbHash decodes, with the picture's aspect ratio.
    assert!(!out.thumbhash.is_empty() && out.thumbhash.len() <= 64);
    let ratio = thumbhash::thumb_hash_to_approximate_aspect_ratio(&out.thumbhash).unwrap();
    assert!((ratio - 4.0 / 3.0).abs() < 0.1, "ratio {ratio}");
    // Content addressing: the name is the hash of what is stored.
    for e in [&out.full, &out.thumb] {
        use sha2::Digest as _;
        let digest: String = sha2::Sha256::digest(&e.bytes)
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect();
        assert_eq!(e.sha256_hex, digest);
        let path = e.relative_path();
        assert_eq!(
            path,
            format!(
                "photos/{}/{}/{}.{EXTENSION}",
                &digest[..2],
                &digest[2..4],
                digest
            )
        );
    }
    assert_ne!(out.full.sha256_hex, out.thumb.sha256_hex);
}

#[test]
fn the_same_upload_gives_the_same_files() {
    let a = process(GPS_JPEG, &Limits::default()).unwrap();
    let b = process(GPS_JPEG, &Limits::default()).unwrap();
    assert_eq!(
        a, b,
        "the same picture sent twice must land on the same path, written once"
    );
}

#[test]
fn decompression_bombs_are_refused_from_their_header() {
    for (bomb, side) in [(PNG_BOMB, 100_000), (JPEG_BOMB, 60_000)] {
        assert!(bomb.len() < 1_000, "a bomb is tiny on the wire");
        let started = Instant::now();
        let refused = process(bomb, &Limits::default()).unwrap_err();
        assert!(
            matches!(
                refused,
                MediaError::DimensionsTooLarge { width, height } if width == side && height == side
            ),
            "{refused:?}"
        );
        assert!(refused.is_client_error());
        assert!(
            started.elapsed() < Duration::from_millis(500),
            "refused before decoding: {:?}",
            started.elapsed()
        );
    }
}

#[test]
fn a_picture_within_the_sides_but_over_the_pixel_count_is_refused() {
    let limits = Limits {
        max_pixels: 10_000_000,
        ..Limits::default()
    };
    let refused = process(LARGE_JPEG, &limits).unwrap_err();
    assert!(
        matches!(
            refused,
            MediaError::DimensionsTooLarge {
                width: 4032,
                height: 3024
            }
        ),
        "{refused:?}"
    );
}

#[test]
fn a_decoder_over_its_memory_bound_stops() {
    let limits = Limits {
        max_alloc: 1024 * 1024,
        ..Limits::default()
    };
    let refused = process(LARGE_JPEG, &limits).unwrap_err();
    assert!(
        matches!(refused, MediaError::TooMuchMemory(_)),
        "a 12 MP picture needs 36 MB of pixels: {refused:?}"
    );
    assert!(refused.is_client_error());
}

#[test]
fn a_file_over_the_size_limit_is_refused_before_decoding() {
    let limits = Limits {
        max_bytes: 1_000,
        ..Limits::default()
    };
    let refused = process(GPS_JPEG, &limits).unwrap_err();
    assert!(
        matches!(refused, MediaError::TooLarge { size, max: 1_000 } if size == GPS_JPEG.len()),
        "{refused:?}"
    );
}

#[test]
fn other_formats_are_refused_whatever_they_claim() {
    for other in [GIF, HEIC, SVG, b"hello, this is text".as_slice(), &[]] {
        let refused = process(other, &Limits::default()).unwrap_err();
        assert!(matches!(refused, MediaError::Unsupported), "{refused:?}");
        assert!(refused.is_client_error());
    }
}

#[test]
fn a_cut_file_is_refused_as_malformed() {
    for (name, cut) in [
        ("large jpeg", &LARGE_JPEG[..LARGE_JPEG.len() / 2]),
        ("jpeg header", &GPS_JPEG[..200]),
        ("png", &ALPHA_PNG[..ALPHA_PNG.len() / 2]),
        ("webp", &WEBP[..WEBP.len() / 2]),
    ] {
        let refused = process(cut, &Limits::default())
            .err()
            .unwrap_or_else(|| panic!("{name} cut in half was accepted"));
        assert!(
            matches!(refused, MediaError::Malformed(_)),
            "{name}: {refused:?}"
        );
        assert!(refused.is_client_error());
    }
}

/// The band the API cuts off the external community source's photos
/// (`lunaway_domain::extcom::MARK_BAND_ROWS`; this crate knows no source).
const BAND: u16 = 68;

/// An upright `width` x `height` scene carrying a source's mark: a blue
/// sky, a green ground, a red block in the top-left corner, and a line of
/// white letter-like strokes 51 to 62 rows above the bottom edge and 52 to
/// 176 columns from the right edge, where the measured source stamps its
/// own. No pixel of the scene but the mark's has its three channels over
/// 200.
fn marked_scene(width: u32, height: u32) -> RgbImage {
    let mut img = RgbImage::from_fn(width, height, |_, y| {
        if y < height / 2 {
            image::Rgb([110, 160, 215])
        } else {
            image::Rgb([70, 95, 50])
        }
    });
    for y in 0..16 {
        for x in 0..16 {
            img.put_pixel(x, y, image::Rgb([255, 0, 0]));
        }
    }
    let (left, right) = (width - 176, width - 52);
    let (top, bottom) = (height - 62, height - 51);
    for x in left..=right {
        for y in top..=bottom {
            // Glyphs seven columns wide, three apart: their outline and a
            // middle bar, the strokes of letters.
            let col = (x - left) % 10;
            let stroke = col == 0 || col == 6 || y == top || y == bottom || y == (top + bottom) / 2;
            if col < 7 && stroke {
                img.put_pixel(x, y, image::Rgb([255, 255, 255]));
            }
        }
    }
    img
}

/// `img` as a JPEG of quality 92, with `exif` (a TIFF block) when given.
fn jpeg(img: &RgbImage, exif: Option<Vec<u8>>) -> Vec<u8> {
    let mut bytes = Vec::new();
    let mut encoder = JpegEncoder::new_with_quality(&mut bytes, 92);
    if let Some(exif) = exif {
        encoder.set_exif_metadata(exif).unwrap();
    }
    encoder
        .write_image(
            img.as_raw(),
            img.width(),
            img.height(),
            ExtendedColorType::Rgb8,
        )
        .unwrap();
    bytes
}

/// A TIFF block holding the orientation `value` alone (big-endian).
fn orientation_exif(value: u16) -> Vec<u8> {
    let mut tiff = b"MM\0\x2a\0\0\0\x08".to_vec();
    tiff.extend(1_u16.to_be_bytes()); // one entry
    tiff.extend(0x0112_u16.to_be_bytes()); // Orientation
    tiff.extend(3_u16.to_be_bytes()); // SHORT
    tiff.extend(1_u32.to_be_bytes()); // one value
    tiff.extend(value.to_be_bytes());
    tiff.extend([0, 0]); // the rest of the value field
    tiff.extend(0_u32.to_be_bytes()); // no next directory
    tiff
}

/// Pixels whose three channels pass 200: the mark's white, nothing else of
/// the scene.
fn white_pixels(img: &RgbImage) -> usize {
    img.pixels()
        .filter(|p| p.0.iter().all(|c| *c > 200))
        .count()
}

fn cut() -> Options {
    Options {
        cut_bottom: BAND,
        ..Options::default()
    }
}

#[test]
fn the_band_holding_a_source_s_mark_is_cut_off_every_file() {
    let input = jpeg(&marked_scene(1049, 749), None);
    // Without the cut, the mark survives the re-encoding: the checks below
    // can fail.
    let whole = process(&input, &Limits::default()).unwrap();
    assert!(white_pixels(&decode(&whole.full)) > 100);

    let out = process_with(&input, &Limits::default(), &cut()).unwrap();
    assert_eq!(
        (out.full.width, out.full.height),
        (1049, 749 - u32::from(BAND)),
        "the band is cut at the size the source sent, before any reduction"
    );
    assert_eq!((out.thumb.width, out.thumb.height), (THUMB_LONG_SIDE, 332));
    for (name, e) in [("photo", &out.full), ("thumbnail", &out.thumb)] {
        assert_pixels_only(e);
        assert_eq!(
            white_pixels(&decode(e)),
            0,
            "no letter of the mark in the {name}"
        );
    }
    let full = decode(&out.full);
    assert!(
        is_red(full.get_pixel(5, 5).0),
        "the rest of the picture stays"
    );
    let ground = full.get_pixel(500, 600).0;
    assert!(ground[1] > ground[0], "the ground above the band stays");
}

#[test]
fn the_band_is_cut_off_the_picture_as_it_stands_upright() {
    // A portrait its camera stored lying: its pixels turned a quarter
    // anticlockwise, and orientation 6 to turn them back. The mark is at
    // the bottom right of the upright picture, so at the top right of the
    // stored pixels: a cut of the stored bottom would leave it.
    let upright = marked_scene(600, 800);
    let stored = image::imageops::rotate270(&upright);
    assert_eq!(stored.dimensions(), (800, 600));
    let input = jpeg(&stored, Some(orientation_exif(6)));
    let whole = process(&input, &Limits::default()).unwrap();
    assert_eq!((whole.full.width, whole.full.height), (600, 800));
    assert!(white_pixels(&decode(&whole.full)) > 100);

    let out = process_with(&input, &Limits::default(), &cut()).unwrap();
    assert_eq!((out.full.width, out.full.height), (600, 732));
    let full = decode(&out.full);
    assert_eq!(white_pixels(&full), 0);
    assert!(is_red(full.get_pixel(5, 5).0));
}

#[test]
fn a_picture_too_small_for_the_band_is_refused_and_other_pictures_are_whole() {
    let small = jpeg(&marked_scene(300, 135), None);
    let refused = process_with(&small, &Limits::default(), &cut()).unwrap_err();
    assert!(
        matches!(
            refused,
            MediaError::TooSmall {
                width: 300,
                height: 135,
                band: BAND
            }
        ),
        "{refused:?}"
    );
    assert!(
        refused.is_client_error(),
        "the proxy records it as a failed download"
    );
    let whole = process_with(&small, &Limits::default(), &Options::default()).unwrap();
    assert_eq!(
        (whole.full.width, whole.full.height),
        (300, 135),
        "without a band, as for a user's photo or an open source's, nothing is cut"
    );
}

/// `cargo test -p lunaway-media --release -- --ignored --nocapture timing`
#[test]
#[ignore = "a measurement, run in release on purpose"]
fn timing_of_a_twelve_megapixel_photo() {
    let started = Instant::now();
    let out = process(LARGE_JPEG, &Limits::default()).unwrap();
    println!(
        "12 MP JPEG ({} bytes) to {}x{} ({} bytes) and {}x{} ({} bytes): {:?}",
        LARGE_JPEG.len(),
        out.full.width,
        out.full.height,
        out.full.bytes.len(),
        out.thumb.width,
        out.thumb.height,
        out.thumb.bytes.len(),
        started.elapsed()
    );
}
