//! Raw payloads kept on disk, so a development re-run reads the last answer
//! of a source instead of asking it again, and so the exact bytes an import
//! was built from can be inspected later. The directory (`data/` at the
//! repository root by default) is gitignored.

use std::{
    ffi::OsString,
    io,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::SystemTime,
};

use chrono::{DateTime, Utc};
use sha2::{Digest, Sha256};

use crate::IngestError;

/// A directory of cached payloads.
#[derive(Debug, Clone)]
pub struct Cache {
    root: PathBuf,
}

/// A payload read from the cache, with the time it was fetched.
#[derive(Debug, Clone)]
pub struct Cached {
    /// The bytes as the source sent them.
    pub bytes: Vec<u8>,
    /// When they were fetched: the file's modification time.
    pub fetched_at: DateTime<Utc>,
}

/// The first 16 hex digits of the SHA-256 of `input`: enough to tell two
/// queries apart in a file name.
#[must_use]
pub fn short_hash(input: &[u8]) -> String {
    Sha256::digest(input)
        .iter()
        .take(8)
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// The file a write goes to before it is renamed to `path`: the full name
/// plus the process and a counter, so two payloads whose names differ only
/// by their extension (`x.json`, `x.csv`), or two writes of one key, never
/// share a temporary file.
fn partial_path(path: &Path) -> PathBuf {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let mut name = path.file_name().map_or_else(OsString::new, OsString::from);
    name.push(format!(
        ".{}.{}.partial",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    path.with_file_name(name)
}

impl Cache {
    /// A cache rooted at `root` (created on first write).
    #[must_use]
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    /// The root directory.
    #[must_use]
    pub fn root(&self) -> &Path {
        &self.root
    }

    fn path(&self, key: &str) -> PathBuf {
        self.root.join(key)
    }

    /// The payload stored under `key`, if any.
    ///
    /// # Errors
    ///
    /// [`IngestError::Cache`] when the file exists but cannot be read.
    pub async fn read(&self, key: &str) -> Result<Option<Cached>, IngestError> {
        let path = self.path(key);
        let bytes = match tokio::fs::read(&path).await {
            Ok(b) => b,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(source) => return Err(IngestError::Cache { path, source }),
        };
        let modified = tokio::fs::metadata(&path)
            .await
            .and_then(|m| m.modified())
            .map_err(|source| IngestError::Cache {
                path: path.clone(),
                source,
            })?;
        Ok(Some(Cached {
            bytes,
            fetched_at: DateTime::<Utc>::from(modified),
        }))
    }

    /// Stores `bytes` under `key`. The file is written next to its final
    /// name and renamed, so a crash never leaves half a payload to be read
    /// back as a whole one.
    ///
    /// # Errors
    ///
    /// [`IngestError::Cache`] when the directory or the file cannot be
    /// written.
    pub async fn write(&self, key: &str, bytes: &[u8]) -> Result<DateTime<Utc>, IngestError> {
        let path = self.path(key);
        let io_err = |source| IngestError::Cache {
            path: path.clone(),
            source,
        };
        if let Some(dir) = path.parent() {
            tokio::fs::create_dir_all(dir).await.map_err(io_err)?;
        }
        let tmp = partial_path(&path);
        tokio::fs::write(&tmp, bytes).await.map_err(io_err)?;
        if let Err(e) = tokio::fs::rename(&tmp, &path).await {
            let _ = tokio::fs::remove_file(&tmp).await;
            return Err(io_err(e));
        }
        Ok(DateTime::<Utc>::from(SystemTime::now()))
    }

    /// The most recently modified file in the sub-directory `dir` whose name
    /// starts with `prefix`, as a key.
    ///
    /// # Errors
    ///
    /// [`IngestError::Cache`] when the directory exists but cannot be listed.
    pub async fn latest(&self, dir: &str, prefix: &str) -> Result<Option<String>, IngestError> {
        let path = self.path(dir);
        let mut entries = match tokio::fs::read_dir(&path).await {
            Ok(e) => e,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(source) => return Err(IngestError::Cache { path, source }),
        };
        let mut best: Option<(SystemTime, String)> = None;
        loop {
            let entry = entries
                .next_entry()
                .await
                .map_err(|source| IngestError::Cache {
                    path: path.clone(),
                    source,
                })?;
            let Some(entry) = entry else { break };
            let name = entry.file_name().to_string_lossy().into_owned();
            if !name.starts_with(prefix) || name.ends_with(".partial") {
                continue;
            }
            let Ok(modified) = entry.metadata().await.and_then(|m| m.modified()) else {
                continue;
            };
            if best.as_ref().is_none_or(|(t, _)| modified > *t) {
                best = Some((modified, format!("{dir}/{name}")));
            }
        }
        Ok(best.map(|(_, key)| key))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn a_written_payload_reads_back_with_its_date() {
        let dir = tempfile::tempdir().unwrap();
        let cache = Cache::new(dir.path());
        assert!(cache.read("osm/x.json").await.unwrap().is_none());
        let written = cache.write("osm/x.json", b"{}").await.unwrap();
        let back = cache.read("osm/x.json").await.unwrap().unwrap();
        assert_eq!(back.bytes, b"{}");
        assert!((back.fetched_at - written).num_seconds().abs() < 5);
        let left: Vec<_> = std::fs::read_dir(dir.path().join("osm"))
            .unwrap()
            .map(|e| e.unwrap().file_name())
            .collect();
        assert_eq!(left, ["x.json"], "the temporary file is renamed away");
    }

    #[test]
    fn two_payloads_never_share_a_temporary_file() {
        let json = partial_path(Path::new("osm/x.json"));
        let csv = partial_path(Path::new("osm/x.csv"));
        assert_ne!(
            json, csv,
            "x.json and x.csv written at once would overwrite each other"
        );
        assert_ne!(json, partial_path(Path::new("osm/x.json")));
        assert_eq!(
            json.parent(),
            Some(Path::new("osm")),
            "same directory, so the rename is atomic"
        );
        assert!(json.to_string_lossy().ends_with(".partial"));
    }

    #[tokio::test]
    async fn payloads_differing_by_extension_are_written_at_once() {
        let dir = tempfile::tempdir().unwrap();
        let cache = Cache::new(dir.path());
        let (a, b) = tokio::join!(
            cache.write("af/data.json", &[1; 200_000]),
            cache.write("af/data.csv", &[2; 200_000])
        );
        a.unwrap();
        b.unwrap();
        assert!(
            cache
                .read("af/data.json")
                .await
                .unwrap()
                .unwrap()
                .bytes
                .iter()
                .all(|x| *x == 1)
        );
        assert!(
            cache
                .read("af/data.csv")
                .await
                .unwrap()
                .unwrap()
                .bytes
                .iter()
                .all(|x| *x == 2)
        );
    }

    #[tokio::test]
    async fn latest_picks_the_newest_matching_file() {
        let dir = tempfile::tempdir().unwrap();
        let cache = Cache::new(dir.path());
        cache.write("af/data-1.csv", b"1").await.unwrap();
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;
        cache.write("af/data-2.csv", b"2").await.unwrap();
        cache.write("af/other.csv", b"3").await.unwrap();
        assert_eq!(
            cache.latest("af", "data-").await.unwrap().as_deref(),
            Some("af/data-2.csv")
        );
        assert_eq!(cache.latest("missing", "data-").await.unwrap(), None);
    }

    #[test]
    fn short_hashes_differ_with_the_input() {
        assert_eq!(short_hash(b"a").len(), 16);
        assert_ne!(short_hash(b"a"), short_hash(b"b"));
        assert_eq!(short_hash(b"a"), short_hash(b"a"));
    }
}
