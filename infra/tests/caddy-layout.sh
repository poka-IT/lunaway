#!/usr/bin/env bash
# Checks the routing of infra/caddy/ (the sslip.io API host and the
# lunaway.net sites, tiles.lunaway.net included) in the official Caddy image,
# before the domain is enabled. The configuration is the real one, rewritten
# for a test: plain HTTP on port 8080, no admin API, test roots under the
# scratch directory, which is the containers' only mount (read-only). The
# basemap routes go to a real `pmtiles serve` (the pinned release, in a second
# container on a private Docker network) over a one-tile archive from the
# go-pmtiles test suite; both are downloaded once into the scratch directory
# and checked against infra/tiles/version.sh.
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

docker info >/dev/null 2>&1 || { echo "docker does not answer" >&2; exit 1; }
mkdir -p "$SCRATCH/site" "$SCRATCH/web/assets" "$SCRATCH/data/media/ab"
mkdir -p "$SCRATCH/bin" "$SCRATCH/tiles/builds" "$SCRATCH/tiles/serve" "$SCRATCH/tiles/tilejson" \
  "$SCRATCH/tiles/assets/fonts/Noto Sans Regular" "$SCRATCH/tiles/assets/sprites/protomaps-v4" \
  "$SCRATCH/tiles/assets/styles" "$SCRATCH/tiles/packs"

# fetch_pinned URL SHA256 FILE: downloads once, and checks the hash each run.
fetch_pinned() {
  [ -f "$3" ] || curl -fsSL -m 300 -o "$3" "$1"
  [ "$(shasum -a 256 "$3" | awk '{ print $1 }')" = "$2" ] || { echo "$3 does not match its pin" >&2; exit 1; }
}
case "$(docker info --format '{{.Architecture}}')" in
  x86_64) fetch_pinned "$PMTILES_URL_AMD64" "$PMTILES_SHA256_AMD64" "$SCRATCH/bin/pmtiles.tar.gz" ;;
  aarch64) fetch_pinned "$PMTILES_URL_ARM64" "$PMTILES_SHA256_ARM64" "$SCRATCH/bin/pmtiles.tar.gz" ;;
  *) echo "unsupported docker architecture" >&2; exit 1 ;;
esac
tar -xzf "$SCRATCH/bin/pmtiles.tar.gz" -C "$SCRATCH/bin" pmtiles
fetch_pinned "$PMTILES_TEST_FIXTURE_URL" "$PMTILES_TEST_FIXTURE_SHA256" "$SCRATCH/tiles/builds/$BUILD.pmtiles"
ln -sfn "../builds/$BUILD.pmtiles" "$SCRATCH/tiles/serve/planet-$BUILD.pmtiles"
ln -sfn "../builds/$BUILD.pmtiles" "$SCRATCH/tiles/serve/planet.pmtiles"
cp "$SCRATCH/tiles/builds/$BUILD.pmtiles" "$SCRATCH/tiles/packs/test.pmtiles"
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
printf 'JPEG' > "$SCRATCH/data/media/ab/0123abcd.jpg"
# A photo as the API writes it: content-addressed WebP.
mkdir -p "$SCRATCH/data/media/photos/ab/cd"
printf 'RIFF\x0c\x00\x00\x00WEBPVP8 ' > "$SCRATCH/data/media/photos/ab/cd/abcd0000000000000000000000000000000000000000000000000000000000ff.webp"
# Bodies for the size limits: /graphql takes 64 KiB, /upload 10304 KiB.
head -c 2000000 /dev/zero > "$SCRATCH/body-2mb"
head -c 60000 /dev/zero > "$SCRATCH/body-60kb"
head -c 70000 /dev/zero > "$SCRATCH/body-70kb"
head -c 11000000 /dev/zero > "$SCRATCH/body-11mb"

sed -e 's|admin unix//run/caddy/admin.sock|admin off|' \
    -e 's|acme_ca .*|auto_https off|' \
    -e 's|__SSLIP_HOST__ {|http://sslip.test:8080 {|' \
    -e 's|__SSLIP_HOST__|sslip.test|g' \
    -e 's|import /etc/caddy/sites-enabled/\*.caddy|import /w/lunaway.net.caddy|' \
    -e 's|/srv/data|/w/data|g' \
    -e 's|/srv/tiles|/w/tiles|g' \
    -e 's|127.0.0.1:8485|lunaway-pmtiles-test:8485|g' \
    -e 's|output file /var/log/caddy/access.log|output file /tmp/access.log|' \
    "$INFRA/caddy/Caddyfile" > "$SCRATCH/Caddyfile"
# A stand-in for the API on its port: it reads the whole body (the
# placeholder does), so the body limits in front of it act as they do in
# production, and it names itself in a header.
cat >> "$SCRATCH/Caddyfile" <<'EOF'

http://:8484 {
	header X-Test-Upstream api
	respond "{http.request.body}" 200
}
EOF
sed -e 's|^api.lunaway.net {|http://api.lunaway.net:8080 {|' \
    -e 's|^lunaway.net {|http://lunaway.net:8080 {|' \
    -e 's|^www.lunaway.net {|http://www.lunaway.net:8080 {|' \
    -e 's|^tiles.lunaway.net {|http://tiles.lunaway.net:8080 {|' \
    -e 's|/srv/lunaway/site|/w/site|; s|/srv/lunaway/web|/w/web|' \
    "$INFRA/caddy/lunaway.net.caddy" > "$SCRATCH/lunaway.net.caddy"

docker rm -f lunaway-caddy-test lunaway-pmtiles-test >/dev/null 2>&1 || true
docker network rm "$NETWORK" >/dev/null 2>&1 || true
docker network create "$NETWORK" >/dev/null
# The TileJSON as lunaway-tiles-refresh writes it.
# shellcheck disable=SC2016 # literal backticks, a Caddy template action
docker run --rm -v "$SCRATCH:/w:ro" "$CADDY_IMAGE" /w/bin/pmtiles show --tilejson \
  --public-url="__TILES_BASE__/planet-$BUILD" "/w/tiles/serve/planet-$BUILD.pmtiles" \
  | sed 's|__TILES_BASE__|{{placeholder `http.vars.tiles_base`}}|g' > "$SCRATCH/tiles/tilejson/planet.json"
docker run -d --name lunaway-pmtiles-test --network "$NETWORK" -v "$SCRATCH:/w:ro" "$CADDY_IMAGE" \
  /w/bin/pmtiles serve /w/tiles/serve --interface=0.0.0.0 --port=8485 >/dev/null
docker run -d --name lunaway-caddy-test --network "$NETWORK" -p "127.0.0.1:$PORT:8080" -v "$SCRATCH:/w:ro" "$CADDY_IMAGE" \
  caddy run --config /w/Caddyfile --adapter caddyfile >/dev/null
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
check "/app/ connect-src" http://lunaway.net:8080/app/ 200 "connect-src 'self' https://api.lunaway.net https://tiles.lunaway.net https://tiles.openfreemap.org"
check "/app deep link" http://lunaway.net:8080/app/place/42/reviews 200 "wasm-unsafe-eval"
check "/app asset" http://lunaway.net:8080/app/main.dart.js 200 "content-type: text/javascript"
check "/app nested asset" http://lunaway.net:8080/app/assets/AssetManifest.json 200 "content-type: application/json"
check "media file" http://api.lunaway.net:8080/media/ab/0123abcd.jpg 200 "cache-control: public, max-age=31536000, immutable"
check "media sandbox" http://api.lunaway.net:8080/media/ab/0123abcd.jpg 200 "content-security-policy: default-src 'none'; frame-ancestors 'none'; sandbox"
check "media miss" http://api.lunaway.net:8080/media/ab/ffffffff.jpg 404
# A directory is not a file: a plain 404, never a listing.
check "media directory not listed" http://api.lunaway.net:8080/media/ab/ 404
check "no media on the site" http://lunaway.net:8080/media/ab/0123abcd.jpg 404
check "media on the sslip host" http://sslip.test:8080/media/ab/0123abcd.jpg 200 "immutable"
check "headers" http://lunaway.net:8080/ 200 "strict-transport-security: max-age=31536000; includeSubDomains"
check "no server header" http://lunaway.net:8080/ 200 "^x-frame-options: DENY"
check "www redirect" http://www.lunaway.net:8080/privacy 301 "location: https://lunaway.net/privacy"
check "api other path" http://api.lunaway.net:8080/admin 404 "content-security-policy: default-src 'none'"
check "api health proxied" http://api.lunaway.net:8080/health 200 "x-test-upstream: api"
check "sslip api other path" http://sslip.test:8080/ 404

# The basemap. T is the tiles host, S the sslip.io host's /tiles/ prefix.
T=http://tiles.lunaway.net:8080
S=http://sslip.test:8080/tiles
check "tilejson" "$T/planet.json" 200 "cache-control: public, max-age=3600"
check "tilejson cors" "$T/planet.json" 200 "access-control-allow-origin: \\*"
check "tilejson on sslip" "$S/planet.json" 200 "cache-control: public, max-age=3600"
check "build tile" "$T/planet-$BUILD/0/0/0.mvt" 200 "cache-control: public, max-age=31536000, immutable"
check "build tile type" "$T/planet-$BUILD/0/0/0.mvt" 200 "content-type: application/x-protobuf"
check "build tile cors" "$T/planet-$BUILD/0/0/0.mvt" 200 "access-control-allow-origin: \\*"
# The body depends on Accept-Encoding (below): a shared cache must know.
check "build tile vary" "$T/planet-$BUILD/0/0/0.mvt" 200 "vary: accept-encoding"
check "build tile on sslip" "$S/planet-$BUILD/0/0/0.mvt" 200 "immutable"
check "zoom beyond the build" "$T/planet-$BUILD/1/0/0.mvt" 404 "immutable"
check "unknown build" "$T/planet-20000101/0/0/0.mvt" 404
check "current tile" "$T/planet/0/0/0.mvt" 200 "cache-control: public, max-age=86400"
check "not a tile path" "$T/planet-$BUILD/0/0/0.png" 404
check "font" "$T/fonts/Noto%20Sans%20Regular/0-255.pbf" 200 "content-type: application/x-protobuf"
check "font cache" "$T/fonts/Noto%20Sans%20Regular/0-255.pbf" 200 "cache-control: public, max-age=604800"
check "font miss" "$T/fonts/Noto%20Sans%20Regular/65280-65535.pbf" 404
check "sprite" "$T/sprites/protomaps-v4/light.json" 200 "cache-control: public, max-age=86400"
check "style" "$T/styles/test.json" 200 "cache-control: public, max-age=3600"
check "pack" "$T/packs/test.pmtiles" 200 "accept-ranges: bytes"
check "packs not listed" "$T/packs/" 404
check "tiles host csp" "$T/planet.json" 200 "content-security-policy: default-src 'none'.*sandbox"
check "tiles host other path" "$T/admin" 404
check "sslip tiles other path" "$S/admin" 404
check "sslip health still proxied" http://sslip.test:8080/health 200 "x-test-upstream: api"

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
sent "upload on the sslip host" POST http://sslip.test:8080/upload 200 -F placeId=x -F file=@"$SCRATCH/body-2mb"
sent "upload preflight routed" OPTIONS "$A/upload" 200 -H 'Origin: https://lunaway.net' -H 'Access-Control-Request-Method: POST'
sent "upload of 11 MB" POST "$A/upload" 413 --data-binary @"$SCRATCH/body-11mb" -H 'Content-Type: multipart/form-data; boundary=x'
sent "upload by GET" GET "$A/upload" 405
sent "graphql body of 2 MB" POST "$A/graphql" 413 --data-binary @"$SCRATCH/body-2mb" -H 'Content-Type: application/json'
sent "graphql body of 60 KB" POST "$A/graphql" 200 --data-binary @"$SCRATCH/body-60kb" -H 'Content-Type: application/json'
sent "graphql body of 70 KB" POST "$A/graphql" 413 --data-binary @"$SCRATCH/body-70kb" -H 'Content-Type: application/json'
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
fetch tilejson-sslip "$S/planet.json"
body tilejson-sslip "json.loads(b)['tiles'] == ['https://sslip.test/tiles/planet-$BUILD/{z}/{x}/{y}.mvt']"
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
fetch pack-range "$T/packs/test.pmtiles" -r 0-6 -D "$SCRATCH/pack-headers.out"
body pack-range "b == b'PMTiles'"
if grep -q '^HTTP/1.1 206' "$SCRATCH/pack-headers.out" && grep -qi '^content-range: bytes 0-6/' "$SCRATCH/pack-headers.out"; then
  echo "ok   pack range: 206 with content-range"
else
  echo "FAIL pack range: $(head -n 1 "$SCRATCH/pack-headers.out")"
  failures=$((failures + 1))
fi
preflight="$(curl -sS -D - -o /dev/null --connect-to "tiles.lunaway.net:8080:127.0.0.1:$PORT" -X OPTIONS \
  -H 'Origin: https://example.org' -H 'Access-Control-Request-Method: GET' -H 'Access-Control-Request-Headers: range' \
  "$T/packs/test.pmtiles")"
if grep -q '^HTTP/1.1 204' <<<"$preflight" && grep -qi '^access-control-allow-headers:.*Range' <<<"$preflight"; then
  echo "ok   preflight for a range request: 204, Range allowed"
else
  echo "FAIL preflight for a range request: $(head -n 1 <<<"$preflight")"
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
default_log="$(docker logs lunaway-caddy-test 2>&1 | grep '"logger":"http.log.access"' | grep '"host":"nobody.test:8080"' || true)"
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
if docker logs lunaway-caddy-test 2>&1 | grep -q 'lat45.7629'; then
  echo "FAIL a query string reached the log"
  failures=$((failures + 1))
else
  echo "ok   query strings are stripped from the log"
fi

# Nothing that names a tile reaches the access log: its coordinates, a byte
# range of a pack and the range it answers, the tile's ETag, its size.
curl -sS -o /dev/null --connect-to "tiles.lunaway.net:8080:127.0.0.1:$PORT" "$T/planet-$BUILD/14/8345/5678.mvt"
curl -sS -o /dev/null --connect-to "tiles.lunaway.net:8080:127.0.0.1:$PORT" -r 123-234 "$T/packs/test.pmtiles"
etag="$(grep -i '^etag:' "$SCRATCH/tile-headers.out" | sed -E 's/^[Ee][Tt][Aa][Gg]: *"?([^"]*)"?.*/\1/' | tr -d '\r')"
curl -sS -o /dev/null --connect-to "tiles.lunaway.net:8080:127.0.0.1:$PORT" -H "If-None-Match: \"$etag\"" "$T/planet-$BUILD/0/0/0.mvt"
sleep 1
access_log="$(docker exec lunaway-caddy-test cat /tmp/access.log)"
leaks=""
grep -qE '8345|5678' <<<"$access_log" && leaks="$leaks coordinates"
grep -qE '123-234|bytes 123' <<<"$access_log" && leaks="$leaks range"
[ -n "$etag" ] && grep -qF "$etag" <<<"$access_log" && leaks="$leaks etag"
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
  echo "ok   the access log keeps the zoom only (/planet-$BUILD/14/x/y.mvt): no range, ETag or size"
else
  echo "FAIL no masked tile line in the access log, or no ETag to look for"
  failures=$((failures + 1))
fi

docker rm -f lunaway-caddy-test lunaway-pmtiles-test >/dev/null
docker network rm "$NETWORK" >/dev/null
echo "$failures failure(s)"
[ "$failures" = 0 ]
