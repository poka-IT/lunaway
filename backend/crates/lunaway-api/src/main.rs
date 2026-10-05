//! Runs the Lunaway API server.
//!
//! `LUNAWAY_LISTEN` sets the address (default `127.0.0.1:8484`), `RUST_LOG`
//! the log filter (default `info`).

use std::net::SocketAddr;

use anyhow::Context;
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
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .with_context(|| format!("cannot listen on {addr}"))?;
    tracing::info!(%addr, "listening");

    axum::serve(listener, lunaway_api::router(lunaway_api::build_schema()))
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
