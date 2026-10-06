#!/usr/bin/env bash
# Checks the routing of infra/caddy/ (the sslip.io API host and the
# lunaway.net sites) in the official Caddy image, before the domain is
# enabled. The configuration is the real one, rewritten for a test: plain
# HTTP on port 8080, no admin API, test roots under the scratch directory,
# which is the container's only mount (read-only).
#
#   infra/tests/caddy-layout.sh
set -euo pipefail
INFRA="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$INFRA/.." && pwd)"
SCRATCH="${LUNAWAY_SCRATCH_DIR:-$REPO/data/tmp/infra}/caddy-test"
CADDY_IMAGE="${LUNAWAY_CADDY_IMAGE:-caddy:2.11}"
PORT=18080

docker info >/dev/null 2>&1 || { echo "docker does not answer" >&2; exit 1; }
mkdir -p "$SCRATCH/site/account" "$SCRATCH/site/about" "$SCRATCH/web/assets" "$SCRATCH/data/media/ab"

# Test content, overwritten on each run.
cp "$INFRA/web/site/index.html" "$INFRA/web/site/style.css" "$SCRATCH/site/"
echo '<!doctype html><title>privacy</title>' > "$SCRATCH/site/privacy.html"
echo '<!doctype html><title>delete</title>' > "$SCRATCH/site/account/delete.html"
echo '<!doctype html><title>about</title>' > "$SCRATCH/site/about/index.html"
echo 'body{}' > "$SCRATCH/site/style.0123abcd.css"
echo '<!doctype html><base href="/app/"><title>app</title>' > "$SCRATCH/web/index.html"
echo 'console.log(1)' > "$SCRATCH/web/main.dart.js"
echo '{}' > "$SCRATCH/web/assets/AssetManifest.json"
printf 'JPEG' > "$SCRATCH/data/media/ab/0123abcd.jpg"

sed -e 's|admin unix//run/caddy/admin.sock|admin off|' \
    -e 's|acme_ca .*|auto_https off|' \
    -e 's|__SSLIP_HOST__ {|http://sslip.test:8080 {|' \
    -e 's|import /etc/caddy/sites-enabled/\*.caddy|import /w/lunaway.net.caddy|' \
    -e 's|/srv/data|/w/data|g' \
    -e 's|output file /var/log/caddy/access.log|output file /tmp/access.log|' \
    "$INFRA/caddy/Caddyfile" > "$SCRATCH/Caddyfile"
sed -e 's|^api.lunaway.net {|http://api.lunaway.net:8080 {|' \
    -e 's|^lunaway.net {|http://lunaway.net:8080 {|' \
    -e 's|^www.lunaway.net {|http://www.lunaway.net:8080 {|' \
    -e 's|/srv/lunaway/site|/w/site|; s|/srv/lunaway/web|/w/web|' \
    "$INFRA/caddy/lunaway.net.caddy" > "$SCRATCH/lunaway.net.caddy"

docker rm -f lunaway-caddy-test >/dev/null 2>&1 || true
docker run -d --name lunaway-caddy-test -p "127.0.0.1:$PORT:8080" -v "$SCRATCH:/w:ro" "$CADDY_IMAGE" \
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

check "landing" http://lunaway.net:8080/ 200 "content-security-policy: default-src 'none'; style-src 'self'"
check "landing html cache" http://lunaway.net:8080/ 200 "cache-control: public, max-age=300"
check "landing css" http://lunaway.net:8080/style.css 200 "cache-control: public, max-age=300"
check "hashed asset cache" http://lunaway.net:8080/style.0123abcd.css 200 "cache-control: public, max-age=31536000, immutable"
check "/privacy" http://lunaway.net:8080/privacy 200
check "/account/delete" http://lunaway.net:8080/account/delete 200
check "/about" http://lunaway.net:8080/about 200
check "unknown page" http://lunaway.net:8080/nope 404
check "/app redirect" http://lunaway.net:8080/app 301 "location: /app/"
check "/app/" http://lunaway.net:8080/app/ 200 "wasm-unsafe-eval"
check "/app/ cache" http://lunaway.net:8080/app/ 200 "cache-control: no-cache"
check "/app/ connect-src" http://lunaway.net:8080/app/ 200 "connect-src 'self' https://api.lunaway.net https://tiles.openfreemap.org"
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
check "api health proxied" http://api.lunaway.net:8080/health 502
check "sslip api other path" http://sslip.test:8080/ 404

if curl -sS -D - -o /dev/null --connect-to "lunaway.net:8080:127.0.0.1:$PORT" http://lunaway.net:8080/ | grep -qi '^server:'; then
  echo "FAIL a Server header is sent"
  failures=$((failures + 1))
fi
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

docker rm -f lunaway-caddy-test >/dev/null
echo "$failures failure(s)"
[ "$failures" = 0 ]
