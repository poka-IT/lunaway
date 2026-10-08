//! Writes the contracts the Flutter client is checked against: the GraphQL
//! schema as SDL to `schema/lunaway.graphql`, which the client is generated
//! from, and the TileJSON of the map tiles to `schema/tilejson.json`, which
//! the map's sources are tested against.
//!
//! ```text
//! cargo run -p lunaway-api --bin export-schema
//! ```
//!
//! The tests `committed_schema_matches_the_code` and
//! `committed_tilejson_matches_the_code` fail when a committed file is
//! stale, so CI catches a change that was not exported.

use std::path::PathBuf;

use anyhow::Context;

fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt().init();
    let schema = contract_path("lunaway.graphql");
    std::fs::write(&schema, lunaway_api::schema::sdl_file())
        .with_context(|| format!("cannot write {}", schema.display()))?;
    tracing::info!(path = %schema.display(), "schema written");
    let tiles = contract_path("tilejson.json");
    let text = lunaway_api::tiles::contract_file().context("cannot write the TileJSON")?;
    std::fs::write(&tiles, text).with_context(|| format!("cannot write {}", tiles.display()))?;
    tracing::info!(path = %tiles.display(), "TileJSON written");
    Ok(())
}

fn contract_path(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../../schema")
        .join(name)
}
