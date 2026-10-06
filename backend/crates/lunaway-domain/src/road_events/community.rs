//! The users' reports of what they meet on the road: a closed road, works,
//! a narrow passage, a low clearance with its measured height, and the end
//! of one ("plus de travaux").
//!
//! One report is a warning for others: one account alone must not be able
//! to close a road. Two reports of the same thing at the same spot, from
//! two trusted accounts (level 1 or more), within [`CONFIRM_WINDOW`], block;
//! a measured height or width blocks only at a figure both agree on. The
//! reporter's own "it is over" ends the event; a trusted account's makes it
//! a warning again, and two trusted accounts' end it. Without new reports,
//! an event ends after its kind's lifetime ([`ReportKind::lifetime`]),
//! counted for a confirmed event from its last confirming pair.
//! Thresholds: the research's proposal
//! (`plan/research/20-travaux-temps-reel.md`, 5.7), hardened after the
//! security review, to adjust on real use.

use std::{fmt, ops::RangeInclusive, str::FromStr};

use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};

use super::{Confidence, EventClass, VehicleLimits};
use crate::{Position, UnknownCode, routing::turn_between, taxonomy::coded_enum};

/// How close two reports must be to be of the same spot, metres: a phone's
/// position is within a few tens of metres, and a closed stretch is longer.
pub const SAME_SPOT_M: f64 = 100.0;
/// Largest angle between the headings of two reports of the same spot: a
/// report heading the other way is about the other direction.
pub const SAME_HEADING_DEG: f64 = 60.0;
/// How close in time two reports of distinct accounts must be to confirm
/// each other.
pub const CONFIRM_WINDOW: Duration = Duration::hours(2);
/// Heights a user may report, metres: a B12 sign shows 1.9 m to 5 m.
pub const HEIGHT_M: RangeInclusive<f64> = 1.5..=6.0;
/// Widths a user may report, metres.
pub const WIDTH_M: RangeInclusive<f64> = 1.5..=5.0;
/// Largest gap between two measured figures of the same limit, metres: two
/// drivers reading one sign agree, a tape measure differs by a few
/// centimetres. A figure further off is another event, which only warns
/// until two trusted accounts confirm it.
pub const AGREE_M: f64 = 0.2;

coded_enum! {
    /// What a user reports.
    ReportKind {
        /// The road is closed.
        Closure => "closure",
        /// Works on the road.
        Works => "works",
        /// A narrow passage, with its width when measured.
        NarrowPassage => "narrow_passage",
        /// A clearance lower than signed or temporary, with its height.
        LowClearance => "low_clearance",
        /// What was reported here is over.
        Cleared => "cleared",
    }
}

impl ReportKind {
    /// How long an event of this kind lasts after its last report: a closed
    /// road reopens within hours more often than not, works and limits last
    /// days.
    #[must_use]
    pub const fn lifetime(self) -> Duration {
        match self {
            Self::Closure | Self::Cleared => Duration::hours(12),
            Self::Works | Self::NarrowPassage | Self::LowClearance => Duration::days(7),
        }
    }
}

/// Why a report is refused.
#[derive(Debug, Clone, Copy, PartialEq, thiserror::Error)]
#[non_exhaustive]
pub enum InvalidReport {
    /// A low clearance needs its height.
    #[error("a low clearance needs its height, {min} to {max} m", min = HEIGHT_M.start(), max = HEIGHT_M.end())]
    MissingHeight,
    /// The measured figure is outside what a sign shows.
    #[error("the figure must be between {min} and {max} m")]
    Figure {
        /// Least accepted.
        min: f64,
        /// Most accepted.
        max: f64,
    },
    /// Only a narrow passage or a low clearance takes a figure.
    #[error("only a narrow passage or a low clearance takes a figure")]
    UnexpectedFigure,
}

/// Checks the figure of a report of `kind`.
///
/// # Errors
///
/// [`InvalidReport`] when a low clearance lacks its height, a figure is out
/// of range, or a kind that takes none has one.
pub fn validate(kind: ReportKind, value_m: Option<f64>) -> Result<(), InvalidReport> {
    let range = match kind {
        ReportKind::LowClearance => &HEIGHT_M,
        ReportKind::NarrowPassage => &WIDTH_M,
        _ => {
            return match value_m {
                None => Ok(()),
                Some(_) => Err(InvalidReport::UnexpectedFigure),
            };
        }
    };
    match value_m {
        None if kind == ReportKind::LowClearance => Err(InvalidReport::MissingHeight),
        None => Ok(()),
        Some(v) if v.is_finite() && range.contains(&v) => Ok(()),
        Some(_) => Err(InvalidReport::Figure {
            min: *range.start(),
            max: *range.end(),
        }),
    }
}

/// A report as the rules read it; `A` identifies the account. Where it was
/// made is not part of it: the reports of one event are of one spot
/// already ([`same_spot`]), and the poller that weighs events again must
/// not read where each account was.
#[derive(Debug, Clone, PartialEq)]
pub struct ReportFacts<A> {
    /// Who reported it.
    pub account: A,
    /// What.
    pub kind: ReportKind,
    /// The measured height or width, metres.
    pub value_m: Option<f64>,
    /// When.
    pub created_at: DateTime<Utc>,
    /// Whether the account may confirm or end an event for everyone: level
    /// 1 or more, not banned. A level-0 account costs a key pair, so two of
    /// them must not be able to close a road.
    pub trusted: bool,
}

/// Whether two reports are of the same spot: close enough, and heading the
/// same way when both headings are known.
#[must_use]
pub fn same_spot(a: Position, a_heading: Option<u16>, b: Position, b_heading: Option<u16>) -> bool {
    if a.distance_m(b) > SAME_SPOT_M {
        return false;
    }
    match (a_heading, b_heading) {
        (Some(x), Some(y)) => turn_between(f64::from(x), f64::from(y)) <= SAME_HEADING_DEG,
        _ => true,
    }
}

/// Whether two measured figures describe the same limit, within
/// [`AGREE_M`]; a missing figure agrees with any.
#[must_use]
pub fn same_figure(a: Option<f64>, b: Option<f64>) -> bool {
    match (a, b) {
        (Some(x), Some(y)) => (x - y).abs() <= AGREE_M,
        _ => true,
    }
}

/// The event the reports of one spot and one kind make.
#[derive(Debug, Clone, PartialEq)]
pub struct CommunityEvent {
    /// What it does.
    pub class: EventClass,
    /// One account, or two trusted accounts that agree within the window.
    pub confidence: Confidence,
    /// The figure: when confirmed, the lowest two trusted accounts agree
    /// on; otherwise the lowest reported, which only warns.
    pub limits: VehicleLimits,
    /// The first report.
    pub first_report_at: DateTime<Utc>,
    /// The last report.
    pub last_report_at: DateTime<Utc>,
    /// When it ends without a new report: a confirmed event lives from its
    /// last confirming pair, so one account alone cannot keep it blocking.
    pub expires_at: DateTime<Utc>,
    /// Whether a trusted account said it is over since it was confirmed:
    /// it only warns until two trusted accounts confirm it again.
    pub disputed: bool,
}

/// Two reports confirm each other: distinct trusted accounts, within
/// [`CONFIRM_WINDOW`], of the same figure.
fn confirm<A: PartialEq>(a: &ReportFacts<A>, b: &ReportFacts<A>) -> bool {
    a.account != b.account
        && a.trusted
        && b.trusted
        && (a.created_at - b.created_at).abs() <= CONFIRM_WINDOW
        && (a.kind != ReportKind::LowClearance || same_figure(a.value_m, b.value_m))
}

fn lowest(values: impl Iterator<Item = f64>) -> Option<f64> {
    values.fold(None, |m: Option<f64>, v| Some(m.map_or(v, |m| m.min(v))))
}

/// What `reports` (one spot, one kind, and the "it is over" reports of the
/// event) make together; `None` when the event is over: no report left,
/// its only reporter took it back, or two trusted accounts said it is over
/// after its last report.
///
/// A trusted account's "it is over" leaves the event a warning: reports
/// made before it no longer confirm. A level-0 account's counts only to
/// take back its own report.
#[must_use]
pub fn summarize<A: PartialEq>(reports: &[ReportFacts<A>]) -> Option<CommunityEvent> {
    let supporting: Vec<&ReportFacts<A>> = reports
        .iter()
        .filter(|r| r.kind != ReportKind::Cleared)
        .collect();
    let kind = supporting.first()?.kind;
    if supporting.iter().any(|r| r.kind != kind) {
        return None;
    }
    let first_report_at = supporting.iter().map(|r| r.created_at).min()?;
    let last_report_at = supporting.iter().map(|r| r.created_at).max()?;
    let clears: Vec<&ReportFacts<A>> = reports
        .iter()
        .filter(|r| r.kind == ReportKind::Cleared)
        .collect();
    let latest_clears: Vec<&&ReportFacts<A>> = clears
        .iter()
        .filter(|c| c.created_at >= last_report_at)
        .collect();
    let withdrawn = latest_clears
        .iter()
        .any(|c| supporting.iter().all(|s| s.account == c.account));
    let mut ending: Vec<&A> = Vec::new();
    for c in latest_clears.iter().filter(|c| c.trusted) {
        if !ending.contains(&&c.account) {
            ending.push(&c.account);
        }
    }
    if withdrawn || ending.len() >= 2 {
        return None;
    }
    let cutoff = clears
        .iter()
        .filter(|c| c.trusted)
        .map(|c| c.created_at)
        .max();
    let fresh: Vec<&&ReportFacts<A>> = supporting
        .iter()
        .filter(|r| cutoff.is_none_or(|c| r.created_at > c))
        .collect();
    let pairs: Vec<(&ReportFacts<A>, &ReportFacts<A>)> = fresh
        .iter()
        .enumerate()
        .flat_map(|(i, a)| fresh[i + 1..].iter().map(move |b| (**a, **b)))
        .filter(|(a, b)| confirm(a, b))
        .collect();
    let confirmed = !pairs.is_empty();
    let figure = if confirmed {
        lowest(
            pairs
                .iter()
                .filter_map(|(a, b)| Some(a.value_m?.min(b.value_m?))),
        )
    } else {
        lowest(supporting.iter().filter_map(|r| r.value_m))
    };
    let (class, limits) = match kind {
        ReportKind::LowClearance => (
            EventClass::VehicleLimit,
            VehicleLimits {
                max_height_m: figure,
                ..VehicleLimits::default()
            },
        ),
        ReportKind::NarrowPassage if figure.is_some() => (
            EventClass::VehicleLimit,
            VehicleLimits {
                max_width_m: figure,
                ..VehicleLimits::default()
            },
        ),
        ReportKind::NarrowPassage => (EventClass::LaneRestriction, VehicleLimits::default()),
        ReportKind::Works => (EventClass::Works, VehicleLimits::default()),
        _ => (EventClass::Closure, VehicleLimits::default()),
    };
    let lives_from = if confirmed {
        pairs
            .iter()
            .map(|(a, b)| a.created_at.max(b.created_at))
            .max()
            .unwrap_or(last_report_at)
    } else {
        last_report_at
    };
    Some(CommunityEvent {
        class,
        confidence: if confirmed {
            Confidence::Confirmed
        } else {
            Confidence::Reported
        },
        limits,
        first_report_at,
        last_report_at,
        expires_at: lives_from + kind.lifetime(),
        disputed: cutoff.is_some() && !confirmed,
    })
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone as _;

    use super::*;

    fn t(h: i64) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 10, 6, 8, 0, 0).unwrap() + Duration::minutes(h)
    }

    fn report(account: u8, kind: ReportKind, minutes: i64) -> ReportFacts<u8> {
        ReportFacts {
            account,
            kind,
            value_m: None,
            created_at: t(minutes),
            trusted: true,
        }
    }

    fn clearance(account: u8, minutes: i64, height: f64) -> ReportFacts<u8> {
        ReportFacts {
            value_m: Some(height),
            ..report(account, ReportKind::LowClearance, minutes)
        }
    }

    fn cleared(account: u8, minutes: i64, trusted: bool) -> ReportFacts<u8> {
        ReportFacts {
            trusted,
            ..report(account, ReportKind::Cleared, minutes)
        }
    }

    #[test]
    fn one_account_warns_and_two_accounts_block() {
        let one = summarize(&[report(1, ReportKind::Closure, 0)]).unwrap();
        assert_eq!(one.class, EventClass::Closure);
        assert_eq!(
            one.confidence,
            Confidence::Reported,
            "one account alone must not close a road for everyone"
        );
        let same_account = summarize(&[
            report(1, ReportKind::Closure, 0),
            report(1, ReportKind::Closure, 10),
        ])
        .unwrap();
        assert_eq!(
            same_account.confidence,
            Confidence::Reported,
            "reporting twice does not confirm one's own report"
        );
        let two = summarize(&[
            report(1, ReportKind::Closure, 0),
            report(2, ReportKind::Closure, 90),
        ])
        .unwrap();
        assert_eq!(two.confidence, Confidence::Confirmed);
        assert_eq!(two.expires_at, t(90) + Duration::hours(12));
        let apart = summarize(&[
            report(1, ReportKind::Closure, 0),
            report(2, ReportKind::Closure, 180),
        ])
        .unwrap();
        assert_eq!(
            apart.confidence,
            Confidence::Reported,
            "two reports three hours apart may describe two different closures"
        );
    }

    #[test]
    fn new_accounts_warn_and_never_block() {
        let mut a = report(1, ReportKind::Closure, 0);
        let mut b = report(2, ReportKind::Closure, 10);
        a.trusted = false;
        b.trusted = false;
        assert_eq!(
            summarize(&[a.clone(), b.clone()]).unwrap().confidence,
            Confidence::Reported,
            "two level-0 accounts cost two key pairs: they must not close a road"
        );
        b.trusted = true;
        assert_eq!(
            summarize(&[a, b]).unwrap().confidence,
            Confidence::Reported,
            "both accounts of the pair must be trusted"
        );
    }

    #[test]
    fn a_clearance_blocks_at_a_height_two_accounts_agree_on() {
        let e = summarize(&[clearance(1, 0, 3.4), clearance(2, 5, 3.3)]).unwrap();
        assert_eq!(e.class, EventClass::VehicleLimit);
        assert_eq!(e.confidence, Confidence::Confirmed);
        assert_eq!(e.limits.max_height_m, Some(3.3));
        assert_eq!(e.expires_at, t(5) + Duration::days(7));
        let lowered = summarize(&[
            clearance(1, 0, 3.4),
            clearance(2, 5, 3.4),
            clearance(3, 9, 1.5),
        ])
        .unwrap();
        assert_eq!(
            lowered.limits.max_height_m,
            Some(3.4),
            "one account alone must not lower a confirmed limit"
        );
        let apart = summarize(&[clearance(1, 0, 3.4), clearance(2, 5, 2.9)]).unwrap();
        assert_eq!(
            apart.confidence,
            Confidence::Reported,
            "two figures half a metre apart describe two limits, neither confirmed"
        );
        assert_eq!(
            apart.limits.max_height_m,
            Some(2.9),
            "the warning shows the lowest"
        );
        let narrow = summarize(&[report(1, ReportKind::NarrowPassage, 0)]).unwrap();
        assert_eq!(
            narrow.class,
            EventClass::LaneRestriction,
            "a narrow passage without a width warns"
        );
        assert_eq!(summarize::<u8>(&[]), None);
        assert_eq!(summarize(&[report(1, ReportKind::Cleared, 0)]), None);
    }

    #[test]
    fn one_account_cannot_keep_a_confirmed_event_alive() {
        let e = summarize(&[
            report(1, ReportKind::Closure, 0),
            report(2, ReportKind::Closure, 10),
            report(3, ReportKind::Closure, 600),
        ])
        .unwrap();
        assert_eq!(e.confidence, Confidence::Confirmed);
        assert_eq!(
            e.expires_at,
            t(10) + Duration::hours(12),
            "a lone later report does not extend the block"
        );
        assert_eq!(e.last_report_at, t(600));
    }

    #[test]
    fn it_is_over_takes_the_reporter_or_two_trusted_accounts() {
        let confirmed = [
            report(1, ReportKind::Closure, 0),
            report(2, ReportKind::Closure, 10),
        ];
        let with = |extra: &[ReportFacts<u8>]| {
            let mut all = confirmed.to_vec();
            all.extend_from_slice(extra);
            summarize(&all)
        };
        let one = with(&[cleared(3, 30, true)]).unwrap();
        assert_eq!(
            one.confidence,
            Confidence::Reported,
            "one trusted account makes a confirmed closure a warning"
        );
        assert!(one.disputed);
        assert_eq!(
            with(&[cleared(3, 30, true), cleared(4, 40, true)]),
            None,
            "two trusted accounts end it"
        );
        let new_account = with(&[cleared(3, 30, false)]).unwrap();
        assert_eq!(
            new_account.confidence,
            Confidence::Confirmed,
            "a level-0 account cannot lift a confirmed closure"
        );
        assert_eq!(
            with(&[cleared(3, 30, true), cleared(3, 40, true)])
                .unwrap()
                .confidence,
            Confidence::Reported,
            "one account saying it twice is still one account"
        );
        let again = with(&[
            cleared(3, 30, true),
            report(4, ReportKind::Closure, 60),
            report(5, ReportKind::Closure, 70),
        ])
        .unwrap();
        assert_eq!(
            again.confidence,
            Confidence::Confirmed,
            "two trusted accounts after the doubt confirm it again"
        );
        let own = [report(1, ReportKind::Closure, 0), cleared(1, 5, false)];
        assert_eq!(summarize(&own), None, "the only reporter takes it back");
    }

    #[test]
    fn reports_of_one_spot_head_the_same_way() {
        let a = Position::new(45.8, 1.25).unwrap();
        let b = Position::new(45.8005, 1.25).unwrap();
        assert!(same_spot(a, Some(10), b, Some(350)));
        assert!(!same_spot(a, Some(10), b, Some(190)), "the other direction");
        assert!(same_spot(a, None, b, Some(190)));
        let far = Position::new(45.81, 1.25).unwrap();
        assert!(!same_spot(a, None, far, None));
    }

    #[test]
    fn figures_fit_their_kind() {
        assert_eq!(
            validate(ReportKind::LowClearance, None),
            Err(InvalidReport::MissingHeight)
        );
        assert!(validate(ReportKind::LowClearance, Some(3.2)).is_ok());
        assert!(validate(ReportKind::LowClearance, Some(32.0)).is_err());
        assert!(validate(ReportKind::NarrowPassage, None).is_ok());
        assert!(validate(ReportKind::NarrowPassage, Some(2.1)).is_ok());
        assert_eq!(
            validate(ReportKind::Closure, Some(2.0)),
            Err(InvalidReport::UnexpectedFigure)
        );
        assert!(validate(ReportKind::Works, Some(f64::NAN)).is_err());
    }
}
