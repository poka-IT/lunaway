#!/usr/bin/env bash
# The data pipeline of the backend, run as root by setup.sh: the `lunaway`
# CLI of the current release, run by systemd as the database role
# lunaway_ingest (/etc/lunaway/ingest.env), sandboxed like the API but with
# outbound HTTPS for the imports and a cache on the data volume.
#
#   lunaway-ingest-osm              daily 03:00 UTC, the OpenStreetMap France extract
#   lunaway-ingest-atout-france     weekly, Sunday 04:00 UTC
#   lunaway-conflate                after each successful import, and nightly
#                                   just after midnight in France
#   lunaway-migrate                 started by install-release.sh, as lunaway_owner
#
#   lunaway-ingest     static user of the imports and the conflation; owns
#                      /srv/data/ingest (raw payload cache, the extract)
#
# The timers stay off while the release carries no `lunaway` binary: a run
# before the first migration would only fail.
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
units="lunaway-migrate.service lunaway-conflate.service lunaway-conflate.timer
  lunaway-ingest-osm.service lunaway-ingest-osm.timer
  lunaway-ingest-atout-france.service lunaway-ingest-atout-france.timer"
for unit in $units; do
  install_file "systemd/$unit" "/etc/systemd/system/$unit" 0644 && changed=1
done
[ "$changed" = 1 ] && systemctl daemon-reload

timers="lunaway-ingest-osm.timer lunaway-ingest-atout-france.timer lunaway-conflate.timer"
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
log "disk: $(df -h --output=avail /srv/data | tail -n 1 | tr -d ' ') free on /srv/data, $(du -sh /srv/data/ingest | cut -f1) in /srv/data/ingest"
