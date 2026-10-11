//! Runs the Lunaway API server.
//!
//! `DATABASE_URL` points at the database (migrated with `lunaway migrate`),
//! `LUNAWAY_LISTEN` sets the address (default `127.0.0.1:8484`), `RUST_LOG`
//! the log filter (default `info`), `LUNAWAY_MIN_APP_VERSION` what
//! `Query.config` answers, `LUNAWAY_DEV_CORS=1` opens the API to pages
//! served from this machine. The limits (`LUNAWAY_MAX_*`, `LUNAWAY_RATE_*`,
//! `LUNAWAY_DB_*`) and their defaults are listed in `.env.example` and
//! documented on `lunaway_api::Limits`; so are the quotas
//! (`LUNAWAY_QUOTA_*`), the trust thresholds (`LUNAWAY_TL*`), the sessions
//! (`LUNAWAY_SESSION_DAYS`), the photos (`LUNAWAY_MEDIA_DIR`,
//! `LUNAWAY_MEDIA_BASE_URL`, `LUNAWAY_MAX_UPLOAD_BYTES`) and the routing
//! engine (`LUNAWAY_VALHALLA_URL`, loopback only, `LUNAWAY_VALHALLA_TIMEOUT_MS`,
//! `LUNAWAY_ROUTING_*`), the account deletion journal and the idempotency
//! keys (`LUNAWAY_DELETION_JOURNAL`, `LUNAWAY_DELETION_JOURNAL_DAYS`,
//! `LUNAWAY_IDEMPOTENCY_DAYS`), and the translation server
//! (`LUNAWAY_TRANSLATE_URL`, loopback only, `LUNAWAY_TRANSLATE_*`).

use std::{net::SocketAddr, time::Duration};

use anyhow::Context;
use lunaway_api::{ApiConfig, ApiState};
use lunaway_db::PoolConfig;
use tracing_subscriber::EnvFilter;

const DEFAULT_LISTEN: &str = "127.0.0.1:8484";

/// The server's allocator. glibc's kept what long routes freed: after
/// batteries of long trips off motorways, 1.1 GB in 45 per-thread arenas,
/// the unit at its `MemoryHigh` and part of it swapped
/// (2026-10-11, `plan/research/129-paquets-routage-suites.md`). jemalloc
/// gives freed pages back after a few seconds (its background thread, set
/// in `main`), and counts what the server holds ([`memory`]).
#[global_allocator]
static ALLOCATOR: tikv_jemallocator::Jemalloc = tikv_jemallocator::Jemalloc;

/// How often what the allocator holds is logged.
const MEMORY_LOG_EVERY: Duration = Duration::from_secs(300);

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();
    // Without it, freed pages go back only while the server allocates.
    if let Err(error) = tikv_jemalloc_ctl::background_thread::write(true) {
        tracing::warn!(%error, "the allocator's background thread did not start");
    }
    tokio::spawn(async {
        let mut every = tokio::time::interval(MEMORY_LOG_EVERY);
        loop {
            every.tick().await;
            match memory() {
                Ok(m) => tracing::info!(
                    allocated_mb = m.allocated >> 20,
                    resident_mb = m.resident >> 20,
                    retained_mb = m.retained >> 20,
                    "memory"
                ),
                Err(error) => {
                    tracing::warn!(%error, "the allocator's counters cannot be read");
                    return;
                }
            }
        }
    });

    let listen = std::env::var("LUNAWAY_LISTEN").unwrap_or_else(|_| DEFAULT_LISTEN.to_owned());
    let addr: SocketAddr = listen
        .parse()
        .with_context(|| format!("LUNAWAY_LISTEN={listen} is not a socket address"))?;
    let database_url = std::env::var("DATABASE_URL").context("DATABASE_URL is not set")?;
    let config = ApiConfig::from_env();
    let limits = config.limits;
    tracing::info!(
        dev_cors = config.dev_cors,
        ?limits,
        quotas = ?config.quotas,
        trust = ?config.trust,
        media_dir = %config.media.dir.display(),
        media_base_url = %config.media.base_url,
        routing = ?config.routing,
        "configuration read"
    );
    let pool = lunaway_db::connect_with(
        &database_url,
        PoolConfig {
            max_connections: limits.db_pool_size,
            acquire_timeout: limits.db_acquire_timeout,
            statement_timeout: Some(limits.db_statement_timeout),
        },
    )
    .await
    .context("cannot reach the database")?;

    let keeping = config.keeping.clone();
    match keeping.journal() {
        Some(journal) => {
            // A journal it cannot write would refuse every deletion: the
            // start fails instead, and a deploy goes back to the release
            // before.
            journal
                .check_writable(chrono::Utc::now())
                .with_context(|| {
                    format!(
                        "the account deletion journal {} cannot be written",
                        journal.dir().display()
                    )
                })?;
            tracing::info!(
                dir = %journal.dir().display(),
                days = keeping.deletion_journal_days,
                "account deletions are journaled"
            );
        }
        None => tracing::warn!(
            "LUNAWAY_DELETION_JOURNAL is off: account deletions are not journaled, \
             and a restored backup would bring back the accounts deleted since"
        ),
    }

    // Hourly upkeep: expired sessions are never used again, idempotency keys
    // answer for a bounded time, and the deletion journal keeps its days
    // only as long as a backup could need them.
    let purge_pool = pool.clone();
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(3_600)).await;
            upkeep(&purge_pool, &keeping).await;
        }
    });
    // The community's road events are weighed again every three minutes,
    // here rather than by the importers, whose role does not read who
    // reported what: a banned or deleted account stops counting.
    let weigh_pool = pool.clone();
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(180)).await;
            match lunaway_db::road_events::reweigh_community(&weigh_pool).await {
                Ok(n) => tracing::debug!(changed = n, "community road events weighed again"),
                Err(error) if lunaway_db::road_events::is_busy(&error) => {
                    tracing::debug!("the road events are being written; weighed at the next round");
                }
                Err(error) => tracing::error!(%error, "cannot weigh the community road events"),
            }
        }
    });

    // The language detector's models load once, before the first review
    // whose language its source did not give: a few hundred milliseconds
    // that no request should wait for.
    tokio::task::spawn_blocking(lunaway_domain::translation::warm_up);

    let state = ApiState::new(pool, config);
    // The restrictions a trip's first engine call excludes are computed
    // again when a new graph serves or an import changed the rows outside
    // it: the version is read every ten minutes, never per request. The
    // first round waits a minute, so that the engine serves the first
    // trips after a deploy before it is lent out.
    let refresh = state.clone();
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_secs(60)).await;
        loop {
            if let Some(done) = refresh.refresh_route_blockers().await {
                tracing::info!(graph = %done.graph_id, kept = ?done.kept, calls = done.calls,
                    failed = done.failed, "restrictions kept ahead are ready");
            }
            tokio::time::sleep(Duration::from_secs(600)).await;
        }
    });

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .with_context(|| format!("cannot listen on {addr}"))?;
    tracing::info!(%addr, "listening");

    // The peer address decides whether X-Forwarded-For is believed.
    axum::serve(
        listener,
        lunaway_api::router(state).into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(shutdown_signal())
    .await
    .context("server stopped with an error")
}

/// One round of the hourly upkeep; each step logs its own failure.
async fn upkeep(pool: &lunaway_db::PgPool, keeping: &lunaway_api::config::KeepingConfig) {
    match lunaway_db::accounts::purge_expired_sessions(pool).await {
        Ok(n) => tracing::info!(sessions = n, "expired sessions dropped"),
        Err(error) => tracing::error!(%error, "cannot drop expired sessions"),
    }
    let now = chrono::Utc::now();
    let keys_before = now - chrono::Duration::days(i64::from(keeping.idempotency_days));
    // A road report's key goes with the report: it names the account and
    // the time of a report the privacy page says is erased.
    let road_keys_before = now - chrono::Duration::days(lunaway_db::road_events::REPORT_KEEP_DAYS);
    match lunaway_db::idempotency::purge(pool, keys_before, road_keys_before).await {
        Ok(n) => tracing::info!(keys = n, "old idempotency keys dropped"),
        Err(error) => tracing::error!(%error, "cannot drop old idempotency keys"),
    }
    if let Some(journal) = keeping.journal() {
        let keep = chrono::Duration::days(i64::from(keeping.deletion_journal_days));
        let pruned = tokio::task::spawn_blocking(move || journal.prune(keep, now)).await;
        match pruned {
            Ok(Ok(n)) => tracing::info!(days = n, "old days of the deletion journal removed"),
            Ok(Err(error)) => tracing::error!(%error, "cannot prune the deletion journal"),
            Err(error) => tracing::error!(%error, "the deletion journal's pruning stopped"),
        }
    }
}

/// Resolves on Ctrl-C in a terminal or SIGTERM from a container runtime.
async fn shutdown_signal() {
    let ctrl_c = async {
        if let Err(error) = tokio::signal::ctrl_c().await {
            tracing::error!(%error, "cannot listen for Ctrl-C");
            std::future::pending::<()>().await;
        }
    };
    #[cfg(unix)]
    let terminate = async {
        match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(mut signal) => {
                signal.recv().await;
            }
            Err(error) => {
                tracing::error!(%error, "cannot listen for SIGTERM");
                std::future::pending::<()>().await;
            }
        }
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        () = ctrl_c => {}
        () = terminate => {}
    }
    tracing::info!("shutting down");
}

/// What the allocator holds, bytes.
struct Memory {
    /// Taken by the server's data.
    allocated: usize,
    /// In physical pages: `allocated`, the free space of the pages in use
    /// and the freed pages not given back yet.
    resident: usize,
    /// Address space kept for reuse, given back to the system.
    retained: usize,
}

/// The allocator's counters, read now.
fn memory() -> Result<Memory, tikv_jemalloc_ctl::Error> {
    // The counters are a snapshot taken at each epoch.
    tikv_jemalloc_ctl::epoch::advance()?;
    Ok(Memory {
        allocated: tikv_jemalloc_ctl::stats::allocated::read()?,
        resident: tikv_jemalloc_ctl::stats::resident::read()?,
        retained: tikv_jemalloc_ctl::stats::retained::read()?,
    })
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        reason = "a test states its preconditions with unwrap"
    )]

    use super::*;

    #[test]
    fn the_server_s_allocations_are_counted_by_its_allocator() {
        let before = memory().unwrap().allocated;
        let held = std::hint::black_box(vec![7_u8; 64 << 20]);
        let during = memory().unwrap();
        assert!(
            during.allocated >= before + (60 << 20),
            "64 MiB held must show in the counters: {before} then {}",
            during.allocated
        );
        assert!(during.resident >= during.allocated);
        drop(held);
    }
}
