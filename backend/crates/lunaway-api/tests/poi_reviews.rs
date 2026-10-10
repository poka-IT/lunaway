//! Ratings and reviews of the points of interest over HTTP, as the app
//! sees them: a rating then a review of a shop, the review that replaces
//! it, its deletion, a text held for a moderator or pasted elsewhere,
//! reports that hide it, the pages and the muted authors, a deleted or
//! banned author, the levels, a point the map does not show, and the
//! rating of a list of points read in one query.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::{TimeZone, Utc};
use lunaway_db::PgPool;
use lunaway_domain::{SourceId, community::trust::Thresholds};
use lunaway_ingest::{poi_osm, store::store_pois};
use serde_json::{Value, json};
use uuid::Uuid;

use crate::community::{Device, app, code, config, gql, ok, sign_in};

const POIS: &[u8] = include_bytes!("../../lunaway-ingest/tests/fixtures/osm_poi_sample.json");

/// The points of the OpenStreetMap sample (Ambérieu-en-Bugey).
async fn seeded(pool: &PgPool) {
    let at = Utc.with_ymd_and_hms(2026, 10, 5, 22, 0, 0).unwrap();
    let parsed = poi_osm::parse(POIS, at).unwrap();
    store_pois(pool, &SourceId::OSM, &parsed.points)
        .await
        .unwrap();
}

async fn point_named(pool: &PgPool, name: &str) -> Uuid {
    sqlx::query_scalar!("SELECT id FROM pois WHERE name = $1", name)
        .fetch_one(pool)
        .await
        .unwrap()
}

const RATE: &str = r"
mutation($id: UUID!, $stars: Int!) {
  ratePoi(poiId: $id, stars: $stars) { id poiId rating text status sourceId }
}";

const REVIEW: &str = r#"
mutation($id: UUID!, $stars: Int!, $text: String!) {
  reviewPoi(poiId: $id, stars: $stars, text: $text, visitedOn: "2026-09-20", lang: "fr") {
    id poiId rating text lang visitedAt status authorId authorName
  }
}"#;

const CARD: &str = r"
query($id: UUID!) {
  poi(id: $id) {
    ratings { sourceId average count }
    reviews(first: 10) {
      nodes { id sourceId poiId rating text lang authorName authorId visitedAt status }
      totalCount hasNextPage endCursor
    }
    myReview { id rating text status }
  }
}";

const DELETE: &str = "mutation($id: UUID!) { deleteReview(id: $id) }";

const REPORT: &str =
    "mutation($id: UUID!) { reportContent(target: POI_REVIEW, id: $id, reason: OFFENSIVE) }";

async fn card(app: &axum::Router, token: Option<&str>, poi: Uuid) -> Value {
    let body = gql(app, token, CARD, json!({"id": poi})).await;
    ok(&body)["poi"].clone()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_point_is_rated_then_reviewed_and_a_new_review_replaces_the_first(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let bakery = point_named(&pool, "Maison Bochard").await;
    let (alice, alice_id) = sign_in(&app, &Device::new(1)).await;
    let (bob, _) = sign_in(&app, &Device::new(2)).await;

    let rated = gql(&app, Some(&alice), RATE, json!({"id": bakery, "stars": 4})).await;
    let rating = &ok(&rated)["ratePoi"];
    assert_eq!(rating["status"], "PUBLISHED", "a rating alone is published");
    assert_eq!(rating["text"], Value::Null);
    assert_eq!(rating["sourceId"], "community-cc-by");
    let shown = card(&app, None, bakery).await;
    assert_eq!(
        shown["ratings"],
        json!([{"sourceId": "community-cc-by", "average": 4.0, "count": 1}])
    );
    assert_eq!(
        shown["reviews"]["totalCount"], 0,
        "a rating without text is not a review to read"
    );

    let text = "Pain au levain excellent, accueil souriant.";
    let written = gql(
        &app,
        Some(&alice),
        REVIEW,
        json!({"id": bakery, "stars": 5, "text": text}),
    )
    .await;
    let review = &ok(&written)["reviewPoi"];
    assert_eq!(
        review["id"], rating["id"],
        "one row per account and point: the review takes the rating's place"
    );
    assert_eq!(review["status"], "PUBLISHED");
    assert_eq!(review["visitedAt"], "2026-09-20");
    let rated_by_bob = gql(&app, Some(&bob), RATE, json!({"id": bakery, "stars": 3})).await;
    ok(&rated_by_bob);

    let shown = card(&app, Some(&alice), bakery).await;
    assert_eq!(
        shown["ratings"],
        json!([{"sourceId": "community-cc-by", "average": 4.0, "count": 2}]),
        "Alice's 5 and Bob's 3"
    );
    let node = &shown["reviews"]["nodes"][0];
    assert_eq!(shown["reviews"]["totalCount"], 1);
    assert_eq!(node["text"], text);
    assert_eq!(node["lang"], "fr");
    assert_eq!(node["poiId"], bakery.to_string());
    assert_eq!(node["authorId"], alice_id.to_string());
    assert!(node["authorName"].as_str().is_some());
    assert_eq!(shown["myReview"]["id"], review["id"]);
    assert_eq!(
        card(&app, None, bakery).await["myReview"],
        Value::Null,
        "an anonymous reader has no review of their own"
    );

    let new_text = "Plus de levain le lundi, mais toujours aussi bon.";
    let again = gql(
        &app,
        Some(&alice),
        REVIEW,
        json!({"id": bakery, "stars": 4, "text": new_text}),
    )
    .await;
    assert_eq!(ok(&again)["reviewPoi"]["id"], review["id"]);
    let shown = card(&app, None, bakery).await;
    assert_eq!(shown["reviews"]["totalCount"], 1, "replaced, not added");
    assert_eq!(shown["reviews"]["nodes"][0]["text"], new_text);
    assert_eq!(shown["ratings"][0]["average"], 3.5);
    let mine = gql(
        &app,
        Some(&alice),
        "{ myAccount { poiReviews { totalCount nodes { id poiId rating text } } } }",
        json!({}),
    )
    .await;
    let mine = &ok(&mine)["myAccount"]["poiReviews"];
    assert_eq!(mine["totalCount"], 1);
    assert_eq!(mine["nodes"][0]["poiId"], bakery.to_string());

    let deleted = gql(&app, Some(&alice), DELETE, json!({"id": review["id"]})).await;
    assert_eq!(ok(&deleted)["deleteReview"], true);
    let shown = card(&app, Some(&alice), bakery).await;
    assert_eq!(shown["reviews"]["totalCount"], 0);
    assert_eq!(shown["myReview"], Value::Null);
    assert_eq!(
        shown["ratings"],
        json!([{"sourceId": "community-cc-by", "average": 3.0, "count": 1}]),
        "her stars went with her review"
    );
    let twice = gql(&app, Some(&alice), DELETE, json!({"id": review["id"]})).await;
    assert_eq!(code(&twice), "NOT_FOUND");
    let others = gql(
        &app,
        Some(&alice),
        DELETE,
        json!({"id": rated_by_bob["data"]["ratePoi"]["id"]}),
    )
    .await;
    assert_eq!(
        code(&others),
        "NOT_FOUND",
        "nobody deletes another account's rating"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_review_of_a_point_with_a_link_waits_for_a_moderator(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let shop = point_named(&pool, "Carrefour Market").await;
    let (alice, _) = sign_in(&app, &Device::new(1)).await;
    let (bob, bob_id) = sign_in(&app, &Device::new(2)).await;

    let held = gql(
        &app,
        Some(&alice),
        REVIEW,
        json!({"id": shop, "stars": 4, "text": "Promotions sur www.example.com chaque semaine"}),
    )
    .await;
    let held = &ok(&held)["reviewPoi"];
    assert_eq!(held["status"], "PENDING");
    let shown = card(&app, None, shop).await;
    assert_eq!(
        shown["reviews"]["totalCount"], 0,
        "a held review is not public"
    );
    assert_eq!(
        shown["ratings"],
        json!([]),
        "nor do its stars count before a moderator publishes it"
    );
    let queue = lunaway_db::moderation::open(&pool, 10).await.unwrap();
    let entry = queue
        .iter()
        .find(|e| e.target_id.to_string() == held["id"].as_str().unwrap())
        .expect("the held review waits in the queue");
    assert_eq!(
        (
            entry.kind.as_str(),
            entry.target_type.as_str(),
            entry.reason.as_str()
        ),
        ("held_review", "poi_review", "link")
    );
    assert!(
        entry
            .excerpt
            .as_deref()
            .is_some_and(|e| e.starts_with("Carrefour Market: Promotions")),
        "the moderator reads which point and what text: {:?}",
        entry.excerpt
    );
    lunaway_db::moderation::decide(
        &pool,
        entry.id,
        lunaway_db::moderation::Decision::Approve,
        None,
    )
    .await
    .unwrap();
    let shown = card(&app, None, shop).await;
    assert_eq!(
        shown["reviews"]["totalCount"], 1,
        "approved, it is published"
    );

    let bob_held = gql(
        &app,
        Some(&bob),
        REVIEW,
        json!({"id": shop, "stars": 1, "text": "Appelez le 06 12 34 56 78 pour en savoir plus"}),
    )
    .await;
    assert_eq!(ok(&bob_held)["reviewPoi"]["status"], "PENDING");
    let entry = lunaway_db::moderation::open(&pool, 10)
        .await
        .unwrap()
        .into_iter()
        .find(|e| e.target_type == "poi_review")
        .unwrap();
    lunaway_db::moderation::decide(
        &pool,
        entry.id,
        lunaway_db::moderation::Decision::Reject,
        None,
    )
    .await
    .unwrap();
    let bob_sees = card(&app, Some(&bob), shop).await;
    assert_eq!(bob_sees["myReview"]["status"], "REMOVED");
    let removals: i32 = sqlx::query_scalar!(
        "SELECT moderation_removals FROM accounts WHERE id = $1",
        bob_id
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        removals, 1,
        "a removed review of a point counts against its author's level"
    );
    let rewritten = gql(
        &app,
        Some(&bob),
        REVIEW,
        json!({"id": shop, "stars": 2, "text": "Rayon frais un peu vide le dimanche."}),
    )
    .await;
    assert_eq!(
        ok(&rewritten)["reviewPoi"]["status"],
        "REMOVED",
        "writing again does not undo a removal"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn three_reports_hide_a_review_of_a_point_until_a_moderator_decides(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let pharmacy = point_named(&pool, "Pharmacie Vallée").await;
    let (alice, _) = sign_in(&app, &Device::new(1)).await;
    let written = gql(
        &app,
        Some(&alice),
        REVIEW,
        json!({"id": pharmacy, "stars": 2, "text": "Personnel désagréable ce matin-là."}),
    )
    .await;
    let id = ok(&written)["reviewPoi"]["id"].clone();
    let own = gql(&app, Some(&alice), REPORT, json!({"id": id})).await;
    assert_eq!(
        code(&own),
        "NOT_FOUND",
        "an author cannot report their own review"
    );
    for n in 3..=5 {
        let (reporter, reporter_id) = sign_in(&app, &Device::new(n)).await;
        if n == 5 {
            lunaway_db::accounts::set_granted_level(&pool, reporter_id, 2)
                .await
                .unwrap();
        }
        let reported = gql(&app, Some(&reporter), REPORT, json!({"id": id})).await;
        assert_eq!(ok(&reported)["reportContent"], true);
        let shown = card(&app, None, pharmacy).await;
        let expected = if n < 5 { 1 } else { 0 };
        assert_eq!(
            shown["reviews"]["totalCount"], expected,
            "hidden at the third distinct reporter, one of level 2"
        );
    }
    let shown = card(&app, Some(&alice), pharmacy).await;
    assert_eq!(
        shown["ratings"],
        json!([]),
        "a hidden review's stars stop counting"
    );
    assert_eq!(shown["myReview"]["status"], "HIDDEN");
    let reported: i64 = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM moderation_queue
           WHERE kind = 'reported_content' AND target_type = 'poi_review' AND status = 'open'"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(reported, 1, "one entry for the moderators");

    // Deleting it withdraws it: the text goes, the hidden row stays with
    // its reports, so posting again does not escape the moderator.
    let deleted = gql(&app, Some(&alice), DELETE, json!({"id": id})).await;
    assert_eq!(ok(&deleted)["deleteReview"], true);
    let stub = sqlx::query!(
        "SELECT body, status FROM poi_reviews WHERE id = $1",
        id.as_str().unwrap().parse::<Uuid>().unwrap()
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!((stub.body, stub.status.as_str()), (None, "hidden"));
    let again = gql(
        &app,
        Some(&alice),
        REVIEW,
        json!({"id": pharmacy, "stars": 2, "text": "Personnel désagréable ce matin-là."}),
    )
    .await;
    assert_eq!(ok(&again)["reviewPoi"]["status"], "HIDDEN");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_deleted_account_leaves_its_published_reviews_of_points_without_author(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let bakery = point_named(&pool, "Maison Bochard").await;
    let shop = point_named(&pool, "Carrefour Market").await;
    let pharmacy = point_named(&pool, "Pharmacie Vallée").await;
    let (alice, alice_id) = sign_in(&app, &Device::new(1)).await;
    let text = "Croissants encore tièdes à sept heures.";
    ok(&gql(
        &app,
        Some(&alice),
        REVIEW,
        json!({"id": bakery, "stars": 5, "text": text}),
    )
    .await);
    ok(&gql(&app, Some(&alice), RATE, json!({"id": shop, "stars": 2})).await);
    let held = gql(
        &app,
        Some(&alice),
        REVIEW,
        json!({"id": pharmacy, "stars": 4, "text": "Horaires sur www.example.com"}),
    )
    .await;
    assert_eq!(ok(&held)["reviewPoi"]["status"], "PENDING");

    let deleted = gql(
        &app,
        Some(&alice),
        r#"mutation { deleteAccount(confirm: "DELETE") }"#,
        json!({}),
    )
    .await;
    assert_eq!(ok(&deleted)["deleteAccount"], true);

    let shown = card(&app, None, bakery).await;
    let node = &shown["reviews"]["nodes"][0];
    assert_eq!(node["text"], text, "a published review stays (CC BY 4.0)");
    assert_eq!(
        (node["authorId"].clone(), node["authorName"].clone()),
        (Value::Null, Value::Null),
        "without its author: the app shows Deleted account"
    );
    assert_eq!(shown["ratings"][0]["count"], 1);
    assert_eq!(
        card(&app, None, shop).await["ratings"],
        json!([]),
        "a rating alone goes with the account"
    );
    let left = sqlx::query!(
        r#"SELECT (SELECT count(*) FROM poi_reviews WHERE account_id = $1) AS "own!",
                  (SELECT count(*) FROM poi_reviews) AS "all!",
                  (SELECT count(*) FROM moderation_queue WHERE target_type = 'poi_review') AS "queued!""#,
        alice_id
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        (left.own, left.all, left.queued),
        (0, 1, 0),
        "only the published review stays; the held one and its queue entry go"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_ban_takes_the_texts_and_the_stars_of_points_away(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let bakery = point_named(&pool, "Maison Bochard").await;
    let (spammer, spammer_id) = sign_in(&app, &Device::new(1)).await;
    ok(&gql(
        &app,
        Some(&spammer),
        REVIEW,
        json!({"id": bakery, "stars": 1, "text": "Fuyez, allez plutôt chez le concurrent."}),
    )
    .await);
    lunaway_db::accounts::ban(&pool, spammer_id, "spam")
        .await
        .unwrap()
        .unwrap();
    let shown = card(&app, None, bakery).await;
    assert_eq!(shown["reviews"]["totalCount"], 0);
    assert_eq!(
        shown["ratings"],
        json!([]),
        "a banned account's stars stop counting"
    );
    let kept = sqlx::query!(
        "SELECT body, visited_on FROM poi_reviews WHERE account_id = $1",
        spammer_id
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        (kept.body, kept.visited_on),
        (None, None),
        "its text and the day of its visit are deleted at the ban"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_text_pasted_on_another_point_or_a_place_waits_for_a_moderator(pool: PgPool) {
    crate::community::seeded(&pool).await;
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let bakery = point_named(&pool, "Maison Bochard").await;
    let shop = point_named(&pool, "Carrefour Market").await;
    let place = crate::community::place_named(&pool, "Camping municipal du Port").await;
    let other_place = crate::community::place_named(&pool, "Aire Val-du-Layon").await;
    let review_place = r"
        mutation($id: UUID!, $text: String!) {
          review(placeId: $id, stars: 4, text: $text) { status }
        }";
    let (alice, _) = sign_in(&app, &Device::new(1)).await;
    let (bob, _) = sign_in(&app, &Device::new(2)).await;

    let text = "Accueil chaleureux et prix honnêtes, je reviendrai.";
    let first = gql(
        &app,
        Some(&alice),
        REVIEW,
        json!({"id": bakery, "stars": 5, "text": text}),
    )
    .await;
    assert_eq!(ok(&first)["reviewPoi"]["status"], "PUBLISHED");
    let pasted = gql(
        &app,
        Some(&alice),
        REVIEW,
        json!({"id": shop, "stars": 5, "text": text}),
    )
    .await;
    assert_eq!(
        ok(&pasted)["reviewPoi"]["status"],
        "PENDING",
        "the same text on a second point"
    );
    let on_a_place = gql(
        &app,
        Some(&alice),
        review_place,
        json!({"id": place, "text": text}),
    )
    .await;
    assert_eq!(
        ok(&on_a_place)["review"]["status"],
        "PENDING",
        "the text of a point pasted on a place"
    );

    let bob_text = "Emplacements plats et calmes, bornes en état.";
    let on_bob_place = gql(
        &app,
        Some(&bob),
        review_place,
        json!({"id": other_place, "text": bob_text}),
    )
    .await;
    assert_eq!(ok(&on_bob_place)["review"]["status"], "PUBLISHED");
    let on_a_point = gql(
        &app,
        Some(&bob),
        REVIEW,
        json!({"id": bakery, "stars": 4, "text": bob_text}),
    )
    .await;
    assert_eq!(
        ok(&on_a_point)["reviewPoi"]["status"],
        "PENDING",
        "the text of a place pasted on a point"
    );
    let reasons: Vec<String> = sqlx::query_scalar!(
        "SELECT reason FROM moderation_queue WHERE kind = 'held_review' ORDER BY created_at"
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    assert_eq!(reasons, ["repetition", "repetition", "repetition"]);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_point_s_reviews_come_by_pages_without_the_authors_the_reader_muted(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let bakery = point_named(&pool, "Maison Bochard").await;
    let texts = [
        "Baguette croustillante, file d'attente le dimanche.",
        "Viennoiseries au beurre, un peu chères.",
        "Ouvert tôt, pratique avant la route.",
    ];
    let mut authors = Vec::new();
    for (n, text) in (1..).zip(texts) {
        let (token, id) = sign_in(&app, &Device::new(n)).await;
        ok(&gql(
            &app,
            Some(&token),
            REVIEW,
            json!({"id": bakery, "stars": 4, "text": text}),
        )
        .await);
        authors.push(id);
    }
    let page = r"
        query($id: UUID!, $after: String) {
          poi(id: $id) {
            reviews(first: 2, after: $after) {
              nodes { text authorId } totalCount hasNextPage endCursor
            }
          }
        }";
    let first = gql(&app, None, page, json!({"id": bakery})).await;
    let first = &ok(&first)["poi"]["reviews"];
    assert_eq!(first["totalCount"], 3);
    assert_eq!(first["hasNextPage"], true);
    assert_eq!(
        first["nodes"]
            .as_array()
            .unwrap()
            .iter()
            .map(|n| n["text"].as_str().unwrap())
            .collect::<Vec<_>>(),
        [texts[2], texts[1]],
        "newest first"
    );
    let next = gql(
        &app,
        None,
        page,
        json!({"id": bakery, "after": first["endCursor"]}),
    )
    .await;
    let next = &ok(&next)["poi"]["reviews"];
    assert_eq!(next["nodes"][0]["text"], texts[0]);
    assert_eq!(next["hasNextPage"], false);

    let (reader, _) = sign_in(&app, &Device::new(9)).await;
    ok(&gql(
        &app,
        Some(&reader),
        "mutation($id: UUID!) { muteAuthor(accountId: $id) }",
        json!({"id": authors[0]}),
    )
    .await);
    let seen = gql(&app, Some(&reader), page, json!({"id": bakery})).await;
    let seen = &ok(&seen)["poi"]["reviews"];
    assert_eq!(
        seen["totalCount"], 2,
        "the muted author's review is left out"
    );
    assert!(
        seen["nodes"]
            .as_array()
            .unwrap()
            .iter()
            .all(|n| n["authorId"] != authors[0].to_string())
    );

    let too_long = gql(
        &app,
        None,
        "query($id: UUID!) { poi(id: $id) { reviews(first: 51) { totalCount } } }",
        json!({"id": bakery}),
    )
    .await;
    assert_eq!(
        code(&too_long),
        "INVALID_INPUT",
        "50 reviews a page at most"
    );
    let every_point = gql(
        &app,
        None,
        r"{ pois(bbox: {south: 45.9, west: 5.3, north: 46.0, east: 5.4}, first: 20) {
              nodes { reviews { totalCount } } } }",
        json!({}),
    )
    .await;
    assert!(
        every_point.get("errors").is_some(),
        "a query per point is for its card, not for a list: {every_point}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_review_of_a_point_needs_level_one_and_a_rating_level_zero(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let mut strict = config(media.path());
    strict.trust = Thresholds::default();
    let app = app(&pool, strict);
    let bakery = point_named(&pool, "Maison Bochard").await;
    let (newcomer, _) = sign_in(&app, &Device::new(1)).await;
    let refused = gql(
        &app,
        Some(&newcomer),
        REVIEW,
        json!({"id": bakery, "stars": 5, "text": "Très bonne boulangerie du centre."}),
    )
    .await;
    assert_eq!(code(&refused), "FORBIDDEN");
    assert_eq!(refused["errors"][0]["extensions"]["requiredLevel"], 1);
    assert_eq!(refused["errors"][0]["extensions"]["level"], 0);
    let rated = gql(
        &app,
        Some(&newcomer),
        RATE,
        json!({"id": bakery, "stars": 5}),
    )
    .await;
    assert_eq!(ok(&rated)["ratePoi"]["status"], "PUBLISHED");
    let anonymous = gql(&app, None, RATE, json!({"id": bakery, "stars": 5})).await;
    assert_eq!(code(&anonymous), "UNAUTHENTICATED");
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_unknown_gone_or_hidden_point_cannot_be_rated(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (alice, _) = sign_in(&app, &Device::new(1)).await;
    let text = "Une adresse que je recommande sans hésiter.";
    let unknown = Uuid::now_v7();
    let gone = point_named(&pool, "Maison Bochard").await;
    let hidden = point_named(&pool, "Carrefour Market").await;
    sqlx::query!("UPDATE pois SET deleted_at = now() WHERE id = $1", gone)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query!("UPDATE pois SET hidden = true WHERE id = $1", hidden)
        .execute(&pool)
        .await
        .unwrap();
    for poi in [unknown, gone, hidden] {
        let rated = gql(&app, Some(&alice), RATE, json!({"id": poi, "stars": 4})).await;
        assert_eq!(code(&rated), "NOT_FOUND", "{poi}: {rated}");
        let reviewed = gql(
            &app,
            Some(&alice),
            REVIEW,
            json!({"id": poi, "stars": 4, "text": text}),
        )
        .await;
        assert_eq!(code(&reviewed), "NOT_FOUND", "{poi}: {reviewed}");
    }
    let stored: i64 = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM poi_reviews"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(stored, 0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_care_practice_takes_no_rating_nor_review(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (alice, _) = sign_in(&app, &Device::new(1)).await;
    let bakery = point_named(&pool, "Maison Bochard").await;
    let practice = point_named(&pool, "Carrefour Market").await;
    sqlx::query!(
        r#"UPDATE pois SET kind = 'doctor', category = 'health', name = 'Dr Martin',
                  data = jsonb_set(data, '{kind}', '"doctor"') WHERE id = $1"#,
        practice
    )
    .execute(&pool)
    .await
    .unwrap();
    let rated = gql(
        &app,
        Some(&alice),
        RATE,
        json!({"id": practice, "stars": 4}),
    )
    .await;
    assert_eq!(code(&rated), "INVALID_INPUT", "{rated}");
    let reviewed = gql(
        &app,
        Some(&alice),
        REVIEW,
        json!({"id": practice, "stars": 2, "text": "Consultation rapide, ordonnance claire."}),
    )
    .await;
    assert_eq!(
        code(&reviewed),
        "INVALID_INPUT",
        "a review of a doctor says its author's health, published under CC BY: {reviewed}"
    );
    let takes = "query($id: UUID!) { poi(id: $id) { takesReviews } }";
    assert_eq!(
        ok(&gql(&app, None, takes, json!({"id": practice})).await)["poi"]["takesReviews"],
        false,
        "the card offers no rating for it"
    );
    assert_eq!(
        ok(&gql(&app, None, takes, json!({"id": bakery})).await)["poi"]["takesReviews"],
        true
    );
    let stored: i64 = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM poi_reviews"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(stored, 0);
}

/// A writer the test reads back, for the statements the API ran.
#[derive(Clone, Default)]
struct Captured(std::sync::Arc<std::sync::Mutex<Vec<u8>>>);

impl std::io::Write for Captured {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.0.lock().unwrap().extend_from_slice(buf);
        Ok(buf.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_ratings_of_a_list_of_points_cost_one_query(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (alice, _) = sign_in(&app, &Device::new(1)).await;
    let rated = [
        ("Maison Bochard", 5),
        ("Carrefour Market", 3),
        ("Pharmacie du Champ de Mars", 4),
    ];
    for (name, stars) in rated {
        let poi = point_named(&pool, name).await;
        ok(&gql(&app, Some(&alice), RATE, json!({"id": poi, "stars": stars})).await);
    }

    let captured = Captured::default();
    let writer = captured.clone();
    let subscriber = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::DEBUG)
        .with_writer(move || writer.clone())
        .with_ansi(false)
        .finish();
    let guard = tracing::subscriber::set_default(subscriber);
    let body = gql(
        &app,
        None,
        r"{ pois(bbox: {south: 45.9, west: 5.3, north: 46.0, east: 5.4}, first: 100) {
              nodes { name ratings { sourceId average count } } } }",
        json!({}),
    )
    .await;
    drop(guard);

    let nodes = ok(&body)["pois"]["nodes"].as_array().unwrap();
    assert!(nodes.len() > rated.len(), "{body}");
    for (name, stars) in rated {
        let node = nodes.iter().find(|n| n["name"] == name).unwrap();
        assert_eq!(
            node["ratings"],
            json!([{"sourceId": "community-cc-by", "average": f64::from(stars), "count": 1}]),
            "{name}"
        );
    }
    assert!(
        nodes
            .iter()
            .filter(|n| !rated.iter().any(|(r, _)| n["name"] == *r))
            .all(|n| n["ratings"] == json!([])),
        "a point nobody rated has no rating"
    );
    // sqlx logs each statement it runs, with its text: the grouping is the
    // ratings' statement alone.
    let logs = String::from_utf8(captured.0.lock().unwrap().clone()).unwrap();
    assert_eq!(
        logs.matches("GROUP BY r.poi_id").count(),
        1,
        "the {} points' ratings are read in one statement, not one per point",
        nodes.len()
    );
}
