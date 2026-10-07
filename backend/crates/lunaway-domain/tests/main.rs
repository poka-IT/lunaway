//! The integration tests of the domain: shared vectors and real fixtures.
//!
//! One binary for the crate: each file of `tests/` is a module declared
//! here (`autotests = false` in Cargo.toml), so a new file needs its line.

mod conflation_vectors;
mod extcom_synthetic;
mod fuel_corridor;

/// With `autotests = false`, a test file nobody declares compiles into
/// nothing and its tests never run, silently. This holds every crate of the
/// workspace to its declarations: a module of its `tests/main.rs`, or a
/// `[[test]]` of its manifest.
#[test]
fn every_integration_test_file_is_compiled() {
    let crates = concat!(env!("CARGO_MANIFEST_DIR"), "/..");
    let mut checked = 0;
    for krate in std::fs::read_dir(crates).expect("the workspace's crates directory") {
        let krate = krate.expect("a crate directory").path();
        let Ok(manifest) = std::fs::read_to_string(krate.join("Cargo.toml")) else {
            continue;
        };
        if !manifest.contains("autotests = false") {
            continue;
        }
        let main = std::fs::read_to_string(krate.join("tests/main.rs")).unwrap_or_default();
        let files = std::fs::read_dir(krate.join("tests")).expect("a tests directory");
        for file in files {
            let path = file.expect("a test file").path();
            let (Some(stem), Some("rs")) = (
                path.file_stem().and_then(|s| s.to_str()),
                path.extension().and_then(|s| s.to_str()),
            ) else {
                continue;
            };
            if stem == "main" {
                continue;
            }
            checked += 1;
            assert!(
                main.contains(&format!("mod {stem};"))
                    || manifest.contains(&format!("path = \"tests/{stem}.rs\"")),
                "{} is neither a module of tests/main.rs nor a [[test]] of its manifest: \
                 its tests would never run",
                path.display()
            );
        }
    }
    assert!(checked > 30, "the walk found the test files ({checked})");
}
