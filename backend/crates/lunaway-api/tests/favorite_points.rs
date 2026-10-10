//! Points saved in a favourite list outside the places of the data (an
//! address, a town, a bare point of the map, a shop), as the app syncs
//! them: saved, updated by the last write, removed, imported with a
//! device's lists, bounded, private to their account and erased with it.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use lunaway_db::PgPool;
use serde_json::{Value, json};
use uuid::Uuid;

use crate::community::{Device, app, code, config, gql, ok, sign_in};

const POINT_FIELDS: &str = "id kind name note address lat lon poiId poiKind addedAt updatedAt";

fn save_query() -> String {
    format!(
        "mutation($l: UUID!, $p: FavoritePointInput!) {{ savePointToList(listId: $l, point: $p) {{ updatedAt points {{ {POINT_FIELDS} }} }} }}"
    )
}

const REMOVE: &str = "mutation($l: UUID!, $p: UUID!) { removePointFromList(listId: $l, pointId: $p) { points { id } } }";

fn mine_query() -> String {
    format!("{{ myFavoriteLists {{ id name updatedAt points {{ {POINT_FIELDS} }} }} }}")
}

/// An address saved from the search: a ministry, never someone's home.
fn address(id: Uuid) -> Value {
    json!({
        "id": id,
        "kind": "ADDRESS",
        "name": "20 Avenue de Ségur",
        "address": "20 Avenue de Ségur, 75007 Paris",
        "lat": 48.8507,
        "lon": 2.3094,
    })
}

async fn new_list(app: &axum::Router, token: &str, name: &str) -> String {
    let created = gql(
        app,
        Some(token),
        "mutation($n: String!) { createList(name: $n) { id } }",
        json!({"n": name}),
    )
    .await;
    ok(&created)["createList"]["id"]
        .as_str()
        .unwrap()
        .to_owned()
}

async fn mine(app: &axum::Router, token: &str) -> Value {
    let body = gql(app, Some(token), &mine_query(), json!({})).await;
    ok(&body)["myFavoriteLists"].clone()
}

async fn point_rows(pool: &PgPool) -> i64 {
    sqlx::query_scalar::<_, i64>("SELECT count(*) FROM favorite_points")
        .fetch_one(pool)
        .await
        .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_point_is_saved_updated_by_the_last_write_and_removed(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (token, _) = sign_in(&app, &Device::new(1)).await;
    let list = new_list(&app, &token, "Bretagne 2027").await;
    let id = Uuid::now_v7();

    let saved = gql(
        &app,
        Some(&token),
        &save_query(),
        json!({"l": list, "p": address(id)}),
    )
    .await;
    let point = &ok(&saved)["savePointToList"]["points"][0];
    assert_eq!(point["id"], id.to_string());
    assert_eq!(point["kind"], "ADDRESS");
    assert_eq!(point["name"], "20 Avenue de Ségur");
    assert_eq!(point["note"], Value::Null);
    assert_eq!(point["address"], "20 Avenue de Ségur, 75007 Paris");
    assert_eq!(point["lat"], 48.8507);
    assert_eq!(point["lon"], 2.3094);
    assert_eq!(point["poiId"], Value::Null);
    let added_at = point["addedAt"].clone();

    // The same content again changes nothing, not even the list's date.
    let list_date = ok(&saved)["savePointToList"]["updatedAt"].clone();
    let again = gql(
        &app,
        Some(&token),
        &save_query(),
        json!({"l": list, "p": address(id)}),
    )
    .await;
    assert_eq!(
        ok(&again)["savePointToList"]["updatedAt"],
        list_date,
        "a save that changes nothing leaves the list as it was"
    );

    let mut renamed = address(id);
    renamed["name"] = json!("  Le  ministère ");
    renamed["note"] = json!("Entrée côté\r\nplace de Fontenoy");
    let updated = gql(
        &app,
        Some(&token),
        &save_query(),
        json!({"l": list, "p": renamed}),
    )
    .await;
    let points = ok(&updated)["savePointToList"]["points"]
        .as_array()
        .unwrap();
    assert_eq!(points.len(), 1, "the same id updates the point");
    assert_eq!(points[0]["name"], "Le ministère");
    assert_eq!(points[0]["note"], "Entrée côté\nplace de Fontenoy");
    assert_eq!(
        points[0]["addedAt"], added_at,
        "an update keeps when the point was added"
    );

    let lists = mine(&app, &token).await;
    assert_eq!(lists[0]["points"][0]["name"], "Le ministère");

    let removed = gql(&app, Some(&token), REMOVE, json!({"l": list, "p": id})).await;
    assert!(
        ok(&removed)["removePointFromList"]["points"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    let twice = gql(&app, Some(&token), REMOVE, json!({"l": list, "p": id})).await;
    assert!(
        ok(&twice)["removePointFromList"]["points"]
            .as_array()
            .unwrap()
            .is_empty(),
        "a point already gone is removed"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_shop_keeps_its_point_of_interest(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (token, _) = sign_in(&app, &Device::new(1)).await;
    let list = new_list(&app, &token, "Courses").await;
    let poi = Uuid::now_v7();
    let saved = gql(
        &app,
        Some(&token),
        &save_query(),
        json!({"l": list, "p": {
            "id": Uuid::now_v7(), "kind": "POI", "name": "Boulangerie du port",
            "lat": 47.5, "lon": -2.1, "poiId": poi, "poiKind": "BAKERY",
        }}),
    )
    .await;
    let point = &ok(&saved)["savePointToList"]["points"][0];
    assert_eq!(point["kind"], "POI");
    assert_eq!(point["poiId"], poi.to_string());
    assert_eq!(point["poiKind"], "BAKERY");
}

#[sqlx::test(migrations = "../../migrations")]
async fn another_account_s_list_does_not_exist_for_it(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (owner, _) = sign_in(&app, &Device::new(1)).await;
    let (other, _) = sign_in(&app, &Device::new(2)).await;
    let list = new_list(&app, &owner, "Mes favoris").await;
    let id = Uuid::now_v7();
    gql(
        &app,
        Some(&owner),
        &save_query(),
        json!({"l": list, "p": address(id)}),
    )
    .await;

    let mut changed = address(id);
    changed["name"] = json!("Écrit par un autre");
    let foreign = gql(
        &app,
        Some(&other),
        &save_query(),
        json!({"l": list, "p": changed}),
    )
    .await;
    assert_eq!(code(&foreign), "NOT_FOUND");
    let foreign = gql(&app, Some(&other), REMOVE, json!({"l": list, "p": id})).await;
    assert_eq!(code(&foreign), "NOT_FOUND");
    assert!(
        mine(&app, &other).await.as_array().unwrap().is_empty(),
        "another account reads none of the owner's points"
    );
    let lists = mine(&app, &owner).await;
    assert_eq!(
        lists[0]["points"][0]["name"], "20 Avenue de Ségur",
        "the owner's point is untouched"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_point_is_checked_before_anything_is_written(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (token, _) = sign_in(&app, &Device::new(1)).await;
    let list = new_list(&app, &token, "Mes favoris").await;
    let base = address(Uuid::now_v7());
    let cases: [(&str, Value); 7] = [
        ("an empty name", json!({"name": "   "})),
        ("a name of 121 characters", json!({"name": "é".repeat(121)})),
        ("a note of 281 characters", json!({"note": "a".repeat(281)})),
        ("a direction override", json!({"name": "abc\u{202E}def"})),
        ("a latitude of 91", json!({"lat": 91.0})),
        (
            "a shop without its kind",
            json!({"kind": "POI", "poiId": Uuid::now_v7()}),
        ),
        ("an address naming a shop", json!({"poiId": Uuid::now_v7()})),
    ];
    for (why, patch) in cases {
        let mut point = base.clone();
        for (k, v) in patch.as_object().unwrap() {
            point[k] = v.clone();
        }
        let refused = gql(
            &app,
            Some(&token),
            &save_query(),
            json!({"l": list, "p": point}),
        )
        .await;
        assert_eq!(code(&refused), "INVALID_INPUT", "{why}");
    }
    assert_eq!(point_rows(&pool).await, 0, "nothing refused is written");
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_account_keeps_two_thousand_points_at_most(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (token, _) = sign_in(&app, &Device::new(1)).await;
    let first = new_list(&app, &token, "Une").await;
    let second = new_list(&app, &token, "Deux").await;
    let kept = Uuid::now_v7();
    gql(
        &app,
        Some(&token),
        &save_query(),
        json!({"l": first, "p": address(kept)}),
    )
    .await;
    // The rest of the bound, in the other list: it counts the account.
    sqlx::query(
        "INSERT INTO favorite_points (list_id, id, kind, name, lat, lon)
         SELECT $1, gen_random_uuid(), 'point', 'P' || g, 45, 6 FROM generate_series(1, 1999) g",
    )
    .bind(second.parse::<Uuid>().unwrap())
    .execute(&pool)
    .await
    .unwrap();

    let over = gql(
        &app,
        Some(&token),
        &save_query(),
        json!({"l": first, "p": address(Uuid::now_v7())}),
    )
    .await;
    assert_eq!(code(&over), "INVALID_INPUT");
    assert!(
        over["errors"][0]["message"]
            .as_str()
            .unwrap()
            .contains("2000"),
        "the refusal names the bound: {over}"
    );

    let mut renamed = address(kept);
    renamed["name"] = json!("Toujours là");
    let update = gql(
        &app,
        Some(&token),
        &save_query(),
        json!({"l": first, "p": renamed}),
    )
    .await;
    assert_eq!(
        ok(&update)["savePointToList"]["points"][0]["name"],
        "Toujours là",
        "an update adds nothing to the count"
    );

    let imported = gql(
        &app,
        Some(&token),
        "mutation($lists: [FavoriteListInput!]!) { importFavorites(lists: $lists) { name } }",
        json!({"lists": [{"name": "Trois", "placeIds": [], "points": [address(Uuid::now_v7())]}]}),
    )
    .await;
    assert_eq!(code(&imported), "INVALID_INPUT");
    assert_eq!(point_rows(&pool).await, 2_000, "the import wrote nothing");
    let names: Vec<Value> = mine(&app, &token)
        .await
        .as_array()
        .unwrap()
        .iter()
        .map(|l| l["name"].clone())
        .collect();
    assert!(
        !names.contains(&json!("Trois")),
        "a refused import leaves no list behind"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_device_s_points_are_imported_with_its_lists(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (token, _) = sign_in(&app, &Device::new(1)).await;
    let list = new_list(&app, &token, "Mes favoris").await;
    let shared = Uuid::now_v7();
    gql(
        &app,
        Some(&token),
        &save_query(),
        json!({"l": list, "p": address(shared)}),
    )
    .await;
    let mut device_copy = address(shared);
    device_copy["name"] = json!("Copie de l'appareil");
    let town = json!({"id": Uuid::now_v7(), "kind": "TOWN", "name": "Annecy", "lat": 45.899, "lon": 6.129});
    let here = json!({"id": Uuid::now_v7(), "kind": "POINT", "name": "Point du 10 octobre", "note": "Vue sur le lac", "lat": 45.86, "lon": 6.17});
    let imported = gql(
        &app,
        Some(&token),
        &format!(
            "mutation($lists: [FavoriteListInput!]!) {{ importFavorites(lists: $lists) {{ name points {{ {POINT_FIELDS} }} }} }}"
        ),
        json!({"lists": [
            {"name": "Mes favoris", "placeIds": [], "points": [device_copy, town]},
            {"name": "Alpes", "placeIds": [], "points": [here]},
        ]}),
    )
    .await;
    let lists = ok(&imported)["importFavorites"].as_array().unwrap();
    let main = lists.iter().find(|l| l["name"] == "Mes favoris").unwrap();
    let points = main["points"].as_array().unwrap();
    assert_eq!(points.len(), 2, "merged into the list of the same name");
    let kept = points
        .iter()
        .find(|p| p["id"] == shared.to_string())
        .unwrap();
    assert_eq!(
        kept["name"], "20 Avenue de Ségur",
        "a point the account holds keeps the account's copy"
    );
    assert!(points.iter().any(|p| p["kind"] == "TOWN"));
    let alps = lists.iter().find(|l| l["name"] == "Alpes").unwrap();
    assert_eq!(alps["points"][0]["note"], "Vue sur le lac");

    // A device with a long history imports in several calls. The points
    // are as small as they come: the 64 KB bound of a request body would
    // refuse 501 addresses before this bound does.
    let many: Vec<Value> = (0..501)
        .map(|_| json!({"id": Uuid::now_v7(), "kind": "POINT", "name": "P", "lat": 45, "lon": 6}))
        .collect();
    let too_many = gql(
        &app,
        Some(&token),
        "mutation($lists: [FavoriteListInput!]!) { importFavorites(lists: $lists) { name } }",
        json!({"lists": [{"name": "Gros", "placeIds": [], "points": many}]}),
    )
    .await;
    assert_eq!(code(&too_many), "INVALID_INPUT");
    assert!(
        too_many["errors"][0]["message"]
            .as_str()
            .unwrap()
            .contains("500 points"),
        "the refusal names the bound: {too_many}"
    );

    // A device that predates the points sends its lists without them.
    let without = gql(
        &app,
        Some(&token),
        "mutation($lists: [FavoriteListInput!]!) { importFavorites(lists: $lists) { name } }",
        json!({"lists": [{"name": "Sans points", "placeIds": []}]}),
    )
    .await;
    ok(&without);
}

#[sqlx::test(migrations = "../../migrations")]
async fn points_need_an_account(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let list = Uuid::now_v7();
    let saved = gql(
        &app,
        None,
        &save_query(),
        json!({"l": list, "p": address(Uuid::now_v7())}),
    )
    .await;
    assert_eq!(code(&saved), "UNAUTHENTICATED");
    let removed = gql(&app, None, REMOVE, json!({"l": list, "p": Uuid::now_v7()})).await;
    assert_eq!(code(&removed), "UNAUTHENTICATED");
    let read = gql(&app, None, &mine_query(), json!({})).await;
    assert_eq!(code(&read), "UNAUTHENTICATED");
}

#[sqlx::test(migrations = "../../migrations")]
async fn deleting_the_account_erases_its_points(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (token, _) = sign_in(&app, &Device::new(1)).await;
    let (other, _) = sign_in(&app, &Device::new(2)).await;
    let list = new_list(&app, &token, "Mes favoris").await;
    let theirs = new_list(&app, &other, "Mes favoris").await;
    for (t, l) in [(&token, &list), (&other, &theirs)] {
        gql(
            &app,
            Some(t),
            &save_query(),
            json!({"l": l, "p": address(Uuid::now_v7())}),
        )
        .await;
    }
    assert_eq!(point_rows(&pool).await, 2);
    let deleted = gql(
        &app,
        Some(&token),
        r#"mutation { deleteAccount(confirm: "DELETE") }"#,
        json!({}),
    )
    .await;
    assert_eq!(ok(&deleted)["deleteAccount"], true);
    assert_eq!(
        point_rows(&pool).await,
        1,
        "the account's points go with it, another account's stay"
    );
    assert_eq!(
        mine(&app, &other).await[0]["points"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
}
