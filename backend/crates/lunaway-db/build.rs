//! Rebuilds the crate when a migration is added or edited: `sqlx::migrate!`
//! embeds the migrations directory at compile time, and on a stable
//! compiler cargo does not know the macro read it. Without this, `lunaway
//! migrate` (and `tool/test-template.sh`) could run a binary that never saw
//! the new file and report the database up to date.

fn main() {
    println!("cargo:rerun-if-changed=../../migrations");
}
