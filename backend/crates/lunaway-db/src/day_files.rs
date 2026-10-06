//! The files of a journal kept outside the database, one per UTC day
//! (`<prefix>YYYYMMDD.jsonl`), one JSON line per entry: the account
//! deletions ([`crate::deletions`]) and the takedowns
//! ([`crate::takedown_journal`]). A dump restored after a failure brings
//! back what was undone after it was taken; the journal lives beside the
//! data, outside the dumps, and a replay after the restore applies it
//! again.
//!
//! A line is appended and synced to disk before what it records is
//! committed, so the database never holds what the journal lacks. A file is
//! never rewritten; whole days only are removed.

use std::{
    io::{Read as _, Seek as _, SeekFrom, Write as _},
    path::{Path, PathBuf},
};

use chrono::{DateTime, Duration, NaiveDate, Utc};

const SUFFIX: &str = ".jsonl";

/// A file or directory that could not be used, and why.
pub(crate) type IoAt = (PathBuf, std::io::Error);

/// The day a file name stands for, if it is one of the journal's.
pub(crate) fn day_of(prefix: &str, name: &str) -> Option<NaiveDate> {
    let digits = name.strip_prefix(prefix)?.strip_suffix(SUFFIX)?;
    if digits.len() != 8 || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    NaiveDate::parse_from_str(digits, "%Y%m%d").ok()
}

/// The day files of a journal: its directory and the prefix of its names.
#[derive(Debug, Clone, Copy)]
pub(crate) struct DayFiles<'a> {
    pub(crate) dir: &'a Path,
    pub(crate) prefix: &'static str,
}

fn at(path: &Path) -> impl FnOnce(std::io::Error) -> IoAt + '_ {
    move |e| (path.to_owned(), e)
}

impl DayFiles<'_> {
    /// The day's file of `at`, opened to append, the directory created
    /// (owner and group) when missing; a new file and its entry in the
    /// directory are synced, so the first line of a day survives a crash.
    pub(crate) fn open_day(&self, when: DateTime<Utc>) -> Result<(std::fs::File, PathBuf), IoAt> {
        let mut builder = std::fs::DirBuilder::new();
        builder.recursive(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::DirBuilderExt as _;
            builder.mode(0o750);
        }
        builder.create(self.dir).map_err(at(self.dir))?;
        let path = self
            .dir
            .join(format!("{}{}{SUFFIX}", self.prefix, when.format("%Y%m%d")));
        let new = !path.exists();
        let mut options = std::fs::OpenOptions::new();
        options.read(true).append(true).create(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt as _;
            options.mode(0o640);
        }
        let file = options.open(&path).map_err(at(&path))?;
        if new {
            std::fs::File::open(self.dir)
                .and_then(|d| d.sync_all())
                .map_err(at(self.dir))?;
        }
        Ok((file, path))
    }

    /// Appends `line` (one JSON object, no newline) to the day's file of
    /// `when` and syncs it to disk. A line cut by a crash is closed first,
    /// so it never swallows the next one.
    pub(crate) fn append(&self, line: &str, when: DateTime<Utc>) -> Result<(), IoAt> {
        let (mut file, path) = self.open_day(when)?;
        let empty = file.metadata().map_err(at(&path))?.len() == 0;
        let cut = if empty {
            false
        } else {
            file.seek(SeekFrom::End(-1)).map_err(at(&path))?;
            let mut last = [0_u8; 1];
            file.read_exact(&mut last).map_err(at(&path))?;
            last[0] != b'\n'
        };
        let line = if cut {
            format!("\n{line}\n")
        } else {
            format!("{line}\n")
        };
        // One write in append mode: an account deletion's short line never
        // interleaves with another writer's (the API and an operator's
        // command). A takedown's line runs to tens of kilobytes, and its
        // writers queue on the catalogue writers' lock instead.
        file.write_all(line.as_bytes()).map_err(at(&path))?;
        file.sync_data().map_err(at(&path))?;
        Ok(())
    }

    /// The day files, oldest first; none when the directory does not
    /// exist.
    pub(crate) fn days(&self) -> Result<Vec<(NaiveDate, PathBuf)>, IoAt> {
        let mut out = Vec::new();
        let dir = match std::fs::read_dir(self.dir) {
            Ok(d) => d,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(out),
            Err(e) => return Err(at(self.dir)(e)),
        };
        for item in dir {
            let item = item.map_err(at(self.dir))?;
            let name = item.file_name();
            if let Some(day) = name.to_str().and_then(|n| day_of(self.prefix, n)) {
                out.push((day, item.path()));
            }
        }
        out.sort();
        Ok(out)
    }

    /// Every non-empty line of every day file, oldest file first, in the
    /// order written, and how many files were read.
    pub(crate) fn lines(&self) -> Result<(Vec<String>, usize), IoAt> {
        let days = self.days()?;
        let mut lines = Vec::new();
        for (_, path) in &days {
            let text = std::fs::read_to_string(path).map_err(at(path))?;
            lines.extend(
                text.lines()
                    .filter(|l| !l.trim().is_empty())
                    .map(str::to_owned),
            );
        }
        Ok((lines, days.len()))
    }

    /// Removes the day files that began `keep` or more before `now`;
    /// returns how many.
    pub(crate) fn prune(&self, keep: Duration, now: DateTime<Utc>) -> Result<usize, IoAt> {
        let horizon = (now - keep).date_naive();
        let mut removed = 0;
        for (day, path) in self.days()? {
            if day <= horizon {
                std::fs::remove_file(&path).map_err(at(&path))?;
                removed += 1;
            }
        }
        Ok(removed)
    }
}
