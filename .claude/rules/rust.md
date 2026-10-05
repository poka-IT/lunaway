---
paths:
  - "backend/**/*.rs"
  - "backend/**/Cargo.toml"
---
# Rust conventions

Edition 2024, toolchain pinned in `backend/rust-toolchain.toml`, lints in
`[workspace.lints]` of `backend/Cargo.toml` (every crate opts in with
`[lints] workspace = true`). CI runs clippy with `-D warnings`.

## Errors

- Libraries return typed errors: `thiserror`, one enum per failure domain,
  `#[source]` on the wrapped cause, `#[non_exhaustive]` on public enums that
  will grow. Binaries (`main.rs`, `src/bin/`) use `anyhow` with `.context()`.
- Never a stringly-typed error, never `map_err(|_| ...)` that drops the cause.
  Log with `tracing::error!` before converting when the cause would be lost.
- `unwrap()` is denied outside tests; `expect()` warns. A real invariant uses
  `expect("why this cannot fail")` with a `# Panics` doc section.

## Shape

- The domain crate is pure: no I/O, no async, no database type. The API and
  the ingestion crates depend on it, never the reverse.
- Newtypes for identifiers and validated values (`PlaceId(Uuid)`, `Latitude`),
  so a raw `f64` or `String` cannot cross a boundary unchecked.
- Public signatures take `&str` and `&[T]`, not `&String` and `&Vec<T>`;
  `impl Trait` before `Box<dyn Trait>`; native `async fn` in traits before
  `async-trait`.
- No `clone()` to silence the borrow checker where a reference or `Cow`
  works. No `format!` in a hot loop. No blocking call in async code
  (`spawn_blocking` for CPU work over a millisecond).
- No `#[allow(...)]` without `reason = "..."`.
- Time is `chrono::DateTime<Utc>` in Rust and `TIMESTAMPTZ` in SQL.

## Tests

- `#[tokio::test]` for async tests; never `block_on` inside one.
- Integration tests in `crates/<crate>/tests/<scenario>.rs`; database tests
  with `#[sqlx::test]` (`.claude/rules/sqlx.md`).
- `proptest` for parsers and encode/decode pairs.
- Fakes are a trait plus a local implementation in the test; no mock crate
  without a proven need.
- An assertion on an invariant says why it matters:
  `assert_eq!(a, b, "the API must expose every kind the domain knows")`.

## Logs

`tracing`, structured fields (`tracing::info!(%addr, "listening")`). No
precise user location, account key or IP in a log line: they are personal
data under the GDPR.
