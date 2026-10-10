//! `lunaway extcom ...`: the switch of the external community source, for
//! the day its agreement ends or must be suspended (`docs/feeds.md`,
//! "Switches").
//!
//! `hide`, `show`, `purge`, `status` and `erasures` run with the import
//! role (they write the switch and the records, or read the erasures);
//! `purge-media` runs with the API's role and as the API's user, like
//! `moderation`, because it removes the photo files the API wrote.

use std::collections::BTreeSet;
use std::io::Write as _;
use std::os::unix::fs::{OpenOptionsExt as _, PermissionsExt as _};
use std::path::Path;

use anyhow::Context;
use clap::Subcommand;
use lunaway_db::{PgPool, extcom};
use lunaway_domain::SourceId;

/// Retired photos handled per round of `purge-media`.
const PURGE_MEDIA_ROUND: i64 = 500;

#[derive(Subcommand)]
pub(crate) enum Extcom {
    /// Prints the switch and what the source holds.
    Status,
    /// Hides the source at once: the API stops serving its reviews,
    /// ratings, photos and its name in a place's sources, and wakes the
    /// conflation, which takes its records off every place (the change
    /// feed then hands the places to every device). Nothing is deleted;
    /// `show` undoes it. The importer refuses to run while it is hidden.
    Hide {
        /// Why, for the operators (never a requester's personal data).
        #[arg(long)]
        note: Option<String>,
    },
    /// Shows the source again after `hide`; its records go back to their
    /// places at the next conflation.
    Show {
        /// Why.
        #[arg(long)]
        note: Option<String>,
    },
    /// Deletes everything of the source (the agreement ended): hides it,
    /// empties and retires its records, deletes its reviews and rating
    /// summaries, retires its photos. Then `purge-media --yes` with the
    /// API's role removes the photo files. Without `--yes`, prints what it
    /// would touch.
    Purge {
        /// Purges for real.
        #[arg(long)]
        yes: bool,
        /// Why.
        #[arg(long)]
        note: Option<String>,
    },
    /// Removes the files of the retired photos (purged, or gone from the
    /// feed) that no other photo uses, then their rows; then forgets the
    /// files of the live photos made without cutting the band the source
    /// stamps its mark in (made before the proxy cut it, or with another
    /// band), and removes them: the proxy makes them again, cut, at their
    /// next view. With the API's role and user. Without `--yes`, prints
    /// how many.
    PurgeMedia {
        /// Removes for real.
        #[arg(long)]
        yes: bool,
    },
    /// Erases one author at the partner's request (an erasure under the
    /// GDPR it forwards): deletes their reviews, retires their photos, and
    /// keeps the SHA-256 of the id so later feeds do not bring them back.
    /// Then `purge-media --yes` removes the files. Without `--yes`, prints
    /// nothing but the plan.
    EraseAuthor {
        /// The partner's id of the author, as the feed's `author_id`.
        author_id: String,
        /// Erases for real.
        #[arg(long)]
        yes: bool,
    },
    /// Writes the SHA-256 of every erased author id, one per line, sorted,
    /// and nothing else, into `--out`, replaced in one rename. The feed's
    /// producer reads that file to purge the same authors from its own
    /// copy (`docs/feeds.md`, "Erasure of one author").
    Erasures {
        /// The file to write; its directory must exist.
        #[arg(long)]
        out: std::path::PathBuf,
    },
}

/// Writes `hashes` (each the SHA-256 of an erased author id, lower-case
/// hexadecimal) into `path`, one per line in order: first into a hidden
/// file beside it, made 0640 so that the directory's group (the reader
/// the server allows) may read it, synced, then renamed over `path`, so a
/// reader sees the previous list or the new one, never a part. A value that
/// is not such a hash stops the write and leaves `path` as it was. One
/// writer at a time (the server's unit; systemd never runs it twice at
/// once): the hidden file's name is fixed.
fn write_erasures(path: &Path, hashes: &BTreeSet<String>) -> anyhow::Result<()> {
    let bad = hashes
        .iter()
        .filter(|h| h.len() != 64 || !h.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f')))
        .count();
    anyhow::ensure!(
        bad == 0,
        "{bad} erasure hashes are not 64 lower-case hexadecimal digits: nothing written"
    );
    let dir = path
        .parent()
        .filter(|d| !d.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    let name = path
        .file_name()
        .with_context(|| format!("{} names no file", path.display()))?;
    let mut partial_name = std::ffi::OsString::from(".");
    partial_name.push(name);
    partial_name.push(".partial");
    let partial = dir.join(partial_name);
    // A partial left by a stopped run: its mode was set when it was made.
    match std::fs::remove_file(&partial) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => return Err(e).with_context(|| format!("cannot remove {}", partial.display())),
    }
    // create_new does not follow a link put in the hidden file's place.
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o640)
        .open(&partial)
        .with_context(|| format!("cannot create {}", partial.display()))?;
    let mut body = String::with_capacity(65 * hashes.len());
    for h in hashes {
        body.push_str(h);
        body.push('\n');
    }
    // The mode again, past the umask: a run by hand under umask 077 would
    // otherwise write a list its reader cannot open.
    let written = file
        .set_permissions(std::fs::Permissions::from_mode(0o640))
        .and_then(|()| file.write_all(body.as_bytes()))
        .and_then(|()| file.sync_all());
    drop(file);
    if let Err(e) = written {
        // Best effort: the next run removes it anyway.
        let _ = std::fs::remove_file(&partial);
        return Err(e).with_context(|| format!("cannot write {}", partial.display()));
    }
    std::fs::rename(&partial, path)
        .with_context(|| format!("cannot rename {} to {}", partial.display(), path.display()))?;
    Ok(())
}

/// Removes the files of `dir` (the importer's cache of downloaded feeds and
/// of their progress), one by one; returns how many. Nothing to do when the
/// directory does not exist.
fn remove_cached_feeds(dir: &Path) -> anyhow::Result<usize> {
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(0),
        Err(e) => return Err(e).with_context(|| format!("cannot list {}", dir.display())),
    };
    let mut removed = 0;
    for entry in entries {
        let path = entry
            .with_context(|| format!("cannot list {}", dir.display()))?
            .path();
        if path.is_file() {
            std::fs::remove_file(&path)
                .with_context(|| format!("cannot remove {}", path.display()))?;
            removed += 1;
        }
    }
    Ok(removed)
}

/// `feeds` is the importer's cache directory of the source
/// (`LUNAWAY_DATA_DIR/raw/extcom`).
pub(crate) async fn run(
    pool: &PgPool,
    media: &lunaway_media::MediaStore,
    feeds: &Path,
    action: Extcom,
) -> anyhow::Result<()> {
    let source = SourceId::EXTCOM;
    match action {
        Extcom::Status => {
            let s = extcom::switch(pool, &source).await?;
            let c = extcom::counts(pool, &source).await?;
            print_switch(&s);
            println!(
                "records: {} live, {} linked to a place; reviews: {}; rating summaries: {}; \
                 photos: {} live ({} stored), {} retired waiting for purge-media",
                c.records,
                c.linked,
                c.reviews,
                c.ratings,
                c.photos,
                c.photos_stored,
                c.photos_retired
            );
        }
        Extcom::Hide { note } => {
            let flagged = extcom::set_hidden(pool, &source, true, note.as_deref())
                .await
                .context("hiding the source failed")?;
            println!(
                "{source} hidden: the API serves none of it from now; {flagged} records flagged, \
                 the conflation worker takes them off their places at its next run \
                 (or run `lunaway conflate`)"
            );
        }
        Extcom::Show { note } => {
            let flagged = extcom::set_hidden(pool, &source, false, note.as_deref())
                .await
                .context("showing the source failed")?;
            println!(
                "{source} shown again; {flagged} records flagged for the conflation \
                 (a purged source shows nothing until a new feed is imported)"
            );
        }
        Extcom::Purge { yes, note } => {
            let c = extcom::counts(pool, &source).await?;
            if !yes {
                println!(
                    "would purge {source}: {} live records ({} linked), {} reviews, {} rating \
                     summaries, {} live photos; run again with --yes",
                    c.records, c.linked, c.reviews, c.ratings, c.photos
                );
                return Ok(());
            }
            let p = extcom::purge(pool, &source, note.as_deref())
                .await
                .context("the purge failed; nothing was changed")?;
            let cached = remove_cached_feeds(feeds)?;
            println!(
                "{source} purged: {} records emptied, {} reviews and {} rating summaries \
                 deleted, {} photos retired, {cached} cached feed files removed. Next: the \
                 conflation takes the records off their places (the worker is woken; or run \
                 `lunaway conflate`), then run `lunaway extcom purge-media --yes` with the API's \
                 role, then rebuild the packs. A feed given with --file is the operator's to \
                 delete.",
                p.records, p.reviews, p.ratings, p.photos
            );
        }
        Extcom::PurgeMedia { yes } => {
            purge_media(pool, media, yes).await?;
            forget_uncut(pool, media, &source, yes).await?;
        }
        Extcom::EraseAuthor { author_id, yes } => {
            let id = author_id.trim();
            anyhow::ensure!(
                !id.is_empty() && id.len() <= 128,
                "an author id holds 1 to 128 bytes"
            );
            if !yes {
                println!(
                    "would delete the reviews and retire the photos of this author of {source}, \
                     and hold back what later feeds carry of them; run again with --yes"
                );
                return Ok(());
            }
            let hash = lunaway_domain::extcom::author_hash(id);
            let e = extcom::erase_author(pool, &source, id, &hash)
                .await
                .context("the erasure failed; nothing was changed")?;
            // A downloaded feed still holds the author's texts and id.
            let cached = remove_cached_feeds(feeds)?;
            // The id is not printed: the terminal's scrollback and a
            // script's log keep what the command prints.
            println!(
                "author erased: {} reviews deleted, {} photos retired, {cached} cached feed \
                 files removed; later feeds' items of theirs are skipped. Next: `lunaway extcom \
                 purge-media --yes` with the API's role. A feed given with --file is the \
                 operator's to delete.",
                e.reviews, e.photos
            );
        }
        Extcom::Erasures { out } => {
            let hashes = extcom::erased_authors(pool, &source)
                .await
                .context("reading the erased authors failed")?;
            let count = hashes.len();
            let shown = out.display().to_string();
            // A write and an fsync: off the runtime's threads.
            tokio::task::spawn_blocking(move || write_erasures(&out, &hashes))
                .await
                .context("the list's writer stopped")??;
            println!("{count} erased authors of {source} written to {shown}");
        }
    }
    Ok(())
}

fn print_switch(s: &extcom::Switch) {
    match (s.hidden_at, s.purged_at) {
        (None, _) => println!("switch: shown"),
        (Some(h), None) => println!("switch: hidden since {h}"),
        (Some(h), Some(p)) => println!("switch: hidden since {h}, purged at {p}"),
    }
}

async fn purge_media(
    pool: &PgPool,
    media: &lunaway_media::MediaStore,
    yes: bool,
) -> anyhow::Result<()> {
    let (mut rows, mut files) = (0_u64, 0_u64);
    loop {
        let batch = extcom::retired_photo_files(pool, PURGE_MEDIA_ROUND).await?;
        if batch.is_empty() {
            break;
        }
        if !yes {
            let n: usize = batch.iter().map(|p| p.unshared_files.len()).sum();
            println!(
                "would remove {} retired photo rows (first round) and {n} files; run again with \
                 --yes",
                batch.len()
            );
            return Ok(());
        }
        for photo in &batch {
            for file in &photo.unshared_files {
                if media
                    .remove(file)
                    .await
                    .with_context(|| format!("cannot remove the file of photo {}", photo.id))?
                {
                    files += 1;
                }
            }
        }
        let deleted = extcom::delete_retired_photos(pool, &batch).await?;
        rows += deleted;
        if deleted == 0 {
            // Every row of the round named new files when it was deleted
            // (a download finished meanwhile): the next run takes them.
            break;
        }
    }
    println!("{rows} retired photo rows deleted, {files} files removed");
    Ok(())
}

/// Forgets the files of the live photos of `source` made with another cut
/// than its band ([`lunaway_domain::extcom::mark_band_rows`]), then
/// removes those no row names any more. A row is emptied before its files
/// go, so no card names a file that is gone.
async fn forget_uncut(
    pool: &PgPool,
    media: &lunaway_media::MediaStore,
    source: &SourceId,
    yes: bool,
) -> anyhow::Result<()> {
    let band = lunaway_domain::extcom::mark_band_rows(source.as_str());
    if !yes {
        let n = extcom::uncut_photos(pool, source, band).await?;
        println!(
            "would forget the files of {n} live photos made without cutting the source's band \
             of {band} rows; run again with --yes"
        );
        return Ok(());
    }
    let (mut photos, mut files) = (0_u64, 0_u64);
    loop {
        let round = extcom::forget_uncut_photos(pool, source, band, PURGE_MEDIA_ROUND).await?;
        if round.photos == 0 {
            break;
        }
        photos += round.photos;
        for file in &round.unshared_files {
            if media
                .remove(file)
                .await
                .with_context(|| format!("cannot remove {file}, no longer named by any photo"))?
            {
                files += 1;
            }
        }
    }
    println!(
        "{photos} live photos made without the band of {band} rows forgotten (the proxy makes \
         them again at their next view), {files} files removed"
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hash(id: &str) -> String {
        lunaway_domain::extcom::author_hash(id)
    }

    #[test]
    fn the_erasure_list_holds_the_hashes_alone_one_per_line_in_order() {
        let dir = tempfile::tempdir().unwrap();
        let out = dir.path().join("erased-authors");
        let hashes: BTreeSet<String> = [hash("u-2"), hash("u-1")].into_iter().collect();
        write_erasures(&out, &hashes).unwrap();
        let sorted: Vec<&String> = hashes.iter().collect();
        assert_eq!(
            std::fs::read_to_string(&out).unwrap(),
            format!("{}\n{}\n", sorted[0], sorted[1]),
            "the producer reads one hash a line and nothing else: no id, no date"
        );
        assert_eq!(
            std::fs::metadata(&out).unwrap().permissions().mode() & 0o777,
            0o640,
            "the reader the server allows reads it through the directory's group, nobody else"
        );
        let left: Vec<_> = std::fs::read_dir(dir.path())
            .unwrap()
            .map(|e| e.unwrap().file_name())
            .collect();
        assert_eq!(left, ["erased-authors"], "no partial file stays behind");
    }

    #[test]
    fn a_new_list_replaces_the_old_and_an_empty_one_is_an_empty_file() {
        let dir = tempfile::tempdir().unwrap();
        let out = dir.path().join("erased-authors");
        write_erasures(&out, &[hash("u-1")].into_iter().collect()).unwrap();
        // A partial a stopped run left behind.
        std::fs::write(dir.path().join(".erased-authors.partial"), "junk").unwrap();
        write_erasures(&out, &[hash("u-1"), hash("u-3")].into_iter().collect()).unwrap();
        assert_eq!(std::fs::read_to_string(&out).unwrap().lines().count(), 2);
        write_erasures(&out, &BTreeSet::new()).unwrap();
        assert_eq!(std::fs::read_to_string(&out).unwrap(), "");
    }

    #[test]
    fn a_value_that_is_no_hash_writes_nothing() {
        let dir = tempfile::tempdir().unwrap();
        let out = dir.path().join("erased-authors");
        write_erasures(&out, &[hash("u-1")].into_iter().collect()).unwrap();
        let before = std::fs::read_to_string(&out).unwrap();
        let bad: BTreeSet<String> = [hash("u-2"), "u-2".to_owned()].into_iter().collect();
        assert!(write_erasures(&out, &bad).is_err());
        assert_eq!(
            std::fs::read_to_string(&out).unwrap(),
            before,
            "an author id must never reach the file the producer reads"
        );
        let upper: BTreeSet<String> = [hash("u-2").to_uppercase()].into_iter().collect();
        assert!(
            write_erasures(&out, &upper).is_err(),
            "the producer compares lower-case hashes"
        );
    }
}
