//! The media directory: content-addressed files under one root, which the
//! web server publishes as `/media/`.

use std::{
    io::ErrorKind,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
};

use tokio::io::AsyncWriteExt;

use crate::{Collection, Encoded, MediaError};

/// Distinguishes the temporary files of concurrent writes in one process.
static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

/// The directory the photos are stored in.
#[derive(Debug, Clone)]
pub struct MediaStore {
    root: PathBuf,
}

impl MediaStore {
    /// A store rooted at `root` (`LUNAWAY_MEDIA_DIR`), created on the first
    /// write.
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    /// The root directory.
    #[must_use]
    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Whether `relative` has the exact shape [`Encoded::relative_path_in`]
    /// produces: `photos/` or `external/`, the first two and the next two hexadecimal
    /// digits of the hash as directories, the 64-digit hash, an extension.
    /// Nothing else is ever joined to the root, so no path from a database
    /// row or a request can climb out of it.
    #[must_use]
    pub fn is_valid_relative_path(relative: &str) -> bool {
        let Some(rest) = [Collection::Photos, Collection::External]
            .iter()
            .find_map(|c| relative.strip_prefix(c.dir())?.strip_prefix('/'))
        else {
            return false;
        };
        let mut parts = rest.split('/');
        let (Some(a), Some(b), Some(file), None) =
            (parts.next(), parts.next(), parts.next(), parts.next())
        else {
            return false;
        };
        let Some((hash, extension)) = file.split_once('.') else {
            return false;
        };
        let lower_hex = |s: &str| s.bytes().all(|c| matches!(c, b'0'..=b'9' | b'a'..=b'f'));
        hash.len() == 64
            && lower_hex(hash)
            && a == &hash[..2]
            && b == &hash[2..4]
            && matches!(extension, "webp" | "jpg")
    }

    fn absolute(&self, relative: &str) -> Result<PathBuf, MediaError> {
        if !Self::is_valid_relative_path(relative) {
            return Err(MediaError::InvalidPath);
        }
        Ok(self.root.join(relative))
    }

    /// Stores `image` at its content address and returns that relative
    /// path. The file appears whole or not at all (written beside its final
    /// name, then renamed); a file already there is the same picture and is
    /// left as it is.
    ///
    /// # Errors
    ///
    /// [`MediaError::Io`] when the directory cannot be written.
    pub async fn put(&self, image: &Encoded) -> Result<String, MediaError> {
        self.put_in(Collection::Photos, image).await
    }

    /// [`MediaStore::put`] into `collection`.
    ///
    /// # Errors
    ///
    /// [`MediaError::Io`] when the directory cannot be written.
    pub async fn put_in(
        &self,
        collection: Collection,
        image: &Encoded,
    ) -> Result<String, MediaError> {
        let relative = image.relative_path_in(collection);
        let target = self.absolute(&relative)?;
        if tokio::fs::try_exists(&target)
            .await
            .map_err(MediaError::Io)?
        {
            return Ok(relative);
        }
        let dir = target.parent().ok_or(MediaError::InvalidPath)?;
        tokio::fs::create_dir_all(dir)
            .await
            .map_err(MediaError::Io)?;
        let temp = dir.join(format!(
            ".{}.{}-{}.tmp",
            image.sha256_hex,
            std::process::id(),
            TEMP_COUNTER.fetch_add(1, Ordering::Relaxed)
        ));
        let written = write_new(&temp, &image.bytes).await;
        let renamed = match written {
            Ok(()) => tokio::fs::rename(&temp, &target).await,
            Err(e) => Err(e),
        };
        if let Err(e) = renamed {
            // The temporary file is ours; a failure to remove it leaves a
            // dot file the next write does not collide with.
            if let Err(cleanup) = tokio::fs::remove_file(&temp).await
                && cleanup.kind() != ErrorKind::NotFound
            {
                return Err(MediaError::Io(cleanup));
            }
            return Err(MediaError::Io(e));
        }
        Ok(relative)
    }

    /// Removes the file at `relative`; `false` when it was not there.
    ///
    /// # Errors
    ///
    /// [`MediaError::InvalidPath`] for a path this crate never produces,
    /// [`MediaError::Io`] when the file exists but cannot be removed.
    pub async fn remove(&self, relative: &str) -> Result<bool, MediaError> {
        let target = self.absolute(relative)?;
        match tokio::fs::remove_file(&target).await {
            Ok(()) => Ok(true),
            Err(e) if e.kind() == ErrorKind::NotFound => Ok(false),
            Err(e) => Err(MediaError::Io(e)),
        }
    }
}

/// Writes `bytes` to a file that must not exist yet, and flushes it to the
/// disk before it is renamed into place.
async fn write_new(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let mut file = tokio::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .await?;
    file.write_all(bytes).await?;
    file.sync_all().await
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hash() -> String {
        "0123456789abcdef".repeat(4)
    }

    #[test]
    fn only_the_produced_shape_is_a_media_path() {
        let h = hash();
        assert!(MediaStore::is_valid_relative_path(&format!(
            "photos/01/23/{h}.webp"
        )));
        assert!(MediaStore::is_valid_relative_path(&format!(
            "photos/01/23/{h}.jpg"
        )));
        for bad in [
            format!("photos/01/24/{h}.webp"),
            format!("photos/01/23/{}.webp", h.to_uppercase()),
            format!("photos/01/23/{h}.png"),
            format!("photos/01/23/{h}.webp/x"),
            format!("/photos/01/23/{h}.webp"),
            format!("photos/../23/{h}.webp"),
            format!("../photos/01/23/{h}.webp"),
            format!("photos/01/23/../../{h}.webp"),
            "photos/01/23/0123.webp".to_owned(),
            "/etc/passwd".to_owned(),
            String::new(),
        ] {
            assert!(
                !MediaStore::is_valid_relative_path(&bad),
                "{bad} must not be joined to the media root"
            );
        }
    }
}
