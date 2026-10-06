//! The sync regions and their first-sync packs (`Query.regions`).

use async_graphql::SimpleObject;
use chrono::{DateTime, Utc};
use lunaway_db::{packs::RegionPack as PackRow, places::FeedHead};

/// A region a device can keep offline: a French region inside France, a
/// country elsewhere.
#[derive(SimpleObject, Debug, Clone)]
pub struct SyncRegion {
    /// Its code, the `region` of `changes` and of `Place.region`: `FR-BRE`,
    /// `ES`.
    pub code: String,
    /// The country it belongs to (ISO 3166-1).
    pub country: String,
    /// Its name in English.
    pub name: String,
    /// Its name in French.
    pub name_fr: String,
    /// The pack to download first, then `changes(region:, since: cursor)`;
    /// null while none is built for this copy of the database.
    pub pack: Option<RegionPack>,
}

/// The box around a region's places.
#[derive(SimpleObject, Debug, Clone, Copy)]
pub struct RegionBounds {
    /// Southern edge.
    pub south: f64,
    /// Western edge.
    pub west: f64,
    /// Northern edge.
    pub north: f64,
    /// Eastern edge.
    pub east: f64,
}

/// A file holding every live place of a region at one position of the
/// change feed, in the format `format` (`docs/region-packs.md`).
#[derive(SimpleObject, Debug, Clone)]
pub struct RegionPack {
    /// Where to download it: a static file, served whole or by byte range,
    /// that never changes under this URL.
    pub url: String,
    /// Its format and version: `sqlite-gzip-1` is an SQLite database
    /// compressed with gzip.
    pub format: String,
    /// Its size as downloaded, in bytes.
    pub bytes: f64,
    /// Its size once decompressed, in bytes.
    pub raw_bytes: f64,
    /// SHA-256 of the file as downloaded, hexadecimal: check it before
    /// importing.
    pub sha256: String,
    /// Opaque, changes with every new pack of the region: a device whose
    /// pack has this version has nothing to download again.
    pub version: String,
    /// The `since` cursor that continues the feed after the pack.
    pub cursor: String,
    /// Places in it.
    pub places: i32,
    /// The box around them.
    pub bounds: RegionBounds,
    /// When it was built.
    pub generated_at: DateTime<Utc>,
}

/// Bytes as a GraphQL `Float`: `Int` is 32-bit, a pack may not be.
#[allow(
    clippy::cast_precision_loss,
    reason = "file sizes stay far below 2^53 bytes"
)]
fn bytes(n: i64) -> f64 {
    n as f64
}

/// The pack of a row, when it was built from the copy of the database the
/// API serves (`head`): a pack of another copy (before a restore) would
/// hand out a cursor this copy answers with `RESYNC`.
pub(crate) fn pack_of(row: &PackRow, head: &FeedHead, public_url: &str) -> Option<RegionPack> {
    (row.feed_identity == head.identity() && row.seq <= head.last_seq).then(|| RegionPack {
        url: format!("{public_url}/packs/{}", row.file),
        format: row.format.clone(),
        bytes: bytes(row.bytes),
        raw_bytes: bytes(row.raw_bytes),
        sha256: row.sha256.clone(),
        version: row.seq.to_string(),
        cursor: crate::schema::changes_cursor(head, row.seq),
        places: row.places,
        bounds: RegionBounds {
            south: row.south,
            west: row.west,
            north: row.north,
            east: row.east,
        },
        generated_at: row.generated_at,
    })
}
