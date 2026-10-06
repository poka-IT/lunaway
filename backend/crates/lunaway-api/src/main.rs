//! Runs the Lunaway API server.
//!
//! `DATABASE_URL` points at the database (migrated with `lunaway migrate`),
//! `LUNAWAY_LISTEN` sets the address (default `127.0.0.1:8484`), `RUST_LOG`
//! the log filter (default `info`), `LUNAWAY_MIN_APP_VERSION` what
//! `Query.config` answers, `LUNAWAY_DEV_CORS=1` opens the API to pages
//! served from this machine. The limits (`LUNAWAY_MAX_*`, `LUNAWAY_RATE_*`,
//! `LUNAWAY_DB_*`) and their defaults are listed in `.env.example` and
//! documented on `lunaway_api::Limits`.

use std::net::SocketAddr;

use anyhow::Context;
use lunaway_api::{ApiConfig, ApiState};
use lunaway_db::PoolConfig;
use tracing_subscriber::EnvFilter;

const DEFAULT_LISTEN: &str = "127.0.0.1:8484";

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();

    let listen = std::env::var("LUNAWAY_LISTEN").unwrap_or_else(|_| DEFAULT_LISTEN.to_owned());
    let addr: SocketAddr = listen
        .parse()
        .with_context(|| format!("LUNAWAY_LISTEN={listen} is not a socket address"))?;
    let database_url = std::env::var("DATABASE_URL").context("DATABASE_URL is not set")?;
    let config = ApiConfig::from_env();
    let limits = config.limits;
    tracing::info!(dev_cors = config.dev_cors, ?limits, "configuration read");
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

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .with_context(|| format!("cannot listen on {addr}"))?;
    tracing::info!(%addr, "listening");

    // The peer address decides whether X-Forwarded-For is believed.
    axum::serve(
        listener,
        lunaway_api::router(ApiState::new(pool, config))
            .into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(shutdown_signal())
    .await
    .context("server stopped with an error")
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
