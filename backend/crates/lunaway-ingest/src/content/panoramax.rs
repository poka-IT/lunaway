//! Panoramax: street-level pictures that look at a place, found through
//! the federation's meta catalogue (`api.panoramax.xyz`, STAC search with
//! `place_position`, which returns pictures "either 360° or looking in
//! direction of wanted place").
//!
//! Only pictures served by the instances of [`INSTANCES`] are kept, each
//! under the licence its own metadata states (`properties.license`). A
//! flat picture is kept whole; of a 360-degree picture, only the part that
//! faces the place is kept (`lunaway_media::PanoramaView`).

use chrono::{DateTime, Utc};
use lunaway_domain::{Position, content};
use reqwest::Url;
use serde::Deserialize;
use serde_json::Value;

use crate::IngestError;

/// The search endpoint of the meta catalogue.
pub const SEARCH_URL: &str = "https://api.panoramax.xyz/api/search";

/// Hosts the search is asked on.
pub const API_HOSTS: &[&str] = &["api.panoramax.xyz"];

/// The instances whose pictures are kept, as (host, name shown): IGN's
/// (Licence Ouverte 2.0) and OpenStreetMap France's (CC BY-SA 4.0), whose
/// terms were read on 2026-10-07. A picture of another instance is left
/// out until its terms are read.
pub const INSTANCES: &[(&str, &str)] = &[
    (
        "panoramax.openstreetmap.fr",
        "Panoramax OpenStreetMap France",
    ),
    ("panoramax.ign.fr", "Panoramax IGN"),
];

/// Pictures asked per place: more than kept, so a picture of an unknown
/// instance or licence can be passed over.
const SEARCH_LIMIT: u32 = 20;

/// Half the angle around the direction of the place within which a flat
/// picture is taken as looking at it, degrees.
pub const FOV_TOLERANCE_DEG: f64 = 35.0;

/// The pictures within `max_distance_m` of a place that look at it, on the
/// search endpoint `search` ([`SEARCH_URL`]).
///
/// # Errors
///
/// [`IngestError::UntrustedUrl`] when `search` is not a URL.
pub fn search_url(
    search: &str,
    place: Position,
    max_distance_m: f64,
) -> Result<String, IngestError> {
    let position = format!("{:.6},{:.6}", place.lon(), place.lat());
    let distance = format!("3-{:.0}", max_distance_m.clamp(10.0, 100.0));
    let tolerance = format!("{FOV_TOLERANCE_DEG:.0}");
    let limit = SEARCH_LIMIT.to_string();
    Url::parse_with_params(
        search,
        [
            ("place_position", position.as_str()),
            ("place_distance", distance.as_str()),
            ("place_fov_tolerance", tolerance.as_str()),
            ("limit", limit.as_str()),
        ],
    )
    .map(String::from)
    .map_err(|_| IngestError::UntrustedUrl {
        url: search.to_owned(),
        reason: "not a URL",
    })
}

/// The pictures `ids` name (an OpenStreetMap `panoramax` tag), on the
/// search endpoint `search`.
///
/// # Errors
///
/// [`IngestError::UntrustedUrl`] when `search` is not a URL.
pub fn ids_url(search: &str, ids: &[String]) -> Result<String, IngestError> {
    Url::parse_with_params(search, [("ids", ids.join(",").as_str()), ("limit", "10")])
        .map(String::from)
        .map_err(|_| IngestError::UntrustedUrl {
            url: search.to_owned(),
            reason: "not a URL",
        })
}

#[derive(Debug, Deserialize)]
struct Collection {
    #[serde(default)]
    features: Vec<Feature>,
}

#[derive(Debug, Deserialize)]
struct Feature {
    id: String,
    #[serde(default)]
    collection: Option<String>,
    geometry: Geometry,
    #[serde(default)]
    properties: Value,
    #[serde(default)]
    assets: Value,
    #[serde(default)]
    links: Vec<Link>,
    #[serde(default)]
    providers: Vec<Provider>,
}

#[derive(Debug, Deserialize)]
struct Geometry {
    coordinates: Vec<f64>,
}

#[derive(Debug, Deserialize)]
struct Link {
    rel: String,
    href: String,
}

#[derive(Debug, Deserialize)]
struct Provider {
    name: String,
    #[serde(default)]
    roles: Vec<String>,
}

/// A picture that looks at a place.
#[derive(Debug, Clone, PartialEq)]
pub struct Picture {
    /// Its UUID.
    pub id: String,
    /// Its sequence.
    pub sequence: Option<String>,
    /// Where the camera stood.
    pub position: Position,
    /// The direction the centre of the picture faces, degrees from north.
    pub azimuth_deg: f64,
    /// Whether it is a 360-degree picture.
    pub panorama: bool,
    /// The file to download: the standard one of a flat picture, the full
    /// one of a panorama, of which only a part is kept.
    pub image_url: String,
    /// The instance it is served by.
    pub instance: &'static str,
    /// Its viewer page on that instance.
    pub page_url: String,
    /// Its producer, as the instance names them.
    pub author: Option<String>,
    /// Its licence.
    pub licence: content::Licence,
    /// When it was taken.
    pub taken_at: Option<DateTime<Utc>>,
}

/// Why a picture is left out.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum PictureSkip {
    /// Served by an instance not in [`INSTANCES`].
    Instance,
    /// No licence, or one [`content::accepted_licence`] refuses.
    Licence,
    /// No position or no direction.
    Geometry,
}

fn str_at<'a>(v: &'a Value, path: &[&str]) -> Option<&'a str> {
    let mut cur = v;
    for k in path {
        cur = cur.get(k)?;
    }
    cur.as_str()
}

fn host_of(url: &str) -> Option<String> {
    let u = Url::parse(url).ok()?;
    (u.scheme() == "https").then(|| u.host_str().map(str::to_ascii_lowercase))?
}

fn instance_of(host: &str) -> Option<&'static str> {
    INSTANCES.iter().find(|(h, _)| *h == host).map(|(_, n)| *n)
}

/// The pictures of a search answer, in its order, and the reasons for
/// those left out.
///
/// # Errors
///
/// [`IngestError::Json`] when the answer is not a STAC item collection.
pub fn parse(body: &[u8]) -> Result<(Vec<Picture>, Vec<PictureSkip>), IngestError> {
    let collection: Collection =
        serde_json::from_slice(body).map_err(|source| IngestError::Json {
            what: "panoramax search".into(),
            source,
        })?;
    let mut kept = Vec::new();
    let mut skipped = Vec::new();
    for f in collection.features {
        match picture_of(f) {
            Ok(p) => kept.push(p),
            Err(s) => skipped.push(s),
        }
    }
    Ok((kept, skipped))
}

fn picture_of(f: Feature) -> Result<Picture, PictureSkip> {
    let id = content::lowercase_uuid(&f.id).ok_or(PictureSkip::Geometry)?;
    let (Some(&lon), Some(&lat)) = (
        f.geometry.coordinates.first(),
        f.geometry.coordinates.get(1),
    ) else {
        return Err(PictureSkip::Geometry);
    };
    let position = Position::new(lat, lon).map_err(|_| PictureSkip::Geometry)?;
    let p = &f.properties;
    let azimuth_deg = p
        .get("view:azimuth")
        .and_then(Value::as_f64)
        .filter(|a| a.is_finite())
        .ok_or(PictureSkip::Geometry)?;
    let fov = p
        .get("pers:interior_orientation")
        .and_then(|o| o.get("field_of_view"))
        .and_then(Value::as_f64);
    let panorama = fov.is_some_and(|f| f >= 359.0);
    let asset = if panorama { "hd" } else { "sd" };
    let image_url = str_at(&f.assets, &[asset, "href"])
        .or_else(|| str_at(&f.assets, &["sd", "href"]))
        .ok_or(PictureSkip::Instance)?
        .to_owned();
    let host = host_of(&image_url).ok_or(PictureSkip::Instance)?;
    let instance = instance_of(&host).ok_or(PictureSkip::Instance)?;
    let via = f
        .links
        .iter()
        .find(|l| l.rel == "via")
        .and_then(|l| host_of(&l.href));
    if via.is_some_and(|v| v != host) {
        // The catalogue says another instance publishes it than the one
        // that serves the file: its licence would be the wrong one.
        return Err(PictureSkip::Instance);
    }
    let licence = match p.get("license") {
        Some(Value::String(s)) => content::accepted_licence(s),
        Some(Value::Array(a)) => a
            .iter()
            .filter_map(Value::as_str)
            .find_map(content::accepted_licence),
        _ => None,
    }
    .ok_or(PictureSkip::Licence)?;
    let author = f
        .providers
        .iter()
        .find(|pr| pr.roles.iter().any(|r| r == "producer"))
        .or_else(|| f.providers.first())
        .map(|pr| pr.name.as_str())
        .or_else(|| p.get("geovisio:producer").and_then(Value::as_str))
        .and_then(|a| content::plain_text(a, content::MAX_LABEL_CHARS));
    let taken_at = p
        .get("datetime")
        .and_then(Value::as_str)
        .and_then(|d| DateTime::parse_from_rfc3339(d).ok())
        .map(|d| d.with_timezone(&Utc));
    let sequence = f.collection.and_then(|c| content::lowercase_uuid(&c));
    Ok(Picture {
        page_url: format!("https://{host}/?focus=pic&pic={id}"),
        id,
        sequence,
        position,
        azimuth_deg,
        panorama,
        image_url,
        instance,
        author,
        licence,
        taken_at,
    })
}

/// The pictures kept for a place: those whose camera looks at it, flat
/// ones before panoramas, the nearest first, at most `max`, one per
/// sequence (the next picture of a sequence shows the same view a few
/// metres on).
#[must_use]
pub fn choose(mut pictures: Vec<Picture>, place: Position, max: usize) -> Vec<Picture> {
    pictures.retain(|p| {
        p.panorama || content::looks_at(p.position, p.azimuth_deg, FOV_TOLERANCE_DEG, place)
    });
    pictures.sort_by(|a, b| {
        a.panorama.cmp(&b.panorama).then(
            a.position
                .distance_m(place)
                .total_cmp(&b.position.distance_m(place)),
        )
    });
    let mut sequences = std::collections::BTreeSet::new();
    pictures
        .into_iter()
        .filter(|p| {
            p.sequence
                .as_ref()
                .is_none_or(|s| sequences.insert(s.clone()))
        })
        .take(max)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A picture at a fixed point near Rennes, facing east, of `fov`
    /// degrees, served by `host` under `licence`.
    fn feature(id: &str, seq: &str, fov: f64, host: &str, licence: &str) -> Value {
        let (lon, lat, azimuth) = (-1.678, 48.117, 90.0);
        serde_json::json!({
            "id": id, "collection": seq, "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [lon, lat]},
            "properties": {"datetime": "2024-05-01T10:00:00+00:00", "license": licence,
                "view:azimuth": azimuth, "pers:interior_orientation": {"field_of_view": fov}},
            "assets": {"hd": {"href": format!("https://{host}/images/{id}.jpg")},
                       "sd": {"href": format!("https://{host}/derivates/{id}/sd.jpg")}},
            "links": [{"rel": "via", "href": format!("https://{host}")}],
            "providers": [{"name": "PanierAvide", "roles": ["producer"]}]
        })
    }

    #[test]
    fn pictures_keep_their_instance_licence_and_producer() {
        let body = serde_json::json!({"type": "FeatureCollection", "features": [
            feature("d8dc9efb-d1b4-4a64-b948-f28bde76b202", "10234440-c379-4af1-8b1a-6bdc0457e23f",
                    360.0, "panoramax.openstreetmap.fr", "CC-BY-SA-4.0"),
            feature("11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222",
                    76.0, "panoramax.ign.fr", "etalab-2.0"),
            feature("33333333-3333-3333-3333-333333333333", "44444444-4444-4444-4444-444444444444",
                    76.0, "panoramax.example.org", "CC-BY-SA-4.0"),
            feature("55555555-5555-5555-5555-555555555555", "66666666-6666-6666-6666-666666666666",
                    76.0, "panoramax.ign.fr", "proprietary"),
        ]});
        let (kept, skipped) = parse(body.to_string().as_bytes()).unwrap();
        assert_eq!(kept.len(), 2);
        assert!(kept[0].panorama);
        assert!(
            kept[0].image_url.contains("/images/"),
            "a panorama is cut from the full picture"
        );
        assert_eq!(kept[0].licence.name, "CC BY-SA 4.0");
        assert_eq!(kept[0].instance, "Panoramax OpenStreetMap France");
        assert_eq!(kept[0].author.as_deref(), Some("PanierAvide"));
        assert!(kept[1].image_url.ends_with("/sd.jpg"));
        assert_eq!(kept[1].licence.name, "Licence Ouverte 2.0");
        assert_eq!(skipped, [PictureSkip::Instance, PictureSkip::Licence]);
    }

    #[test]
    fn flat_pictures_facing_the_place_come_first_one_per_sequence() {
        let place = Position::new(48.0, 2.0).unwrap();
        let west_of_it = Position::new(48.0, 1.9997).unwrap();
        let pic = |id: &str, seq: &str, azimuth: f64, panorama: bool| Picture {
            id: id.into(),
            sequence: Some(seq.into()),
            position: west_of_it,
            azimuth_deg: azimuth,
            panorama,
            image_url: String::new(),
            instance: "Panoramax IGN",
            page_url: String::new(),
            author: None,
            licence: content::accepted_licence("etalab-2.0").unwrap(),
            taken_at: None,
        };
        let chosen = choose(
            vec![
                pic("pano", "s1", 0.0, true),
                pic("away", "s2", 270.0, false),
                pic("facing", "s3", 85.0, false),
                pic("facing-again", "s3", 95.0, false),
            ],
            place,
            3,
        );
        let ids: Vec<&str> = chosen.iter().map(|p| p.id.as_str()).collect();
        assert_eq!(ids, ["facing", "pano"]);
    }
}
