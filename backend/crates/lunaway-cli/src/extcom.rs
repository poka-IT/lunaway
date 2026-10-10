//! `lunaway extcom ...`: the switch of the external community source, for
//! the day its agreement ends or must be suspended (`docs/feeds.md`,
//! "Switches").
//!
//! `hide`, `show`, `purge` and `status` run with the import role (they
//! write the switch and the records); `purge-media` runs with the API's
//! role and as the API's user, like `moderation`, because it removes the
//! photo files the API wrote.

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
