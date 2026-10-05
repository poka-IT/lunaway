//! The committed SDL is the contract the Flutter client is generated from; it
//! must match what the code serves.

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
