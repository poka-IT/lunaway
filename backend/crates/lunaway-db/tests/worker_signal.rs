//! The signal the API sends the conflation worker.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::time::{Duration, Instant};

use lunaway_db::{
    PgPool,
    community::{MAX_SETTLE, WORK_CHANNEL, WorkListener},
};

#[sqlx::test(migrations = "../../migrations")]
async fn a_steady_stream_of_writes_does_not_keep_the_worker_asleep(pool: PgPool) {
    let mut listener = WorkListener::connect(&pool).await.unwrap();
    let sender = pool.clone();
    let writes = tokio::spawn(async move {
        // A write every 100 ms for 6 s: more than one per settle window.
        for _ in 0..60 {
            sqlx::query("SELECT pg_notify($1, '')")
                .bind(WORK_CHANNEL)
                .execute(&sender)
                .await
                .unwrap();
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    });
    let started = Instant::now();
    let woken = listener
        .wait(Duration::from_secs(60), Duration::from_millis(300))
        .await
        .unwrap();
    let took = started.elapsed();
    writes.abort();
    assert!(woken);
    assert!(
        took < MAX_SETTLE + Duration::from_secs(1),
        "the worker runs within its settle bound even while writes keep coming: {took:?}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn without_a_signal_the_worker_waits_its_period(pool: PgPool) {
    let mut listener = WorkListener::connect(&pool).await.unwrap();
    let started = Instant::now();
    let woken = listener
        .wait(Duration::from_millis(300), Duration::from_millis(100))
        .await
        .unwrap();
    assert!(!woken);
    assert!(started.elapsed() >= Duration::from_millis(300));
}
