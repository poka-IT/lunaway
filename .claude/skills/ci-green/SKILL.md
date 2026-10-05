---
name: ci-green
description: "Diagnosing a red CI or a push refused by a local hook in Lunaway: formatting and lint, codegen or schema drift, lockfile skew, checks that only fail on another OS, cargo-deny and cargo-audit drift, toolchain pins. Use when the GitHub Actions run goes red, when a hook blocks a commit or a push, or before bumping a dependency or a toolchain."
---

# Getting CI back to green

A red `main` hides the next real regression. Diagnose in this order, from the
cheapest and most frequent cause to the rarest.

## 0. Is it your commit?

Read the run for the exact SHA you pushed (`gh run list --branch <b>`,
`gh run view <id> --log-failed`). A cancelled run can hide a failed job:
read the per-job conclusions before filing it as churn. A job that died with
no log is a runner problem: rerun it before concluding anything.

## 1. Formatting, lint, analysis (the most frequent red)

- `tool/check.sh --quick` replays every one of them locally; run it first.
- Dart: the CI reads `page_width` from `app/analysis_options.yaml`. Format
  with `fvm dart format` (never a bare `dart`, which may be another SDK).
- Analysis runs as `fvm dart analyze --fatal-infos`: riverpod_lint findings
  appear only there, not in `flutter analyze`.
- Rust: `cargo fmt --all` then `cargo clippy --workspace --all-targets -- -D warnings`.
  The toolchain is pinned, so a new stable cannot add a lint by surprise; a
  lint that appears after a pin bump is fixed in the bump's commit.

## 2. Generated code and contracts

- `app`: `build_runner --only-check` failing means a provider changed without
  `fvm dart run build_runner build`; slang output stale means
  `fvm dart run slang` was not run. Regenerate and commit the output.
- `schema/lunaway.graphql` stale: `cargo run -p lunaway-api --bin export-schema`
  in `backend/`, commit the file.
- `.sqlx/` stale: `cargo sqlx prepare --workspace` with the local database up.

## 3. Lockfiles

- Never a bare `cargo update` (the bash guard refuses it): `cargo update -p
  <crate>` for the one you need, so the diff stays reviewable.
- Validate a dependency change with `--all-targets`: test fixtures compile only
  there.
- `app/pubspec.lock` resolving from a path, or `backend/Cargo.lock` from git,
  is refused by `tool/harness/git/check_lock.sh`.

## 4. Checks that cannot fail on your machine

- A macOS build does not compile Linux-only code: replay
  `cargo check --workspace --all-targets --target x86_64-unknown-linux-gnu`
  before pushing cfg-dependent Rust.
- The CI runs Ubuntu: a path with a backslash, a case-insensitive file name,
  a locale-dependent sort all pass on macOS and fail there.

## 5. Supply chain

`cargo-deny` and `cargo-audit` keep separate ignore lists (`backend/deny.toml`,
`backend/.cargo/audit.toml`); `tool/structure_rs.sh` fails when they differ.
Prefer `cargo update -p <crate>` to a new ignore: an ignore is permanent, an
update is not. Every ignore carries its reachability argument.

## 6. Second agent in the tree

Before committing in a shared checkout, check `git status` and `git reflog`
for a HEAD that moved under you. Stage your own files by path, never
`git add -A`.
