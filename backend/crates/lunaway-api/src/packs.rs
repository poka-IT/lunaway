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
//! disagree on a value.
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

/// How a field of the place's JSON goes into its column.
#[derive(Debug, Clone, Copy)]
enum Field {
    /// A scalar at this key (a string, a number, a boolean as 0 or 1).
    Scalar(&'static str),
    /// A scalar of the `address` object.
    Address(&'static str),
    /// A list or an object at this key, as JSON text (`null` stays NULL).
    Json(&'static str),
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
    ("descriptions", "TEXT NOT NULL", Field::Json("descriptions")),
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
}

/// What to build.
#[derive(Debug, Clone)]
pub struct PackOptions {
    /// The directory the backend serves under `/packs/`; files go to its
    /// `places/` subdirectory.
    pub dir: PathBuf,
    /// Only these regions; every region with places when empty.
    pub only: Vec<String>,
    /// Builds the packs of `only` even when nothing changed in them, and
    /// removes their previous files at once: after a place was taken down
    /// (personal data, a court order), no file still serves it.
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
        if path.exists() {
            std::fs::remove_file(path).map_err(|source| PackError::Io {
                path: path.to_owned(),
                source,
            })?;
        }
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
    })
}

/// Builds the pack of every sync region with places (or of `only`) whose
/// current pack predates a change of its places, records each in
/// `region_packs` and removes the files of the packs before the previous
/// one: a device that read the manifest just before a build still finds the
/// file it names. A region nothing changed in keeps its pack, so a device
/// that has it finds no new version.
///
/// # Errors
///
/// [`PackError`] when the database, a resolver or a file fails; the packs
/// recorded before stay.
pub async fn build(
    pool: &PgPool,
    config: ApiConfig,
    options: &PackOptions,
) -> Result<Vec<Built>, PackError> {
    let dir = options.dir.join("places");
    tokio::fs::create_dir_all(&dir)
        .await
        .map_err(|source| PackError::Io {
            path: dir.clone(),
            source,
        })?;
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
        .filter(|r| options.only.is_empty() || options.only.contains(&r.region))
        .collect();
    let query = format!("{{ places {{ {PLACE_SELECTION} }} }}");
    let cursor = crate::schema::changes_cursor(&head, head.last_seq);
    let mut built = Vec::with_capacity(regions.len());
    for extent in &regions {
        let up_to_date = !options.takedown
            && current.get(&extent.region).is_some_and(|p| {
                p.feed_identity == identity
                    && p.seq >= extent.last_seq
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
        // The cover photos' URLs come from the API's configuration, the
        // rest from the snapshot.
        let schema = Schema::build(PackRoot, EmptyMutation, EmptySubscription)
            .data(DataLoader::new(
                PlaceSourcesLoader::Read(sources),
                tokio::spawn,
            ))
            .data(ApiState::new(pool.clone(), config.clone()))
            .finish();
        let raw_path = dir.join(format!("{}.sqlite.building", extent.region));
        let generated_at = Utc::now();
        let describe = vec![
            ("format", FORMAT.to_owned()),
            ("region", extent.region.clone()),
            ("cursor", cursor.clone()),
            ("places", extent.places.to_string()),
            ("generatedAt", generated_at.to_rfc3339()),
            ("licence", LICENCE.to_owned()),
            ("attribution", ATTRIBUTION.to_owned()),
        ];
        let path = raw_path.clone();
        let mut writer = blocking(move || {
            let w = Writer::create(&path)?;
            w.describe(&describe)?;
            Ok(w)
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
        let compressed = blocking(move || gzip(&raw, &gz_dir)).await?;
        remove_file(&raw_path).await?;
        let sha256: String = Sha256::digest(&compressed)
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect();
        let file_name = format!(
            "{}-{}-{}.sqlite.gz",
            extent.region,
            head.last_seq,
            &sha256[..12]
        );
        write_atomically(&dir.join(&file_name), &compressed).await?;
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
    let mut out = Vec::with_capacity(built.len());
    for pack in built {
        let previous = packs::record(pool, &pack).await?;
        let keep_previous = previous.as_deref().filter(|_| !options.takedown);
        let removed = remove_older(&dir, &pack, keep_previous).await?;
        out.push(Built { pack, removed });
    }
    if options.only.is_empty() {
        let keep: Vec<String> = regions.iter().map(|r| r.region.clone()).collect();
        for file in packs::forget_others(pool, &keep).await? {
            remove_file(&options.dir.join(file)).await?;
        }
    }
    Ok(out)
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

async fn write_atomically(path: &Path, bytes: &[u8]) -> Result<(), PackError> {
    let io = |source| PackError::Io {
        path: path.to_owned(),
        source,
    };
    let tmp = path.with_extension("partial");
    tokio::fs::write(&tmp, bytes).await.map_err(io)?;
    tokio::fs::rename(&tmp, path).await.map_err(io)
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

/// Whether the file `name` is a pack of the region whose prefix (its code
/// and a dash) is `prefix`: the code is followed by the feed position, all
/// digits, then a dash. `FR-` also starts `FR-BRE-` and `FR-20R-`, whose
/// next part is not all digits.
fn is_pack_of(name: &str, prefix: &str) -> bool {
    name.strip_prefix(prefix)
        .and_then(|rest| rest.split_once('-'))
        .is_some_and(|(seq, _)| !seq.is_empty() && seq.bytes().all(|b| b.is_ascii_digit()))
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
    Ok(removed)
}

#[cfg(test)]
mod tests {
    use super::*;

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
    }

    #[test]
    fn every_column_reads_a_field_of_the_selection() {
        let selection: Vec<&str> = PLACE_SELECTION
            .split(|c: char| !c.is_ascii_alphanumeric())
            .filter(|w| !w.is_empty())
            .collect();
        for (name, _, field) in COLUMNS {
            let key = match field {
                Field::Scalar(k) | Field::Address(k) | Field::Json(k) => *k,
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
}
