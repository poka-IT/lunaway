//! The media directory: files appear whole at their content address, and
//! nothing outside the root is ever touched.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use lunaway_media::{Limits, MediaError, MediaStore, process};

const GPS_JPEG: &[u8] = include_bytes!("fixtures/gps_orientation6.jpg");

fn files_under(dir: &std::path::Path) -> Vec<String> {
    let mut out = Vec::new();
    for entry in std::fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            out.extend(files_under(&path));
        } else {
            out.push(path.to_string_lossy().into_owned());
        }
    }
    out.sort();
    out
}

#[tokio::test]
async fn a_photo_is_stored_once_at_its_content_address_and_removed() {
    let dir = tempfile::tempdir().unwrap();
    let store = MediaStore::new(dir.path().join("media"));
    let out = process(GPS_JPEG, &Limits::default()).unwrap();

    let full = store.put(&out.full).await.unwrap();
    let thumb = store.put(&out.thumb).await.unwrap();
    assert_eq!(full, out.full.relative_path());
    assert!(MediaStore::is_valid_relative_path(&full));
    let on_disk = std::fs::read(store.root().join(&full)).unwrap();
    assert_eq!(on_disk, out.full.bytes, "the file holds the encoded bytes");

    let again = store.put(&out.full).await.unwrap();
    assert_eq!(again, full, "the same picture lands on the same path");
    let files = files_under(store.root());
    assert_eq!(
        files.len(),
        2,
        "two files, no temporary file left behind: {files:?}"
    );
    assert!(
        files.iter().all(|f| !f.ends_with(".tmp")),
        "no temporary file left: {files:?}"
    );

    assert!(store.remove(&full).await.unwrap());
    assert!(
        !store.remove(&full).await.unwrap(),
        "a second removal finds nothing"
    );
    assert!(!store.root().join(&full).exists());
    assert!(store.root().join(&thumb).exists(), "the thumbnail stays");
}

#[tokio::test]
async fn paths_outside_the_produced_shape_are_refused() {
    let dir = tempfile::tempdir().unwrap();
    let outside = dir.path().join("secret.txt");
    std::fs::write(&outside, b"keep me").unwrap();
    let store = MediaStore::new(dir.path().join("media"));
    std::fs::create_dir_all(store.root()).unwrap();
    for bad in [
        "../secret.txt".to_owned(),
        outside.to_string_lossy().into_owned(),
        format!("photos/00/00/../../../secret.txt{}", "0".repeat(40)),
        "photos/ab/cd/x.webp".to_owned(),
    ] {
        assert!(
            matches!(store.remove(&bad).await, Err(MediaError::InvalidPath)),
            "{bad}"
        );
    }
    assert!(outside.exists(), "nothing outside the root was removed");

    let mut forged = process(GPS_JPEG, &Limits::default()).unwrap().full;
    forged.sha256_hex = format!("../../{}", "0".repeat(58));
    assert!(
        matches!(store.put(&forged).await, Err(MediaError::InvalidPath)),
        "a name that is not a hash is never written"
    );
}
