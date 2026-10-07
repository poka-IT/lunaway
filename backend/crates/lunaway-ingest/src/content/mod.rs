//! The open content of the places: photos, descriptions and reviews read
//! from open sources, each item kept with its author, its licence and its
//! link (`docs/data-sources.md`, "Open content"; the research behind the
//! choice of sources is `plan/research/46-contenus-ouverts.md`).
//!
//! `lunaway content refresh` asks each source about the places it has not
//! been asked about for a week, least recently asked first, so a stopped
//! run resumes where it stopped (`content_checks`). Photos are downloaded
//! once, re-encoded from their pixels by `lunaway-media` (no metadata of
//! the source file survives) and stored under `external/` in the media
//! directory, which the API's host serves: the app never loads a source's
//! own URL. One run at a time (`lunaway_db::content::RunLock`): two would
//! share files and double the requests the sources see.
//!
//! Every source is paced on its own: Wikimedia's servers (Commons,
//! Wikidata, Wikipedia, their media) share one pace, under the 5
//! requests a second their robot policy asks of an unauthenticated client
//! and one request at a time; Panoramax, Mangrove and the photo hosts of
//! the tourist offices have theirs. A place whose requests fail waits for
//! the next run; a source whose places keep failing is stopped for the
//! run ([`ContentConfig::max_failures`]), and the report says so.

pub mod commons;
pub mod mangrove;
pub mod panoramax;
pub mod wikipedia;

use std::{
    collections::{BTreeMap, BTreeSet},
    path::Path,
    time::Duration,
};

use chrono::Utc;
use lunaway_db::{
    PgPool,
    content::{
        self as db, Area, DuePlace, DueQuery, NewDescription, NewPhoto, NewReview, PhotoFiles,
        RunLock,
    },
};
use lunaway_domain::{
    PlaceKind, Position, SourceId,
    content::{self, PhotoRelation, ReviewCandidate},
};
use lunaway_media::{Collection, MediaStore, Options, PanoramaView};
use tokio::{sync::Mutex, time::Instant};
use uuid::Uuid;

use crate::{
    IngestError,
    cache::short_hash,
    datatourisme,
    http::{RetryPolicy, check_status, read_capped, with_retry},
    web::check_host,
};

/// A source of open content.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum ContentSource {
    /// Wikimedia Commons: the files a place's data names, and those taken
    /// near it.
    Commons,
    /// Wikipedia: the introduction of a place's article.
    Wikipedia,
    /// Panoramax: street-level pictures looking at a place.
    Panoramax,
    /// DATAtourisme: the descriptions and photos of the tourist offices,
    /// from the records the conflation linked to a place.
    Datatourisme,
    /// Mangrove Reviews: open reviews.
    Mangrove,
}

impl ContentSource {
    /// Every source, in the order a full refresh runs them.
    pub const ALL: [Self; 5] = [
        Self::Datatourisme,
        Self::Wikipedia,
        Self::Commons,
        Self::Panoramax,
        Self::Mangrove,
    ];

    /// Its id in `sources`.
    #[must_use]
    pub fn id(self) -> SourceId {
        match self {
            Self::Commons => SourceId::WIKIMEDIA_COMMONS,
            Self::Wikipedia => SourceId::WIKIPEDIA,
            Self::Panoramax => SourceId::PANORAMAX,
            Self::Datatourisme => SourceId::DATATOURISME,
            Self::Mangrove => SourceId::MANGROVE,
        }
    }

    /// The source a command-line name designates (`commons`,
    /// `wikipedia`, `panoramax`, `datatourisme`, `mangrove`).
    #[must_use]
    pub fn parse(name: &str) -> Option<Self> {
        Some(match name.trim() {
            "commons" | "wikimedia-commons" => Self::Commons,
            "wikipedia" => Self::Wikipedia,
            "panoramax" => Self::Panoramax,
            "datatourisme" => Self::Datatourisme,
            "mangrove" => Self::Mangrove,
            _ => return None,
        })
    }
}

/// Where the sources are asked. Tests point them at a local server.
#[derive(Debug, Clone)]
pub struct Endpoints {
    /// The Commons action API ([`commons::API_URL`]).
    pub commons: String,
    /// The Wikidata action API ([`wikipedia::WIKIDATA_API_URL`]).
    pub wikidata: String,
    /// The Wikipedias' action API, `{lang}` standing for the language
    /// ([`wikipedia::WIKIPEDIA_API_URL`]).
    pub wikipedia: String,
    /// The Panoramax search ([`panoramax::SEARCH_URL`]).
    pub panoramax: String,
    /// The Mangrove reviews ([`mangrove::REVIEWS_URL`]).
    pub mangrove: String,
}

impl Default for Endpoints {
    fn default() -> Self {
        Self {
            commons: commons::API_URL.to_owned(),
            wikidata: wikipedia::WIKIDATA_API_URL.to_owned(),
            wikipedia: wikipedia::WIKIPEDIA_API_URL.to_owned(),
            panoramax: panoramax::SEARCH_URL.to_owned(),
            mangrove: mangrove::REVIEWS_URL.to_owned(),
        }
    }
}

/// How a refresh runs.
#[derive(Debug, Clone)]
pub struct ContentConfig {
    /// A place asked about more recently than this is not asked again.
    pub stale_after: chrono::Duration,
    /// Places asked per source in one run at most.
    pub max_places: usize,
    /// Places read from the database at a time.
    pub batch: usize,
    /// Only the places in this box. Mangrove, read whole, does not run
    /// with an area: it replaces every review at once.
    pub area: Option<Area>,
    /// Where the sources are asked.
    pub endpoints: Endpoints,
    /// Retries on load shedding, per request.
    pub retry: RetryPolicy,
    /// Least time between two requests to Wikimedia's servers.
    pub wikimedia_pace: Duration,
    /// Least time between two requests to Panoramax.
    pub panoramax_pace: Duration,
    /// Least time between two downloads from a tourist office's photo
    /// host.
    pub media_pace: Duration,
    /// Least time between two pages of Mangrove reviews.
    pub mangrove_pace: Duration,
    /// Failed places in a row after which a source is stopped for the run.
    pub max_failures: usize,
    /// Bounds on a downloaded picture.
    pub media_limits: lunaway_media::Limits,
}

impl Default for ContentConfig {
    fn default() -> Self {
        Self {
            stale_after: chrono::Duration::days(7),
            max_places: usize::MAX,
            batch: 50,
            area: None,
            endpoints: Endpoints::default(),
            // Shorter waits than an import's: a request for one place is
            // retried a few times, then the place waits for the next run.
            retry: RetryPolicy {
                min_delay: Duration::from_secs(5),
                max_delay: Duration::from_secs(120),
                max_retries: 4,
            },
            // 3.3 requests a second, under the robot policy's 5 and the
            // 200 a minute of the 2026 rate limits.
            wikimedia_pace: Duration::from_millis(300),
            panoramax_pace: Duration::from_millis(500),
            media_pace: Duration::from_millis(500),
            mangrove_pace: Duration::from_secs(2),
            max_failures: 20,
            media_limits: lunaway_media::Limits {
                max_bytes: 25 * 1024 * 1024,
                max_width: 12_000,
                max_height: 12_000,
                // A 360-degree picture of an 8K camera (7 680 by 3 840)
                // fits; decoding one takes about 100 MB, its copies twice
                // that, within the unit's memory cap.
                max_pixels: 40_000_000,
                max_alloc: 512 * 1024 * 1024,
            },
        }
    }
}

/// What a refresh did with one source.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SourceReport {
    /// Places asked about.
    pub places: usize,
    /// Of them, places with at least one item kept.
    pub with_content: usize,
    /// Items kept (photos, descriptions or reviews).
    pub items: usize,
    /// Items removed: the source no longer offers them, or their place is
    /// gone.
    pub removed: usize,
    /// Pictures downloaded and processed.
    pub downloaded: usize,
    /// Pictures already stored, reused.
    pub reused: usize,
    /// Files removed from the media directory.
    pub files_removed: usize,
    /// Places whose requests failed: asked again by the next run.
    pub failures: usize,
    /// Items left out, by reason.
    pub skipped: BTreeMap<String, usize>,
    /// Why the source was stopped before the end, if it was.
    pub stopped: Option<String>,
}

impl SourceReport {
    fn skip(&mut self, reason: impl std::fmt::Debug) {
        *self.skipped.entry(format!("{reason:?}")).or_default() += 1;
    }
}

/// One request at a time, at least `every` apart.
#[derive(Debug)]
struct Pacer {
    every: Duration,
    next: Mutex<Instant>,
}

impl Pacer {
    fn new(every: Duration) -> Self {
        Self {
            every,
            next: Mutex::new(Instant::now()),
        }
    }

    async fn wait(&self) {
        let mut next = self.next.lock().await;
        tokio::time::sleep_until(*next).await;
        *next = Instant::now() + self.every;
    }
}

/// What every step of a refresh needs.
struct Ctx<'a> {
    pool: &'a PgPool,
    http: &'a reqwest::Client,
    store: &'a MediaStore,
    config: &'a ContentConfig,
    wikimedia: Pacer,
    panoramax: Pacer,
    media: Pacer,
}

/// Largest API answer read: a page of 1 000 Mangrove reviews weighs
/// about 2 MB.
const ANSWER_MAX_BYTES: usize = 16 * 1024 * 1024;

/// The host of an endpoint, for the host check of its requests.
fn host_of(url: &str) -> String {
    reqwest::Url::parse(url)
        .ok()
        .and_then(|u| u.host_str().map(str::to_ascii_lowercase))
        .unwrap_or_default()
}

/// A picture of a source, as [`Ctx::photo_files`] fetches it.
#[derive(Debug, Clone, Copy)]
struct Item<'a> {
    source: &'a SourceId,
    external_id: &'a str,
    version: &'a str,
    url: &'a str,
}

impl Ctx<'_> {
    async fn get(
        &self,
        pacer: &Pacer,
        url: &str,
        hosts: &[&str],
        limit: usize,
        what: &str,
    ) -> Result<Vec<u8>, IngestError> {
        check_host(url, hosts)?;
        with_retry(what, self.config.retry, || async {
            pacer.wait().await;
            let response = self
                .http
                .get(url)
                .send()
                .await
                .map_err(|source| IngestError::Http {
                    url: url.to_owned(),
                    source,
                })?;
            let response = check_status(url, response).await?;
            read_capped(url, response, limit).await
        })
        .await
    }

    /// Asks the API at `endpoint`, on its own host only.
    async fn api(
        &self,
        pacer: &Pacer,
        endpoint: &str,
        url: &str,
        what: &str,
    ) -> Result<Vec<u8>, IngestError> {
        let host = host_of(endpoint);
        self.get(pacer, url, &[host.as_str()], ANSWER_MAX_BYTES, what)
            .await
    }

    /// The files of a picture: already stored for this version, or
    /// downloaded from its URL on a host `host_allowed` accepts, processed
    /// and stored. `None` when the picture cannot be used (gone, not an
    /// image, too large): the reason is counted.
    async fn photo_files(
        &self,
        pacer: &Pacer,
        item: Item<'_>,
        host_allowed: &dyn Fn(&str) -> bool,
        view: Option<PanoramaView>,
        report: &mut SourceReport,
    ) -> Result<Option<PhotoFiles>, IngestError> {
        if let Some(files) = db::stored_files(
            self.pool,
            item.source.as_str(),
            item.external_id,
            item.version,
        )
        .await?
        {
            report.reused += 1;
            return Ok(Some(files));
        }
        // HTTPS on the default port of an allowed host: a source's URL
        // never reaches another service of that host, nor a host by its
        // address.
        let host = reqwest::Url::parse(item.url)
            .ok()
            .filter(|u| u.scheme() == "https" && u.port().is_none())
            .and_then(|u| u.host_str().map(str::to_ascii_lowercase));
        let Some(host) = host.filter(|h| host_allowed(h)) else {
            report.skip("PhotoHost");
            return Ok(None);
        };
        let bytes = match self
            .get(
                pacer,
                item.url,
                &[host.as_str()],
                self.config.media_limits.max_bytes,
                "picture",
            )
            .await
        {
            Ok(b) => b,
            Err(IngestError::Status { status, .. }) if status.is_client_error() => {
                report.skip("PhotoGone");
                return Ok(None);
            }
            Err(IngestError::TooLarge { .. }) => {
                report.skip("PhotoTooLarge");
                return Ok(None);
            }
            Err(e) => return Err(e),
        };
        let limits = self.config.media_limits;
        let options = Options {
            full_long_side: commons::THUMB_WIDTH,
            thumb_long_side: lunaway_media::THUMB_LONG_SIDE,
            panorama_view: view,
        };
        let processed = tokio::task::spawn_blocking(move || {
            lunaway_media::process_with(&bytes, &limits, &options)
        })
        .await
        .map_err(IngestError::Blocking)?;
        let processed = match processed {
            Ok(p) => p,
            Err(e) if e.is_client_error() => {
                tracing::info!(error = %e, url = item.url, "picture refused");
                report.skip("PhotoUnreadable");
                return Ok(None);
            }
            Err(e) => return Err(IngestError::Media(e)),
        };
        let path = self
            .store
            .put_in(Collection::External, &processed.full)
            .await
            .map_err(IngestError::Media)?;
        let thumb_path = self
            .store
            .put_in(Collection::External, &processed.thumb)
            .await
            .map_err(IngestError::Media)?;
        report.downloaded += 1;
        Ok(Some(PhotoFiles {
            path,
            thumb_path,
            width: i32::try_from(processed.full.width).unwrap_or(i32::MAX),
            height: i32::try_from(processed.full.height).unwrap_or(i32::MAX),
            thumbhash: processed.thumbhash,
        }))
    }

    async fn remove_files(&self, paths: &[String], report: &mut SourceReport) {
        for p in paths {
            match self.store.remove(p).await {
                Ok(true) => report.files_removed += 1,
                Ok(false) => {}
                Err(e) => tracing::warn!(error = %e, path = p, "cannot remove a media file"),
            }
        }
    }
}

/// Asks `sources` about the places due, in the order given, and reports
/// what each did. The content of places gone since the last run is removed
/// first. A source's failures are in its report; the run goes on with the
/// next source.
///
/// # Errors
///
/// [`IngestError::Busy`] when another refresh runs, and
/// [`IngestError::Db`] when the database fails.
pub async fn refresh(
    pool: &PgPool,
    http: &reqwest::Client,
    store: &MediaStore,
    sources: &[ContentSource],
    config: &ContentConfig,
) -> Result<Vec<(ContentSource, SourceReport)>, IngestError> {
    let Some(lock) = RunLock::try_acquire(pool).await? else {
        return Err(IngestError::Busy {
            what: "content refresh",
        });
    };
    let result = refresh_locked(pool, http, store, sources, config).await;
    // The run's own outcome matters more than the lock's: closing its
    // connection releases it whatever happens.
    if let Err(e) = lock.release().await {
        tracing::warn!(error = %e, "the content lock's connection did not close cleanly");
    }
    result
}

async fn refresh_locked(
    pool: &PgPool,
    http: &reqwest::Client,
    store: &MediaStore,
    sources: &[ContentSource],
    config: &ContentConfig,
) -> Result<Vec<(ContentSource, SourceReport)>, IngestError> {
    let ctx = Ctx {
        pool,
        http,
        store,
        config,
        wikimedia: Pacer::new(config.wikimedia_pace),
        panoramax: Pacer::new(config.panoramax_pace),
        media: Pacer::new(config.media_pace),
    };
    let purged = db::purge_gone_places(pool).await?;
    let mut purge_report = SourceReport::default();
    ctx.remove_files(&purged.orphaned_files, &mut purge_report)
        .await;
    tracing::info!(
        removed = purged.removed,
        files = purge_report.files_removed,
        "content of gone places removed"
    );
    let mut out = Vec::new();
    for source in sources {
        tracing::info!(source = %source.id(), "refreshing open content");
        let report = match source {
            ContentSource::Commons | ContentSource::Panoramax => {
                per_place(&ctx, *source, None).await?
            }
            ContentSource::Wikipedia => wikipedia_pass(&ctx).await?,
            ContentSource::Datatourisme => {
                let mut r = SourceReport::default();
                let purged = db::purge_unlinked(pool, SourceId::DATATOURISME.as_str()).await?;
                r.removed += purged.removed;
                ctx.remove_files(&purged.orphaned_files, &mut r).await;
                let mut rest = per_place(&ctx, *source, Some(SourceId::DATATOURISME)).await?;
                rest.removed += r.removed;
                rest.files_removed += r.files_removed;
                rest
            }
            ContentSource::Mangrove => mangrove_pass(&ctx).await?,
        };
        tracing::info!(source = %source.id(), ?report, "open content refreshed");
        out.push((*source, report));
    }
    Ok(out)
}

/// Removes the files under `external/` of the media directory that no
/// photo row points at and that are older than a day: what a run stopped
/// between writing a file and storing its row left behind. Weekly, after
/// the refresh, under the same lock.
///
/// # Errors
///
/// [`IngestError::Busy`] when a refresh runs, [`IngestError::Media`] when
/// the directory cannot be read, and [`IngestError::Db`].
pub async fn collect_garbage(pool: &PgPool, store: &MediaStore) -> Result<usize, IngestError> {
    let Some(lock) = RunLock::try_acquire(pool).await? else {
        return Err(IngestError::Busy {
            what: "content refresh",
        });
    };
    let result = collect_garbage_locked(pool, store).await;
    if let Err(e) = lock.release().await {
        tracing::warn!(error = %e, "the content lock's connection did not close cleanly");
    }
    result
}

async fn collect_garbage_locked(pool: &PgPool, store: &MediaStore) -> Result<usize, IngestError> {
    let root = store.root().to_path_buf();
    let found = tokio::task::spawn_blocking(move || old_external_files(&root))
        .await
        .map_err(IngestError::Blocking)?
        .map_err(|e| IngestError::Media(lunaway_media::MediaError::Io(e)))?;
    let mut removed = 0;
    for chunk in found.chunks(1_000) {
        for path in db::unreferenced_files(pool, chunk.to_vec()).await? {
            if store.remove(&path).await.map_err(IngestError::Media)? {
                removed += 1;
            }
        }
    }
    Ok(removed)
}

/// The files under `external/` older than a day, as paths relative to
/// the media root.
fn old_external_files(root: &Path) -> std::io::Result<Vec<String>> {
    let day_ago = std::time::SystemTime::now() - Duration::from_secs(86_400);
    let mut out = Vec::new();
    let base = root.join(Collection::External.dir());
    let Ok(level1) = std::fs::read_dir(&base) else {
        return Ok(out);
    };
    for a in level1 {
        let a = a?;
        if !a.file_type()?.is_dir() {
            continue;
        }
        for b in std::fs::read_dir(a.path())? {
            let b = b?;
            if !b.file_type()?.is_dir() {
                continue;
            }
            for f in std::fs::read_dir(b.path())? {
                let f = f?;
                let meta = f.metadata()?;
                if !meta.is_file() || meta.modified()? > day_ago {
                    continue;
                }
                let relative = format!(
                    "{}/{}/{}/{}",
                    Collection::External.dir(),
                    a.file_name().to_string_lossy(),
                    b.file_name().to_string_lossy(),
                    f.file_name().to_string_lossy()
                );
                // A temporary file of a write in progress, or anything the
                // store never makes, is left alone.
                if MediaStore::is_valid_relative_path(&relative) {
                    out.push(relative);
                }
            }
        }
    }
    Ok(out)
}

/// Whether a database error is about this place's data (a constraint the
/// rows broke) rather than the database itself.
fn is_data_error(e: &IngestError) -> bool {
    matches!(e, IngestError::Db(d) if d.is_constraint_violation())
}

/// The places due for `source`, without those already tried in this run.
async fn due(
    ctx: &Ctx<'_>,
    source: &SourceId,
    with_records_of: Option<&SourceId>,
    tried: &[Uuid],
) -> Result<Vec<DuePlace>, IngestError> {
    Ok(db::places_due(
        ctx.pool,
        DueQuery {
            source: source.as_str(),
            before: Utc::now() - ctx.config.stale_after,
            limit: i64::try_from(ctx.config.batch).unwrap_or(i64::MAX),
            area: ctx.config.area,
            with_records_of: with_records_of.map(SourceId::as_str),
            skip: tried,
        },
    )
    .await?)
}

fn position_of(p: &DuePlace) -> Option<Position> {
    Position::new(p.lat, p.lon).ok()
}

fn kind_of(p: &DuePlace) -> PlaceKind {
    p.kind.parse().unwrap_or(PlaceKind::Parking)
}

/// What became of one place.
enum Outcome {
    /// Its items were stored; how many.
    Kept(usize),
    /// Its requests failed; it waits for the next run.
    Failed(IngestError),
}

/// Records the outcome of a place in `report`; `Some` when the source must
/// stop.
fn tally(
    report: &mut SourceReport,
    outcome: Outcome,
    failed_in_a_row: &mut usize,
    max_failures: usize,
    place: Uuid,
) -> Option<String> {
    match outcome {
        Outcome::Kept(kept) => {
            *failed_in_a_row = 0;
            report.items += kept;
            if kept > 0 {
                report.with_content += 1;
            }
            None
        }
        Outcome::Failed(e) => {
            tracing::warn!(error = %e, %place, "open content of a place failed");
            report.failures += 1;
            *failed_in_a_row += 1;
            (*failed_in_a_row >= max_failures)
                .then(|| format!("{failed_in_a_row} places failed in a row, the last with: {e}"))
        }
    }
}

/// Runs `work` for one place: a data error (a row the database refuses)
/// marks the place asked with nothing kept, so it does not head every
/// later run; any other database error stops the refresh; a source's
/// error leaves the place for the next run.
async fn guarded(
    ctx: &Ctx<'_>,
    place: Uuid,
    source: &SourceId,
    work: impl std::future::Future<Output = Result<usize, IngestError>>,
) -> Result<Outcome, IngestError> {
    match work.await {
        Ok(kept) => Ok(Outcome::Kept(kept)),
        Err(e) if is_data_error(&e) => {
            tracing::error!(error = %e, %place, "a row of the place was refused");
            db::mark_checked(ctx.pool, place, source.as_str(), Utc::now(), 0).await?;
            Ok(Outcome::Failed(e))
        }
        Err(e @ IngestError::Db(_)) => Err(e),
        Err(e) => Ok(Outcome::Failed(e)),
    }
}

/// Asks a source place by place (Commons, Panoramax, DATAtourisme).
async fn per_place(
    ctx: &Ctx<'_>,
    source: ContentSource,
    with_records_of: Option<SourceId>,
) -> Result<SourceReport, IngestError> {
    let id = source.id();
    let mut report = SourceReport::default();
    let mut tried = Vec::new();
    let mut failed_in_a_row = 0;
    'run: while report.places < ctx.config.max_places {
        let batch = due(ctx, &id, with_records_of.as_ref(), &tried).await?;
        if batch.is_empty() {
            break;
        }
        let items = if source == ContentSource::Commons {
            match wikidata_items(ctx, &batch).await {
                Ok(items) => Some(items),
                Err(e) => {
                    tracing::warn!(error = %e, "wikidata items unavailable");
                    None
                }
            }
        } else {
            Some(BTreeMap::new())
        };
        for place in batch {
            if report.places >= ctx.config.max_places {
                break 'run;
            }
            tried.push(place.id);
            report.places += 1;
            let outcome = match source {
                // Without its Wikidata item a place would lose the image
                // the item names until the next week: it waits instead.
                ContentSource::Commons if items.is_none() && !place.links.wikidata.is_empty() => {
                    Outcome::Failed(IngestError::Implausible {
                        what: "wikidata items unavailable".into(),
                    })
                }
                ContentSource::Commons => {
                    let empty = BTreeMap::new();
                    let items = items.as_ref().unwrap_or(&empty);
                    guarded(
                        ctx,
                        place.id,
                        &id,
                        commons_place(ctx, &place, items, &mut report),
                    )
                    .await?
                }
                ContentSource::Panoramax => {
                    guarded(
                        ctx,
                        place.id,
                        &id,
                        panoramax_place(ctx, &place, &mut report),
                    )
                    .await?
                }
                ContentSource::Datatourisme => {
                    guarded(
                        ctx,
                        place.id,
                        &id,
                        datatourisme_place(ctx, &place, &mut report),
                    )
                    .await?
                }
                ContentSource::Wikipedia | ContentSource::Mangrove => Outcome::Kept(0),
            };
            if let Some(why) = tally(
                &mut report,
                outcome,
                &mut failed_in_a_row,
                ctx.config.max_failures,
                place.id,
            ) {
                report.stopped = Some(why);
                break 'run;
            }
        }
    }
    Ok(report)
}

/// The Wikidata items the places of a batch cite.
async fn wikidata_items(
    ctx: &Ctx<'_>,
    batch: &[DuePlace],
) -> Result<BTreeMap<String, wikipedia::Item>, IngestError> {
    let ids: BTreeSet<String> = batch
        .iter()
        .flat_map(|p| p.links.wikidata.iter())
        .filter_map(|q| lunaway_domain::conflation::normalize::normalize_wikidata(q))
        .collect();
    let ids: Vec<String> = ids.into_iter().collect();
    let mut out = BTreeMap::new();
    let endpoint = &ctx.config.endpoints.wikidata;
    for chunk in ids.chunks(wikipedia::ITEMS_PER_REQUEST) {
        let url = wikipedia::entities_url(endpoint, chunk)?;
        let body = ctx.api(&ctx.wikimedia, endpoint, &url, "wikidata").await?;
        out.extend(wikipedia::parse_entities(&body)?);
    }
    Ok(out)
}

fn commons_host(host: &str) -> bool {
    commons::MEDIA_HOSTS.contains(&host)
}

/// The Commons photos of one place: the files its data names, then those
/// taken around it. Returns the photos kept.
async fn commons_place(
    ctx: &Ctx<'_>,
    place: &DuePlace,
    items: &BTreeMap<String, wikipedia::Item>,
    report: &mut SourceReport,
) -> Result<usize, IngestError> {
    let id = SourceId::WIKIMEDIA_COMMONS;
    let Some(at) = position_of(place) else {
        db::mark_checked(ctx.pool, place.id, id.as_str(), Utc::now(), 0).await?;
        return Ok(0);
    };
    let endpoint = &ctx.config.endpoints.commons;
    let mut titles: Vec<String> = Vec::new();
    let mut categories: Vec<String> = Vec::new();
    for v in &place.links.wikimedia_commons {
        if let Some(t) = content::commons_file_title(v) {
            titles.push(t);
        } else if let Some(c) = commons::category_title(v) {
            categories.push(c);
        }
    }
    titles.extend(
        place
            .links
            .image
            .iter()
            .filter_map(|v| content::commons_file_title(v)),
    );
    for q in &place.links.wikidata {
        if let Some(item) =
            lunaway_domain::conflation::normalize::normalize_wikidata(q).and_then(|q| items.get(&q))
        {
            titles.extend(item.images.iter().cloned());
            categories.extend(item.commons_category.iter().cloned());
        }
    }
    titles.sort();
    titles.dedup();
    let mut linked = Vec::new();
    if !titles.is_empty() {
        let url = commons::files_url(endpoint, &titles)?;
        let body = ctx
            .api(&ctx.wikimedia, endpoint, &url, "commons files")
            .await?;
        let (files, skipped) = commons::parse(&body)?;
        skipped.iter().for_each(|s| report.skip(s));
        linked.extend(files);
    }
    for category in categories.iter().take(1) {
        let url = commons::category_url(endpoint, category, 4)?;
        let body = ctx
            .api(&ctx.wikimedia, endpoint, &url, "commons category")
            .await?;
        let (files, skipped) = commons::parse(&body)?;
        skipped.iter().for_each(|s| report.skip(s));
        linked.extend(files);
    }
    let radius = content::nearby_radius_m(kind_of(place));
    let url = commons::geosearch_url(endpoint, at, radius, 20)?;
    let body = ctx
        .api(&ctx.wikimedia, endpoint, &url, "commons geosearch")
        .await?;
    let (mut nearby, skipped) = commons::parse(&body)?;
    skipped.iter().for_each(|s| report.skip(s));
    let linked_titles: BTreeSet<String> = linked.iter().map(|f| f.title.clone()).collect();
    nearby.retain(|f| {
        !linked_titles.contains(&f.title) && f.position.is_some_and(|p| p.distance_m(at) <= radius)
    });
    nearby.sort_by(|a, b| {
        let d = |f: &commons::CommonsFile| f.position.map_or(f64::MAX, |p| p.distance_m(at));
        d(a).total_cmp(&d(b))
    });
    nearby.truncate(content::MAX_NEARBY_PHOTOS);
    let mut chosen: Vec<(commons::CommonsFile, PhotoRelation)> = Vec::new();
    let mut seen = BTreeSet::new();
    for f in linked {
        if seen.insert(f.title.clone()) {
            chosen.push((f, PhotoRelation::Linked));
        }
    }
    chosen.extend(nearby.into_iter().map(|f| (f, PhotoRelation::Nearby)));
    chosen.truncate(content::MAX_PHOTOS_PER_PLACE);
    let mut photos = Vec::new();
    for (f, relation) in chosen {
        let version: String = f.sha1.chars().take(100).collect();
        let item = Item {
            source: &id,
            external_id: &f.title,
            version: &version,
            url: &f.image_url,
        };
        let Some(files) = ctx
            .photo_files(&ctx.wikimedia, item, &commons_host, None, report)
            .await?
        else {
            continue;
        };
        let title = f.object_name.clone().or_else(|| {
            f.title
                .strip_prefix("File:")
                .map(|t| t.rsplit_once('.').map_or(t, |(stem, _)| stem).to_owned())
        });
        #[allow(clippy::cast_possible_truncation, reason = "metres, shown rounded")]
        let distance_m = f.position.map(|p| p.distance_m(at) as f32);
        photos.push(NewPhoto {
            external_id: f.title.clone(),
            version,
            relation: relation.code().to_owned(),
            distance_m,
            page_url: f.page_url.clone(),
            title,
            author: f.author.clone(),
            publisher: None,
            source_updated_on: None,
            licence: f.licence.name.clone(),
            licence_url: f.licence.url.clone(),
            taken_at: f.taken_at,
            rights_end_on: None,
            files,
        });
    }
    let kept = photos.len();
    let replaced =
        db::replace_photos(ctx.pool, place.id, id.as_str(), &photos, Utc::now(), kept).await?;
    report.removed += replaced.removed;
    ctx.remove_files(&replaced.orphaned_files, report).await;
    Ok(kept)
}

fn panoramax_host(host: &str) -> bool {
    panoramax::INSTANCES.iter().any(|(h, _)| *h == host)
}

/// Pictures looking at a place kept at most.
const MAX_PANORAMAX_PHOTOS: usize = 2;

/// Horizontal field kept of a 360-degree picture, degrees: about what a
/// phone's main camera sees.
const PANORAMA_WIDTH_DEG: f64 = 90.0;
/// Vertical field kept, degrees, centred on the horizon.
const PANORAMA_HEIGHT_DEG: f64 = 60.0;

/// The Panoramax pictures of one place: those its data names, and those
/// looking at it.
async fn panoramax_place(
    ctx: &Ctx<'_>,
    place: &DuePlace,
    report: &mut SourceReport,
) -> Result<usize, IngestError> {
    let id = SourceId::PANORAMAX;
    let Some(at) = position_of(place) else {
        db::mark_checked(ctx.pool, place.id, id.as_str(), Utc::now(), 0).await?;
        return Ok(0);
    };
    let endpoint = &ctx.config.endpoints.panoramax;
    let mut chosen: Vec<(panoramax::Picture, PhotoRelation)> = Vec::new();
    let linked_ids: Vec<String> = place
        .links
        .panoramax
        .iter()
        .filter_map(|v| content::panoramax_picture_id(v))
        .take(2)
        .collect();
    if !linked_ids.is_empty() {
        let url = panoramax::ids_url(endpoint, &linked_ids)?;
        let body = ctx
            .api(&ctx.panoramax, endpoint, &url, "panoramax pictures")
            .await?;
        let (pictures, skipped) = panoramax::parse(&body)?;
        skipped.iter().for_each(|s| report.skip(s));
        chosen.extend(pictures.into_iter().map(|p| (p, PhotoRelation::Linked)));
    }
    let distance = content::nearby_radius_m(kind_of(place)).min(60.0);
    let url = panoramax::search_url(endpoint, at, distance)?;
    let body = ctx
        .api(&ctx.panoramax, endpoint, &url, "panoramax search")
        .await?;
    let (pictures, skipped) = panoramax::parse(&body)?;
    skipped.iter().for_each(|s| report.skip(s));
    let facing = panoramax::choose(pictures, at, MAX_PANORAMAX_PHOTOS);
    for p in facing {
        if !chosen.iter().any(|(c, _)| c.id == p.id) {
            chosen.push((p, PhotoRelation::Facing));
        }
    }
    chosen.truncate(MAX_PANORAMAX_PHOTOS + linked_ids.len());
    let mut photos = Vec::new();
    for (p, relation) in chosen {
        let offset_deg = content::bearing_deg(p.position, at) - p.azimuth_deg;
        let view = p.panorama.then_some(PanoramaView {
            offset_deg,
            width_deg: PANORAMA_WIDTH_DEG,
            height_deg: PANORAMA_HEIGHT_DEG,
        });
        // A panorama is cut towards its place: the same picture seen from
        // another place is another file, so the direction is part of the
        // version.
        let version = if p.panorama {
            format!("{}@{:.0}", p.id, offset_deg.rem_euclid(360.0))
        } else {
            p.id.clone()
        };
        let item = Item {
            source: &id,
            external_id: &p.id,
            version: &version,
            url: &p.image_url,
        };
        let Some(files) = ctx
            .photo_files(&ctx.panoramax, item, &panoramax_host, view, report)
            .await?
        else {
            continue;
        };
        #[allow(clippy::cast_possible_truncation, reason = "metres, shown rounded")]
        let distance_m = Some(p.position.distance_m(at) as f32);
        photos.push(NewPhoto {
            external_id: p.id.clone(),
            version,
            relation: relation.code().to_owned(),
            distance_m,
            page_url: p.page_url.clone(),
            title: None,
            author: p.author.clone(),
            publisher: Some(p.instance.to_owned()),
            source_updated_on: None,
            licence: p.licence.name.clone(),
            licence_url: p.licence.url.clone(),
            taken_at: p.taken_at,
            rights_end_on: None,
            files,
        });
    }
    let kept = photos.len();
    let replaced =
        db::replace_photos(ctx.pool, place.id, id.as_str(), &photos, Utc::now(), kept).await?;
    report.removed += replaced.removed;
    ctx.remove_files(&replaced.orphaned_files, report).await;
    Ok(kept)
}

/// The hosts the tourist offices' photos of DATAtourisme come from, read
/// on 2026-10-07 over the 24 377 photos of its motorhome areas and
/// campsites: the software their offices use (Tourinsoft, Apidae, Tourism
/// System, Kapt, HIT, Constellation) and two offices' own sites. A photo
/// elsewhere is left out and counted (`PhotoHost`) until its host is added
/// here.
pub const DATATOURISME_MEDIA_HOSTS: &[&str] = &[
    "medias.hit.enaveyron.fr",
    "static.apidae-tourisme.com",
    "opendata.sitlor.fr",
    "cnstlltn.com",
    "opendata.tourisme-alsace.info",
    "medias.tourism-system.com",
    "medias.tourism-system.fr",
    "static.kap-tourisme.fr",
    "www.caravelis.com",
    "www.grandpicsaintloup-tourisme.fr",
];

/// Host suffixes of the same: Tourinsoft gives each office its own
/// subdomain (`cdt24.media.tourinsoft.eu`).
pub const DATATOURISME_MEDIA_SUFFIXES: &[&str] = &[".tourinsoft.eu", ".tourinsoft.com"];

/// Whether a photo of DATAtourisme may be downloaded from `host`.
#[must_use]
pub fn datatourisme_media_host(host: &str) -> bool {
    DATATOURISME_MEDIA_HOSTS.contains(&host)
        || DATATOURISME_MEDIA_SUFFIXES
            .iter()
            .any(|s| host.ends_with(s) && host.len() > s.len())
}

/// The descriptions and photos of one place from the DATAtourisme records
/// the conflation linked to it.
async fn datatourisme_place(
    ctx: &Ctx<'_>,
    place: &DuePlace,
    report: &mut SourceReport,
) -> Result<usize, IngestError> {
    let id = SourceId::DATATOURISME;
    let payloads = db::payloads(ctx.pool, place.id, id.as_str()).await?;
    let today = Utc::now().date_naive();
    let licence = content::accepted_licence("etalab-2.0").ok_or(IngestError::Implausible {
        what: "the Licence Ouverte is not recognised".into(),
    })?;
    let mut descriptions: Vec<NewDescription> = Vec::new();
    let mut photos: Vec<NewPhoto> = Vec::new();
    for payload in &payloads {
        let raw = &payload.raw;
        let Some(page_url) = datatourisme::page_url(raw) else {
            report.skip("NoPage");
            continue;
        };
        let publisher = datatourisme::publisher_of(raw);
        let updated = datatourisme::updated_on(raw);
        for d in datatourisme::descriptions_of(raw) {
            if descriptions.iter().any(|x| x.lang == d.lang) {
                continue;
            }
            descriptions.push(NewDescription {
                lang: d.lang,
                text: d.text,
                title: None,
                page_url: page_url.clone(),
                author: None,
                publisher: publisher.clone(),
                source_updated_on: updated,
                licence: licence.name.clone(),
                licence_url: licence.url.clone(),
            });
        }
        let (kept, skipped) = datatourisme::photos_of(raw, today);
        skipped.iter().for_each(|s| report.skip(s));
        for p in kept {
            if photos.len() >= content::MAX_PHOTOS_PER_PLACE {
                break;
            }
            let external_id = format!("{}:{}", payload.external_id, short_hash(p.url.as_bytes()));
            if photos.iter().any(|x| x.external_id == external_id) {
                continue;
            }
            // An office may put a new picture at the same address: the
            // object's update date is part of the version, so the next
            // read of an updated object downloads its photos again.
            let version = short_hash(
                format!(
                    "{}|{}",
                    p.url,
                    updated.map(|d| d.to_string()).unwrap_or_default()
                )
                .as_bytes(),
            );
            let item = Item {
                source: &id,
                external_id: &external_id,
                version: &version,
                url: &p.url,
            };
            let Some(files) = ctx
                .photo_files(&ctx.media, item, &datatourisme_media_host, None, report)
                .await?
            else {
                continue;
            };
            photos.push(NewPhoto {
                external_id,
                version,
                relation: PhotoRelation::Linked.code().to_owned(),
                distance_m: None,
                page_url: page_url.clone(),
                title: p.title,
                author: Some(p.credits),
                publisher: publisher.clone(),
                source_updated_on: updated,
                licence: p.licence.name,
                licence_url: p.licence.url,
                taken_at: None,
                rights_end_on: p.rights_end,
                files,
            });
        }
    }
    let now = Utc::now();
    let kept = descriptions.len() + photos.len();
    let d =
        db::replace_descriptions(ctx.pool, place.id, id.as_str(), &descriptions, now, kept).await?;
    let p = db::replace_photos(ctx.pool, place.id, id.as_str(), &photos, now, kept).await?;
    report.removed += d.removed + p.removed;
    ctx.remove_files(&p.orphaned_files, report).await;
    Ok(kept)
}

/// Wikipedia: the introductions of the articles of the places due, batch
/// by batch, one request per language per batch. A place whose Wikidata
/// item or one of whose languages could not be read waits for the next
/// run; the others of the batch are stored.
async fn wikipedia_pass(ctx: &Ctx<'_>) -> Result<SourceReport, IngestError> {
    let id = SourceId::WIKIPEDIA;
    let mut report = SourceReport::default();
    let mut tried = Vec::new();
    let mut failed_in_a_row = 0;
    let licence = content::accepted_licence("CC BY-SA 4.0").ok_or(IngestError::Implausible {
        what: "CC BY-SA 4.0 is not recognised".into(),
    })?;
    'run: while report.places < ctx.config.max_places {
        let batch = due(ctx, &id, None, &tried).await?;
        if batch.is_empty() {
            break;
        }
        let items = wikidata_items(ctx, &batch).await;
        if let Err(e) = &items {
            tracing::warn!(error = %e, "wikidata items unavailable");
        }
        let mut wanted: Vec<(&DuePlace, Vec<(String, String)>)> = Vec::new();
        for place in &batch {
            let osm: Vec<(String, String)> = place
                .links
                .wikipedia
                .iter()
                .filter_map(|v| content::wikipedia_article(v))
                .collect();
            let mut from_items = BTreeMap::new();
            if let Ok(items) = &items {
                for q in &place.links.wikidata {
                    if let Some(item) = lunaway_domain::conflation::normalize::normalize_wikidata(q)
                        .and_then(|q| items.get(&q))
                    {
                        for (l, t) in &item.articles {
                            from_items.entry(l.clone()).or_insert_with(|| t.clone());
                        }
                    }
                }
            }
            let chosen =
                wikipedia::choose_articles(&osm, &from_items, place.country_code.as_deref());
            wanted.push((place, chosen));
        }
        let mut by_lang: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
        for (_, articles) in &wanted {
            for (lang, title) in articles {
                by_lang
                    .entry(lang.clone())
                    .or_default()
                    .insert(title.clone());
            }
        }
        let mut extracts: BTreeMap<(String, String), wikipedia::Extract> = BTreeMap::new();
        let mut failed_langs: BTreeMap<String, String> = BTreeMap::new();
        for (lang, titles) in &by_lang {
            let titles: Vec<String> = titles.iter().cloned().collect();
            let Some(api) = wikipedia::wikipedia_api(&ctx.config.endpoints.wikipedia, lang) else {
                continue;
            };
            for chunk in titles.chunks(wikipedia::TITLES_PER_REQUEST) {
                let Some(url) = wikipedia::extracts_url(&api, chunk) else {
                    continue;
                };
                let got = match ctx
                    .api(&ctx.wikimedia, &api, &url, "wikipedia extracts")
                    .await
                {
                    Ok(body) => wikipedia::parse_extracts(&body, lang, chunk),
                    Err(e) => Err(e),
                };
                match got {
                    Ok(found) => {
                        for (title, e) in found {
                            extracts.insert((lang.clone(), title), e);
                        }
                    }
                    Err(e) => {
                        failed_langs.insert(lang.clone(), e.to_string());
                    }
                }
            }
        }
        for (place, articles) in wanted {
            if report.places >= ctx.config.max_places {
                break 'run;
            }
            tried.push(place.id);
            report.places += 1;
            let failure = if items.is_err() && !place.links.wikidata.is_empty() {
                Some("wikidata items unavailable".to_owned())
            } else {
                articles
                    .iter()
                    .find_map(|(lang, _)| failed_langs.get(lang))
                    .map(|e| format!("wikipedia extracts failed: {e}"))
            };
            let outcome = if let Some(what) = failure {
                Outcome::Failed(IngestError::Implausible { what })
            } else {
                let descriptions: Vec<NewDescription> = articles
                    .iter()
                    .filter_map(|(lang, title)| {
                        let e = extracts.get(&(lang.clone(), title.clone()))?;
                        Some(NewDescription {
                            lang: lang.clone(),
                            text: e.text.clone(),
                            title: Some(e.title.clone()),
                            page_url: e.url.clone(),
                            author: None,
                            publisher: Some("Wikipedia".to_owned()),
                            source_updated_on: None,
                            licence: licence.name.clone(),
                            licence_url: licence.url.clone(),
                        })
                    })
                    .collect();
                let kept = descriptions.len();
                let mut removed = 0;
                let work = async {
                    let r = db::replace_descriptions(
                        ctx.pool,
                        place.id,
                        id.as_str(),
                        &descriptions,
                        Utc::now(),
                        kept,
                    )
                    .await?;
                    removed = r.removed;
                    Ok(kept)
                };
                let outcome = guarded(ctx, place.id, &id, work).await?;
                report.removed += removed;
                outcome
            };
            if let Some(why) = tally(
                &mut report,
                outcome,
                &mut failed_in_a_row,
                ctx.config.max_failures,
                place.id,
            ) {
                report.stopped = Some(why);
                break 'run;
            }
        }
    }
    Ok(report)
}

/// Pages of Mangrove reviews read at most: 11 held every review on
/// 2026-10-07 (10 803). A source that keeps sending pages past it is not
/// taken as read whole.
const MANGROVE_MAX_PAGES: usize = 100;

/// How far from where a review says it is a place is looked for, metres.
const REVIEW_SEARCH_M: f64 = 300.0;

/// Mangrove reviews kept per place at most, the newest: a place is not
/// filled by one author with many keys.
pub const MAX_REVIEWS_PER_PLACE: usize = 10;

/// Mangrove: every review read, those about places on the map matched to
/// a place, and the whole set stored in place of the last one. Nothing is
/// replaced unless every page was read.
async fn mangrove_pass(ctx: &Ctx<'_>) -> Result<SourceReport, IngestError> {
    let id = SourceId::MANGROVE;
    let mut report = SourceReport::default();
    if ctx.config.area.is_some() {
        report.stopped = Some(
            "Mangrove is read whole and replaces every review: it runs without an area".into(),
        );
        return Ok(report);
    }
    let endpoint = &ctx.config.endpoints.mangrove;
    let pacer = Pacer::new(ctx.config.mangrove_pace);
    let mut reviews = Vec::new();
    let mut offset = 0;
    let mut complete = false;
    for _ in 0..MANGROVE_MAX_PAGES {
        let page = match mangrove::page_url(endpoint, offset) {
            Ok(url) => ctx.api(&pacer, endpoint, &url, "mangrove reviews").await,
            Err(e) => Err(e),
        }
        .and_then(|body| mangrove::parse_page(&body));
        let (kept, skipped, total) = match page {
            Ok(p) => p,
            Err(e) => {
                report.stopped = Some(format!("a page of reviews failed: {e}"));
                return Ok(report);
            }
        };
        skipped.iter().for_each(|s| report.skip(s));
        reviews.extend(kept);
        // The server drops the older edits of a review after it took the
        // page, so a page holds fewer than asked while more follow: the
        // offset counts what it took, and only an empty page ends.
        if total == 0 {
            complete = true;
            break;
        }
        offset += mangrove::PAGE_SIZE;
    }
    if !complete {
        report.stopped = Some(format!(
            "more than {MANGROVE_MAX_PAGES} pages of reviews: nothing replaced"
        ));
        return Ok(report);
    }
    let mut matched: Vec<NewReview> = Vec::new();
    for r in reviews {
        let at = r.subject.position;
        let near = db::places_near(ctx.pool, at.lat(), at.lon(), REVIEW_SEARCH_M).await?;
        // Each candidate stays beside its place, so the index the matching
        // returns names the right one.
        let paired: Vec<(&db::NearPlace, ReviewCandidate<'_>)> = near
            .iter()
            .filter_map(|p| {
                Some((
                    p,
                    ReviewCandidate {
                        position: Position::new(p.lat, p.lon).ok()?,
                        kind: p.kind.parse().ok()?,
                        name: p.name.as_deref(),
                    },
                ))
            })
            .collect();
        let candidates: Vec<ReviewCandidate<'_>> = paired.iter().map(|(_, c)| *c).collect();
        let Some((place, candidate)) =
            content::review_place(&r.subject, &candidates).and_then(|i| paired.get(i))
        else {
            report.skip("NoPlace");
            continue;
        };
        #[allow(clippy::cast_possible_truncation, reason = "metres, shown rounded")]
        let distance_m = Some(candidate.position.distance_m(at) as f32);
        matched.push(NewReview {
            place_id: place.id,
            external_id: r.signature,
            rating: r.stars.map(i16::from),
            text: r.text,
            lang: None,
            author: r.author,
            author_key: r.author_key,
            written_at: r.written_at,
            page_url: r.page_url,
            licence: r.licence.name,
            licence_url: r.licence.url,
            distance_m,
        });
    }
    // What an operator hid takes no room: then the newest first, one per
    // author key and place, at most a few per place.
    let (hidden_items, hidden_authors) = db::hidden_keys(ctx.pool, id.as_str()).await?;
    matched.retain(|r| {
        !hidden_items.contains(&r.external_id)
            && r.author_key
                .as_ref()
                .is_none_or(|k| !hidden_authors.contains(k))
    });
    matched.sort_by_key(|r| std::cmp::Reverse(r.written_at));
    let mut per_place: BTreeMap<Uuid, usize> = BTreeMap::new();
    let mut per_author: BTreeSet<(Uuid, String)> = BTreeSet::new();
    matched.retain(|r| {
        if let Some(k) = &r.author_key
            && !per_author.insert((r.place_id, k.clone()))
        {
            return false;
        }
        let n = per_place.entry(r.place_id).or_default();
        *n += 1;
        *n <= MAX_REVIEWS_PER_PLACE
    });
    report.places = per_place.len();
    report.with_content = per_place.len();
    let replaced = db::replace_reviews(ctx.pool, id.as_str(), &matched, Utc::now()).await?;
    report.items = replaced.kept;
    report.removed = replaced.removed;
    Ok(report)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tourist_office_photo_hosts_are_a_closed_list() {
        assert!(datatourisme_media_host("cdt24.media.tourinsoft.eu"));
        assert!(datatourisme_media_host("static.apidae-tourisme.com"));
        assert!(!datatourisme_media_host("tourinsoft.eu.evil.example"));
        assert!(!datatourisme_media_host(".tourinsoft.eu"));
        assert!(!datatourisme_media_host("example.org"));
        assert!(!datatourisme_media_host("169.254.169.254"));
    }

    #[test]
    fn sources_are_named_on_the_command_line() {
        for s in ContentSource::ALL {
            let name = match s {
                ContentSource::Commons => "commons",
                ContentSource::Wikipedia => "wikipedia",
                ContentSource::Panoramax => "panoramax",
                ContentSource::Datatourisme => "datatourisme",
                ContentSource::Mangrove => "mangrove",
            };
            assert_eq!(ContentSource::parse(name), Some(s));
        }
        assert_eq!(
            ContentSource::parse("mapillary"),
            None,
            "not a source of Lunaway"
        );
    }
}
