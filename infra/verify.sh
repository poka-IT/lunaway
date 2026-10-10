#!/usr/bin/env bash
# Checks the servers from outside (ports, SSH policy, TLS, the API, the
# basemap, the status page, the Mac's pull) and from inside (firewall,
# fail2ban, sandbox scores, PostgreSQL, backups, the pipeline, the tile
# server and its refresh, Gatus, the replica, what the ops server's keys
# reach on the backend). Changes nothing. Prints each check
# with its evidence.
#
#   infra/verify.sh               both servers
#   infra/verify.sh backend|ops   one
#
# Port scans are connect scans from this machine's own network stack, on the
# low ports and the services' own. No SYN scan from a container: colima's NAT
# does not carry raw probes back and reports open ports as filtered. No sweep
# of all 65535 ports: every dropped probe costs a timeout, and from a home
# line it did not end within 15 minutes. That nothing else answers is shown
# from the inside instead: the listening sockets, the nftables default drop
# and the Hetzner rules printed below.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
require_hcloud
roles="${1:-backend ops}"
ports="1-1024,2019,3900-3904,5432,8002,8080,8443,8484,8485,9000,9090"
section() { echo; echo "######## $*"; }
# refused LABEL COMMAND...: prints whether the command failed, as it should.
# No timeout(1) here, macOS has none (with it, a missing command passed for a
# refusal); the commands carry their own connection timeouts.
refused() {
  local label="$1" out status=0
  shift
  out="$("$@" </dev/null 2>&1)" || status=$?
  if [ "$status" != 0 ]; then echo "ok   $label refused: $(echo "$out" | tail -n 1 | cut -c1-120)"
  else echo "FAIL $label was accepted: $(echo "$out" | tail -n 1 | cut -c1-120)"; fi
}

SCRATCH_VERIFY="${LUNAWAY_SCRATCH_DIR:-$LUNAWAY_REPO_DIR/data/tmp/infra}/verify"
mkdir -p "$SCRATCH_VERIFY"

# The weekly groups of European extracts hold every extract of the
# European import but France (daily), once each.
groups="$(sed -nE 's/^LUNAWAY_EXTRACTS_[A-Z][a-z]{2}=//p' "$LUNAWAY_INFRA_DIR/files/usr/local/share/lunaway/osm-extracts.env" | tr ' ' '\n' | grep -v '^--extract$' | grep . | sort)"
europe="$(sed -n '/^pub const EUROPE: &\[&str\] = &\[/,/^\];/p' "$LUNAWAY_REPO_DIR/backend/crates/lunaway-ingest/src/osm_extract.rs" | sed -nE 's/^ *"([a-z-]+)",$/\1/p' | grep -vx france | sort)"
if [ -n "$europe" ] && [ "$groups" = "$europe" ]; then
  echo "ok   the weekly groups hold the $(echo "$europe" | wc -l | tr -d ' ') European extracts but France, once each"
else
  echo "FAIL the weekly groups differ from osm_extract::EUROPE (without france):"
  diff <(echo "$europe") <(echo "$groups") | sed 's/^/       /'
fi

# Caddy is pinned and no longer updates itself (infra/caddy/version.sh): a
# newer release is for the maintainer to read and pin.
. "$LUNAWAY_INFRA_DIR/caddy/version.sh"
latest="$(curl -fsS -m 10 https://api.github.com/repos/caddyserver/caddy/releases/latest 2>/dev/null \
  | python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])' 2>/dev/null || echo unknown)"
if [ "$latest" = "v$CADDY_VERSION" ]; then
  echo "ok   Caddy $CADDY_VERSION pinned, the latest release"
else
  echo "note Caddy $CADDY_VERSION pinned, the latest release is $latest: docs/deploy.md, \"Upgrading Caddy\""
fi

for role in $roles; do
  require_host "$role"
  ip4="$(role_var "$role" IPV4)"
  ip6="$(role_var "$role" IPV6)"
  server="$(role_get "$role" server)"

  section "$server, outside: ports $ports"
  if command -v nmap >/dev/null; then
    echo "IPv4:"
    nmap -Pn -sT -T4 -p "$ports" "$ip4" | grep -E '^[0-9]+/|Not shown|All [0-9]+'
    echo "IPv6:"
    nmap -6 -Pn -sT -T4 -p "$ports" "$ip6" | grep -E '^[0-9]+/|Not shown|All [0-9]+'
  else
    for port in 22 80 443 2019 5432 8080 8484 8485; do
      nc -z -G 3 "$ip4" "$port" 2>/dev/null && echo "$port open" || echo "$port closed or filtered"
    done
  fi
  echo "Hetzner firewall $(role_get "$role" firewall):"
  hcloud firewall describe "$(role_get "$role" firewall)" -o json | python3 -c '
import json, sys
for r in json.load(sys.stdin)["rules"]:
    print("  ", r["direction"], r["protocol"], r.get("port") or "-", "from", ",".join(r["source_ips"]))'

  section "$server, outside: SSH policy"
  echo "root login: $(ssh -F /dev/null -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o IdentitiesOnly=yes -i "$LUNAWAY_SSH_IDENTITY" -o ConnectTimeout=10 "root@$ip4" true 2>&1 | tail -n 1)"
  echo "password login: $(ssh -F /dev/null -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive \
    -o ConnectTimeout=10 "$LUNAWAY_ADMIN_USER@$ip4" true 2>&1 | tail -n 1)"
  echo "methods offered: $(ssh -F /dev/null -v -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o PubkeyAuthentication=no -o ConnectTimeout=10 "nobody@$ip4" true 2>&1 | grep -m1 'Authentications that can continue')"
  echo "negotiated with the admin key:"
  host_ssh "$role" -v true 2>&1 | grep -E 'kex: algorithm|kex: host key algorithm|cipher:' | head -n 3
  if command -v uvx >/dev/null; then
    echo "ssh-audit:"
    uvx --quiet ssh-audit --no-colors "$ip4" 2>/dev/null | grep -E '^\(gen\) software|\[fail\]|\[warn\]|^\(fin\)' | head -n 20
  fi

  # The provisional a-b-c-d.sslip.io name of each server was retired on
  # 2026-10-07: Caddy holds no site for it, so TLS fails.
  retired="$(echo "$ip4" | tr . -).sslip.io"
  refused "HTTPS for the retired name $retired" curl -fsS -o /dev/null -m 10 --resolve "$retired:443:$ip4" "https://$retired/"

  if [ "$role" = backend ]; then
    # The public names (LUNAWAY_API_HOST, LUNAWAY_TILES_URL, infra/lib.sh).
    host="$LUNAWAY_API_HOST"
    section "$server, outside: HTTPS"
    curl -sS -o /dev/null -D - -m 10 "https://$host/health" | grep -iE '^(HTTP|strict-transport|content-security|x-content-type|x-frame|referrer-policy|alt-svc|server)'
    echo "http redirect: $(curl -sS -o /dev/null -w '%{http_code} -> %{redirect_url}' -m 10 "http://$host/health")"
    echo "/health over IPv4: $(curl -4 -sS -m 10 "https://$host/health")"
    echo "/health over IPv6: $(curl -6 -sS -m 10 --resolve "$host:443:[$ip6]" "https://$host/health" || echo unreachable)"
    echo "GraphQL apiVersion: $(curl -sS -m 10 -H 'Content-Type: application/json' -d '{"query":"{ apiVersion }"}' "https://$host/graphql")"
    echo "CORS for https://lunaway.net: $(curl -sS -o /dev/null -D - -m 10 -X OPTIONS -H 'Origin: https://lunaway.net' \
      -H 'Access-Control-Request-Method: POST' "https://$host/graphql" | grep -i '^access-control-allow-origin' | tr -d '\r' || echo none)"
    echo "CORS for another origin: $(curl -sS -o /dev/null -D - -m 10 -X OPTIONS -H 'Origin: https://example.org' \
      -H 'Access-Control-Request-Method: POST' "https://$host/graphql" | grep -i '^access-control-allow-origin' | tr -d '\r' || echo none)"
    echo "other path: $(curl -sS -o /dev/null -w '%{http_code}' -m 10 "https://$host/admin")"
    echo "media miss: $(curl -sS -o /dev/null -w '%{http_code}' -m 10 "https://$host/media/none.jpg")"
    echo "body over 1 MB: $(head -c 2000000 /dev/zero | curl -sS -o /dev/null -w '%{http_code}' -m 20 -H 'Content-Type: application/json' --data-binary @- "https://$host/graphql")"
    # Photo uploads: routed to the API, which asks for a session; 10 MiB of
    # image at most; POST only. The full path (sign-in, upload, a WebP without
    # metadata) is infra/tests/api-flow.py, which creates and deletes an account.
    echo "upload without a session: $(head -c 1000 /dev/zero | curl -sS -o /dev/null -w '%{http_code}' -m 20 -F placeId=00000000-0000-0000-0000-000000000000 -F file=@- "https://$host/upload")"
    echo "upload body over 10 MiB: $(head -c 11000000 /dev/zero | curl -sS -o /dev/null -w '%{http_code}' -m 60 -H 'Content-Type: multipart/form-data; boundary=x' --data-binary @- "https://$host/upload")"
    echo "upload by GET: $(curl -sS -o /dev/null -w '%{http_code}' -m 10 "https://$host/upload")"
    echo "certificate: $(echo | openssl s_client -connect "$ip4:443" -servername "$host" 2>/dev/null | openssl x509 -noout -issuer -enddate | tr '\n' ' ')"
    # The versions and suites the server offers, measured by nmap (a local
    # openssl may refuse an old version on its own side, which proves nothing).
    if command -v nmap >/dev/null; then
      echo "TLS offered:"
      nmap -Pn -p 443 --script ssl-enum-ciphers --script-args "tls.servername=$host" "$ip4" \
        | grep -E 'TLSv1\.[0-3]:|least strength' | sed 's/^|[ _]*/  /'
    fi
    if docker info >/dev/null 2>&1; then
      # Debian 13's curl speaks HTTP/3 (ngtcp2); the macOS one does not.
      echo "HTTP/3: $(docker run --rm buildpack-deps:trixie-curl curl -sS -o /dev/null -w '%{http_version} %{http_code}' --http3-only -m 10 "https://$host/health" 2>&1 | tail -n 1)"
    fi
    # The basemap: TileJSON, tiles at z0, z8 and z14 over Paris and over
    # Tokyo, with their status, size as sent (gzip), encoding, cache and time.
    tiles="$LUNAWAY_TILES_URL"
    echo "basemap TileJSON: $(curl -fsS -m 10 "$tiles/planet.json" | python3 -c '
import json, sys
t = json.load(sys.stdin)
print(t["tiles"][0], "zoom %s-%s" % (t["minzoom"], t["maxzoom"]), "schema", t.get("version"))' 2>&1)"
    for tile in 0/0/0 8/129/88 14/8299/5636 8/227/100 14/14552/6451; do
      echo "basemap tile $tile: $(curl -sS -o /dev/null -D - -w 'status %{http_code}, %{size_download} bytes, %{time_total}s' \
        -H 'Accept-Encoding: gzip' -m 10 "$tiles/planet/$tile.mvt" | tr -d '\r' \
        | grep -iE '^(content-encoding|cache-control):|^status' | tr '\n' ' ')"
    done
    echo "basemap CORS: $(curl -sS -o /dev/null -D - -m 10 -H 'Origin: https://example.org' "$tiles/planet.json" | grep -i '^access-control-allow-origin' | tr -d '\r' || echo none)"
    echo "basemap glyphs: $(curl -sS -o /dev/null -w '%{http_code} %{content_type}' -m 10 "$tiles/fonts/Noto%20Sans%20Regular/0-255.pbf")"
    echo "basemap sprite: $(curl -sS -o /dev/null -w '%{http_code} %{content_type}' -m 10 "$tiles/sprites/protomaps-v4/light.json")"
    for asset in styles/aube-fr.json styles/minuit-en.json sprites/lunaway-pins/pins.json sprites/lunaway-pins/pins@2x.png; do
      echo "basemap $asset: $(curl -sS -o /dev/null -D - -w 'status %{http_code}, %{content_type}' -m 10 "$tiles/$asset" | tr -d '\r' | grep -i '^cache-control:\|^status' | tr '\n' ' ')"
    done
    echo "basemap other path: $(curl -sS -o /dev/null -w '%{http_code}' -m 10 "$tiles/admin")"
    # The points of interest (docs/deploy.md, "Points of interest"): the
    # TileJSON, a z13 tile over Annecy at the current version (immutable) and
    # at an old one (current data, 5 minutes), the web app's CORS, a write
    # refused.
    poi_tiles="$(curl -sS -m 10 "https://$host/poi/tiles.json" | python3 -c 'import json, sys; print(json.load(sys.stdin)["tiles"][0])' 2>&1)"
    echo "poi TileJSON: $poi_tiles"
    poi_version="$(echo "$poi_tiles" | sed -nE 's|.*/poi/([0-9]+)/\{z\}.*|\1|p')"
    echo "poi tile, current version $poi_version: $(curl -sS -o /dev/null -D - -m 10 -H 'Accept-Encoding: gzip' -H 'Origin: https://lunaway.net' \
      -w 'status %{http_code}, %{size_download} bytes gzip' "https://$host/poi/$poi_version/13/4235/2917.mvt" \
      | tr -d '\r' | grep -iE '^cache-control|^access-control-allow-origin|^status' | tr '\n' ' ')"
    echo "poi tile, old version: $(curl -sS -o /dev/null -D - -m 10 "https://$host/poi/1/13/4235/2917.mvt" | tr -d '\r' | grep -i '^cache-control')"
    echo "poi by POST: $(curl -sS -o /dev/null -w '%{http_code}' -m 10 -X POST "https://$host/poi/tiles.json")"
    # Road events (docs/deploy.md, "Road events"): each feed's last read and
    # freshness, and the size of the full set a phone loads at the start.
    echo "road event sources: $(curl -sS -m 10 -H 'Content-Type: application/json' \
      -d '{"query":"{ roadEventSources { id ageSeconds fresh } }"}' "https://$host/graphql" | python3 -c '
import json, sys
print(" ".join("%s %s%s" % (s["id"], "never read" if s["ageSeconds"] is None else "%ss" % s["ageSeconds"], "" if s["fresh"] else " STALE")
               for s in json.load(sys.stdin)["data"]["roadEventSources"]))' 2>&1)"
    echo "road events, full set: $(curl -sS -o /dev/null -m 30 -H 'Content-Type: application/json' -H 'Accept-Encoding: gzip' \
      -w 'status %{http_code}, %{size_download} bytes gzip, %{time_total} s' \
      -d '{"query":"{ roadEvents { cursor upserts { id lines } } }"}' "https://$host/graphql")"
    # Routing (docs/deploy.md, "Routing"): an active graph the engine serves,
    # and the witness route of the status page (a 3.3 m motorhome round the
    # 2.7 m bridge of Rue Maurice Utrillo, Limoges). One route of the quota.
    echo "routing: $(curl -sS -m 10 -H 'Content-Type: application/json' \
      -d '{"query":"{ routing { available graph { id ignEdition builtAt } } }"}' "https://$host/graphql")"
    echo "witness route: $(curl -sS -m 20 -H 'Content-Type: application/json' \
      -d '{"query":"{ route(input: {origin: {lat: 45.84719, lon: 1.28476}, destination: {lat: 45.8451, lon: 1.28637}, vehicle: {kind: OVERCAB, heightM: 3.3, widthM: 2.3, lengthM: 7.4, weightT: 3.5}}) { status recalculations routes { distanceM } } }"}' \
      "https://$host/graphql")"
    # Europe and the regional packs (docs/region-packs.md): the manifest,
    # one pack fetched whole and checked against it, the work directory
    # and the listing refused. The danger zones of France carry no point,
    # Switzerland gets nothing (docs/speed-cameras.md).
    echo "regional packs: $(curl -sS -m 20 -H 'Content-Type: application/json' \
      -d '{"query":"{ regions { code pack { url bytes sha256 places } } }"}' "https://$host/graphql" > "$SCRATCH_VERIFY/regions.json"; python3 -c '
import json, sys
r = json.load(open(sys.argv[1]))["data"]["regions"]
built = [x for x in r if x["pack"]]
print("%d regions, %d with a pack, %d places, %d bytes" % (len(r), len(built), sum(x["pack"]["places"] for x in built), sum(x["pack"]["bytes"] for x in built)))' "$SCRATCH_VERIFY/regions.json" 2>&1)"
    pack_url="$(python3 -c '
import json, sys
r = [x for x in json.load(open(sys.argv[1]))["data"]["regions"] if x["pack"]]
r.sort(key=lambda x: x["pack"]["bytes"])
print(r[0]["pack"]["url"], int(r[0]["pack"]["bytes"]), r[0]["pack"]["sha256"]) if r else print("")' "$SCRATCH_VERIFY/regions.json" 2>/dev/null)"
    if [ -n "$pack_url" ]; then
      read -r pack_href pack_bytes pack_sum <<<"$pack_url"
      curl -sS -m 60 -o "$SCRATCH_VERIFY/pack.sqlite.gz" -D "$SCRATCH_VERIFY/pack.headers" -H 'Accept-Encoding: gzip, zstd' "$pack_href"
      got_sum="$(shasum -a 256 "$SCRATCH_VERIFY/pack.sqlite.gz" | awk '{ print $1 }')"
      got_bytes="$(wc -c < "$SCRATCH_VERIFY/pack.sqlite.gz" | tr -d ' ')"
      if [ "$got_sum" = "$pack_sum" ] && [ "$got_bytes" = "$pack_bytes" ]; then
        echo "ok   smallest pack $(basename "$pack_href" | sed -E 's/-[0-9]+-[0-9a-f]{12}\.sqlite\.gz$//'): $got_bytes bytes, SHA-256 of the manifest, $(tr -d '\r' < "$SCRATCH_VERIFY/pack.headers" | grep -iE '^cache-control' | head -n 1)"
      else
        echo "FAIL smallest pack: $got_bytes bytes, SHA-256 $got_sum (manifest: $pack_bytes, $pack_sum)"
      fi
      echo "pack range: $(curl -sS -o /dev/null -m 20 -r 0-99 -w '%{http_code} %{size_download} bytes' "$pack_href")"
      echo "pack work directory: $(curl -sS -o /dev/null -w '%{http_code}' -m 10 "https://$host/packs/.work/")"
      echo "packs listing: $(curl -sS -o /dev/null -w '%{http_code}' -m 10 "https://$host/packs/places/")"
    else
      echo "FAIL no regional pack in the manifest"
    fi
    echo "danger zones, France: $(python3 - "https://$host/graphql" <<'PY' 2>&1
import json, sys, urllib.request
url, since, items, pages = sys.argv[1], None, [], 0
while True:
    body = {"query": "query($s: String) { enforcement(since: $s, countries: [\"FR\"], first: 2000) { cursor hasMore upserts { kind lat lon bearingDeg } } }", "variables": {"s": since}}
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    d = json.load(urllib.request.urlopen(req, timeout=30))["data"]["enforcement"]
    items += d["upserts"]
    pages += 1
    since = d["cursor"]
    if not d["hasMore"]:
        break
kinds = sorted({x["kind"] for x in items})
points = sum(1 for x in items if x["lat"] is not None or x["lon"] is not None or x["bearingDeg"] is not None)
print("%d items in %d pages, kinds %s, %d with a point or a heading" % (len(items), pages, ",".join(kinds), points))
if points or kinds != ["ZONE"]:
    print("FAIL a French item is not a zone or carries a point")
PY
)"
    echo "Switzerland: $(curl -sS -m 30 -H 'Content-Type: application/json' \
      -d '{"query":"{ enforcement(countries: [\"CH\"]) { upserts { id } } }"}' "https://$host/graphql" | python3 -c '
import json, sys
u = json.load(sys.stdin)["data"]["enforcement"]["upserts"]
print("%d items%s" % (len(u), "" if not u else ": FAIL"))' 2>&1)"
    refused "lunaway-pull over the public address (it is the ops server's, private network only)" \
      ssh -F /dev/null -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o IdentitiesOnly=yes -i "$LUNAWAY_SSH_IDENTITY" -o ConnectTimeout=10 "lunaway-pull@$ip4" true
  fi

  if [ "$role" = ops ]; then
    host="$LUNAWAY_STATUS_DOMAIN"
    section "$server, outside: status page and the Mac's pull"
    curl -sS -o /dev/null -D - -m 10 "https://$host/" | grep -iE '^(HTTP|strict-transport|content-security|x-content-type|x-frame|referrer-policy|alt-svc|server)'
    echo "status API: $(curl -fsS -m 10 "https://$host/api/v1/endpoints/statuses" | python3 -c '
import json, sys
print("; ".join("%s/%s %s" % (e["group"], e["name"], "ok" if (e.get("results") or [{}])[-1].get("success") else "FAIL") for e in json.load(sys.stdin)))')"
    echo "a write to the status page: $(curl -sS -o /dev/null -w '%{http_code}' -m 10 -X POST "https://$host/api/v1/endpoints/x/external?success=true")"
    echo "certificate: $(echo | openssl s_client -connect "$ip4:443" -servername "$host" 2>/dev/null | openssl x509 -noout -issuer -enddate | tr '\n' ' ')"
    if [ -f "$LUNAWAY_CONFIG_DIR/ops-pull_ed25519" ]; then
      echo "the Mac's pull, list: $(rsync -e "ssh -F $LUNAWAY_SSH_CONFIG" --list-only lunaway-ops-pull: 2>&1 | grep -c 'dump.age') encrypted dump(s) listed"
      refused "the Mac's pull key: a shell" ssh -F "$LUNAWAY_SSH_CONFIG" lunaway-ops-pull id
      refused "the Mac's pull key: a write" rsync -e "ssh -F $LUNAWAY_SSH_CONFIG" "$LUNAWAY_INFRA_DIR/lib.sh" lunaway-ops-pull:lib.sh
      refused "the Mac's pull key: a path outside the replica" rsync -e "ssh -F $LUNAWAY_SSH_CONFIG" lunaway-ops-pull:/etc/passwd /dev/null
    fi
  fi

  section "$server, inside"
  host_ssh "$role" 'mkdir -p ~/infra/server ~/infra/caddy'
  lunaway_scp "$LUNAWAY_INFRA_DIR/server/common.sh" "$LUNAWAY_INFRA_DIR/server/inspect.sh" \
    "$LUNAWAY_INFRA_DIR/server/test-fail2ban.sh" "$LUNAWAY_INFRA_DIR/server/test-ops-access.sh" \
    "$LUNAWAY_INFRA_DIR/server/test-grants.sh" "$(role_get "$role" alias):infra/server/"
  lunaway_scp "$LUNAWAY_INFRA_DIR/caddy/version.sh" "$(role_get "$role" alias):infra/caddy/"
  host_ssh "$role" "sudo bash ~/infra/server/inspect.sh $role"

  section "$server, inside: fail2ban end to end"
  host_ssh "$role" 'sudo bash ~/infra/server/test-fail2ban.sh'

  if [ "$role" = backend ]; then
    section "$server, inside: what the API and import roles may do in the database"
    host_ssh backend 'sudo bash ~/infra/server/test-grants.sh'
  fi

  if [ "$role" = ops ] && [ -n "$(role_var backend IPV4)" ]; then
    section "what the ops server's keys reach on the backend, over the private network"
    host_ssh ops "sudo bash ~/infra/server/test-ops-access.sh $LUNAWAY_BACKEND_PRIVATE_IP"
  fi
done
