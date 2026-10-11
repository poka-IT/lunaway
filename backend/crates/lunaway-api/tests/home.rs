//! The account's home as the app syncs it: set, replaced by the last
//! write, cleared, checked as a saved point is, private to its account and
//! erased with it.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use lunaway_db::PgPool;
use serde_json::{Value, json};
use uuid::Uuid;

use crate::community::{Device, app, code, config, gql, ok, sign_in};

pub(crate) const HOME_FIELDS: &str = "kind name address lat lon poiId poiKind updatedAt";

pub(crate) fn set_home_query() -> String {
    format!("mutation($h: HomeInput!) {{ setHome(home: $h) {{ {HOME_FIELDS} }} }}")
}

pub(crate) fn my_home_query() -> String {
    format!("{{ myHome {{ {HOME_FIELDS} }} }}")
}

/// A public building, never someone's home.
pub(crate) fn town_hall() -> Value {
    json!({
        "kind": "ADDRESS",
        "name": "Hôtel de ville",
        "address": "1 Rue Jean Jaurès, 74000 Annecy",
        "lat": 45.8992,
        "lon": 6.1294,
    })
}

pub(crate) async fn my_home(app: &axum::Router, token: &str) -> Value {
    let body = gql(app, Some(token), &my_home_query(), json!({})).await;
    ok(&body)["myHome"].clone()
}

async fn home_rows(pool: &PgPool) -> i64 {
    sqlx::query_scalar::<_, i64>("SELECT count(*) FROM favorite_homes")
        .fetch_one(pool)
        .await
        .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_home_is_set_replaced_cleared_and_kept_from_others(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (token, _) = sign_in(&app, &Device::new(1)).await;
    let (other, _) = sign_in(&app, &Device::new(2)).await;
    assert_eq!(my_home(&app, &token).await, Value::Null, "no home at first");

    let set = gql(
        &app,
        Some(&token),
        &set_home_query(),
        json!({"h": town_hall()}),
    )
    .await;
    let home = &ok(&set)["setHome"];
    assert_eq!(home["kind"], "ADDRESS");
    assert_eq!(home["name"], "Hôtel de ville");
    assert_eq!(home["address"], "1 Rue Jean Jaurès, 74000 Annecy");
    assert_eq!(home["lat"], 45.8992);
    let first_date = home["updatedAt"].clone();

    let same = gql(
        &app,
        Some(&token),
        &set_home_query(),
        json!({"h": town_hall()}),
    )
    .await;
    assert_eq!(
        ok(&same)["setHome"]["updatedAt"],
        first_date,
        "the same home again changes nothing, not even its date"
    );

    let shop = Uuid::now_v7();
    let replaced = gql(
        &app,
        Some(&token),
        &set_home_query(),
        json!({"h": {"kind": "POI", "name": "  Boulangerie   du port ", "lat": 47.5, "lon": -2.1,
                     "poiId": shop, "poiKind": "BAKERY"}}),
    )
    .await;
    let home = &ok(&replaced)["setHome"];
    assert_eq!(
        home["name"], "Boulangerie du port",
        "named as a saved point is"
    );
    assert_eq!(home["poiId"], shop.to_string());
    assert_eq!(home["address"], Value::Null);
    assert_eq!(home_rows(&pool).await, 1, "one home per account");
    assert_eq!(my_home(&app, &token).await["poiKind"], "BAKERY");

    assert_eq!(
        my_home(&app, &other).await,
        Value::Null,
        "another account never reads it"
    );
    let anonymous = gql(&app, None, &my_home_query(), json!({})).await;
    assert_eq!(code(&anonymous), "UNAUTHENTICATED");

    let cleared = gql(&app, Some(&token), "mutation { clearHome }", json!({})).await;
    assert_eq!(ok(&cleared)["clearHome"], true);
    let twice = gql(&app, Some(&token), "mutation { clearHome }", json!({})).await;
    assert_eq!(
        ok(&twice)["clearHome"],
        false,
        "a home already gone is done"
    );
    assert_eq!(my_home(&app, &token).await, Value::Null);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_home_is_checked_as_a_saved_point(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (token, _) = sign_in(&app, &Device::new(1)).await;
    let mut long = town_hall();
    long["name"] = json!("x".repeat(121));
    let mut off_earth = town_hall();
    off_earth["lat"] = json!(91.0);
    let mut shop_without_point = town_hall();
    shop_without_point["kind"] = json!("POI");
    let mut reversed = town_hall();
    reversed["name"] = json!("Maison \u{202e}");
    for (bad, field) in [
        (long, "name"),
        (off_earth, "lat"),
        (shop_without_point, "poiId"),
        (reversed, "name"),
    ] {
        let refused = gql(&app, Some(&token), &set_home_query(), json!({"h": bad})).await;
        assert_eq!(code(&refused), "INVALID_INPUT", "{field}");
        let message = refused["errors"][0]["message"].as_str().unwrap();
        assert!(
            message.contains(field),
            "the refusal names {field}: {message}"
        );
    }
    assert_eq!(home_rows(&pool).await, 0, "nothing refused is stored");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_home_goes_with_its_account(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (token, _) = sign_in(&app, &Device::new(1)).await;
    gql(
        &app,
        Some(&token),
        &set_home_query(),
        json!({"h": town_hall()}),
    )
    .await;
    assert_eq!(home_rows(&pool).await, 1);
    let deleted = gql(
        &app,
        Some(&token),
        r#"mutation { deleteAccount(confirm: "DELETE") }"#,
        json!({}),
    )
    .await;
    assert_eq!(ok(&deleted)["deleteAccount"], true);
    assert_eq!(
        home_rows(&pool).await,
        0,
        "a deleted account leaves no home behind"
    );
}
