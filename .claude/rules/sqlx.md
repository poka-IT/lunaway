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

## Queries

- `sqlx::query!` / `query_as!` for compile-time checked SQL. The offline cache
  (`backend/.sqlx/`) is regenerated with `cargo sqlx prepare --workspace` and
  committed with the query change; CI builds with `SQLX_OFFLINE=true`.
- Geometry columns are `geography(Point, 4326)` for places; read coordinates
  with `ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon`, filter with
  `ST_DWithin` (metres on geography) and `&&` against an envelope for a map
  viewport. Every spatial filter has a GiST index behind it.
- Text search uses `unaccent` + `pg_trgm` (`similarity`, `%`) and a GIN index.
- A mutation touching more than one table runs in one transaction; two
  writers that can race take `FOR UPDATE` or run `SERIALIZABLE`.
- Timestamps are `TIMESTAMPTZ`; identifiers are UUID v7 generated in Rust.

## Tests

`#[sqlx::test(migrations = "../../migrations")]` gives each test a fresh
database; it needs `DATABASE_URL` pointing at a server where the user may
create databases (the local compose database does).
