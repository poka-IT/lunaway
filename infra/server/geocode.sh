#!/usr/bin/env bash
# The geocoders of the backend, run as root by setup.sh (docs/deploy.md,
# "Geocoding"): Java, the pinned Photon jar, the photon account, the two
# instances (photon@europe, photon@morocco) on the loopback,
# lunaway-photon-refresh with its unit and timer, and /srv/photon on the
# local disk.
#
# An instance starts once its database is installed (lunaway-photon-refresh,
# by hand the first time: sudo systemctl start lunaway-photon-refresh, about
# an hour); the monthly timer is enabled only when a database serves.
. "$(dirname "$0")/common.sh"
need_root
. "$INFRA/geocode/version.sh"

log "packages"
apt_install openjdk-21-jre-headless lbzip2 zstd curl ca-certificates

log "photon account and directories"
getent group photon >/dev/null || groupadd --system photon
getent passwd photon >/dev/null || useradd --system --gid photon --home-dir /srv/photon --no-create-home --shell /usr/sbin/nologin photon
install -d -m 0755 -o root -g root /opt/photon /usr/local/share/lunaway /usr/local/share/lunaway/geocode
install -d -m 0750 -o photon -g photon /srv/photon

log "Photon $PHOTON_VERSION"
jar="/opt/photon/photon-$PHOTON_VERSION.jar"
if ! echo "$PHOTON_JAR_SHA256  $jar" | sha256sum -c --quiet - >/dev/null 2>&1; then
  curl -fsSL --retry 3 -o "$STAGING/photon.jar" "$PHOTON_JAR_URL"
  echo "$PHOTON_JAR_SHA256  $STAGING/photon.jar" | sha256sum -c --quiet - \
    || die "the Photon jar does not match PHOTON_JAR_SHA256 of infra/geocode/version.sh"
  install -m 0644 -o root -g root "$STAGING/photon.jar" "$jar"
  echo "    installed $jar"
fi
changed=0
if [ "$(readlink /opt/photon/photon.jar 2>/dev/null || true)" != "$jar" ]; then
  ln -sfn "$jar" /opt/photon/photon.jar
  changed=1
fi

log "units"
# Europe's heap: 2 GB, which held OpenSearch's own structures and answered
# as fast as 4 GB under a 7 GB cap (docs/deploy.md, the measurements of
# 2026-10-07); the index is read through the page cache, which the backend's
# database and routing engine share, within the unit's MemoryHigh. Morocco's
# index weighs about 110 MB.
printf 'PHOTON_PORT=2322\nPHOTON_HEAP=2048m\n' > "$STAGING/europe.env"
printf 'PHOTON_PORT=2323\nPHOTON_HEAP=512m\n' > "$STAGING/morocco.env"
install_file "$STAGING/europe.env" /usr/local/share/lunaway/geocode/europe.env 0644 && changed=1
install_file "$STAGING/morocco.env" /usr/local/share/lunaway/geocode/morocco.env 0644 && changed=1
install_file geocode/photon@.service /etc/systemd/system/photon@.service 0644 && changed=1
install_file geocode/lunaway-photon-refresh.service /etc/systemd/system/lunaway-photon-refresh.service 0644 && changed=1
install_file geocode/lunaway-photon-refresh.timer /etc/systemd/system/lunaway-photon-refresh.timer 0644 && changed=1
install_file geocode/lunaway-photon-refresh /usr/local/sbin/lunaway-photon-refresh 0755 || true
install_file geocode/version.sh /usr/local/share/lunaway/geocode/version.sh 0644 || true
[ "$changed" = 1 ] && systemctl daemon-reload

served=0
for instance in europe morocco; do
  if [ -L "/srv/photon/$instance/current" ]; then
    served=1
    systemctl enable --quiet "photon@$instance"
    if [ "$changed" = 1 ] || ! systemctl is-active --quiet "photon@$instance"; then
      systemctl restart "photon@$instance"
    fi
    log "$instance: $(readlink "/srv/photon/$instance/current") of $(cat "/srv/photon/$instance/current/INSTALLED_AT" 2>/dev/null || echo '?'), $(systemctl is-active "photon@$instance")"
  else
    log "$instance: no database yet"
  fi
done
if [ "$served" = 1 ]; then
  systemctl enable --quiet --now lunaway-photon-refresh.timer
  log "next refresh $(systemctl show lunaway-photon-refresh.timer -p NextElapseUSecRealtime --value)"
else
  log "no database yet: sudo systemctl start lunaway-photon-refresh (about an hour), then run this step again"
fi
