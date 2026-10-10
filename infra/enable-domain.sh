#!/usr/bin/env bash
# Turns on the lunaway.net sites (api.lunaway.net, lunaway.net,
# www.lunaway.net, tiles.lunaway.net) once their DNS records point at the
# server, then the status page (status.lunaway.net) once its own records
# do, then waits for the certificates and checks each name over HTTPS.
#
#   infra/enable-domain.sh              check DNS from two resolvers, enable, verify
#   infra/enable-domain.sh --disable    unlink the sites again
#
# Enabling before the records resolve here would only collect failed Let's
# Encrypt validations, which are rate limited; so the DNS check comes first.
# The status page is checked apart: its name moved from another server on
# 2026-10-10, and a record not moved yet leaves it off without holding the
# other sites back.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
require_host
names="lunaway.net api.lunaway.net www.lunaway.net tiles.lunaway.net"
status_name="$LUNAWAY_STATUS_DOMAIN"
site=/etc/caddy/sites-available/lunaway.net.caddy
link=/etc/caddy/sites-enabled/lunaway.net.caddy
status_site=/etc/caddy/sites-available/status.caddy
status_link=/etc/caddy/sites-enabled/status.caddy

reload_caddy() {
  lunaway_ssh "sudo runuser -u caddy -- env HOME=/var/lib/caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 && sudo systemctl reload caddy"
}

if [ "${1:-}" = "--disable" ]; then
  lunaway_ssh "sudo rm -f $link $status_link"
  reload_caddy
  log "lunaway.net sites disabled"
  exit 0
fi

# points_here NAME: its A record (and AAAA, when there is one) name this
# server, from both resolvers; prints what each says.
points_here() {
  local name="$1" resolver a aaaa status ok=0
  for resolver in 1.1.1.1 8.8.8.8; do
    a="$(dig +short A "$name" "@$resolver" | grep -E '^[0-9.]+$' | sort -u | tr '\n' ' ' | sed 's/ $//')"
    aaaa="$(dig +short AAAA "$name" "@$resolver" | grep ':' | sort -u | tr '\n' ' ' | sed 's/ $//')"
    status=ok
    [ "$a" = "$LUNAWAY_BACKEND_IPV4" ] || status="A is '$a', expected $LUNAWAY_BACKEND_IPV4"
    if [ -n "$aaaa" ] && [ "$aaaa" != "$LUNAWAY_BACKEND_IPV6" ]; then
      status="AAAA is '$aaaa', expected $LUNAWAY_BACKEND_IPV6"
    fi
    echo "    $name @$resolver: A $a, AAAA ${aaaa:-none}: $status"
    [ "$status" = ok ] || ok=1
  done
  return "$ok"
}

command -v dig >/dev/null || die "dig is needed"
log "DNS, seen from two public resolvers"
bad=0
for name in $names; do
  points_here "$name" || bad=1
done
caa="$(dig +short CAA lunaway.net @1.1.1.1)"
if [ -n "$caa" ] && ! grep -q 'issue "letsencrypt.org' <<<"$caa"; then
  echo "    CAA of lunaway.net does not allow Let's Encrypt: $caa"
  bad=1
fi
echo "    CAA: ${caa:-none}"
[ "$bad" = 0 ] || die "DNS does not point here yet; nothing changed"
status_here=0
points_here "$status_name" && status_here=1

log "enabling the sites"
lunaway_ssh "sudo ln -sfn $site $link"
if [ "$status_here" = 1 ]; then
  lunaway_ssh "sudo ln -sfn $status_site $status_link"
else
  lunaway_ssh "sudo rm -f $status_link"
  echo "    $status_name does not point here yet: its site stays off"
fi
reload_caddy || die "Caddy rejected the configuration"
[ "$status_here" = 1 ] && names="$names $status_name"

log "waiting for certificates"
for name in $names; do
  for _ in $(seq 1 36); do
    curl -fsS -o /dev/null -m 10 "https://$name/" 2>/dev/null && break
    code="$(curl -sS -o /dev/null -w '%{http_code}' -m 10 "https://$name/" 2>/dev/null || true)"
    [ "$code" = 404 ] || [ "$code" = 301 ] || [ "$code" = 308 ] && break
    sleep 5
  done
done
echo "    api.lunaway.net/health: $(curl -fsS -m 10 https://api.lunaway.net/health || echo FAILED)"
echo "    api.lunaway.net apiVersion: $(curl -fsS -m 10 -H 'Content-Type: application/json' -d '{"query":"{ apiVersion }"}' https://api.lunaway.net/graphql || echo FAILED)"
echo "    lunaway.net: $(curl -sS -o /dev/null -w '%{http_code}' -m 10 https://lunaway.net/)"
echo "    www.lunaway.net: $(curl -sS -o /dev/null -w '%{http_code} -> %{redirect_url}' -m 10 https://www.lunaway.net/somewhere)"
echo "    tiles.lunaway.net TileJSON: $(curl -fsS -m 10 https://tiles.lunaway.net/planet.json | python3 -c 'import json,sys; print(json.load(sys.stdin)["tiles"][0])' 2>/dev/null || echo FAILED)"
echo "    tiles.lunaway.net tile z0: $(curl -sS -o /dev/null -w '%{http_code} %{size_download} bytes' -m 10 https://tiles.lunaway.net/planet/0/0/0.mvt)"
if [ "$status_here" = 1 ]; then
  echo "    $status_name checks: $(curl -fsS -m 10 "https://$status_name/api/v1/endpoints/statuses" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo FAILED)"
fi
log "issuer of api.lunaway.net: $(echo | openssl s_client -connect api.lunaway.net:443 -servername api.lunaway.net 2>/dev/null | openssl x509 -noout -issuer)"
