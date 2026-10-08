//! Regional first-sync packs: every live place of a sync region in one
//! compressed SQLite file a device downloads once, attaches to its own
//! cache and copies from, then follows with `changes(region:, since: <the
//! pack's cursor>)` (`docs/region-packs.md`).
//!
//! A build reads one snapshot of the database ([`Snapshot`]), so every
//! pack holds the places of one instant and its cursor continues the feed
//! exactly from there: a place changed or deleted after the snapshot comes
//! with the first `changes` page.
//!
//! The values are the GraphQL API's own: each chunk of places goes through
//! this API's `Place` resolvers with the selection the app keeps offline
//! ([`PLACE_SELECTION`]), and each column holds a field of that JSON (lists
//! and objects as JSON text), so a pack and a `changes` page cannot
//! disagree on a value. One field is narrowed: `descriptions` keeps the
//! texts the app's card can show ([`APP_LANGUAGES`]), the descriptions of
//! the external community source in German, Spanish, Dutch or Italian
//! being most of what its places weigh.
//!
//! SQLite rather than one JSON object per line: on the France packs
//! (18 391 places), the app's own SQLite build copied an attached pack into
//! a cache shaped like the app's in 0.29 to 0.34 s, against 1.04 to 1.46 s
//! to decode and insert the same places from JSON lines, for 2.66 MB to
//! download instead of 2.18 MB (`plan/research/23-backend-europe-packs.md`).

use std::{
    collections::HashMap,
    io::Write,
    path::{Path, PathBuf},
    sync::Mutex,
};

use async_graphql::{
    Context, EmptyMutation, EmptySubscription, Object, Request, Schema, dataloader::DataLoader,
};
use chrono::Utc;
use lunaway_db::{
    PgPool,
    packs::{self, RegionPack, Snapshot},
    places::{PlaceRow, PlaceSourceRow},
};
use serde_json::Value;
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::{ApiConfig, ApiState, loaders::PlaceSourcesLoader, types::Place};

/// The fields of a place a pack holds: the app's `PlaceFields` fragment
/// (`app/lib/features/places/data/graphql/operations.dart`), the vehicle
/// limits and the sync region. A field the app adds to its offline copy is
/// added here and to [`COLUMNS`], with a new [`FORMAT`].
pub const PLACE_SELECTION: &str = "
  id name kind lat lon overnight services activities description
  address { street postcode city countryCode }
  municipality region
  priceParkingEur priceServicesEur maxHeightM maxLengthM maxWidthM maxWeightT capacity stars
  openingHours openingHoursParsed openingIntervals { start end } openingIntervalsUntil
  website phone lastConfirmedAt updatedAt
  sources {
    source { id name licence attribution url }
    externalId externalUrl fetchedAt matchScore
  }
  provenance { field sourceId alternatives { sourceId value } }
  descriptions { lang text sourceId }
  ratings { sourceId average count }
  externalLinks { sourceId url label }
  verification reviewCount photoCount
  coverPhotos { id sourceId thumbUrl largeUrl width height thumbhash authorId }
  reportedIssues { kind count lastReportedAt }
";

/// The format and its version, as `Query.regions` gives it.
pub const FORMAT: &str = "sqlite-gzip-1";

/// The languages the app writes its screens in (`app/lib/i18n/`): its card
/// shows the description in the screen's language, else in English, else
/// the first one (`descriptionFor`,
/// `app/lib/features/places/domain/place_content.dart`), so a pack keeps
/// only those ([`shown_descriptions`]). The external community source
/// describes its spots in up to six languages: on the region pack of
/// Auvergne-Rhône-Alpes of 2026-10-08, the texts in other languages were
/// 4094 of 9354 and a quarter of the compressed file (1 767 887 bytes,
/// 1 343 421 without them). The change feed and `Query.place` keep every
/// language; a language the app adds is added here, and a test reads the
/// app's list. A device keeps the pack it imported until each place
/// changes: the texts in a language added later reach the places that
/// never change only with a new pack (a new [`FORMAT`] makes the app take
/// one).
pub const APP_LANGUAGES: &[&str] = &["fr", "en"];

/// How a field of the place's JSON goes into its column.
#[derive(Debug, Clone, Copy)]
enum Field {
    /// A scalar at this key (a string, a number, a boolean as 0 or 1).
    Scalar(&'static str),
    /// A scalar of the `address` object.
    Address(&'static str),
    /// A list or an object at this key, as JSON text (`null` stays NULL).
    Json(&'static str),
    /// The list of descriptions at this key, narrowed to those the app can
    /// show ([`shown_descriptions`]), as JSON text.
    Descriptions(&'static str),
}

/// The columns of the `places` table of a pack, in order, with their SQL
/// type and the field each holds. `docs/region-packs.md` is the contract.
const COLUMNS: &[(&str, &str, Field)] = &[
    ("id", "TEXT NOT NULL", Field::Scalar("id")),
    ("name", "TEXT", Field::Scalar("name")),
    ("kind", "TEXT NOT NULL", Field::Scalar("kind")),
    ("lat", "REAL NOT NULL", Field::Scalar("lat")),
    ("lon", "REAL NOT NULL", Field::Scalar("lon")),
    ("overnight", "TEXT NOT NULL", Field::Scalar("overnight")),
    ("services", "TEXT NOT NULL", Field::Json("services")),
    ("activities", "TEXT NOT NULL", Field::Json("activities")),
    ("description", "TEXT", Field::Scalar("description")),
    ("street", "TEXT", Field::Address("street")),
    ("postcode", "TEXT", Field::Address("postcode")),
    ("city", "TEXT", Field::Address("city")),
    ("country_code", "TEXT", Field::Address("countryCode")),
    ("municipality", "TEXT", Field::Scalar("municipality")),
    ("region", "TEXT", Field::Scalar("region")),
    (
        "price_parking_eur",
        "REAL",
        Field::Scalar("priceParkingEur"),
    ),
    (
        "price_services_eur",
        "REAL",
        Field::Scalar("priceServicesEur"),
    ),
    ("max_height_m", "REAL", Field::Scalar("maxHeightM")),
    ("max_length_m", "REAL", Field::Scalar("maxLengthM")),
    ("max_width_m", "REAL", Field::Scalar("maxWidthM")),
    ("max_weight_t", "REAL", Field::Scalar("maxWeightT")),
    ("capacity", "INTEGER", Field::Scalar("capacity")),
    ("stars", "INTEGER", Field::Scalar("stars")),
    ("opening_hours", "TEXT", Field::Scalar("openingHours")),
    (
        "opening_hours_parsed",
        "INTEGER NOT NULL",
        Field::Scalar("openingHoursParsed"),
    ),
    ("opening_intervals", "TEXT", Field::Json("openingIntervals")),
    (
        "opening_intervals_until",
        "TEXT",
        Field::Scalar("openingIntervalsUntil"),
    ),
    ("website", "TEXT", Field::Scalar("website")),
    ("phone", "TEXT", Field::Scalar("phone")),
    (
        "last_confirmed_at",
        "TEXT",
        Field::Scalar("lastConfirmedAt"),
    ),
    ("updated_at", "TEXT NOT NULL", Field::Scalar("updatedAt")),
    ("sources", "TEXT NOT NULL", Field::Json("sources")),
    ("provenance", "TEXT NOT NULL", Field::Json("provenance")),
    (
        "descriptions",
        "TEXT NOT NULL",
        Field::Descriptions("descriptions"),
    ),
    ("ratings", "TEXT NOT NULL", Field::Json("ratings")),
    (
        "external_links",
        "TEXT NOT NULL",
        Field::Json("externalLinks"),
    ),
    (
        "verification",
        "TEXT NOT NULL",
        Field::Scalar("verification"),
    ),
    (
        "review_count",
        "INTEGER NOT NULL",
        Field::Scalar("reviewCount"),
    ),
    (
        "photo_count",
        "INTEGER NOT NULL",
        Field::Scalar("photoCount"),
    ),
    ("cover_photos", "TEXT NOT NULL", Field::Json("coverPhotos")),
    (
        "reported_issues",
        "TEXT NOT NULL",
        Field::Json("reportedIssues"),
    ),
];

/// Places run through the resolvers at once: bounds the memory a chunk's
/// JSON holds.
const CHUNK: usize = 2_000;

/// The licence and attribution every pack carries, as the places database
/// does.
const LICENCE: &str = "ODbL-1.0";
const ATTRIBUTION: &str = "© OpenStreetMap contributors, Lunaway contributors and the sources \
                           each place lists (docs/data-sources.md)";

/// The licence and attribution of a pack whose places list `sources`: the
/// ODbL, and, when a place carries values of a source an agreement keeps
/// out of the open licence (`extcom`), the exception said in so many words
/// with that source's attribution (`docs/data-sources.md`, "Licences of
/// the places database"). A pack is a file anyone may copy: it must not
/// label the partner's values as open data.
fn pack_terms<'a>(sources: impl IntoIterator<Item = &'a PlaceSourceRow>) -> (String, String) {
    let withheld = sources
        .into_iter()
        .find(|s| !lunaway_domain::conflation::public_dump::in_public_dump(&s.source_id));
    match withheld {
        None => (LICENCE.to_owned(), ATTRIBUTION.to_owned()),
        Some(s) => (
            format!(
                "{LICENCE}, except the values whose provenance is `{}` ({}), licensed under its \
                 written agreement ({}) and excluded from any public dump",
                s.source_id, s.source_name, s.licence
            ),
            format!("{ATTRIBUTION}; {}", s.attribution),
        ),
    }
}

/// What can stop a build.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum PackError {
    /// The database failed.
    #[error(transparent)]
    Db(#[from] lunaway_db::DbError),
    /// A file could not be written.
    #[error("pack file {path}")]
    Io {
        /// The file.
        path: PathBuf,
        /// The cause.
        #[source]
        source: std::io::Error,
    },
    /// The pack's SQLite file could not be written.
    #[error("pack database {path}")]
    Sqlite {
        /// The file.
        path: PathBuf,
        /// The cause.
        #[source]
        source: rusqlite::Error,
    },
    /// The resolvers refused a place.
    #[error("the resolvers failed on region {region}: {message}")]
    Resolve {
        /// The region.
        region: String,
        /// Their messages.
        message: String,
    },
    /// A JSON value did not serialise.
    #[error("pack JSON")]
    Json(#[source] serde_json::Error),
    /// A blocking task panicked or was cancelled.
    #[error("blocking task failed")]
    Blocking(#[source] tokio::task::JoinError),
    /// A region asked for is not a sync region: a mistyped takedown would
    /// otherwise build nothing and look done.
    #[error("{0:?} is not a sync region")]
    UnknownRegion(String),
    /// The builders' lock was lost during the build (its session ended):
    /// another build may have run beside this one, so nothing was recorded.
    #[error("the pack build lock was lost; nothing recorded")]
    LockLost,
}

/// What to build.
#[derive(Debug, Clone)]
pub struct PackOptions {
    /// The directory the backend serves under `/packs/`; files go to its
    /// `places/` subdirectory.
    pub dir: PathBuf,
    /// Only these regions; every region with places when empty.
    pub only: Vec<String>,
    /// After a place was taken down (personal data, a court order): builds
    /// the packs of `only` even when nothing changed in them, builds every
    /// other region whose pack is behind (the place may have left one of
    /// them), and removes every pack file the manifest does not name, so
    /// no file still serves the place. The place's tombstone must be in the
    /// change feed first (a new `updated_seq`), or its region does not
    /// look behind.
    pub takedown: bool,
}

/// A pack built.
#[derive(Debug, Clone, PartialEq)]
pub struct Built {
    /// What the table now says of it.
    pub pack: RegionPack,
    /// Files of older packs of its region removed.
    pub removed: Vec<String>,
}

/// A region that no longer has a live place: no pack, no file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Dropped {
    /// The region.
    pub region: String,
    /// Its files removed.
    pub removed: Vec<String>,
}

/// What a build did.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct BuildReport {
    /// The packs built.
    pub built: Vec<Built>,
    /// The regions whose packs were withdrawn.
    pub dropped: Vec<Dropped>,
    /// Pack files the manifest no longer names, removed by a takedown.
    pub pruned: Vec<String>,
}

/// The root of the schema a build runs the places through: it answers the
/// chunk handed with the request.
struct PackRoot;

struct Chunk(Mutex<Option<Vec<PlaceRow>>>);

#[Object]
impl PackRoot {
    async fn places(&self, ctx: &Context<'_>) -> Vec<Place> {
        ctx.data_unchecked::<Chunk>()
            .0
            .lock()
            .ok()
            .and_then(|mut c| c.take())
            .unwrap_or_default()
            .into_iter()
            .map(Place)
            .collect()
    }
}

/// A pack being written: an SQLite file with a `pack` table (what the pack
/// is) and a `places` table ([`COLUMNS`]).
struct Writer {
    conn: rusqlite::Connection,
    path: PathBuf,
}

impl Writer {
    fn create(path: &Path) -> Result<Self, PackError> {
        let err = |source| PackError::Sqlite {
            path: path.to_owned(),
            source,
        };
        // An empty file made by `tempfile`, which SQLite opens as an empty
        // database.
        let conn = rusqlite::Connection::open(path).map_err(err)?;
        // A plain table with rowids: rows of about 2 KB stay on their leaf
        // page, where a table keyed by the id spilled them over overflow
        // pages and doubled the file (9.4 MB against 4.3 MB for one region).
        let columns: Vec<String> = COLUMNS
            .iter()
            .map(|(name, ty, _)| format!("{name} {ty}"))
            .collect();
        conn.execute_batch(&format!(
            "PRAGMA page_size = 4096; PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF;
             CREATE TABLE pack (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
             CREATE TABLE places ({});
             BEGIN;",
            columns.join(", ")
        ))
        .map_err(err)?;
        Ok(Self {
            conn,
            path: path.to_owned(),
        })
    }

    fn err(&self) -> impl Fn(rusqlite::Error) -> PackError + '_ {
        |source| PackError::Sqlite {
            path: self.path.clone(),
            source,
        }
    }

    fn describe(&self, entries: &[(&str, String)]) -> Result<(), PackError> {
        let mut insert = self
            .conn
            .prepare("INSERT INTO pack (key, value) VALUES (?1, ?2)")
            .map_err(self.err())?;
        for (key, value) in entries {
            insert.execute((key, value)).map_err(self.err())?;
        }
        Ok(())
    }

    fn insert(&self, places: &[Value]) -> Result<(), PackError> {
        let names: Vec<&str> = COLUMNS.iter().map(|(name, _, _)| *name).collect();
        let marks: Vec<String> = (1..=COLUMNS.len()).map(|i| format!("?{i}")).collect();
        let mut insert = self
            .conn
            .prepare(&format!(
                "INSERT INTO places ({}) VALUES ({})",
                names.join(", "),
                marks.join(", ")
            ))
            .map_err(self.err())?;
        for place in places {
            let values: Vec<rusqlite::types::Value> = COLUMNS
                .iter()
                .map(|(_, _, field)| column(place, *field))
                .collect::<Result<_, _>>()?;
            insert
                .execute(rusqlite::params_from_iter(values))
                .map_err(self.err())?;
        }
        Ok(())
    }

    fn finish(self) -> Result<PathBuf, PackError> {
        self.conn.execute_batch("COMMIT;").map_err(self.err())?;
        self.conn.close().map_err(|(_, source)| PackError::Sqlite {
            path: self.path.clone(),
            source,
        })?;
        Ok(self.path)
    }
}

/// The value of one column of a place.
fn column(place: &Value, field: Field) -> Result<rusqlite::types::Value, PackError> {
    use rusqlite::types::Value as Sql;
    let scalar = |v: Option<&Value>| match v {
        None | Some(Value::Null) => Sql::Null,
        Some(Value::Bool(b)) => Sql::Integer(i64::from(*b)),
        Some(Value::Number(n)) => n
            .as_i64()
            .map(Sql::Integer)
            .or_else(|| n.as_f64().map(Sql::Real))
            .unwrap_or(Sql::Null),
        Some(Value::String(s)) => Sql::Text(s.clone()),
        Some(other) => Sql::Text(other.to_string()),
    };
    Ok(match field {
        Field::Scalar(key) => scalar(place.get(key)),
        Field::Address(key) => scalar(place.get("address").and_then(|a| a.get(key))),
        Field::Json(key) => match place.get(key) {
            None | Some(Value::Null) => Sql::Null,
            Some(v) => Sql::Text(serde_json::to_string(v).map_err(PackError::Json)?),
        },
        Field::Descriptions(key) => match place.get(key) {
            None | Some(Value::Null) => Sql::Null,
            Some(Value::Array(list)) => Sql::Text(
                serde_json::to_string(&shown_descriptions(list)).map_err(PackError::Json)?,
            ),
            Some(v) => Sql::Text(serde_json::to_string(v).map_err(PackError::Json)?),
        },
    })
}

/// The descriptions of `list` (`{lang, text, sourceId}`, in the API's
/// order) the app's card can pick: those in a language of
/// [`APP_LANGUAGES`], and the first one when none is in English, the
/// card's fallback. The card then picks the same text from the pack as
/// from the full list, whatever the screen's language.
fn shown_descriptions(list: &[Value]) -> Vec<&Value> {
    fn lang(d: &Value) -> Option<&str> {
        d.get("lang").and_then(Value::as_str)
    }
    let english = list.iter().any(|d| lang(d) == Some("en"));
    list.iter()
        .enumerate()
        .filter(|(i, d)| {
            lang(d).is_some_and(|l| APP_LANGUAGES.contains(&l)) || (!english && *i == 0)
        })
        .map(|(_, d)| d)
        .collect()
}

/// Builds the pack of every sync region with places (or of `only`) whose
/// current pack predates a change of its places, records each in
/// `region_packs` and removes the files of the packs before the previous
/// one: a device that read the manifest just before a build still finds the
/// file it names. A region nothing changed in keeps its pack, so a device
/// that has it finds no new version. A region left without a live place
/// loses its pack and every file of it. One build runs at a time
/// ([`packs::BuildLock`]); a second waits for the first.
///
/// # Errors
///
/// [`PackError`] when the database, a resolver or a file fails; the packs
/// recorded before stay; [`PackError::UnknownRegion`] when `only` names a
/// code that is not a sync region.
pub async fn build(
    pool: &PgPool,
    config: ApiConfig,
    options: &PackOptions,
) -> Result<BuildReport, PackError> {
    // The codes as the catalogue writes them: `fr-bre` names `FR-BRE`.
    let only: Vec<String> = options
        .only
        .iter()
        .map(|r| {
            lunaway_domain::region::sync_region(r)
                .map(|s| s.code.to_owned())
                .ok_or_else(|| PackError::UnknownRegion(r.clone()))
        })
        .collect::<Result<_, _>>()?;
    let mut lock = packs::BuildLock::acquire(pool).await?;
    let built = build_locked(pool, config, options, &only, &mut lock).await;
    let released = lock.release().await;
    if let (Err(_), Err(error)) = (&built, &released) {
        tracing::warn!(%error, "the pack build lock was not released cleanly");
    }
    let built = built?;
    // A release that fails most likely means the session ended during the
    // build, after its last check: the operator must hear of it.
    released?;
    Ok(built)
}

async fn build_locked(
    pool: &PgPool,
    config: ApiConfig,
    options: &PackOptions,
    only: &[String],
    lock: &mut packs::BuildLock,
) -> Result<BuildReport, PackError> {
    let dir = options.dir.join("places");
    // Files being written, beside the served ones on the same disk (an
    // atomic rename) but outside `places/`: a half-written pack or the raw
    // database of a build that stopped is never served. What a stopped
    // build left there goes now; builds run one at a time.
    let work = options.dir.join(".work");
    for d in [&dir, &work] {
        tokio::fs::create_dir_all(d)
            .await
            .map_err(|source| PackError::Io {
                path: d.clone(),
                source,
            })?;
    }
    clear_work(&work).await?;
    let current: HashMap<String, RegionPack> = packs::all(pool)
        .await?
        .into_iter()
        .map(|p| (p.region.clone(), p))
        .collect();
    let mut snapshot = Snapshot::begin(pool).await?;
    let head = snapshot.feed_head().await?;
    let identity = head.identity();
    let regions: Vec<_> = snapshot
        .regions()
        .await?
        .into_iter()
        .filter(|r| lunaway_domain::region::sync_region(&r.region).is_some())
        .filter(|r| only.is_empty() || options.takedown || only.contains(&r.region))
        .collect();
    let query = format!("{{ places {{ {PLACE_SELECTION} }} }}");
    let cursor = crate::schema::changes_cursor(&head, head.last_seq);
    let fingerprint = fingerprint(&config);
    let state = ApiState::new(pool.clone(), config);
    let mut built = Vec::with_capacity(regions.len());
    for extent in &regions {
        let forced = options.takedown && only.contains(&extent.region);
        let up_to_date = !forced
            && current.get(&extent.region).is_some_and(|p| {
                p.feed_identity == identity
                    && p.seq >= extent.last_seq
                    && p.fingerprint.as_deref() == Some(fingerprint.as_str())
                    && options.dir.join(&p.file).is_file()
            });
        if up_to_date {
            continue;
        }
        let mut places = snapshot.places(&extent.region).await?;
        let ids: Vec<Uuid> = places.iter().map(|p| p.id).collect();
        let mut sources: HashMap<Uuid, Vec<PlaceSourceRow>> = HashMap::with_capacity(ids.len());
        for chunk in ids.chunks(10_000) {
            for row in snapshot.sources_of(chunk).await? {
                sources.entry(row.place_id).or_default().push(row);
            }
        }
        let (licence, attribution) = pack_terms(sources.values().flatten());
        // The cover photos' URLs come from the API's configuration, the
        // rest from the snapshot.
        let schema = Schema::build(PackRoot, EmptyMutation, EmptySubscription)
            .data(DataLoader::new(
                PlaceSourcesLoader::Read(sources),
                tokio::spawn,
            ))
            .data(state.clone())
            .finish();
        let generated_at = Utc::now();
        let describe = vec![
            ("format", FORMAT.to_owned()),
            ("region", extent.region.clone()),
            ("cursor", cursor.clone()),
            ("places", extent.places.to_string()),
            ("generatedAt", generated_at.to_rfc3339()),
            ("licence", licence),
            ("attribution", attribution),
        ];
        let work_dir = work.clone();
        let (mut writer, raw_file) = blocking(move || {
            // The raw database, removed when dropped, whichever way the
            // build ends.
            let raw_file = tempfile::Builder::new()
                .prefix("raw-")
                .suffix(".sqlite")
                .tempfile_in(&work_dir)
                .map_err(|source| PackError::Io {
                    path: work_dir.clone(),
                    source,
                })?
                .into_temp_path();
            let w = Writer::create(&raw_file)?;
            w.describe(&describe)?;
            Ok((w, raw_file))
        })
        .await?;
        while !places.is_empty() {
            let rest = places.split_off(places.len().min(CHUNK));
            let chunk = std::mem::replace(&mut places, rest);
            let response = schema
                .execute(Request::new(query.as_str()).data(Chunk(Mutex::new(Some(chunk)))))
                .await;
            if !response.errors.is_empty() {
                let message: Vec<String> =
                    response.errors.iter().map(|e| e.message.clone()).collect();
                return Err(PackError::Resolve {
                    region: extent.region.clone(),
                    message: message.join("; "),
                });
            }
            let mut data = response.data.into_json().map_err(PackError::Json)?;
            let list = match data.get_mut("places").map(Value::take) {
                Some(Value::Array(list)) => list,
                _ => Vec::new(),
            };
            writer = blocking(move || {
                writer.insert(&list)?;
                Ok(writer)
            })
            .await?;
        }
        let raw_path = blocking(move || writer.finish()).await?;
        let raw = tokio::fs::read(&raw_path)
            .await
            .map_err(|source| PackError::Io {
                path: raw_path.clone(),
                source,
            })?;
        let raw_bytes = raw.len();
        let gz_dir = dir.clone();
        let (compressed, sha256) = blocking(move || {
            let compressed = gzip(&raw, &gz_dir)?;
            let sha256: String = Sha256::digest(&compressed)
                .iter()
                .map(|b| format!("{b:02x}"))
                .collect();
            raw_file.close().map_err(|source| PackError::Io {
                path: raw_path,
                source,
            })?;
            Ok((compressed, sha256))
        })
        .await?;
        let file_name = format!(
            "{}-{}-{}.sqlite.gz",
            extent.region,
            head.last_seq,
            &sha256[..12]
        );
        write_atomically(&work, &dir.join(&file_name), &compressed).await?;
        let pack = RegionPack {
            region: extent.region.clone(),
            seq: head.last_seq,
            feed_identity: head.identity(),
            places: i32::try_from(extent.places).unwrap_or(i32::MAX),
            south: extent.south,
            west: extent.west,
            north: extent.north,
            east: extent.east,
            file: format!("places/{file_name}"),
            format: FORMAT.to_owned(),
            bytes: i64::try_from(compressed.len()).unwrap_or(i64::MAX),
            raw_bytes: i64::try_from(raw_bytes).unwrap_or(i64::MAX),
            sha256,
            generated_at,
            fingerprint: Some(fingerprint.clone()),
        };
        tracing::info!(
            region = %pack.region,
            places = pack.places,
            bytes = pack.bytes,
            raw_bytes = pack.raw_bytes,
            "pack written"
        );
        built.push(pack);
    }
    snapshot.end().await?;
    // Packs from a snapshot older than a build that ran beside this one
    // must not be recorded after it.
    if !lock.held().await? {
        return Err(PackError::LockLost);
    }
    let mut out = BuildReport::default();
    for pack in built {
        let previous = packs::record(pool, &pack).await?;
        let keep_previous = previous.as_deref().filter(|_| !options.takedown);
        let removed = remove_older(&dir, &pack, keep_previous).await?;
        out.built.push(Built { pack, removed });
    }
    let keep: Vec<String> = regions.iter().map(|r| r.region.clone()).collect();
    // A region whose last place went (taken down, moved, retired) keeps no
    // pack: its last file would still serve the place. Its files go before
    // its row, so a removal that fails is tried again by the next build.
    let whole = only.is_empty() || options.takedown;
    let mut gone: Vec<String> = current.keys().filter(|_| whole).cloned().collect();
    gone.extend(only.iter().cloned());
    gone.retain(|r| !keep.contains(r));
    gone.sort_unstable();
    gone.dedup();
    for region in &gone {
        let removed = remove_region(&dir, region).await?;
        out.dropped.push(Dropped {
            region: region.clone(),
            removed,
        });
    }
    if whole {
        packs::forget_others(pool, &keep).await?;
    } else if !gone.is_empty() {
        packs::forget(pool, &gone).await?;
    }
    if options.takedown {
        // The place may have left another region, whose previous file
        // still holds it, or sit in a file a stopped build wrote and never
        // recorded: only the packs the manifest names stay.
        let recorded: Vec<String> = packs::all(pool)
            .await?
            .into_iter()
            .map(|p| p.file)
            .collect();
        out.pruned = remove_unrecorded(&dir, &recorded).await?;
    }
    Ok(out)
}

/// What a pack depends on besides its places: its format, the fields it
/// holds and the photos' public URL its cover photos name. A new format, a
/// field added or a URL moved (the photos' host changing, as it did to
/// `https://api.lunaway.net/media/`) rebuilds every pack, changed region or
/// not.
fn fingerprint(config: &ApiConfig) -> String {
    let digest = Sha256::digest(
        format!(
            "{FORMAT}\n{PLACE_SELECTION}\n{}\n{}",
            config.media.base_url,
            APP_LANGUAGES.join(",")
        )
        .as_bytes(),
    );
    digest.iter().take(8).map(|b| format!("{b:02x}")).collect()
}

/// Runs `f` on a blocking thread: SQLite and gzip are CPU and disk work.
async fn blocking<T: Send + 'static>(
    f: impl FnOnce() -> Result<T, PackError> + Send + 'static,
) -> Result<T, PackError> {
    tokio::task::spawn_blocking(f)
        .await
        .map_err(PackError::Blocking)?
}

fn gzip(bytes: &[u8], dir: &Path) -> Result<Vec<u8>, PackError> {
    let io = |source| PackError::Io {
        path: dir.to_owned(),
        source,
    };
    let mut encoder = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::best());
    encoder.write_all(bytes).map_err(io)?;
    encoder.finish().map_err(io)
}

/// Writes `bytes` to `path` through a file of `work`, so `path` appears
/// whole or not at all.
async fn write_atomically(work: &Path, path: &Path, bytes: &[u8]) -> Result<(), PackError> {
    let io = |source| PackError::Io {
        path: path.to_owned(),
        source,
    };
    let name = path.file_name().unwrap_or_default().to_string_lossy();
    let tmp = work.join(format!("{name}.partial"));
    let written = match tokio::fs::write(&tmp, bytes).await {
        Ok(()) => tokio::fs::rename(&tmp, path).await,
        Err(e) => Err(e),
    };
    if written.is_err() {
        // A disk full or a rename refused leaves no half file behind; one
        // left by a crash goes at the next build (`clear_work`).
        let _ignored = tokio::fs::remove_file(&tmp).await;
    }
    written.map_err(io)
}

/// Removes what a build that stopped left in `work`: half-written packs
/// and raw databases, which hold places that may since have been taken
/// down.
async fn clear_work(work: &Path) -> Result<(), PackError> {
    let io = |source| PackError::Io {
        path: work.to_owned(),
        source,
    };
    let mut entries = tokio::fs::read_dir(work).await.map_err(io)?;
    while let Some(entry) = entries.next_entry().await.map_err(io)? {
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.ends_with(".partial") || name.ends_with(".sqlite") {
            remove_file(&entry.path()).await?;
        }
    }
    Ok(())
}

async fn remove_file(path: &Path) -> Result<(), PackError> {
    match tokio::fs::remove_file(path).await {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(source) => Err(PackError::Io {
            path: path.to_owned(),
            source,
        }),
    }
}

/// Whether `rest` reads `<seq>-<12 hex>.sqlite.gz`, the end of the name a
/// build gives a pack after its region's code and a dash.
fn is_pack_tail(rest: &str) -> bool {
    let Some((seq, hash)) = rest
        .strip_suffix(".sqlite.gz")
        .and_then(|rest| rest.split_once('-'))
    else {
        return false;
    };
    !seq.is_empty()
        && seq.bytes().all(|b| b.is_ascii_digit())
        && hash.len() == 12
        && hash.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
}

/// Whether the file `name` is a pack of the region whose prefix (its code
/// and a dash) is `prefix`. `FR-` also starts `FR-BRE-` and `FR-20R-`,
/// whose next part is not all digits; any other file in the directory is
/// left alone.
fn is_pack_of(name: &str, prefix: &str) -> bool {
    name.strip_prefix(prefix).is_some_and(is_pack_tail)
}

/// Whether the file `name` is a pack of some region. A code holds dashes
/// too (`FR-BRE`), so each dash is tried as the end of the code.
fn is_pack_name(name: &str) -> bool {
    name.match_indices('-').any(|(i, _)| {
        let (code, rest) = (&name[..i], &name[i + 1..]);
        !code.is_empty()
            && code
                .bytes()
                .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit() || b == b'-')
            && is_pack_tail(rest)
    })
}

/// Removes every pack file of `dir` that `recorded` (the `file` column of
/// `region_packs`) does not name.
async fn remove_unrecorded(dir: &Path, recorded: &[String]) -> Result<Vec<String>, PackError> {
    let io = |source| PackError::Io {
        path: dir.to_owned(),
        source,
    };
    let mut removed = Vec::new();
    let mut entries = tokio::fs::read_dir(dir).await.map_err(io)?;
    while let Some(entry) = entries.next_entry().await.map_err(io)? {
        let name = entry.file_name().to_string_lossy().into_owned();
        let named = recorded
            .iter()
            .any(|f| f.strip_prefix("places/") == Some(name.as_str()));
        if is_pack_name(&name) && !named {
            remove_file(&entry.path()).await?;
            removed.push(name);
        }
    }
    removed.sort_unstable();
    Ok(removed)
}

/// Removes every file of `region`.
async fn remove_region(dir: &Path, region: &str) -> Result<Vec<String>, PackError> {
    let io = |source| PackError::Io {
        path: dir.to_owned(),
        source,
    };
    let prefix = format!("{region}-");
    let mut removed = Vec::new();
    let mut entries = tokio::fs::read_dir(dir).await.map_err(io)?;
    while let Some(entry) = entries.next_entry().await.map_err(io)? {
        let name = entry.file_name().to_string_lossy().into_owned();
        if is_pack_of(&name, &prefix) {
            remove_file(&entry.path()).await?;
            removed.push(name);
        }
    }
    removed.sort_unstable();
    Ok(removed)
}

/// Removes the files of `pack`'s region other than its own and the
/// previous one.
async fn remove_older(
    dir: &Path,
    pack: &RegionPack,
    previous: Option<&str>,
) -> Result<Vec<String>, PackError> {
    let io = |source| PackError::Io {
        path: dir.to_owned(),
        source,
    };
    let prefix = format!("{}-", pack.region);
    let keep: Vec<&str> = [Some(pack.file.as_str()), previous]
        .into_iter()
        .flatten()
        .filter_map(|f| f.strip_prefix("places/"))
        .collect();
    let mut removed = Vec::new();
    let mut entries = tokio::fs::read_dir(dir).await.map_err(io)?;
    while let Some(entry) = entries.next_entry().await.map_err(io)? {
        let name = entry.file_name().to_string_lossy().into_owned();
        if is_pack_of(&name, &prefix) && !keep.contains(&name.as_str()) {
            remove_file(&entry.path()).await?;
            removed.push(name);
        }
    }
    removed.sort_unstable();
    Ok(removed)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(
        source: lunaway_domain::SourceId,
        name: &str,
        licence: &str,
        attribution: &str,
    ) -> PlaceSourceRow {
        PlaceSourceRow {
            place_id: Uuid::nil(),
            source_id: source,
            source_name: name.into(),
            licence: licence.into(),
            attribution: attribution.into(),
            source_url: "https://lunaway.net".into(),
            external_id: "1".into(),
            external_url: None,
            fetched_at: Utc::now(),
            match_score: None,
        }
    }

    #[test]
    fn a_pack_carrying_partner_values_says_they_are_not_odbl() {
        let osm = row(
            lunaway_domain::SourceId::OSM,
            "OpenStreetMap",
            "ODbL 1.0",
            "© OpenStreetMap contributors",
        );
        assert_eq!(
            pack_terms([&osm]),
            (LICENCE.to_owned(), ATTRIBUTION.to_owned()),
            "a pack of open sources only is ODbL, as before"
        );
        let partner = row(
            lunaway_domain::SourceId::EXTCOM,
            "Source communautaire externe",
            "EXTCOM-REF-1",
            "Source communautaire externe, avec l'accord du partenaire",
        );
        let (licence, attribution) = pack_terms([&osm, &partner]);
        assert!(licence.starts_with("ODbL-1.0, except the values whose provenance is `extcom`"));
        assert!(
            licence.contains("EXTCOM-REF-1"),
            "the agreement the values come under is named"
        );
        assert!(attribution.ends_with("Source communautaire externe, avec l'accord du partenaire"));
    }

    #[test]
    fn a_region_s_files_are_told_from_those_of_regions_its_code_starts() {
        assert!(is_pack_of("FR-18415-c2f0d06ad6d6.sqlite.gz", "FR-"));
        assert!(
            !is_pack_of("FR-20R-18415-5649afa75e53.sqlite.gz", "FR-"),
            "Corsica's pack is not France's: rebuilding FR must not delete it"
        );
        assert!(!is_pack_of("FR-BRE-18415-4f2777014568.sqlite.gz", "FR-"));
        assert!(is_pack_of("FR-20R-18415-5649afa75e53.sqlite.gz", "FR-20R-"));
        assert!(!is_pack_of("FR-20R.sqlite.building", "FR-20R-"));
        assert!(!is_pack_of("FR-18415-c2f0d06ad6d6.sqlite.partial", "FR-"));
        assert!(is_pack_name("FR-20R-18415-5649afa75e53.sqlite.gz"));
        assert!(is_pack_name("FR-18415-c2f0d06ad6d6.sqlite.gz"));
        assert!(is_pack_name("ES-7-c2f0d06ad6d6.sqlite.gz"));
        assert!(!is_pack_name("-7-c2f0d06ad6d6.sqlite.gz"));
        assert!(
            !is_pack_name("fr-7-c2f0d06ad6d6.sqlite.gz"),
            "only the names a build gives"
        );
        assert!(!is_pack_name("notes.txt"));
        assert!(!is_pack_of("FR-18415-c2f0d06ad6d6.sqlite.gz.bak", "FR-"));
        assert!(!is_pack_of("FR-18415-notes.sqlite.gz", "FR-"));
    }

    #[test]
    fn every_column_reads_a_field_of_the_selection() {
        let selection: Vec<&str> = PLACE_SELECTION
            .split(|c: char| !c.is_ascii_alphanumeric())
            .filter(|w| !w.is_empty())
            .collect();
        for (name, _, field) in COLUMNS {
            let key = match field {
                Field::Scalar(k) | Field::Address(k) | Field::Json(k) | Field::Descriptions(k) => {
                    *k
                }
            };
            assert!(
                selection.contains(&key),
                "column {name} reads {key}, which the selection does not ask for"
            );
        }
    }

    #[test]
    fn columns_take_the_json_as_the_api_writes_it() {
        use rusqlite::types::Value as Sql;
        let place = serde_json::json!({
            "id": "0192", "lat": 47.5, "capacity": 12, "openingHoursParsed": true,
            "address": {"countryCode": "FR"}, "services": ["TOILETS"], "openingIntervals": null
        });
        assert_eq!(
            column(&place, Field::Scalar("id")).unwrap(),
            Sql::Text("0192".into())
        );
        assert_eq!(
            column(&place, Field::Scalar("lat")).unwrap(),
            Sql::Real(47.5)
        );
        assert_eq!(
            column(&place, Field::Scalar("capacity")).unwrap(),
            Sql::Integer(12)
        );
        assert_eq!(
            column(&place, Field::Scalar("openingHoursParsed")).unwrap(),
            Sql::Integer(1),
            "a boolean is 0 or 1, SQLite's own"
        );
        assert_eq!(
            column(&place, Field::Address("countryCode")).unwrap(),
            Sql::Text("FR".into())
        );
        assert_eq!(
            column(&place, Field::Json("services")).unwrap(),
            Sql::Text("[\"TOILETS\"]".into())
        );
        assert_eq!(
            column(&place, Field::Json("openingIntervals")).unwrap(),
            Sql::Null,
            "a null list stays NULL, not the text null"
        );
        assert_eq!(column(&place, Field::Scalar("name")).unwrap(), Sql::Null);
    }

    fn texts(langs: &[&str]) -> Vec<Value> {
        langs
            .iter()
            .map(|l| serde_json::json!({"lang": l, "text": format!("text {l}"), "sourceId": "extcom"}))
            .collect()
    }

    fn langs_of(kept: &[&Value]) -> Vec<String> {
        kept.iter()
            .map(|d| d["lang"].as_str().unwrap().to_owned())
            .collect()
    }

    #[test]
    fn a_pack_keeps_the_descriptions_the_card_can_show() {
        assert_eq!(
            langs_of(&shown_descriptions(&texts(&["fr", "de", "en", "es", "fr"]))),
            ["fr", "en", "fr"],
            "every text in the app's languages, from every source"
        );
        assert_eq!(
            langs_of(&shown_descriptions(&texts(&["de", "fr", "nl"]))),
            ["de", "fr"],
            "without English, the first text stays: the card falls back to it"
        );
        assert_eq!(langs_of(&shown_descriptions(&texts(&["de", "es"]))), ["de"]);
        assert!(shown_descriptions(&[]).is_empty());
        let place = serde_json::json!({"descriptions": texts(&["it", "en"])});
        assert_eq!(
            column(&place, Field::Descriptions("descriptions")).unwrap(),
            rusqlite::types::Value::Text(
                r#"[{"lang":"en","sourceId":"extcom","text":"text en"}]"#.into()
            )
        );
    }

    #[test]
    fn the_packs_keep_every_language_the_app_speaks() {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../app/lib/i18n");
        let mut spoken: Vec<String> = std::fs::read_dir(&dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .filter_map(|n| n.strip_suffix(".i18n.json").map(str::to_owned))
            // The card asks for the language subtag (`pt` of `pt-BR`).
            .map(|tag| tag.split(['-', '_']).next().unwrap_or_default().to_owned())
            .collect();
        spoken.sort_unstable();
        assert!(!spoken.is_empty(), "the app's translations are in {dir:?}");
        for lang in &spoken {
            assert!(
                APP_LANGUAGES.contains(&lang.as_str()),
                "the app speaks {lang}: a pack must keep its descriptions (APP_LANGUAGES)"
            );
        }
    }
}
