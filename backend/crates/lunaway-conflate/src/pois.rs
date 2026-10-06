//! The worker's part of the points of interest: their opening intervals,
//! the vending machines users add, and what the community says of them.
//!
//! Points are not conflated: each step here reads and writes the POI layer
//! under the POI writers' lock, in short transactions of a bounded number
//! of points, so the fuel poller or an import never waits long.

use chrono::{DateTime, Days, NaiveDate, TimeZone, Utc};
use chrono_tz::Tz;
use lunaway_db::{
    PgPool,
    pois::{self, HoursWrite, StaleHours},
};
use lunaway_domain::{
    OPENING_WINDOW_DAYS, OpeningInterval, SourceId,
    poi::{PostOfficeDays, encode_hours},
};

use crate::{ConflateError, blocking, opening};

/// Points evaluated per transaction.
const HOURS_BATCH: i64 = 2_000;

/// How La Poste's `24:00` is stored (`laposte.rs`).
const END_OF_DAY: chrono::NaiveTime = match chrono::NaiveTime::from_hms_opt(23, 59, 59) {
    Some(t) => t,
    None => chrono::NaiveTime::MIN,
};

/// What a refresh of the hours did.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct HoursStats {
    /// Points evaluated.
    pub evaluated: u64,
    /// Of which with intervals from La Poste's calendar.
    pub from_laposte: u64,
    /// Points whose tile hours changed.
    pub changed: u64,
}

/// Evaluates the opening intervals of every point whose window must move at
/// `now` (new points, new hours, new La Poste days, and every point once a
/// day at its local midnight), in batches.
///
/// # Errors
///
/// [`ConflateError`] when the database fails; the batches already written
/// stay.
pub async fn refresh_hours(pool: &PgPool, now: DateTime<Utc>) -> Result<HoursStats, ConflateError> {
    let mut stats = HoursStats::default();
    loop {
        let mut tx = pois::begin_poi_writer(pool).await?;
        let stale = pois::stale_hours(&mut tx, now, HOURS_BATCH).await?;
        if stale.is_empty() {
            tx.commit().await?;
            break;
        }
        let n = stale.len();
        let writes = blocking(move || {
            stale
                .into_iter()
                .map(|s| evaluate(&s, now))
                .collect::<Vec<_>>()
        })
        .await?;
        stats.evaluated += u64::try_from(n).unwrap_or(u64::MAX);
        stats.from_laposte += u64::try_from(
            writes
                .iter()
                .filter(|w| w.source.as_ref() == Some(&SourceId::LAPOSTE))
                .count(),
        )
        .unwrap_or(u64::MAX);
        stats.changed += pois::set_hours(&mut tx, &writes).await?;
        tx.commit().await?;
        if i64::try_from(n).unwrap_or(i64::MAX) < HOURS_BATCH {
            break;
        }
    }
    // Once for the whole refresh; the worker publishes the change with the
    // others of the next hours.
    if stats.changed > 0 {
        pois::mark_layer_now(pool).await?;
    }
    if stats.evaluated > 0 {
        tracing::info!(?stats, "points of interest: opening hours refreshed");
    }
    Ok(stats)
}

/// The hours of one point: La Poste's calendar when it covers the start of
/// the window, its `opening_hours` otherwise. The window starts on the
/// point's own local date at `now`.
fn evaluate(s: &StaleHours, now: DateTime<Utc>) -> HoursWrite {
    let country = s.country_code.as_deref().or(Some("FR"));
    let today = opening::local_today(country, s.position, now);
    let refresh_at = opening::refresh_at(country, s.position, today);
    // La Poste's calendar is French: a point without a known zone that has
    // one is in France.
    let tz = country
        .and_then(|cc| opening::timezone_at(cc, s.position))
        .unwrap_or(Tz::Europe__Paris);
    if let Some((intervals, until)) = s
        .laposte
        .as_ref()
        .and_then(|v| <PostOfficeDays as serde::Deserialize>::deserialize(v).ok())
        .and_then(|days| laposte_intervals(&days, tz, today))
    {
        return HoursWrite {
            id: s.id,
            parsed: true,
            tile: Some(encode_hours(&intervals)),
            intervals: Some(intervals),
            until: Some(until),
            window_start: today,
            refresh_at,
            source: Some(SourceId::LAPOSTE),
        };
    }
    let eval = opening::evaluate(s.opening_hours.as_deref(), country, s.position, today);
    HoursWrite {
        id: s.id,
        parsed: eval.parsed,
        tile: eval.intervals.as_deref().map(encode_hours),
        source: eval.intervals.as_ref().map(|_| s.source_id.clone()),
        intervals: eval.intervals,
        until: eval.until,
        window_start: today,
        refresh_at,
    }
}

/// Publishes the changes of the points layer as a new tiles version, when
/// one waits and the last version is older than `every`. Returns the new
/// version.
///
/// # Errors
///
/// [`ConflateError`] when the database fails.
pub async fn publish_layer(
    pool: &PgPool,
    every: std::time::Duration,
) -> Result<Option<i64>, ConflateError> {
    let v = pois::publish_layer(pool, every).await?;
    if let Some(version) = v {
        tracing::info!(version, "points layer: new tiles version");
    }
    Ok(v)
}

/// UTC intervals from La Poste's day-by-day calendar, from local midnight
/// of `today` for [`OPENING_WINDOW_DAYS`] days, and the end of what they
/// cover: the calendar's last consecutive day from `today`, so a missing day
/// is unknown rather than closed. `None` when the calendar does not hold
/// `today`.
#[must_use]
pub fn laposte_intervals(
    days: &PostOfficeDays,
    tz: Tz,
    today: NaiveDate,
) -> Option<(Vec<OpeningInterval>, DateTime<Utc>)> {
    let mut out: Vec<OpeningInterval> = Vec::new();
    let mut covered_to: Option<NaiveDate> = None;
    let window = u64::try_from(OPENING_WINDOW_DAYS).ok()?;
    for offset in 0..window {
        let date = today.checked_add_days(Days::new(offset))?;
        let Some(day) = days.days.iter().find(|d| d.date == date) else {
            break;
        };
        for [open, close] in &day.open {
            let local = |day: NaiveDate, t: chrono::NaiveTime| {
                tz.from_local_datetime(&day.and_time(t))
                    .earliest()
                    .map(|d| d.with_timezone(&Utc))
            };
            // La Poste's `24:00` is stored as the day's last second, which
            // a time of day can hold: it closes at midnight.
            let close_at = if *close == END_OF_DAY {
                date.checked_add_days(Days::new(1))
                    .and_then(|next| local(next, chrono::NaiveTime::MIN))
            } else {
                local(date, *close)
            };
            let (Some(start), Some(end)) = (local(date, *open), close_at) else {
                continue;
            };
            if start >= end {
                continue;
            }
            match out.last_mut() {
                Some(last) if last.end == start => last.end = end,
                _ => out.push(OpeningInterval { start, end }),
            }
        }
        covered_to = Some(date);
    }
    let last = covered_to?;
    let until = tz
        .from_local_datetime(&last.checked_add_days(Days::new(1))?.and_hms_opt(0, 0, 0)?)
        .earliest()?
        .with_timezone(&Utc);
    Some((out, until))
}

/// What a community step did.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct CommunityStats {
    /// Vending machines written as points.
    pub vending_added: u64,
    /// Points whose community state changed (last "still there", hidden).
    pub refreshed: u64,
}

/// Writes the accepted vending machines, purges the answers past their
/// year, and recomputes the community state of the points the API queued
/// and of those the purge touched, in one POI writer transaction.
///
/// # Errors
///
/// [`ConflateError`] when the database fails; nothing of the step is kept
/// and the queue stays.
pub async fn community(pool: &PgPool) -> Result<CommunityStats, ConflateError> {
    let mut tx = pois::begin_poi_writer(pool).await?;
    let applied = pois::apply_submissions(&mut tx).await?;
    let mut queued = pois::take_refresh_queue(&mut tx).await?;
    queued.extend(pois::purge_old_answers(&mut tx).await?);
    queued.sort_unstable();
    queued.dedup();
    let refreshed = pois::refresh_community(&mut tx, &queued).await?;
    tx.commit().await?;
    Ok(CommunityStats {
        vending_added: applied.applied,
        refreshed,
    })
}

#[cfg(test)]
mod tests {
    use chrono::{NaiveTime, Timelike};
    use lunaway_domain::poi::PostDay;

    use super::*;

    fn t(h: u32, m: u32) -> NaiveTime {
        NaiveTime::from_hms_opt(h, m, 0).unwrap()
    }

    #[test]
    fn la_poste_days_become_utc_intervals_and_a_gap_ends_the_window() {
        let monday = NaiveDate::from_ymd_opt(2026, 11, 2).unwrap();
        let day = |d: u32, open: Vec<[NaiveTime; 2]>| PostDay {
            date: NaiveDate::from_ymd_opt(2026, 11, d).unwrap(),
            open,
        };
        let days = PostOfficeDays {
            kind: Some("Bureau de Poste".into()),
            days: vec![
                day(2, vec![[t(9, 0), t(12, 0)], [t(14, 0), t(18, 0)]]),
                day(3, vec![]),
                day(4, vec![[t(9, 0), t(12, 0)], [t(20, 0), END_OF_DAY]]),
                // The 5th is missing: from it on, nothing is known.
                day(6, vec![[t(9, 0), t(12, 0)]]),
            ],
        };
        let (iv, until) = laposte_intervals(&days, Tz::Europe__Paris, monday).unwrap();
        assert_eq!(iv.len(), 4, "the 3rd is closed, the 6th is past the gap");
        assert_eq!(
            iv[3].end,
            Utc.with_ymd_and_hms(2026, 11, 4, 23, 0, 0).unwrap(),
            "24:00 closes at local midnight, not a second before"
        );
        assert_eq!(
            iv[0].start.hour(),
            8,
            "09:00 in Paris is 08:00 UTC in November"
        );
        assert_eq!(
            until,
            Utc.with_ymd_and_hms(2026, 11, 4, 23, 0, 0).unwrap(),
            "the window ends at local midnight after the last day held"
        );
        assert!(
            laposte_intervals(&days, Tz::Europe__Paris, monday.pred_opt().unwrap()).is_none(),
            "a calendar that does not hold today gives nothing"
        );
    }
}
