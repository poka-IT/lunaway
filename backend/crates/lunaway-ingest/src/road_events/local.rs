//! City and département datasets of closures and works, the ones the
//! research found usable (`plan/research/20-travaux-temps-reel.md`, 1.4,
//! and `plan/research/27-backend-communaute-travaux2.md`): Paris (road
//! closures, disruptive works), Lyon (disruptive works), Toulouse (works in
//! progress), Charente-Maritime (closed roads, in the Waze CIFS format),
//! Rennes (works of the next 30 days), Aix-Marseille-Provence (tunnel
//! closures), Mayenne (closed roads in Waze's fields), the Côtes-d'Armor
//! (works orders on departmental roads), the Sarthe (works on departmental
//! roads), Bordeaux (works orders). None carries a vehicle limit: they give
//! closures and lane restrictions. A closure drawn as a line is matched to the graph and
//! may block; one drawn as an area cannot be placed on a road and warns.
//!
//! Each dataset is read whole, once an hour, and is the truth for its
//! source: an event missing from it ended.

use std::collections::BTreeMap;

use chrono::{DateTime, Duration, NaiveDate, NaiveDateTime, TimeZone as _, Utc};
use lunaway_db::road_events::NewEvent;
use lunaway_domain::{
    Position,
    road_events::{
        Carriageway, Confidence, EndReason, EventClass, EventDirection, MatchQuality, Schedule,
        SourceGeometry, VehicleLimits, road,
    },
    routing::is_covered,
};
use serde_json::Value;

use super::{ParseError, cap_raw, digest, instant, past_end};

/// The widening of the Paris closures' times when their date-times and
/// their period text disagree: the research found 122 of 153 three hours
/// apart and 30 one hour apart, and could not tell which is right.
const PARIS_DOUBT: Duration = Duration::hours(3);

/// A dataset and how to read it.
#[derive(Debug, Clone, Copy)]
pub struct LocalFeed {
    /// The source id (`road_event_sources.id`).
    pub id: &'static str,
    /// Where it is read: the export, or the data.gouv.fr dataset whose
    /// resource is read.
    pub url: &'static str,
    /// Hosts the URL and the resource may be on.
    pub hosts: &'static [&'static str],
    /// The format.
    pub format: Format,
}

/// How a dataset is written.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum Format {
    /// GeoJSON features with Paris's road closure fields.
    ParisClosures,
    /// GeoJSON features with Paris's works fields.
    ParisWorks,
    /// GeoJSON features with Lyon's works fields.
    LyonWorks,
    /// GeoJSON features with Toulouse's works fields.
    ToulouseWorks,
    /// Waze CIFS JSON (`incidents[].incident`), its file named by the
    /// data.gouv.fr dataset at `url`.
    CifsDataGouv,
    /// GeoJSON features with Rennes's works fields, one per measure.
    RennesWorks,
    /// GeoJSON features of Aix-Marseille-Provence's tunnel closures.
    AixMarseilleTunnels,
    /// GeoJSON features with Waze's fields, as the Mayenne writes them.
    MayenneClosures,
    /// Data Fair GeoJSON of the Côtes-d'Armor's works orders; `{today}` in
    /// the URL is replaced by the day of the read.
    CotesDArmorOrders,
    /// GeoJSON features of the Sarthe's road works.
    SartheWorks,
    /// GeoJSON features of Bordeaux's works orders.
    BordeauxWorks,
}

/// The datasets read, with their terms in `docs/data-sources.md`.
pub const FEEDS: [LocalFeed; 11] = [
    LocalFeed {
        id: "paris-fermetures",
        url: "https://opendata.paris.fr/api/explore/v2.1/catalog/datasets/fermetures-voirie/exports/geojson",
        hosts: &["opendata.paris.fr"],
        format: Format::ParisClosures,
    },
    LocalFeed {
        id: "paris-chantiers",
        url: "https://opendata.paris.fr/api/explore/v2.1/catalog/datasets/chantiers-perturbants/exports/geojson",
        hosts: &["opendata.paris.fr"],
        format: Format::ParisWorks,
    },
    LocalFeed {
        id: "lyon",
        url: "https://data.grandlyon.com/geoserver/metropole-de-lyon/ows?SERVICE=WFS&VERSION=2.0.0&request=GetFeature&typename=metropole-de-lyon:pvo_patrimoine_voirie.pvochantierperturbant&outputFormat=application/json&SRSNAME=EPSG:4326",
        hosts: &["data.grandlyon.com"],
        format: Format::LyonWorks,
    },
    LocalFeed {
        id: "toulouse",
        url: "https://data.toulouse-metropole.fr/api/explore/v2.1/catalog/datasets/chantiers-en-cours/exports/geojson",
        hosts: &["data.toulouse-metropole.fr"],
        format: Format::ToulouseWorks,
    },
    LocalFeed {
        id: "charente-maritime",
        url: "https://www.data.gouv.fr/api/1/datasets/incidents-et-routes-fermees/",
        hosts: &["www.data.gouv.fr", "static.data.gouv.fr"],
        format: Format::CifsDataGouv,
    },
    LocalFeed {
        id: "rennes",
        url: "https://data.rennesmetropole.fr/api/explore/v2.1/catalog/datasets/travaux_30_jours/exports/geojson",
        hosts: &["data.rennesmetropole.fr"],
        format: Format::RennesWorks,
    },
    LocalFeed {
        id: "aix-marseille-tunnels",
        url: "https://data.ampmetropole.fr/api/explore/v2.1/catalog/datasets/fr-fermeture-des-tunnels-exploites-par-la-metropole/exports/geojson",
        hosts: &["data.ampmetropole.fr"],
        format: Format::AixMarseilleTunnels,
    },
    LocalFeed {
        id: "mayenne",
        url: "https://data.lamayenne.fr/api/explore/v2.1/catalog/datasets/225300011_waze_road-closures/exports/geojson",
        hosts: &["data.lamayenne.fr"],
        format: Format::MayenneClosures,
    },
    LocalFeed {
        id: "cotes-d-armor",
        url: "https://datarmor.cotesdarmor.fr/data-fair/api/v1/datasets/cd22arreteschantiers/lines?size=1000&format=geojson&DATEFIN_gte={today}",
        hosts: &["datarmor.cotesdarmor.fr"],
        format: Format::CotesDArmorOrders,
    },
    LocalFeed {
        id: "sarthe",
        url: "https://data.sarthe.fr/api/explore/v2.1/catalog/datasets/227200029_chantiers_routiers/exports/geojson",
        hosts: &["data.sarthe.fr"],
        format: Format::SartheWorks,
    },
    LocalFeed {
        id: "bordeaux",
        url: "https://opendata.bordeaux-metropole.fr/api/explore/v2.1/catalog/datasets/ci_chantier/exports/geojson",
        hosts: &["opendata.bordeaux-metropole.fr"],
        format: Format::BordeauxWorks,
    },
];

/// The page size the Côtes-d'Armor's export is asked with (`size=1000`):
/// an answer that fills it may have more, and read as complete it would end
/// the orders past the page.
pub const COTES_D_ARMOR_PAGE: usize = 1_000;

/// The URL of `feed` for a read on `now`: a dataset filtered by date names
/// the day in Paris.
#[must_use]
pub fn url_for(url: &str, now: DateTime<Utc>) -> String {
    url.replace(
        "{today}",
        &now.with_timezone(&chrono_tz::Europe::Paris)
            .format("%Y-%m-%d")
            .to_string(),
    )
}

/// What a dataset gave.
#[derive(Debug, Clone, Default)]
pub struct Publication {
    /// The events.
    pub events: Vec<NewEvent>,
    /// Features read.
    pub features: usize,
    /// Features left out, by reason.
    pub skipped: BTreeMap<String, usize>,
}

/// The facts a feature maps to.
struct Mapped {
    external_id: String,
    class: EventClass,
    detail: String,
    carriageway: Carriageway,
    direction: EventDirection,
    road_number: Option<String>,
    road_name: Option<String>,
    valid_from: DateTime<Utc>,
    valid_to: Option<DateTime<Utc>>,
    schedule: Schedule,
    description: Option<String>,
}

fn text<'a>(props: &'a serde_json::Map<String, Value>, key: &str) -> Option<&'a str> {
    props
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
}

fn id_of(props: &serde_json::Map<String, Value>, key: &str) -> Option<String> {
    match props.get(key)? {
        Value::String(s) if !s.trim().is_empty() => Some(s.trim().chars().take(150).collect()),
        Value::Number(n) => Some(n.to_string()),
        _ => None,
    }
}

/// A date (`2026-10-05`, or a date-time whose date counts) at a time of day
/// in Paris.
fn paris_day(raw: &str, h: u32, m: u32, s: u32) -> Option<DateTime<Utc>> {
    let date = NaiveDate::parse_from_str(raw.get(..10)?, "%Y-%m-%d").ok()?;
    chrono_tz::Europe::Paris
        .from_local_datetime(&date.and_hms_opt(h, m, s)?)
        .earliest()
        .map(|d| d.with_timezone(&Utc))
}

/// The two ends of a Paris period text: "Du lundi 07/09/2026 22:00 au mardi
/// 08/09/2026 06:00", Paris time.
fn paris_period(text: &str) -> Option<(DateTime<Utc>, DateTime<Utc>)> {
    let stamps: Vec<DateTime<Utc>> = text
        .split_whitespace()
        .collect::<Vec<_>>()
        .windows(2)
        .filter_map(|w| {
            let t = NaiveDateTime::parse_from_str(&format!("{} {}", w[0], w[1]), "%d/%m/%Y %H:%M")
                .ok()?;
            chrono_tz::Europe::Paris
                .from_local_datetime(&t)
                .earliest()
                .map(|d| d.with_timezone(&Utc))
        })
        .collect();
    match stamps.as_slice() {
        [a, b, ..] => Some((*a, *b)),
        _ => None,
    }
}

fn joined(parts: &[Option<&str>]) -> Option<String> {
    let parts: Vec<&str> = parts.iter().flatten().copied().collect();
    (!parts.is_empty()).then(|| parts.join(". ").chars().take(2_000).collect())
}

fn paris_closure(p: &serde_json::Map<String, Value>) -> Result<Mapped, &'static str> {
    if text(p, "etat_avancement") == Some("Terminé") {
        return Err("finished");
    }
    let external_id = id_of(p, "identifiant_fv").ok_or("no id")?;
    let kind = text(p, "type_fv").unwrap_or("Fermeture");
    let start = text(p, "date_debut_bar_fv").and_then(instant);
    let end = text(p, "date_fin_bar_fv").and_then(instant);
    let period = text(p, "periode_fv");
    let said = period.and_then(paris_period);
    // The widest reading of the two: a closure is never shorter than one of
    // them says.
    let (valid_from, valid_to, label) = match (start, end, said) {
        (Some(s), Some(e), Some((ps, pe))) if s == ps && e == pe => (s, Some(e), None),
        (Some(s), Some(e), Some((ps, pe))) => (s.min(ps), Some(e.max(pe)), None),
        (Some(s), e, None) => (
            s - PARIS_DOUBT,
            e.map(|e| e + PARIS_DOUBT),
            Some("heures incertaines"),
        ),
        (None, _, Some((ps, pe))) => (ps, Some(pe), None),
        _ => return Err("no dates"),
    };
    Ok(Mapped {
        external_id,
        class: EventClass::Closure,
        detail: kind.chars().take(100).collect(),
        carriageway: if kind == "Bretelle" {
            Carriageway::Ramps
        } else {
            Carriageway::Main
        },
        direction: EventDirection::Both,
        road_number: None,
        road_name: text(p, "lieu_fv").map(|s| s.chars().take(200).collect()),
        valid_from,
        valid_to,
        schedule: Schedule {
            label: label.map(str::to_owned),
            ..Schedule::default()
        },
        description: joined(&[text(p, "lieu_fv"), period, text(p, "sens_fv")]),
    })
}

fn paris_works(p: &serde_json::Map<String, Value>) -> Result<Mapped, &'static str> {
    let external_id = id_of(p, "identifiant").ok_or("no id")?;
    let impact = text(p, "impact_circulation").ok_or("no traffic impact")?;
    let class = match impact {
        "BARRAGE_TOTAL" => EventClass::Closure,
        "RESTREINTE" | "SENS_UNIQUE" | "IMPASSE" => EventClass::LaneRestriction,
        _ => return Err("no traffic impact"),
    };
    let valid_from = text(p, "date_debut")
        .and_then(|d| paris_day(d, 0, 0, 0))
        .ok_or("no dates")?;
    let valid_to = text(p, "date_fin").and_then(|d| paris_day(d, 23, 59, 59));
    Ok(Mapped {
        external_id,
        class,
        detail: impact.to_owned(),
        carriageway: Carriageway::Main,
        direction: EventDirection::Both,
        road_number: None,
        road_name: text(p, "voie").map(|s| s.chars().take(200).collect()),
        valid_from,
        valid_to,
        schedule: Schedule::default(),
        description: joined(&[
            text(p, "voie"),
            text(p, "impact_circulation_detail"),
            text(p, "description"),
        ]),
    })
}

fn lyon_works(p: &serde_json::Map<String, Value>) -> Result<Mapped, &'static str> {
    let external_id = id_of(p, "gid").ok_or("no id")?;
    let kind = text(p, "typeperturbation").ok_or("no traffic impact")?;
    let lower = kind.to_lowercase();
    let class = if lower.contains("interdite") {
        EventClass::Closure
    } else if lower.contains("réduite")
        || lower.contains("alternée")
        || lower.contains("sens unique")
    {
        EventClass::LaneRestriction
    } else {
        return Err("no traffic impact");
    };
    // Every record reads "Chantier en cours", those of next month included
    // (354 of 354 on 2026-10-06): the dates decide.
    let valid_from = text(p, "debutchantier")
        .and_then(|d| paris_day(d, 0, 0, 0))
        .ok_or("no dates")?;
    let valid_to = text(p, "finchantier").and_then(|d| paris_day(d, 23, 59, 59));
    let schedule = if lower.contains("de jour") || lower.contains("de nuit") {
        Schedule::from_label(kind)
    } else {
        Schedule::default()
    };
    Ok(Mapped {
        external_id,
        class,
        detail: kind.chars().take(100).collect(),
        carriageway: Carriageway::Main,
        direction: EventDirection::Both,
        road_number: None,
        road_name: text(p, "nom").map(|s| s.chars().take(200).collect()),
        valid_from,
        valid_to,
        schedule,
        description: joined(&[
            text(p, "nom"),
            text(p, "precisionlocalisation"),
            text(p, "nomchantier"),
            text(p, "descripchantierinternet"),
        ]),
    })
}

fn toulouse_works(p: &serde_json::Map<String, Value>) -> Result<Mapped, &'static str> {
    let external_id = id_of(p, "numero").ok_or("no id")?;
    let traffic = text(p, "circulation").ok_or("no traffic impact")?;
    let lower = traffic.to_lowercase();
    let class = if lower.contains("barrée") {
        EventClass::Closure
    } else if lower.contains("alternat") || lower.contains("file") || lower.contains("rétréci") {
        EventClass::LaneRestriction
    } else {
        return Err("no traffic impact");
    };
    let valid_from = text(p, "datedebut")
        .and_then(|d| paris_day(d, 0, 0, 0))
        .ok_or("no dates")?;
    let valid_to = text(p, "datefin").and_then(|d| paris_day(d, 23, 59, 59));
    Ok(Mapped {
        external_id,
        class,
        detail: traffic.chars().take(100).collect(),
        carriageway: Carriageway::Main,
        direction: EventDirection::Both,
        road_number: None,
        road_name: text(p, "voie").map(|s| s.chars().take(200).collect()),
        valid_from,
        valid_to,
        schedule: Schedule::default(),
        description: joined(&[text(p, "libelle"), text(p, "commentaire")]),
    })
}

/// The start of a day the source names (`2026-10-05`, or a date-time whose
/// date counts), midnight in Paris, and the end of another, the last second
/// of it in Paris: a source that gives days closes a road for the whole of
/// its last day.
fn days(start: &str, end: Option<&str>) -> Option<(DateTime<Utc>, Option<DateTime<Utc>>)> {
    Some((
        paris_day(start, 0, 0, 0)?,
        end.and_then(|e| paris_day(e, 23, 59, 59)),
    ))
}

/// The day in Paris of an instant (`2026-11-27T01:00:00+00:00`), as text:
/// a source that writes local midnights as UTC instants.
fn paris_date_of(text: &str) -> Option<String> {
    instant(text).map(|t| {
        t.with_timezone(&chrono_tz::Europe::Paris)
            .format("%Y-%m-%d")
            .to_string()
    })
}

/// A schedule from a period text, when it names day or night works only.
fn day_or_night(text: &str) -> Schedule {
    let lower = text.to_lowercase();
    if lower.contains("de jour") || lower.contains("de nuit") {
        Schedule::from_label(text)
    } else {
        Schedule::default()
    }
}

fn rennes_works(p: &serde_json::Map<String, Value>) -> Result<Mapped, &'static str> {
    // `id` looks like a row number of a view (`v_geotravaux_evenement_30j.6`)
    // and may be renumbered; `id_evt` is the measure's own.
    let external_id = id_of(p, "id_evt").ok_or("no id")?;
    let kind = text(p, "type").ok_or("no traffic impact")?;
    let lower = kind.to_lowercase();
    let class = if lower.contains("circulation interdite") || lower.starts_with("fermeture") {
        EventClass::Closure
    } else if ["rétrécissement", "alternée", "impasse", "neutralisation"]
        .iter()
        .any(|w| lower.contains(w))
    {
        EventClass::LaneRestriction
    } else {
        return Err("no traffic impact");
    };
    let (valid_from, valid_to) =
        days(text(p, "date_deb").ok_or("no dates")?, text(p, "date_fin")).ok_or("no dates")?;
    let said = joined(&[text(p, "libelle"), text(p, "commentaire")]).unwrap_or_default();
    Ok(Mapped {
        external_id,
        class,
        detail: kind.chars().take(100).collect(),
        carriageway: Carriageway::Main,
        // "Fermeture sens est-ouest": the direction is named by cardinal
        // points only, not by the line's order; both are closed.
        direction: EventDirection::Both,
        road_number: None,
        road_name: text(p, "localisation").map(|s| s.chars().take(200).collect()),
        valid_from,
        valid_to,
        schedule: day_or_night(&said),
        description: joined(&[
            text(p, "localisation"),
            text(p, "libelle"),
            text(p, "commentaire"),
        ]),
    })
}

fn aix_marseille_tunnel(p: &serde_json::Map<String, Value>) -> Result<Mapped, &'static str> {
    let tunnel = text(p, "tunnel").ok_or("no id")?;
    let sens = text(p, "sens").unwrap_or("");
    let start = text(p, "date_de_debut").ok_or("no dates")?;
    let valid_from = instant(start).ok_or("no dates")?;
    let valid_to = text(p, "date_de_fin").and_then(instant);
    if valid_to.is_some_and(|end| end < valid_from) {
        // 9 past records of 2026-10-06 end before they start.
        return Err("ends before it starts");
    }
    let kind = text(p, "type").unwrap_or("Fermeture");
    Ok(Mapped {
        // No id field: a tunnel, a direction and a start make one closure
        // (unique over the 325 records of 2026-10-06).
        external_id: digest(&[tunnel, sens, start]),
        class: EventClass::Closure,
        detail: format!("Fermeture {kind}").chars().take(100).collect(),
        carriageway: Carriageway::Main,
        // One line per tunnel and direction, drawn in its direction of
        // travel (each checked on the sample of 2026-10-06).
        direction: EventDirection::Forward,
        road_number: None,
        road_name: text(p, "nom").map(|s| s.chars().take(200).collect()),
        valid_from,
        valid_to,
        schedule: Schedule {
            unplanned: kind.starts_with("Inopin"),
            ..Schedule::default()
        },
        description: joined(&[text(p, "titrecalendrier"), text(p, "nature")]),
    })
}

/// Minutes after midnight of an hour as the Mayenne writes it (`7h`,
/// `19h`, `7h30`, `07h00`).
fn hour_minutes(text: &str) -> Option<u16> {
    let (h, m) = text.trim().to_lowercase().split_once('h').map(|(h, m)| {
        (
            h.trim().parse::<u16>().ok(),
            if m.trim().is_empty() {
                Some(0)
            } else {
                m.trim().parse::<u16>().ok()
            },
        )
    })?;
    let (h, m) = (h?, m?);
    (h < 24 && m < 60).then_some(h * 60 + m)
}

fn mayenne_closure(p: &serde_json::Map<String, Value>) -> Result<Mapped, &'static str> {
    let external_id = id_of(p, "objectid").ok_or("no id")?;
    let kind = text(p, "type").ok_or("no traffic impact")?;
    let class = match kind {
        "ROAD_CLOSED" => EventClass::Closure,
        "CONSTRUCTION" => EventClass::LaneRestriction,
        _ => return Err("no traffic impact"),
    };
    // The clock part of `starttime` and `endtime` means nothing (a closure
    // "from 08:15:03 to 08:15:07"): the dates count, the daily hours come
    // from `timestart` and `timeend`.
    let (valid_from, valid_to) =
        days(text(p, "starttime").ok_or("no dates")?, text(p, "endtime")).ok_or("no dates")?;
    let windows = match (
        text(p, "timestart").and_then(hour_minutes),
        text(p, "timeend").and_then(hour_minutes),
    ) {
        (Some(a), Some(b)) if a != b => {
            vec![lunaway_domain::road_events::schedule::Window::daily(a, b)]
        }
        _ => Vec::new(),
    };
    let hours = joined(&[text(p, "timestart"), text(p, "timeend")]);
    let street = text(p, "street");
    Ok(Mapped {
        external_id,
        class,
        detail: kind.to_owned(),
        carriageway: Carriageway::Main,
        // Which side a "ONE_DIRECTION" closure takes is in free text only.
        direction: EventDirection::Both,
        road_number: street.and_then(|s| road::numbers(s).into_iter().next()),
        road_name: street.map(|s| s.chars().take(200).collect()),
        valid_from,
        valid_to,
        schedule: Schedule {
            windows,
            label: hours,
            ..Schedule::default()
        },
        description: joined(&[
            text(p, "descriptio"),
            text(p, "locdesc"),
            text(p, "obs"),
            street,
        ]),
    })
}

fn cotes_d_armor_order(p: &serde_json::Map<String, Value>) -> Result<Mapped, &'static str> {
    // `NUMDOSSIER` repeats across orders; `_id` is the line's own.
    let external_id = id_of(p, "_id").ok_or("no id")?;
    let traffic = text(p, "CIRCULATION").ok_or("no traffic impact")?;
    let lower = traffic.to_lowercase();
    let class = if lower.contains("interdiction") || lower.contains("interdite") {
        EventClass::Closure
    } else if lower.contains("altern") {
        EventClass::LaneRestriction
    } else {
        return Err("no traffic impact");
    };
    let (valid_from, valid_to) =
        days(text(p, "DATEDEBUT").ok_or("no dates")?, text(p, "DATEFIN")).ok_or("no dates")?;
    let road = text(p, "ROUTE");
    Ok(Mapped {
        external_id,
        class,
        detail: traffic.chars().take(100).collect(),
        carriageway: Carriageway::Main,
        direction: EventDirection::Both,
        road_number: road.and_then(road::normalize),
        road_name: joined(&[road, text(p, "COMMUNE")]).map(|s| s.chars().take(200).collect()),
        valid_from,
        valid_to,
        // The hours are free text (93 phrasings in 300 lines): the order
        // counts whole days, its text says when.
        schedule: Schedule {
            label: text(p, "JOURSETHORAIRES1").map(|s| s.chars().take(200).collect()),
            ..Schedule::default()
        },
        description: joined(&[
            text(p, "TRAVAUX"),
            text(p, "COMMUNE"),
            text(p, "JOURSETHORAIRES1"),
        ]),
    })
}

fn sarthe_works(p: &serde_json::Map<String, Value>) -> Result<Mapped, &'static str> {
    let external_id = id_of(p, "objectid").ok_or("no id")?;
    let mode = text(p, "mode_exp").ok_or("no traffic impact")?;
    let lower = mode.to_lowercase();
    // "Déviation 2 sens": traffic sent round both ways, the road closed.
    let class = if lower.contains("barrée") || lower.starts_with("déviation") {
        EventClass::Closure
    } else if lower.contains("alternat") || lower.contains("neutralisation") {
        EventClass::LaneRestriction
    } else {
        return Err("no traffic impact");
    };
    // Local midnights written as UTC instants (02:00Z in summer).
    let start = text(p, "date_debut")
        .and_then(paris_date_of)
        .ok_or("no dates")?;
    let end = text(p, "date_fin").and_then(paris_date_of);
    let (valid_from, valid_to) = days(&start, end.as_deref()).ok_or("no dates")?;
    let place = text(p, "loc_txt");
    Ok(Mapped {
        external_id,
        class,
        detail: mode.chars().take(100).collect(),
        carriageway: Carriageway::Main,
        direction: EventDirection::Both,
        road_number: place
            .and_then(|l| l.split(':').next())
            .and_then(road::normalize),
        road_name: place.map(|s| s.chars().take(200).collect()),
        valid_from,
        valid_to,
        schedule: Schedule::default(),
        // `maitre_ouvrage` sometimes names a person: never shown.
        description: joined(&[text(p, "nature_trvx"), place, text(p, "commentaires")]),
    })
}

fn bordeaux_works(p: &serde_json::Map<String, Value>) -> Result<Mapped, &'static str> {
    let external_id = id_of(p, "ident").ok_or("no id")?;
    let label = text(p, "libelle").ok_or("no traffic impact")?;
    // One part per right of way ("/") and per order ("#"), measures within
    // it (";").
    let parts: Vec<String> = label
        .split(['/', '#'])
        .map(str::trim)
        .filter(|p| !p.is_empty())
        .map(str::to_lowercase)
        .collect();
    let closed = |s: &str| s.contains("circulation interdite");
    let restricted = |s: &str| {
        [
            "rétrécissement",
            "alternée",
            "neutralisation",
            "impasse",
            "interruption de circulation",
        ]
        .iter()
        .any(|w| s.contains(w))
    };
    // A closure of one right of way would close the whole works line: only
    // a line closed everywhere is a closure.
    let class = if parts.iter().all(|s| closed(s)) {
        EventClass::Closure
    } else if parts.iter().any(|s| closed(s) || restricted(s)) {
        EventClass::LaneRestriction
    } else {
        return Err("no traffic impact");
    };
    // Several orders give several dates, one per order, after '#'.
    let starts: Vec<&str> = text(p, "date_debut")
        .ok_or("no dates")?
        .split('#')
        .map(str::trim)
        .collect();
    let ends: Vec<&str> = text(p, "date_fin")
        .unwrap_or("")
        .split('#')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .collect();
    let valid_from = starts
        .iter()
        .filter_map(|d| paris_day(d, 0, 0, 0))
        .min()
        .ok_or("no dates")?;
    let valid_to = ends.iter().filter_map(|d| paris_day(d, 23, 59, 59)).max();
    Ok(Mapped {
        external_id,
        class,
        detail: label.chars().take(100).collect(),
        carriageway: Carriageway::Main,
        direction: EventDirection::Both,
        road_number: None,
        road_name: text(p, "localisation_emprise")
            .or_else(|| text(p, "localisation"))
            .map(|s| s.chars().take(200).collect()),
        valid_from,
        valid_to,
        schedule: Schedule::default(),
        description: joined(&[
            text(p, "localisation"),
            Some(label),
            text(p, "alias_nature_n1"),
        ]),
    })
}

/// A position, read lon-lat, or lat-lon when only that order falls in
/// France: some feeds write their pairs the other way round
/// (`plan/research/20-travaux-temps-reel.md`, 4.2).
fn france(a: f64, b: f64) -> Option<Position> {
    let lon_lat = Position::new(b, a).ok().filter(|p| is_covered(*p));
    lon_lat.or_else(|| Position::new(a, b).ok().filter(|p| is_covered(*p)))
}

fn line_of(c: &Value) -> Vec<Position> {
    c.as_array()
        .map(|a| {
            a.iter()
                .filter_map(|p| france(p.get(0)?.as_f64()?, p.get(1)?.as_f64()?))
                .collect()
        })
        .unwrap_or_default()
}

/// The geometry of a GeometryCollection: its lines when it has some (the
/// Côtes-d'Armor draws some orders as lines and points), its first part
/// otherwise.
fn collection_of(g: &Value) -> Option<SourceGeometry> {
    let parts: Vec<SourceGeometry> = g
        .get("geometries")?
        .as_array()?
        .iter()
        .take(64)
        .filter(|p| p.get("type").and_then(Value::as_str) != Some("GeometryCollection"))
        .filter_map(geometry_of)
        .collect();
    let lines: Vec<Vec<Position>> = parts
        .iter()
        .filter_map(|p| match p {
            SourceGeometry::Lines(l) => Some(l.clone()),
            _ => None,
        })
        .flatten()
        .collect();
    if lines.is_empty() {
        parts.into_iter().next()
    } else {
        Some(SourceGeometry::Lines(lines))
    }
}

/// The geometry of a GeoJSON feature: lines, or areas.
fn geometry_of(g: &Value) -> Option<SourceGeometry> {
    if g.get("type")?.as_str()? == "GeometryCollection" {
        return collection_of(g);
    }
    let c = g.get("coordinates")?;
    let (lines, areas): (Vec<Vec<Position>>, Vec<Vec<Position>>) = match g.get("type")?.as_str()? {
        "LineString" => (vec![line_of(c)], Vec::new()),
        "MultiLineString" => (c.as_array()?.iter().map(line_of).collect(), Vec::new()),
        "Polygon" => (Vec::new(), vec![line_of(c.get(0)?)]),
        "MultiPolygon" => (
            Vec::new(),
            c.as_array()?
                .iter()
                .filter_map(|p| p.get(0).map(line_of))
                .collect(),
        ),
        "Point" => {
            let p = france(c.get(0)?.as_f64()?, c.get(1)?.as_f64()?)?;
            return Some(SourceGeometry::Point(p));
        }
        // Bordeaux marks some rights of way with several points: the first
        // places the warning.
        "MultiPoint" => {
            let first = c.get(0)?;
            let p = france(first.get(0)?.as_f64()?, first.get(1)?.as_f64()?)?;
            return Some(SourceGeometry::Point(p));
        }
        _ => return None,
    };
    let lines: Vec<Vec<Position>> = lines.into_iter().filter(|l| l.len() >= 2).collect();
    let areas: Vec<Vec<Position>> = areas.into_iter().filter(|a| a.len() >= 3).collect();
    if !lines.is_empty() {
        Some(SourceGeometry::Lines(lines))
    } else if !areas.is_empty() {
        Some(SourceGeometry::Polygons(areas))
    } else {
        None
    }
}

fn event(
    source: &str,
    m: Mapped,
    geometry: SourceGeometry,
    raw: &Value,
    now: DateTime<Utc>,
) -> NewEvent {
    let match_quality = match &geometry {
        SourceGeometry::Lines(_) => MatchQuality::Pending,
        _ => MatchQuality::Unmatched,
    };
    let raw = raw.to_string();
    NewEvent {
        external_version: digest(&[source, &raw]),
        external_id: m.external_id,
        situation_id: None,
        class: m.class,
        detail: m.detail,
        carriageway: m.carriageway,
        direction: m.direction,
        road_number: m.road_number,
        road_name: m.road_name,
        limits: VehicleLimits::default(),
        valid_to: m.valid_to.filter(|t| *t >= m.valid_from),
        valid_from: m.valid_from,
        schedule: m.schedule,
        geometry,
        match_quality,
        confidence: Confidence::Official,
        description: m.description,
        detour: None,
        url: None,
        source_updated_at: None,
        ended: past_end(m.valid_to, now).then_some(EndReason::PastEnd),
        raw: cap_raw(raw),
    }
}

/// Reads a GeoJSON dataset of `format`.
///
/// # Errors
///
/// [`ParseError`] when the body is not a GeoJSON feature collection.
pub fn parse_geojson(
    source: &str,
    format: Format,
    body: &[u8],
    now: DateTime<Utc>,
) -> Result<Publication, ParseError> {
    let doc: Value = serde_json::from_slice(body)?;
    let features = doc
        .get("features")
        .and_then(Value::as_array)
        .ok_or(ParseError::Shape("a GeoJSON without features"))?;
    let map = match format {
        Format::ParisClosures => paris_closure,
        Format::ParisWorks => paris_works,
        Format::LyonWorks => lyon_works,
        Format::ToulouseWorks => toulouse_works,
        Format::RennesWorks => rennes_works,
        Format::AixMarseilleTunnels => aix_marseille_tunnel,
        Format::MayenneClosures => mayenne_closure,
        Format::CotesDArmorOrders => cotes_d_armor_order,
        Format::SartheWorks => sarthe_works,
        Format::BordeauxWorks => bordeaux_works,
        Format::CifsDataGouv => return Err(ParseError::Shape("a CIFS feed is not GeoJSON")),
    };
    let mut out = Publication {
        features: features.len(),
        ..Publication::default()
    };
    let mut seen = std::collections::HashSet::new();
    for f in features {
        let Some(props) = f.get("properties").and_then(Value::as_object) else {
            *out.skipped.entry("no properties".into()).or_default() += 1;
            continue;
        };
        let mapped = match map(props) {
            Ok(m) => m,
            Err(why) => {
                *out.skipped.entry(why.into()).or_default() += 1;
                continue;
            }
        };
        let Some(geometry) = f.get("geometry").and_then(geometry_of) else {
            *out.skipped
                .entry("no geometry in France".into())
                .or_default() += 1;
            continue;
        };
        if !seen.insert(mapped.external_id.clone()) {
            *out.skipped.entry("listed twice".into()).or_default() += 1;
            continue;
        }
        out.events.push(event(source, mapped, geometry, f, now));
    }
    Ok(out)
}

/// Reads a Waze CIFS JSON feed (`{"incidents": [{"incident": {...}}]}`):
/// its closed roads as closures, each drawn by its polyline of "lat lon"
/// pairs.
///
/// # Errors
///
/// [`ParseError`] when the body is not a CIFS JSON document.
pub fn parse_cifs(
    source: &str,
    body: &[u8],
    now: DateTime<Utc>,
) -> Result<Publication, ParseError> {
    let doc: Value = serde_json::from_slice(body)?;
    let incidents = doc
        .get("incidents")
        .and_then(Value::as_array)
        .ok_or(ParseError::Shape("a CIFS document without incidents"))?;
    let mut out = Publication {
        features: incidents.len(),
        ..Publication::default()
    };
    for item in incidents {
        let i = item.get("incident").unwrap_or(item);
        let Some(p) = i.as_object() else {
            *out.skipped.entry("not an object".into()).or_default() += 1;
            continue;
        };
        if text(p, "type") != Some("ROAD_CLOSED") {
            *out.skipped.entry("not a closure".into()).or_default() += 1;
            continue;
        }
        let Some(external_id) = id_of(p, "id") else {
            *out.skipped.entry("no id".into()).or_default() += 1;
            continue;
        };
        let Some(valid_from) = text(p, "starttime").and_then(instant) else {
            *out.skipped.entry("no dates".into()).or_default() += 1;
            continue;
        };
        let numbers: Vec<f64> = text(p, "polyline")
            .unwrap_or_default()
            .split_whitespace()
            .filter_map(|n| n.parse().ok())
            .collect();
        let line: Vec<Position> = numbers
            .as_chunks::<2>()
            .0
            .iter()
            .filter_map(|[lat, lon]| france(*lon, *lat))
            .collect();
        if line.len() < 2 {
            *out.skipped
                .entry("no geometry in France".into())
                .or_default() += 1;
            continue;
        }
        let street = text(p, "street");
        let mapped = Mapped {
            external_id,
            class: EventClass::Closure,
            detail: "ROAD_CLOSED".into(),
            carriageway: Carriageway::Main,
            direction: if text(p, "direction") == Some("ONE_DIRECTION") {
                EventDirection::Forward
            } else {
                EventDirection::Both
            },
            road_number: street.and_then(road::normalize),
            road_name: street.map(|s| s.chars().take(200).collect()),
            valid_from,
            valid_to: text(p, "endtime").and_then(instant),
            schedule: Schedule::default(),
            description: joined(&[text(p, "description"), street]),
        };
        out.events.push(event(
            source,
            mapped,
            SourceGeometry::Lines(vec![line]),
            item,
            now,
        ));
    }
    Ok(out)
}

/// The URL of the CIFS file a data.gouv.fr dataset description names: its
/// JSON resource.
///
/// # Errors
///
/// [`ParseError`] when the description lists no JSON resource.
pub fn cifs_resource(dataset: &[u8]) -> Result<String, ParseError> {
    let doc: Value = serde_json::from_slice(dataset)?;
    doc.get("resources")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .find(|r| {
            r.get("format")
                .and_then(Value::as_str)
                .is_some_and(|f| f.eq_ignore_ascii_case("json"))
        })
        .and_then(|r| r.get("url").and_then(Value::as_str))
        .map(str::to_owned)
        .ok_or(ParseError::Shape("the dataset lists no JSON resource"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_paris_period_reads_in_paris_time() {
        let (a, b) = paris_period("Du lundi 07/09/2026 22:00 au mardi 08/09/2026 06:00").unwrap();
        assert_eq!(a.to_rfc3339(), "2026-09-07T20:00:00+00:00");
        assert_eq!(b.to_rfc3339(), "2026-09-08T04:00:00+00:00");
        assert_eq!(paris_period("la nuit"), None);
    }

    #[test]
    fn pairs_written_the_other_way_round_are_turned() {
        let lyon = france(4.84, 45.87).unwrap();
        assert!((lyon.lat() - 45.87).abs() < 1e-9);
        let swapped = france(45.87, 4.84).unwrap();
        assert!((swapped.lat() - 45.87).abs() < 1e-9);
        assert!(france(13.4, 52.5).is_none(), "Berlin is not covered");
    }
}
