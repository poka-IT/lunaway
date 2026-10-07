//! The external community source's feed (`docs/feeds.md`), imported into a
//! real database: what lands where with its provenance, what a second read
//! writes (nothing), deletions and erasures passed on, refusals, resuming
//! after a stop, and the switches. The feed is synthetic, written for
//! these tests (`fixtures/extcom_feed.jsonl`).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::path::{Path, PathBuf};

use chrono::NaiveDate;
use lunaway_db::{PgPool, extcom};
use lunaway_domain::{SourceId, extcom::Terms};
use lunaway_ingest::{
    IngestError,
    cache::Cache,
    extcom::{Dropped, Input, Limits, Options, Report, import},
};

const FEED: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/tests/fixtures/extcom_feed.jsonl"
);
const REFERENCE: &str = "EXTCOM-TEST-2026-01";

fn options(limits: Limits) -> Options {
    Options {
        terms: Terms::new(REFERENCE, &["img.partner.example".into()]).unwrap(),
        limits,
        refresh: false,
        today: NaiveDate::from_ymd_opt(2026, 10, 7).unwrap(),
    }
}

async fn run(
    pool: &PgPool,
    cache: &Cache,
    file: &Path,
    o: &Options,
) -> Result<Report, IngestError> {
    let http = lunaway_ingest::http::client_allowing_plain_http().unwrap();
    import(pool, &http, cache, &Input::File(file.to_owned()), o).await
}

/// The fixture with its lines changed by `edit` (line index, from 0, to
/// new text; `None` drops the line), written to `dir`.
fn variant(dir: &Path, name: &str, edit: impl Fn(usize, &str) -> Option<String>) -> PathBuf {
    let text = std::fs::read_to_string(FEED).unwrap();
    let lines: Vec<String> = text
        .lines()
        .enumerate()
        .filter_map(|(i, l)| edit(i, l))
        .collect();
    let path = dir.join(name);
    std::fs::write(&path, lines.join("\n")).unwrap();
    path
}

async fn count(pool: &PgPool, sql: &'static str) -> i64 {
    sqlx::query_scalar::<_, i64>(sql)
        .fetch_one(pool)
        .await
        .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_feed_lands_with_its_agreement_and_provenance(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let r = run(&pool, &cache, Path::new(FEED), &options(Limits::default()))
        .await
        .unwrap();
    assert_eq!(r.agreement, REFERENCE);
    assert!(r.complete);
    assert_eq!(r.places, 6);
    assert!(
        r.unmapped.is_empty(),
        "every code of the fixture must be in a mapping table: {:?}",
        r.unmapped
    );
    assert_eq!(r.dropped.get(&Dropped::NotAPlace), Some(&1));
    assert_eq!(r.dropped.get(&Dropped::BadPosition), Some(&1));
    assert_eq!(r.dropped.get(&Dropped::Duplicate), Some(&1));
    assert_eq!(r.dropped.get(&Dropped::Malformed), Some(&1));
    assert_eq!(r.marked_deleted, 1);
    assert_eq!(
        r.photos_dropped, 1,
        "the photo on a host the server does not allow"
    );
    assert_eq!(r.records.inserted, 6);

    assert_eq!(
        count(
            &pool,
            "SELECT count(*) FROM source_records WHERE source_id = 'extcom' \
             AND licence = 'EXTCOM-TEST-2026-01' AND deleted_at IS NULL"
        )
        .await,
        6,
        "every record carries the agreement it came under"
    );
    assert_eq!(
        count(&pool, "SELECT count(*) FROM external_reviews").await,
        6
    );
    assert_eq!(
        count(
            &pool,
            "SELECT count(*) FROM external_reviews WHERE licence = 'EXTCOM-TEST-2026-01' \
             AND author_id IS NOT NULL"
        )
        .await,
        6
    );
    assert_eq!(
        count(&pool, "SELECT count(*) FROM external_ratings").await,
        3
    );
    assert_eq!(
        count(&pool, "SELECT count(*) FROM external_photos").await,
        3
    );
    let (licence, attribution): (String, String) =
        sqlx::query_as("SELECT licence, attribution FROM source_terms WHERE id = 'extcom'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        licence, REFERENCE,
        "the source shows its agreement's reference"
    );
    assert!(attribution.starts_with("Source communautaire externe"));
    let hosts: Vec<String> =
        sqlx::query_scalar("SELECT photo_hosts FROM source_agreements WHERE source_id = 'extcom'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(hosts, ["img.partner.example"], "the hosts are the server's");

    let data: serde_json::Value = sqlx::query_scalar(
        "SELECT data FROM source_records WHERE source_id = 'extcom' AND external_id = '1008'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        data["description"], "Borne Flot Bleu, jetons à la mairie. invisible",
        "markup and direction overrides are gone from a stored text"
    );
    assert_eq!(data["opening_hours"], "Mar 15-Nov 15");
    assert_eq!(
        data["services"],
        serde_json::json!(["drinking_water", "grey_water", "black_water"])
    );
    let raw: serde_json::Value = sqlx::query_scalar(
        "SELECT raw FROM source_records WHERE source_id = 'extcom' AND external_id = '1001'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(raw["reviews_count"], 3);
    assert!(
        raw.get("reviews").is_none(),
        "reviews live in their own table"
    );
    let overnight: String = sqlx::query_scalar(
        "SELECT data->>'overnight' FROM source_records WHERE external_id = '1002'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(overnight, "allowed", "five reports and none against");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_second_read_of_the_same_feed_writes_nothing(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let o = options(Limits::default());
    run(&pool, &cache, Path::new(FEED), &o).await.unwrap();
    let stamp = |pool: PgPool| async move {
        sqlx::query_as::<_, (chrono::DateTime<chrono::Utc>, chrono::DateTime<chrono::Utc>)>(
            "SELECT (SELECT max(changed_at) FROM source_records), \
                    (SELECT max(changed_at) FROM external_reviews)",
        )
        .fetch_one(&pool)
        .await
        .unwrap()
    };
    let before = stamp(pool.clone()).await;
    let again = run(&pool, &cache, Path::new(FEED), &o).await.unwrap();
    assert_eq!(again.records.inserted + again.records.changed, 0);
    assert_eq!(again.records.unchanged, 6);
    assert_eq!(again.licences_set, 0);
    assert_eq!(
        again.extras,
        extcom::ExtrasStats::default(),
        "no review, rating or photo rewritten"
    );
    assert_eq!(again.retired, 0);
    assert_eq!(stamp(pool.clone()).await, before, "no row was rewritten");
}

#[sqlx::test(migrations = "../../migrations")]
async fn deletions_in_a_complete_feed_reach_records_reviews_and_photos(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let o = options(Limits::default());
    run(&pool, &cache, Path::new(FEED), &o).await.unwrap();
    // The next feed: 1002 is gone, 1003 is marked deleted, and 1001 lost a
    // review and a photo.
    let next = variant(dir.path(), "next.jsonl", |i, l| match i {
        2 => None,
        3 => Some(r#"{"type":"place","id":"1003","deleted":true}"#.to_owned()),
        1 => {
            let mut v: serde_json::Value = serde_json::from_str(l).unwrap();
            v["reviews"].as_array_mut().unwrap().remove(1);
            v["photos"].as_array_mut().unwrap().remove(1);
            Some(v.to_string())
        }
        _ => Some(l.to_owned()),
    });
    let r = run(&pool, &cache, &next, &o).await.unwrap();
    assert_eq!(r.retired, 2, "1003 marked deleted, 1002 absent");
    assert_eq!(r.forgotten.records, 2);
    assert_eq!(r.extras.reviews_removed, 1);
    assert_eq!(r.extras.photos_retired, 1);
    assert_eq!(
        count(
            &pool,
            "SELECT count(*) FROM source_records WHERE external_id IN ('1002', '1003') \
             AND deleted_at IS NOT NULL AND raw = '{}' AND name IS NULL AND licence IS NULL"
        )
        .await,
        2,
        "a spot gone at the partner is emptied, not kept"
    );
    assert_eq!(
        count(
            &pool,
            "SELECT count(*) FROM external_reviews WHERE external_id IN ('r-2', 'r-4', 'r-5')"
        )
        .await,
        0,
        "the reviews of a removed spot, and a review removed from its spot, are deleted"
    );
    assert_eq!(
        count(&pool, "SELECT count(*) FROM external_ratings").await,
        1,
        "the ratings of the removed spots are deleted"
    );
    assert_eq!(
        count(
            &pool,
            "SELECT count(*) FROM external_photos WHERE external_id = 'p-2' \
             AND retired_at IS NOT NULL AND url IS NULL AND author IS NULL AND author_id IS NULL"
        )
        .await,
        1
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_delta_feed_deletes_only_what_it_marks(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let o = options(Limits::default());
    run(&pool, &cache, Path::new(FEED), &o).await.unwrap();
    let delta = variant(dir.path(), "delta.jsonl", |i, l| match i {
        0 => Some(l.replace(r#""complete":true"#, r#""complete":false"#)),
        5 => Some(r#"{"type":"place","id":"1005","deleted":true}"#.to_owned()),
        4 => Some(l.to_owned()),
        _ => None,
    });
    let r = run(&pool, &cache, &delta, &o).await.unwrap();
    assert!(!r.complete);
    assert_eq!(r.retired, 1);
    assert_eq!(
        count(
            &pool,
            "SELECT count(*) FROM source_records WHERE source_id = 'extcom' AND deleted_at IS NULL"
        )
        .await,
        5,
        "a delta does not delete the spots it does not list"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn feeds_without_the_server_s_agreement_in_force_are_refused(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let o = options(Limits::default());
    let cases = [
        (
            "no-header",
            variant(dir.path(), "a.jsonl", |i, l| (i > 0).then(|| l.to_owned())),
        ),
        (
            "no-agreement",
            variant(dir.path(), "b.jsonl", |i, l| {
                Some(if i == 0 {
                    r#"{"type":"header","format":"lunaway-extcom-1","generated_at":"2026-10-07T03:00:00Z"}"#.to_owned()
                } else {
                    l.to_owned()
                })
            }),
        ),
        (
            "other-agreement",
            variant(dir.path(), "c.jsonl", |_, l| {
                Some(l.replace(REFERENCE, "SOMEONE-ELSE"))
            }),
        ),
        (
            "expired",
            variant(dir.path(), "d.jsonl", |_, l| {
                Some(l.replace("2027-09-30", "2026-10-06"))
            }),
        ),
    ];
    for (why, file) in cases {
        let error = run(&pool, &cache, &file, &o).await.unwrap_err();
        assert!(
            matches!(error, IngestError::Agreement(_)),
            "{why}: {error:?}"
        );
    }
    assert_eq!(
        count(
            &pool,
            "SELECT count(*) FROM source_records WHERE source_id = 'extcom'"
        )
        .await
            + count(&pool, "SELECT count(*) FROM source_agreements").await,
        0,
        "nothing of a refused feed is stored"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_stopped_import_resumes_after_its_last_stored_batch(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let small = Limits {
        batch: 2,
        ..Limits::default()
    };
    // The first run stops at its fourth place: the first batch (1001,
    // 1002) is stored, the second is not.
    let stopping = options(Limits {
        max_places: 3,
        ..small
    });
    let error = run(&pool, &cache, Path::new(FEED), &stopping)
        .await
        .unwrap_err();
    assert!(
        matches!(error, IngestError::Implausible { .. }),
        "{error:?}"
    );
    assert_eq!(
        count(
            &pool,
            "SELECT count(*) FROM source_records WHERE source_id = 'extcom'"
        )
        .await,
        2
    );
    let r = run(&pool, &cache, Path::new(FEED), &options(small))
        .await
        .unwrap();
    assert_eq!(
        r.resumed_after, 3,
        "the header and the first batch's two lines"
    );
    assert_eq!(
        r.records.inserted, 4,
        "the stored batch is skipped, the rest written"
    );
    assert_eq!(
        r.records.unchanged, 0,
        "nothing of the first batch is read again"
    );
    assert_eq!(r.retired, 0, "the skipped batch's spots count as seen");
    assert_eq!(
        count(
            &pool,
            "SELECT count(*) FROM source_records WHERE deleted_at IS NULL"
        )
        .await,
        6
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_erased_author_stays_erased_across_feeds(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let o = options(Limits::default());
    run(&pool, &cache, Path::new(FEED), &o).await.unwrap();
    let hash = lunaway_domain::extcom::author_hash("u-42");
    let e = extcom::erase_author(&pool, &SourceId::EXTCOM, "u-42", &hash)
        .await
        .unwrap();
    assert_eq!((e.reviews, e.photos), (1, 1));
    let stored: Vec<String> = sqlx::query_scalar("SELECT author_hash FROM source_erasures")
        .fetch_all(&pool)
        .await
        .unwrap();
    assert_eq!(stored, [hash], "the hash is kept, never the id");
    let r = run(&pool, &cache, Path::new(FEED), &o).await.unwrap();
    assert_eq!(
        r.erased_skipped, 2,
        "the feed still carries their review and photo"
    );
    assert_eq!(
        count(
            &pool,
            "SELECT count(*) FROM external_reviews WHERE author_id = 'u-42'"
        )
        .await
            + count(
                &pool,
                "SELECT count(*) FROM external_photos WHERE retired_at IS NULL \
                 AND author_id = 'u-42'"
            )
            .await,
        0
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_purge_empties_the_source_and_blocks_imports_until_shown(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let o = options(Limits::default());
    run(&pool, &cache, Path::new(FEED), &o).await.unwrap();
    let p = extcom::purge(&pool, &SourceId::EXTCOM, Some("agreement ended"))
        .await
        .unwrap();
    assert_eq!((p.records, p.reviews, p.ratings, p.photos), (6, 6, 3, 3));
    assert_eq!(
        count(
            &pool,
            "SELECT count(*) FROM source_records WHERE source_id = 'extcom' \
             AND (deleted_at IS NULL OR raw <> '{}' OR name IS NOT NULL OR needs_conflation = false)"
        )
        .await,
        0,
        "every record is emptied, retired and flagged for the conflation"
    );
    assert_eq!(
        count(
            &pool,
            "SELECT count(*) FROM external_photos WHERE url IS NOT NULL"
        )
        .await,
        0
    );
    let error = run(&pool, &cache, Path::new(FEED), &o).await.unwrap_err();
    assert!(matches!(error, IngestError::SourceHidden(_)), "{error:?}");
    let files = extcom::retired_photo_files(&pool, 100).await.unwrap();
    assert_eq!(files.len(), 3, "the retired photos wait for purge-media");

    extcom::set_hidden(&pool, &SourceId::EXTCOM, false, None)
        .await
        .unwrap();
    let r = run(&pool, &cache, Path::new(FEED), &o).await.unwrap();
    assert_eq!(
        r.records.changed, 6,
        "a new feed fills the emptied records again"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_gzip_feed_reads_like_a_plain_one(pool: PgPool) {
    use std::io::Write as _;
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let path = dir.path().join("feed.jsonl.gz");
    let mut gz = flate2::write::GzEncoder::new(
        std::fs::File::create(&path).unwrap(),
        flate2::Compression::default(),
    );
    gz.write_all(&std::fs::read(FEED).unwrap()).unwrap();
    gz.finish().unwrap();
    let r = run(&pool, &cache, &path, &options(Limits::default()))
        .await
        .unwrap();
    assert_eq!(r.places, 6);
    assert_eq!(r.records.inserted, 6);
}
