//! The machine translations kept for the reviews and descriptions
//! (`lunaway_db::translations`): what may be translated, and that a
//! review's translations go with it, whoever deletes or rewrites it.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::Utc;
use lunaway_db::{
    PgPool, accounts, community,
    conflation::{self, OpeningEval, PlaceWrite},
    content::{self, NewDescription, NewReview},
    retention,
    translations::{self, ItemKey, ItemKind, Translatable, Translation},
};
use lunaway_domain::{
    Address, OvernightStatus, PlaceKind, Position, SourceId,
    community::ReviewStatus,
    conflation::{LocalizedText, PlaceContent},
    translation::text_fingerprint,
};
use sqlx::postgres::PgPoolOptions;
use uuid::Uuid;

const NO_OPENING: OpeningEval = OpeningEval {
    parsed: false,
    intervals: None,
    until: None,
    window_start: None,
    refresh_at: None,
};

async fn as_role(pool: &PgPool, set_role: &'static str) -> PgPool {
    PgPoolOptions::new()
        .max_connections(2)
        .after_connect(move |conn, _| {
            Box::pin(async move {
                sqlx::query(set_role).execute(conn).await?;
                Ok(())
            })
        })
        .connect_with((*pool.connect_options()).clone())
        .await
        .unwrap()
}

/// Writes place `id` with `descriptions`, as the conflation does.
async fn write_place(pool: &PgPool, id: Uuid, descriptions: &[LocalizedText]) {
    let c = PlaceContent {
        name: Some("Aire du Lac".into()),
        kind: PlaceKind::MotorhomeArea,
        position: Position::new(45.9, 6.1).unwrap(),
        overnight: OvernightStatus::Unknown,
        services: Vec::new(),
        activities: Vec::new(),
        description: None,
        address: Address::default(),
        price_parking_eur: None,
        price_services_eur: None,
        price_services_included: false,
        price_parking_includes: Vec::new(),
        max_height_m: None,
        max_length_m: None,
        max_width_m: None,
        max_weight_t: None,
        capacity: None,
        opening_hours: None,
        website: None,
        phone: None,
        stars: None,
    };
    let mut tx = conflation::begin_writer(pool).await.unwrap();
    conflation::upsert_place(
        &mut tx,
        PlaceWrite {
            id,
            content: &c,
            provenance: &[],
            opening: &NO_OPENING,
            descriptions,
            external_links: &[],
            content_hash: &format!("h{}", descriptions.len()),
        },
    )
    .await
    .unwrap();
    tx.commit().await.unwrap();
}

fn german(text: &str) -> LocalizedText {
    LocalizedText {
        lang: "de".into(),
        text: text.into(),
        source_id: SourceId::OSM,
    }
}

async fn account(app: &PgPool) -> Uuid {
    let mut key = [7u8; 65];
    key[0] = 4;
    let (a, _) = accounts::create_with_key(
        app,
        accounts::NewAccount {
            pseudonym: "Loutre du Doubs",
            thumbprint: &format!("{:0>43}", 7),
            public_key: &key,
            session_hash: &[7; 32],
            session_ttl_secs: 3_600.0,
        },
    )
    .await
    .unwrap();
    accounts::set_trust_level(app, a.id, 2).await.unwrap();
    a.id
}

async fn review(
    app: &PgPool,
    account: Uuid,
    place: Uuid,
    body: &str,
    status: ReviewStatus,
) -> Uuid {
    community::review(
        app,
        community::ReviewWrite {
            account,
            place,
            stars: 4,
            body,
            lang: Some("de"),
            visited_on: None,
            vehicle: None,
            status,
            held_for: None,
        },
    )
    .await
    .unwrap()
    .id
}

fn made_from(text: &str) -> Translation {
    Translation {
        text: "Calme et propre.".into(),
        source_lang: "de".into(),
        source_sha256: text_fingerprint(text).to_vec(),
        engine: "opus-mt".into(),
        model: "deu-fra opusTCv20210807_transformer-big_2022-07-22".into(),
        translated_at: Utc::now(),
    }
}

async fn count(pool: &PgPool) -> i64 {
    sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM translations"#)
        .fetch_one(pool)
        .await
        .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_review_s_translations_go_when_its_text_changes_or_it_is_deleted(pool: PgPool) {
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let place = Uuid::now_v7();
    write_place(&pool, place, &[]).await;
    let author = account(&app).await;
    let body = "Ruhig und sauber, die Säule funktioniert.";
    let id = review(&app, author, place, body, ReviewStatus::Published).await;

    let original = translations::original(&app, &Translatable::Review(id))
        .await
        .unwrap()
        .expect("a published review with text can be translated");
    assert_eq!(original.text, body);
    assert_eq!(original.lang.as_deref(), Some("de"));
    assert!(
        translations::keep(&app, &original.key, "fr", &made_from(body))
            .await
            .unwrap()
    );
    let kept = translations::kept(&app, &original.key, "fr")
        .await
        .unwrap()
        .expect("kept for the next reader");
    assert_eq!(kept.text, "Calme et propre.");

    review(
        &app,
        author,
        place,
        "Laut in der Nacht, aber sauber.",
        ReviewStatus::Published,
    )
    .await;
    assert_eq!(
        count(&pool).await,
        0,
        "an edited review is never shown with the translation of its old text"
    );

    let text = "Laut in der Nacht, aber sauber.";
    let original = translations::original(&app, &Translatable::Review(id))
        .await
        .unwrap()
        .unwrap();
    translations::keep(&app, &original.key, "fr", &made_from(text))
        .await
        .unwrap();
    assert_eq!(count(&pool).await, 1);
    community::delete_review(&app, author, id).await.unwrap();
    assert_eq!(
        count(&pool).await,
        0,
        "what a person wrote goes with every translation of it"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_translation_of_a_text_that_changed_meanwhile_is_not_kept(pool: PgPool) {
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let place = Uuid::now_v7();
    write_place(&pool, place, &[]).await;
    let author = account(&app).await;
    let id = review(
        &app,
        author,
        place,
        "Ruhig und sauber, die Säule funktioniert.",
        ReviewStatus::Published,
    )
    .await;
    let key = ItemKey {
        kind: ItemKind::Review,
        id,
        source: String::new(),
        lang: String::new(),
    };
    let kept = translations::keep(&app, &key, "fr", &made_from("the text before an edit"))
        .await
        .unwrap();
    assert!(
        !kept,
        "the engine worked on a text the review no longer holds: nothing of it may stay"
    );
    assert_eq!(count(&pool).await, 0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn only_what_a_reader_sees_can_be_translated(pool: PgPool) {
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let place = Uuid::now_v7();
    write_place(&pool, place, &[german("Ein ruhiger Platz am See.")]).await;
    let author = account(&app).await;
    let held = review(
        &app,
        author,
        place,
        "Ruhig und sauber, die Säule funktioniert.",
        ReviewStatus::Pending,
    )
    .await;
    assert!(
        translations::original(&app, &Translatable::Review(held))
            .await
            .unwrap()
            .is_none(),
        "a review the rules hold is not shown, so not translated"
    );
    assert!(
        translations::original(&app, &Translatable::Review(Uuid::now_v7()))
            .await
            .unwrap()
            .is_none()
    );
    let description = translations::original(
        &app,
        &Translatable::Description {
            place,
            source: "osm".into(),
            lang: "de".into(),
        },
    )
    .await
    .unwrap()
    .expect("the place's own description, named by its source and language");
    assert_eq!(description.text, "Ein ruhiger Platz am See.");
    assert!(
        translations::original(
            &app,
            &Translatable::Description {
                place,
                source: "osm".into(),
                lang: "fr".into(),
            },
        )
        .await
        .unwrap()
        .is_none(),
        "a description is named exactly: no other one is picked instead"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_place_s_description_translations_go_when_its_descriptions_change(pool: PgPool) {
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let place = Uuid::now_v7();
    let text = "Ein ruhiger Platz am See.";
    write_place(&pool, place, &[german(text)]).await;
    let original = translations::original(
        &app,
        &Translatable::Description {
            place,
            source: "osm".into(),
            lang: "de".into(),
        },
    )
    .await
    .unwrap()
    .unwrap();
    translations::keep(&app, &original.key, "fr", &made_from(text))
        .await
        .unwrap();
    write_place(&pool, place, &[german(text)]).await;
    assert_eq!(
        count(&pool).await,
        1,
        "a write that changes no description keeps them"
    );
    // A takedown empties the place: what it said must not stay translated.
    write_place(&pool, place, &[]).await;
    assert_eq!(count(&pool).await, 0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_import_role_clears_the_translations_of_the_reviews_it_removes(pool: PgPool) {
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let place = Uuid::now_v7();
    write_place(&pool, place, &[]).await;
    let text = "Rustige plek, schoon sanitair en vriendelijke ontvangst.";
    let review = NewReview {
        place_id: place,
        external_id: "sig-nl".into(),
        rating: Some(4),
        text: Some(text.into()),
        lang: Some("nl".into()),
        author: None,
        author_key: None,
        written_at: Utc::now(),
        page_url: "https://mangrove.reviews/list?signature=sig-nl".into(),
        licence: "CC BY 4.0".into(),
        licence_url: "https://creativecommons.org/licenses/by/4.0/".into(),
        distance_m: None,
    };
    content::replace_reviews(&ingest, "mangrove", &[review], Utc::now())
        .await
        .unwrap();
    let id = sqlx::query_scalar!("SELECT id FROM content_reviews WHERE external_id = 'sig-nl'")
        .fetch_one(&pool)
        .await
        .unwrap();
    let original = translations::original(&app, &Translatable::ExternalReview(id))
        .await
        .unwrap()
        .expect("an open source's review is translated like the partner's");
    assert_eq!(original.key.kind, ItemKind::ContentReview);
    translations::keep(&app, &original.key, "fr", &made_from(text))
        .await
        .unwrap();
    assert!(
        sqlx::query("SELECT 1 FROM translations")
            .execute(&ingest)
            .await
            .is_err(),
        "the import role, which parses untrusted payloads, never reads the translations"
    );
    content::replace_reviews(&ingest, "mangrove", &[], Utc::now())
        .await
        .unwrap();
    assert_eq!(
        count(&pool).await,
        0,
        "a review gone at its source takes its translations along, whoever removes it"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn only_the_api_role_reads_and_writes_the_translations(pool: PgPool) {
    for (role, expected) in [
        ("lunaway_app", vec!["SELECT", "INSERT", "UPDATE", "DELETE"]),
        ("lunaway_ingest", vec![]),
    ] {
        let mut has = Vec::new();
        for p in ["SELECT", "INSERT", "UPDATE", "DELETE"] {
            let granted = sqlx::query_scalar!(
                r#"SELECT has_table_privilege($1, 'translations', $2) AS "has!""#,
                role,
                p
            )
            .fetch_one(&pool)
            .await
            .unwrap();
            if granted {
                has.push(p);
            }
        }
        assert_eq!(has, expected, "{role} on translations");
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_daily_sweep_removes_a_translation_its_original_no_longer_matches(pool: PgPool) {
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let place = Uuid::now_v7();
    let text = "Ein ruhiger Platz am See.";
    write_place(&pool, place, &[german(text)]).await;
    let key = ItemKey {
        kind: ItemKind::PlaceDescription,
        id: place,
        source: "osm".into(),
        lang: "de".into(),
    };
    assert!(
        translations::keep(&app, &key, "fr", &made_from(text))
            .await
            .unwrap()
    );
    assert!(
        !translations::keep(&app, &key, "en", &made_from("an older text"))
            .await
            .unwrap(),
        "a description changed while the engine worked leaves nothing behind"
    );
    // What a race with a refresh could leave: a row of an older text.
    sqlx::query!(
        r#"
        INSERT INTO translations (item_kind, item_id, item_source, item_lang, target_lang,
                                  source_lang, source_sha256, text, engine, model)
        VALUES ('place_description', $1, 'osm', 'de', 'en', 'de', $2, 'Old.', 'opus-mt', 'm')
        "#,
        place,
        &text_fingerprint("an older text")[..],
    )
    .execute(&app)
    .await
    .unwrap();
    let swept = retention::sweep(&app, Utc::now()).await.unwrap();
    assert_eq!(swept.translations, 1, "only the stale one goes");
    assert!(
        translations::kept(&app, &key, "fr")
            .await
            .unwrap()
            .is_some()
    );
}

/// A review of Lunaway's community on `place`, by a new account `n`.
async fn review_by(app: &PgPool, n: u8, place: Uuid, body: &str) -> (Uuid, Uuid) {
    let mut key = [n; 65];
    key[0] = 4;
    let (a, _) = accounts::create_with_key(
        app,
        accounts::NewAccount {
            pseudonym: "Castor des Vosges",
            thumbprint: &format!("{n:0>43}"),
            public_key: &key,
            session_hash: &[n; 32],
            session_ttl_secs: 3_600.0,
        },
    )
    .await
    .unwrap();
    accounts::set_trust_level(app, a.id, 2).await.unwrap();
    (
        a.id,
        review(app, a.id, place, body, ReviewStatus::Published).await,
    )
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_review_is_translatable_only_where_a_reader_sees_it(pool: PgPool) {
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let text = "Ruhig und sauber, die Säule funktioniert.";
    // Merged into a live place: the review shows on the place it was
    // merged into.
    let (merged, root) = (Uuid::now_v7(), Uuid::now_v7());
    write_place(&pool, merged, &[]).await;
    write_place(&pool, root, &[]).await;
    let (_, on_merged) = review_by(&app, 11, merged, text).await;
    let mut tx = conflation::begin_writer(&pool).await.unwrap();
    conflation::tombstone(&mut tx, merged, Some(root))
        .await
        .unwrap();
    tx.commit().await.unwrap();
    assert!(
        translations::original(&app, &Translatable::Review(on_merged))
            .await
            .unwrap()
            .is_some(),
        "a merge leads to the live place that shows the review"
    );
    // A place taken down, before a moderator purges its community content.
    let gone = Uuid::now_v7();
    write_place(&pool, gone, &[]).await;
    let (_, on_gone) = review_by(&app, 12, gone, text).await;
    sqlx::query!(
        "UPDATE places SET deleted_at = now(), taken_down_at = now() WHERE id = $1",
        gone
    )
    .execute(&pool)
    .await
    .unwrap();
    assert!(
        translations::original(&app, &Translatable::Review(on_gone))
            .await
            .unwrap()
            .is_none(),
        "a place taken down keeps nothing readable, translated or not"
    );
    // A banned author's reviews leave every list.
    let open = Uuid::now_v7();
    write_place(&pool, open, &[]).await;
    let (author, by_banned) = review_by(&app, 13, open, text).await;
    sqlx::query!(
        "UPDATE accounts SET banned_at = now() WHERE id = $1",
        author
    )
    .execute(&pool)
    .await
    .unwrap();
    assert!(
        translations::original(&app, &Translatable::Review(by_banned))
            .await
            .unwrap()
            .is_none()
    );
}

fn wikipedia(lang: &str, text: &str) -> NewDescription {
    NewDescription {
        lang: lang.into(),
        text: text.into(),
        title: Some("Lac".into()),
        page_url: "https://de.wikipedia.org/wiki/See".into(),
        author: None,
        publisher: Some("Wikipedia".into()),
        source_updated_on: None,
        licence: "CC BY-SA 4.0".into(),
        licence_url: "https://creativecommons.org/licenses/by-sa/4.0/".into(),
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_open_source_s_description_is_translated_while_its_place_stands(pool: PgPool) {
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let place = Uuid::now_v7();
    write_place(&pool, place, &[]).await;
    let text = "Der See liegt auf 450 Metern Höhe und ist im Sommer warm.";
    content::replace_descriptions(
        &ingest,
        place,
        "wikipedia",
        &[wikipedia("de", text)],
        Utc::now(),
        1,
    )
    .await
    .unwrap();
    let item = Translatable::ExternalDescription {
        place,
        source: "wikipedia".into(),
        lang: "de".into(),
    };
    let original = translations::original(&app, &item)
        .await
        .unwrap()
        .expect("an open source's text on a live place");
    assert_eq!(original.key.kind, ItemKind::ContentDescription);
    assert_eq!(original.text, text);
    assert!(
        translations::keep(&app, &original.key, "fr", &made_from(text))
            .await
            .unwrap()
    );
    // The weekly refresh rewrites the text: the old translation is stale.
    let newer = "Der See liegt auf 450 Metern Höhe.";
    content::replace_descriptions(
        &ingest,
        place,
        "wikipedia",
        &[wikipedia("de", newer)],
        Utc::now(),
        1,
    )
    .await
    .unwrap();
    assert_eq!(
        retention::sweep(&app, Utc::now())
            .await
            .unwrap()
            .translations,
        1,
        "a translation of a text the source no longer gives goes"
    );
    sqlx::query!(
        "UPDATE places SET deleted_at = now(), taken_down_at = now() WHERE id = $1",
        place
    )
    .execute(&pool)
    .await
    .unwrap();
    assert!(
        translations::original(&app, &item).await.unwrap().is_none(),
        "nothing of a place taken down is translated"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_description_inherited_through_merges_is_kept_until_its_place_goes(pool: PgPool) {
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    // Two merges deep: the oldest place's text shows on the live one.
    let (oldest, middle, live) = (Uuid::now_v7(), Uuid::now_v7(), Uuid::now_v7());
    for p in [oldest, middle, live] {
        write_place(&pool, p, &[]).await;
    }
    let text = "Der See liegt auf 450 Metern Höhe und ist im Sommer warm.";
    content::replace_descriptions(
        &ingest,
        oldest,
        "wikipedia",
        &[wikipedia("de", text)],
        Utc::now(),
        1,
    )
    .await
    .unwrap();
    let mut tx = conflation::begin_writer(&pool).await.unwrap();
    conflation::tombstone(&mut tx, oldest, Some(middle))
        .await
        .unwrap();
    conflation::tombstone(&mut tx, middle, Some(live))
        .await
        .unwrap();
    tx.commit().await.unwrap();
    let original = translations::original(
        &app,
        &Translatable::ExternalDescription {
            place: live,
            source: "wikipedia".into(),
            lang: "de".into(),
        },
    )
    .await
    .unwrap()
    .expect("the card of the live place shows its merged places' texts");
    assert!(
        translations::keep(&app, &original.key, "fr", &made_from(text))
            .await
            .unwrap(),
        "kept, or it would be translated again at every request"
    );
    assert_eq!(
        retention::sweep(&app, Utc::now())
            .await
            .unwrap()
            .translations,
        0
    );
    sqlx::query!("UPDATE places SET deleted_at = now() WHERE id = $1", live)
        .execute(&pool)
        .await
        .unwrap();
    assert_eq!(
        retention::sweep(&app, Utc::now())
            .await
            .unwrap()
            .translations,
        1,
        "a place gone takes its translations at the next sweep"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_open_review_follows_its_place_s_merges_and_their_hides(pool: PgPool) {
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    // Two merges deep: the review's place, then the place it went into,
    // then the live place that shows it.
    let (merged, middle, live) = (Uuid::now_v7(), Uuid::now_v7(), Uuid::now_v7());
    for p in [merged, middle, live] {
        write_place(&pool, p, &[]).await;
    }
    let review = NewReview {
        place_id: merged,
        external_id: "sig-merged".into(),
        rating: Some(4),
        text: Some("Rustige plek, schoon sanitair en vriendelijke ontvangst.".into()),
        lang: Some("nl".into()),
        author: None,
        author_key: None,
        written_at: Utc::now(),
        page_url: "https://mangrove.reviews/list?signature=sig-merged".into(),
        licence: "CC BY 4.0".into(),
        licence_url: "https://creativecommons.org/licenses/by/4.0/".into(),
        distance_m: None,
    };
    content::replace_reviews(&ingest, "mangrove", &[review], Utc::now())
        .await
        .unwrap();
    let mut tx = conflation::begin_writer(&pool).await.unwrap();
    conflation::tombstone(&mut tx, merged, Some(middle))
        .await
        .unwrap();
    conflation::tombstone(&mut tx, middle, Some(live))
        .await
        .unwrap();
    tx.commit().await.unwrap();
    let id = sqlx::query_scalar!("SELECT id FROM content_reviews WHERE external_id = 'sig-merged'")
        .fetch_one(&pool)
        .await
        .unwrap();
    let item = Translatable::ExternalReview(id);
    assert!(
        translations::original(&app, &item).await.unwrap().is_some(),
        "shown on the live place its place was merged into"
    );
    sqlx::query!(
        "INSERT INTO content_hides (source_id, scope, key) VALUES ('mangrove', 'place', $1)",
        live.to_string()
    )
    .execute(&pool)
    .await
    .unwrap();
    assert!(
        translations::original(&app, &item).await.unwrap().is_none(),
        "a hide of the source on the place that shows it hides it, translated or not"
    );
}
