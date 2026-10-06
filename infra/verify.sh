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

  if [ "$role" = backend ]; then
    host="$LUNAWAY_HOSTNAME"
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
    # The basemap under /tiles/ (tiles.lunaway.net serves the same once DNS
    # exists): TileJSON, tiles at z0, z8 and z14 over Paris and over Tokyo,
    # with their status, size as sent (gzip), encoding, cache and time.
    tiles="https://$host/tiles"
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
    echo "basemap other path: $(curl -sS -o /dev/null -w '%{http_code}' -m 10 "$tiles/admin")"
    refused "lunaway-pull over the public address (it is the ops server's, private network only)" \
      ssh -F /dev/null -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o IdentitiesOnly=yes -i "$LUNAWAY_SSH_IDENTITY" -o ConnectTimeout=10 "lunaway-pull@$ip4" true
  fi

  if [ "$role" = ops ]; then
    host="$(echo "$ip4" | tr . -).sslip.io"
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
  host_ssh "$role" 'mkdir -p ~/infra/server'
  lunaway_scp "$LUNAWAY_INFRA_DIR/server/common.sh" "$LUNAWAY_INFRA_DIR/server/inspect.sh" \
    "$LUNAWAY_INFRA_DIR/server/test-fail2ban.sh" "$LUNAWAY_INFRA_DIR/server/test-ops-access.sh" \
    "$LUNAWAY_INFRA_DIR/server/test-grants.sh" "$(role_get "$role" alias):infra/server/"
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
