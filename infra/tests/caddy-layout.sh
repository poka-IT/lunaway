#!/usr/bin/env bash
# Checks the routing of infra/caddy/ (the lunaway.net sites, api. and
# tiles.lunaway.net included) in the official Caddy image, and that the main
# Caddyfile alone (the domain not enabled) serves nothing and still
# validates. The configuration is the real one, rewritten
# for a test: plain HTTP on port 8080, no admin API, test roots under the
# scratch directory, which is the containers' only mount (read-only). The
# basemap routes go to a real `pmtiles serve` (the pinned release, in a second
# container on a private Docker network) over a one-tile archive from the
# go-pmtiles test suite; both are downloaded once into the scratch directory
# and checked against infra/tiles/version.sh.
#
# On macOS (Apple silicon) and Linux x86_64 it runs native binaries by
# default: the Caddy release the servers run (2.11.7, pinned below by the
# SHA-256 GitHub records for the asset; the release's own checksums file
# gives the same tarball's SHA-512) and the pinned pmtiles, bound to
# 127.0.0.1, on ports 18080 (sites), 18484 (stand-in API) and 18485
# (pmtiles). LUNAWAY_CADDY_DOCKER=1 runs the Docker images instead (a
# Docker that answers `docker info` may still fail to start containers, as
# colima did on 2026-10-06).
#
#   infra/tests/caddy-layout.sh
set -euo pipefail
INFRA="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$INFRA/.." && pwd)"
SCRATCH="${LUNAWAY_SCRATCH_DIR:-$REPO/data/tmp/infra}/caddy-test"
CADDY_IMAGE="${LUNAWAY_CADDY_IMAGE:-caddy:2.11}"
PORT=18080
NETWORK=lunaway-caddy-test
BUILD=20261005
. "$INFRA/tiles/version.sh"
CADDY_NATIVE_URL_MAC_ARM64=https://github.com/caddyserver/caddy/releases/download/v2.11.7/caddy_2.11.7_mac_arm64.tar.gz
CADDY_NATIVE_SHA256_MAC_ARM64=cda3030e5d5b13eb9f0b6fb541037f633bddd958c070c5f561d7a5cccb581665
CADDY_NATIVE_URL_LINUX_AMD64=https://github.com/caddyserver/caddy/releases/download/v2.11.7/caddy_2.11.7_linux_amd64.tar.gz
CADDY_NATIVE_SHA256_LINUX_AMD64=727b91701a392de6ebc5027509f548bf39979e5216340d0faed8fa5e69c84f8b

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64|Linux-x86_64) native_pin=yes ;;
  *) native_pin=no ;;
esac
if [ "${LUNAWAY_CADDY_DOCKER:-0}" = 1 ] || [ "$native_pin" = no ]; then
  docker info >/dev/null 2>&1 || { echo "docker does not answer" >&2; exit 1; }
  MODE=docker W=/w LISTEN=8080 API_UP=127.0.0.1:8484 API_LISTEN=8484 PMTILES_UP=lunaway-pmtiles-test:8485
  ACCESS_LOG=/tmp/access.log
else
  MODE=native W="$SCRATCH" LISTEN="$PORT" API_UP=127.0.0.1:18484 API_LISTEN=18484 PMTILES_UP=127.0.0.1:18485
  ACCESS_LOG="$SCRATCH/access.log"
fi
echo "mode: $MODE"
mkdir -p "$SCRATCH/site" "$SCRATCH/web/assets" "$SCRATCH/data/media/ab"
mkdir -p "$SCRATCH/data/packs/places" "$SCRATCH/data/packs/.work"
mkdir -p "$SCRATCH/bin" "$SCRATCH/tiles/builds" "$SCRATCH/tiles/serve" "$SCRATCH/tiles/tilejson" \
  "$SCRATCH/tiles/assets/fonts/Noto Sans Regular" "$SCRATCH/tiles/assets/sprites/protomaps-v4" \
  "$SCRATCH/tiles/assets/styles" "$SCRATCH/tiles/packs" "$SCRATCH/fdroid/repo/diff"

# fetch_pinned URL SHA256 FILE: downloads once, and checks the hash each run.
fetch_pinned() {
  [ -f "$3" ] || curl -fsSL -m 300 -o "$3" "$1"
  [ "$(shasum -a 256 "$3" | awk '{ print $1 }')" = "$2" ] || { echo "$3 does not match its pin" >&2; exit 1; }
}
if [ "$MODE" = docker ]; then
  case "$(docker info --format '{{.Architecture}}')" in
    x86_64) fetch_pinned "$PMTILES_URL_AMD64" "$PMTILES_SHA256_AMD64" "$SCRATCH/bin/pmtiles.tar.gz" ;;
    aarch64) fetch_pinned "$PMTILES_URL_ARM64" "$PMTILES_SHA256_ARM64" "$SCRATCH/bin/pmtiles.tar.gz" ;;
    *) echo "unsupported docker architecture" >&2; exit 1 ;;
  esac
  tar -xzf "$SCRATCH/bin/pmtiles.tar.gz" -C "$SCRATCH/bin" pmtiles
else
  mkdir -p "$SCRATCH/native"
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64)
      fetch_pinned "$CADDY_NATIVE_URL_MAC_ARM64" "$CADDY_NATIVE_SHA256_MAC_ARM64" "$SCRATCH/native/caddy.tar.gz"
      fetch_pinned "$PMTILES_URL_DARWIN_ARM64" "$PMTILES_SHA256_DARWIN_ARM64" "$SCRATCH/native/pmtiles.zip"
      unzip -o -q "$SCRATCH/native/pmtiles.zip" pmtiles -d "$SCRATCH/native" ;;
    Linux-x86_64)
      fetch_pinned "$CADDY_NATIVE_URL_LINUX_AMD64" "$CADDY_NATIVE_SHA256_LINUX_AMD64" "$SCRATCH/native/caddy.tar.gz"
      fetch_pinned "$PMTILES_URL_AMD64" "$PMTILES_SHA256_AMD64" "$SCRATCH/native/pmtiles.tar.gz"
      tar -xzf "$SCRATCH/native/pmtiles.tar.gz" -C "$SCRATCH/native" pmtiles ;;
    *) echo "no pinned native Caddy for $(uname -s)-$(uname -m); start Docker" >&2; exit 1 ;;
  esac
  tar -xzf "$SCRATCH/native/caddy.tar.gz" -C "$SCRATCH/native" caddy
fi
fetch_pinned "$PMTILES_TEST_FIXTURE_URL" "$PMTILES_TEST_FIXTURE_SHA256" "$SCRATCH/tiles/builds/$BUILD.pmtiles"
ln -sfn "../builds/$BUILD.pmtiles" "$SCRATCH/tiles/serve/planet-$BUILD.pmtiles"
ln -sfn "../builds/$BUILD.pmtiles" "$SCRATCH/tiles/serve/planet.pmtiles"
# An offline pack named as lunaway-tiles-packs names them, and its manifest.
PACK="fr-bre-$BUILD-0123abcd.pmtiles"
rm -f "$SCRATCH/tiles/packs/test.pmtiles"
cp "$SCRATCH/tiles/builds/$BUILD.pmtiles" "$SCRATCH/tiles/packs/$PACK"
printf '{"version": 1, "build": "%s", "packs": [{"id": "fr-bre", "url": "%s"}]}\n' "$BUILD" "$PACK" > "$SCRATCH/tiles/packs/manifest.json"
# The F-Droid repository as infra/fdroid/publish.sh deploys it: stand-ins
# for the signed index, a diff and an APK.
printf 'PK' > "$SCRATCH/fdroid/repo/index-v1.jar"
printf '{}' > "$SCRATCH/fdroid/repo/index-v2.json"
printf '{}' > "$SCRATCH/fdroid/repo/diff/1.json"
printf 'PK' > "$SCRATCH/fdroid/repo/legal.p2p.lunaway_1.apk"
# Compressible stand-ins for a glyph range and a sprite index, and a style
# that names its host the way the TileJSON does.
head -c 4096 /dev/zero > "$SCRATCH/tiles/assets/fonts/Noto Sans Regular/0-255.pbf"
echo '{"poi":{"x":0,"y":0,"width":16,"height":16,"pixelRatio":1}}' > "$SCRATCH/tiles/assets/sprites/protomaps-v4/light.json"
# A style as infra/server/install-basemap-assets.sh installs it.
# shellcheck disable=SC2016 # literal backticks, a Caddy template action
echo '{"version":8,"glyphs":"{{placeholder `http.vars.tiles_base`}}/fonts/{fontstack}/{range}.pbf"}' > "$SCRATCH/tiles/assets/styles/test.json"

# Test content, overwritten on each run.
# The landing site as it is deployed (infra/web/site), copied whole so that a
# page or an asset removed from it is gone here too. Its stylesheet and script
# carry a content hash in their names.
rsync -a --delete "$INFRA/web/site/" "$SCRATCH/site/"
css="$(find "$SCRATCH/site" -maxdepth 1 -name 'style.*.css' -exec basename {} \; | head -n 1)"
js="$(find "$SCRATCH/site/js" -maxdepth 1 -name 'delete-account.*.js' -exec basename {} \; | head -n 1)"
font="$(find "$SCRATCH/site/fonts" -maxdepth 1 -name 'atkinson-next-lunaway-regular.*.woff2' -exec basename {} \; | head -n 1)"
echo '<!doctype html><base href="/app/"><title>app</title>' > "$SCRATCH/web/index.html"
echo 'console.log(1)' > "$SCRATCH/web/main.dart.js"
echo '{}' > "$SCRATCH/web/assets/AssetManifest.json"
# Startup files as app/tool/web/fingerprint.py names them, one with the
# Brotli copy it writes beside it.
echo 'console.log(2)' > "$SCRATCH/web/main.dart.fedcba987654.js"
printf 'BR' > "$SCRATCH/web/main.dart.fedcba987654.js.br"
mkdir -p "$SCRATCH/web/canvaskit-fedcba987654"
printf 'WASM' > "$SCRATCH/web/canvaskit-fedcba987654/canvaskit.wasm"
printf 'JPEG' > "$SCRATCH/data/media/ab/0123abcd.jpg"
# A photo as the API writes it: content-addressed WebP.
mkdir -p "$SCRATCH/data/media/photos/ab/cd"
printf 'RIFF\x0c\x00\x00\x00WEBPVP8 ' > "$SCRATCH/data/media/photos/ab/cd/abcd0000000000000000000000000000000000000000000000000000000000ff.webp"
# A regional pack of places as lunaway-packs names it, a file of a build in
# progress in its work directory, and a file of another name beside the
# packs: only the first may be served.
PLACES_PACK="FR-BRE-4242-0123456789ab.sqlite.gz"
head -c 3000 /dev/urandom | gzip -c > "$SCRATCH/data/packs/places/$PLACES_PACK"
cp "$SCRATCH/data/packs/places/$PLACES_PACK" "$SCRATCH/data/packs/.work/$PLACES_PACK.partial"
echo note > "$SCRATCH/data/packs/places/notes.txt"
# Bodies for the size limits: /graphql takes 64 KiB, /upload 10304 KiB.
head -c 2000000 /dev/zero > "$SCRATCH/body-2mb"
head -c 60000 /dev/zero > "$SCRATCH/body-60kb"
head -c 70000 /dev/zero > "$SCRATCH/body-70kb"
head -c 11000000 /dev/zero > "$SCRATCH/body-11mb"
# An answer of 96 MiB from the stand-in API, for the write bound:
# larger than the socket buffers of a loopback connection on macOS.
mkdir -p "$SCRATCH/big"
head -c 100663296 /dev/zero > "$SCRATCH/big/answer.bin"

sed -e 's|admin unix//run/caddy/admin.sock|admin off|' \
    -e 's|acme_ca .*|auto_https off|' \
    -e "s|import /etc/caddy/sites-enabled/\\*.caddy|import $W/*.caddy|" \
    -e "s|/srv/data|$W/data|g" \
    -e "s|/srv/tiles|$W/tiles|g" \
    -e "s|/srv/lunaway/fdroid|$W/fdroid|g" \
    -e "s|127.0.0.1:8485|$PMTILES_UP|g" \
    -e "s|127.0.0.1:8484|$API_UP|g" \
    -e "s|output file /var/log/caddy/access.log|output file $ACCESS_LOG|" \
    -e "s|write_idle 3m 32768|write_idle 2s 4194304|" \
    "$INFRA/caddy/Caddyfile" > "$SCRATCH/Caddyfile"
grep -q 'write_idle 2s 4194304' "$SCRATCH/Caddyfile" || { echo "no write_idle 3m 32768 in the Caddyfile to shorten" >&2; exit 1; }
# Natively, nothing listens beyond loopback.
if [ "$MODE" = native ]; then
  python3 - "$SCRATCH/Caddyfile" <<'EOF'
import sys
text = open(sys.argv[1]).read()
open(sys.argv[1], "w").write(text.replace("\tadmin off\n", "\tadmin off\n\tdefault_bind 127.0.0.1\n", 1))
EOF
fi
# A stand-in for the API on its port: it reads the whole body (the
# placeholder does), so the body limits in front of it act as they do in
# production, and it names itself in a header. With X-Test-Big it sends a
# 96 MiB answer instead, as the API sends a long route.
cat >> "$SCRATCH/Caddyfile" <<EOF

http://:$API_LISTEN {
	header X-Test-Upstream api
	@big header X-Test-Big 1
	handle @big {
		root * $W/big
		rewrite * /answer.bin
		file_server
	}
	handle {
		respond "{http.request.body}" 200
	}
}
EOF
# The geocoders' loopback site on its own port, its upstreams (the
# Géoplateforme, Photon on the private network) replaced by a stand-in that
# answers with the host and the URI it was asked.
GEO_PORT=18486
sed -e "s|^http://127.0.0.1:8486 {|http://127.0.0.1:$GEO_PORT {|" \
    -e "s|https://data.geopf.fr|http://127.0.0.1:18487|" \
    -e "s|10.42.0.4:2322|127.0.0.1:18487|; s|10.42.0.4:2323|127.0.0.1:18487|" \
    "$INFRA/caddy/geocoders.caddy" > "$SCRATCH/geocoders.caddy"
grep -q '18487' "$SCRATCH/geocoders.caddy" || { echo "no upstream to replace in geocoders.caddy" >&2; exit 1; }
cat >> "$SCRATCH/Caddyfile" <<EOF

http://:18487 {
	respond "{http.request.host} {http.request.uri} xff={http.request.header.X-Forwarded-For}" 200
}
EOF
sed -e "s|^api.lunaway.net {|http://api.lunaway.net:$LISTEN {|" \
    -e "s|^lunaway.net {|http://lunaway.net:$LISTEN {|" \
    -e "s|^www.lunaway.net {|http://www.lunaway.net:$LISTEN {|" \
    -e "s|^tiles.lunaway.net {|http://tiles.lunaway.net:$LISTEN {|" \
    -e "s|/srv/lunaway/site|$W/site|; s|/srv/lunaway/web|$W/web|" \
    "$INFRA/caddy/lunaway.net.caddy" > "$SCRATCH/lunaway.net.caddy"

# The TileJSON as lunaway-tiles-refresh writes it.
# shellcheck disable=SC2016 # literal backticks, a Caddy template action
tilejson_from() {
  sed 's|__TILES_BASE__|{{placeholder `http.vars.tiles_base`}}|g' > "$SCRATCH/tiles/tilejson/planet.json"
}
if [ "$MODE" = docker ]; then
  docker rm -f lunaway-caddy-test lunaway-pmtiles-test >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
  docker network create "$NETWORK" >/dev/null
  docker run --rm -v "$SCRATCH:/w:ro" "$CADDY_IMAGE" /w/bin/pmtiles show --tilejson \
    --public-url="__TILES_BASE__/planet-$BUILD" "/w/tiles/serve/planet-$BUILD.pmtiles" | tilejson_from
  docker run -d --name lunaway-pmtiles-test --network "$NETWORK" -v "$SCRATCH:/w:ro" "$CADDY_IMAGE" \
    /w/bin/pmtiles serve /w/tiles/serve --interface=0.0.0.0 --port=8485 >/dev/null
  docker run -d --name lunaway-caddy-test --network "$NETWORK" -p "127.0.0.1:$PORT:8080" -v "$SCRATCH:/w:ro" "$CADDY_IMAGE" \
    caddy run --config /w/Caddyfile --adapter caddyfile >/dev/null
  caddy_log() { docker logs lunaway-caddy-test 2>&1; }
else
  "$SCRATCH/native/pmtiles" show --tilejson \
    --public-url="__TILES_BASE__/planet-$BUILD" "$SCRATCH/tiles/serve/planet-$BUILD.pmtiles" | tilejson_from
  : > "$ACCESS_LOG"
  "$SCRATCH/native/caddy" validate --config "$SCRATCH/Caddyfile" --adapter caddyfile > "$SCRATCH/caddy-validate.log" 2>&1 \
    || { tail -n 5 "$SCRATCH/caddy-validate.log" >&2; exit 1; }
  "$SCRATCH/native/pmtiles" serve "$SCRATCH/tiles/serve" --interface=127.0.0.1 --port=18485 > "$SCRATCH/pmtiles.log" 2>&1 &
  pmtiles_pid=$!
  "$SCRATCH/native/caddy" run --config "$SCRATCH/Caddyfile" --adapter caddyfile > "$SCRATCH/caddy.log" 2>&1 &
  caddy_pid=$!
  trap 'kill "$caddy_pid" "$pmtiles_pid" 2>/dev/null || true' EXIT
  caddy_log() { cat "$SCRATCH/caddy.log"; }
fi
for _ in $(seq 1 20); do
  curl -s -o /dev/null --connect-to "lunaway.net:8080:127.0.0.1:$PORT" http://lunaway.net:8080/ && break
  sleep 0.5
done

failures=0
# check NAME URL EXPECTED_STATUS [HEADER_REGEX]
check() {
  local name="$1" url="$2" status="$3" header="${4:-}" host got headers
  host="$(echo "$url" | sed -E 's|^http://([^:/]+):8080.*|\1|')"
  headers="$(curl -sS -D - -o /dev/null --connect-to "$host:8080:127.0.0.1:$PORT" "$url")"
  got="$(echo "$headers" | head -n 1 | awk '{ print $2 }')"
  if [ "$got" != "$status" ] || { [ -n "$header" ] && ! grep -qiE "$header" <<<"$headers"; }; then
    echo "FAIL $name: status $got (want $status)${header:+, header /$header/}"
    failures=$((failures + 1))
  else
    echo "ok   $name: $got${header:+, /$header/}"
  fi
}

L=http://lunaway.net:8080
NO_SCRIPT="content-security-policy: default-src 'none'; style-src 'self'; img-src 'self' data:; font-src 'self'; base-uri 'none'"
DELETE_CSP="content-security-policy: default-src 'none'; script-src 'self'; connect-src https://api.lunaway.net; style-src 'self'"
check "landing" "$L/" 200 "$NO_SCRIPT"
check "landing html cache" "$L/" 200 "cache-control: public, max-age=300"
check "hashed stylesheet" "$L/$css" 200 "cache-control: public, max-age=31536000, immutable"
check "stylesheet type" "$L/$css" 200 "content-type: text/css"
check "font" "$L/fonts/$font" 200 "content-type: font/woff2"
check "font cache" "$L/fonts/$font" 200 "immutable"
check "screenshot" "$L/img/screens/fr-1-map.webp" 200 "content-type: image/webp"
check "screenshot cache" "$L/img/screens/fr-1-map.webp" 200 "cache-control: public, max-age=300"
check "/en/" "$L/en/" 200 "$NO_SCRIPT"
check "/en" "$L/en" 200
check "/privacy" "$L/privacy" 200 "$NO_SCRIPT"
check "/en/privacy" "$L/en/privacy" 200 "$NO_SCRIPT"
check "/about" "$L/about" 200 "$NO_SCRIPT"
check "/en/about" "$L/en/about" 200
check "/legal" "$L/legal" 200 "$NO_SCRIPT"
check "/en/legal" "$L/en/legal" 200
check "/fdroid/" "$L/fdroid/" 200 "$NO_SCRIPT"
check "/fdroid" "$L/fdroid" 200
check "/en/fdroid/" "$L/en/fdroid/" 200
check "/account/delete" "$L/account/delete" 200 "$DELETE_CSP"
check "/en/account/delete" "$L/en/account/delete" 200 "$DELETE_CSP"
check "/account/delete.html" "$L/account/delete.html" 200 "$DELETE_CSP"
check "deletion script" "$L/js/$js" 200 "content-type: text/javascript"
check "deletion script cache" "$L/js/$js" 200 "immutable"
check "robots.txt" "$L/robots.txt" 200 "content-type: text/plain"
check "sitemap.xml" "$L/sitemap.xml" 200 "content-type: (text|application)/xml"
check "favicon.ico" "$L/favicon.ico" 200
check "unknown page" "$L/nope" 404 "$NO_SCRIPT"
check "unknown page under /en/" "$L/en/nope" 404
check "unknown page headers" "$L/nope" 404 "strict-transport-security: max-age=31536000; includeSubDomains"
# Only the deletion page may run a script: no other page's CSP names one.
for page in / /en/ /privacy /about /legal /fdroid/ /nope; do
  if curl -sS -D - -o /dev/null --connect-to "lunaway.net:8080:127.0.0.1:$PORT" "$L$page" | grep -qi '^content-security-policy:.*script-src'; then
    echo "FAIL $page: its CSP allows a script"
    failures=$((failures + 1))
  else
    echo "ok   $page: no script in its CSP"
  fi
done
check "/app redirect" http://lunaway.net:8080/app 301 "location: /app/"
check "/app/" http://lunaway.net:8080/app/ 200 "wasm-unsafe-eval"
check "/app/ cache" http://lunaway.net:8080/app/ 200 "cache-control: no-cache"
check "/app/ connect-src" http://lunaway.net:8080/app/ 200 "connect-src 'self' https://api.lunaway.net https://tiles.lunaway.net; "
if curl -sS -D - -o /dev/null --connect-to "lunaway.net:8080:127.0.0.1:$PORT" http://lunaway.net:8080/app/ | grep -qi 'openfreemap'; then
  echo "FAIL the web app's CSP still names OpenFreeMap"
  failures=$((failures + 1))
else
  echo "ok   the web app's CSP names no other tile host"
fi
# A file asked by name is served or answers 404, never index.html; only the
# app's routes fall back to it.
check "/app missing fallback font" http://lunaway.net:8080/app/fonts/NotoSansSymbols2-Regular.woff2 404
check "/app missing asset" http://lunaway.net:8080/app/assets/fonts/missing.otf 404
check "/app missing canvaskit file" http://lunaway.net:8080/app/canvaskit/missing.wasm 404
check "/app missing icon" http://lunaway.net:8080/app/icons/missing.png 404
check "/app missing script" http://lunaway.net:8080/app/missing.js 404
check "/app route with a trailing slash" http://lunaway.net:8080/app/lists/ 200 "cache-control: no-cache"
for route in /app/place/42/reviews /app/lists/; do
  if curl -sS --connect-to "lunaway.net:8080:127.0.0.1:$PORT" "http://lunaway.net:8080$route" | grep -qi '<base href="/app/">'; then
    echo "ok   $route falls back to the app's index.html"
  else
    echo "FAIL $route does not answer the app's index.html"
    failures=$((failures + 1))
  fi
done
for missing in /app/fonts/NotoSansSymbols2-Regular.woff2 /app/assets/fonts/missing.otf /app/canvaskit/missing.wasm; do
  # A bare 404: neither the app's index.html nor the site's error page.
  size="$(curl -sS -o /dev/null -w '%{size_download}' --connect-to "lunaway.net:8080:127.0.0.1:$PORT" "http://lunaway.net:8080$missing")"
  if [ "$size" = 0 ]; then
    echo "ok   $missing: an empty 404"
  else
    echo "FAIL $missing answers $size bytes"
    failures=$((failures + 1))
  fi
done
check "/app deep link" http://lunaway.net:8080/app/place/42/reviews 200 "wasm-unsafe-eval"
check "/app asset" http://lunaway.net:8080/app/main.dart.js 200 "content-type: text/javascript"
check "/app asset without a digest" http://lunaway.net:8080/app/main.dart.js 200 "cache-control: no-cache"
check "/app fingerprinted script" http://lunaway.net:8080/app/main.dart.fedcba987654.js 200 "cache-control: public, max-age=31536000, immutable"
check "/app fingerprinted CanvasKit" http://lunaway.net:8080/app/canvaskit-fedcba987654/canvaskit.wasm 200 "cache-control: public, max-age=31536000, immutable"
# The Brotli copy goes to a browser that accepts it, under the original's type.
br_headers="$(curl -sS -D - -o /dev/null -H 'Accept-Encoding: br, gzip' --connect-to "lunaway.net:8080:127.0.0.1:$PORT" http://lunaway.net:8080/app/main.dart.fedcba987654.js)"
if grep -qi '^content-encoding: br' <<<"$br_headers" && grep -qi '^content-type: text/javascript' <<<"$br_headers"; then
  echo "ok   /app Brotli copy served as the script"
else
  echo "FAIL /app Brotli copy: $(tr -d '\r' <<<"$br_headers" | grep -iE '^content-(encoding|type)' | tr '\n' ' ')"
  failures=$((failures + 1))
fi
check "/app nested asset" http://lunaway.net:8080/app/assets/AssetManifest.json 200 "content-type: application/json"
check "media file" http://api.lunaway.net:8080/media/ab/0123abcd.jpg 200 "cache-control: public, max-age=31536000, immutable"
check "media sandbox" http://api.lunaway.net:8080/media/ab/0123abcd.jpg 200 "content-security-policy: default-src 'none'; frame-ancestors 'none'; sandbox"
check "media miss" http://api.lunaway.net:8080/media/ab/ffffffff.jpg 404
# A directory is not a file: a plain 404, never a listing.
check "media directory not listed" http://api.lunaway.net:8080/media/ab/ 404
check "no media on the site" http://lunaway.net:8080/media/ab/0123abcd.jpg 404
check "headers" http://lunaway.net:8080/ 200 "strict-transport-security: max-age=31536000; includeSubDomains"
check "no server header" http://lunaway.net:8080/ 200 "^x-frame-options: DENY"
check "www redirect" http://www.lunaway.net:8080/privacy 301 "location: https://lunaway.net/privacy"
check "api other path" http://api.lunaway.net:8080/admin 404 "content-security-policy: default-src 'none'"
check "api health proxied" http://api.lunaway.net:8080/health 200 "x-test-upstream: api"

# The basemap, on the tiles host.
T=http://tiles.lunaway.net:8080
check "tilejson" "$T/planet.json" 200 "cache-control: public, max-age=3600"
check "tilejson cors" "$T/planet.json" 200 "access-control-allow-origin: \\*"
check "build tile" "$T/planet-$BUILD/0/0/0.mvt" 200 "cache-control: public, max-age=31536000, immutable"
check "build tile type" "$T/planet-$BUILD/0/0/0.mvt" 200 "content-type: application/x-protobuf"
check "build tile cors" "$T/planet-$BUILD/0/0/0.mvt" 200 "access-control-allow-origin: \\*"
# The body depends on Accept-Encoding (below): a shared cache must know.
check "build tile vary" "$T/planet-$BUILD/0/0/0.mvt" 200 "vary: accept-encoding"
check "zoom beyond the build" "$T/planet-$BUILD/1/0/0.mvt" 404 "immutable"
check "unknown build" "$T/planet-20000101/0/0/0.mvt" 404
check "current tile" "$T/planet/0/0/0.mvt" 200 "cache-control: public, max-age=86400"
check "not a tile path" "$T/planet-$BUILD/0/0/0.png" 404
check "font" "$T/fonts/Noto%20Sans%20Regular/0-255.pbf" 200 "content-type: application/x-protobuf"
check "font cache" "$T/fonts/Noto%20Sans%20Regular/0-255.pbf" 200 "cache-control: public, max-age=604800"
check "font miss" "$T/fonts/Noto%20Sans%20Regular/65280-65535.pbf" 404
check "sprite" "$T/sprites/protomaps-v4/light.json" 200 "cache-control: public, max-age=86400"
check "style" "$T/styles/test.json" 200 "cache-control: public, max-age=3600"
check "pack" "$T/packs/$PACK" 200 "accept-ranges: bytes"
check "pack cache" "$T/packs/$PACK" 200 "cache-control: public, max-age=31536000, immutable"
check "pack manifest" "$T/packs/manifest.json" 200 "cache-control: public, max-age=300"
check "pack manifest cors" "$T/packs/manifest.json" 200 "access-control-allow-origin: \\*"
check "pack miss" "$T/packs/fr-bre-20000101-0123abcd.pmtiles" 404
check "not a pack name" "$T/packs/FR.pmtiles" 404
check "not a pack file" "$T/packs/manifest.txt" 404
check "packs not listed" "$T/packs/" 404
check "tiles host csp" "$T/planet.json" 200 "content-security-policy: default-src 'none'.*sandbox"
check "tiles host other path" "$T/admin" 404
# The basemap lives on its own host only: the API host has no /tiles/.
check "no basemap on the api host" http://api.lunaway.net:8080/tiles/planet.json 404

# The regional packs of places (docs/region-packs.md), on the API hosts.
A=http://api.lunaway.net:8080
check "places pack" "$A/packs/places/$PLACES_PACK" 200 "accept-ranges: bytes"
check "places pack cache" "$A/packs/places/$PLACES_PACK" 200 "cache-control: public, max-age=31536000, immutable"
check "places pack cors" "$A/packs/places/$PLACES_PACK" 200 "access-control-allow-origin: https://lunaway.net"
check "places pack exposes its range headers" "$A/packs/places/$PLACES_PACK" 200 "access-control-expose-headers: .*Content-Range"
check "places pack miss" "$A/packs/places/FR-BRE-4242-ffffffffffff.sqlite.gz" 404
check "places pack work file" "$A/packs/.work/$PLACES_PACK.partial" 404
check "places pack work directory" "$A/packs/.work/" 404
check "places packs not listed" "$A/packs/places/" 404
check "packs root not listed" "$A/packs/" 404
check "another file beside the packs" "$A/packs/places/notes.txt" 404
check "a pack name in lower case" "$A/packs/places/fr-bre-4242-0123456789ab.sqlite.gz" 404
check "a pack name with a shorter hash" "$A/packs/places/FR-BRE-4242-0123456789a.sqlite.gz" 404
check "places pack on the site host" "$L/packs/places/$PLACES_PACK" 404
if curl -sS -D - -o /dev/null --connect-to "api.lunaway.net:8080:127.0.0.1:$PORT" "$A/packs/places/FR-BRE-4242-ffffffffffff.sqlite.gz" \
  | grep -qi '^cache-control:.*immutable'; then
  echo "FAIL a places pack miss carries the year-long cache"
  failures=$((failures + 1))
else
  echo "ok   a places pack miss is not cached"
fi

# The F-Droid repository: on lunaway.net under /fdroid/repo/, and nowhere
# else.
check "fdroid index" "$L/fdroid/repo/index-v1.jar" 200 "cache-control: no-cache"
check "fdroid index csp" "$L/fdroid/repo/index-v1.jar" 200 "content-security-policy: default-src 'none'; frame-ancestors 'none'; sandbox"
check "fdroid index v2" "$L/fdroid/repo/index-v2.json" 200 "content-type: application/json"
check "fdroid diff" "$L/fdroid/repo/diff/1.json" 200 "cache-control: no-cache"
check "fdroid apk" "$L/fdroid/repo/legal.p2p.lunaway_1.apk" 200 "cache-control: public, max-age=86400"
check "fdroid apk range" "$L/fdroid/repo/legal.p2p.lunaway_1.apk" 200 "accept-ranges: bytes"
check "fdroid miss" "$L/fdroid/repo/nope.apk" 404
check "fdroid directory not listed" "$L/fdroid/repo/diff/" 404
check "no fdroid on the api host" http://api.lunaway.net:8080/fdroid/repo/index-v1.jar 404
check "fdroid bare address" "$L/fdroid/repo" 302 "location: /fdroid/"
check "fdroid address with a slash" "$L/fdroid/repo/" 302 "location: /fdroid/"
check "fdroid page still served" "$L/fdroid/" 200 "$NO_SCRIPT"

# sent NAME METHOD URL EXPECTED_STATUS [CURL ARGS...]: the status of a
# request with a method and a body. 200 comes from the stand-in API.
sent() {
  local name="$1" method="$2" url="$3" status="$4" host got
  shift 4
  host="$(echo "$url" | sed -E 's|^http://([^:/]+):8080.*|\1|')"
  got="$(curl -sS -o /dev/null -w '%{http_code}' -X "$method" --connect-to "$host:8080:127.0.0.1:$PORT" "$@" "$url")"
  if [ "$got" = "$status" ]; then
    echo "ok   $name: $got"
  else
    echo "FAIL $name: status $got (want $status)"
    failures=$((failures + 1))
  fi
}
A=http://api.lunaway.net:8080
sent "upload of 2 MB routed to the API" POST "$A/upload" 200 -F placeId=x -F file=@"$SCRATCH/body-2mb"
sent "upload preflight routed" OPTIONS "$A/upload" 200 -H 'Origin: https://lunaway.net' -H 'Access-Control-Request-Method: POST'
sent "upload of 11 MB" POST "$A/upload" 413 --data-binary @"$SCRATCH/body-11mb" -H 'Content-Type: multipart/form-data; boundary=x'
sent "upload by GET" GET "$A/upload" 405
sent "fdroid repository by POST" POST "$L/fdroid/repo/index-v1.jar" 405 -d x
sent "fdroid repository by PUT" PUT "$L/fdroid/repo/index-v1.jar" 405 -d x
sent "graphql body of 2 MB" POST "$A/graphql" 413 --data-binary @"$SCRATCH/body-2mb" -H 'Content-Type: application/json'
sent "graphql body of 60 KB" POST "$A/graphql" 200 --data-binary @"$SCRATCH/body-60kb" -H 'Content-Type: application/json'
sent "graphql body of 70 KB" POST "$A/graphql" 413 --data-binary @"$SCRATCH/body-70kb" -H 'Content-Type: application/json'
# The write bound, shortened above to 2 s plus a second per 4 MiB sent: a
# client reading /graphql at full speed gets the whole 96 MiB answer, one
# reading at 1 MiB/s is cut well before the 96 s it would need. curl sees
# the cut once it has drained the socket buffers, a few MiB.
big_fast="$(curl -sS -o /dev/null -w '%{size_download}' -H 'X-Test-Big: 1' \
  --connect-to "api.lunaway.net:8080:127.0.0.1:$PORT" "$A/graphql" || true)"
big_slow="$(curl -sS -o /dev/null -w '%{size_download} %{time_total}' --limit-rate 1m --max-time 150 \
  -H 'X-Test-Big: 1' --connect-to "api.lunaway.net:8080:127.0.0.1:$PORT" "$A/graphql" 2>/dev/null || true)"
if [ "$big_fast" = 100663296 ] && awk -v b="${big_slow%% *}" -v t="${big_slow#* }" 'BEGIN { exit !(b < 100663296 && t < 90) }'; then
  echo "ok   write bound: a fast reader gets 96 MiB, a reader at 1 MiB/s is cut ($big_slow: bytes, seconds)"
else
  echo "FAIL write bound: fast reader $big_fast bytes (want 100663296), slow reader $big_slow (want cut)"
  failures=$((failures + 1))
fi
# The tiles of the points of interest: reads only, all to the API.
sent "poi tile routed to the API" GET "$A/poi/3/13/4149/2815.mvt" 200
sent "poi TileJSON routed to the API" GET "$A/poi/tiles.json" 200
sent "poi tile by HEAD" HEAD "$A/poi/3/13/4149/2815.mvt" 200 -I
sent "poi preflight routed" OPTIONS "$A/poi/3/13/4149/2815.mvt" 200 -H 'Origin: https://lunaway.net' -H 'Access-Control-Request-Method: GET'
sent "poi by POST" POST "$A/poi/tiles.json" 405 --data-binary '{}'
sent "poi with a body over 1 KiB" GET "$A/poi/tiles.json" 413 --data-binary @"$SCRATCH/body-60kb"
# The tiles of the places: the same contract.
sent "places tile routed to the API" GET "$A/places/7/12/2075/1409.mvt" 200
sent "places TileJSON routed to the API" GET "$A/places/tiles.json" 200
sent "places tile by HEAD" HEAD "$A/places/7/12/2075/1409.mvt" 200 -I
sent "places preflight routed" OPTIONS "$A/places/7/12/2075/1409.mvt" 200 -H 'Origin: https://lunaway.net' -H 'Access-Control-Request-Method: GET'
sent "places by POST" POST "$A/places/tiles.json" 405 --data-binary '{}'
sent "places with a body over 1 KiB" GET "$A/places/tiles.json" 413 --data-binary @"$SCRATCH/body-60kb"
sent "places pack by POST" POST "$A/packs/places/$PLACES_PACK" 405 --data-binary '{}'
sent "places pack by HEAD" HEAD "$A/packs/places/$PLACES_PACK" 200 -I
if curl -sS -D - -o /dev/null -X PUT --connect-to "api.lunaway.net:8080:127.0.0.1:$PORT" "$A/packs/places/$PLACES_PACK" \
  | grep -qi '^allow: GET, HEAD, OPTIONS'; then
  echo "ok   places pack by PUT says what it allows: GET, HEAD, OPTIONS"
else
  echo "FAIL places pack by PUT: no Allow: GET, HEAD, OPTIONS"
  failures=$((failures + 1))
fi
if curl -sS -D - -o /dev/null -X DELETE --connect-to "api.lunaway.net:8080:127.0.0.1:$PORT" "$A/poi/tiles.json" \
  | grep -qi '^allow: GET, HEAD, OPTIONS'; then
  echo "ok   poi by DELETE says what it allows: GET, HEAD, OPTIONS"
else
  echo "FAIL poi by DELETE: no Allow: GET, HEAD, OPTIONS"
  failures=$((failures + 1))
fi
if curl -sS -D - -o /dev/null -X DELETE --connect-to "api.lunaway.net:8080:127.0.0.1:$PORT" "$A/places/tiles.json" \
  | grep -qi '^allow: GET, HEAD, OPTIONS'; then
  echo "ok   places by DELETE says what it allows: GET, HEAD, OPTIONS"
else
  echo "FAIL places by DELETE: no Allow: GET, HEAD, OPTIONS"
  failures=$((failures + 1))
fi
check "photo type" http://api.lunaway.net:8080/media/photos/ab/cd/abcd0000000000000000000000000000000000000000000000000000000000ff.webp 200 "content-type: image/webp"
check "upload by GET says what it allows" "$A/upload" 405 "allow: POST, OPTIONS"

# fetch NAME URL [CURL ARGS...]: the body of a response, in a file.
fetch() {
  local name="$1" url="$2" host
  shift 2
  host="$(echo "$url" | sed -E 's|^http://([^:/]+):8080.*|\1|')"
  curl -sS -o "$SCRATCH/$name.out" --connect-to "$host:8080:127.0.0.1:$PORT" "$@" "$url"
}
# body NAME PYTHON_CONDITION: the condition, on the bytes b of the body of NAME.
body() {
  if python3 -c "import gzip, json, sys; b = open(sys.argv[1], 'rb').read(); sys.exit(0 if ($2) else 1)" "$SCRATCH/$1.out" 2>/dev/null; then
    echo "ok   $1: $2"
  else
    echo "FAIL $1: $2 ($(head -c 160 "$SCRATCH/$1.out" | tr -c '[:print:]' '.'))"
    failures=$((failures + 1))
  fi
}
fetch tilejson-tiles "$T/planet.json"
body tilejson-tiles "json.loads(b)['tiles'] == ['https://tiles.lunaway.net/planet-$BUILD/{z}/{x}/{y}.mvt']"
# pmtiles always answers with the gzip stream stored in the archive. A client
# that accepts gzip gets it as is, encoded once (one gunzip gives the vector
# tile, not another gzip stream); for a client that does not, Caddy's
# transport decodes it.
fetch tile-body "$T/planet-$BUILD/0/0/0.mvt" -H 'Accept-Encoding: gzip, zstd' -D "$SCRATCH/tile-headers.out"
body tile-body "b[:2] == b'\\x1f\\x8b' and len(gzip.decompress(b)) > 0 and gzip.decompress(b)[:2] != b'\\x1f\\x8b'"
if grep -qi '^content-encoding: gzip' "$SCRATCH/tile-headers.out" && [ "$(grep -ci '^vary:' "$SCRATCH/tile-headers.out")" = 1 ]; then
  echo "ok   tile for a gzip client: content-encoding gzip, one Vary header"
else
  echo "FAIL tile for a gzip client: $(grep -iE '^(content-encoding|vary):' "$SCRATCH/tile-headers.out" | tr -d '\r' | tr '\n' ' ')"
  failures=$((failures + 1))
fi
fetch tile-plain "$T/planet-$BUILD/0/0/0.mvt" -D "$SCRATCH/tile-plain-headers.out"
body tile-plain "len(b) > 0 and b[:2] != b'\\x1f\\x8b' and b == gzip.decompress(open(sys.argv[1].replace('tile-plain', 'tile-body'), 'rb').read())"
if grep -qi '^content-encoding' "$SCRATCH/tile-plain-headers.out"; then echo "FAIL tile for a client without gzip: still encoded"; failures=$((failures + 1)); else echo "ok   tile for a client without gzip: decoded by Caddy"; fi
fetch font-body "$T/fonts/Noto%20Sans%20Regular/0-255.pbf" -H 'Accept-Encoding: gzip' -D "$SCRATCH/font-headers.out"
if grep -qi '^content-encoding: gzip' "$SCRATCH/font-headers.out"; then echo "ok   glyphs are compressed"; else echo "FAIL glyphs are sent uncompressed"; failures=$((failures + 1)); fi
fetch style-body "$T/styles/test.json"
body style-body "json.loads(b)['glyphs'] == 'https://tiles.lunaway.net/fonts/{fontstack}/{range}.pbf'"
# A missing page answers with the site's 404 page, in both languages.
fetch page-404 "$L/nope"
body page-404 "b'<title>Page introuvable' in b and b'This page does not exist' in b"
fetch pack-range "$T/packs/$PACK" -r 0-6 -D "$SCRATCH/pack-headers.out"
body pack-range "b == b'PMTiles'"
if grep -q '^HTTP/1.1 206' "$SCRATCH/pack-headers.out" && grep -qi '^content-range: bytes 0-6/' "$SCRATCH/pack-headers.out"; then
  echo "ok   pack range: 206 with content-range"
else
  echo "FAIL pack range: $(head -n 1 "$SCRATCH/pack-headers.out")"
  failures=$((failures + 1))
fi
preflight="$(curl -sS -D - -o /dev/null --connect-to "tiles.lunaway.net:8080:127.0.0.1:$PORT" -X OPTIONS \
  -H 'Origin: https://example.org' -H 'Access-Control-Request-Method: GET' -H 'Access-Control-Request-Headers: range' \
  "$T/packs/$PACK")"
if grep -q '^HTTP/1.1 204' <<<"$preflight" && grep -qi '^access-control-allow-headers:.*Range' <<<"$preflight"; then
  echo "ok   preflight for a range request: 204, Range allowed"
else
  echo "FAIL preflight for a range request: $(head -n 1 <<<"$preflight")"
  failures=$((failures + 1))
fi
# A places pack comes as stored, never re-encoded on the way, even to a
# client that accepts gzip and zstd: its SHA-256 is the manifest's.
fetch places-pack "$A/packs/places/$PLACES_PACK" -H 'Accept-Encoding: gzip, zstd' -D "$SCRATCH/places-pack-headers.out"
if cmp -s "$SCRATCH/places-pack.out" "$SCRATCH/data/packs/places/$PLACES_PACK" && ! grep -qi '^content-encoding' "$SCRATCH/places-pack-headers.out"; then
  echo "ok   places pack: the stored bytes, no content-encoding"
else
  echo "FAIL places pack: not the stored bytes ($(grep -i '^content-encoding' "$SCRATCH/places-pack-headers.out" | tr -d '\r'))"
  failures=$((failures + 1))
fi
fetch places-pack-range "$A/packs/places/$PLACES_PACK" -r 100-199 -D "$SCRATCH/places-pack-range-headers.out"
if grep -q '^HTTP/1.1 206' "$SCRATCH/places-pack-range-headers.out" \
  && grep -qi '^content-range: bytes 100-199/' "$SCRATCH/places-pack-range-headers.out" \
  && [ "$(wc -c < "$SCRATCH/places-pack-range.out" | tr -d ' ')" = 100 ]; then
  echo "ok   places pack range: 206, content-range, 100 bytes"
else
  echo "FAIL places pack range: $(head -n 1 "$SCRATCH/places-pack-range-headers.out")"
  failures=$((failures + 1))
fi
preflight="$(curl -sS -D - -o /dev/null --connect-to "api.lunaway.net:8080:127.0.0.1:$PORT" -X OPTIONS \
  -H 'Origin: https://lunaway.net' -H 'Access-Control-Request-Method: GET' -H 'Access-Control-Request-Headers: range' \
  "$A/packs/places/$PLACES_PACK")"
if grep -q '^HTTP/1.1 204' <<<"$preflight" && grep -qi '^access-control-allow-headers:.*Range' <<<"$preflight" \
  && grep -qi '^access-control-allow-origin: https://lunaway.net' <<<"$preflight"; then
  echo "ok   preflight for a places pack range: 204, Range allowed for https://lunaway.net"
else
  echo "FAIL preflight for a places pack range: $(head -n 1 <<<"$preflight")"
  failures=$((failures + 1))
fi
write="$(curl -sS -o /dev/null -w '%{http_code}' --connect-to "tiles.lunaway.net:8080:127.0.0.1:$PORT" -X POST -d x "$T/planet.json")"
if [ "$write" = 405 ]; then echo "ok   a POST to the tiles host: 405"; else echo "FAIL a POST to the tiles host: $write"; failures=$((failures + 1)); fi

for page in / /nope; do
  if curl -sS -D - -o /dev/null --connect-to "lunaway.net:8080:127.0.0.1:$PORT" "http://lunaway.net:8080$page" | grep -qi '^server:'; then
    echo "FAIL $page sends a Server header"
    failures=$((failures + 1))
  fi
done
if curl -sS -D - -o /dev/null --connect-to "api.lunaway.net:8080:127.0.0.1:$PORT" http://api.lunaway.net:8080/media/ab/ffffffff.jpg | grep -qi '^cache-control:.*immutable'; then
  echo "FAIL a media miss carries the year-long cache"
  failures=$((failures + 1))
fi

# Caddy's own log: a request for a host no site serves is logged there (not
# in the access log), and its client address must come out masked like the
# access log's (IPv4 /16, so the last two bytes are 0), without a port.
curl -sS -o /dev/null --connect-to "nobody.test:8080:127.0.0.1:$PORT" http://nobody.test:8080/ || true
sleep 1
default_log="$(caddy_log | grep '"logger":"http.log.access"' | grep '"host":"nobody.test:8080"' || true)"
if [ -z "$default_log" ]; then
  echo "FAIL no default-log line for a request to an unknown host"
  failures=$((failures + 1))
elif grep -qE '"remote_ip":"[0-9]+\.[0-9]+\.([1-9][0-9]*\.[0-9]+|0\.[1-9][0-9]*)"|"remote_port"' <<<"$default_log"; then
  echo "FAIL the default log writes a full client address: $(echo "$default_log" | head -n 1 | cut -c1-200)"
  failures=$((failures + 1))
else
  echo "ok   default log masks the client: $(echo "$default_log" | grep -oE '"remote_ip":"[^"]*"' | head -n 1)"
fi

# Query strings never reach a log: a GraphQL GET could carry a position.
curl -sS -o /dev/null --connect-to "nobody.test:8080:127.0.0.1:$PORT" "http://nobody.test:8080/graphql?variables=lat45.7629" || true
sleep 1
if caddy_log | grep -q 'lat45.7629'; then
  echo "FAIL a query string reached the log"
  failures=$((failures + 1))
else
  echo "ok   query strings are stripped from the log"
fi

# Nothing that names a tile or a photo reaches the access log: tile
# coordinates, a byte range of a pack and the range it answers, a tile's
# ETag, its size, a photo's path.
curl -sS -o /dev/null --connect-to "tiles.lunaway.net:8080:127.0.0.1:$PORT" "$T/planet-$BUILD/14/8345/5678.mvt"
curl -sS -o /dev/null --connect-to "api.lunaway.net:8080:127.0.0.1:$PORT" \
  http://api.lunaway.net:8080/media/photos/ab/cd/abcd0000000000000000000000000000000000000000000000000000000000ff.webp
curl -sS -o /dev/null --connect-to "tiles.lunaway.net:8080:127.0.0.1:$PORT" -r 123-234 "$T/packs/$PACK"
# A places pack as the app asks for it is served; other spellings of the
# same path, which Caddy's path matching would decode or clean into it, are
# not. None may name its region in the log, served or not.
for spelling in "200 /packs/places/$PLACES_PACK" "404 //packs/places/$PLACES_PACK" "404 /packs/%70laces/$PLACES_PACK" \
  "404 /packs/places/$PLACES_PACK?x=1" "404 /PACKS/places/$PLACES_PACK" "404 /packs/places/./$PLACES_PACK" \
  "404 /%70acks/places/$PLACES_PACK" "404 /packs%2Fplaces/$PLACES_PACK"; do
  want="${spelling%% *}"
  path="${spelling#* }"
  got="$(curl -sS -o /dev/null -w '%{http_code}' --path-as-is --connect-to "api.lunaway.net:8080:127.0.0.1:$PORT" "http://api.lunaway.net:8080$path")"
  if [ "$got" = "$want" ]; then
    echo "ok   places pack spelled $(echo "$path" | sed "s|$PLACES_PACK|<pack>|"): $got"
  else
    echo "FAIL places pack spelled $(echo "$path" | sed "s|$PLACES_PACK|<pack>|"): $got (want $want)"
    failures=$((failures + 1))
  fi
done
etag="$(grep -i '^etag:' "$SCRATCH/tile-headers.out" | sed -E 's/^[Ee][Tt][Aa][Gg]: *"?([^"]*)"?.*/\1/' | tr -d '\r')"
curl -sS -o /dev/null --connect-to "tiles.lunaway.net:8080:127.0.0.1:$PORT" -H "If-None-Match: \"$etag\"" "$T/planet-$BUILD/0/0/0.mvt"
sleep 1
# The geocoders' site: each way to its upstream, path and query kept,
# nothing else answered. Natively only: in Docker the site's loopback is the
# container's.
if [ "$MODE" = native ]; then
  geo() { curl -sS -w ' %{http_code}' "http://127.0.0.1:$GEO_PORT$1"; }
  for want in \
    "/ban/search?q=avenue%20de%20segur&limit=5|data.geopf.fr /geocodage/search?q=avenue%20de%20segur&limit=5 xff= 200" \
    "/photon/europe/api?q=berlin|127.0.0.1 /api?q=berlin xff= 200" \
    "/photon/morocco/api?q=fes|127.0.0.1 /api?q=fes xff= 200"; do
    path="${want%%|*}"
    got="$(geo "$path")"
    if [ "$got" = "${want#*|}" ]; then
      echo "ok   geocoders $path: $got"
    else
      echo "FAIL geocoders $path: $got (want ${want#*|})"
      failures=$((failures + 1))
    fi
  done
  got="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$GEO_PORT/geocodage/search?q=x")"
  if [ "$got" = 404 ]; then
    echo "ok   geocoders: any other path 404"
  else
    echo "FAIL geocoders: another path answered $got"
    failures=$((failures + 1))
  fi
fi
if [ "$MODE" = docker ]; then
  access_log="$(docker exec lunaway-caddy-test cat /tmp/access.log)"
else
  access_log="$(cat "$ACCESS_LOG")"
fi
leaks=""
# In the request's fields only: a timestamp may hold the same digits.
grep -qE '"uri":"[^"]*(8345|5678)' <<<"$access_log" && leaks="$leaks coordinates"
# The tiles of the points of interest, requested above through the API.
grep -qE '"uri":"[^"]*(4149|2815)' <<<"$access_log" && leaks="$leaks poi-coordinates"
grep -q '"uri":"/poi/3/13/x/y.mvt"' <<<"$access_log" || leaks="$leaks no-masked-poi-line"
# The tiles of the places, the same way.
grep -qE '"uri":"[^"]*(2075|1409)' <<<"$access_log" && leaks="$leaks places-coordinates"
grep -q '"uri":"/places/7/12/x/y.mvt"' <<<"$access_log" || leaks="$leaks no-masked-places-line"
grep -q 'abcd00000' <<<"$access_log" && leaks="$leaks photo"
# The text of a search sent to the geocoders.
grep -qiE 'segur|berlin' <<<"$access_log" && leaks="$leaks geocoded-text"
grep -q '"uri":"/media/\[photo\]"' <<<"$access_log" || leaks="$leaks no-masked-photo-line"
grep -qE '123-234|bytes 123' <<<"$access_log" && leaks="$leaks range"
grep -q 'fr-bre' <<<"$access_log" && leaks="$leaks pack-region"
grep -q '"uri":"/packs/\[pack\].pmtiles"' <<<"$access_log" || leaks="$leaks no-masked-pack-line"
grep -qE 'FR-BRE|0123456789ab' <<<"$access_log" && leaks="$leaks places-pack-region"
grep -q '"uri":"/packs/places/\[pack\]"' <<<"$access_log" || leaks="$leaks no-masked-places-pack-line"
[ -n "$etag" ] && grep -qF "$etag" <<<"$access_log" && leaks="$leaks etag"
# A file's date names it as well as its ETag (a HEAD of each pack matches it).
grep -qE '"(Last-Modified|If-Modified-Since|If-Unmodified-Since)":' <<<"$access_log" && leaks="$leaks dates"
python3 -c '
import json, sys
for line in sys.stdin:
    entry = json.loads(line)
    if "size" in entry or {"Content-Length", "Content-Range", "Etag"} & set(entry.get("resp_headers", {})):
        sys.exit(1)' <<<"$access_log" || leaks="$leaks size"
if [ -n "$leaks" ]; then
  echo "FAIL the access log names a tile:$leaks"
  failures=$((failures + 1))
elif [ -n "$etag" ] && grep -q "\"uri\":\"/planet-$BUILD/14/x/y.mvt\"" <<<"$access_log"; then
  echo "ok   the access log keeps the zoom only (/planet-$BUILD/14/x/y.mvt, /poi/3/13/x/y.mvt, /places/7/12/x/y.mvt), /media/[photo], /packs/[pack].pmtiles and /packs/places/[pack]: no range, ETag, size, photo name or pack region"
else
  echo "FAIL no masked tile line in the access log, or no ETag to look for"
  failures=$((failures + 1))
fi

# The main Caddyfile alone, as on a backend before infra/enable-domain.sh
# (or after --disable): it adapts with no site at all, so the server answers
# no name of its own.
mkdir -p "$SCRATCH/sites-none"
sed "s|import /etc/caddy/sites-enabled/\\*.caddy|import $W/sites-none/*.caddy|" "$INFRA/caddy/Caddyfile" > "$SCRATCH/Caddyfile.bare"
if [ "$MODE" = docker ]; then
  docker run --rm -v "$SCRATCH:/w:ro" "$CADDY_IMAGE" caddy adapt --config /w/Caddyfile.bare --adapter caddyfile \
    > "$SCRATCH/bare.json" 2> "$SCRATCH/bare.log" || true
else
  "$SCRATCH/native/caddy" adapt --config "$SCRATCH/Caddyfile.bare" --adapter caddyfile > "$SCRATCH/bare.json" 2> "$SCRATCH/bare.log" || true
fi
if python3 -c '
import json, sys
c = json.load(open(sys.argv[1]))
sys.exit(1 if c.get("apps", {}).get("http", {}).get("servers") else 0)' "$SCRATCH/bare.json" 2>/dev/null; then
  echo "ok   the main Caddyfile alone adapts with no site"
else
  echo "FAIL the main Caddyfile alone: $(tail -n 1 "$SCRATCH/bare.log" | cut -c1-160)$(head -c 160 "$SCRATCH/bare.json")"
  failures=$((failures + 1))
fi

if [ "$MODE" = docker ]; then
  docker rm -f lunaway-caddy-test lunaway-pmtiles-test >/dev/null
  docker network rm "$NETWORK" >/dev/null
fi
echo "$failures failure(s)"
[ "$failures" = 0 ]
