//! `lunaway content` and `lunaway ingest datatourisme`: the open content
//! of the places (photos, descriptions, reviews) and the tourist offices'
//! records it partly comes from.

use std::path::Path;

use anyhow::Context;
use clap::{Subcommand, ValueEnum};
use lunaway_db::{
    PgPool,
    content::{self as db, Area},
};
use lunaway_ingest::{
    cache::Cache,
    content::{self, ContentConfig, ContentSource},
    datatourisme,
    store::store_complete,
};
use lunaway_media::MediaStore;
use uuid::Uuid;

/// The environment variable that holds the DATAtourisme key. It is read
/// from the environment only, never from an argument, which every user of
/// the machine could read in the process list.
pub(crate) const DATATOURISME_KEY_VAR: &str = "LUNAWAY_DATATOURISME_KEY";

#[derive(Subcommand)]
pub(crate) enum Content {
    /// Asks each source about the places it has not been asked about for a
    /// week, least recently asked first: Commons and Panoramax photos,
    /// Wikipedia introductions, the tourist offices' descriptions and
    /// photos from the DATAtourisme records, Mangrove reviews. Weekly.
    Refresh {
        /// Only these sources (`datatourisme`, `wikipedia`, `commons`,
        /// `panoramax`, `mangrove`), comma separated; all when absent.
        #[arg(long = "source", value_delimiter = ',')]
        sources: Vec<String>,
        /// Places asked per source at most in this run.
        #[arg(long)]
        max_places: Option<usize>,
        /// Only the places in this box: south,west,north,east. Mangrove,
        /// read whole, does not run with an area.
        #[arg(long, value_delimiter = ',', allow_negative_numbers = true)]
        area: Vec<f64>,
        /// A place asked about more recently than this many days is not
        /// asked again.
        #[arg(long, default_value_t = 7)]
        stale_days: i64,
    },
    /// Removes the files of `external/` no photo points at (what a stopped
    /// run left behind). Weekly, after the refresh.
    Gc,
    /// Counts the places with a photo, a description or a review.
    Coverage {
        /// Only the places in this box: south,west,north,east.
        #[arg(long, value_delimiter = ',', allow_negative_numbers = true)]
        area: Vec<f64>,
        /// Only what this source gives.
        #[arg(long)]
        source: Option<String>,
    },
    /// Hides a photo or a review wherever it shows (or shows it again with
    /// `--show`); no refresh brings it back.
    Hide {
        /// What the id names.
        what: HideWhat,
        /// Its id (`ExternalPhoto.id`, `ExternalReview.id`).
        id: Uuid,
        /// For a review: every review signed by the same key, those to
        /// come included.
        #[arg(long)]
        author: bool,
        /// Shows it again.
        #[arg(long)]
        show: bool,
    },
    /// Hides everything a source shows on a place (or shows it again).
    HidePlace {
        /// The place.
        place: Uuid,
        /// The source (`wikipedia`, `datatourisme`, `mangrove`, ...).
        source: String,
        /// Shows it again.
        #[arg(long)]
        show: bool,
    },
    /// Hides a whole source from every card (or shows it again): the
    /// switch for a source that turns bad.
    HideSource {
        /// The source.
        source: String,
        /// Shows it again.
        #[arg(long)]
        show: bool,
    },
}

#[derive(Clone, Copy, ValueEnum)]
pub(crate) enum HideWhat {
    /// A photo.
    Photo,
    /// A review.
    Review,
}

fn area_of(area: &[f64]) -> anyhow::Result<Option<Area>> {
    match area {
        [] => Ok(None),
        [s, w, n, e] if s < n && w < e => Ok(Some((*s, *w, *n, *e))),
        _ => anyhow::bail!("--area is south,west,north,east, south below north, west below east"),
    }
}

fn source_of(name: &str) -> anyhow::Result<String> {
    ContentSource::parse(name)
        .map(|s| s.id().to_string())
        .with_context(|| {
            format!(
                "unknown source {name}: datatourisme, wikipedia, commons, panoramax or mangrove"
            )
        })
}

fn done(changed: bool, show: bool) {
    println!(
        "{}",
        match (changed, show) {
            (true, false) => "hidden",
            (true, true) => "shown again",
            (false, false) => "already hidden",
            (false, true) => "was not hidden",
        }
    );
}

/// Runs a `content` command.
pub(crate) async fn run(
    pool: &PgPool,
    http: &reqwest::Client,
    media_dir: &Path,
    action: Content,
) -> anyhow::Result<()> {
    match action {
        Content::Refresh {
            sources,
            max_places,
            area,
            stale_days,
        } => {
            let sources = if sources.is_empty() {
                ContentSource::ALL.to_vec()
            } else {
                sources
                    .iter()
                    .map(|s| {
                        ContentSource::parse(s).with_context(|| {
                            format!("unknown source {s}: datatourisme, wikipedia, commons, panoramax or mangrove")
                        })
                    })
                    .collect::<anyhow::Result<_>>()?
            };
            anyhow::ensure!(stale_days >= 0, "--stale-days cannot be negative");
            let config = ContentConfig {
                stale_after: chrono::Duration::days(stale_days),
                max_places: max_places.unwrap_or(usize::MAX),
                area: area_of(&area)?,
                ..ContentConfig::default()
            };
            let store = MediaStore::new(media_dir);
            let reports = content::refresh(pool, http, &store, &sources, &config)
                .await
                .context("open content refresh failed")?;
            let mut stopped = Vec::new();
            for (source, r) in &reports {
                println!(
                    "{}: {} places asked, {} with content, {} items kept, {} removed; \
                     {} pictures downloaded, {} reused, {} files removed; {} failed",
                    source.id(),
                    r.places,
                    r.with_content,
                    r.items,
                    r.removed,
                    r.downloaded,
                    r.reused,
                    r.files_removed,
                    r.failures
                );
                if r.new_keys > 0 || r.held_new_keys > 0 || r.struck_keys > 0 {
                    println!(
                        "  new author keys: {} let in, {} reviews held for a later run; \
                         {} strikes for a hidden review",
                        r.new_keys, r.held_new_keys, r.struck_keys
                    );
                }
                if !r.skipped.is_empty() {
                    let skipped: Vec<String> =
                        r.skipped.iter().map(|(k, v)| format!("{k} {v}")).collect();
                    println!("  left out: {}", skipped.join(", "));
                }
                if let Some(why) = &r.stopped {
                    println!("  stopped: {why}");
                    stopped.push(source.id().to_string());
                }
            }
            anyhow::ensure!(
                stopped.is_empty(),
                "sources stopped before the end: {} (the next run resumes them)",
                stopped.join(", ")
            );
        }
        Content::Gc => {
            let store = MediaStore::new(media_dir);
            let removed = content::collect_garbage(pool, &store)
                .await
                .context("removing the unused files failed")?;
            println!("files no photo points at, removed: {removed}");
        }
        Content::Coverage { area, source } => {
            let source = source.as_deref().map(source_of).transpose()?;
            let c = db::coverage(pool, area_of(&area)?, source.as_deref()).await?;
            let pct = |n: i64| {
                if c.places == 0 {
                    0.0
                } else {
                    #[allow(clippy::cast_precision_loss, reason = "a percentage")]
                    let p = n as f64 * 100.0 / c.places as f64;
                    p
                }
            };
            println!("places: {}", c.places);
            println!(
                "  with a photo: {} ({:.1} %)",
                c.with_photo,
                pct(c.with_photo)
            );
            println!(
                "  with a photo of the place itself (linked or facing): {} ({:.1} %)",
                c.with_own_photo,
                pct(c.with_own_photo)
            );
            println!(
                "  with a description: {} ({:.1} %)",
                c.with_description,
                pct(c.with_description)
            );
            println!(
                "  with a review: {} ({:.1} %)",
                c.with_review,
                pct(c.with_review)
            );
            println!(
                "  with any of them: {} ({:.1} %)",
                c.with_any,
                pct(c.with_any)
            );
        }
        Content::Hide {
            what,
            id,
            author,
            show,
        } => {
            let kind = match what {
                HideWhat::Photo => db::ItemKind::Photo,
                HideWhat::Review => db::ItemKind::Review,
            };
            let item = db::item(pool, kind, id)
                .await?
                .with_context(|| format!("no {} has the id {id}", kind.scope()))?;
            let hide = match (kind, author) {
                (db::ItemKind::Review, true) => db::Hide::Author(
                    item.author_key
                        .context("this review carries no key to hide its author by")?,
                ),
                (db::ItemKind::Photo, true) => anyhow::bail!("--author is for a review"),
                (_, false) => db::Hide::Item(kind, item.external_id),
            };
            done(
                db::set_hidden(pool, &item.source_id, &hide, !show).await?,
                show,
            );
        }
        Content::HidePlace {
            place,
            source,
            show,
        } => {
            let source = source_of(&source)?;
            done(
                db::set_hidden(pool, &source, &db::Hide::Place(place), !show).await?,
                show,
            );
        }
        Content::HideSource { source, show } => {
            let source = source_of(&source)?;
            done(
                db::set_hidden(pool, &source, &db::Hide::Source, !show).await?,
                show,
            );
        }
    }
    Ok(())
}

/// `lunaway ingest datatourisme`: the tourist offices' motorhome areas,
/// service areas and campsites, as records the conflation merges.
pub(crate) async fn ingest_datatourisme(
    pool: &PgPool,
    cache: &Cache,
    refresh: bool,
) -> anyhow::Result<()> {
    // The key travels in a header that a redirect to another host would
    // carry along: this client follows none.
    let http =
        lunaway_ingest::http::client_without_redirects().context("cannot build the HTTP client")?;
    let key = std::env::var(DATATOURISME_KEY_VAR)
        .ok()
        .and_then(|k| datatourisme::ApiKey::new(&k))
        .with_context(|| {
            format!(
                "{DATATOURISME_KEY_VAR} is not set: ask a free key at \
                 https://www.datatourisme.fr/utiliser-les-donnees/ (docs/data-sources.md)"
            )
        })?;
    let config = datatourisme::DatatourismeConfig::new(key);
    let fetched = datatourisme::fetch(&http, cache, &config, refresh)
        .await
        .context("reading the datatourisme catalogue failed")?;
    let objects = fetched.objects.len();
    let parsed = datatourisme::to_records(fetched.objects, fetched.fetched_at);
    let store = store_complete(
        pool,
        &lunaway_domain::SourceId::DATATOURISME,
        None,
        &parsed.records,
    )
    .await
    .context("storing the datatourisme records failed")?;
    println!(
        "objects read: {objects} in {} pages{}",
        fetched.pages,
        if fetched.cached {
            " (from today's cache)"
        } else {
            ""
        }
    );
    let skipped: Vec<String> = parsed
        .skipped
        .iter()
        .map(|(k, v)| format!("{k:?} {v}"))
        .collect();
    println!(
        "records: {} kept; left out: {}",
        parsed.records.len(),
        if skipped.is_empty() {
            "none".to_owned()
        } else {
            skipped.join(", ")
        }
    );
    println!(
        "stored: {} inserted, {} changed, {} unchanged, {} retired{}",
        store.upsert.inserted,
        store.upsert.changed,
        store.upsert.unchanged,
        store.retired,
        if store.retire_refused {
            " (retiring refused: truncated?)"
        } else {
            ""
        }
    );
    anyhow::ensure!(
        !store.retire_refused,
        "retiring refused for datatourisme: the fetch holds less than half of the stored records"
    );
    Ok(())
}
