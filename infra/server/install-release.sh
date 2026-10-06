#!/usr/bin/env bash
# Installs an uploaded release (lunaway-api, and the lunaway CLI when the
# revision has one) and switches /opt/lunaway/current to it. Run as root by
# infra/deploy-api.sh. In order:
#
#   1. the binaries go to /opt/lunaway/releases/<name>/ and current points there
#   2. with a CLI, lunaway-migrate.service applies the pending migrations as
#      lunaway_owner; if they fail, current goes back and the running API is
#      never touched
#   3. the API restarts and must answer /health on 127.0.0.1:8484 within 20
#      seconds, or current goes back to the previous release and the API
#      restarts on it. Migrations already applied stay: they are additive
#      (.claude/rules/sqlx.md), so the previous API runs on the new schema.
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
  log "migrations of $name"
  systemctl reset-failed lunaway-migrate 2>/dev/null || true
  if ! systemctl start lunaway-migrate.service; then
    journalctl -u lunaway-migrate -n 30 --no-pager >&2
    [ -n "$previous" ] && point_at "$previous"
    die "the migrations of $name failed; current is back on ${previous:-nothing}, the API was not restarted"
  fi
  journalctl -u lunaway-migrate -n 3 --no-pager -o cat
fi

restart_api
if answers; then
  log "release $name answers on 127.0.0.1:8484"
  exit 0
fi
echo "error: release $name does not answer; rolling back to ${previous:-nothing}" >&2
journalctl -u lunaway-api -n 20 --no-pager >&2
if [ -n "$previous" ]; then
  point_at "$previous"
  restart_api
  answers && log "back on $previous"
fi
exit 1
