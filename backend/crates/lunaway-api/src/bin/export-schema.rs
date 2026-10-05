//! Writes the GraphQL schema as SDL to `schema/lunaway.graphql`, the contract
//! the Flutter client is generated from.
//!
//! ```text
//! cargo run -p lunaway-api --bin export-schema
//! ```
//!
//! The test `committed_schema_matches_the_code` fails when the committed file
//! is stale, so CI catches a schema change that was not exported.

use std::path::PathBuf;

use anyhow::Context;

fn main() -> anyhow::Result<()> {
    let path = schema_path();
    std::fs::write(&path, lunaway_api::schema::sdl_file())
        .with_context(|| format!("cannot write {}", path.display()))?;
    tracing_subscriber::fmt().init();
    tracing::info!(path = %path.display(), "schema written");
    Ok(())
}

fn schema_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../schema/lunaway.graphql")
}
