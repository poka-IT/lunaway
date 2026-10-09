---
paths:
  - "backend/migrations/**"
  - "backend/crates/lunaway-db/**"
  - "backend/.sqlx/**"
---
# SQL and migrations

PostgreSQL 18 + PostGIS, accessed with sqlx 0.9.

## Migrations

- One file per change in `backend/migrations/`, named
  `<YYYYMMDDHHMMSS>_<what>.sql`, created with `sqlx migrate add <what>`.
- **A committed migration is never modified**: sqlx stores its checksum, and
  an edited one breaks every database it ran on. Fix forward with a new
  migration. Gate: edit guard.
- A migration is safe on a populated table: add a nullable column, backfill,
  then constrain; create indexes `CONCURRENTLY` in their own migration when
  the table is large.
- Grants are part of the schema (`*_roles_and_grants.sql`, and each later
  migration for its tables): the API connects as `lunaway_app` (SELECT on
  the catalogue it serves; it writes accounts and contributions, never a
  record or a place), the importers and the conflation worker as
  `lunaway_ingest` (no DELETE on records or places: a gone one is a
  tombstone the change feed reports). A new place or an edit is a
  `place_submissions` row the worker turns into a `community` record; a
  contribution that changes what a place shows queues it in
  `place_refresh_queue` for the worker. A migration that creates a
  table or a sequence grants it to the roles that need it, nothing more; the
  tests in `lunaway-db/tests/locks_and_roles.rs` and the role-scoped
  pipeline and API tests fail otherwise.

## Queries

- `sqlx::query!` / `query_as!` for compile-time checked SQL. The offline cache
  (`backend/.sqlx/`) is regenerated with `cargo sqlx prepare --workspace` and
  committed with the query change; CI builds with `SQLX_OFFLINE=true`.
- Geometry columns are `geography(Point, 4326)` for places; read coordinates
  with `ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon`, filter with
  `ST_DWithin` (metres on geography) and `&&` against an envelope for a map
  viewport. Every spatial filter has a GiST index behind it.
- Text search: places by their words (`places.search_vector`, a `tsvector`
  of the folded name, city and municipality kept by a trigger, GIN index),
  a typo by the trigram index of `place_search_words`, the path chosen from
  `pg_stats` (`lunaway_db::search`); points of interest by `unaccent` +
  `pg_trgm` (`similarity`, `%`) and a GIN index.
- A mutation touching more than one table runs in one transaction; two
  writers that can race take `FOR UPDATE` or run `SERIALIZABLE`.
- Every write to the catalogue (`source_records`, `places` and what hangs on
  them) holds the writers' advisory lock for its transaction
  (`begin_locked`, `conflation::begin_writer`): the change feed is correct
  only with one writer of `places` at a time, and an import beside a
  conflation would otherwise lock the same rows in opposite orders. Functions
  that write places take a `WriterTx`, so a write outside the lock does not
  compile. The points of interest have their own writers' lock
  (`pois::begin_poi_writer`, `PoiWriterTx`): their importers, the fuel
  poller and the worker write them. A writer that changed what a tile
  shows marks the layer (`pois::mark_layer`, `mark_layer_now` once at the
  end of an import), and the worker publishes a new tiles version at most
  every `--poi-layer-every-mins` (`pois::publish_layer`), so neither an
  import's batches nor the fuel poller make devices fetch their tiles
  again each time. A publication also updates what the low zooms' tiles
  read, in its transaction: the points' clusters of zooms 6 to 9
  (`poi_cluster_cells`, counted again) and the places' dots (`place_dots`,
  the places written since `place_layer.dots_seq`). A migration that
  changes what a dot or a cluster is made of without writing the rows
  fills them again from `place_dots_computed` and
  `poi_cluster_cells_computed`.
- An import of several country extracts writes each record under the
  scope of its country and retires only in the scopes of the countries it
  read (`extract_run`); its progress is kept in the cache so a stopped run
  resumes after the last extract it stored.
- An import writes only the rows whose content changed, so a row's own date
  no longer says when Lunaway last read it: a query that serves a record's
  or a point's date reads it through `lunaway_read_at`, and an import calls
  `records::mark_read` after a complete read of its slice.
- Timestamps are `TIMESTAMPTZ`; identifiers are UUID v7 generated in Rust.
- A statement a loop runs often gets PostgreSQL's generic plan after five
  runs, which knows no parameter's value: a growing array (`<> ALL($n)`
  compared with every row) or a box meant as "everywhere" (it walked the
  spatial index) turned a batch of the content refresh into 94 s. Walk a
  run with a keyset cursor, leave a filter out rather than pass a value
  that disables it, and check the plan under `SET plan_cache_mode =
  force_generic_plan` (`lunaway_db::content::places_due`).

## Tests

`#[sqlx::test(migrations = "../../migrations")]` gives each test a fresh
database; it needs `DATABASE_URL` pointing at a server where the user may
create databases (the local compose database does).

## Test speed

- `#[sqlx::test]` copies `template1` for each test. `backend/tool/test-template.sh`
  migrates `template1` so tests skip PostGIS creation and the migrations;
  `tool/check.sh` and the CI run it before the tests. After editing a
  migration, run it again, or the tests fail with "previously applied but
  has been modified".
- The dev and CI databases run without fsync (`backend/compose.yaml`, the CI
  step): never copy those settings to a server.
- Dependencies, `lunaway-domain` and `lunaway-media` are optimised in dev
  builds (`backend/Cargo.toml`); keep pure, heavy computation in those crates.
- One database server per checkout: `template1` holds one branch's
  migrations, so a git worktree on another branch starts its own compose
  project on another port (`backend/compose.yaml`, `LUNAWAY_PG_PORT`).
