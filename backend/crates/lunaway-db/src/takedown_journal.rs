//! The journal of takedowns, kept outside the database.
//!
//! A dump older than a takedown brings the place back when it is restored:
//! the takedown was logged in the database only (`place_takedowns`). Like
//! the account deletions ([`crate::deletions`]), every takedown is written
//! first to a journal in a directory of its own on the data volume, outside
//! the dumps, which travels with the off-site copies; after a restore, the
//! replay takes down again every place it names that the restored database
//! still holds, and puts back the cells of their exclusion zones
//! (`lunaway_conflate::takedown::replay`).
//!
//! One file per UTC day (`takedowns-YYYYMMDD.jsonl`), one JSON line per
//! takedown: the places' ids, the date, a short code of the kind of request,
//! the keyed hashes of the zone's cells and the check value of the secret
//! that keyed them. No name, no position, no text
//! of the reason. The line is written and synced before the takedown
//! commits, so no takedown is in the database without its line. Lines are
//! kept: a few a year, nothing personal in them, and the cells they hold
//! must outlive every restore.

use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use lunaway_domain::takedown::{CellHash, TakedownCode};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::day_files::{DayFiles, IoAt};

/// The prefix of a day's file.
const PREFIX: &str = "takedowns-";

/// Why the journal could not be written or read.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum JournalError {
    /// A file or the directory could not be opened, written or listed.
    #[error("takedown journal {path}")]
    Io {
        /// The file or directory.
        path: PathBuf,
        /// The cause.
        #[source]
        source: std::io::Error,
    },
    /// The blocking task that wrote the line did not finish.
    #[error("the takedown journal's writer stopped")]
    Task(#[source] tokio::task::JoinError),
    /// A line could not be written as JSON.
    #[error("a takedown could not be written as JSON")]
    Encode(#[source] serde_json::Error),
    /// The journal names no takedown: after a restore, a journal not put
    /// back would take nothing down and bring every takedown back.
    #[error("the takedown journal {0} names no takedown: put it back before replaying")]
    Empty(PathBuf),
}

fn io((path, source): IoAt) -> JournalError {
    JournalError::Io { path, source }
}

/// One takedown as written.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Entry {
    /// The place taken down (merges followed), then the places merged into
    /// it: a restored database may hold them apart.
    pub places: Vec<Uuid>,
    /// When.
    pub taken_down_at: DateTime<Utc>,
    /// The kind of request.
    pub code: TakedownCode,
    /// Whether the retired records near it that name no place were emptied
    /// too (`--with-nearby`), which the replay does again.
    pub with_nearby: bool,
    /// The keyed hashes of its exclusion zone.
    pub cells: Vec<CellHash>,
    /// The check value of the secret that keyed them
    /// (`TakedownKey::check`): a replay under another secret is refused.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub key_check: Option<CellHash>,
}

/// What reading the journal found.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Journal {
    /// The takedowns, oldest file first, in the order written.
    pub entries: Vec<Entry>,
    /// Day files read.
    pub files: usize,
    /// Lines that do not read (a line cut by a crash while it was written).
    pub unreadable: usize,
}

/// What an import wrote.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Imported {
    /// Takedowns written into their days.
    pub written: usize,
    /// Lines that do not read.
    pub unreadable: usize,
}

/// The directory of the journal.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TakedownJournal {
    dir: PathBuf,
}

impl TakedownJournal {
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
    /// written there: run before a takedown starts, so a journal that
    /// cannot be written stops it before anything is emptied.
    ///
    /// # Errors
    ///
    /// [`JournalError`] when the directory or today's file cannot be
    /// opened for writing.
    pub fn check_writable(&self, now: DateTime<Utc>) -> Result<(), JournalError> {
        self.files().open_day(now).map(drop).map_err(io)
    }

    /// Appends `entry` to the file of its day and syncs it to disk.
    ///
    /// # Errors
    ///
    /// [`JournalError`] when the line cannot be written and synced.
    pub fn record_blocking(&self, entry: &Entry) -> Result<(), JournalError> {
        let line = serde_json::to_string(entry).map_err(JournalError::Encode)?;
        self.files().append(&line, entry.taken_down_at).map_err(io)
    }

    /// [`Self::record_blocking`] on a blocking thread: the sync waits for
    /// the disk.
    ///
    /// # Errors
    ///
    /// [`JournalError`] when the line cannot be written and synced.
    pub async fn record(&self, entry: Entry) -> Result<(), JournalError> {
        let journal = self.clone();
        tokio::task::spawn_blocking(move || journal.record_blocking(&entry))
            .await
            .map_err(JournalError::Task)?
    }

    /// Writes `lines`, the journal's own JSON lines as its off-site copy
    /// holds them, into the journal, each takedown in the day it was made:
    /// after the loss of the data volume the copy is put back this way
    /// before the replay. A line already there is written again (the
    /// replay takes each place down once); a line that does not read is
    /// counted and left out.
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
                    self.record_blocking(&e)?;
                    out.written += 1;
                }
                Err(_) => out.unreadable += 1,
            }
        }
        Ok(out)
    }

    /// Every takedown written. A directory that does not exist is an empty
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

    /// [`Self::read`], refusing a journal that names no takedown unless
    /// `allow_empty`: after the loss of the data volume, a journal not put
    /// back from its copy would let every takedown since the dump come
    /// back.
    ///
    /// # Errors
    ///
    /// [`JournalError::Empty`], or what [`Self::read`] returns.
    pub fn read_for_replay(&self, allow_empty: bool) -> Result<Journal, JournalError> {
        let journal = self.read()?;
        if journal.entries.is_empty() && !allow_empty {
            return Err(JournalError::Empty(self.dir.clone()));
        }
        Ok(journal)
    }
}

#[cfg(test)]
mod tests {
    use std::io::Write as _;

    use chrono::NaiveDate;
    use lunaway_domain::{Position, takedown::TakedownKey};

    use super::*;

    fn at(day: u32, hour: u32) -> DateTime<Utc> {
        NaiveDate::from_ymd_opt(2026, 10, day)
            .and_then(|d| d.and_hms_opt(hour, 0, 0))
            .unwrap()
            .and_utc()
    }

    fn entry(day: u32) -> Entry {
        let key = TakedownKey::new(&[7; 32]).unwrap();
        Entry {
            places: vec![Uuid::now_v7(), Uuid::now_v7()],
            taken_down_at: at(day, 9),
            code: TakedownCode::PrivateHome,
            with_nearby: false,
            cells: key.zone(Position::new(45.0, 5.0).unwrap()),
            key_check: Some(key.check()),
        }
    }

    #[test]
    fn takedowns_are_read_back_across_days_and_a_cut_line_is_skipped() {
        let dir = tempfile::tempdir().unwrap();
        let journal = TakedownJournal::new(dir.path().join("takedowns"));
        assert_eq!(journal.read().unwrap(), Journal::default());
        assert!(
            matches!(journal.read_for_replay(false), Err(JournalError::Empty(_))),
            "a journal not put back must not pass for one with nothing to replay"
        );
        assert!(journal.read_for_replay(true).is_ok());
        let (a, b) = (entry(5), entry(6));
        journal.record_blocking(&a).unwrap();
        let mut f = std::fs::OpenOptions::new()
            .append(true)
            .open(dir.path().join("takedowns/takedowns-20261005.jsonl"))
            .unwrap();
        f.write_all(br#"{"places":["01a1"#).unwrap();
        journal.record_blocking(&b).unwrap();
        let read = journal.read().unwrap();
        assert_eq!(read.entries, [a, b]);
        assert_eq!((read.files, read.unreadable), (2, 1));
    }

    #[test]
    fn a_line_holds_ids_dates_a_code_and_hashes_only() {
        let dir = tempfile::tempdir().unwrap();
        let journal = TakedownJournal::new(dir.path());
        let e = entry(6);
        journal.record_blocking(&e).unwrap();
        let text = std::fs::read_to_string(dir.path().join("takedowns-20261006.jsonl")).unwrap();
        let line: serde_json::Value = serde_json::from_str(text.trim()).unwrap();
        let mut keys: Vec<&str> = line
            .as_object()
            .unwrap()
            .keys()
            .map(String::as_str)
            .collect();
        keys.sort_unstable();
        assert_eq!(
            keys,
            [
                "cells",
                "code",
                "keyCheck",
                "places",
                "takenDownAt",
                "withNearby"
            ],
            "no name, no position, no reason's text leaves the database"
        );
        assert_eq!(line["code"], "private-home");
        assert_eq!(line["cells"].as_array().unwrap().len(), 61);
    }

    #[test]
    fn an_off_site_copy_goes_back_into_its_days() {
        let dir = tempfile::tempdir().unwrap();
        let journal = TakedownJournal::new(dir.path());
        let (a, b) = (entry(2), entry(4));
        let copy = format!(
            "{}\n{{\"places\":\"cut\n{}\n",
            serde_json::to_string(&a).unwrap(),
            serde_json::to_string(&b).unwrap(),
        );
        assert_eq!(
            journal.import_blocking(&copy).unwrap(),
            Imported {
                written: 2,
                unreadable: 1
            }
        );
        let days: Vec<NaiveDate> = journal
            .files()
            .days()
            .unwrap()
            .into_iter()
            .map(|(d, _)| d)
            .collect();
        assert_eq!(days, [at(2, 0).date_naive(), at(4, 0).date_naive()]);
        assert_eq!(journal.read().unwrap().entries, [a, b]);
    }

    #[cfg(unix)]
    #[test]
    fn the_files_are_closed_to_other_users() {
        use std::os::unix::fs::PermissionsExt as _;
        let dir = tempfile::tempdir().unwrap();
        let journal = TakedownJournal::new(dir.path().join("j"));
        journal.record_blocking(&entry(6)).unwrap();
        let mode = std::fs::metadata(dir.path().join("j/takedowns-20261006.jsonl"))
            .unwrap()
            .permissions()
            .mode();
        assert_eq!(mode & 0o007, 0);
    }
}
