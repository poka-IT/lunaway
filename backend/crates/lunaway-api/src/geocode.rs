//! The geocoders behind the map's search: postal addresses, streets, towns
//! and postcodes, asked by the server and never by the app
//! (`docs/data-sources.md`, "Addresses").
//!
//! France is answered by the Base Adresse Nationale through IGN's
//! Géoplateforme (`/search`, its autocompletion mode); the rest of the
//! covered countries by Lunaway's own Photon over OpenStreetMap, which
//! leaves France to the BAN. Both are reached through Caddy on the
//! backend's loopback (`infra/caddy/Caddyfile`, the geocoders' site), so
//! the API itself still connects to nothing outside the host.
//!
//! The text and the point a search ranks from are sent to the geocoders
//! and nowhere else: nothing here logs or keeps them, and the point is the
//! one the resolver already rounded to the coarse search grid.

use std::{
    sync::Mutex,
    time::{Duration, Instant},
};

use lunaway_domain::{
    Position,
    address::{AddressKind, AddressMatch, AddressSource},
};
use serde::Deserialize;
use tokio::sync::Semaphore;

use crate::config::GeocodeConfig;

/// Largest answer read from a geocoder: ten BAN matches weigh about 6 kB,
/// thirty Photon matches about 15 kB.
const MAX_ANSWER_BYTES: usize = 256 * 1024;
/// Fewest characters a geocoder is asked for: the BAN refuses fewer than
/// three ("q: must contain between 3 and 200 chars and start with a number
/// or a letter").
const MIN_TEXT_CHARS: usize = 3;
/// Longest text sent, in characters: the BAN's own maximum is 200, the
/// API's search text stops at 100.
const MAX_TEXT_CHARS: usize = 200;
/// Longest pause asked by a `Retry-After` the API honours: the
/// Géoplateforme announces 5 seconds.
const MAX_BACKOFF: Duration = Duration::from_secs(60);
/// The pause after a 429 without a readable `Retry-After`.
const DEFAULT_BACKOFF: Duration = Duration::from_secs(5);
/// Photon matches asked per match wanted: its French matches are dropped
/// when the BAN answers for France, and the rest must still fill the list.
const PHOTON_OVERSAMPLE: usize = 3;

/// What became of the geocoders' answers to one search.
#[derive(Debug, Default)]
pub(crate) struct Lookup {
    /// Every match, the BAN's first, in each geocoder's order.
    pub(crate) matches: Vec<AddressMatch>,
    /// False when a geocoder that should have answered did not (out of
    /// time, down, paused by its own limit): the list may lack addresses.
    pub(crate) complete: bool,
}

/// Why one geocoder gave nothing.
#[derive(Debug, thiserror::Error)]
enum GeocodeError {
    #[error("unreachable: {0}")]
    Unreachable(reqwest::Error),
    #[error("answered {0}")]
    Status(u16),
    #[error("answer too large")]
    TooLarge,
    #[error("answer not understood")]
    NotJson(#[source] serde_json::Error),
    #[error("out of time")]
    Timeout(#[source] tokio::time::error::Elapsed),
    #[error("paused by its rate limit")]
    Paused,
    #[error("no slot")]
    Closed(#[source] tokio::sync::AcquireError),
}

/// What one search asks every geocoder.
#[derive(Debug, Clone, Copy)]
pub(crate) struct Ask<'a> {
    /// The text, as typed.
    pub(crate) text: &'a str,
    /// The point the matches are ranked from, already on the coarse grid.
    pub(crate) near: Option<Position>,
    /// Most matches per geocoder.
    pub(crate) max: usize,
    /// The reader's language (`fr`, `en`...), for the names Photon gives.
    pub(crate) language: Option<&'a str>,
}

/// The languages of the names in the Photon databases (GraphHopper's
/// dumps: English, German, French, Italian, and the local names): another
/// language gets the local names.
const PHOTON_LANGUAGES: [&str; 4] = ["de", "en", "fr", "it"];

/// The pace of the requests to the Géoplateforme, all clients together:
/// it allows 50 requests a second per address and answers 429 for five
/// seconds beyond, so the API keeps under it and stops at the first 429
/// for as long as it is told.
#[derive(Debug)]
struct Pace {
    per_second: f64,
    tokens: f64,
    at: Instant,
    paused_until: Option<Instant>,
}

impl Pace {
    fn new(per_second: u32) -> Self {
        let per_second = f64::from(per_second.max(1));
        Self {
            per_second,
            tokens: per_second,
            at: Instant::now(),
            paused_until: None,
        }
    }

    fn take(&mut self, now: Instant) -> bool {
        if self.paused_until.is_some_and(|until| now < until) {
            return false;
        }
        let elapsed = now.saturating_duration_since(self.at).as_secs_f64();
        self.tokens = (self.tokens + elapsed * self.per_second).min(self.per_second);
        self.at = now;
        if self.tokens >= 1.0 {
            self.tokens -= 1.0;
            true
        } else {
            false
        }
    }

    fn pause(&mut self, now: Instant, wait: Duration) {
        self.paused_until = Some(now + wait.min(MAX_BACKOFF));
    }
}

/// The geocoders the API asks, or none when they are not configured.
#[derive(Debug)]
pub(crate) struct Geocoder {
    http: Option<reqwest::Client>,
    ban: Option<reqwest::Url>,
    photon: Vec<reqwest::Url>,
    timeout: Duration,
    pace: Mutex<Pace>,
    photon_slots: Semaphore,
}

impl Geocoder {
    /// The geocoders of `config`. Without an HTTP client (a TLS stack that
    /// cannot start), none is asked and the error is logged.
    pub(crate) fn new(config: &GeocodeConfig) -> Self {
        // reqwest is built without a bundled crypto provider (workspace
        // manifest); an error means one is installed already.
        static RING: std::sync::Once = std::sync::Once::new();
        RING.call_once(|| {
            let _ = rustls::crypto::ring::default_provider().install_default();
        });
        let http = reqwest::Client::builder()
            .user_agent(concat!(
                "Lunaway/",
                env!("CARGO_PKG_VERSION"),
                " (+https://lunaway.net)"
            ))
            // A proxy variable in the environment would send the text
            // elsewhere; a redirect could too.
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .connect_timeout(config.timeout)
            .timeout(config.timeout)
            .build()
            .inspect_err(|error| {
                tracing::error!(%error, "no HTTP client: addresses are not searched");
            })
            .ok();
        Self {
            http,
            ban: config.ban_url.as_deref().and_then(base_url),
            photon: config
                .photon_urls
                .iter()
                .filter_map(|u| base_url(u))
                .collect(),
            timeout: config.timeout,
            pace: Mutex::new(Pace::new(config.ban_per_second)),
            photon_slots: Semaphore::new(config.photon_at_once),
        }
    }

    /// Whether any geocoder is configured.
    pub(crate) fn enabled(&self) -> bool {
        self.http.is_some() && (self.ban.is_some() || !self.photon.is_empty())
    }

    /// Whether [`Self::lookup`] would ask a geocoder for `text`: one is
    /// configured and the text is long enough to send. A search that would
    /// not is never counted in the client's quota.
    pub(crate) fn would_ask(&self, text: &str) -> bool {
        self.enabled() && sendable(text).is_some()
    }

    /// The matches of `ask`, `ask.max` per geocoder at most. A text too
    /// short for a geocoder asks nothing and is complete.
    pub(crate) async fn lookup(&self, ask: Ask<'_>) -> Lookup {
        let Some(http) = &self.http else {
            return Lookup {
                matches: Vec::new(),
                complete: !self.enabled(),
            };
        };
        let Some(text) = sendable(ask.text) else {
            return Lookup {
                matches: Vec::new(),
                complete: true,
            };
        };
        let ask = Ask { text, ..ask };
        let ban = async {
            match &self.ban {
                Some(base) => Some(self.bounded(self.ask_ban(http, base, ask)).await),
                None => None,
            }
        };
        let photon = futures_util::future::join_all(
            self.photon
                .iter()
                .map(|base| self.bounded(self.ask_photon(http, base, ask))),
        );
        let (ban, photon) = tokio::join!(ban, photon);
        let mut lookup = Lookup {
            matches: Vec::new(),
            complete: true,
        };
        // France is the BAN's when it answered; while it is paused or down,
        // Photon's French matches stand in.
        let france_from_ban = matches!(ban, Some(Ok(_)));
        let photon = photon.into_iter().map(|answer| {
            answer.map(|mut found| {
                if france_from_ban {
                    found.retain(|m| m.country_code.as_deref() != Some("FR"));
                }
                found.truncate(ask.max);
                found
            })
        });
        let answers = std::iter::once(("ban", ban)).chain(photon.map(|a| ("photon", Some(a))));
        for (name, answer) in answers {
            match answer {
                None => {}
                Some(Ok(mut found)) => lookup.matches.append(&mut found),
                Some(Err(GeocodeError::Paused)) => {
                    lookup.complete = false;
                    // Said once, by the 429 that started the pause.
                    tracing::debug!(geocoder = name, "a geocoder is paused");
                }
                Some(Err(error)) => {
                    lookup.complete = false;
                    // Which geocoder and why, never what was searched: the
                    // transport's errors carry no URL.
                    tracing::warn!(geocoder = name, %error, "a geocoder gave no addresses");
                }
            }
        }
        lookup
    }

    /// `call` within the bound of one geocoder, its wait for a slot
    /// included: the places of the search wait for the slowest.
    async fn bounded<T>(
        &self,
        call: impl Future<Output = Result<T, GeocodeError>>,
    ) -> Result<T, GeocodeError> {
        tokio::time::timeout(self.timeout, call)
            .await
            .unwrap_or_else(|elapsed| Err(GeocodeError::Timeout(elapsed)))
    }

    async fn ask_ban(
        &self,
        http: &reqwest::Client,
        base: &reqwest::Url,
        ask: Ask<'_>,
    ) -> Result<Vec<AddressMatch>, GeocodeError> {
        if !self.pace_take() {
            return Err(GeocodeError::Paused);
        }
        let mut url = endpoint(base, "search");
        {
            let mut q = url.query_pairs_mut();
            q.append_pair("q", ask.text)
                .append_pair("limit", &ask.max.to_string())
                .append_pair("autocomplete", "1")
                .append_pair("index", "address");
            if let Some(p) = ask.near {
                q.append_pair("lat", &p.lat().to_string())
                    .append_pair("lon", &p.lon().to_string());
            }
        }
        let (status, bytes, retry_after) = self.get(http, url).await?;
        if status == 429 {
            let wait = retry_after.unwrap_or(DEFAULT_BACKOFF).min(MAX_BACKOFF);
            if let Ok(mut pace) = self.pace.lock() {
                pace.pause(Instant::now(), wait);
            }
            tracing::warn!(
                seconds = wait.as_secs(),
                "the Géoplateforme refused for its rate: the BAN is paused"
            );
            return Err(GeocodeError::Status(status));
        }
        if status != 200 {
            return Err(GeocodeError::Status(status));
        }
        parse_ban(&bytes, ask.text).map_err(GeocodeError::NotJson)
    }

    /// Photon's matches, with room for its French ones, which
    /// [`Self::lookup`] drops when the BAN answered.
    async fn ask_photon(
        &self,
        http: &reqwest::Client,
        base: &reqwest::Url,
        ask: Ask<'_>,
    ) -> Result<Vec<AddressMatch>, GeocodeError> {
        let _slot = self
            .photon_slots
            .acquire()
            .await
            .map_err(GeocodeError::Closed)?;
        let asked = if self.ban.is_some() {
            ask.max * PHOTON_OVERSAMPLE
        } else {
            ask.max
        };
        let mut url = endpoint(base, "api");
        {
            let mut q = url.query_pairs_mut();
            q.append_pair("q", ask.text)
                .append_pair("limit", &asked.to_string());
            for layer in PHOTON_LAYERS {
                q.append_pair("layer", layer);
            }
            if let Some(lang) = ask.language.filter(|l| PHOTON_LANGUAGES.contains(l)) {
                q.append_pair("lang", lang);
            }
            if let Some(p) = ask.near {
                q.append_pair("lat", &p.lat().to_string())
                    .append_pair("lon", &p.lon().to_string());
            }
        }
        let (status, bytes, _) = self.get(http, url).await?;
        if status != 200 {
            return Err(GeocodeError::Status(status));
        }
        parse_photon(&bytes).map_err(GeocodeError::NotJson)
    }

    fn pace_take(&self) -> bool {
        self.pace
            .lock()
            .is_ok_and(|mut pace| pace.take(Instant::now()))
    }

    /// `GET url`: the status, the body within [`MAX_ANSWER_BYTES`], and the
    /// `Retry-After` in seconds when there is one. Bounded by the caller.
    async fn get(
        &self,
        http: &reqwest::Client,
        url: reqwest::Url,
    ) -> Result<(u16, Vec<u8>, Option<Duration>), GeocodeError> {
        let call = async {
            let mut response = http
                .get(url)
                .send()
                .await
                .map_err(|e| GeocodeError::Unreachable(e.without_url()))?;
            let status = response.status().as_u16();
            let retry_after = response
                .headers()
                .get(reqwest::header::RETRY_AFTER)
                .and_then(|v| v.to_str().ok())
                .and_then(|v| v.trim().parse::<u64>().ok())
                .map(Duration::from_secs);
            if response
                .content_length()
                .is_some_and(|n| n > MAX_ANSWER_BYTES as u64)
            {
                return Err(GeocodeError::TooLarge);
            }
            let mut bytes = Vec::new();
            while let Some(chunk) = response
                .chunk()
                .await
                .map_err(|e| GeocodeError::Unreachable(e.without_url()))?
            {
                bytes.extend_from_slice(&chunk);
                if bytes.len() > MAX_ANSWER_BYTES {
                    return Err(GeocodeError::TooLarge);
                }
            }
            Ok((status, bytes, retry_after))
        };
        call.await
    }
}

/// A geocoder's base URL, checked by the configuration; one that does not
/// parse is left out, and said.
fn base_url(url: &str) -> Option<reqwest::Url> {
    reqwest::Url::parse(url)
        .inspect_err(|error| tracing::error!(%error, "a geocoder's URL does not parse; it is off"))
        .ok()
}

/// `base` with `name` added to its path.
fn endpoint(base: &reqwest::Url, name: &str) -> reqwest::Url {
    let mut url = base.clone();
    if let Ok(mut path) = url.path_segments_mut() {
        path.pop_if_empty().push(name);
    }
    url
}

/// The text as a geocoder takes it: from its first letter or digit, at
/// most [`MAX_TEXT_CHARS`]; none when fewer than [`MIN_TEXT_CHARS`]
/// remain.
fn sendable(text: &str) -> Option<&str> {
    let start = text.find(char::is_alphanumeric)?;
    let text = text[start..].trim_end();
    let end = text
        .char_indices()
        .nth(MAX_TEXT_CHARS)
        .map_or(text.len(), |(i, _)| i);
    let text = text[..end].trim_end();
    (text.chars().count() >= MIN_TEXT_CHARS).then_some(text)
}

/// The Photon layers asked: everything but `other`, which holds the points
/// of interest (the map's own search covers those).
const PHOTON_LAYERS: [&str; 8] = [
    "house", "street", "locality", "district", "city", "county", "state", "country",
];

#[derive(Deserialize)]
struct Collection<P> {
    features: Vec<Feature<P>>,
}

#[derive(Deserialize)]
struct Feature<P> {
    geometry: Point,
    properties: P,
}

#[derive(Deserialize)]
struct Point {
    coordinates: (f64, f64),
}

#[derive(Deserialize)]
struct BanProperties {
    #[serde(rename = "type")]
    kind: String,
    name: Option<String>,
    postcode: Option<String>,
    city: Option<String>,
    context: Option<String>,
    score: Option<f64>,
}

/// The matches of a BAN answer; a match of an unknown type or without a
/// valid position is skipped. A town found by its postcode (the text is
/// that postcode) is a postcode match.
fn parse_ban(bytes: &[u8], text: &str) -> Result<Vec<AddressMatch>, serde_json::Error> {
    let collection: Collection<BanProperties> = serde_json::from_slice(bytes)?;
    let postcode_text = text.len() == 5 && text.bytes().all(|b| b.is_ascii_digit());
    Ok(collection
        .features
        .into_iter()
        .filter_map(|f| {
            let (lon, lat) = f.geometry.coordinates;
            let position = Position::new(lat, lon).ok()?;
            let p = f.properties;
            let name = p.name.filter(|n| !n.trim().is_empty())?;
            let (kind, name, city) = match p.kind.as_str() {
                "housenumber" => (AddressKind::HouseNumber, name, p.city),
                "street" => (AddressKind::Street, name, p.city),
                "locality" => (AddressKind::Locality, name, p.city),
                "municipality" if postcode_text && p.postcode.as_deref() == Some(text) => {
                    (AddressKind::Postcode, text.to_owned(), Some(name))
                }
                "municipality" => (AddressKind::Town, name, None),
                _ => return None,
            };
            Some(AddressMatch {
                kind,
                name,
                postcode: p.postcode,
                city,
                context: p.context,
                country_code: Some("FR".to_owned()),
                position,
                source: AddressSource::Ban,
                score: p.score,
            })
        })
        .collect())
}

#[derive(Deserialize)]
struct PhotonProperties {
    #[serde(rename = "type")]
    kind: Option<String>,
    name: Option<String>,
    housenumber: Option<String>,
    street: Option<String>,
    postcode: Option<String>,
    city: Option<String>,
    district: Option<String>,
    county: Option<String>,
    state: Option<String>,
    country: Option<String>,
    countrycode: Option<String>,
}

/// The countries that write the house number before the street; the
/// others write it after ("Hauptstraße 5", "Calle Mayor 5").
const NUMBER_FIRST: [&str; 9] = ["FR", "MC", "LU", "BE", "GB", "IE", "MA", "CA", "US"];

/// The matches of a Photon answer; a house without a number (a point of
/// interest) or of an unknown type is skipped.
fn parse_photon(bytes: &[u8]) -> Result<Vec<AddressMatch>, serde_json::Error> {
    let collection: Collection<PhotonProperties> = serde_json::from_slice(bytes)?;
    Ok(collection
        .features
        .into_iter()
        .filter_map(|f| {
            let (lon, lat) = f.geometry.coordinates;
            let position = Position::new(lat, lon).ok()?;
            let p = f.properties;
            let country_code = p
                .countrycode
                .as_deref()
                .map(str::to_ascii_uppercase)
                .filter(|c| c.len() == 2);
            let (kind, name, city) = match p.kind.as_deref()? {
                "house" => {
                    let number = p.housenumber.as_deref()?;
                    let street = p.street.as_deref().or(p.name.as_deref())?;
                    let first = country_code
                        .as_deref()
                        .is_some_and(|c| NUMBER_FIRST.contains(&c));
                    let line = if first {
                        format!("{number} {street}")
                    } else {
                        format!("{street} {number}")
                    };
                    (AddressKind::HouseNumber, line, p.city.or(p.district))
                }
                "street" => (AddressKind::Street, p.name?, p.city.or(p.district)),
                "locality" | "district" => (AddressKind::Locality, p.name?, p.city),
                "city" => (AddressKind::Town, p.name?, None),
                "county" | "state" | "country" => (AddressKind::Region, p.name?, None),
                _ => return None,
            };
            let context = [
                p.county.as_deref(),
                p.state.as_deref(),
                p.country.as_deref(),
            ]
            .into_iter()
            .flatten()
            .filter(|c| *c != name)
            .collect::<Vec<_>>()
            .join(", ");
            Some(AddressMatch {
                kind,
                name,
                postcode: p.postcode,
                city,
                context: (!context.is_empty()).then_some(context),
                country_code,
                position,
                source: AddressSource::Osm,
                score: None,
            })
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(name: &str) -> Vec<u8> {
        let path = format!(
            "{}/tests/fixtures/geocode/{name}",
            env!("CARGO_MANIFEST_DIR")
        );
        std::fs::read(&path).unwrap_or_else(|e| panic!("{path}: {e}"))
    }

    #[test]
    fn a_ban_house_number_is_a_house_number_in_its_town() {
        let found = parse_ban(
            &fixture("ban_housenumber.json"),
            "20 avenue de segur 75007 paris",
        )
        .unwrap();
        let first = &found[0];
        assert_eq!(first.kind, AddressKind::HouseNumber);
        assert_eq!(first.name, "20 Avenue de Ségur");
        assert_eq!(first.city.as_deref(), Some("Paris"));
        assert_eq!(first.postcode.as_deref(), Some("75007"));
        assert_eq!(first.source, AddressSource::Ban);
        assert!(
            (first.position.lat() - 48.850_699).abs() < 1e-6,
            "GeoJSON is lon, lat"
        );
    }

    #[test]
    fn a_ban_town_is_a_town_and_its_streets_are_streets() {
        let found = parse_ban(&fixture("ban_town.json"), "annecy").unwrap();
        let kinds: Vec<AddressKind> = found.iter().map(|m| m.kind).collect();
        assert_eq!(
            kinds,
            [AddressKind::Town, AddressKind::Street, AddressKind::Street]
        );
        assert_eq!(found[0].city, None, "a town is not inside a town");
        assert_eq!(
            found[0].context.as_deref(),
            Some("74, Haute-Savoie, Auvergne-Rhône-Alpes")
        );
    }

    #[test]
    fn a_town_found_by_its_postcode_is_a_postcode() {
        let found = parse_ban(&fixture("ban_postcode.json"), "29200").unwrap();
        assert_eq!(found[0].kind, AddressKind::Postcode);
        assert_eq!(found[0].name, "29200");
        assert_eq!(found[0].city.as_deref(), Some("Brest"));
        assert_eq!(found[1].kind, AddressKind::Street);
    }

    #[test]
    fn photon_matches_get_their_kind_and_the_local_order_of_the_number() {
        let found = parse_photon(&fixture("photon_mixed.json")).unwrap();
        let lines: Vec<(AddressKind, &str)> =
            found.iter().map(|m| (m.kind, m.name.as_str())).collect();
        assert_eq!(
            lines,
            [
                (AddressKind::HouseNumber, "Calle Mayor 5"),
                (AddressKind::HouseNumber, "12 Rue Neuve"),
                (AddressKind::Street, "Hauptstraße"),
                (AddressKind::Town, "Chefchaouen"),
                (AddressKind::Region, "Bayern"),
            ],
            "the shop without a number is left out"
        );
        assert_eq!(found[0].country_code.as_deref(), Some("ES"));
        assert_eq!(found[0].city.as_deref(), Some("Madrid"));
        assert_eq!(
            found[3].context.as_deref(),
            Some("Chefchaouen Province, Morocco")
        );
    }

    #[test]
    fn the_text_sent_starts_at_a_letter_or_a_digit() {
        assert_eq!(sendable("-- vaux"), Some("vaux"));
        assert_eq!(sendable("  ab "), None);
        assert_eq!(sendable("«»"), None);
        assert_eq!(
            sendable(&"é".repeat(300)).map(|t| t.chars().count()),
            Some(200)
        );
    }

    #[test]
    fn the_pace_stops_at_its_rate_and_after_a_429() {
        let mut pace = Pace::new(2);
        let t = Instant::now();
        assert!(pace.take(t));
        assert!(pace.take(t));
        assert!(!pace.take(t), "two a second");
        assert!(
            pace.take(t + Duration::from_millis(500)),
            "one more after half a second"
        );
        pace.pause(t + Duration::from_secs(1), Duration::from_secs(5));
        assert!(
            !pace.take(t + Duration::from_secs(5)),
            "paused as the 429 asked"
        );
        assert!(pace.take(t + Duration::from_secs(7)));
        pace.pause(t, Duration::from_secs(3_600));
        assert!(
            pace.take(t + MAX_BACKOFF + Duration::from_secs(1)),
            "a pause never outlasts a minute"
        );
    }
}
