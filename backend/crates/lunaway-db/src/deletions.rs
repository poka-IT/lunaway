//! The journal of account deletions, kept outside the database.
//!
//! A dump restored after a failure brings back every account deleted after
//! it was taken. The journal lives in a directory of its own on the data
//! volume, outside the dumps, and travels with the off-site copies; after a
//! restore, [`replay`] deletes those accounts again, exactly as
//! `deleteAccount` did, before the API serves the restored data
//! (`docs/deploy.md`, "Backups and restore").
//!
//! One file per UTC day (`accounts-YYYYMMDD.jsonl`), one JSON line per
//! deletion: the account's id and the time. A line is written and synced to
//! disk before the deletion is committed ([`delete_recorded`]), so no
//! deletion is ever in the database without its line. A file is never
//! rewritten: [`DeletionJournal::prune`] removes whole days once they are
//! older than every backup that could be restored.

use std::{
    collections::BTreeSet,
    path::{Path, PathBuf},
};

use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    DbError, PgPool,
    accounts::{self, DeletedAccount},
    day_files::{DayFiles, IoAt},
};

/// The prefix of a day's file.
const PREFIX: &str = "accounts-";

/// Why the journal could not be written or read.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum JournalError {
    /// A file or the directory could not be opened, written or listed.
    #[error("account deletion journal {path}")]
    Io {
        /// The file or directory.
        path: PathBuf,
        /// The cause.
        #[source]
        source: std::io::Error,
    },
    /// The blocking task that wrote the line did not finish.
    #[error("the account deletion journal's writer stopped")]
    Task(#[source] tokio::task::JoinError),
    /// A line could not be written as JSON.
    #[error("an account deletion could not be written as JSON")]
    Encode(#[source] serde_json::Error),
    /// The journal names no deletion at all: after a restore, a journal not
    /// put back would delete nothing and bring every deletion back. Its
    /// files say nothing here: the API's start writes an empty file for
    /// the day ([`DeletionJournal::check_writable`]).
    #[error("the account deletion journal {0} names no deletion: put it back before replaying")]
    Empty(PathBuf),
}

/// Why an account could not be deleted.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum DeleteError {
    /// The journal refused the line: nothing was deleted.
    #[error(transparent)]
    Journal(#[from] JournalError),
    /// The database failed: the line is written, the account still exists,
    /// and a replay would delete it as asked.
    #[error(transparent)]
    Db(#[from] DbError),
}

/// One deletion as written.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Entry {
    /// The account deleted.
    pub account: Uuid,
    /// When.
    pub deleted_at: DateTime<Utc>,
}

/// What reading the journal found.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Journal {
    /// The deletions, oldest file first, in the order written.
    pub entries: Vec<Entry>,
    /// Day files read.
    pub files: usize,
    /// Lines that do not read (a line cut by a crash while it was written).
    pub unreadable: usize,
}

/// The directory of the journal.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeletionJournal {
    dir: PathBuf,
}

/// The day a file name stands for, if it is one of the journal's.
#[cfg(test)]
fn day_of(name: &str) -> Option<chrono::NaiveDate> {
    crate::day_files::day_of(PREFIX, name)
}

fn io((path, source): IoAt) -> JournalError {
    JournalError::Io { path, source }
}

impl DeletionJournal {
    /// The journal kept in `dir`.
    #[must_use]
    pub fn new(dir: impl Into<PathBuf>) -> Self {
        Self { dir: dir.into() }
    }

    /// Its directory.
    #[must_use]
    pub fn dir(&self) -> &Path {
        &self.dir
    }

    fn files(&self) -> DayFiles<'_> {
        DayFiles {
            dir: &self.dir,
            prefix: PREFIX,
        }
    }

    /// Creates the directory when missing and checks a day file can be
    /// written there: run when the API starts, so a journal it could not
    /// write stops the start instead of every deletion.
    ///
    /// # Errors
    ///
    /// [`JournalError`] when the directory or today's file cannot be
    /// opened for writing.
    pub fn check_writable(&self, now: DateTime<Utc>) -> Result<(), JournalError> {
        self.files().open_day(now).map(drop).map_err(io)
    }

    /// Appends the deletion of `account` at `at` to the day's file and
    /// syncs it to disk. The file is readable by the owner's group, which
    /// the off-site copy runs as. A line cut by a crash is closed first, so
    /// it never swallows the next one.
    ///
    /// # Errors
    ///
    /// [`JournalError`] when the line cannot be written and synced.
    pub fn record_blocking(&self, account: Uuid, at: DateTime<Utc>) -> Result<(), JournalError> {
        let entry = serde_json::to_string(&Entry {
            account,
            deleted_at: at,
        })
        .map_err(JournalError::Encode)?;
        self.files().append(&entry, at).map_err(io)
    }

    /// [`Self::record_blocking`] on a blocking thread: the sync waits for
    /// the disk.
    ///
    /// # Errors
    ///
    /// [`JournalError`] when the line cannot be written and synced.
    pub async fn record(&self, account: Uuid, at: DateTime<Utc>) -> Result<(), JournalError> {
        let journal = self.clone();
        tokio::task::spawn_blocking(move || journal.record_blocking(account, at))
            .await
            .map_err(JournalError::Task)?
    }

    /// Writes `lines`, the journal's own JSON lines as its off-site copy
    /// holds them, into the journal, each deletion in the day it was made:
    /// after the loss of the data volume the copy is put back this way
    /// before the replay, and each line keeps its own retention. A line
    /// already there is written again (the replay reads each account once);
    /// a line that does not read is counted and left out.
    ///
    /// # Errors
    ///
    /// [`JournalError`] when a line cannot be written and synced; the lines
    /// before it are written, and importing again finishes the work.
    pub fn import_blocking(&self, lines: &str) -> Result<Imported, JournalError> {
        let mut out = Imported::default();
        for line in lines.lines().map(str::trim).filter(|l| !l.is_empty()) {
            match serde_json::from_str::<Entry>(line) {
                Ok(e) => {
                    self.record_blocking(e.account, e.deleted_at)?;
                    out.written += 1;
                }
                Err(_) => out.unreadable += 1,
            }
        }
        Ok(out)
    }

    /// [`Self::import_blocking`] on a blocking thread.
    ///
    /// # Errors
    ///
    /// As [`Self::import_blocking`], or [`JournalError::Task`].
    pub async fn import(&self, lines: String) -> Result<Imported, JournalError> {
        let journal = self.clone();
        tokio::task::spawn_blocking(move || journal.import_blocking(&lines))
            .await
            .map_err(JournalError::Task)?
    }

    /// The day files, oldest first.
    #[cfg(test)]
    fn days(&self) -> Result<Vec<(chrono::NaiveDate, PathBuf)>, JournalError> {
        self.files().days().map_err(io)
    }

    /// Every deletion written. A directory that does not exist is an empty
    /// journal; a line that does not read is counted and skipped.
    ///
    /// # Errors
    ///
    /// [`JournalError`] when the directory or a file cannot be read.
    pub fn read(&self) -> Result<Journal, JournalError> {
        let (lines, files) = self.files().lines().map_err(io)?;
        let mut journal = Journal {
            files,
            ..Journal::default()
        };
        for line in lines {
            match serde_json::from_str::<Entry>(&line) {
                Ok(e) => journal.entries.push(e),
                Err(_) => journal.unreadable += 1,
            }
        }
        Ok(journal)
    }

    /// Removes the day files that began `keep` or more before `now`;
    /// returns how many. No line is kept longer than `keep` (the figure
    /// the privacy page gives), and the last lines of a day go up to a day
    /// sooner: `keep` must outlast the oldest copy of a dump that could be
    /// restored by more than a day, or a restore could bring back a
    /// deletion the journal no longer holds.
    ///
    /// # Errors
    ///
    /// [`JournalError`] when the directory cannot be listed or a file
    /// removed.
    pub fn prune(&self, keep: Duration, now: DateTime<Utc>) -> Result<usize, JournalError> {
        self.files().prune(keep, now).map_err(io)
    }
}

/// Deletes `account` as `deleteAccount` does ([`accounts::delete_account`]),
/// after writing the deletion to `journal` when there is one. A line that
/// cannot be written stops the deletion: a deletion missing from the
/// journal would come back with the next restore. `Ok(None)` when the
/// account does not exist (its line is harmless).
///
/// # Errors
///
/// [`DeleteError::Journal`] when the line cannot be written (nothing is
/// deleted), [`DeleteError::Db`] when the database fails.
pub async fn delete_recorded(
    pool: &PgPool,
    journal: Option<&DeletionJournal>,
    account: Uuid,
) -> Result<Option<DeletedAccount>, DeleteError> {
    if let Some(journal) = journal {
        journal.record(account, Utc::now()).await?;
    }
    Ok(accounts::delete_account(pool, account).await?)
}

/// What an import wrote.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Imported {
    /// Deletions written into their days.
    pub written: usize,
    /// Lines that do not read (a line a crash cut short in the copy).
    pub unreadable: usize,
}

/// What a replay did.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Replayed {
    /// Distinct accounts the journal names.
    pub accounts: usize,
    /// Of them, those found in the database and deleted again.
    pub deleted: usize,
    /// Lines that did not read.
    pub unreadable: usize,
    /// Photo files no row refers to any more (the caller removes them).
    pub orphan_files: Vec<String>,
}

/// Deletes again every account the journal names that the database still
/// holds, as `deleteAccount` did. Run after a restore, before the API
/// serves the restored database. With `dry_run`, counts them only. A
/// journal that names no deletion is refused unless `allow_empty`: after
/// the loss of the data volume, a journal not put back from its copy would
/// bring every deletion since the dump back.
///
/// # Errors
///
/// [`DeleteError`] when the journal cannot be read or names no deletion, or the
/// database fails; the accounts deleted before the failure stay deleted,
/// and running it again finishes the work.
pub async fn replay(
    pool: &PgPool,
    journal: &DeletionJournal,
    dry_run: bool,
    allow_empty: bool,
) -> Result<Replayed, DeleteError> {
    let read = journal.read()?;
    if read.entries.is_empty() && !allow_empty {
        return Err(JournalError::Empty(journal.dir().to_owned()).into());
    }
    let ids: BTreeSet<Uuid> = read.entries.iter().map(|e| e.account).collect();
    let mut out = Replayed {
        accounts: ids.len(),
        unreadable: read.unreadable,
        ..Replayed::default()
    };
    for id in ids {
        if dry_run {
            if accounts::account(pool, id).await?.is_some() {
                out.deleted += 1;
            }
            continue;
        }
        if let Some(d) = accounts::delete_account(pool, id).await? {
            out.deleted += 1;
            out.orphan_files.extend(d.orphan_files);
        }
    }
    out.orphan_files.sort();
    out.orphan_files.dedup();
    Ok(out)
}

#[cfg(test)]
mod tests {
    use std::io::Write as _;

    use chrono::NaiveDate;

    use super::*;

    fn at(day: u32, hour: u32) -> DateTime<Utc> {
        NaiveDate::from_ymd_opt(2026, 10, day)
            .and_then(|d| d.and_hms_opt(hour, 0, 0))
            .unwrap()
            .and_utc()
    }

    #[test]
    fn deletions_are_read_back_in_the_order_written_across_days() {
        let dir = tempfile::tempdir().unwrap();
        let journal = DeletionJournal::new(dir.path().join("deletions"));
        assert_eq!(
            journal.read().unwrap(),
            Journal::default(),
            "a journal never written is empty, not an error"
        );
        let (a, b, c) = (Uuid::now_v7(), Uuid::now_v7(), Uuid::now_v7());
        journal.record_blocking(a, at(5, 23)).unwrap();
        journal.record_blocking(b, at(6, 1)).unwrap();
        journal.record_blocking(c, at(6, 2)).unwrap();
        let read = journal.read().unwrap();
        assert_eq!(read.files, 2, "one file per UTC day");
        assert_eq!(
            read.entries.iter().map(|e| e.account).collect::<Vec<_>>(),
            [a, b, c]
        );
        assert_eq!(read.entries[0].deleted_at, at(5, 23));
    }

    #[test]
    fn a_line_cut_by_a_crash_is_skipped_and_counted() {
        let dir = tempfile::tempdir().unwrap();
        let journal = DeletionJournal::new(dir.path());
        let a = Uuid::now_v7();
        journal.record_blocking(a, at(6, 1)).unwrap();
        let path = dir.path().join("accounts-20261006.jsonl");
        let mut f = std::fs::OpenOptions::new()
            .append(true)
            .open(&path)
            .unwrap();
        f.write_all(br#"{"account":"01a1"#).unwrap();
        std::fs::write(dir.path().join("notes.txt"), "not a day file").unwrap();
        let read = journal.read().unwrap();
        assert_eq!(read.entries.len(), 1);
        assert_eq!(read.unreadable, 1);
        assert_eq!(read.files, 1, "files of other names are not the journal's");
    }

    #[test]
    fn a_deletion_after_a_cut_line_is_kept() {
        let dir = tempfile::tempdir().unwrap();
        let journal = DeletionJournal::new(dir.path());
        let (a, b) = (Uuid::now_v7(), Uuid::now_v7());
        journal.record_blocking(a, at(6, 1)).unwrap();
        let mut f = std::fs::OpenOptions::new()
            .append(true)
            .open(dir.path().join("accounts-20261006.jsonl"))
            .unwrap();
        f.write_all(br#"{"account":"01a1"#).unwrap();
        journal.record_blocking(b, at(6, 2)).unwrap();
        let read = journal.read().unwrap();
        assert_eq!(
            read.entries.iter().map(|e| e.account).collect::<Vec<_>>(),
            [a, b],
            "the deletion written after a crash is not glued to the cut line"
        );
        assert_eq!(read.unreadable, 1);
    }

    #[test]
    fn a_journal_that_cannot_be_written_is_found_at_start() {
        let dir = tempfile::tempdir().unwrap();
        let blocked = dir.path().join("a-file");
        std::fs::write(&blocked, "x").unwrap();
        assert!(
            DeletionJournal::new(&blocked)
                .check_writable(at(6, 1))
                .is_err()
        );
        assert!(
            DeletionJournal::new(dir.path().join("j"))
                .check_writable(at(6, 1))
                .is_ok()
        );
    }

    #[test]
    fn whole_days_older_than_the_backups_are_pruned() {
        let dir = tempfile::tempdir().unwrap();
        let journal = DeletionJournal::new(dir.path());
        journal.record_blocking(Uuid::now_v7(), at(1, 12)).unwrap();
        journal.record_blocking(Uuid::now_v7(), at(5, 12)).unwrap();
        journal.record_blocking(Uuid::now_v7(), at(6, 12)).unwrap();
        let removed = journal.prune(Duration::days(2), at(7, 6)).unwrap();
        assert_eq!(
            removed, 2,
            "the 5th began two days before: a line of its first hours would be older than kept"
        );
        assert_eq!(journal.read().unwrap().entries.len(), 1, "the 6th stays");
    }

    #[test]
    fn an_off_site_copy_goes_back_into_its_days() {
        let dir = tempfile::tempdir().unwrap();
        let journal = DeletionJournal::new(dir.path());
        let (a, b) = (Uuid::now_v7(), Uuid::now_v7());
        let copy = format!(
            "{}\n{{\"account\":\"cut\n{}\n",
            serde_json::to_string(&Entry {
                account: a,
                deleted_at: at(2, 9)
            })
            .unwrap(),
            serde_json::to_string(&Entry {
                account: b,
                deleted_at: at(4, 18)
            })
            .unwrap(),
        );
        let imported = journal.import_blocking(&copy).unwrap();
        assert_eq!(
            imported,
            Imported {
                written: 2,
                unreadable: 1
            }
        );
        let days: Vec<NaiveDate> = journal
            .days()
            .unwrap()
            .into_iter()
            .map(|(d, _)| d)
            .collect();
        assert_eq!(
            days,
            [at(2, 0).date_naive(), at(4, 0).date_naive()],
            "each deletion in the day it was made, so it leaves at its own time"
        );
        assert_eq!(
            journal
                .read()
                .unwrap()
                .entries
                .iter()
                .map(|e| e.account)
                .collect::<Vec<_>>(),
            [a, b]
        );
    }

    #[test]
    fn only_the_journal_s_own_names_are_days() {
        assert_eq!(
            day_of("accounts-20261006.jsonl"),
            NaiveDate::from_ymd_opt(2026, 10, 6)
        );
        for other in [
            "accounts-2026106.jsonl",
            "accounts-20261306.jsonl",
            "accounts-20261006.jsonl.tmp",
            "x-20261006.jsonl",
        ] {
            assert_eq!(day_of(other), None, "{other}");
        }
    }

    #[cfg(unix)]
    #[test]
    fn the_files_are_closed_to_other_users() {
        use std::os::unix::fs::PermissionsExt as _;
        let dir = tempfile::tempdir().unwrap();
        let journal = DeletionJournal::new(dir.path().join("j"));
        journal.record_blocking(Uuid::now_v7(), at(6, 1)).unwrap();
        let mode = std::fs::metadata(dir.path().join("j/accounts-20261006.jsonl"))
            .unwrap()
            .permissions()
            .mode();
        assert_eq!(
            mode & 0o007,
            0,
            "account ids of deleted accounts are nobody else's business"
        );
    }
}
