#!/usr/bin/env bash
# The status page, run as root by setup.sh on the backend: Gatus (user,
# configuration, sandboxed unit; the binary comes from infra/deploy-gatus.sh)
# and its probe key, which the ops-access step lets into lunaway-pull on the
# loopback. Caddy serves the page as status.lunaway.net
# (infra/caddy/status.caddy, enabled by infra/enable-domain.sh once the name
# points here).
#
#   LUNAWAY_API_HOST            the API's public name (api.lunaway.net)
#   LUNAWAY_WEB_URL             the web app's address, empty while not served
#   LUNAWAY_TILES_URL           the basemap's public base URL
#                               (https://tiles.lunaway.net)
. "$(dirname "$0")/common.sh"
need_root
api_host="${LUNAWAY_API_HOST:?set LUNAWAY_API_HOST}"
web_url="${LUNAWAY_WEB_URL:-}"
tiles_url="${LUNAWAY_TILES_URL:?set LUNAWAY_TILES_URL}"
[[ "$api_host" =~ ^[a-z0-9.-]+$ ]] || die "unexpected API host $api_host"
[ -z "$web_url" ] || [[ "$web_url" =~ ^https://[a-z0-9.-]+(/[A-Za-z0-9/._-]*)?$ ]] || die "unexpected web app URL $web_url"
[[ "$tiles_url" =~ ^https://[a-z0-9.-]+\.[a-z]+(/[a-z0-9_-]+)*$ ]] || die "unexpected basemap URL $tiles_url"

log "Gatus account and probe key"
if ! getent passwd gatus >/dev/null; then
  useradd --system --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin \
    --comment "Gatus status page" --user-group gatus
fi
install -d -m 0755 -o root -g root /etc/lunaway-ops
if [ ! -f /etc/lunaway-ops/probe_ed25519 ]; then
  ssh-keygen -q -t ed25519 -N '' -C "lunaway status probe" -f /etc/lunaway-ops/probe_ed25519
  echo "    generated the probe key; the ops-access step lets it in"
fi
chmod 0600 /etc/lunaway-ops/probe_ed25519
chmod 0644 /etc/lunaway-ops/probe_ed25519.pub

log "Gatus configuration"
web_enabled=false
if [ -n "$web_url" ]; then web_enabled=true; else web_url=https://lunaway.net/app/; fi
# The private key goes inline (Gatus reads no key file), indented under
# private-key: |, in a file only root and gatus can read.
python3 - "$INFRA/ops/gatus/config.yaml" "$STAGING/gatus-config.yaml" "$api_host" "$web_url" "$web_enabled" "$tiles_url" <<'EOF'
import os, sys
os.umask(0o077)
src, dest, api_host, web_url, web_enabled, tiles_url = sys.argv[1:7]
key = open("/etc/lunaway-ops/probe_ed25519").read().strip("\n")
indented = "\n".join("        " + line for line in key.splitlines())
text = open(src).read()
for marker, value in (("__API_HOST__", api_host), ("__WEB_URL__", web_url),
                      ("__WEB_ENABLED__", web_enabled), ("__TILES_URL__", tiles_url)):
    text = text.replace(marker, value)
text = text.replace("__PROBE_KEY__", indented)
assert "__" not in text, "unrendered marker"
with open(dest, "w") as out:
    out.write(text)
EOF
install -d -m 0750 -o root -g gatus /etc/gatus
restart=0
if ! cmp -s "$STAGING/gatus-config.yaml" /etc/gatus/config.yaml; then
  install -m 0640 -o root -g gatus "$STAGING/gatus-config.yaml" /etc/gatus/config.yaml
  echo "    updated /etc/gatus/config.yaml"
  restart=1
fi
install_file systemd/gatus.service /etc/systemd/system/gatus.service 0644 && { systemctl daemon-reload; restart=1; }
systemctl enable --quiet gatus
if [ -x /usr/local/bin/gatus ]; then
  if [ "$restart" = 1 ] || ! systemctl is-active --quiet gatus; then
    systemctl reset-failed gatus 2>/dev/null || true
    systemctl restart gatus
  fi
  log "gatus $(systemctl is-active gatus)"
else
  log "gatus configured, waiting for its binary (infra/deploy-gatus.sh)"
fi
