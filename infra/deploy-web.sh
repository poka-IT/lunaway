#!/usr/bin/env bash
# Deploys the landing site (lunaway.net/) or the Flutter web app
# (lunaway.net/app/) as a new release on the server. A previous release comes
# back by deploying it again, or by pointing the symlink at it (docs/deploy.md).
#
#   infra/deploy-web.sh site DIR       the generated website (infra/web/site, built by tool/site/build.py)
#   infra/deploy-web.sh app DIR        a Flutter web build built with --base-href /app/
#   infra/deploy-web.sh app --build    builds the guidance WebAssembly and app/ first, then deploys it
#
# LUNAWAY_FLUTTER_WEB_ARGS adds flags to the build (--wasm, for instance).
# LUNAWAY_DRY_RUN=1 builds and checks the release, then stops before the
# server is touched.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
dry_run="${LUNAWAY_DRY_RUN:-0}"
[ "$dry_run" = 1 ] || require_host
kind="${1:-}"
dir="${2:-}"
case "$kind" in
  site|app) ;;
  *) die "usage: $0 site DIR | app DIR | app --build" ;;
esac

if [ "$kind" = app ] && [ "$dir" = --build ]; then
  # The guidance engine's WebAssembly is not committed: built from the
  # crate here, it lands in app/web/ before Flutter copies that directory.
  log "building the guidance engine for the browser"
  sh "$LUNAWAY_REPO_DIR/app/packages/lunaway_nav/tool/build_web.sh"
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
# Without it the app runs but guides nowhere, which nothing else would show.
if [ "$kind" = app ] && [ ! -s "$dir/lunaway_nav/lunaway_nav_bg.wasm" ]; then
  die "$dir has no lunaway_nav/lunaway_nav_bg.wasm; run app/packages/lunaway_nav/tool/build_web.sh before the build"
fi
if [ "$kind" = app ]; then
  # The service worker that serves a second visit from the browser's cache
  # names every file of this build, so it is written after the build.
  python3 "$LUNAWAY_REPO_DIR/app/tool/web/service_worker.py" "$dir" || die "the service worker was not written"
fi

if [ "$dry_run" = 1 ]; then
  log "dry run: $dir is ready as a $kind release, nothing uploaded"
  exit 0
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
