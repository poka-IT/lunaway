//! Wikimedia Commons: the files a place's data names, and the files taken
//! near it, through the MediaWiki action API of `commons.wikimedia.org`.
//!
//! One request per place finds the geotagged files around it with their
//! licence and author (`generator=geosearch` with `prop=imageinfo`); one
//! more reads the files its OpenStreetMap tags or its Wikidata item name.
//! Each file's licence is read from its own metadata
//! (`extmetadata.LicenseShortName`) and refused unless
//! [`content::accepted_licence`] knows it. The image is the 1280-pixel
//! thumbnail, a standard width: Wikimedia's servers refuse the others
//! (`plan/research/46-contenus-ouverts.md`).

use std::collections::BTreeMap;

use chrono::{DateTime, NaiveDate, Utc};
use lunaway_domain::{Position, content};
use reqwest::Url;
use serde::Deserialize;
use serde_json::Value;

use crate::IngestError;

/// The action API.
pub const API_URL: &str = "https://commons.wikimedia.org/w/api.php";

/// Hosts the API is asked on.
pub const API_HOSTS: &[&str] = &["commons.wikimedia.org"];

/// Hosts the image files come from: the thumbnails moved to
/// `thumb.wikimedia.org` in 2026, originals stay on `upload.wikimedia.org`.
pub const MEDIA_HOSTS: &[&str] = &["thumb.wikimedia.org", "upload.wikimedia.org"];

/// Width of the thumbnail asked for: one of the standard sizes
/// (https://www.mediawiki.org/wiki/Common_thumbnail_sizes, read
/// 2026-10-07); a file narrower than that comes as its original.
pub const THUMB_WIDTH: u32 = 1280;

/// Shortest long side kept, pixels: smaller files look blurred on a card.
pub const MIN_LONG_SIDE: u32 = 640;

/// The metadata fields read of each file.
const METADATA: &str =
    "LicenseShortName|LicenseUrl|Artist|DateTimeOriginal|ObjectName|AttributionRequired";

/// Seconds of replication lag past which the API asks a bot to wait
/// (https://www.mediawiki.org/wiki/API:Etiquette).
const MAXLAG: &str = "5";

/// The query URL of the API at `api` with `pairs`.
///
/// # Errors
///
/// [`IngestError::UntrustedUrl`] when `api` is not a URL.
fn api_url(api: &str, pairs: &[(&str, &str)]) -> Result<String, IngestError> {
    let common = [
        ("action", "query"),
        ("format", "json"),
        ("formatversion", "2"),
        ("maxlag", MAXLAG),
    ];
    Url::parse_with_params(api, common.iter().chain(pairs))
        .map(String::from)
        .map_err(|_| IngestError::UntrustedUrl {
            url: api.to_owned(),
            reason: "not a URL",
        })
}

/// The files within `radius_m` of a point, at most `limit`, with what
/// [`file_of`] reads, on the API at `api` ([`API_URL`]).
///
/// # Errors
///
/// [`IngestError::UntrustedUrl`] when `api` is not a URL.
pub fn geosearch_url(
    api: &str,
    at: Position,
    radius_m: f64,
    limit: u32,
) -> Result<String, IngestError> {
    let coord = format!("{:.6}|{:.6}", at.lat(), at.lon());
    // The API takes 10 to 10 000 m.
    let radius = format!("{:.0}", radius_m.clamp(10.0, 10_000.0));
    let limit = limit.clamp(1, 50).to_string();
    let width = THUMB_WIDTH.to_string();
    api_url(
        api,
        &[
            ("generator", "geosearch"),
            ("ggscoord", &coord),
            ("ggsradius", &radius),
            ("ggslimit", &limit),
            ("ggsnamespace", "6"),
            ("prop", "imageinfo|coordinates"),
            ("iiprop", "url|size|mime|sha1|extmetadata"),
            ("iiurlwidth", &width),
            ("iiextmetadatafilter", METADATA),
            ("coprimary", "all"),
        ],
    )
}

/// The files named `titles` (`File:...`, 50 at most).
///
/// # Errors
///
/// [`IngestError::UntrustedUrl`] when `api` is not a URL.
pub fn files_url(api: &str, titles: &[String]) -> Result<String, IngestError> {
    let joined = titles
        .iter()
        .take(50)
        .map(String::as_str)
        .collect::<Vec<_>>()
        .join("|");
    let width = THUMB_WIDTH.to_string();
    api_url(
        api,
        &[
            ("titles", &joined),
            ("prop", "imageinfo|coordinates"),
            ("iiprop", "url|size|mime|sha1|extmetadata"),
            ("iiurlwidth", &width),
            ("iiextmetadatafilter", METADATA),
            ("coprimary", "all"),
            ("redirects", "1"),
        ],
    )
}

/// The first files of a category (`Category:...`), which an OpenStreetMap
/// `wikimedia_commons` value may name instead of a file.
///
/// # Errors
///
/// [`IngestError::UntrustedUrl`] when `api` is not a URL.
pub fn category_url(api: &str, category: &str, limit: u32) -> Result<String, IngestError> {
    let limit = limit.clamp(1, 20).to_string();
    let width = THUMB_WIDTH.to_string();
    api_url(
        api,
        &[
            ("generator", "categorymembers"),
            ("gcmtitle", category),
            ("gcmtype", "file"),
            ("gcmlimit", &limit),
            ("prop", "imageinfo|coordinates"),
            ("iiprop", "url|size|mime|sha1|extmetadata"),
            ("iiurlwidth", &width),
            ("iiextmetadatafilter", METADATA),
            ("coprimary", "all"),
        ],
    )
}

/// The category an OpenStreetMap `wikimedia_commons` value names.
#[must_use]
pub fn category_title(value: &str) -> Option<String> {
    let v = value.split(';').next()?.trim();
    let name = v
        .strip_prefix("Category:")
        .or_else(|| v.strip_prefix("category:"))?
        .replace('_', " ");
    let name = name.trim();
    (!name.is_empty() && !name.contains(['|', '#', '<', '>', '[', ']', '{', '}', '\n']))
        .then(|| format!("Category:{name}"))
}

#[derive(Debug, Deserialize)]
struct Answer {
    #[serde(default)]
    error: Option<ApiError>,
    #[serde(default)]
    query: Option<Query>,
}

#[derive(Debug, Deserialize)]
struct ApiError {
    #[serde(default)]
    code: String,
    #[serde(default)]
    info: String,
}

#[derive(Debug, Deserialize)]
struct Query {
    #[serde(default)]
    pages: Vec<Page>,
}

#[derive(Debug, Deserialize)]
struct Page {
    title: String,
    #[serde(default)]
    missing: bool,
    #[serde(default)]
    imageinfo: Vec<ImageInfo>,
    #[serde(default)]
    coordinates: Vec<Coordinate>,
}

#[derive(Debug, Deserialize)]
struct ImageInfo {
    #[serde(default)]
    url: Option<String>,
    #[serde(default)]
    thumburl: Option<String>,
    #[serde(default)]
    descriptionurl: Option<String>,
    #[serde(default)]
    width: u32,
    #[serde(default)]
    height: u32,
    #[serde(default)]
    mime: String,
    #[serde(default)]
    sha1: String,
    #[serde(default)]
    extmetadata: BTreeMap<String, MetaValue>,
}

#[derive(Debug, Deserialize)]
struct MetaValue {
    value: Value,
}

#[derive(Debug, Deserialize)]
struct Coordinate {
    lat: f64,
    lon: f64,
    #[serde(default)]
    primary: bool,
    #[serde(default)]
    r#type: Option<String>,
}

/// A file of Commons as a candidate photo.
#[derive(Debug, Clone, PartialEq)]
pub struct CommonsFile {
    /// `File:<name>`.
    pub title: String,
    /// Its page on Commons.
    pub page_url: String,
    /// The image to download: the thumbnail, or the original when it is
    /// no wider.
    pub image_url: String,
    /// The SHA-1 of the file: a new upload of it changes it.
    pub sha1: String,
    /// Its licence.
    pub licence: content::Licence,
    /// Its author, as plain text.
    pub author: Option<String>,
    /// Its title, as plain text.
    pub object_name: Option<String>,
    /// When it was taken.
    pub taken_at: Option<DateTime<Utc>>,
    /// Where the camera stood, or the object when that is all it says.
    pub position: Option<Position>,
}

/// Why a file is left out.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum FileSkip {
    /// The file does not exist.
    Missing,
    /// Its licence is not one [`content::accepted_licence`] accepts.
    Licence,
    /// Not a JPEG, PNG or WebP picture (a drawing, a PDF, a video).
    Format,
    /// Smaller than [`MIN_LONG_SIDE`].
    Small,
    /// No URL on a media host, or no page.
    Url,
}

/// The files of an answer, in its order, and the reasons for those left
/// out.
///
/// # Errors
///
/// [`IngestError::Json`] when the answer is not the API's JSON, and
/// [`IngestError::Status`] (503, retried) when the API asks to wait: for
/// its replicas (`maxlag`), or because its search is busy
/// (`cirrussearch-too-busy-error`) or the client goes too fast
/// (`ratelimited`).
pub fn parse(body: &[u8]) -> Result<(Vec<CommonsFile>, Vec<FileSkip>), IngestError> {
    let answer: Answer = serde_json::from_slice(body).map_err(|source| IngestError::Json {
        what: "commons answer".into(),
        source,
    })?;
    if let Some(e) = answer.error {
        let wait = match e.code.as_str() {
            "maxlag" => Some(5),
            "cirrussearch-too-busy-error" | "ratelimited" => Some(60),
            _ => None,
        };
        if let Some(seconds) = wait {
            return Err(IngestError::Status {
                url: API_URL.to_owned(),
                status: reqwest::StatusCode::SERVICE_UNAVAILABLE,
                body: e.info,
                retry_after: Some(std::time::Duration::from_secs(seconds)),
            });
        }
        return Err(IngestError::Implausible {
            what: format!("commons answered {}: {}", e.code, e.info),
        });
    }
    let mut files = Vec::new();
    let mut skipped = Vec::new();
    for page in answer.query.map(|q| q.pages).unwrap_or_default() {
        match file_of(page) {
            Ok(f) => files.push(f),
            Err(s) => skipped.push(s),
        }
    }
    Ok((files, skipped))
}

fn meta_text(info: &ImageInfo, key: &str) -> Option<String> {
    match &info.extmetadata.get(key)?.value {
        Value::String(s) => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        _ => None,
    }
}

/// `DateTimeOriginal` as Commons writes it: `2020-10-30`, `2020-10-30
/// 14:02:11`, or free text (`circa 1950`), which reads as nothing.
fn taken_at(raw: &str) -> Option<DateTime<Utc>> {
    let text = content::plain_text(raw, 40)?;
    let date = text.get(..10)?;
    let day = NaiveDate::parse_from_str(date, "%Y-%m-%d")
        .or_else(|_| NaiveDate::parse_from_str(date, "%Y:%m:%d"))
        .ok()?;
    Some(day.and_hms_opt(12, 0, 0)?.and_utc())
}

fn on_media_host(url: &str) -> bool {
    Url::parse(url).ok().is_some_and(|u| {
        u.scheme() == "https"
            && u.host_str()
                .is_some_and(|h| MEDIA_HOSTS.iter().any(|m| m.eq_ignore_ascii_case(h)))
    })
}

fn file_of(page: Page) -> Result<CommonsFile, FileSkip> {
    if page.missing {
        return Err(FileSkip::Missing);
    }
    let info = page.imageinfo.into_iter().next().ok_or(FileSkip::Missing)?;
    if !matches!(
        info.mime.as_str(),
        "image/jpeg" | "image/png" | "image/webp"
    ) {
        return Err(FileSkip::Format);
    }
    if info.width.max(info.height) < MIN_LONG_SIDE {
        return Err(FileSkip::Small);
    }
    let licence = meta_text(&info, "LicenseShortName")
        .and_then(|l| content::accepted_licence(&l))
        .ok_or(FileSkip::Licence)?;
    let image_url = info
        .thumburl
        .clone()
        .or_else(|| info.url.clone())
        .filter(|u| on_media_host(u))
        .ok_or(FileSkip::Url)?;
    let page_url = info
        .descriptionurl
        .clone()
        .filter(|u| u.starts_with("https://commons.wikimedia.org/"))
        .ok_or(FileSkip::Url)?;
    let author =
        meta_text(&info, "Artist").and_then(|a| content::plain_text(&a, content::MAX_LABEL_CHARS));
    let object_name = meta_text(&info, "ObjectName")
        .and_then(|a| content::plain_text(&a, content::MAX_LABEL_CHARS));
    let taken_at = meta_text(&info, "DateTimeOriginal").and_then(|d| taken_at(&d));
    // The camera's position when the file has one, else the object's.
    let camera = page
        .coordinates
        .iter()
        .find(|c| c.r#type.as_deref() == Some("camera"))
        .or_else(|| page.coordinates.iter().find(|c| c.primary))
        .or_else(|| page.coordinates.first());
    let position = camera.and_then(|c| Position::new(c.lat, c.lon).ok());
    let sha1 = if info.sha1.is_empty() {
        image_url.clone()
    } else {
        info.sha1.clone()
    };
    Ok(CommonsFile {
        title: page.title,
        page_url,
        image_url,
        sha1,
        licence,
        author,
        object_name,
        taken_at,
        position,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const ANSWER: &str = r#"{"batchcomplete":true,"query":{"pages":[
      {"pageid":1,"ns":6,"title":"File:Aire de Treignac.jpg",
       "coordinates":[{"lat":45.5358,"lon":1.7951,"primary":true,"type":"camera","globe":"earth"}],
       "imagetype":"bitmap",
       "imageinfo":[{"size":3000000,"width":4000,"height":3000,
         "thumburl":"https://thumb.wikimedia.org/wikipedia/commons/thumb/a/ab/Aire_de_Treignac.jpg/1280px-Aire_de_Treignac.jpg?utm_source=x",
         "thumbwidth":1280,"thumbheight":960,
         "url":"https://upload.wikimedia.org/wikipedia/commons/a/ab/Aire_de_Treignac.jpg",
         "descriptionurl":"https://commons.wikimedia.org/wiki/File:Aire_de_Treignac.jpg",
         "sha1":"0123456789abcdef0123456789abcdef01234567","mime":"image/jpeg",
         "extmetadata":{
           "LicenseShortName":{"value":"CC BY-SA 4.0","source":"commons-desc-page"},
           "Artist":{"value":"<a href=\"//commons.wikimedia.org/wiki/User:Pierre\">Pierre</a>"},
           "DateTimeOriginal":{"value":"2021-07-14 10:02:11"},
           "ObjectName":{"value":"Aire de Treignac"}}}]},
      {"pageid":2,"ns":6,"title":"File:Logo.svg","imageinfo":[{"width":800,"height":800,
         "mime":"image/svg+xml","url":"https://upload.wikimedia.org/x.svg",
         "descriptionurl":"https://commons.wikimedia.org/wiki/File:Logo.svg",
         "extmetadata":{"LicenseShortName":{"value":"CC0"}}}]},
      {"pageid":3,"ns":6,"title":"File:NC.jpg","imageinfo":[{"width":4000,"height":3000,
         "mime":"image/jpeg","url":"https://upload.wikimedia.org/nc.jpg",
         "descriptionurl":"https://commons.wikimedia.org/wiki/File:NC.jpg",
         "extmetadata":{"LicenseShortName":{"value":"CC BY-NC 2.0"}}}]},
      {"ns":6,"title":"File:Gone.jpg","missing":true},
      {"pageid":4,"ns":6,"title":"File:Elsewhere.jpg","imageinfo":[{"width":4000,"height":3000,
         "mime":"image/jpeg","url":"https://evil.example/x.jpg",
         "descriptionurl":"https://commons.wikimedia.org/wiki/File:Elsewhere.jpg",
         "extmetadata":{"LicenseShortName":{"value":"CC0"}}}]}
    ]}}"#;

    #[test]
    fn files_keep_their_licence_author_and_camera() {
        let (files, skipped) = parse(ANSWER.as_bytes()).unwrap();
        assert_eq!(files.len(), 1);
        let f = &files[0];
        assert_eq!(f.title, "File:Aire de Treignac.jpg");
        assert_eq!(f.licence.name, "CC BY-SA 4.0");
        assert_eq!(f.author.as_deref(), Some("Pierre"));
        assert!(f.image_url.starts_with("https://thumb.wikimedia.org/"));
        assert_eq!(
            f.taken_at.map(|t| t.date_naive().to_string()).as_deref(),
            Some("2021-07-14")
        );
        assert!(f.position.is_some());
        assert_eq!(
            skipped,
            [
                FileSkip::Format,
                FileSkip::Licence,
                FileSkip::Missing,
                FileSkip::Url
            ],
            "a drawing, a non-commercial licence, a missing file and a foreign host are refused"
        );
    }

    #[test]
    fn maxlag_and_a_busy_search_are_a_wait_not_a_failure() {
        let body =
            br#"{"error":{"code":"maxlag","info":"Waiting for a replica: 6 seconds lagged."}}"#;
        let e = parse(body).unwrap_err();
        assert!(e.is_transient(), "{e}");
        let busy = br#"{"error":{"code":"cirrussearch-too-busy-error","info":"Search is currently too busy."}}"#;
        assert!(parse(busy).unwrap_err().is_transient());
        let other = br#"{"error":{"code":"badvalue","info":"x"}}"#;
        assert!(!parse(other).unwrap_err().is_transient());
    }

    #[test]
    fn urls_ask_a_standard_width_and_bounded_values() {
        let at = Position::new(45.5, 1.79).unwrap();
        let url = geosearch_url(API_URL, at, 50_000.0, 500).unwrap();
        assert!(url.contains("ggsradius=10000"), "{url}");
        assert!(url.contains("ggslimit=50"), "{url}");
        assert!(url.contains("iiurlwidth=1280"), "{url}");
        assert!(url.contains("maxlag=5"), "{url}");
        assert_eq!(
            category_title("Category:Campsites_in_Brittany").as_deref(),
            Some("Category:Campsites in Brittany")
        );
        assert_eq!(category_title("File:X.jpg"), None);
    }
}
