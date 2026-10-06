#!/bin/sh
# Migrates template1 of the test database server, so that every database
# #[sqlx::test] creates (copied from template1) already holds the schema:
# sqlx's migrator then finds every migration applied, checksums included,
# and skips them. The tests pass without this, only slower (each one would
# create PostGIS and run every migration). Run it after pulling or writing a
# migration; a template migrated from an older copy of a migration makes the
# tests fail with "previously applied but has been modified", and this script
# rebuilds the template from template0 first.
#
#   backend/tool/test-template.sh            # DATABASE_URL, or the compose URL
set -eu
cd "$(dirname "$0")/.."
url="${DATABASE_URL:-postgres://lunaway:lunaway@127.0.0.1:54329/lunaway}"
base="${url%/*}"
# Homebrew's libpq is keg-only: its psql is not on PATH by default.
if ! command -v psql >/dev/null 2>&1 && [ -x /opt/homebrew/opt/libpq/bin/psql ]; then
  PATH="/opt/homebrew/opt/libpq/bin:$PATH"
fi
# template1 cannot be dropped while it is a template, nor recreated while a
# session is connected to it; this runs against the maintenance database.
psql "$base/postgres" -v ON_ERROR_STOP=1 -q <<'SQL'
UPDATE pg_database SET datistemplate = false WHERE datname = 'template1';
DROP DATABASE template1;
CREATE DATABASE template1 TEMPLATE template0 IS_TEMPLATE true;
SQL
SQLX_OFFLINE=true DATABASE_URL="$base/template1" cargo run -q --locked -p lunaway-cli -- migrate
