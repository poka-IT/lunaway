#!/usr/bin/env bash
# PostgreSQL 18 and PostGIS 3.6 from the PostgreSQL project's repository
# (PGDG), run as root by setup.sh. The cluster lives on the root disk
# ($PG_DATADIR, common.sh), listens on localhost only, authenticates with
# SCRAM, and is tuned from the machine's memory, so a second run after a
# resize retunes it. The nightly dumps stay on the data volume, another
# disk than the database's.
#
# Database lunaway, owned by lunaway_owner (`lunaway migrate`, DDL);
# lunaway_app (the API) and lunaway_ingest (`lunaway ingest` and `lunaway
# conflate`) get no privilege here beyond connecting: the migrations grant
# each of them what it needs, table by table. Their passwords are generated
# here once and kept in /etc/lunaway/{owner,api,ingest}.env (root, 0600).
. "$(dirname "$0")/common.sh"
need_root
datadir="$PG_DATADIR"
confdir=/etc/postgresql/18/main
dropins=/etc/systemd/system/postgresql@18-main.service.d

log "PGDG repository"
apt_install postgresql-common
if ! grep -rqs apt.postgresql.org /etc/apt/sources.list.d/; then
  # Debian's helper writes the source with the PGDG key that postgresql-common ships.
  /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y >/dev/null
fi
# Debian's default cluster would be created without our locale provider and
# checksums; ours is created below.
sed -i 's/^#\?\s*create_main_cluster\s*=.*/create_main_cluster = false/' /etc/postgresql-common/createcluster.conf
grep -qx 'create_main_cluster = false' /etc/postgresql-common/createcluster.conf || die "cannot disable the default cluster"

log "packages"
packages="postgresql-18 postgresql-18-postgis-3 postgresql-18-postgis-3-scripts"
# Updates come from unattended-upgrades; the package lists are refreshed
# here only to install, so that retuning after a resize does not hang on
# another source of the machine (Caddy's answered 402 on 2026-10-10).
# shellcheck disable=SC2086 # one package per word
if dpkg-query -W -f '${Status}\n' $packages 2>/dev/null | grep -qvx 'install ok installed' \
  || [ "$(dpkg-query -W -f '${Status}\n' $packages 2>/dev/null | wc -l)" -ne 3 ]; then
  apt-get update -q >/dev/null
  # shellcheck disable=SC2086
  apt_install $packages
fi

log "cluster on the root disk"
current="$(pg_lsclusters --no-header | awk '$1 == 18 && $2 == "main" { print $6 }')"
if [ -z "$current" ]; then
  # A new server, or a rebuilt one: the root disk is new, so the cluster
  # starts empty and the data comes back from the latest dump
  # (docs/deploy.md, "Backups and restore"). A cluster left on the data
  # volume by the layout before 2026-10-10 is never taken over silently.
  [ ! -e /srv/data/postgresql/18/main/PG_VERSION ] \
    || die "a cluster of the old layout is on the data volume: take it over (pg_createcluster 18 main --datadir=/srv/data/postgresql/18/main) and move it with postgres-move.sh, or move it aside and restore a dump"
  install -d -o postgres -g postgres -m 0755 "$(dirname "$datadir")"
  pg_createcluster 18 main --datadir="$datadir" --locale=C.UTF-8 --start-conf=auto -- \
    --locale-provider=builtin --builtin-locale=C.UTF-8 --data-checksums >/dev/null
  echo "    created cluster 18/main in $datadir"
elif [ "$current" != "$datadir" ]; then
  die "cluster 18/main is in $current, not in $datadir: move it first, in a maintenance window (sudo bash ~/infra/server/postgres-move.sh, docs/deploy.md)"
fi

restart=0 reload=0
# Client authentication is re-read on a reload; the API keeps its connections.
install_file files/etc/postgresql/18/main/pg_hba.conf "$confdir/pg_hba.conf" 0640 && reload=1
chown postgres:postgres "$confdir/pg_hba.conf"
install_file systemd/postgresql@18-main.service.d/lunaway.conf "$dropins/lunaway.conf" 0644 && restart=1
pg_datadir_dropin "$STAGING/postgresql-data-directory.conf"
install_file "$STAGING/postgresql-data-directory.conf" "$dropins/data-directory.conf" 0644 && restart=1
if [ "$restart" = 1 ]; then systemctl daemon-reload; fi

# Tuning from the memory and cores of this machine (shared_buffers needs a
# restart, so the file is only rewritten when a value changes). The other
# tenants of the backend hold about 21 GB at their caps: the routing engine
# 6 GB (its tiles' pages included), the API 1.5 GB, an import reading an
# extract 3 GB, Caddy, the tile server and the system about 1.5 GB; and
# since the servers were merged (2026-10-10), Photon's two JVMs (heaps of
# 2 GB and 512 MB, and the JVM's own) about 3.5 GB, the translation server
# 4.5 GB, the crawler 0.6 GB and Gatus 0.5 GB.
mem="$(mem_mb)"
cores="$(nproc)"
others=21504
# A parallel query takes up to this many processes besides its own; on 16
# shared vCPUs, half of them would crowd the API and the routing engine.
half_cores=$(( cores / 2 > 4 ? 4 : (cores / 2 > 0 ? cores / 2 : 1) ))
# Index builds of the migrations over millions of rows use it whole.
maintenance=$(( mem / 16 < 2048 ? mem / 16 : 2048 ))
# Three autovacuum workers at most, each bounded on its own.
autovacuum=$(( maintenance < 512 ? maintenance : 512 ))
# At 61 MB no statement of the API spilled to disk in three days; the
# imports' did, 82 MB on disk in the median. 61 MB is 1/512 of 32 GB: the
# sessions' sorts share the memory with the other tenants.
work=$(( mem / 512 > 4 ? mem / 512 : 4 ))
# An eighth of the memory (3.9 GB on 32 GB, what it had alone on 16 GB):
# the rest of the database's hot pages sit in the page cache, which the
# other tenants share; a quarter would take memory from them twice.
buffers=$(( mem / 8 ))
# What the planner may count on finding in memory: the shared buffers and
# the page cache the other tenants leave.
cache=$(( mem - others > mem / 4 ? mem - others : mem / 4 ))
max_wal=2GB
[ "$mem" -ge 8000 ] && max_wal=4GB
cat > "$STAGING/90-lunaway.conf" <<EOF
# Written by infra/server/postgres.sh for ${mem} MB of RAM and ${cores} cores.
# Edit the script, not this file: the next run rewrites it.
listen_addresses = 'localhost'
port = 5432
max_connections = 50
password_encryption = 'scram-sha-256'

shared_buffers = ${buffers}MB
effective_cache_size = ${cache}MB
work_mem = ${work}MB
maintenance_work_mem = ${maintenance}MB
autovacuum_work_mem = ${autovacuum}MB
huge_pages = try

wal_compression = zstd
min_wal_size = 256MB
max_wal_size = ${max_wal}
checkpoint_completion_target = 0.9

random_page_cost = 1.1
effective_io_concurrency = 64
max_worker_processes = $(( cores > 8 ? cores : 8 ))
max_parallel_workers = ${cores}
max_parallel_workers_per_gather = ${half_cores}
max_parallel_maintenance_workers = ${half_cores}
jit = off

shared_preload_libraries = 'pg_stat_statements'
timezone = 'UTC'
log_timezone = 'UTC'
log_line_prefix = '%m [%p] %q%u@%d '
log_min_duration_statement = 1s
# Slow statements are logged without their bound values, which may be
# personal data (a position, a pseudonym).
log_parameter_max_length = 0
log_parameter_max_length_on_error = 0
log_lock_waits = on
log_temp_files = 64MB
log_autovacuum_min_duration = 10s
EOF
install_file "$STAGING/90-lunaway.conf" "$confdir/conf.d/90-lunaway.conf" 0644 && restart=1

systemctl enable --quiet postgresql
if [ "$restart" = 1 ] || ! systemctl is-active --quiet postgresql@18-main; then
  systemctl restart postgresql@18-main
elif [ "$reload" = 1 ]; then
  systemctl reload postgresql@18-main
fi
for _ in $(seq 1 30); do runuser -u postgres -- pg_isready -q && break; sleep 1; done
runuser -u postgres -- pg_isready -q || die "PostgreSQL does not answer"

psql_admin() { runuser -u postgres -- psql -X -q -v ON_ERROR_STOP=1 "$@"; }

log "roles and database"
psql_admin -d postgres <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'lunaway_owner') THEN
    CREATE ROLE lunaway_owner LOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'lunaway_app') THEN
    CREATE ROLE lunaway_app LOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'lunaway_ingest') THEN
    CREATE ROLE lunaway_ingest LOGIN;
  END IF;
END
$$;
-- Caps under max_connections (50, 3 kept for superusers), 45 in all:
--   lunaway_app 25: the API's pool (LUNAWAY_DB_POOL_SIZE, 16) and one
--     lunaway-admin moderation or accounts run (4);
--   lunaway_ingest 15: the conflation worker (a pool of 4 and its LISTEN
--     connection), an import (4) and the conflation its success starts or a
--     lunaway-admin run (4);
--   lunaway_owner 5: the migrations.
ALTER ROLE lunaway_owner NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 5;
ALTER ROLE lunaway_app NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 25;
ALTER ROLE lunaway_ingest NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 15;
-- An import or a conflation runs longer than an API request.
ALTER ROLE lunaway_ingest SET statement_timeout = '10min';
ALTER ROLE lunaway_ingest SET idle_in_transaction_session_timeout = '5min';
-- Bounds on what one API session can hold.
ALTER ROLE lunaway_app SET statement_timeout = '15s';
ALTER ROLE lunaway_app SET lock_timeout = '5s';
ALTER ROLE lunaway_app SET idle_in_transaction_session_timeout = '30s';
SELECT 'CREATE DATABASE lunaway OWNER lunaway_owner'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'lunaway') \gexec
SQL

psql_admin -d lunaway <<'SQL'
REVOKE ALL ON DATABASE lunaway FROM PUBLIC;
GRANT CONNECT ON DATABASE lunaway TO lunaway_app, lunaway_ingest;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
-- Since PostgreSQL 15 the public schema belongs to the database owner and
-- PUBLIC cannot create in it. The two row roles may look up names in it;
-- which tables and sequences they may touch is granted per object by the
-- migrations (backend/migrations), never by default for every future table.
-- Default privileges an earlier version of this script granted are taken
-- back (a no-op when there are none).
GRANT USAGE ON SCHEMA public TO lunaway_app, lunaway_ingest;
-- pg_stat_statements makes its views readable by PUBLIC; only the
-- administrator reads them.
REVOKE ALL ON pg_stat_statements, pg_stat_statements_info FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE lunaway_owner IN SCHEMA public
  REVOKE ALL ON TABLES FROM lunaway_app, lunaway_ingest;
ALTER DEFAULT PRIVILEGES FOR ROLE lunaway_owner IN SCHEMA public
  REVOKE ALL ON SEQUENCES FROM lunaway_app, lunaway_ingest;
SQL

log "credentials"
install -d -m 0700 -o root -g root /etc/lunaway
# set_password ROLE ENV_FILE: reuses the password already in ENV_FILE, or
# creates one; sets it on the role either way. Never printed.
set_password() {
  local role="$1" file="$2" pw=""
  if [ -f "$file" ]; then
    pw="$(sed -n "s|^DATABASE_URL=postgres://$role:\([A-Za-z0-9]*\)@.*|\1|p" "$file")"
  fi
  if [ -z "$pw" ]; then
    pw="$(random_password)"
    ( umask 077
      grep -v '^DATABASE_URL=' "$file" 2>/dev/null > "$file.new" || true
      echo "DATABASE_URL=postgres://$role:$pw@127.0.0.1:5432/lunaway" >> "$file.new"
      mv "$file.new" "$file" )
    echo "    new password for $role in $file"
  fi
  chmod 0600 "$file"
  chown root:root "$file"
  # The statement carries the password in clear. pg_stat_statements keeps the
  # text of a utility statement as written, and a statement that fails or
  # runs long is logged with its text, so all of that is off for this one
  # session.
  printf "SET pg_stat_statements.track_utility = off;\nSET log_statement = 'none';\nSET log_min_error_statement = panic;\nSET log_min_duration_statement = -1;\nALTER ROLE %s PASSWORD '%s';\n" "$role" "$pw" \
    | psql_admin -d postgres
}
set_password lunaway_owner /etc/lunaway/owner.env
set_password lunaway_app /etc/lunaway/api.env
set_password lunaway_ingest /etc/lunaway/ingest.env
# Statements recorded by an earlier version of this script, which set the
# passwords with tracking on, are dropped with the rest of the statistics.
# Only role statements count: the catalog queries of pg_dump and pg_dumpall
# name password columns and hold no secret.
cleared="$(psql_admin -d lunaway -At -c "SELECT count(*) FROM pg_stat_statements WHERE query ~* '^\s*(alter|create)\s+(role|user)\M.*\mpassword\M'")"
if [ "$cleared" != 0 ]; then
  psql_admin -d lunaway -At -c "SELECT pg_stat_statements_reset()" >/dev/null
  echo "    pg_stat_statements held $cleared statement(s) with a password: statistics reset"
fi

log "check"
psql_admin -d lunaway -At <<'SQL'
SELECT 'server ' || current_setting('server_version');
SELECT 'postgis ' || postgis_lib_version() || ', geos ' || postgis_geos_version() || ', proj ' || postgis_proj_version();
SELECT 'extensions ' || string_agg(extname || ' ' || extversion, ', ' ORDER BY extname) FROM pg_extension;
SELECT 'data_checksums ' || current_setting('data_checksums') || ', shared_buffers ' || current_setting('shared_buffers')
  || ', listen ' || current_setting('listen_addresses') || ', collation provider ' || datlocprovider::text || ' ' || coalesce(datlocale, datcollate)
FROM pg_database WHERE datname = 'lunaway';
SQL
