# Lunaway engineering guide

Lunaway is a free (AGPL-3.0-or-later) map of motorhome and van spots:
car parks, motorhome areas, campsites, service points. A Flutter app for
Android, iOS, macOS, Windows and the web (Linux users get the web app), and a
Rust backend serving GraphQL over PostgreSQL + PostGIS. This file is the entry
point for every agent and contributor. It is a map: depth lives in
`.claude/rules/` and `docs/`, and the hard rules are held by the machine (git
hooks, gates, CI, agent hooks). The harness check refuses this file above 260
lines, so anything long goes to a routed file.

Official website https://lunaway.net, public API https://api.lunaway.net
(`/health`, `/graphql`). Every User-Agent the project sends names
`(+https://lunaway.net)`.

## Toolchain

- Flutter is pinned in `.fvmrc`; run every command through fvm (`fvm flutter
  ...`, `fvm dart ...`). A bare `flutter`/`dart` is refused when fvm is
  installed, because another SDK reformats files and changes the lints.
- Rust is pinned in `backend/rust-toolchain.toml` (rustup installs it on first
  use). The gates also need cargo-nextest and cargo-deny.
- First time on a clone: `sh tool/setup.sh` (activates the git hooks, reports
  missing tools). Claude Code and Cursor sessions run the same steps at start.

```bash
# app, from app/
fvm flutter pub get
fvm dart run slang                      # after editing lib/i18n/*.i18n.json
fvm dart run build_runner build         # after changing a @riverpod provider
sh packages/lunaway_nav/tool/build_web.sh  # before a web run or build (guidance WebAssembly)
fvm flutter run -d macos                # or chrome, or a device
fvm flutter test
fvm dart analyze --fatal-infos          # dart, not flutter: only dart analyze runs riverpod_lint
# backend, from backend/
docker compose -f compose.yaml up -d    # local PostGIS, 127.0.0.1:54329
sh tool/test-template.sh                # after a new migration: tests start from a migrated template
cargo nextest run --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo run -p lunaway-api                # 127.0.0.1:8484, /health and /graphql
cargo run -p lunaway-api --bin export-schema   # after a GraphQL change
cargo run -p lunaway-cli -- migrate     # then ingest osm-extract|atout-france, conflate, stats
cargo sqlx prepare --workspace -- --all-targets  # after a query change, commit .sqlx/
# everything, from the root
tool/check.sh [--quick] [--fix]
```

## Layout, the part the tree does not say

- `app/`, Flutter package `lunaway`: `lib/features/<feature>/` split into
  `data/` (storage, GraphQL operations, repositories), `application/`
  (providers) and `presentation/` (screens, widgets); `lib/core/` holds the
  router, layout classes and app wiring; `lib/shared/` the design system;
  `lib/i18n/` the slang sources and their generated code.
- `backend/`, Cargo workspace: `lunaway-domain` (types and rules, no I/O),
  `lunaway-db` (migrations, sqlx), `lunaway-ingest` (adapters),
  `lunaway-conflate` (merging into places), `lunaway-api` (axum +
  async-graphql), `lunaway-cli` (the `lunaway` command). Dependencies point
  inward to the domain.
- `schema/lunaway.graphql` is the API contract, exported from the Rust code;
  the app's GraphQL client is generated from it.
- `tool/` holds the gates and the agent harness, `.githooks/` the tracked git
  hooks, `docs/` the architecture and harness notes.
- `plan/` exists only on the maintainer's machine (gitignored): roadmap and
  research notes. Never commit it.

## Binding rules

Each rule names where the machine enforces it. When a rule and the code
disagree, fix the code; a gate is loosened only in the same change that
explains why, never by `--no-verify`.

### Data and privacy

- **Sources are ingested by the server, never fetched by the app.** Every
  source goes through the ingestion workers: paced, resumable, cached, no
  proxy or IP rotation; a proprietary database is crawled only under a written
  licence that allows it (the `extcom` feed). The app talks only to
  our hosts; third-party images come through the API's image proxy. Gate:
  `structure_check` rule `allowed-hosts`. Depth:
  `.claude/rules/data-sources.md`.
- **Every imported record carries its source**: licence, attribution,
  external id and fetch date travel with the data up to the screen. A source
  without a known licence is not ingested. Depth:
  `.claude/rules/data-sources.md`.
- **No tracker, no ad SDK, no analytics.** The app talks only to hosts listed
  in `tool/allowed_hosts.txt`; a new host is a reviewed decision. Gate:
  `structure_check` rule `allowed-hosts`.
- **Secrets** (`.env`, keystores, Apple keys) never enter git nor an agent's
  context. Gates: settings deny rules, edit guard, pre-commit.

### Rust

- Lints are workspace-wide (`backend/Cargo.toml`) and clippy runs with
  `-D warnings`: no `unwrap()` outside tests, no `unsafe`, every public item
  documented. Typed errors (`thiserror`) in libraries, `anyhow` in binaries.
  Gate: clippy. Depth: `.claude/rules/rust.md`.
- Dependencies move one crate at a time (`cargo update -p <crate>`); licences,
  sources and advisories go through `cargo deny`. Gates: bash guard, deny.
- The GraphQL schema is the contract: export it after any change, and a stale
  `schema/lunaway.graphql` fails the tests. Every query is bounded (depth,
  complexity). Depth: `.claude/rules/graphql.md`.
- Database migrations are append-only. Gate: edit guard. Depth:
  `.claude/rules/sqlx.md`.

### Flutter

- **Riverpod 3 with codegen** (`@riverpod`), checked by riverpod_lint through
  `fvm dart analyze`. No legacy provider types. Gate: `structure_check` rule
  `no-legacy-provider`. Depth: `.claude/rules/riverpod.md`.
- **One screen, three layouts**: compact (bottom bar), medium (rail),
  expanded (extended rail and side panels). Depth: `.claude/rules/screens.md`.
- **User-facing text** goes through slang (`context.t`); a key lands in every
  locale in the same commit. Gate: `tool/i18n_check.dart`. Depth:
  `.claude/rules/translations.md`.
- **Logging** through `package:logging`, never `print`. Gate:
  `structure_check` rule `no-print`.
- **Tests that would fail without the code they cover.** Depth:
  `.claude/rules/dart-tests.md`.

### Writing

- **No em dash, no en dash** in anything authored: code, comments,
  translations, commit messages, docs. Gates: edit guard, pre-commit, CI.
- **Comments say why**, for an outside reader. No step narration, no
  tombstones, no phase or ticket markers. Code, comments and docs in English;
  commit subjects in French.

### Git

- Never a git subcommand that discards the working tree (stash, a checkout or
  restore of paths, reset --hard, clean), never `--no-verify`, never a forced
  push. Gate: bash guard; the CI replays every hook.
- Shell commands stay reviewable: no `sh -c`/`bash -c` script that removes
  files, no recursive `rm` on a variable or a glob (scratch files go to the
  gitignored `data/tmp/`, removed by literal path), never print a file that
  holds secrets. Gate: bash guard.
- Commit subject: `type(scope) : sujet`, in French, under 100 characters,
  types `feat fix docs refactor perf test chore ci build style i18n revert`.
  Subject only: no body, no `Co-Authored-By` trailer. Gate: `commit-msg` hook.
- Tags: `vX.Y.Z-beta.N` for pre-releases; `vX.Y.Z` publishes and needs
  `LUNAWAY_PROD_TAG_ACK=1`. Gates: bash guard, pre-push.

## Check before committing

```bash
tool/check.sh --quick   # harness, format, i18n, structure, analyze, clippy, deny (no test suites)
tool/check.sh           # the same plus flutter test and cargo nextest
```

The pre-commit hook formats the staged Dart and Rust files and runs the cheap
gates; pre-push runs the analyses; the CI runs the whole list.

## Read before touching

| area | read first |
|---|---|
| providers | `.claude/rules/riverpod.md` |
| screens, widgets, layouts | `.claude/rules/screens.md` |
| translations | `.claude/rules/translations.md` |
| Dart tests | `.claude/rules/dart-tests.md` |
| Rust code | `.claude/rules/rust.md` |
| SQL, migrations | `.claude/rules/sqlx.md` |
| GraphQL schema and resolvers | `.claude/rules/graphql.md` |
| data sources, ingestion, conflation | `.claude/rules/data-sources.md` |
| architecture | `docs/architecture.md` |
| releases, store listings, privacy declarations | `docs/release.md` |
| the harness itself | `docs/harness.md` |

Claude Code loads a `.claude/rules/` file by itself when a matching file is
opened; every other agent reads it from this table before editing the area.

## Procedures, on demand

`.claude/skills/<name>/SKILL.md`, one per procedure with steps and an end
state: `pre-pr-audit`, `review-pr`, `ci-green`, `job-watching`,
`db-migration`, `graphql-schema-change`, `data-source`,
`harness-maintenance`, `harness-check`. Generic Rust guidance vendored from
actionbook/rust-skills (MIT): `m05-type-driven`, `m06-error-handling`,
`m07-concurrency`, `m10-performance`, `m15-anti-pattern`, `domain-web`.
Claude invokes them by name; anyone else reads the file and follows it.

## Contributing

- Branch from `origin/main` after a fetch; pull request against `main`.
- Before opening a pull request: `tool/check.sh` green, then the pre-PR audit
  (`.claude/skills/pre-pr-audit/SKILL.md`).
- Something learned that a future agent needs goes where the decision table
  of `.claude/skills/harness-maintenance/SKILL.md` says, in the same change.
  This file stays a map.
