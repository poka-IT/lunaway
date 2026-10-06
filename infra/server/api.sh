#!/usr/bin/env bash
# The lunaway-api service, run as root by setup.sh: release directories, the
# service's user, the photo directory and the account deletion journal it
# writes, the sandboxed unit, the environment files, and lunaway-admin (the
# CLI run as the API or as the imports, for an operator). The binary itself arrives with
# infra/deploy-api.sh; until then the unit is enabled but not started.
#
#   LUNAWAY_MEDIA_BASE_URL   public URL of /srv/data/media,
#                            https://api.lunaway.net/media/ (infra/lib.sh)
#
# The API's own public URL (LUNAWAY_PUBLIC_URL, which the TileJSON of the
# points of interest names in its tile URLs) is that origin without
# /media/, so the two always name the same host.
. "$(dirname "$0")/common.sh"
need_root
media_base="${LUNAWAY_MEDIA_BASE_URL:?set LUNAWAY_MEDIA_BASE_URL}"
[[ "$media_base" =~ ^https://[a-z0-9.-]+/media/$ ]] || die "unexpected media base URL $media_base"
mountpoint -q /srv/data || die "/srv/data is not mounted; run data-volume.sh first"

install -d -m 0755 /opt/lunaway /opt/lunaway/releases
install -d -m 0700 -o root -g root /etc/lunaway
if [ ! -f /etc/lunaway/api.env ]; then
  ( umask 077; : > /etc/lunaway/api.env )
fi
chmod 0600 /etc/lunaway/api.env

log "account, photos and deletion journal"
# Static, not dynamic: the photos it writes stay on the volume across runs,
# and the moderation commands (lunaway-admin) delete them as the same user.
# The passwd file only (getent -s files): while the unit of an earlier
# version still ran with DynamicUser, a plain getent found that dynamic user
# through nss-systemd, useradd was skipped, and the API failed to start once
# it stopped (about 13 seconds of outage on 2026-10-06).
if ! getent -s files passwd lunaway-api >/dev/null; then
  useradd --system --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin \
    --comment "Lunaway API" --user-group lunaway-api
fi
# Owned by the API, readable by everyone (Caddy serves it under /media/).
install -d -m 0755 -o lunaway-api -g lunaway-api /srv/data/media
# The account deletion journal, outside the dumps so a restore cannot bring
# a deleted account back (docs/deploy.md, "Backups and restore"). Written by
# the API, which refuses to start without it; read by group
# lunaway-deletions only (setgid: the API's 0640 files take that group), the
# encrypted copy's unit, lunaway-deletions-offsite (infra/server/backups.sh).
getent group lunaway-deletions >/dev/null || groupadd --system lunaway-deletions
install -d -m 2750 -o lunaway-api -g lunaway-deletions /srv/data/account-deletions
cat > "$STAGING/media.env" <<EOF
LUNAWAY_MEDIA_DIR=/srv/data/media
LUNAWAY_MEDIA_BASE_URL=$media_base
LUNAWAY_PUBLIC_URL=${media_base%/media/}
LUNAWAY_DELETION_JOURNAL=/srv/data/account-deletions
EOF

changed=0
install_file "$STAGING/media.env" /etc/lunaway/media.env 0600 && changed=1
install_file systemd/lunaway-api.service /etc/systemd/system/lunaway-api.service 0644 && changed=1
install_file files/usr/local/sbin/lunaway-admin /usr/local/sbin/lunaway-admin 0755 || true
[ "$changed" = 1 ] && systemctl daemon-reload
systemctl enable --quiet lunaway-api
if [ -x /opt/lunaway/current/lunaway-api ]; then
  if [ "$changed" = 1 ] || ! systemctl is-active --quiet lunaway-api; then
    systemctl reset-failed lunaway-api 2>/dev/null || true
    systemctl restart lunaway-api
  fi
  log "lunaway-api $(systemctl is-active lunaway-api), photos at $media_base, public URL ${media_base%/media/}"
else
  log "lunaway-api installed, waiting for its first binary (infra/deploy-api.sh)"
fi
