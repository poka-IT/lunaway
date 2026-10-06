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

/// The bound itself (the worker runs `MAX_SETTLE` after the first write)
/// is held on a paused clock by the tests of `lunaway_db::community`; here,
/// real notifications from another connection, and a wait that must end
/// although the writes never stop. Only a worker kept asleep for good fails
/// it, however loaded the machine is.
#[sqlx::test(migrations = "../../migrations")]
async fn a_steady_stream_of_writes_does_not_keep_the_worker_asleep(pool: PgPool) {
    let mut listener = WorkListener::connect(&pool).await.unwrap();
    let sender = pool.clone();
    let writes = tokio::spawn(async move {
        // A write every 100 ms, more than one per settle window, until the
        // test ends.
        loop {
            sqlx::query("SELECT pg_notify($1, '')")
                .bind(WORK_CHANNEL)
                .execute(&sender)
                .await
                .unwrap();
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    });
    let woken = tokio::time::timeout(
        MAX_SETTLE * 15,
        listener.wait(Duration::from_secs(60), Duration::from_millis(300)),
    )
    .await;
    writes.abort();
    assert!(
        matches!(woken, Ok(Ok(true))),
        "the worker wakes while writes keep coming: {woken:?}"
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
