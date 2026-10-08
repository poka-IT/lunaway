//! The committed contracts must match what the code serves: the SDL the
//! Flutter client is generated from, and the TileJSON its map sources are
//! tested against.

#[test]
fn committed_schema_matches_the_code() {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../../schema/lunaway.graphql"
    );
    let committed = std::fs::read_to_string(path).unwrap_or_default();
    assert!(
        committed == lunaway_api::schema::sdl_file(),
        "schema/lunaway.graphql is stale: run `cargo run -p lunaway-api --bin export-schema` \
         from backend/ and commit the result"
    );
}

#[test]
fn committed_tilejson_matches_the_code() {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../schema/tilejson.json");
    let committed = std::fs::read_to_string(path).unwrap_or_default();
    let served = lunaway_api::tiles::contract_file().unwrap_or_default();
    assert!(
        !served.is_empty() && committed == served,
        "schema/tilejson.json is stale: run `cargo run -p lunaway-api --bin export-schema` \
         from backend/ and commit the result"
    );
}
