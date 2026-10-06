#!/usr/bin/env bash
# The data pipeline of the backend, run as root by setup.sh: the `lunaway`
# CLI of the current release, run by systemd as the database role
# lunaway_ingest (/etc/lunaway/ingest.env), sandboxed like the API but with
# outbound HTTPS for the imports and a cache on the data volume.
#
#   lunaway-ingest-osm              daily 03:00 UTC, the OpenStreetMap France extract
#   lunaway-ingest-atout-france     weekly, Sunday 04:00 UTC
#   lunaway-ingest-pois             daily 03:45 UTC, the points of interest of
#                                   the same extract (3 GB memory cap)
#   lunaway-ingest-fuel             every 15 minutes, the fuel price feed
#   lunaway-ingest-laposte          daily 04:10 UTC, La Poste's calendar
#   lunaway-ingest-finess           monthly, the 2nd at 04:20 UTC
#   lunaway-road-events             every 3 minutes, the road event feeds
#                                   (closures, works), matched on the
#                                   routing engine at 127.0.0.1:8002
#   lunaway-road-events-dialog      weekly, Monday 05:20 UTC, DiaLog's
#                                   permanent orders into route_restrictions
#   lunaway-conflate                after each successful import of places
#   lunaway-conflate-worker         always: the community's submissions and
#                                   summaries, woken by the API's NOTIFY, and
#                                   at least every 5 minutes (which also slides
#                                   the opening hours to the new day: the
#                                   nightly conflation timer is gone)
#   lunaway-migrate                 started by install-release.sh, as lunaway_owner
#
#   lunaway-ingest     static user of the imports and the conflation; owns
#                      /srv/data/ingest (raw payload cache, the extract)
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

log "units"
changed=0
units="lunaway-migrate.service lunaway-conflate.service lunaway-conflate-worker.service
  lunaway-ingest-osm.service lunaway-ingest-osm.timer
  lunaway-ingest-atout-france.service lunaway-ingest-atout-france.timer
  lunaway-ingest-pois.service lunaway-ingest-pois.timer
  lunaway-ingest-fuel.service lunaway-ingest-fuel.timer
  lunaway-ingest-laposte.service lunaway-ingest-laposte.timer
  lunaway-ingest-finess.service lunaway-ingest-finess.timer
  lunaway-road-events.service lunaway-road-events.timer
  lunaway-road-events-dialog.service lunaway-road-events-dialog.timer"
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

timers="lunaway-ingest-osm.timer lunaway-ingest-atout-france.timer lunaway-ingest-pois.timer
  lunaway-ingest-fuel.timer lunaway-ingest-laposte.timer lunaway-ingest-finess.timer
  lunaway-road-events.timer lunaway-road-events-dialog.timer"
if [ -x /opt/lunaway/current/lunaway ]; then
  # shellcheck disable=SC2086 # one unit per word
  systemctl enable --quiet --now $timers
  # shellcheck disable=SC2086 # one unit per word
  log "timers on: $(systemctl list-timers --no-pager --no-legend $timers | awk '{ print $(NF-1) " " $1 " " $2 }' | tr '\n' ';')"
else
  # shellcheck disable=SC2086 # one unit per word
  systemctl disable --quiet --now $timers 2>/dev/null || true
  log "no lunaway CLI in the release yet: the timers stay off (infra/deploy-api.sh, then this step again)"
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
log "disk: $(df -h --output=avail /srv/data | tail -n 1 | tr -d ' ') free on /srv/data, $(du -sh /srv/data/ingest | cut -f1) in /srv/data/ingest"
