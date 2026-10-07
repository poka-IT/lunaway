//! Wikidata and Wikipedia: which article and which image a place's
//! Wikidata item names (CC0), and the introduction of each article
//! (CC BY-SA 4.0), read through the MediaWiki action API.
//!
//! Wikidata is read 50 items a request (`wbgetentities`), Wikipedia 20
//! titles a request per language (`prop=extracts`, the introduction as
//! plain text). An introduction longer than
//! [`content::MAX_DESCRIPTION_CHARS`] is cut and ends with an ellipsis,
//! which is how the card shows that it was shortened, as CC BY-SA asks.

use std::collections::BTreeMap;

use lunaway_domain::content;
use reqwest::Url;
use serde::Deserialize;

use crate::IngestError;

/// The Wikidata action API.
pub const WIKIDATA_API_URL: &str = "https://www.wikidata.org/w/api.php";

/// Hosts the Wikidata API is asked on.
pub const WIKIDATA_HOSTS: &[&str] = &["www.wikidata.org"];

/// Items per `wbgetentities` request, the API's maximum.
pub const ITEMS_PER_REQUEST: usize = 50;

/// Titles per extracts request, the API's maximum (`exlimit`).
pub const TITLES_PER_REQUEST: usize = 20;

/// The image property (P18) of a Wikidata item.
const IMAGE: &str = "P18";

/// The items `ids` (`Q42`, 50 at most), with their image and their
/// articles, on the API at `api` ([`WIKIDATA_API_URL`]). Without `maxlag`:
/// Wikidata counts the lag of its query service in it, which a read of
/// items does not wait for, and which kept every request waiting for
/// minutes on 2026-10-07.
///
/// # Errors
///
/// [`IngestError::UntrustedUrl`] when `api` is not a URL.
pub fn entities_url(api: &str, ids: &[String]) -> Result<String, IngestError> {
    let joined = ids
        .iter()
        .take(ITEMS_PER_REQUEST)
        .map(String::as_str)
        .collect::<Vec<_>>()
        .join("|");
    Url::parse_with_params(
        api,
        [
            ("action", "wbgetentities"),
            ("format", "json"),
            ("props", "claims|sitelinks"),
            ("ids", joined.as_str()),
        ],
    )
    .map(String::from)
    .map_err(|_| IngestError::UntrustedUrl {
        url: api.to_owned(),
        reason: "not a URL",
    })
}

#[derive(Debug, Deserialize)]
struct Entities {
    #[serde(default)]
    entities: BTreeMap<String, Entity>,
    #[serde(default)]
    error: Option<ApiError>,
}

#[derive(Debug, Deserialize)]
struct ApiError {
    #[serde(default)]
    code: String,
    #[serde(default)]
    info: String,
}

#[derive(Debug, Deserialize)]
struct Entity {
    #[serde(default)]
    claims: BTreeMap<String, Vec<Claim>>,
    #[serde(default)]
    sitelinks: BTreeMap<String, Sitelink>,
    #[serde(default)]
    missing: Option<String>,
}

#[derive(Debug, Deserialize)]
struct Claim {
    mainsnak: Snak,
    #[serde(default)]
    rank: String,
}

#[derive(Debug, Deserialize)]
struct Snak {
    #[serde(default)]
    datavalue: Option<DataValue>,
}

#[derive(Debug, Deserialize)]
struct DataValue {
    value: serde_json::Value,
}

#[derive(Debug, Deserialize)]
struct Sitelink {
    title: String,
}

/// What a Wikidata item says that leads to content.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Item {
    /// Its images, as Commons titles (`File:...`), preferred ones first.
    pub images: Vec<String>,
    /// Its Wikipedia articles, by language.
    pub articles: BTreeMap<String, String>,
    /// Its Commons category (`Category:...`): most items of French
    /// motorway rest areas have one and no article.
    pub commons_category: Option<String>,
}

fn maxlag(code: &str, info: String, url: &str) -> Option<IngestError> {
    (code == "maxlag").then(|| IngestError::Status {
        url: url.to_owned(),
        status: reqwest::StatusCode::SERVICE_UNAVAILABLE,
        body: info,
        retry_after: Some(std::time::Duration::from_secs(5)),
    })
}

/// The items of a `wbgetentities` answer, by id.
///
/// # Errors
///
/// [`IngestError::Json`] when the answer is not the API's JSON, and a
/// retried [`IngestError::Status`] when it asks to wait (`maxlag`).
pub fn parse_entities(body: &[u8]) -> Result<BTreeMap<String, Item>, IngestError> {
    let answer: Entities = serde_json::from_slice(body).map_err(|source| IngestError::Json {
        what: "wikidata entities".into(),
        source,
    })?;
    if let Some(e) = answer.error {
        return Err(maxlag(&e.code, e.info.clone(), WIKIDATA_API_URL).unwrap_or(
            IngestError::Implausible {
                what: format!("wikidata answered {}: {}", e.code, e.info),
            },
        ));
    }
    let mut out = BTreeMap::new();
    for (id, entity) in answer.entities {
        if entity.missing.is_some() {
            continue;
        }
        let mut claims: Vec<&Claim> = entity.claims.get(IMAGE).into_iter().flatten().collect();
        claims.retain(|c| c.rank != "deprecated");
        claims.sort_by_key(|c| c.rank != "preferred");
        let images = claims
            .iter()
            .filter_map(|c| c.mainsnak.datavalue.as_ref()?.value.as_str())
            .filter_map(|name| content::commons_file_title(&format!("File:{name}")))
            .collect();
        let commons_category = entity
            .sitelinks
            .get("commonswiki")
            .filter(|l| l.title.starts_with("Category:"))
            .map(|l| l.title.clone());
        let articles = entity
            .sitelinks
            .into_iter()
            .filter_map(|(site, link)| {
                let lang = site.strip_suffix("wiki")?;
                // `commonswiki`, `specieswiki` and the like are not
                // Wikipedias.
                if lang.contains("commons") || lang.contains("species") || lang.contains("meta") {
                    return None;
                }
                let lang = lang.replace('_', "-");
                content::content_language(&lang)
                    .filter(|l| *l == lang)
                    .map(|l| (l, link.title))
            })
            .collect();
        out.insert(
            id,
            Item {
                images,
                articles,
                commons_category,
            },
        );
    }
    Ok(out)
}

/// The API of the Wikipedias, `{lang}` standing for the language.
pub const WIKIPEDIA_API_URL: &str = "https://{lang}.wikipedia.org/w/api.php";

/// The API of the Wikipedia in `lang` from the pattern `api`
/// ([`WIKIPEDIA_API_URL`]), when the code looks like a language.
#[must_use]
pub fn wikipedia_api(api: &str, lang: &str) -> Option<String> {
    let valid = (2..=12).contains(&lang.len())
        && lang.bytes().all(|b| b.is_ascii_lowercase() || b == b'-')
        && !lang.starts_with('-')
        && !lang.ends_with('-');
    valid.then(|| api.replace("{lang}", lang))
}

/// The introductions of `titles` (20 at most) on the Wikipedia whose API
/// is `api` (from [`wikipedia_api`]).
#[must_use]
pub fn extracts_url(api: &str, titles: &[String]) -> Option<String> {
    let joined = titles
        .iter()
        .take(TITLES_PER_REQUEST)
        .map(String::as_str)
        .collect::<Vec<_>>()
        .join("|");
    Url::parse_with_params(
        api,
        [
            ("action", "query"),
            ("format", "json"),
            ("formatversion", "2"),
            ("maxlag", "5"),
            ("prop", "extracts|info"),
            ("exintro", "1"),
            ("explaintext", "1"),
            ("exlimit", "20"),
            ("inprop", "url"),
            ("redirects", "1"),
            ("titles", joined.as_str()),
        ],
    )
    .ok()
    .map(String::from)
}

#[derive(Debug, Deserialize)]
struct Extracts {
    #[serde(default)]
    error: Option<ApiError>,
    #[serde(default)]
    query: Option<ExtractQuery>,
}

#[derive(Debug, Deserialize)]
struct ExtractQuery {
    #[serde(default)]
    normalized: Vec<Rename>,
    #[serde(default)]
    redirects: Vec<Rename>,
    #[serde(default)]
    pages: Vec<ExtractPage>,
}

#[derive(Debug, Deserialize)]
struct Rename {
    from: String,
    to: String,
}

#[derive(Debug, Deserialize)]
struct ExtractPage {
    title: String,
    #[serde(default)]
    missing: bool,
    #[serde(default)]
    extract: Option<String>,
    #[serde(default)]
    fullurl: Option<String>,
}

/// An article's introduction.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Extract {
    /// The article's title, after redirects.
    pub title: String,
    /// Its introduction as plain text, cut to
    /// [`content::MAX_DESCRIPTION_CHARS`].
    pub text: String,
    /// The article.
    pub url: String,
}

/// The introductions of an extracts answer, by the title asked for
/// (before normalisation and redirects). An empty introduction is none.
///
/// # Errors
///
/// [`IngestError::Json`] when the answer is not the API's JSON, and a
/// retried [`IngestError::Status`] when it asks to wait (`maxlag`).
pub fn parse_extracts(
    body: &[u8],
    lang: &str,
    asked: &[String],
) -> Result<BTreeMap<String, Extract>, IngestError> {
    let answer: Extracts = serde_json::from_slice(body).map_err(|source| IngestError::Json {
        what: "wikipedia extracts".into(),
        source,
    })?;
    if let Some(e) = answer.error {
        return Err(
            maxlag(&e.code, e.info.clone(), lang).unwrap_or(IngestError::Implausible {
                what: format!("wikipedia answered {}: {}", e.code, e.info),
            }),
        );
    }
    let Some(q) = answer.query else {
        return Ok(BTreeMap::new());
    };
    let host = format!("{lang}.wikipedia.org");
    let follow = |t: &str| -> String {
        let mut t = t.to_owned();
        for renames in [&q.normalized, &q.redirects] {
            if let Some(r) = renames.iter().find(|r| r.from == t) {
                t.clone_from(&r.to);
            }
        }
        t
    };
    let mut out = BTreeMap::new();
    for title in asked {
        let resolved = follow(title);
        let Some(page) = q.pages.iter().find(|p| p.title == resolved) else {
            continue;
        };
        if page.missing {
            continue;
        }
        let Some(text) = page
            .extract
            .as_deref()
            .and_then(|e| content::plain_text(e, content::MAX_DESCRIPTION_CHARS))
        else {
            continue;
        };
        let url = page
            .fullurl
            .clone()
            .filter(|u| u.starts_with(&format!("https://{host}/")))
            .unwrap_or_else(|| {
                lunaway_domain::conflation::wikipedia_url(&format!("{lang}:{}", page.title))
                    .unwrap_or_default()
            });
        if url.is_empty() {
            continue;
        }
        out.insert(
            title.clone(),
            Extract {
                title: page.title.clone(),
                text,
                url,
            },
        );
    }
    Ok(out)
}

/// The language most travellers in `country` read, for choosing which
/// articles to keep (ISO 3166-1 alpha-2).
#[must_use]
pub fn country_language(country: &str) -> Option<&'static str> {
    Some(match country {
        "FR" | "BE" | "LU" | "MC" => "fr",
        "DE" | "AT" | "CH" | "LI" => "de",
        "NL" => "nl",
        "ES" | "AD" => "es",
        "PT" => "pt",
        "IT" | "SM" | "VA" => "it",
        "GB" | "IE" => "en",
        "DK" => "da",
        "SE" => "sv",
        "NO" => "no",
        "FI" => "fi",
        "PL" => "pl",
        "CZ" => "cs",
        "SI" => "sl",
        "HR" => "hr",
        "GR" => "el",
        _ => return None,
    })
}

/// Languages of articles kept per place at most: the card shows the one
/// in the reader's language, else another.
pub const MAX_LANGUAGES: usize = 3;

/// The articles kept for a place, by language: the one its OpenStreetMap
/// data names, then those of its Wikidata item in French, English and the
/// language of its country, at most [`MAX_LANGUAGES`].
#[must_use]
pub fn choose_articles(
    osm: &[(String, String)],
    item_articles: &BTreeMap<String, String>,
    country: Option<&str>,
) -> Vec<(String, String)> {
    let mut out: Vec<(String, String)> = Vec::new();
    let mut push = |lang: &str, title: &str| {
        if out.len() < MAX_LANGUAGES && !out.iter().any(|(l, _)| l == lang) {
            out.push((lang.to_owned(), title.to_owned()));
        }
    };
    for (lang, title) in osm {
        push(lang, title);
    }
    let local = country.and_then(country_language);
    for lang in ["fr", "en"].into_iter().chain(local) {
        if let Some(title) = item_articles.get(lang) {
            push(lang, title);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn items_give_their_preferred_image_and_their_wikipedias() {
        let body = r#"{"entities":{"Q1":{"id":"Q1","claims":{"P18":[
            {"mainsnak":{"datavalue":{"value":"Old view.jpg","type":"string"}},"rank":"normal"},
            {"mainsnak":{"datavalue":{"value":"Best view.jpg","type":"string"}},"rank":"preferred"},
            {"mainsnak":{"datavalue":{"value":"Wrong.jpg","type":"string"}},"rank":"deprecated"}]},
          "sitelinks":{"frwiki":{"site":"frwiki","title":"Aire de la Baie"},
                       "commonswiki":{"site":"commonswiki","title":"Category:X"},
                       "enwiki":{"site":"enwiki","title":"Bay rest area"}}},
          "Q2":{"id":"Q2","missing":""}}}"#;
        let items = parse_entities(body.as_bytes()).unwrap();
        let q1 = &items["Q1"];
        assert_eq!(q1.images, ["File:Best view.jpg", "File:Old view.jpg"]);
        assert_eq!(q1.articles.len(), 2, "Commons is no Wikipedia");
        assert_eq!(q1.articles["fr"], "Aire de la Baie");
        assert_eq!(q1.commons_category.as_deref(), Some("Category:X"));
        assert!(!items.contains_key("Q2"));
    }

    #[test]
    fn extracts_follow_redirects_and_skip_empty_introductions() {
        let body = r#"{"batchcomplete":true,"query":{
            "normalized":[{"fromencoded":false,"from":"Aire_de_service","to":"Aire de service"}],
            "redirects":[{"from":"Aire de service","to":"Aire de repos et de service autoroutière"}],
            "pages":[
              {"pageid":1,"ns":0,"title":"Aire de repos et de service autoroutière",
               "extract":"Une aire de repos est un lieu aménagé.","fullurl":"https://fr.wikipedia.org/wiki/Aire_de_repos"},
              {"pageid":2,"ns":0,"title":"Caravane","extract":"","fullurl":"https://fr.wikipedia.org/wiki/Caravane"},
              {"ns":0,"title":"Absent","missing":true}]}}"#;
        let asked = vec![
            "Aire_de_service".to_owned(),
            "Caravane".to_owned(),
            "Absent".to_owned(),
        ];
        let got = parse_extracts(body.as_bytes(), "fr", &asked).unwrap();
        assert_eq!(got.len(), 1);
        let e = &got["Aire_de_service"];
        assert_eq!(e.text, "Une aire de repos est un lieu aménagé.");
        assert_eq!(e.url, "https://fr.wikipedia.org/wiki/Aire_de_repos");
    }

    #[test]
    fn hosts_are_built_from_language_codes_only() {
        let api = |l| wikipedia_api(WIKIPEDIA_API_URL, l);
        assert_eq!(
            api("fr").as_deref(),
            Some("https://fr.wikipedia.org/w/api.php")
        );
        assert_eq!(
            api("zh-yue").as_deref(),
            Some("https://zh-yue.wikipedia.org/w/api.php")
        );
        assert_eq!(api("evil.example/x"), None);
        assert_eq!(api("FR"), None);
        assert!(
            extracts_url(&api("fr").unwrap(), &["A".into()])
                .unwrap()
                .starts_with("https://fr.wikipedia.org/w/api.php?")
        );
    }

    #[test]
    fn articles_are_chosen_by_language() {
        let item: BTreeMap<String, String> = [("en", "A"), ("fr", "B"), ("de", "C"), ("it", "D")]
            .into_iter()
            .map(|(a, b)| (a.to_owned(), b.to_owned()))
            .collect();
        let osm = vec![("de".to_owned(), "C2".to_owned())];
        let chosen = choose_articles(&osm, &item, Some("IT"));
        assert_eq!(
            chosen,
            [
                ("de".to_owned(), "C2".to_owned()),
                ("fr".to_owned(), "B".to_owned()),
                ("en".to_owned(), "A".to_owned())
            ]
        );
    }
}
