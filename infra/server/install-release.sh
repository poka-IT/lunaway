#!/usr/bin/env bash
# Installs an uploaded release (lunaway-api, and the lunaway CLI when the
# revision has one) and switches /opt/lunaway/current to it. Run as root by
# infra/deploy-api.sh. In order:
#
#   1. the binaries go to /opt/lunaway/releases/<name>/ and current points there
#   2. with a CLI, the long jobs of the CLI are paused between two of their
#      transactions (pause-jobs.sh), lunaway-migrate.service applies the
#      pending migrations as lunaway_owner, and the jobs go on; if the pause
#      or the migrations fail, current goes back and the running API is
#      never touched
#   3. the API restarts and must answer /health on 127.0.0.1:8484 within 20
#      seconds, or current goes back to the previous release and the API
#      restarts on it; the conflation worker, when it runs, restarts on
#      whichever release current ends on. Migrations already applied stay:
#      they are additive (.claude/rules/sqlx.md), so the previous API runs on
#      the new schema.
#
# Old releases stay in /opt/lunaway/releases (a few tens of MB each) until
# someone removes one by its name.
#
#   sudo bash ~/infra/server/install-release.sh RELEASE UPLOAD_DIR
. "$(dirname "$0")/common.sh"
need_root
name="${1:?release name}"
upload="${2:?uploaded directory}"
[[ "$name" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-z]+(-dirty)?$ ]] || die "unexpected release name $name"
[[ "$upload" =~ ^/home/[a-z]+/release-upload$ ]] || die "unexpected upload path $upload"
[ -f "$upload/lunaway-api" ] || die "no lunaway-api in $upload"
release="/opt/lunaway/releases/$name"
[ ! -e "$release" ] || die "release $name already exists"
if [ -f "$upload/lunaway" ] && [ ! -f /etc/systemd/system/lunaway-migrate.service ]; then
  die "the release carries the lunaway CLI but lunaway-migrate.service is not installed: run infra/configure.sh backend pipeline first"
fi

install -d -m 0755 "$release"
for bin in lunaway-api lunaway; do
  [ -f "$upload/$bin" ] || continue
  install -m 0755 -o root -g root "$upload/$bin" "$release/$bin"
  rm -f "$upload/$bin"
done
previous="$(readlink /opt/lunaway/current || true)"

point_at() {
  ln -sfn "$1" /opt/lunaway/current.new
  mv -T /opt/lunaway/current.new /opt/lunaway/current
}

restart_api() {
  # Earlier failures must not leave the unit stuck at its start limit.
  systemctl reset-failed lunaway-api 2>/dev/null || true
  systemctl restart lunaway-api
}

answers() {
  local _
  for _ in $(seq 1 20); do
    [ "$(curl -fsS -m 2 http://127.0.0.1:8484/health 2>/dev/null)" = ok ] && return 0
    sleep 1
  done
  return 1
}

point_at "$release"
if [ -x "$release/lunaway" ]; then
  # The long jobs wait between two of their transactions while the
  # migrations run (pause-jobs.sh), and go on where they stood after,
  # whatever happens.
  pause_jobs="$(dirname "$0")/pause-jobs.sh"
  if ! bash "$pause_jobs" pause; then
    [ -n "$previous" ] && point_at "$previous"
    die "the long jobs could not be paused; current is back on ${previous:-nothing}, nothing was migrated"
  fi
  trap 'bash "$pause_jobs" resume' EXIT
  log "migrations of $name"
  systemctl reset-failed lunaway-migrate 2>/dev/null || true
  if ! systemctl start lunaway-migrate.service; then
    journalctl -u lunaway-migrate -n 30 --no-pager >&2
    [ -n "$previous" ] && point_at "$previous"
    die "the migrations of $name failed; current is back on ${previous:-nothing}, the API was not restarted"
  fi
  journalctl -u lunaway-migrate -n 3 --no-pager -o cat
  bash "$pause_jobs" resume
  trap - EXIT
fi

# The conflation worker runs the CLI of current: restart it on the new one
# (no-op when it is not running, before infra/configure.sh backend pipeline
# has started it).
restart_worker() {
  systemctl try-restart lunaway-conflate-worker.service 2>/dev/null || true
}

restart_api
if answers; then
  restart_worker
  log "release $name answers on 127.0.0.1:8484; worker $(systemctl is-active lunaway-conflate-worker 2>/dev/null || true)"
  exit 0
fi
echo "error: release $name does not answer; rolling back to ${previous:-nothing}" >&2
journalctl -u lunaway-api -n 20 --no-pager >&2
if [ -n "$previous" ]; then
  point_at "$previous"
  restart_api
  restart_worker
  answers && log "back on $previous"
fi
exit 1
