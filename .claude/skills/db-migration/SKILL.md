---
name: db-migration
description: Add or change the PostgreSQL schema of Lunaway safely. Use when a feature needs a new table, column, index or constraint, when a query needs a schema change, or when a migration fails. Covers creating the migration, testing it on a fresh and on a populated database, the sqlx offline cache, and the rule that a committed migration is never edited.
---

# Changing the database schema

The rules live in `.claude/rules/sqlx.md`; this is the procedure.

## Steps

1. **Start the local database** (`backend/compose.yaml`) and point
   `DATABASE_URL` at it (`backend/.env.example` has the value).
2. **Create the migration**, never edit a committed one (the edit guard
   refuses it):
   ```bash
   cd backend && sqlx migrate add <what_it_does>
   ```
3. **Write it for a populated table.** New columns nullable or with a cheap
   default; backfill in batches; add the `NOT NULL` or the constraint after;
   large indexes `CONCURRENTLY` in their own migration (no transaction).
   Spatial columns get a GiST index, text search a GIN index on the
   expression the query uses.
4. **Apply and roll forward locally**: `sqlx migrate run`. A mistake is fixed
   by another migration, not by editing this one once it is committed.
5. **Update the queries** (`query!`/`query_as!`), then the offline cache:
   ```bash
   cargo sqlx prepare --workspace
   ```
   and commit `backend/.sqlx/` with the change.
6. **Test**: `#[sqlx::test(migrations = "../../migrations")]` tests cover the
   new behaviour; `cargo nextest run --workspace` green.
7. **Data written by ingestion** (places, sources): rerun the affected
   adapter on the local database and check the conflation output did not
   change unexpectedly (count of places, of merges, a few known spots).

## End state

One new migration file, the queries and `.sqlx/` updated in the same commit,
tests green, and nothing in an already committed migration changed.
