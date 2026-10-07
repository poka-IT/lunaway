//! The open content adapters on answers recorded from the sources on
//! 2026-10-07 (`tests/fixtures/content/`).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::{NaiveDate, TimeZone, Utc};
use lunaway_domain::PlaceKind;
use lunaway_ingest::{
    content::{commons, mangrove, panoramax, wikipedia},
    datatourisme,
};

const COMMONS: &[u8] = include_bytes!("fixtures/content/commons_geosearch_treignac.json");
const PANORAMAX: &[u8] = include_bytes!("fixtures/content/panoramax_search_rennes.json");
const MANGROVE: &[u8] = include_bytes!("fixtures/content/mangrove_reviews_page.json");
const WIKIDATA: &[u8] = include_bytes!("fixtures/content/wikidata_entities.json");
const WIKIPEDIA: &[u8] = include_bytes!("fixtures/content/wikipedia_extracts_fr.json");
const DATATOURISME: &[u8] = include_bytes!("fixtures/content/datatourisme_objects.json");

#[test]
fn commons_files_carry_an_open_licence_and_a_standard_thumbnail() {
    let (files, skipped) = commons::parse(COMMONS).unwrap();
    assert!(!files.is_empty(), "skipped: {skipped:?}");
    for f in &files {
        assert!(f.title.starts_with("File:"), "{}", f.title);
        assert!(
            f.image_url.starts_with("https://thumb.wikimedia.org/")
                || f.image_url.starts_with("https://upload.wikimedia.org/"),
            "{}",
            f.image_url
        );
        assert!(
            !f.image_url.contains("px-") || f.image_url.contains("/1280px-"),
            "only the standard width is asked: {}",
            f.image_url
        );
        assert!(
            f.page_url
                .starts_with("https://commons.wikimedia.org/wiki/File:")
        );
        assert!(f.position.is_some(), "a geosearch answer is geotagged");
    }
}

#[test]
fn panoramax_pictures_come_from_known_instances_under_their_licence() {
    let (pictures, skipped) = panoramax::parse(PANORAMAX).unwrap();
    assert!(!pictures.is_empty(), "skipped: {skipped:?}");
    for p in &pictures {
        assert!(
            panoramax::INSTANCES
                .iter()
                .any(|(_, name)| *name == p.instance),
            "{}",
            p.instance
        );
        assert!(["CC BY-SA 4.0", "Licence Ouverte 2.0"].contains(&p.licence.name.as_str()));
        assert!(p.page_url.starts_with("https://panoramax."));
    }
}

#[test]
fn mangrove_reviews_are_read_from_a_real_page() {
    let (reviews, skipped, total) = mangrove::parse_page(MANGROVE).unwrap();
    assert_eq!(total, 5);
    assert_eq!(reviews.len() + skipped.len(), 5);
    for r in &reviews {
        assert!(r.stars.is_some() || r.text.is_some());
        assert!(
            r.page_url
                .starts_with("https://mangrove.reviews/list?signature=")
        );
    }
}

#[test]
fn wikidata_and_wikipedia_answers_are_read() {
    let items = wikipedia::parse_entities(WIKIDATA).unwrap();
    assert!(!items.is_empty());
    let asked = vec!["Mont-Saint-Michel".to_owned(), "Aire_de_service".to_owned()];
    let extracts = wikipedia::parse_extracts(WIKIPEDIA, "fr", &asked).unwrap();
    let msm = extracts
        .get("Mont-Saint-Michel")
        .expect("the article exists");
    assert!(msm.text.chars().count() <= lunaway_domain::content::MAX_DESCRIPTION_CHARS);
    assert!(msm.url.starts_with("https://fr.wikipedia.org/wiki/"));
    assert!(
        extracts.contains_key("Aire_de_service"),
        "a title is followed through its normalisation and redirect"
    );
}

#[test]
fn every_datatourisme_class_of_the_fixture_is_mapped_or_dropped() {
    let page = datatourisme::parse_page(DATATOURISME).unwrap();
    let known: Vec<&str> = datatourisme::CLASSES
        .iter()
        .map(|(c, _)| *c)
        .chain(datatourisme::GENERIC_CLASSES.iter().copied())
        .collect();
    for o in &page.objects {
        for t in o["type"].as_array().unwrap() {
            let t = t.as_str().unwrap();
            assert!(
                known.contains(&t),
                "class {t} is neither mapped, dropped nor generic: add it to CLASSES"
            );
        }
    }
    let at = Utc.with_ymd_and_hms(2026, 10, 7, 12, 0, 0).unwrap();
    let parsed = datatourisme::to_records(page.objects.clone(), at);
    assert!(!parsed.records.is_empty());
    assert!(
        parsed
            .records
            .iter()
            .any(|r| r.record.kind == PlaceKind::MotorhomeArea),
        "the fixture holds a motorhome area"
    );
    for r in &parsed.records {
        assert!(
            r.record.description.is_none() && r.record.descriptions.is_empty(),
            "descriptions stay in the raw payload, out of the change feed and the packs"
        );
        assert!(
            r.external_url
                .as_deref()
                .is_some_and(|u| u.starts_with("https://data.datatourisme.fr/"))
        );
        assert!(
            r.raw.get("uuid").is_some(),
            "the object is kept as the raw payload"
        );
    }
    let today = NaiveDate::from_ymd_opt(2026, 10, 7).unwrap();
    let (mut kept, mut skipped) = (0, 0);
    for r in &parsed.records {
        let (k, s) = datatourisme::photos_of(&r.raw, today);
        kept += k.len();
        skipped += s.len();
        for p in k {
            assert!(!p.credits.is_empty(), "a photo is shown with its credit");
            assert!(!p.licence.name.contains("NC") && !p.licence.name.contains("ND"));
        }
    }
    assert!(kept > 0 && skipped > 0, "kept {kept}, skipped {skipped}");
}
