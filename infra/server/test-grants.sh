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

# The import role reads the sync epoch for the regional packs' cursors
# (lunaway packs build). No migration of 38adf3d grants it: granted by hand
# on the backend on 2026-10-06 (plan/research/13-basemap.md, "Déploiement
# Europe, carburant et radars"), until a migration does.
#
# The account and contribution tables the API writes (migration
# 20261006005548, and 20261010130000 for the reviews of points): every row
# privilege, and nothing on the catalogue but SELECT.
#
# The open content and the partner's reviews, ratings and photos
# (migrations 20261007180000 to 20261008110400) are the import role's to
# write. The API reads them; it writes no hide (content_hides SELECT only):
# it hides a reported item and lifts the reports' hide through
# content_hide_reported and content_unhide_reported.
#
# The words of the places (migration 20261008140100) are kept by the
# writers of places. What the tiles' low zooms read (migration
# 20261008210100): the API reads place_dots and poi_cluster_cells, the
# import role writes them with place_dot_members when it publishes a
# version, through the views place_dot_sources and
# poi_cluster_cells_computed. The towns the search finds by name
# (migration 20261008220100): the API reads place_towns, the import role
# keeps it.
account_tables="accounts device_keys sessions recovery_codes account_endorsements muted_authors
  reviews poi_reviews photos confirmations issue_reports content_reports moderation_queue
  favorite_lists favorite_items place_submissions"
expected_app="$(sort <<EOF
$postgis
place_sources SELECT
places SELECT
source_records SELECT
sources SELECT
sync_epoch SELECT
place_refresh_queue INSERT
route_restrictions SELECT
routing_graphs SELECT
pois SELECT
poi_join_records SELECT
poi_layer SELECT
place_layer SELECT
place_dots SELECT
poi_cluster_cells SELECT
place_search_words SELECT
place_towns SELECT
poi_confirmations SELECT
poi_confirmations INSERT
poi_confirmations UPDATE
poi_confirmations DELETE
poi_refresh_queue INSERT
poi_moderation SELECT
poi_moderation INSERT
poi_moderation DELETE
road_events SELECT
road_events INSERT
road_events UPDATE
road_event_reports SELECT
road_event_reports INSERT
road_event_reports UPDATE
road_event_sources SELECT
road_event_purges SELECT
road_event_revision_seq USAGE
road_event_report_facts SELECT
idempotency_keys SELECT
idempotency_keys INSERT
idempotency_keys DELETE
region_packs SELECT
place_region_exits SELECT
fuel_price_days SELECT
enforcement_sources SELECT
source_reads SELECT
place_holds SELECT
place_hold_releases INSERT
place_hold_releases SELECT
banned_keys SELECT
banned_keys INSERT
banned_keys DELETE
confirmation_tallies SELECT
confirmation_tallies INSERT
confirmation_tallies UPDATE
confirmation_tallies DELETE
content_photos SELECT
content_descriptions SELECT
content_reviews SELECT
content_hides SELECT
external_ratings SELECT
external_photos DELETE
source_agreements SELECT
source_switches SELECT
source_terms SELECT
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
moderation_queue INSERT
photos SELECT
place_refresh_queue DELETE
place_refresh_queue INSERT
place_refresh_queue SELECT
place_submissions SELECT
place_submissions UPDATE
reviews SELECT
route_restrictions DELETE
route_restrictions INSERT
route_restrictions SELECT
route_restrictions UPDATE
routing_graphs DELETE
routing_graphs INSERT
routing_graphs SELECT
routing_graphs UPDATE
pois INSERT
pois SELECT
pois UPDATE
poi_join_records INSERT
poi_join_records SELECT
poi_join_records UPDATE
poi_layer INSERT
poi_layer SELECT
poi_layer UPDATE
place_layer SELECT
place_layer UPDATE
place_dots SELECT
place_dots INSERT
place_dots UPDATE
place_dots DELETE
place_dot_members SELECT
place_dot_members INSERT
place_dot_members UPDATE
place_dot_members DELETE
place_dot_sources SELECT
poi_cluster_cells SELECT
poi_cluster_cells INSERT
poi_cluster_cells UPDATE
poi_cluster_cells DELETE
poi_cluster_cells_computed SELECT
place_search_words SELECT
place_search_words INSERT
place_search_words DELETE
place_towns SELECT
place_towns INSERT
place_towns UPDATE
place_towns DELETE
poi_confirmations DELETE
poi_confirmations SELECT
poi_refresh_queue DELETE
poi_refresh_queue SELECT
poi_moderation SELECT
road_events SELECT
road_events INSERT
road_events UPDATE
road_events DELETE
road_event_reports DELETE
road_event_sources SELECT
road_event_sources UPDATE
road_event_purges SELECT
road_event_purges UPDATE
road_event_revision_seq USAGE
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
sync_epoch SELECT
place_hold_releases SELECT
place_holds INSERT
place_holds SELECT
takedown_cells INSERT
takedown_cells SELECT
takedown_key INSERT
takedown_key SELECT
confirmation_tallies SELECT
region_packs SELECT
region_packs INSERT
region_packs UPDATE
region_packs DELETE
place_region_exits SELECT
place_region_exits INSERT
fuel_price_days SELECT
fuel_price_days INSERT
fuel_price_days UPDATE
fuel_price_days DELETE
enforcement_devices SELECT
enforcement_devices INSERT
enforcement_devices UPDATE
enforcement_items SELECT
enforcement_items INSERT
enforcement_items UPDATE
enforcement_sources SELECT
enforcement_sources INSERT
enforcement_sources UPDATE
enforcement_revision_seq USAGE
source_reads SELECT
source_reads INSERT
source_reads UPDATE
place_takedowns SELECT
place_takedowns INSERT
content_photos SELECT
content_photos INSERT
content_photos UPDATE
content_photos DELETE
content_descriptions SELECT
content_descriptions INSERT
content_descriptions UPDATE
content_descriptions DELETE
content_reviews SELECT
content_reviews INSERT
content_reviews UPDATE
content_reviews DELETE
content_checks SELECT
content_checks INSERT
content_checks UPDATE
content_checks DELETE
content_hides SELECT
content_hides INSERT
content_hides DELETE
content_review_keys SELECT
content_review_keys INSERT
content_review_strikes SELECT
content_review_strikes INSERT
content_review_sightings SELECT
content_review_sightings INSERT
content_review_sightings DELETE
external_reviews SELECT
external_reviews INSERT
external_reviews UPDATE
external_reviews DELETE
external_ratings SELECT
external_ratings INSERT
external_ratings UPDATE
external_ratings DELETE
external_photos SELECT
external_photos INSERT
external_photos UPDATE
source_agreements SELECT
source_agreements INSERT
source_agreements UPDATE
source_erasures SELECT
source_erasures INSERT
source_switches SELECT
source_switches INSERT
source_switches UPDATE
source_terms SELECT
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
refused "lunaway_app writes a route restriction" /etc/lunaway/api.env "DELETE FROM route_restrictions WHERE false"
refused "lunaway_app activates a routing graph" /etc/lunaway/api.env "UPDATE routing_graphs SET id = id WHERE false"
allowed "lunaway_app reads the routing graphs" /etc/lunaway/api.env "SELECT 'routing graphs: ' || count(*) FROM routing_graphs"
allowed "lunaway_app reads the points of interest" /etc/lunaway/api.env "SELECT 'points: ' || count(*) FROM pois"
refused "lunaway_app writes a point of interest" /etc/lunaway/api.env "UPDATE pois SET name = name WHERE false"
refused "lunaway_app moves the point layer's version" /etc/lunaway/api.env "UPDATE poi_layer SET version = version WHERE false"
refused "lunaway_app moves the places layer's version" /etc/lunaway/api.env "UPDATE place_layer SET version = version WHERE false"
refused "lunaway_app writes a fuel price" /etc/lunaway/api.env "UPDATE poi_join_records SET ref = ref WHERE false"
refused "lunaway_app deletes a road report" /etc/lunaway/api.env "DELETE FROM road_event_reports WHERE false"
refused "lunaway_app deletes a road event" /etc/lunaway/api.env "DELETE FROM road_events WHERE false"
refused "lunaway_app moves a feed's cursor" /etc/lunaway/api.env "UPDATE road_event_sources SET id = id WHERE false"
allowed "lunaway_app writes an account" /etc/lunaway/api.env "BEGIN; UPDATE accounts SET pseudonym = pseudonym WHERE false; ROLLBACK; SELECT 'accounts writable'"
# Regional packs, fuel history and speed cameras (migrations 20261006140000
# to 20261006181000): the API reads what it serves and writes none of it.
allowed "lunaway_app reads the regional packs" /etc/lunaway/api.env "SELECT 'region packs: ' || count(*) FROM region_packs"
refused "lunaway_app writes a regional pack" /etc/lunaway/api.env "UPDATE region_packs SET places = places WHERE false"
refused "lunaway_app writes a region departure" /etc/lunaway/api.env "INSERT INTO place_region_exits SELECT * FROM place_region_exits WHERE false"
refused "lunaway_app writes a fuel price day" /etc/lunaway/api.env "UPDATE fuel_price_days SET low_eur = low_eur WHERE false"
refused "lunaway_app reads the speed camera devices" /etc/lunaway/api.env "SELECT count(*) FROM enforcement_devices"
refused "lunaway_app writes a danger zone" /etc/lunaway/api.env "UPDATE enforcement_items SET kind = kind WHERE false"
refused "lunaway_app reads which camera a zone comes from" /etc/lunaway/api.env "SELECT device_key FROM enforcement_items LIMIT 1"
refused "lunaway_app moves the speed camera revision" /etc/lunaway/api.env "SELECT nextval('enforcement_revision_seq')"
# Taking a place down (migration 20261006193913) is the import role's step:
# a leak of the API's credentials must not empty the catalogue.
refused "lunaway_app reads the takedowns" /etc/lunaway/api.env "SELECT count(*) FROM place_takedowns"
refused "lunaway_app logs a takedown" /etc/lunaway/api.env "INSERT INTO place_takedowns SELECT * FROM place_takedowns WHERE false"
refused "lunaway_app dates a read" /etc/lunaway/api.env "UPDATE source_reads SET read_at = read_at WHERE false"
# The cells around a place taken down and the secret's check value are the
# import role's (migrations 20261006210100 and 20261006210300): the API only
# decides the holds a moderator approves or rejects.
refused "lunaway_app reads the takedown cells" /etc/lunaway/api.env "SELECT count(*) FROM takedown_cells"
refused "lunaway_app reads the takedown key's check" /etc/lunaway/api.env "SELECT count(*) FROM takedown_key"
refused "lunaway_app moves a held place" /etc/lunaway/api.env "UPDATE place_holds SET place_id = place_id WHERE false"
got="$(as_role /etc/lunaway/api.env "
SELECT string_agg(attname, ' ' ORDER BY attname)
FROM pg_attribute
WHERE attrelid = 'enforcement_items'::regclass AND attnum > 0 AND NOT attisdropped
  AND has_column_privilege('enforcement_items', attname, 'SELECT')")"
want="bearing_deg category country deleted_at id kind limit_kmh line point revision source_ids updated_at"
if [ "$got" = "$want" ]; then
  echo "ok   lunaway_app reads these columns of enforcement_items only: $got"
else
  echo "FAIL lunaway_app reads these columns of enforcement_items: $got (want: $want)"
fi

# Only row security keeps the API to the community's road events: the
# grants above cannot show it. Neither role may bypass it, it is on for
# road_events, and an update of an official event matches no row for the
# API (rolled back, and a no-op update anyway).
got="$(as_role /etc/lunaway/api.env "SELECT string_agg(rolname || ' ' || rolbypassrls, ', ' ORDER BY rolname) FROM pg_roles WHERE rolname IN ('lunaway_app', 'lunaway_ingest')")"
if [ "$got" = "lunaway_app false, lunaway_ingest false" ]; then
  echo "ok   no role bypasses row security: $got"
else
  echo "FAIL row security bypass: $got"
fi
got="$(as_role /etc/lunaway/api.env "SELECT relrowsecurity FROM pg_class WHERE oid = 'road_events'::regclass")"
if [ "$got" = t ]; then
  echo "ok   row security is on for road_events"
else
  echo "FAIL row security on road_events: $got"
fi
got="$(as_role /etc/lunaway/api.env "BEGIN; WITH u AS (UPDATE road_events SET description = description WHERE source <> 'community' RETURNING 1)
  SELECT 'rls ' || (SELECT count(*) FROM road_events WHERE source <> 'community') || ' ' || count(*) FROM u; ROLLBACK;" | grep '^rls ')"
if [[ "$got" =~ ^rls\ [1-9][0-9]*\ 0$ ]]; then
  echo "ok   lunaway_app updates no official road event: $(cut -d' ' -f2 <<<"$got") visible, 0 updatable"
else
  echo "FAIL lunaway_app and the official road events: ${got:-no answer} (want: some visible, 0 updatable)"
fi

compare lunaway_ingest /etc/lunaway/ingest.env "$expected_ingest"
allowed "lunaway_ingest reads records" /etc/lunaway/ingest.env "SELECT 'records: ' || count(*) FROM source_records"
refused "lunaway_ingest deletes a place" /etc/lunaway/ingest.env "DELETE FROM places WHERE false"
refused "lunaway_ingest deletes a record" /etc/lunaway/ingest.env "DELETE FROM source_records WHERE false"
refused "lunaway_ingest writes a source" /etc/lunaway/ingest.env "UPDATE sources SET name = name WHERE false"
refused "lunaway_ingest writes the sync epoch" /etc/lunaway/ingest.env "UPDATE sync_epoch SET created_at = created_at WHERE false"
refused "lunaway_ingest decides a held place" /etc/lunaway/ingest.env "UPDATE place_holds SET status = status WHERE false"
refused "lunaway_ingest releases a held place" /etc/lunaway/ingest.env "INSERT INTO place_hold_releases SELECT * FROM place_hold_releases WHERE false"
# The retention's tables (migration 20261007090000): a banned key's hash is
# the API's alone, the tallies of answers are the API's to write.
refused "lunaway_ingest reads a banned key's hash" /etc/lunaway/ingest.env "SELECT count(*) FROM banned_keys"
refused "lunaway_ingest writes an answer tally" /etc/lunaway/ingest.env "DELETE FROM confirmation_tallies WHERE false"
refused "lunaway_ingest writes the migrations table" /etc/lunaway/ingest.env "DELETE FROM _sqlx_migrations WHERE false"
refused "lunaway_ingest creates a table" /etc/lunaway/ingest.env "CREATE TABLE grants_probe (x int)"
refused "lunaway_ingest writes an account" /etc/lunaway/ingest.env "UPDATE accounts SET trust_level = trust_level WHERE false"
refused "lunaway_ingest reads the sessions" /etc/lunaway/ingest.env "SELECT count(*) FROM sessions"
refused "lunaway_ingest reads a pseudonym" /etc/lunaway/ingest.env "SELECT pseudonym FROM accounts LIMIT 1"
refused "lunaway_ingest writes a review" /etc/lunaway/ingest.env "UPDATE reviews SET status = status WHERE false"
refused "lunaway_ingest changes a merge decision" /etc/lunaway/ingest.env "DELETE FROM conflation_constraints WHERE false"
allowed "lunaway_ingest reads the points of interest" /etc/lunaway/ingest.env "SELECT 'points: ' || count(*) FROM pois"
refused "lunaway_ingest deletes a point of interest" /etc/lunaway/ingest.env "DELETE FROM pois WHERE false"
refused "lunaway_ingest writes a point confirmation" /etc/lunaway/ingest.env "INSERT INTO poi_confirmations SELECT * FROM poi_confirmations WHERE false"
refused "lunaway_ingest decides a point's moderation" /etc/lunaway/ingest.env "INSERT INTO poi_moderation SELECT * FROM poi_moderation WHERE false"
refused "lunaway_ingest reads the moderation queue" /etc/lunaway/ingest.env "SELECT count(*) FROM moderation_queue"
refused "lunaway_ingest reads where a road report was made" /etc/lunaway/ingest.env "SELECT geom FROM road_event_reports LIMIT 1"
refused "lunaway_ingest reads a road report's heading" /etc/lunaway/ingest.env "SELECT heading_deg FROM road_event_reports LIMIT 1"
refused "lunaway_ingest writes a road report" /etc/lunaway/ingest.env "UPDATE road_event_reports SET status = status WHERE false"
got="$(as_role /etc/lunaway/ingest.env "
SELECT string_agg(attname, ' ' ORDER BY attname)
FROM pg_attribute
WHERE attrelid = 'road_event_reports'::regclass AND attnum > 0 AND NOT attisdropped
  AND has_column_privilege('road_event_reports', attname, 'SELECT')")"
if [ "$got" = "created_at event_id id kind status value_m" ]; then
  echo "ok   lunaway_ingest reads these columns of road_event_reports only: $got"
else
  echo "FAIL lunaway_ingest reads these columns of road_event_reports: $got (want: created_at event_id id kind status value_m)"
fi
# The community's road events are weighed by the API, through a view that
# names no account (migration 20261006145517): the importers read neither
# the view nor the salt behind its reporter keys.
refused "lunaway_ingest reads which account made a road report" /etc/lunaway/ingest.env "SELECT account_id FROM road_event_reports LIMIT 1"
refused "lunaway_ingest reads the road reports' facts" /etc/lunaway/ingest.env "SELECT count(*) FROM road_event_report_facts"
refused "lunaway_ingest reads the reporter keys' salt" /etc/lunaway/ingest.env "SELECT count(*) FROM road_event_report_salt"
refused "lunaway_app reads the reporter keys' salt" /etc/lunaway/api.env "SELECT count(*) FROM road_event_report_salt"
refused "lunaway_ingest reads the idempotency keys" /etc/lunaway/ingest.env "SELECT count(*) FROM idempotency_keys"
refused "lunaway_ingest deletes a danger zone" /etc/lunaway/ingest.env "DELETE FROM enforcement_items WHERE false"
refused "lunaway_ingest deletes a speed camera" /etc/lunaway/ingest.env "DELETE FROM enforcement_devices WHERE false"
refused "lunaway_ingest rewrites a region departure" /etc/lunaway/ingest.env "UPDATE place_region_exits SET seq = seq WHERE false"
refused "lunaway_ingest rewrites a takedown" /etc/lunaway/ingest.env "UPDATE place_takedowns SET reason = reason WHERE false"
# The database refuses any data for a position in Switzerland
# (docs/speed-cameras.md): no camera, no zone, whatever a source says.
got="$(as_role /etc/lunaway/ingest.env "SELECT (SELECT count(*) FROM enforcement_devices WHERE country = 'CH' OR scope = 'CH') + (SELECT count(*) FROM enforcement_items WHERE country = 'CH')")"
checks="$(as_role /etc/lunaway/ingest.env "SELECT count(*) FROM pg_constraint WHERE conrelid IN ('enforcement_devices'::regclass, 'enforcement_items'::regclass) AND contype = 'c' AND pg_get_constraintdef(oid) LIKE '%<> ''CH''%'")"
if [ "$got" = 0 ] && [ "$checks" -ge 3 ]; then
  echo "ok   no Swiss speed camera data stored, $checks constraints refuse it"
else
  echo "FAIL Swiss speed camera data: $got rows, $checks constraints (want 0 rows, 3 constraints)"
fi
# The importers read every road event and the reports' times: a community
# event must hold no more than the feed publishes (four decimals of a
# degree, about ten metres, and no heading), or a join by event_id would
# give where and when someone stood (migration 20261006144030).
got="$(as_role /etc/lunaway/ingest.env "SELECT count(*) || ' ' || count(*) FILTER (WHERE heading_deg IS NOT NULL
    OR ST_X(geom_source::geometry) <> round(ST_X(geom_source::geometry)::numeric, 4)::double precision
    OR ST_Y(geom_source::geometry) <> round(ST_Y(geom_source::geometry)::numeric, 4)::double precision)
  FROM road_events WHERE source = 'community'")"
if [[ "$got" =~ ^[0-9]+\ 0$ ]]; then
  echo "ok   lunaway_ingest sees community road events at the published precision only: $(cut -d' ' -f1 <<<"$got") events, none finer or with a heading"
else
  echo "FAIL community road events finer than published, as lunaway_ingest sees them: $got (events, finer)"
fi
got="$(as_role /etc/lunaway/ingest.env "$account_columns_sql")"
if [ "$got" = "banned_at id trust_level" ]; then
  echo "ok   lunaway_ingest reads these columns of accounts only: $got"
else
  echo "FAIL lunaway_ingest reads these columns of accounts: $got (want: banned_at id trust_level)"
fi
