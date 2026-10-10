#!/usr/bin/env bash
# Read-only inspection of a Lunaway server from the inside, run as root by
# infra/verify.sh: effective SSH settings, firewall, fail2ban, listening
# sockets, sandbox scores, kernel settings, updates; on the backend also
# PostgreSQL, credentials, backups, the API, the data pipeline and what the
# ops server may read; on the ops server Gatus, the status page and the dump
# replica. Key material is never printed: authorized_keys lines show their
# options with the key replaced.
#
#   sudo bash ~/infra/server/inspect.sh backend|ops
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run as root (sudo)" >&2; exit 1; }
server_role="${1:?backend or ops}"
masked_keys() { sed -E 's/ssh-ed25519 [A-Za-z0-9+\/=]+.*$/ssh-ed25519 <key>/' "$1"; }

echo "--- sshd effective settings"
sshd -T 2>/dev/null | grep -E '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|authenticationmethods|allowusers|maxauthtries|logingracetime|x11forwarding|allowtcpforwarding|allowagentforwarding|kexalgorithms|ciphers|macs|hostkeyalgorithms|persourcepenalties) '
ls /etc/ssh/sshd_config.d/
echo "--- accounts with a login shell"
awk -F: '$7 !~ /(nologin|false|sync)$/ { print $1, $7 }' /etc/passwd
echo "--- nftables (terse: set elements, which hold client addresses, left out)"
nft -t list ruleset
echo "--- fail2ban"
fail2ban-client status
fail2ban-client status sshd
grep -h '^ignoreip' /etc/fail2ban/jail.d/lunaway-ignore.local
echo "--- listening sockets"
ss -tulpnH | awk '{ print $1, $5, $7 }' | sort
echo "--- systemd-analyze security"
units="ssh caddy"
[ "$server_role" = backend ] && units="lunaway-api caddy lunaway-pgdump lunaway-media-offsite lunaway-deletions-offsite lunaway-takedowns-offsite postgresql@18-main lunaway-migrate lunaway-ingest-osm lunaway-ingest-osm-europe@Mon lunaway-conflate lunaway-conflate-worker lunaway-worker-status lunaway-packs lunaway-cameras lunaway-enforcement lunaway-tiles lunaway-tiles-refresh lunaway-tiles-packs ssh"
[ "$server_role" = ops ] && units="gatus caddy lunaway-replica ssh"
for unit in $units; do
  printf '%-22s %s\n' "$unit" "$(systemd-analyze security "$unit" 2>/dev/null | tail -n 1)"
done
echo "--- kernel"
sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.all.accept_redirects net.ipv6.conf.all.accept_redirects net.ipv4.tcp_syncookies kernel.kptr_restrict kernel.dmesg_restrict kernel.unprivileged_bpf_disabled fs.protected_symlinks fs.protected_hardlinks fs.suid_dumpable kernel.yama.ptrace_scope
echo "AppArmor: $(aa-enabled), $(aa-status --profiled 2>/dev/null) profiles loaded, $(aa-status --enforced 2>/dev/null) enforced"
echo "--- time, swap, journal, disks, mounts"
chronyc -n tracking | grep -E 'Reference ID|System time|Leap status'
swapon --show
grep -E '^[^#].* swap ' /etc/fstab || echo "fstab: no swap line"
journalctl --disk-usage
df -h / /srv/data | sed 1d
[ -d /srv/tiles ] && df -h /srv/tiles | sed 1d
findmnt -no SOURCE,TARGET,OPTIONS /srv/data
[ -d /srv/tiles ] && findmnt -no SOURCE,TARGET,OPTIONS /srv/tiles
grep -vE '^#|^$' /etc/fstab | awk '{ print $2, $3 }'
ip -brief address
echo "--- updates"
systemctl is-enabled unattended-upgrades apt-daily.timer apt-daily-upgrade.timer
systemctl list-timers --no-pager | grep -E 'apt-daily|lunaway' | awk '{ print $(NF-1), $NF }'
unattended-upgrade --dry-run --debug 2>&1 | grep -E 'Allowed origins' | head -n 1
# Caddy's former apt repository answers 402 (common.sh); apt.systemd.daily
# reports success all the same, so the sources are read here.
if grep -rqs 'dl\.cloudsmith\.io' /etc/apt/sources.list /etc/apt/sources.list.d/; then
  echo "FAIL an apt source names dl.cloudsmith.io, Caddy's former repository: run the caddy (backend) or ops-status (ops) step"
else
  echo "ok   no apt source names Caddy's former repository"
fi
# The release pinned in infra/caddy/version.sh, which verify.sh uploads
# beside infra/server/; apt's candidate the installed package (no Debian
# caddy above it, the apt preferences); a running Caddy started from the
# binary in place (one replaced under it shows as "(deleted)").
pinned="$(sed -n 's/^CADDY_VERSION=//p' "$(dirname "$0")/../caddy/version.sh" 2>/dev/null)"
installed="$(dpkg-query -W -f '${Version}' caddy 2>/dev/null)"
candidate="$(apt-cache policy caddy 2>/dev/null | awk '$1 == "Candidate:" { print $2 }')"
binary="$(caddy version 2>/dev/null | cut -d' ' -f1)"
exe="$(readlink "/proc/$(systemctl show -p MainPID --value caddy)/exe" 2>/dev/null)"
if [ -n "$pinned" ] && [ "$installed" = "$pinned" ] && [ "$candidate" = "$pinned" ] && [ "$binary" = "v$pinned" ] \
  && [ "$exe" = /usr/bin/caddy ]; then
  echo "ok   caddy $installed, the pinned release and apt's candidate, running from /usr/bin/caddy"
else
  echo "FAIL caddy package ${installed:-absent}, apt candidate ${candidate:-none}, binary ${binary:-absent}, running ${exe:-nothing}, pinned ${pinned:-unknown}"
fi
echo "--- units"
systemctl list-unit-files --no-pager --no-legend 'lunaway*' 'gatus*' | awk '{ print $1, $2 }'
systemctl --failed --no-legend --no-pager

if [ "$server_role" = ops ]; then
  echo "--- Gatus"
  systemctl is-active gatus caddy
  stat -c '%a %U:%G %n' /etc/gatus /etc/gatus/config.yaml /usr/local/bin/gatus /etc/lunaway-ops /etc/lunaway-ops/*
  sha256sum /usr/local/bin/gatus | cut -c1-64
  curl -fsS -m 10 http://127.0.0.1:8080/api/v1/endpoints/statuses | python3 -c '
import json, sys
for e in json.load(sys.stdin):
    r = (e.get("results") or [{}])[-1]
    print("  %-8s %-16s %s %s" % (e.get("group"), e.get("name"), "ok  " if r.get("success") else "FAIL", r.get("timestamp", "")))'
  echo "--- dump replica"
  stat -c '%a %U:%G %n' /srv/data/backups/postgresql
  ls -l /srv/data/backups/postgresql
  systemctl status lunaway-replica.service --no-pager -n 3 | tail -n 4
  echo "--- the Mac's pull account"
  stat -c '%a %U:%G %n' /var/lib/lunaway-pull/.ssh/authorized_keys
  masked_keys /var/lib/lunaway-pull/.ssh/authorized_keys
  exit 0
fi

echo "--- PostgreSQL"
runuser -u postgres -- psql -X -At -d lunaway -c "select 'version ' || current_setting('server_version') || ', postgis ' || postgis_lib_version() || ', listen ' || current_setting('listen_addresses') || ', password_encryption ' || current_setting('password_encryption') || ', data_directory ' || current_setting('data_directory')"
# Where the cluster must be: PG_DATADIR of common.sh, uploaded beside this
# script, on the root disk.
expected="$(sed -n 's/^PG_DATADIR=//p' "$(dirname "$0")/common.sh")"
datadir="$(runuser -u postgres -- psql -X -At -d lunaway -c 'show data_directory')"
if [ -n "$expected" ] && [ "$datadir" = "$expected" ] && [ "$(findmnt -n -o TARGET -T "$datadir")" = / ]; then
  echo "ok   data directory $datadir, on the root disk ($(findmnt -n -o SOURCE -T "$datadir"))"
else
  echo "FAIL data directory $datadir on $(findmnt -n -o SOURCE,TARGET -T "$datadir"), expected ${expected:-PG_DATADIR of common.sh} on the root disk"
fi
# A directory postgres-move.sh left: a copy of the database as it stood
# then, which must go well within the 30 days the privacy page allows a
# deleted record (docs/deploy.md, "PostgreSQL on the root disk").
for old in /srv/data/postgresql/18/main.moved-*; do
  [ -d "$old" ] || continue
  s="${old##*.moved-}"
  t="$(date -u -d "${s:0:4}-${s:4:2}-${s:6:2} ${s:9:2}:${s:11:2}:${s:13:2}" +%s 2>/dev/null || echo 0)"
  days=$(( ($(date +%s) - t) / 86400 ))
  if [ "$days" -ge 7 ]; then
    echo "FAIL an old data directory is still on the volume after $days days: $old; remove it by its name"
  else
    echo "note an old data directory is on the volume since $days days: $old; remove it by its name after 48 hours"
  fi
done
runuser -u postgres -- psql -X -At -d lunaway -c "select 'extensions: ' || string_agg(extname || ' ' || extversion, ', ' order by extname) from pg_extension"
runuser -u postgres -- psql -X -At -d postgres -c "select 'role ' || rolname || ': login=' || rolcanlogin || ' super=' || rolsuper || ' createdb=' || rolcreatedb || ' createrole=' || rolcreaterole || ' conn_limit=' || rolconnlimit from pg_roles where rolname like 'lunaway%' order by 1"
runuser -u postgres -- psql -X -At -d lunaway -c "select 'default privileges: ' || count(*) from pg_default_acl"
runuser -u postgres -- psql -X -At -d lunaway -c "select 'pg_stat_statements role statements with a password: ' || count(*) from pg_stat_statements where query ~* '^\s*(alter|create)\s+(role|user)\M.*\mpassword\M'"
grep -v '^#' /etc/postgresql/18/main/pg_hba.conf | grep -v '^$'
echo "--- logins with the generated credentials (password through the environment, never printed)"
for f in /etc/lunaway/api.env /etc/lunaway/ingest.env /etc/lunaway/owner.env; do
  url="$(sed -n 's/^DATABASE_URL=//p' "$f")"
  role="$(sed -n 's|^postgres://\([^:]*\):.*|\1|p' <<<"$url")"
  printf '%s as %s: ' "$f" "$role"
  PGPASSWORD="$(sed -n 's|^postgres://[^:]*:\([^@]*\)@.*|\1|p' <<<"$url")" \
    psql -X -At -h 127.0.0.1 -U "$role" -d lunaway \
    -c "select 'connected as ' || current_user || ', ssl ' || coalesce((select ssl::text from pg_stat_ssl where pid = pg_backend_pid()), '?') || ', may create in public: ' || has_schema_privilege('public', 'CREATE')" 2>&1 | head -n 1
done
echo "--- secrets files"
stat -c '%a %U:%G %n' /etc/lunaway /etc/lunaway/*
echo "--- backups"
stat -c '%a %U:%G %n' /srv/data/backups/postgresql /var/backups/lunaway/postgresql /srv/data/backups/offsite
ls -l /srv/data/backups/postgresql /var/backups/lunaway/postgresql /srv/data/backups/offsite
systemctl list-timers --no-pager --no-legend lunaway-pgdump.timer | awk '{ print "next dump:", $1, $2, $3 }'
systemctl show -p After apt-daily-upgrade.service | tr ' ' '\n' | grep -x 'lunaway-pgdump.service' || echo "apt-daily-upgrade is NOT ordered after the dump"
echo "--- API"
systemctl is-active lunaway-api caddy postgresql@18-main
readlink /opt/lunaway/current
ls /opt/lunaway/current/
echo "--- data pipeline"
systemctl is-enabled lunaway-ingest-osm.timer lunaway-ingest-atout-france.timer lunaway-worker-status.timer 2>&1 | tr '\n' ' '
echo
echo "nightly conflation timer (retired): $(systemctl is-enabled lunaway-conflate.timer 2>&1 | head -n 1)"
echo "conflation worker: $(systemctl is-active lunaway-conflate-worker), restarts $(systemctl show -p NRestarts --value lunaway-conflate-worker), user $(systemctl show -p User --value lunaway-conflate-worker)"
echo "worker queues: $(cat /var/lib/lunaway-status/worker.json 2>/dev/null || echo none)"
journalctl -u lunaway-conflate-worker -n 2 --no-pager -o cat
echo "connection limits: $(runuser -u postgres -- psql -X -At -d postgres -c "select string_agg(rolname || ' ' || rolconnlimit, ', ' order by rolname) from pg_roles where rolname like 'lunaway%'")"
echo "--- photos"
echo "API user: $(systemctl show -p User --value lunaway-api), dynamic: $(systemctl show -p DynamicUser --value lunaway-api)"
stat -c '%a %U:%G %n' /srv/data/ingest /srv/data/media /srv/data/account-deletions /etc/lunaway/media.env /usr/local/sbin/lunaway-admin
sed -n 's/^LUNAWAY_MEDIA_BASE_URL=//p' /etc/lunaway/media.env
echo "photo files: $(find /srv/data/media/photos -type f 2>/dev/null | wc -l), $(du -sh /srv/data/media 2>/dev/null | cut -f1)"
echo "encrypted copy: $(find /srv/data/backups/offsite/media -type f -name '*.webp.age' 2>/dev/null | wc -l) files, last-success $(cat /srv/data/backups/offsite/media/last-success 2>/dev/null || echo none)"
echo "deletion journal: $(find /srv/data/account-deletions -maxdepth 1 -type f -name 'accounts-*.jsonl' 2>/dev/null | wc -l) days, encrypted copy last-success $(cat /srv/data/backups/offsite/account-deletions/last-success 2>/dev/null || echo none)"
echo "--- basemap"
systemctl is-active lunaway-tiles
echo "refresh timer: $(systemctl is-enabled lunaway-tiles-refresh.timer), next $(systemctl list-timers --no-pager --no-legend lunaway-tiles-refresh.timer | awk '{ print $1, $2, $3 }')"
echo "last refresh: $(systemctl show -p Result --value lunaway-tiles-refresh), $(journalctl -u lunaway-tiles-refresh --no-pager -n 1 -o cat 2>/dev/null)"
echo "$(/usr/local/bin/pmtiles version | cut -d, -f1), sha256 $(sha256sum /usr/local/bin/pmtiles | cut -c1-64)"
echo "basemaps-assets: $(cat /srv/tiles/assets/.basemaps-assets 2>/dev/null || echo none)"
stat -c '%a %U:%G %n' /srv/tiles /srv/tiles/builds /srv/tiles/serve /srv/tiles/tilejson /srv/tiles/assets /srv/tiles/packs
ls -l /srv/tiles/builds /srv/tiles/serve
echo "local tile z0: $(curl -sS -o /dev/null -w '%{http_code} %{size_download} bytes in %{time_total}s' -m 10 http://127.0.0.1:8485/planet/0/0/0.mvt)"
# pmtiles logs each request path; the unit's LogFilterPatterns keeps them out.
echo "request lines from pmtiles in the journal (should be 0): $(journalctl -u lunaway-tiles --no-pager -o cat | grep -cE 'served [0-9]+|[^-]fetching|fetched')"
echo "--- points of interest"
for t in lunaway-ingest-pois lunaway-ingest-fuel lunaway-ingest-laposte lunaway-ingest-finess; do
  echo "$t: timer $(systemctl is-enabled "$t.timer" 2>&1 | head -n 1), next $(systemctl list-timers --no-pager --no-legend "$t.timer" | awk '{ print $1, $2, $3 }'), last run $(systemctl show -p Result --value "$t"), $(journalctl -u "$t" --no-pager -n 1 -o cat 2>/dev/null | cut -c1-100)"
done
echo "fuel feed age: $(sed -nE 's/.*"fuel_age_s" *: *(-?[0-9]+).*/\1/p' /var/lib/lunaway-status/worker.json 2>/dev/null) s"
echo "layer: $(runuser -u postgres -- psql -X -At -d lunaway -c "select count(*) || ' points, ' || count(*) filter (where hidden) || ' hidden, version ' || (select max(version) from poi_layer) from pois where deleted_at is null" 2>&1 | head -n 1)"
echo "cache: $(du -sh /srv/data/ingest/raw/fuel /srv/data/ingest/raw/laposte /srv/data/ingest/raw/finess 2>/dev/null | awk '{ print $2 " " $1 }' | tr '\n' ' ')"
echo "--- road events"
for t in lunaway-road-events lunaway-road-events-dialog lunaway-road-events-ndw; do
  echo "$t: timer $(systemctl is-enabled "$t.timer" 2>&1 | head -n 1), next $(systemctl list-timers --no-pager --no-legend "$t.timer" | awk '{ print $1, $2, $3 }'), last run $(systemctl show -p Result --value "$t")"
done
echo "matching: $(runuser -u postgres -- psql -X -At -d lunaway -c "select string_agg(match_quality || ' ' || n, ', ' order by match_quality) from (select match_quality, count(*) n from road_events where ended_at is null group by 1) s" 2>&1 | head -n 1)"
echo "engine in the last hour: $(journalctl -u lunaway-road-events --since -1h --no-pager -o cat | grep -c 'the routing engine refused a road event') events refused, $(journalctl -u lunaway-road-events --since -1h --no-pager -o cat | grep -c 'the routing engine failed') passes stopped by a failure"
echo "refused and unplaced: $(runuser -u postgres -- psql -X -At -d lunaway -c "select count(*) || ' events, ' || count(*) filter (where match_attempts >= 3) || ' given up on this graph' from road_events where ended_at is null and match_error is not null" 2>&1 | head -n 1)"
echo "cache: $(du -sh /srv/data/ingest/raw/road-events 2>/dev/null | cut -f1)"
echo "--- OpenStreetMap, France daily and Europe weekly"
for t in lunaway-ingest-osm lunaway-ingest-pois; do
  echo "$t: timer $(systemctl is-enabled "$t.timer" 2>&1 | head -n 1), next $(systemctl list-timers --no-pager --no-legend "$t.timer" | awk '{ print $1, $2, $3 }'), last run $(systemctl show -p Result --value "$t")"
done
for d in $(sed -nE 's/^LUNAWAY_EXTRACTS_([A-Z][a-z]{2})=.*/\1/p' /usr/local/share/lunaway/osm-extracts.env 2>/dev/null); do
  echo "$d: $(sed -nE "s/^LUNAWAY_EXTRACTS_$d=//p" /usr/local/share/lunaway/osm-extracts.env | sed 's/--extract //g'); places timer $(systemctl is-enabled "lunaway-ingest-osm-europe@$d.timer" 2>&1 | head -n 1), last run $(systemctl show -p Result --value "lunaway-ingest-osm-europe@$d"); points timer $(systemctl is-enabled "lunaway-ingest-pois-europe@$d.timer" 2>&1 | head -n 1), last run $(systemctl show -p Result --value "lunaway-ingest-pois-europe@$d")"
done
echo "records by country: $(runuser -u postgres -- psql -X -At -d lunaway -c "select string_agg(coalesce(scope, '-') || ' ' || n, ', ' order by n desc) from (select scope, count(*) n from source_records where source_id = 'osm' and deleted_at is null group by 1) s" 2>&1 | head -n 1)"
echo "points by country: $(runuser -u postgres -- psql -X -At -d lunaway -c "select string_agg(coalesce(scope, '-') || ' ' || n, ', ' order by n desc) from (select scope, count(*) n from pois where deleted_at is null group by 1) s" 2>&1 | head -n 1)"
echo "import ages: $(cat /var/lib/lunaway-status/imports.json 2>/dev/null || echo none)"
echo "extract cache: $(du -sh /srv/data/ingest/raw/osm-extract 2>/dev/null | cut -f1), $(find /srv/data/ingest/raw/osm-extract -maxdepth 1 -name '*.osm.pbf' 2>/dev/null | wc -l) files; a run in progress: $(ls /srv/data/ingest/raw/osm-extract/runs/ 2>/dev/null | grep -c '\.json$')"
echo "database: $(runuser -u postgres -- psql -X -At -d lunaway -c "select pg_size_pretty(pg_database_size('lunaway')) || ', pois ' || pg_size_pretty(pg_total_relation_size('pois')) || ', source_records ' || pg_size_pretty(pg_total_relation_size('source_records')) || ', places ' || pg_size_pretty(pg_total_relation_size('places'))" 2>&1 | head -n 1)"
echo "--- regional packs of places"
echo "lunaway-packs: timer $(systemctl is-enabled lunaway-packs.timer 2>&1 | head -n 1), next $(systemctl list-timers --no-pager --no-legend lunaway-packs.timer | awk '{ print $1, $2, $3 }'), last run $(systemctl show -p Result --value lunaway-packs), $(journalctl -u lunaway-packs --no-pager -n 1 -o cat 2>/dev/null | cut -c1-100)"
stat -c '%a %U:%G %n' /srv/data/packs /srv/data/packs/places /srv/data/packs/.work 2>&1
echo "files: $(find /srv/data/packs/places -maxdepth 1 -type f -name '*.sqlite.gz' 2>/dev/null | wc -l), $(du -sh /srv/data/packs 2>/dev/null | cut -f1); work files: $(find /srv/data/packs/.work -type f 2>/dev/null | wc -l)"
echo "recorded: $(runuser -u postgres -- psql -X -At -d lunaway -c "select count(*) || ' regions, ' || coalesce(sum(places), 0) || ' places, ' || coalesce(pg_size_pretty(sum(bytes)), '0') || ' gzip, newest ' || coalesce(max(generated_at)::text, 'none') from region_packs" 2>&1 | head -n 1)"
echo "status: $(sed -nE 's/.*"packs" *: *(\{[^}]*\}).*/\1/p' /var/lib/lunaway-status/worker.json 2>/dev/null)"
echo "--- speed cameras"
for t in lunaway-cameras lunaway-enforcement lunaway-cameras-osm lunaway-enforcement-full; do
  echo "$t: last run $(systemctl show -p Result --value "$t"), $(journalctl -u "$t" --no-pager -n 1 -o cat 2>/dev/null | cut -c1-100)"
done
echo "daily timer: $(systemctl is-enabled lunaway-enforcement.timer 2>&1 | head -n 1), next $(systemctl list-timers --no-pager --no-legend lunaway-enforcement.timer | awk '{ print $1, $2, $3 }')"
stat -c '%a %U:%G %n' /etc/lunaway/zone.env /srv/data/backups/offsite/zone-secret.env.age 2>&1
stat -c '%a %U:%G %n' /etc/lunaway/datatourisme.env /srv/data/backups/offsite/datatourisme-key.env.age /srv/data/media/external 2>&1
echo "zone secret: $(grep -cE '^LUNAWAY_ZONE_SECRET=[0-9a-f]{64}$' /etc/lunaway/zone.env 2>/dev/null) line of 64 hex digits (the value is not printed); loaded by: $(grep -l '^EnvironmentFile=/etc/lunaway/zone.env' /etc/systemd/system/lunaway-*.service 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ' ')"
stat -c '%a %U:%G %n' /etc/lunaway/takedown.env /srv/data/backups/offsite/takedown-secret.env.age /srv/data/place-takedowns 2>&1
echo "takedown secret: $(grep -cE '^LUNAWAY_TAKEDOWN_SECRET=[0-9a-f]{64}$' /etc/lunaway/takedown.env 2>/dev/null) line of 64 hex digits (the value is not printed); loaded by: $(grep -l '^EnvironmentFile=/etc/lunaway/takedown.env' /etc/systemd/system/lunaway-*.service 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ' ')"
echo "takedown journal: $(find /srv/data/place-takedowns -maxdepth 1 -type f -name 'takedowns-*.jsonl' 2>/dev/null | wc -l) days, encrypted copy last-success $(cat /srv/data/backups/offsite/place-takedowns/last-success 2>/dev/null || echo none)"
echo "lists: $(runuser -u postgres -- psql -X -At -d lunaway -c "select string_agg(source_id || ' ' || devices || ' read ' || to_char(fetched_at at time zone 'UTC', 'MM-DD HH24:MI'), ', ' order by source_id) from enforcement_sources" 2>&1 | head -n 1)"
echo "items: $(runuser -u postgres -- psql -X -At -d lunaway -c "select string_agg(country || ' ' || kind || ' ' || n, ', ' order by country, kind) from (select country, kind, count(*) n from enforcement_items where deleted_at is null group by 1, 2) s" 2>&1 | head -n 1)"
echo "last build: $(stat -c '%y' /var/lib/lunaway-enforcement/built 2>/dev/null || echo never)"
echo "--- routing"
echo "valhalla: $(systemctl is-active valhalla), candidate: $(systemctl is-active valhalla-candidate), podman $(podman --version 2>/dev/null | awk '{ print $3 }')"
echo "image: $(podman image inspect --format '{{.Digest}}' "$(sed -n 's/^Image=//p' /etc/containers/systemd/valhalla.container)" 2>&1 | head -n 1)"
echo "refresh timer: $(systemctl is-enabled lunaway-routing-refresh.timer 2>&1 | head -n 1), next $(systemctl list-timers --no-pager --no-legend lunaway-routing-refresh.timer | awk '{ print $1, $2, $3 }')"
echo "last refresh: $(systemctl show -p Result --value lunaway-routing-refresh), $(journalctl -u lunaway-routing-refresh --no-pager -n 1 -o cat 2>/dev/null)"
echo "current: $(readlink /srv/routing/current 2>/dev/null || echo none), previous: $(cat /srv/routing/previous 2>/dev/null || echo none)"
stat -c '%a %U:%G %n' /srv/routing /etc/lunaway/routing-signers /usr/local/sbin/lunaway-routing-refresh
grep -E '^(containers|lunaway)' /etc/subuid /etc/subgid
echo "graph files: $(du -sh /srv/routing 2>/dev/null | cut -f1), root disk $(df --output=avail -h / | tail -n 1 | tr -d ' ') free"
echo "engine status: $(curl -sS -m 5 http://127.0.0.1:8002/status 2>&1 | head -c 300)"
echo "engine memory: $(systemctl show -p MemoryCurrent --value valhalla) bytes (unit), limit $(podman inspect --format '{{.HostConfig.Memory}}' systemd-valhalla 2>/dev/null) bytes (container)"
echo "--- what the ops server may read (lunaway-pull)"
id lunaway-pull
stat -c '%a %U:%G %n' /var/lib/lunaway-pull/.ssh/authorized_keys
masked_keys /var/lib/lunaway-pull/.ssh/authorized_keys
runuser -u lunaway-pull -- /usr/local/sbin/lunaway-health
