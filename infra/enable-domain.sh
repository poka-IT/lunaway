#!/usr/bin/env bash
# Turns on the lunaway.net sites (api.lunaway.net, lunaway.net,
# www.lunaway.net, tiles.lunaway.net) once their DNS records point at the
# server, then waits for the certificates and checks each name over HTTPS.
#
#   infra/enable-domain.sh              check DNS from two resolvers, enable, verify
#   infra/enable-domain.sh --disable    unlink the sites again
#
# Enabling before the records resolve here would only collect failed Let's
# Encrypt validations, which are rate limited; so the DNS check comes first.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
require_host
names="lunaway.net api.lunaway.net www.lunaway.net tiles.lunaway.net"
site=/etc/caddy/sites-available/lunaway.net.caddy
link=/etc/caddy/sites-enabled/lunaway.net.caddy

reload_caddy() {
  lunaway_ssh "sudo runuser -u caddy -- env HOME=/var/lib/caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 && sudo systemctl reload caddy"
}

if [ "${1:-}" = "--disable" ]; then
  lunaway_ssh "sudo rm -f /etc/caddy/sites-enabled/lunaway.net.caddy"
  reload_caddy
  log "lunaway.net sites disabled"
  exit 0
fi

command -v dig >/dev/null || die "dig is needed"
log "DNS, seen from two public resolvers"
bad=0
for name in $names; do
  for resolver in 1.1.1.1 8.8.8.8; do
    a="$(dig +short A "$name" "@$resolver" | grep -E '^[0-9.]+$' | sort -u | tr '\n' ' ' | sed 's/ $//')"
    aaaa="$(dig +short AAAA "$name" "@$resolver" | grep ':' | sort -u | tr '\n' ' ' | sed 's/ $//')"
    status=ok
    [ "$a" = "$LUNAWAY_BACKEND_IPV4" ] || status="A is '$a', expected $LUNAWAY_BACKEND_IPV4"
    if [ -n "$aaaa" ] && [ "$aaaa" != "$LUNAWAY_BACKEND_IPV6" ]; then
      status="AAAA is '$aaaa', expected $LUNAWAY_BACKEND_IPV6"
    fi
    echo "    $name @$resolver: A $a, AAAA ${aaaa:-none}: $status"
    [ "$status" = ok ] || bad=1
  done
done
caa="$(dig +short CAA lunaway.net @1.1.1.1)"
if [ -n "$caa" ] && ! grep -q 'issue "letsencrypt.org' <<<"$caa"; then
  echo "    CAA of lunaway.net does not allow Let's Encrypt: $caa"
  bad=1
fi
echo "    CAA: ${caa:-none}"
[ "$bad" = 0 ] || die "DNS does not point here yet; nothing changed"

log "enabling the sites"
lunaway_ssh "sudo ln -sfn $site $link"
reload_caddy || die "Caddy rejected the configuration"

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
log "issuer of api.lunaway.net: $(echo | openssl s_client -connect api.lunaway.net:443 -servername api.lunaway.net 2>/dev/null | openssl x509 -noout -issuer)"
