//! Idempotency keys under a race: a request whose key another request,
//! still in flight, has just stored waits for it, then answers with what
//! that one made and leaves nothing of its own.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::time::Duration;

use lunaway_db::{
    PgPool, accounts,
    idempotency::{Key, Once, Operation},
    submissions::{self, NewSubmission, Submitted},
};
use lunaway_domain::{
    PlaceKind, Position,
    community::submission::{NewPlace, PlacePatch},
};
use serde_json::json;
use uuid::Uuid;

async fn account(pool: &PgPool) -> (Uuid, Uuid) {
    let (account, _) = accounts::create_with_key(
        pool,
        accounts::NewAccount {
            pseudonym: "Hérisson du Vercors",
            thumbprint: &"t".repeat(43),
            public_key: &[4; 65],
            session_hash: &[1; 32],
            session_ttl_secs: 3_600.0,
        },
    )
    .await
    .unwrap();
    let key = accounts::key_by_thumbprint(pool, &"t".repeat(43))
        .await
        .unwrap()
        .unwrap();
    (account.id, key.id)
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_request_that_loses_the_race_answers_with_the_winner_s_row(pool: PgPool) {
    let (account, device_key) = account(&pool).await;
    let arguments = json!({"name": "Clairière"});
    let key = Key::of(
        account,
        "outbox-entry-race",
        Operation::AddPlace,
        &arguments,
    );
    // The winner: its key is stored, its transaction not yet committed.
    let winner_row = Uuid::now_v7();
    let mut winner = pool.begin().await.unwrap();
    sqlx::query(
        "INSERT INTO idempotency_keys (account_id, key, operation, request_hash, result_id)
         VALUES ($1, $2, 'add_place', $3, $4)",
    )
    .bind(account)
    .bind(key.key)
    .bind(&key.request[..])
    .bind(winner_row)
    .execute(&mut *winner)
    .await
    .unwrap();

    let place = NewPlace {
        kind: PlaceKind::Nature,
        position: Position::new(47.1, -1.0).unwrap(),
        details: PlacePatch {
            name: Some("Clairière".into()),
            ..PlacePatch::default()
        },
    };
    let loser = {
        let pool = pool.clone();
        tokio::spawn(async move {
            let key = Key::of(
                account,
                "outbox-entry-race",
                Operation::AddPlace,
                &arguments,
            );
            submissions::submit_once(
                &pool,
                &key,
                NewSubmission {
                    account,
                    device_key,
                    what: Submitted::Create(&place),
                    accepted: true,
                    held_for: None,
                },
            )
            .await
            .unwrap()
        })
    };
    // The loser has looked the key up (not yet visible), written its row,
    // and now waits on the winner's key: a lock not granted shows it.
    let mut waited = Duration::ZERO;
    loop {
        // Only this test's database: the other tests run beside it.
        let waiting: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM pg_locks WHERE NOT granted AND pid IN
               (SELECT pid FROM pg_stat_activity WHERE datname = current_database())",
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        if waiting > 0 {
            break;
        }
        assert!(
            !loser.is_finished() && waited < Duration::from_secs(10),
            "the second insert of the key waits for the first transaction"
        );
        tokio::time::sleep(Duration::from_millis(20)).await;
        waited += Duration::from_millis(20);
    }
    assert!(!loser.is_finished(), "the second insert of the key waits");
    winner.commit().await.unwrap();
    let answer = loser.await.unwrap();
    assert_eq!(
        answer,
        Once::Replay(winner_row),
        "the request that lost answers with the row the winner made"
    );
    let left: i64 = sqlx::query_scalar("SELECT count(*) FROM place_submissions")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(left, 0, "the loser's own write is rolled back");
}
