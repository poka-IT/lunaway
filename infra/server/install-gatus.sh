#!/usr/bin/env bash
# Installs an uploaded Gatus binary as /usr/local/bin/gatus when its SHA-256
# is the expected one, then (re)starts the service. Run as root by
# infra/deploy-gatus.sh, which pins the hash (infra/ops/gatus/version.sh).
#
#   sudo bash ~/infra/server/install-gatus.sh UPLOADED_FILE SHA256
. "$(dirname "$0")/common.sh"
need_root
upload="${1:?uploaded file}"
want="${2:?expected SHA-256}"
[[ "$want" =~ ^[0-9a-f]{64}$ ]] || die "unexpected hash $want"
[ -f "$upload" ] || die "no uploaded file at $upload"
got="$(sha256sum "$upload" | awk '{ print $1 }')"
[ "$got" = "$want" ] || die "the upload hashes to $got, expected $want; nothing installed"
install -m 0755 -o root -g root "$upload" /usr/local/bin/gatus
rm -f "$upload"
systemctl reset-failed gatus 2>/dev/null || true
systemctl restart gatus
for _ in $(seq 1 20); do
  curl -fs -m 2 -o /dev/null http://127.0.0.1:8080/api/v1/endpoints/statuses && break
  sleep 1
done
log "gatus $(systemctl is-active gatus), $(sha256sum /usr/local/bin/gatus | cut -c1-16)..."
