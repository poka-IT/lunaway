#!/usr/bin/env bash
# Moves the PostgreSQL cluster 18/main into $PG_DATADIR (common.sh, the root
# disk) from wherever it is registered (the data volume until 2026-10-10).
# Run by hand as root on the backend, once, in a maintenance window: the
# database is stopped while its files are copied (134 s for 19.6 GB read
# from the volume on 2026-10-10).
#
#   sudo bash ~/infra/server/postgres-move.sh --check   what it would do; touches no cluster file
#   sudo bash ~/infra/server/postgres-move.sh           stop, copy, verify, switch, start
#
# Before the second form, stop everything that writes: every lunaway timer
# and path unit (so that no job starts), then the API, the conflation worker
# and any job still running; the script refuses while one is active or a
# client is connected. It never removes anything: the old directory is
# renamed <old>.moved-<UTC stamp> and stays until removed by name once the
# checks are done, within the 30 days the privacy page allows a deleted
# record (docs/deploy.md, "PostgreSQL on the root disk").
. "$(dirname "$0")/common.sh"
need_root
check_only=0
case "${1:-}" in
  --check) check_only=1 ;;
  "") ;;
  *) die "usage: $0 [--check]" ;;
esac
target="$PG_DATADIR"
bindir=/usr/lib/postgresql/18/bin
unit=postgresql@18-main
dropins=/etc/systemd/system/$unit.service.d

current="$(pg_lsclusters --no-header | awk '$1 == 18 && $2 == "main" { print $6 }')"
[ -n "$current" ] || die "no cluster 18/main is registered"
if [ "$current" = "$target" ]; then
  log "cluster 18/main is already in $target"
  exit 0
fi
[ -f "$current/PG_VERSION" ] || die "$current holds no cluster"
# A tablespace, or a journal kept elsewhere, is a symbolic link out of the
# directory, which a copy of the directory would not carry.
[ -z "$(find "$current/pg_tblspc" -mindepth 1 -print -quit)" ] || die "$current has tablespaces; this script moves a cluster without any"
[ ! -L "$current/pg_wal" ] || die "$current/pg_wal is a link; this script moves a cluster whose journal is inside it"
if [ -e "$target" ] && [ -n "$(find "$target" -mindepth 1 -print -quit)" ]; then
  die "$target exists and is not empty"
fi

need_kb="$(du -sk "$current" | awk '{ print $1 }')"
probe="$target"
while [ ! -e "$probe" ]; do probe="$(dirname "$probe")"; done
free_kb="$(df -k --output=avail "$probe" | tail -n 1 | tr -dc '0-9')"
log "cluster 18/main: $current ($(( need_kb / 1024 )) MB) to $target ($(( free_kb / 1024 )) MB free there)"
# Room for the copy, a quarter more for its growth, and the routing graphs'
# refresh, which needs 55 GB free on the same disk for five parts
# (lunaway-routing-refresh).
[ "$free_kb" -gt $(( need_kb * 5 / 4 + 55 * 1024 * 1024 )) ] || die "not enough room for the copy and the routing refresh"

# Clients: nothing that writes may run, or start while the database is down.
active="$(systemctl list-units --no-legend --plain --state=active,activating,deactivating,reloading \
  'lunaway-*.service' 'lunaway-*.timer' 'lunaway-*.path' | awk '{ print $1 }' | grep -vx 'lunaway-tiles.service' || true)"
clients=""
if systemctl is-active --quiet "$unit"; then
  clients="$(runuser -u postgres -- psql -X -At -d postgres -c \
    "select usename || ' ' || coalesce(nullif(application_name, ''), '-') from pg_stat_activity where backend_type = 'client backend' and pid <> pg_backend_pid()")"
fi
if [ -n "$active" ] || [ -n "$clients" ]; then
  echo "still running:"
  [ -z "$active" ] || echo "$active" | sed 's/^/    unit /'
  [ -z "$clients" ] || echo "$clients" | sed 's/^/    session /'
  if [ "$check_only" = 0 ]; then
    die "stop them first: systemctl stop 'lunaway-*.timer' 'lunaway-*.path', then the services above"
  fi
fi
if [ "$check_only" = 1 ]; then
  log "check only: would stop $unit, copy $current to $target, verify, switch, rename $current, start"
  exit 0
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
old="$current.moved-$stamp"
size_before="$(runuser -u postgres -- psql -X -At -d postgres -c "select string_agg(datname || ' ' || pg_database_size(datname), ', ' order by datname) from pg_database")"
# The way back, printed before anything changes, so that it is on screen
# whichever step fails after the switch.
cat <<EOF
Back to the old directory, should a step after the switch fail, while no
client has written yet:
  systemctl stop $unit
  mv $old $current      (when the rename was done)
  pg_conftool 18 main set data_directory $current
  printf '[Service]\nReadWritePaths=%s\n' $current > $dropins/data-directory.conf
  systemctl daemon-reload && systemctl start $unit
EOF

log "stopping $unit"
systemctl stop "$unit"
# state DIR FIELD: one line of pg_controldata, never empty. Called in an
# assignment, so that its failure stops the script (set -e).
state() {
  local value
  value="$(LC_ALL=C "$bindir/pg_controldata" "$1" | sed -n "s/^$2: *//p")"
  [ -n "$value" ] || die "pg_controldata gives no \"$2\" for $1"
  echo "$value"
}
shutdown_state="$(state "$current" 'Database cluster state')"
[ "$shutdown_state" = "shut down" ] || die "the cluster did not shut down cleanly ($shutdown_state); start it again and look"

log "copying"
install -d -o postgres -g postgres -m 0755 "$(dirname "$target")"
start_s="$(date +%s)"
rsync -aH --numeric-ids "$current/" "$target/"
# On the disk before anything relies on the copy: the checks below read the
# page cache, and the old directory is renamed once they pass.
sync -f "$target"
log "copied in $(( $(date +%s) - start_s )) s"

log "verifying"
# Same entries, types, modes and owners, the same target for a link, and
# for files the same sizes and modification times. The time of a directory
# or a link is not compared: rsync 3.5 gave the copies new ones, and
# PostgreSQL reads neither.
manifest() {
  (cd "$1" && find . \( -type d -printf '%p d %m %U %G\n' \) -o \( -type l -printf '%p l %l %U %G\n' \) \
    -o -printf '%p %y %s %m %U %G %T@\n' | LC_ALL=C sort) > "$2"
}
manifest "$current" "$STAGING/postgres-move.old"
manifest "$target" "$STAGING/postgres-move.new"
entries="$(wc -l < "$STAGING/postgres-move.new")"
[ "$entries" -gt 100 ] || die "the manifest of the copy holds $entries entries; nothing was switched, start $unit to serve from $current again"
if ! diff "$STAGING/postgres-move.old" "$STAGING/postgres-move.new" > "$STAGING/postgres-move.diff"; then
  head -n 20 "$STAGING/postgres-move.diff"
  die "the copy differs from $current; nothing was switched, start $unit to serve from $current again"
fi
echo "    $entries entries alike"
# Every data page against its checksum (the cluster has data checksums).
runuser -u postgres -- "$bindir/pg_checksums" --check -D "$target" | sed 's/^/    /' \
  || die "pg_checksums found a bad page in the copy; nothing was switched, start $unit to serve from $current again"
for field in 'Database cluster state' 'Latest checkpoint location' 'Database system identifier'; do
  was="$(state "$current" "$field")"
  now="$(state "$target" "$field")"
  [ "$was" = "$now" ] || die "$field differs between the two copies ($was, $now)"
done
echo "    pg_controldata: same state, checkpoint and system identifier"

log "switching to $target"
pg_conftool 18 main set data_directory "$target"
install_file systemd/postgresql@18-main.service.d/lunaway.conf "$dropins/lunaway.conf" 0644 || true
pg_datadir_dropin "$STAGING/postgresql-data-directory.conf"
install_file "$STAGING/postgresql-data-directory.conf" "$dropins/data-directory.conf" 0644 || true
systemctl daemon-reload
# The old directory out of the way, so nothing can start on it by mistake.
mv "$current" "$old"

log "starting $unit"
systemctl start "$unit"
for _ in $(seq 1 30); do runuser -u postgres -- pg_isready -q && break; sleep 1; done
runuser -u postgres -- pg_isready -q || die "PostgreSQL does not answer; see journalctl -u $unit"
served="$(runuser -u postgres -- psql -X -At -d postgres -c 'show data_directory')"
[ "$served" = "$target" ] || die "PostgreSQL serves $served"
size_after="$(runuser -u postgres -- psql -X -At -d postgres -c "select string_agg(datname || ' ' || pg_database_size(datname), ', ' order by datname) from pg_database")"
echo "    database sizes before: $size_before"
echo "    database sizes after:  $size_after"
# The files were compared above; a size that moved means something wrote
# since the start (autovacuum, or the removal of temporary files at start),
# worth a look rather than a stop.
[ "$size_before" = "$size_after" ] || echo "    note: the sizes moved since the start"
log "moved: $unit serves $target; the old directory is $old"
