#!/usr/bin/env bash
# Proves on the backend what the two row roles may do, run as root by
# infra/verify.sh: logs in with each role's own credentials (password
# through the environment, never printed), lists every privilege it holds on
# the tables and sequences of the public schema, compares that list with the
# grants of backend/migrations, and tries the writes it must not do. Those
# tries run inside a transaction that is rolled back and match no row
# (WHERE false), so even a wrong grant would change nothing.
#
# A new table makes this test fail until its expected grants are added here.
. "$(dirname "$0")/common.sh"
need_root

# as_role ENV_FILE SQL: runs SQL as the role of ENV_FILE, prints the result.
as_role() {
  local url role
  url="$(sed -n 's/^DATABASE_URL=//p' "$1")"
  role="$(sed -n 's|^postgres://\([^:]*\):.*|\1|p' <<<"$url")"
  PGPASSWORD="$(sed -n 's|^postgres://[^:]*:\([^@]*\)@.*|\1|p' <<<"$url")" \
    psql -X -At -v ON_ERROR_STOP=1 -h 127.0.0.1 -U "$role" -d lunaway -c "$2" 2>&1
}

granted_sql="
SELECT c.relname || ' ' || p
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace,
     unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) p
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'v', 'm', 'p') AND has_table_privilege(c.oid, p)
UNION ALL
SELECT c.relname || ' ' || p
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace,
     unnest(ARRAY['USAGE','SELECT','UPDATE']) p
WHERE n.nspname = 'public' AND c.relkind = 'S' AND has_sequence_privilege(c.oid, p)
UNION ALL
SELECT 'schema public CREATE' WHERE has_schema_privilege('public', 'CREATE')
ORDER BY 1"

# PostGIS grants SELECT on its reference table and views to PUBLIC.
postgis="geography_columns SELECT
geometry_columns SELECT
spatial_ref_sys SELECT"

# The account and contribution tables the API writes (migration
# 20261006005548): every row privilege, and nothing on the catalogue but
# SELECT.
account_tables="accounts device_keys sessions recovery_codes account_endorsements muted_authors
  reviews photos confirmations issue_reports content_reports moderation_queue favorite_lists
  favorite_items place_submissions"
expected_app="$(sort <<EOF
$postgis
place_sources SELECT
places SELECT
source_records SELECT
sources SELECT
sync_epoch SELECT
place_refresh_queue INSERT
$(for table in $account_tables; do printf '%s SELECT\n%s INSERT\n%s UPDATE\n%s DELETE\n' "$table" "$table" "$table" "$table"; done)
EOF
)"
expected_ingest="$(sort <<EOF
$postgis
conflation_constraints INSERT
conflation_constraints SELECT
confirmations SELECT
issue_reports SELECT
municipalities DELETE
municipalities INSERT
municipalities SELECT
municipalities UPDATE
photos SELECT
place_refresh_queue DELETE
place_refresh_queue INSERT
place_refresh_queue SELECT
place_submissions SELECT
place_submissions UPDATE
reviews SELECT
match_pairs DELETE
match_pairs INSERT
match_pairs SELECT
match_pairs UPDATE
place_change_seq USAGE
place_sources DELETE
place_sources INSERT
place_sources SELECT
place_sources UPDATE
places INSERT
places SELECT
places UPDATE
source_records INSERT
source_records SELECT
source_records UPDATE
sources SELECT
EOF
)"

# The columns of accounts a role may read: the worker reads only what the
# trust and ban rules need, never a pseudonym or a ban reason.
account_columns_sql="
SELECT string_agg(attname, ' ' ORDER BY attname)
FROM pg_attribute
WHERE attrelid = 'accounts'::regclass AND attnum > 0 AND NOT attisdropped
  AND has_column_privilege('accounts', attname, 'SELECT')"

compare() {
  local label="$1" env="$2" expected="$3" got
  got="$(as_role "$env" "$granted_sql" | sort)"
  if [ "$got" = "$expected" ]; then
    echo "ok   $label holds exactly its grants: $(echo "$got" | grep -cv -e '_columns' -e spatial_ref_sys) privileges besides PostGIS's public ones"
  else
    echo "FAIL $label grants differ from the expected list:"
    diff <(echo "$expected") <(echo "$got") | sed 's/^/       /' || true
  fi
}

# refused LABEL ENV SQL: SQL must fail with "permission denied".
refused() {
  local label="$1" out
  # The error is the expected outcome here, not a reason to stop.
  out="$(as_role "$2" "BEGIN; $3; ROLLBACK;")" || true
  if grep -q 'permission denied' <<<"$out"; then
    echo "ok   $label: $(grep -m1 -o 'permission denied[^"]*' <<<"$out")"
  else
    echo "FAIL $label was not refused: $(echo "$out" | tail -n 1 | cut -c1-120)"
  fi
}

allowed() {
  local label="$1" out
  if out="$(as_role "$2" "$3")"; then
    echo "ok   $label: $(echo "$out" | tail -n 1 | cut -c1-80)"
  else
    echo "FAIL $label: $(echo "$out" | tail -n 1 | cut -c1-120)"
  fi
}

compare lunaway_app /etc/lunaway/api.env "$expected_app"
allowed "lunaway_app reads places" /etc/lunaway/api.env "SELECT 'places: ' || count(*) FROM places"
refused "lunaway_app writes a place" /etc/lunaway/api.env "UPDATE places SET name = name WHERE false"
refused "lunaway_app deletes a record" /etc/lunaway/api.env "DELETE FROM source_records WHERE false"
refused "lunaway_app reads the merge pairs" /etc/lunaway/api.env "SELECT count(*) FROM match_pairs"
refused "lunaway_app moves the change sequence" /etc/lunaway/api.env "SELECT nextval('place_change_seq')"
refused "lunaway_app creates a table" /etc/lunaway/api.env "CREATE TABLE grants_probe (x int)"
refused "lunaway_app adds a record" /etc/lunaway/api.env "INSERT INTO source_records SELECT * FROM source_records WHERE false"
refused "lunaway_app writes a merge decision" /etc/lunaway/api.env "INSERT INTO conflation_constraints SELECT * FROM conflation_constraints WHERE false"
refused "lunaway_app writes the communes" /etc/lunaway/api.env "DELETE FROM municipalities WHERE false"
refused "lunaway_app empties the worker's queue" /etc/lunaway/api.env "DELETE FROM place_refresh_queue WHERE false"
allowed "lunaway_app writes an account" /etc/lunaway/api.env "BEGIN; UPDATE accounts SET pseudonym = pseudonym WHERE false; ROLLBACK; SELECT 'accounts writable'"

compare lunaway_ingest /etc/lunaway/ingest.env "$expected_ingest"
allowed "lunaway_ingest reads records" /etc/lunaway/ingest.env "SELECT 'records: ' || count(*) FROM source_records"
refused "lunaway_ingest deletes a place" /etc/lunaway/ingest.env "DELETE FROM places WHERE false"
refused "lunaway_ingest deletes a record" /etc/lunaway/ingest.env "DELETE FROM source_records WHERE false"
refused "lunaway_ingest writes a source" /etc/lunaway/ingest.env "UPDATE sources SET name = name WHERE false"
refused "lunaway_ingest writes the sync epoch" /etc/lunaway/ingest.env "UPDATE sync_epoch SET created_at = created_at WHERE false"
refused "lunaway_ingest writes the migrations table" /etc/lunaway/ingest.env "DELETE FROM _sqlx_migrations WHERE false"
refused "lunaway_ingest creates a table" /etc/lunaway/ingest.env "CREATE TABLE grants_probe (x int)"
refused "lunaway_ingest writes an account" /etc/lunaway/ingest.env "UPDATE accounts SET trust_level = trust_level WHERE false"
refused "lunaway_ingest reads the sessions" /etc/lunaway/ingest.env "SELECT count(*) FROM sessions"
refused "lunaway_ingest reads a pseudonym" /etc/lunaway/ingest.env "SELECT pseudonym FROM accounts LIMIT 1"
refused "lunaway_ingest writes a review" /etc/lunaway/ingest.env "UPDATE reviews SET status = status WHERE false"
refused "lunaway_ingest changes a merge decision" /etc/lunaway/ingest.env "DELETE FROM conflation_constraints WHERE false"
got="$(as_role /etc/lunaway/ingest.env "$account_columns_sql")"
if [ "$got" = "banned_at id trust_level" ]; then
  echo "ok   lunaway_ingest reads these columns of accounts only: $got"
else
  echo "FAIL lunaway_ingest reads these columns of accounts: $got (want: banned_at id trust_level)"
fi
