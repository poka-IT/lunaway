//! Merging one account into another (`mergeAccount`), as the app does when
//! a person imports an account on a device that holds another: what moves,
//! which side wins a conflict, what the merge needs as proof, what it
//! refuses, the other devices of the merged account, and the journal that
//! makes a restored backup merge it again.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::Utc;
use lunaway_api::ApiConfig;
use lunaway_auth::DevicePublicKey;
use lunaway_db::{
    PgPool,
    deletions::{self, DeletionJournal},
};
use lunaway_domain::community::trust::Thresholds;
use serde_json::{Value, json};
use uuid::Uuid;

use crate::{
    community::{
        Device, REVIEW, app, challenge, code, config, gql, ok, place_named, seeded, sign_in,
    },
    home::{my_home, set_home_query, town_hall},
};

const MERGE: &str = r"
mutation($jwk: String!, $nonce: String!, $asig: String!, $sig: String!) {
  mergeAccount(absorbedKeyJwk: $jwk, nonce: $nonce, absorbedSignature: $asig, signature: $sig) {
    home
    account { id pseudonym trustLevel nextLevel { level missing { kind current needed } } }
  }
}";

fn thumbprint(device: &Device) -> String {
    DevicePublicKey::from_jwk_json(&device.jwk())
        .unwrap()
        .thumbprint()
}

/// What both keys sign to merge `absorbed`'s account into `into`'s.
fn message(nonce: &str, absorbed: &Device, into: &Device) -> String {
    lunaway_auth::merge_message(nonce, &thumbprint(absorbed), &thumbprint(into))
}

/// Merges the account of `absorbed` into the account of `into`, signed in
/// as `token`, both keys signing as the app does.
async fn merge(app: &axum::Router, token: &str, absorbed: &Device, into: &Device) -> Value {
    let (nonce, _) = challenge(app).await;
    let m = message(&nonce, absorbed, into);
    gql(
        app,
        Some(token),
        MERGE,
        json!({"jwk": absorbed.jwk(), "nonce": nonce, "asig": absorbed.sign(&m), "sig": into.sign(&m)}),
    )
    .await
}

async fn exists(pool: &PgPool, id: Uuid) -> bool {
    lunaway_db::accounts::account(pool, id)
        .await
        .unwrap()
        .is_some()
}

async fn create_list(app: &axum::Router, token: &str, name: &str) -> String {
    let body = gql(
        app,
        Some(token),
        "mutation($n: String!) { createList(name: $n) { id } }",
        json!({"n": name}),
    )
    .await;
    ok(&body)["createList"]["id"].as_str().unwrap().to_owned()
}

async fn save(app: &axum::Router, token: &str, list: &str, place: Uuid) {
    let body = gql(
        app,
        Some(token),
        "mutation($l: UUID!, $p: UUID!) { saveToList(listId: $l, placeId: $p) { id } }",
        json!({"l": list, "p": place}),
    )
    .await;
    ok(&body);
}

async fn rate(app: &axum::Router, token: &str, place: Uuid, stars: u8) {
    let body = gql(
        app,
        Some(token),
        "mutation($id: UUID!, $s: Int!) { rate(placeId: $id, stars: $s) { id } }",
        json!({"id": place, "s": stars}),
    )
    .await;
    ok(&body);
}

async fn mute(app: &axum::Router, token: &str, author: Uuid) {
    let body = gql(
        app,
        Some(token),
        "mutation($id: UUID!) { muteAuthor(accountId: $id) }",
        json!({"id": author}),
    )
    .await;
    ok(&body);
}

async fn muted(app: &axum::Router, token: &str) -> Vec<String> {
    let body = gql(
        app,
        Some(token),
        "{ myAccount { mutedAuthors { id } } }",
        json!({}),
    )
    .await;
    ok(&body)["myAccount"]["mutedAuthors"]
        .as_array()
        .unwrap()
        .iter()
        .map(|a| a["id"].as_str().unwrap().to_owned())
        .collect()
}

/// A live place of the fixture other than `except`.
async fn another_place(pool: &PgPool, except: &[Uuid]) -> Uuid {
    sqlx::query_scalar!(
        "SELECT id FROM places WHERE deleted_at IS NULL AND id <> ALL($1) ORDER BY id LIMIT 1",
        except
    )
    .fetch_one(pool)
    .await
    .unwrap()
}

/// Level 1 at once, level 2 at three contributions: two accounts of two
/// contributions each are level 1, their merged history would be level 2.
fn merging_config(media: &std::path::Path) -> ApiConfig {
    let mut c = config(media);
    c.trust = Thresholds {
        tl1_min_age_days: 0,
        tl1_min_confirmations: 0,
        tl2_min_age_days: 0,
        tl2_min_contributions: 3,
        ..Thresholds::default()
    };
    c
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_merge_moves_everything_into_the_imported_account_and_deletes_the_other(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, merging_config(media.path()));
    let p = place_named(&pool, "Aire Val-du-Layon").await;
    let q = place_named(&pool, "Camping municipal du Port").await;
    let r = another_place(&pool, &[p, q]).await;

    let (old_phone, new_phone, neighbour) = (Device::new(1), Device::new(2), Device::new(3));
    let (current, current_id) = sign_in(&app, &old_phone).await;
    let (imported, imported_id) = sign_in(&app, &new_phone).await;
    let (other, other_id) = sign_in(&app, &neighbour).await;

    // The account on the device: its default list, another list, a home,
    // two ratings, a mute; and an author who muted it.
    let default = create_list(&app, &current, "Mes favoris").await;
    save(&app, &current, &default, q).await;
    let trip = create_list(&app, &current, "Bretagne 2027").await;
    save(&app, &current, &trip, p).await;
    gql(
        &app,
        Some(&current),
        &set_home_query(),
        json!({"h": town_hall()}),
    )
    .await;
    rate(&app, &current, p, 2).await;
    rate(&app, &current, q, 5).await;
    mute(&app, &current, other_id).await;
    mute(&app, &other, current_id).await;

    // The account imported: its default list in English, a review of the
    // same place, a rating elsewhere.
    let mine = create_list(&app, &imported, "My favourites").await;
    save(&app, &imported, &mine, r).await;
    let reviewed = gql(
        &app,
        Some(&imported),
        REVIEW,
        json!({"id": p, "text": "Calme la nuit, quai propre."}),
    )
    .await;
    ok(&reviewed);
    rate(&app, &imported, r, 4).await;
    let before = gql(
        &app,
        Some(&imported),
        "{ myAccount { trustLevel } }",
        json!({}),
    )
    .await;
    assert_eq!(ok(&before)["myAccount"]["trustLevel"], 1);
    let pseudonym: String =
        sqlx::query_scalar!("SELECT pseudonym FROM accounts WHERE id = $1", imported_id)
            .fetch_one(&pool)
            .await
            .unwrap();

    let merged = merge(&app, &imported, &old_phone, &new_phone).await;
    let result = &ok(&merged)["mergeAccount"];
    assert_eq!(result["account"]["id"], imported_id.to_string());
    assert_eq!(result["account"]["pseudonym"], pseudonym.as_str());
    assert_eq!(
        result["home"], "MOVED",
        "the imported account had no home: the other's became its own"
    );
    assert!(
        !exists(&pool, current_id).await,
        "the merged account is deleted"
    );

    // Lists: the two default lists are one, the other list changed owner.
    let lists = gql(
        &app,
        Some(&imported),
        "{ myFavoriteLists { name places { placeId } } }",
        json!({}),
    )
    .await;
    let lists = ok(&lists)["myFavoriteLists"].as_array().unwrap().clone();
    let names: Vec<&str> = lists.iter().map(|l| l["name"].as_str().unwrap()).collect();
    assert_eq!(names, ["Bretagne 2027", "My favourites"]);
    let places_of = |name: &str| -> Vec<String> {
        let mut v: Vec<String> = lists.iter().find(|l| l["name"] == name).unwrap()["places"]
            .as_array()
            .unwrap()
            .iter()
            .map(|p| p["placeId"].as_str().unwrap().to_owned())
            .collect();
        v.sort();
        v
    };
    let mut both = vec![q.to_string(), r.to_string()];
    both.sort();
    assert_eq!(places_of("My favourites"), both);
    assert_eq!(places_of("Bretagne 2027"), [p.to_string()]);
    assert_eq!(my_home(&app, &imported).await["name"], "Hôtel de ville");

    // Contributions: the imported account's review of the shared place
    // stays, alone; the other rating changed author.
    let on_p = sqlx::query!(
        r#"SELECT account_id, body FROM reviews WHERE place_id = $1"#,
        p
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    assert_eq!(on_p.len(), 1, "one review per account and place");
    assert_eq!(on_p[0].account_id, Some(imported_id));
    assert_eq!(on_p[0].body.as_deref(), Some("Calme la nuit, quai propre."));
    let on_q: Option<Uuid> =
        sqlx::query_scalar!("SELECT account_id FROM reviews WHERE place_id = $1", q)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        on_q,
        Some(imported_id),
        "the rating now shows the imported pseudonym"
    );

    // Mutes both ways.
    assert_eq!(muted(&app, &imported).await, [other_id.to_string()]);
    assert_eq!(
        muted(&app, &other).await,
        [imported_id.to_string()],
        "an author muted stays muted under the account it went into"
    );

    // The other devices of the merged account: no session, and a sign-in
    // that says where the account went, creating nothing.
    let gone = gql(&app, Some(&current), "{ myAccount { id } }", json!({})).await;
    assert_eq!(code(&gone), "UNAUTHENTICATED");
    let (nonce, challenge_message) = challenge(&app).await;
    let again = gql(
        &app,
        None,
        "mutation($jwk: String!, $nonce: String!, $sig: String!) {
          signIn(publicKeyJwk: $jwk, nonce: $nonce, signature: $sig, createIfUnknown: false) { created }
        }",
        json!({"jwk": old_phone.jwk(), "nonce": nonce, "sig": old_phone.sign(&challenge_message)}),
    )
    .await;
    assert_eq!(code(&again), "NOT_FOUND");
    let extensions = &again["errors"][0]["extensions"];
    assert_eq!(
        extensions["reason"], "UNKNOWN_KEY",
        "an app older than merges forgets the account as a deleted one"
    );
    assert_eq!(extensions["mergedInto"], pseudonym.as_str());

    // The level: the merged history would make level 2; the merge alone
    // never raises it, the next contribution does.
    assert_eq!(result["account"]["trustLevel"], 1);
    assert_eq!(result["account"]["nextLevel"]["level"], 2);
    assert_eq!(
        result["account"]["nextLevel"]["missing"],
        json!([{"kind": "CONTRIBUTIONS", "current": 3, "needed": 4}])
    );
    let read = gql(
        &app,
        Some(&imported),
        "{ myAccount { trustLevel } }",
        json!({}),
    )
    .await;
    assert_eq!(
        ok(&read)["myAccount"]["trustLevel"],
        1,
        "reading the account again keeps the ceiling"
    );
    rate(&app, &imported, r, 3).await;
    let after = gql(
        &app,
        Some(&imported),
        "{ myAccount { trustLevel } }",
        json!({}),
    )
    .await;
    assert_eq!(
        ok(&after)["myAccount"]["trustLevel"],
        2,
        "a contribution of its own and the rules count the merged history"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_merge_needs_both_keys_and_a_recent_sign_in(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    // Every attempt below spends the quota, refused or not.
    let mut c = config(media.path());
    c.quotas.merge.count = 100;
    c.quotas.merge_client.count = 100;
    let app = app(&pool, c);
    let (a, b, stranger) = (Device::new(1), Device::new(2), Device::new(3));
    let (a_token, a_id) = sign_in(&app, &a).await;
    let (b_token, b_id) = sign_in(&app, &b).await;
    let send = |nonce: &str, asig: String, sig: String, jwk: String| json!({"jwk": jwk, "nonce": nonce, "asig": asig, "sig": sig});

    // The absorbed account's signature by a key that is not its own.
    let (nonce, _) = challenge(&app).await;
    let m = message(&nonce, &a, &b);
    let forged = gql(
        &app,
        Some(&b_token),
        MERGE,
        send(&nonce, stranger.sign(&m), b.sign(&m), a.jwk()),
    )
    .await;
    assert_eq!(
        code(&forged),
        "UNAUTHENTICATED",
        "a stolen key id alone is not a proof"
    );

    // The session's key did not sign: a stolen bearer token alone.
    let (nonce, _) = challenge(&app).await;
    let m = message(&nonce, &a, &b);
    let token_only = gql(
        &app,
        Some(&b_token),
        MERGE,
        send(&nonce, a.sign(&m), a.sign(&m), a.jwk()),
    )
    .await;
    assert_eq!(code(&token_only), "UNAUTHENTICATED");

    // A sign-in signature replayed as a merge proof.
    let (nonce, sign_in_text) = challenge(&app).await;
    let replayed = gql(
        &app,
        Some(&b_token),
        MERGE,
        send(
            &nonce,
            a.sign(&sign_in_text),
            b.sign(&sign_in_text),
            a.jwk(),
        ),
    )
    .await;
    assert_eq!(code(&replayed), "UNAUTHENTICATED");

    // The direction is signed: a proof to merge B into A does not merge A
    // into B.
    let (nonce, _) = challenge(&app).await;
    let other_way = message(&nonce, &b, &a);
    let turned = gql(
        &app,
        Some(&b_token),
        MERGE,
        send(&nonce, a.sign(&other_way), b.sign(&other_way), a.jwk()),
    )
    .await;
    assert_eq!(code(&turned), "UNAUTHENTICATED");

    // A key of the signed-in account itself.
    let refused = merge(&app, &b_token, &b, &b).await;
    assert_eq!(code(&refused), "INVALID_INPUT");

    // A key no account holds.
    let unknown = merge(&app, &b_token, &stranger, &b).await;
    assert_eq!(code(&unknown), "NOT_FOUND");

    // A nonce answers once.
    let (nonce, _) = challenge(&app).await;
    let m = message(&nonce, &a, &b);
    let vars = send(&nonce, a.sign(&m), b.sign(&m), a.jwk());
    sqlx::query!("UPDATE sessions SET created_at = now() - interval '1 hour'")
        .execute(&pool)
        .await
        .unwrap();
    let stale = gql(&app, Some(&b_token), MERGE, vars.clone()).await;
    assert_eq!(code(&stale), "UNAUTHENTICATED");
    assert_eq!(
        stale["errors"][0]["extensions"]["reason"], "FRESH_SIGN_IN",
        "a session an hour old does not merge: the device signs in again"
    );
    assert!(
        exists(&pool, a_id).await && exists(&pool, b_id).await,
        "nothing merged"
    );

    let (fresh, _) = sign_in(&app, &b).await;
    let done = gql(&app, Some(&fresh), MERGE, vars.clone()).await;
    ok(&done);
    let again = gql(&app, Some(&fresh), MERGE, vars).await;
    assert_eq!(code(&again), "INVALID_INPUT", "the same nonce twice");
    assert!(!exists(&pool, a_id).await);
    let _ = a_token;
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_banned_account_is_never_merged(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (a, b) = (Device::new(1), Device::new(2));
    let (_, a_id) = sign_in(&app, &a).await;
    let (b_token, b_id) = sign_in(&app, &b).await;
    lunaway_db::accounts::ban(&pool, a_id, "spam, ticket 9")
        .await
        .unwrap()
        .unwrap();
    let refused = merge(&app, &b_token, &a, &b).await;
    assert_eq!(
        code(&refused),
        "FORBIDDEN",
        "a merge must not wash a ban away"
    );
    let banned: bool = sqlx::query_scalar!(
        r#"SELECT banned_at IS NOT NULL AS "b!" FROM accounts WHERE id = $1"#,
        a_id
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(banned, "the banned account stays as it was");

    // Into a banned account: its session no longer opens anything, and the
    // repository refuses it too.
    assert_eq!(
        lunaway_db::merge::merge_accounts(&pool, b_id, a_id)
            .await
            .unwrap(),
        Err(lunaway_db::merge::MergeRefusal::Banned)
    );
    assert!(exists(&pool, b_id).await);
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_imported_account_keeps_its_home(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (a, b) = (Device::new(1), Device::new(2));
    let (a_token, _) = sign_in(&app, &a).await;
    let (b_token, _) = sign_in(&app, &b).await;
    gql(
        &app,
        Some(&a_token),
        &set_home_query(),
        json!({"h": town_hall()}),
    )
    .await;
    let mut harbour = town_hall();
    harbour["name"] = json!("Capitainerie");
    harbour["address"] = json!("Quai de la Tournette, 74000 Annecy");
    gql(
        &app,
        Some(&b_token),
        &set_home_query(),
        json!({"h": harbour}),
    )
    .await;

    let merged = merge(&app, &b_token, &a, &b).await;
    assert_eq!(ok(&merged)["mergeAccount"]["home"], "KEPT");
    assert_eq!(my_home(&app, &b_token).await["name"], "Capitainerie");
    let homes: i64 = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM favorite_homes"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(homes, 1, "the merged account's home went with it");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_merge_asked_again_after_its_answer_was_lost_answers_the_same(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (a, b, c) = (Device::new(1), Device::new(2), Device::new(3));
    sign_in(&app, &a).await;
    let (b_token, b_id) = sign_in(&app, &b).await;
    let (c_token, _) = sign_in(&app, &c).await;
    ok(&merge(&app, &b_token, &a, &b).await);
    let again = merge(&app, &b_token, &a, &b).await;
    assert_eq!(
        ok(&again)["mergeAccount"]["account"]["id"],
        b_id.to_string(),
        "the device retrying after a lost answer finds the merge made"
    );
    let elsewhere = merge(&app, &c_token, &a, &c).await;
    assert_eq!(
        code(&elsewhere),
        "NOT_FOUND",
        "a key merged into one account proves nothing for another"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn merges_are_limited_per_account(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let mut c = config(media.path());
    c.quotas.merge.count = 1;
    let app = app(&pool, c);
    let (a, b, d) = (Device::new(1), Device::new(2), Device::new(4));
    sign_in(&app, &a).await;
    sign_in(&app, &d).await;
    let (b_token, _) = sign_in(&app, &b).await;
    ok(&merge(&app, &b_token, &a, &b).await);
    let second = merge(&app, &b_token, &d, &b).await;
    assert_eq!(code(&second), "RATE_LIMITED");
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_import_cancelled_detaches_the_new_key(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let phone = Device::new(1);
    let (token, id) = sign_in(&app, &phone).await;
    let forgot = gql(
        &app,
        Some(&token),
        "mutation { signOut(forgetDevice: true) }",
        json!({}),
    )
    .await;
    assert_eq!(ok(&forgot)["signOut"], true);
    let keys: i64 = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM device_keys WHERE account_id = $1"#,
        id
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(keys, 0, "the account no longer lists the device");
    assert!(exists(&pool, id).await, "the account itself stays");
}

fn journaled(media: &std::path::Path, journal: &std::path::Path) -> ApiConfig {
    let mut c = config(media);
    c.keeping.deletion_journal = Some(journal.to_path_buf());
    c
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_merge_is_journaled_and_made_again_after_a_restore(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let journal_dir = dir.path().join("account-deletions");
    let app = app(&pool, journaled(media.path(), &journal_dir));
    let journal = DeletionJournal::new(&journal_dir);
    let place = place_named(&pool, "Camping municipal du Port").await;

    let (a, b) = (Device::new(1), Device::new(2));
    let (_, a_id) = sign_in(&app, &a).await;
    let (b_token, b_id) = sign_in(&app, &b).await;
    ok(&merge(&app, &b_token, &a, &b).await);
    let read = journal.read().unwrap();
    assert_eq!(
        read.entries
            .iter()
            .map(|e| (e.account, e.merged_into))
            .collect::<Vec<_>>(),
        [(a_id, Some(b_id))],
        "the merge is in the journal, outside the database, with where it went"
    );

    // A backup taken before a second merge is restored: the database holds
    // both accounts again, with what the merged one held; the journal says
    // it went into the other.
    let (c, d) = (Device::new(3), Device::new(4));
    let (c_token, c_id) = sign_in(&app, &c).await;
    let (_, d_id) = sign_in(&app, &d).await;
    let trip = create_list(&app, &c_token, "Été 2027").await;
    save(&app, &c_token, &trip, place).await;
    gql(
        &app,
        Some(&c_token),
        &set_home_query(),
        json!({"h": town_hall()}),
    )
    .await;
    rate(&app, &c_token, place, 4).await;
    journal.record_merge(c_id, d_id, Utc::now()).await.unwrap();
    // And one merged into an account deleted since: deleted, as the merge
    // deleted it.
    let (e, f) = (Device::new(5), Device::new(6));
    let (_, e_id) = sign_in(&app, &e).await;
    let (_, f_id) = sign_in(&app, &f).await;
    journal.record_merge(e_id, f_id, Utc::now()).await.unwrap();
    lunaway_db::deletions::delete_recorded(&pool, Some(&journal), f_id)
        .await
        .unwrap();

    let replayed = deletions::replay(&pool, &journal, false, false)
        .await
        .unwrap();
    assert_eq!(
        (replayed.accounts, replayed.deleted, replayed.merged),
        (4, 2, 1),
        "the four accounts named; the merged one already gone, the deleted one too"
    );
    assert!(
        !exists(&pool, c_id).await,
        "a restore never brings a merged account back"
    );
    assert!(!exists(&pool, e_id).await);
    let lists: Vec<String> = sqlx::query_scalar!(
        "SELECT name FROM favorite_lists WHERE account_id = $1",
        d_id
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    assert_eq!(
        lists,
        ["Été 2027"],
        "the replay merges again rather than delete"
    );
    let rating: Option<Uuid> =
        sqlx::query_scalar!("SELECT account_id FROM reviews WHERE place_id = $1", place)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(rating, Some(d_id));
    let home: i64 = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM favorite_homes WHERE account_id = $1"#,
        d_id
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(home, 1);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_merge_that_cannot_be_journaled_is_refused(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let blocked = dir.path().join("not-a-directory");
    std::fs::write(&blocked, "x").unwrap();
    let app = app(&pool, journaled(media.path(), &blocked));
    let (a, b) = (Device::new(1), Device::new(2));
    let (_, a_id) = sign_in(&app, &a).await;
    let (b_token, _) = sign_in(&app, &b).await;
    let refused = merge(&app, &b_token, &a, &b).await;
    assert_eq!(code(&refused), "UNAVAILABLE");
    assert!(
        exists(&pool, a_id).await,
        "a merge missing from the journal would come back with a restore: none is made"
    );
}
