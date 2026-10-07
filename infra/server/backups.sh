#!/usr/bin/env bash
# Nightly PostgreSQL dump, run as root by setup.sh: the dump script, its
# sandboxed unit, its failure marker and timer, the ordering that keeps the
# upgrade run from restarting PostgreSQL under a dump, and the directories:
#
#   /srv/data/backups/postgresql   plaintext dumps, 7 kept (postgres, 0700)
#   /var/backups/lunaway/...       the newest 3 encrypted copies on the root
#                                  disk (0700), which Hetzner's images capture
#   /srv/data/backups/offsite      age-encrypted copies, 7 kept, and the
#                                  last-success / last-failure markers; group
#                                  lunaway-pull reads it (infra/server/ops-access.sh)
#   /srv/data/backups/offsite/media   the photos, one age-encrypted file per
#                                  photo, kept in step with /srv/data/media every
#                                  night by lunaway-media-offsite (00:45 UTC)
#   /srv/data/backups/offsite/account-deletions   the account deletion journal
#                                  (/srv/data/account-deletions, infra/server/api.sh)
#                                  as one age-encrypted file, written again
#                                  every hour by lunaway-deletions-offsite
#   /srv/data/backups/offsite/place-takedowns   the takedown journal
#                                  (/srv/data/place-takedowns, infra/server/pipeline.sh)
#                                  the same way, by lunaway-takedowns-offsite
#
#   LUNAWAY_BACKUP_RECIPIENT   the age public key the copies are encrypted to;
#                              its private half exists only on the Mac
#                              (infra/ops/mac/install.sh)
#
# Runs a first dump when none exists yet, which also proves the chain works.
. "$(dirname "$0")/common.sh"
need_root
mountpoint -q /srv/data || die "/srv/data is not mounted; run data-volume.sh first"
recipient="${LUNAWAY_BACKUP_RECIPIENT:-}"
[[ "$recipient" =~ ^age1[02-9ac-hj-np-z]{58}$ ]] || die "LUNAWAY_BACKUP_RECIPIENT is not an age recipient"
apt_install age

getent group lunaway-pull >/dev/null || groupadd --system lunaway-pull
# The unit of the journal's copy reads the journal through this group
# (infra/server/api.sh makes the journal's directory).
getent group lunaway-deletions >/dev/null || groupadd --system lunaway-deletions
getent group lunaway-takedowns >/dev/null || groupadd --system lunaway-takedowns
install -d -m 0755 /srv/data/backups /var/backups/lunaway
install -d -o postgres -g postgres -m 0700 /srv/data/backups/postgresql /var/backups/lunaway/postgresql
install -d -o postgres -g lunaway-pull -m 2750 /srv/data/backups/offsite
install -d -o root -g lunaway-pull -m 2750 /srv/data/backups/offsite/media
install -d -o root -g lunaway-pull -m 2750 /srv/data/backups/offsite/account-deletions
install -d -o root -g lunaway-pull -m 2750 /srv/data/backups/offsite/place-takedowns

install -d -m 0700 -o root -g root /etc/lunaway
echo "$recipient" > "$STAGING/backup-recipient"
install_file "$STAGING/backup-recipient" /etc/lunaway/backup-recipient 0600 || true

changed=0
install_file files/usr/local/sbin/lunaway-pgdump /usr/local/sbin/lunaway-pgdump 0755 || true
install_file files/usr/local/sbin/lunaway-media-offsite /usr/local/sbin/lunaway-media-offsite 0755 || true
install_file files/usr/local/sbin/lunaway-deletions-offsite /usr/local/sbin/lunaway-deletions-offsite 0755 || true
install_file files/usr/local/sbin/lunaway-takedowns-offsite /usr/local/sbin/lunaway-takedowns-offsite 0755 || true
for unit in lunaway-pgdump.service lunaway-pgdump-failed.service lunaway-pgdump.timer \
  lunaway-media-offsite.service lunaway-media-offsite.timer \
  lunaway-deletions-offsite.service lunaway-deletions-offsite.timer \
  lunaway-takedowns-offsite.service lunaway-takedowns-offsite.timer \
  apt-daily-upgrade.service.d/lunaway-pgdump.conf; do
  install_file "systemd/$unit" "/etc/systemd/system/$unit" 0644 && changed=1
done
[ "$changed" = 1 ] && systemctl daemon-reload
systemctl enable --quiet --now lunaway-pgdump.timer lunaway-media-offsite.timer \
  lunaway-deletions-offsite.timer lunaway-takedowns-offsite.timer

if ! ls /srv/data/backups/offsite/lunaway-*.dump.age >/dev/null 2>&1; then
  log "first dump"
  systemctl start lunaway-pgdump.service
fi
log "encrypted copies: $(find /srv/data/backups/offsite -maxdepth 1 -type f -printf '%f ' | tr -s ' ')"
log "next run: $(systemctl show lunaway-pgdump.timer -p NextElapseUSecRealtime --value); photos: $(systemctl show lunaway-media-offsite.timer -p NextElapseUSecRealtime --value)"
