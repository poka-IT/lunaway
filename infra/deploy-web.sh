#!/usr/bin/env bash
# Deploys the landing site (lunaway.net/) or the Flutter web app
# (lunaway.net/app/) as a new release on the server. A previous release comes
# back by deploying it again, or by pointing the symlink at it (docs/deploy.md).
#
#   infra/deploy-web.sh site DIR       a directory of HTML and CSS, index.html at its root
#   infra/deploy-web.sh app DIR        a Flutter web build built with --base-href /app/
#   infra/deploy-web.sh app --build    builds app/ first (fvm flutter build web), then deploys it
#
# LUNAWAY_FLUTTER_WEB_ARGS adds flags to the build (--wasm, for instance).
set -euo pipefail
. "$(dirname "$0")/lib.sh"
require_host
kind="${1:-}"
dir="${2:-}"
case "$kind" in
  site|app) ;;
  *) die "usage: $0 site DIR | app DIR | app --build" ;;
esac

if [ "$kind" = app ] && [ "$dir" = --build ]; then
  log "building the web app"
  # The CSP refuses scripts from other hosts, so CanvasKit must be bundled.
  # shellcheck disable=SC2086 # extra flags, one per word
  ( cd "$LUNAWAY_REPO_DIR/app" && fvm flutter build web --release --base-href /app/ --no-web-resources-cdn ${LUNAWAY_FLUTTER_WEB_ARGS:-} )
  dir="$LUNAWAY_REPO_DIR/app/build/web"
fi
[ -n "$dir" ] && [ -f "$dir/index.html" ] || die "no index.html in '${dir}'"
if [ "$kind" = app ] && ! grep -q '<base href="/app/">' "$dir/index.html"; then
  die "$dir/index.html has no <base href=\"/app/\">; build with --base-href /app/"
fi

commit="$(git -C "$LUNAWAY_REPO_DIR" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
release="$(date -u +%Y%m%dT%H%M%SZ)-$commit"
upload="/home/$LUNAWAY_ADMIN_USER/web-upload/$release"

log "uploading $dir as $kind release $release"
lunaway_ssh "mkdir -p ~/infra/server $upload"
lunaway_scp "$LUNAWAY_INFRA_DIR/server/common.sh" "$LUNAWAY_INFRA_DIR/server/install-web.sh" "lunaway:infra/server/"
COPYFILE_DISABLE=1 tar -C "$dir" --no-xattrs --no-mac-metadata -cf - . | lunaway_ssh "tar -xf - -C $upload"
lunaway_ssh "sudo bash ~/infra/server/install-web.sh $kind $release $upload"

if lunaway_ssh 'test -L /etc/caddy/sites-enabled/lunaway.net.caddy'; then
  path=/
  [ "$kind" = app ] && path=/app/
  log "https://lunaway.net$path: $(curl -sS -o /dev/null -w '%{http_code}' -m 10 "https://lunaway.net$path")"
else
  log "lunaway.net is not enabled yet (infra/enable-domain.sh); the release is in place"
fi
