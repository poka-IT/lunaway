#!/usr/bin/env bash
# The data pipeline of the backend, run as root by setup.sh: the `lunaway`
# CLI of the current release, run by systemd as the database role
# lunaway_ingest (/etc/lunaway/ingest.env), sandboxed like the API but with
# outbound HTTPS for the imports and a cache on the data volume.
#
#   lunaway-ingest-osm              daily 03:00 UTC, the OpenStreetMap France extract
#   lunaway-ingest-osm-europe@Day   weekly, Monday to Saturday 05:00 UTC, one
#                                   group of the other European extracts each
#                                   day (/usr/local/share/lunaway/osm-extracts.env)
#   lunaway-ingest-atout-france     weekly, Sunday 04:00 UTC
#   lunaway-ingest-pois             daily 03:45 UTC, the points of interest of
#                                   the same extract (3 GB memory cap)
#   lunaway-ingest-pois-europe@Day  weekly, 05:45 UTC, the points of interest of
#                                   that day's group, after its places
#   lunaway-ingest-fuel             every 15 minutes, the fuel price feed
#   lunaway-ingest-laposte          daily 04:10 UTC, La Poste's calendar
#   lunaway-ingest-finess           monthly, the 2nd at 04:20 UTC
#   lunaway-ingest-datatourisme     weekly, Sunday 04:30 UTC, the tourist
#                                   offices' places, with the key of
#                                   /etc/lunaway/datatourisme.env; off
#                                   while no key is installed
#   lunaway-ingest-extcom           the external community feed, when its
#                                   producer drops one into
#                                   /srv/data/extcom-inbox (a path unit,
#                                   and hourly): checked, imported, then
#                                   the conflation and the photo files;
#                                   off while /etc/lunaway/extcom.env is
#                                   not installed
#   lunaway-extcom-purge-media      after each import of that feed, and
#                                   daily 05:10 UTC: as the API's user,
#                                   the files of its retired photos
#   lunaway-extcom-erasures         after each erasure of one of its
#                                   authors, and hourly: the SHA-256 of
#                                   every erased author id into
#                                   /srv/data/extcom-erasures, which the
#                                   feed's producer reads through
#                                   lunaway-pull (ops-access.sh)
#   lunaway-content-refresh         weekly, Sunday 07:00 UTC, the open
#                                   content of the places (photos,
#                                   descriptions, reviews), then the files
#                                   no photo points at
#   lunaway-addresses               hourly at :20, the addresses of the
#                                   places no source gives a street, by a
#                                   reverse geocoding on Lunaway's Photon
#                                   through Caddy on the loopback
#   lunaway-road-events             every 3 minutes, the road event feeds
#                                   (closures, works), matched on the
#                                   routing engine at 127.0.0.1:8002
#   lunaway-road-events-dialog      weekly, Monday 05:20 UTC, DiaLog's
#                                   permanent orders into route_restrictions
#   lunaway-road-events-ndw         every 3 hours at :40, the Dutch planning
#                                   feed (204 MB of XML, 1 GB memory cap),
#                                   stored but not served while the routing
#                                   graph covers France only
#   lunaway-conflate                after each successful import of places
#   lunaway-packs                   after each conflation that follows an import
#                                   of places, and daily 06:30 UTC: the regional
#                                   first-sync packs into /srv/data/packs
#   lunaway-enforcement             daily 05:30 UTC: the official speed camera
#                                   lists (lunaway-cameras), then the zones and
#                                   points, on the engine at 127.0.0.1:8002
#   lunaway-enforcement-full        after each new routing graph (started by
#                                   lunaway-routing-refresh): OpenStreetMap's
#                                   cameras (lunaway-cameras-osm), then every
#                                   zone and point built again
#   lunaway-conflate-worker         always: the community's submissions and
#                                   summaries, woken by the API's NOTIFY, and
#                                   at least every 5 minutes (which also slides
#                                   the opening hours to the new day: the
#                                   nightly conflation timer is gone)
#   lunaway-migrate                 started by install-release.sh, as lunaway_owner
#
#   lunaway-ingest     static user of the imports and the conflation; owns
#                      /srv/data/ingest (raw payload cache, the extracts) and
#                      /srv/data/packs (setgid caddy, which serves the packs)
#   /etc/lunaway/zone.env   LUNAWAY_ZONE_SECRET, generated here once and never
#                      again: a new secret moves every danger zone the phones
#                      hold. An age-encrypted copy goes to the off-site
#                      directory, pulled to the ops server and the Mac
#   /etc/lunaway/datatourisme.env   LUNAWAY_DATATOURISME_KEY, the free key of
#                      the DATAtourisme API, given by the maintainer (never
#                      generated): an age-encrypted copy goes off site like
#                      the zone secret's, and a missing key is restored
#                      from that copy, never asked for again silently
#   /etc/lunaway/extcom.env   LUNAWAY_EXTCOM_AGREEMENT_REF and
#                      LUNAWAY_EXTCOM_PHOTO_HOSTS, the settings of the
#                      external community source's agreement, given by the
#                      maintainer and kept out of the repository (a photo
#                      host names the partner); an age-encrypted copy goes
#                      off site, written again whenever the file changes
#   /srv/data/media/external   the photos of the open sources, written by
#                      the content refresh (lunaway-ingest, setgid caddy)
#   /etc/lunaway/takedown.env   LUNAWAY_TAKEDOWN_SECRET, the same way: it keys
#                      the cells of every takedown's exclusion zone, so a new
#                      one would free every zone taken down before it. Loaded
#                      by the conflation units and lunaway-admin's import
#                      role only, never by the API
#   /srv/data/place-takedowns   the takedown journal (lunaway-ingest, group
#                      lunaway-takedowns, 2750), outside the dumps: after a
#                      restore, `takedowns replay` takes down again what the
#                      dump brought back; copied off the server hourly by
#                      lunaway-takedowns-offsite (infra/server/backups.sh)
#
# The timers stay off while the release carries no `lunaway` binary: a run
# before the first migration would only fail. The worker starts only with a
# CLI that has `conflate --watch`.
. "$(dirname "$0")/common.sh"
need_root
mountpoint -q /srv/data || die "/srv/data is not mounted; run data-volume.sh first"
[ -f /etc/lunaway/ingest.env ] && [ -f /etc/lunaway/owner.env ] || die "no database credentials; run the postgres step first"

log "account and cache"
if ! getent passwd lunaway-ingest >/dev/null; then
  useradd --system --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin \
    --comment "Lunaway imports and conflation" --user-group lunaway-ingest
fi
install -d -m 0750 -o lunaway-ingest -g lunaway-ingest /srv/data/ingest
# The regional packs: written by the imports' user, read by Caddy alone
# (/packs/places/ of the Caddyfile). The directory is setgid to caddy, so
# what the builder writes with its umask 0027 comes out readable by caddy
# and nobody else. Nothing to back up: each build writes it again.
getent group caddy >/dev/null || die "no caddy group; run the caddy step first"
install -d -m 2750 -o lunaway-ingest -g caddy /srv/data/packs

log "speed camera zones' secret"
# The key of each zone's cut and id (docs/speed-cameras.md): generated once
# (32 random bytes, hex), read by the builds only (lunaway-enforcement*,
# lunaway-admin enforcement), never printed. A copy on the data volume
# means a secret existed: a new one would move every zone the phones keep,
# so it is restored from that copy instead (docs/deploy.md, "Backups and
# restore").
zone_env=/etc/lunaway/zone.env
zone_copy=/srv/data/backups/offsite/zone-secret.env.age
[ -f /etc/lunaway/backup-recipient ] || die "no /etc/lunaway/backup-recipient; run the backups step first"
if ! grep -qE '^LUNAWAY_ZONE_SECRET=[^[:space:]]{32,}$' "$zone_env" 2>/dev/null; then
  [ -e "$zone_copy" ] && die "$zone_env holds no LUNAWAY_ZONE_SECRET but $zone_copy exists: restore the secret from it (docs/deploy.md, \"Backups and restore\"), never generate another"
  # On its own line, so that a failing openssl stops the step (set -e)
  # instead of writing, and backing up, an empty secret.
  secret="$(openssl rand -hex 32)"
  [[ "$secret" =~ ^[0-9a-f]{64}$ ]] || die "openssl gave no secret of 64 hex digits"
  ( umask 077
    printf 'LUNAWAY_ZONE_SECRET=%s\n' "$secret" > "$zone_env.new"
    mv "$zone_env.new" "$zone_env" )
  unset secret
  echo "    generated LUNAWAY_ZONE_SECRET in $zone_env"
fi
chown root:root "$zone_env"
chmod 0600 "$zone_env"
if [ ! -s "$zone_copy" ]; then
  age --encrypt --recipients-file /etc/lunaway/backup-recipient --output "$zone_copy.partial" "$zone_env"
  chown root:lunaway-pull "$zone_copy.partial"
  chmod 0640 "$zone_copy.partial"
  mv "$zone_copy.partial" "$zone_copy"
  echo "    encrypted copy: $zone_copy (the ops server pulls it at 01:15 UTC, the Mac at 04:30)"
fi

log "DATAtourisme key"
# The free key of the DATAtourisme API (docs/data-sources.md), installed by
# the maintainer, read by the DATAtourisme import alone. Its encrypted copy
# is made once and never overwritten; a key missing beside a copy means a
# restore is due (docs/deploy.md, "Backups and restore").
datatourisme_env=/etc/lunaway/datatourisme.env
datatourisme_copy=/srv/data/backups/offsite/datatourisme-key.env.age
if grep -qE '^LUNAWAY_DATATOURISME_KEY=[^[:space:]]{8,}$' "$datatourisme_env" 2>/dev/null; then
  chown root:root "$datatourisme_env"
  chmod 0600 "$datatourisme_env"
  if [ ! -s "$datatourisme_copy" ]; then
    age --encrypt --recipients-file /etc/lunaway/backup-recipient --output "$datatourisme_copy.partial" "$datatourisme_env"
    chown root:lunaway-pull "$datatourisme_copy.partial"
    chmod 0640 "$datatourisme_copy.partial"
    mv "$datatourisme_copy.partial" "$datatourisme_copy"
    echo "    encrypted copy: $datatourisme_copy (the ops server pulls it at 01:15 UTC, the Mac at 04:30)"
  fi
  datatourisme_key=1
else
  [ -e "$datatourisme_copy" ] && die "$datatourisme_env holds no LUNAWAY_DATATOURISME_KEY but $datatourisme_copy exists: restore the key from it (docs/deploy.md, \"Backups and restore\")"
  echo "    no key: the DATAtourisme import stays off until the maintainer installs one (docs/deploy.md)"
  datatourisme_key=0
fi

log "external community source"
# The reference of the signed agreement and the hosts its photos come from
# (docs/feeds.md, "Server configuration"), installed by the maintainer on
# the server only, read by the feed's import alone. A copy is encrypted
# again whenever the file is newer than it, so a new photo host reaches the
# backups; a file missing beside a copy means a restore is due.
extcom_env=/etc/lunaway/extcom.env
extcom_copy=/srv/data/backups/offsite/extcom-env.age
if grep -qE '^LUNAWAY_EXTCOM_AGREEMENT_REF=[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$' "$extcom_env" 2>/dev/null \
  && grep -qE '^LUNAWAY_EXTCOM_PHOTO_HOSTS=[a-z0-9.-]+(,[a-z0-9.-]+)*$' "$extcom_env"; then
  chown root:root "$extcom_env"
  chmod 0600 "$extcom_env"
  if [ ! -s "$extcom_copy" ] || [ "$extcom_env" -nt "$extcom_copy" ]; then
    age --encrypt --recipients-file /etc/lunaway/backup-recipient --output "$extcom_copy.partial" "$extcom_env"
    chown root:lunaway-pull "$extcom_copy.partial"
    chmod 0640 "$extcom_copy.partial"
    mv "$extcom_copy.partial" "$extcom_copy"
    echo "    encrypted copy: $extcom_copy (the ops server pulls it at 01:15 UTC, the Mac at 04:30)"
  fi
  extcom=1
else
  [ -e "$extcom_copy" ] && die "$extcom_env does not hold LUNAWAY_EXTCOM_AGREEMENT_REF and LUNAWAY_EXTCOM_PHOTO_HOSTS but $extcom_copy exists: restore it from the copy (docs/deploy.md, \"Backups and restore\")"
  echo "    no settings: the external community feed is not imported until the maintainer installs them (docs/deploy.md)"
  extcom=0
fi
# The inbox, its write-only account and its tmpfiles rule come from the
# producer's private deployment (docs/deploy.md, "The external community
# feed"): checked here, never made, so a change there shows up at the next
# run of this step.
if [ -d /srv/data/extcom-inbox ]; then
  inbox_mode="$(stat -c '%U:%G %a' /srv/data/extcom-inbox)"
  echo "    inbox: $(find /srv/data/extcom-inbox -maxdepth 1 -type f -name 'extcom-*.jsonl.gz' | wc -l) feed(s) in /srv/data/extcom-inbox ($inbox_mode)"
  [ "$inbox_mode" = "extcom-drop:lunaway-ingest 2750" ] \
    || echo "    WARNING: /srv/data/extcom-inbox is $inbox_mode, not extcom-drop:lunaway-ingest 2750"
  grep -qsE '^d /srv/data/extcom-inbox 2750 extcom-drop lunaway-ingest [0-9]+d$' /etc/tmpfiles.d/extcom-inbox.conf \
    || echo "    WARNING: no tmpfiles rule removes the inbox's old feeds (/etc/tmpfiles.d/extcom-inbox.conf)"
else
  echo "    no /srv/data/extcom-inbox yet: the producer's deployment makes it, with its write-only account"
fi
# The list of erased authors goes the other way: written here by the
# imports' user, read by the producer through lunaway-pull, whose forced
# command prints it (ops-access.sh). Setgid lunaway-pull, so the CLI's 0640
# file takes that group and nobody else reads it.
getent group lunaway-pull >/dev/null || die "no group lunaway-pull; run the backups step first"
install -d -m 2750 -o lunaway-ingest -g lunaway-pull /srv/data/extcom-erasures

log "open content's photos"
# Written by the content refresh with its umask 0027; setgid caddy so that
# Caddy, which serves /media/, reads them.
[ -d /srv/data/media ] || die "no /srv/data/media; run the api step first"
install -d -m 2750 -o lunaway-ingest -g caddy /srv/data/media/external

log "takedown secret and journal"
# The key of the cells around each place taken down (plan/research/34,
# 9.1): the conflation holds a new or moving place in them. Generated once,
# never printed; a copy on the data volume means a secret existed, and the
# cells already stored only match that one, so it is restored, never
# generated again (docs/deploy.md, "Backups and restore").
takedown_env=/etc/lunaway/takedown.env
takedown_copy=/srv/data/backups/offsite/takedown-secret.env.age
if ! grep -qE '^LUNAWAY_TAKEDOWN_SECRET=[0-9a-f]{64}$' "$takedown_env" 2>/dev/null; then
  [ -e "$takedown_copy" ] && die "$takedown_env holds no LUNAWAY_TAKEDOWN_SECRET but $takedown_copy exists: restore the secret from it (docs/deploy.md, \"Backups and restore\"), never generate another"
  secret="$(openssl rand -hex 32)"
  [[ "$secret" =~ ^[0-9a-f]{64}$ ]] || die "openssl gave no secret of 64 hex digits"
  ( umask 077
    printf 'LUNAWAY_TAKEDOWN_SECRET=%s\n' "$secret" > "$takedown_env.new"
    mv "$takedown_env.new" "$takedown_env" )
  unset secret
  echo "    generated LUNAWAY_TAKEDOWN_SECRET in $takedown_env"
fi
chown root:root "$takedown_env"
chmod 0600 "$takedown_env"
if [ ! -s "$takedown_copy" ]; then
  age --encrypt --recipients-file /etc/lunaway/backup-recipient --output "$takedown_copy.partial" "$takedown_env"
  chown root:lunaway-pull "$takedown_copy.partial"
  chmod 0640 "$takedown_copy.partial"
  mv "$takedown_copy.partial" "$takedown_copy"
  echo "    encrypted copy: $takedown_copy (the ops server pulls it at 01:15 UTC, the Mac at 04:30)"
fi
# The journal: written by the import role (conflate --take-down, takedowns
# import), read by its encrypted copy's unit through the group (setgid: the
# CLI's 0640 files take it).
getent group lunaway-takedowns >/dev/null || groupadd --system lunaway-takedowns
install -d -m 2750 -o lunaway-ingest -g lunaway-takedowns /srv/data/place-takedowns

log "units"
changed=0
units="lunaway-migrate.service lunaway-conflate.service lunaway-conflate-worker.service
  lunaway-ingest-osm.service lunaway-ingest-osm.timer
  lunaway-ingest-atout-france.service lunaway-ingest-atout-france.timer
  lunaway-ingest-pois.service lunaway-ingest-pois.timer
  lunaway-ingest-fuel.service lunaway-ingest-fuel.timer
  lunaway-ingest-laposte.service lunaway-ingest-laposte.timer
  lunaway-ingest-finess.service lunaway-ingest-finess.timer
  lunaway-ingest-datatourisme.service lunaway-ingest-datatourisme.timer
  lunaway-ingest-extcom.service lunaway-ingest-extcom.timer lunaway-ingest-extcom.path
  lunaway-extcom-purge-media.service lunaway-extcom-purge-media.timer
  lunaway-extcom-erasures.service lunaway-extcom-erasures.timer
  lunaway-content-refresh.service lunaway-content-refresh.timer
  lunaway-addresses.service lunaway-addresses.timer
  lunaway-road-events.service lunaway-road-events.timer
  lunaway-road-events-dialog.service lunaway-road-events-dialog.timer
  lunaway-road-events-ndw.service lunaway-road-events-ndw.timer
  lunaway-ingest-osm-europe@.service lunaway-ingest-osm-europe@.timer
  lunaway-ingest-pois-europe@.service lunaway-ingest-pois-europe@.timer
  lunaway-packs.service lunaway-packs.timer
  lunaway-cameras.service lunaway-enforcement.service lunaway-enforcement.timer
  lunaway-cameras-osm.service lunaway-enforcement-full.service"
install_file files/usr/local/share/lunaway/osm-extracts.env /usr/local/share/lunaway/osm-extracts.env 0644 || true
install_file files/usr/local/sbin/lunaway-extcom-inbox /usr/local/sbin/lunaway-extcom-inbox 0755 || true
install_file files/usr/local/sbin/lunaway-unit-result /usr/local/sbin/lunaway-unit-result 0755 || true
# Where it keeps how the extcom units' last runs ended: root's own, read by
# the probe's user (lunaway-unit-result refuses any other directory).
install -d -o root -g root -m 0755 /var/lib/lunaway-unit-result
worker_changed=0
for unit in $units; do
  if install_file "systemd/$unit" "/etc/systemd/system/$unit" 0644; then
    changed=1
    if [ "$unit" = lunaway-conflate-worker.service ]; then worker_changed=1; fi
  fi
done
# The nightly conflation timer of earlier versions: the worker does its job.
if [ -f /etc/systemd/system/lunaway-conflate.timer ]; then
  systemctl disable --quiet --now lunaway-conflate.timer 2>/dev/null || true
  rm -f /etc/systemd/system/lunaway-conflate.timer
  changed=1
  echo "    removed lunaway-conflate.timer (the worker runs at least every 5 minutes)"
fi
[ "$changed" = 1 ] && systemctl daemon-reload

# One weekly timer per group of European extracts, named by the keys of
# osm-extracts.env (LUNAWAY_EXTRACTS_Mon: lunaway-ingest-osm-europe@Mon.timer).
days="$(sed -nE 's/^LUNAWAY_EXTRACTS_(Mon|Tue|Wed|Thu|Fri|Sat|Sun)=.*/\1/p' /usr/local/share/lunaway/osm-extracts.env)"
[ -n "$days" ] || die "no group in /usr/local/share/lunaway/osm-extracts.env"
weekly=""
for day in $days; do
  weekly="$weekly lunaway-ingest-osm-europe@$day.timer lunaway-ingest-pois-europe@$day.timer"
done
# A day dropped from the file stops importing.
for unit in $(ls /etc/systemd/system/timers.target.wants/ | grep -E '^lunaway-ingest-(osm|pois)-europe@[A-Z][a-z]{2}\.timer$'); do
  case " $weekly " in *" $unit "*) ;; *) systemctl disable --quiet --now "$unit" && echo "    disabled $unit" ;; esac
done
timers="lunaway-ingest-osm.timer lunaway-ingest-atout-france.timer lunaway-ingest-pois.timer
  lunaway-ingest-fuel.timer lunaway-ingest-laposte.timer lunaway-ingest-finess.timer
  lunaway-road-events.timer lunaway-road-events-dialog.timer lunaway-road-events-ndw.timer
  lunaway-packs.timer lunaway-enforcement.timer lunaway-content-refresh.timer
  lunaway-addresses.timer $weekly"
if [ "$datatourisme_key" = 1 ]; then
  timers="$timers lunaway-ingest-datatourisme.timer"
else
  systemctl disable --quiet --now lunaway-ingest-datatourisme.timer 2>/dev/null || true
fi
# The external community feed's triggers, once its settings are installed.
if [ "$extcom" = 1 ]; then
  timers="$timers lunaway-ingest-extcom.timer"
  extcom_path=lunaway-ingest-extcom.path
else
  systemctl disable --quiet --now lunaway-ingest-extcom.timer lunaway-ingest-extcom.path 2>/dev/null || true
  # A feed switched off is not a failed import.
  rm -f /var/lib/lunaway-unit-result/extcom-import.result
  extcom_path=""
fi
if [ -x /opt/lunaway/current/lunaway ]; then
  # shellcheck disable=SC2086 # one unit per word
  systemctl enable --quiet --now $timers $extcom_path
  # shellcheck disable=SC2086 # one unit per word
  log "timers on: $(systemctl list-timers --no-pager --no-legend $timers | awk '{ print $(NF-1) " " $1 " " $2 }' | tr '\n' ';')"
  [ -n "$extcom_path" ] && log "$extcom_path $(systemctl is-active "$extcom_path"), watching /srv/data/extcom-inbox"
else
  # shellcheck disable=SC2086 # one unit per word
  systemctl disable --quiet --now $timers lunaway-ingest-extcom.path 2>/dev/null || true
  log "no lunaway CLI in the release yet: the timers stay off (infra/deploy-api.sh, then this step again)"
fi
# The removal of the retired photos' files, whenever the release's CLI has
# the command, settings or not: a purge after the agreement ends needs it
# too. Asked as the API's user, never as root.
# The help in a variable: grep -q in a pipe may close it early, and the
# pipeline would then fail under pipefail.
extcom_help=""
[ -x /opt/lunaway/current/lunaway ] \
  && extcom_help="$(runuser -u lunaway-api -- /opt/lunaway/current/lunaway extcom --help 2>/dev/null || true)"
if [[ "$extcom_help" == *purge-media* ]]; then
  systemctl enable --quiet --now lunaway-extcom-purge-media.timer
  log "retired photo files of the external community source: daily, next $(systemctl show lunaway-extcom-purge-media.timer -p NextElapseUSecRealtime --value)"
else
  systemctl disable --quiet --now lunaway-extcom-purge-media.timer 2>/dev/null || true
  log "the release's CLI has no extcom purge-media: its timer stays off"
fi
# The list of erased authors, settings or not: the producer runs on its
# own, and an erasure applies after the agreement ends too. Written once
# now, so the producer finds a list as soon as this step ran.
if [[ "$extcom_help" == *erasures* ]]; then
  systemctl enable --quiet --now lunaway-extcom-erasures.timer
  systemctl start lunaway-extcom-erasures.service \
    || echo "    WARNING: lunaway-extcom-erasures.service failed: journalctl -u lunaway-extcom-erasures"
  # Counted as the reader the forced command runs as, never as root: the
  # directory is the imports' user's.
  listed="$(runuser -u lunaway-pull -- /usr/local/sbin/lunaway-extcom-erasures 2>/dev/null | wc -l || true)"
  log "erased authors' list: $listed hash(es), hourly, next $(systemctl show lunaway-extcom-erasures.timer -p NextElapseUSecRealtime --value)"
else
  systemctl disable --quiet --now lunaway-extcom-erasures.timer 2>/dev/null || true
  log "the release's CLI has no extcom erasures: its timer stays off"
fi

# The worker's queues, measured every minute for the health probe.
status_changed=0
install_file files/usr/local/sbin/lunaway-worker-status /usr/local/sbin/lunaway-worker-status 0755 && status_changed=1
for unit in lunaway-worker-status.service lunaway-worker-status.timer; do
  install_file "systemd/$unit" "/etc/systemd/system/$unit" 0644 && status_changed=1
done
[ "$status_changed" = 1 ] && systemctl daemon-reload

# The release's CLI is asked about --watch as the imports' user, never as root.
if [ -x /opt/lunaway/current/lunaway ] \
  && runuser -u lunaway-ingest -- /opt/lunaway/current/lunaway conflate --help 2>/dev/null | grep -q -- '--watch'; then
  systemctl enable --quiet lunaway-conflate-worker
  systemctl reset-failed lunaway-conflate-worker 2>/dev/null || true
  if [ "$worker_changed" = 1 ] || ! systemctl is-active --quiet lunaway-conflate-worker; then
    systemctl restart lunaway-conflate-worker
  fi
  systemctl enable --quiet --now lunaway-worker-status.timer
  log "conflation worker $(systemctl is-active lunaway-conflate-worker), queue measure every minute"
else
  systemctl disable --quiet --now lunaway-worker-status.timer 2>/dev/null || true
  systemctl disable --quiet --now lunaway-conflate-worker 2>/dev/null || true
  log "the release's CLI has no conflate --watch: the worker stays off"
fi
log "disk: $(df -h --output=avail /srv/data | tail -n 1 | tr -d ' ') free on /srv/data, $(du -sh /srv/data/ingest | cut -f1) in /srv/data/ingest, $(du -sh /srv/data/packs | cut -f1) in /srv/data/packs"
