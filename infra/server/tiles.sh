#!/usr/bin/env bash
# The basemap of the backend, run as root by setup.sh: the tile volume at
# /srv/tiles, the pinned go-pmtiles binary, the fonts and sprites, the tile
# server on loopback (Caddy serves it, see the tiles snippet of the
# Caddyfile) and its monthly refresh. Starts the first download when no
# planet is on the volume yet.
#
#   LUNAWAY_TILES_VOLUME_ID   the Hetzner id of the tile volume (provision.sh)
#
# /srv/tiles:
#   builds/ serve/ tilejson/   written by lunaway-tiles-refresh only
#   assets/fonts/              Noto Sans glyph ranges, from basemaps-assets
#   assets/sprites/            protomaps-v4/ from basemaps-assets; our own
#                              sprite sheets go beside it
#   assets/styles/             map styles served with the site's address
#                              filled in (empty until the app's design lands)
#   packs/                     offline packs, <region>.pmtiles, served with
#                              range requests (empty until the feature lands)
. "$(dirname "$0")/common.sh"
need_root
. "$INFRA/tiles/version.sh"
id="${LUNAWAY_TILES_VOLUME_ID:?set LUNAWAY_TILES_VOLUME_ID}"
user_agent="Lunaway infra (+https://lunaway.net)"

log "tile volume"
mount_volume "$id" /srv/tiles
dev="/dev/disk/by-id/scsi-0HC_Volume_$id"
# No blocks reserved for root: nothing but the refresh writes here, and the
# 5% ext4 keeps by default would be 15 GB of a volume sized for two planets.
if [ "$(tune2fs -l "$dev" | awk -F: '/^Reserved block count/ { gsub(/ /, "", $2); print $2 }')" != 0 ]; then
  tune2fs -m 0 "$dev" >/dev/null
  echo "    reserved blocks set to 0"
fi

log "accounts and directories"
if ! getent passwd lunaway-tiles >/dev/null; then
  useradd --system --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin \
    --comment "Lunaway basemap refresh" --user-group lunaway-tiles
fi
install -d -m 0755 -o lunaway-tiles -g lunaway-tiles /srv/tiles/builds /srv/tiles/serve /srv/tiles/tilejson
install -d -m 0755 -o root -g root /srv/tiles/assets /srv/tiles/assets/sprites /srv/tiles/assets/styles /srv/tiles/packs

log "go-pmtiles $PMTILES_VERSION"
case "$(uname -m)" in
  x86_64) url="$PMTILES_URL_AMD64" want="$PMTILES_SHA256_AMD64" ;;
  aarch64) url="$PMTILES_URL_ARM64" want="$PMTILES_SHA256_ARM64" ;;
  *) die "unsupported architecture $(uname -m)" ;;
esac
tarball="$STAGING/go-pmtiles-$PMTILES_VERSION-$(uname -m).tar.gz"
if [ ! -f "$tarball" ] || [ "$(sha256sum "$tarball" | awk '{ print $1 }')" != "$want" ]; then
  curl -fsSL --retry 3 -m 300 -A "$user_agent" -o "$tarball.download" "$url"
  got="$(sha256sum "$tarball.download" | awk '{ print $1 }')"
  [ "$got" = "$want" ] || { rm -f "$tarball.download"; die "the go-pmtiles tarball hashes to $got, the pin says $want"; }
  mv -f "$tarball.download" "$tarball"
fi
install -d -m 0700 "$STAGING/pmtiles"
tar -xzf "$tarball" -C "$STAGING/pmtiles" pmtiles LICENSE
if ! cmp -s "$STAGING/pmtiles/pmtiles" /usr/local/bin/pmtiles; then
  install -m 0755 -o root -g root "$STAGING/pmtiles/pmtiles" /usr/local/bin/pmtiles
  echo "    installed /usr/local/bin/pmtiles ($(/usr/local/bin/pmtiles version | cut -d, -f1))"
fi
install -D -m 0644 "$STAGING/pmtiles/LICENSE" /usr/local/share/doc/go-pmtiles/LICENSE
apt_install b3sum

log "fonts and sprites, basemaps-assets ${BASEMAPS_ASSETS_COMMIT:0:12}"
# The marker names the layout too: files are copied with links resolved.
marker="$BASEMAPS_ASSETS_COMMIT files"
if [ "$(cat /srv/tiles/assets/.basemaps-assets 2>/dev/null || true)" != "$marker" ]; then
  checkout="$STAGING/basemaps-assets/basemaps-assets-$BASEMAPS_ASSETS_COMMIT"
  rm -rf /var/lib/lunaway-setup/basemaps-assets
  install -d -m 0700 "$STAGING/basemaps-assets"
  curl -fsSL --retry 3 -m 300 -A "$user_agent" -o "$STAGING/basemaps-assets.tar.gz" \
    "https://codeload.github.com/protomaps/basemaps-assets/tar.gz/$BASEMAPS_ASSETS_COMMIT"
  tar -xzf "$STAGING/basemaps-assets.tar.gz" -C "$STAGING/basemaps-assets"
  read -r tree count < <(python3 "$INFRA/tiles/assets-hash.py" "$checkout")
  [ "$tree" = "$BASEMAPS_ASSETS_TREE_SHA256" ] \
    || die "basemaps-assets $BASEMAPS_ASSETS_COMMIT hashes to $tree over $count files, the pin says $BASEMAPS_ASSETS_TREE_SHA256"
  # Copied into fresh directories, then swapped in, so Caddy never serves a
  # half-copied font set. Links between font stacks (checked by
  # assets-hash.py to stay inside the set) become plain files: nothing under
  # the web root is a link.
  rm -rf /srv/tiles/assets/fonts.new /srv/tiles/assets/sprites/protomaps-v4.new
  install -d -m 0755 /srv/tiles/assets/fonts.new /srv/tiles/assets/sprites/protomaps-v4.new
  for stack in "Noto Sans Regular" "Noto Sans Medium" "Noto Sans Italic" "Noto Sans Devanagari Regular v1"; do
    cp -RL "$checkout/fonts/$stack" /srv/tiles/assets/fonts.new/
  done
  cp "$checkout/fonts/OFL.txt" /srv/tiles/assets/fonts.new/OFL.txt
  cp -L "$checkout"/sprites/v4/* /srv/tiles/assets/sprites/protomaps-v4.new/
  chown -R root:root /srv/tiles/assets/fonts.new /srv/tiles/assets/sprites/protomaps-v4.new
  chmod -R u=rwX,go=rX /srv/tiles/assets/fonts.new /srv/tiles/assets/sprites/protomaps-v4.new
  rm -rf /srv/tiles/assets/fonts.old /srv/tiles/assets/sprites/protomaps-v4.old
  [ -d /srv/tiles/assets/fonts ] && mv /srv/tiles/assets/fonts /srv/tiles/assets/fonts.old
  [ -d /srv/tiles/assets/sprites/protomaps-v4 ] && mv /srv/tiles/assets/sprites/protomaps-v4 /srv/tiles/assets/sprites/protomaps-v4.old
  mv /srv/tiles/assets/fonts.new /srv/tiles/assets/fonts
  mv /srv/tiles/assets/sprites/protomaps-v4.new /srv/tiles/assets/sprites/protomaps-v4
  rm -rf /srv/tiles/assets/fonts.old /srv/tiles/assets/sprites/protomaps-v4.old /var/lib/lunaway-setup/basemaps-assets
  rm -f "$STAGING/basemaps-assets.tar.gz"
  [ -z "$(find /srv/tiles/assets/fonts /srv/tiles/assets/sprites/protomaps-v4 ! -type f ! -type d -print -quit)" ] \
    || die "a link or a special file under /srv/tiles/assets after the copy"
  echo "$marker" > /srv/tiles/assets/.basemaps-assets
  echo "    installed $count files (tree $tree)"
fi

log "units"
changed=0 server_changed=0
# A running refresh keeps its script: bash reads it as it goes.
if [ "$(systemctl show -p ActiveState --value lunaway-tiles-refresh)" = inactive ] \
  || [ "$(systemctl show -p ActiveState --value lunaway-tiles-refresh)" = failed ]; then
  install_file files/usr/local/sbin/lunaway-tiles-refresh /usr/local/sbin/lunaway-tiles-refresh 0755 || true
elif ! cmp -s "$INFRA/files/usr/local/sbin/lunaway-tiles-refresh" /usr/local/sbin/lunaway-tiles-refresh; then
  echo "    a refresh is running: lunaway-tiles-refresh left as it is, run this step again after it"
fi
install_file systemd/lunaway-tiles.service /etc/systemd/system/lunaway-tiles.service 0644 && changed=1 server_changed=1
for unit in lunaway-tiles-refresh.service lunaway-tiles-refresh.timer; do
  install_file "systemd/$unit" "/etc/systemd/system/$unit" 0644 && changed=1
done
[ "$changed" = 1 ] && systemctl daemon-reload
systemctl enable --quiet lunaway-tiles lunaway-tiles-refresh.timer
if [ "$server_changed" = 1 ] || ! systemctl is-active --quiet lunaway-tiles; then
  systemctl restart lunaway-tiles
fi
systemctl start lunaway-tiles-refresh.timer
for _ in $(seq 1 20); do
  curl -fs -m 2 -o /dev/null http://127.0.0.1:8485/ && break
  sleep 0.5
done
log "tile server $(systemctl is-active lunaway-tiles); next refresh: $(systemctl list-timers --no-pager --no-legend lunaway-tiles-refresh.timer | awk '{ print $1, $2, $3 }')"

current="$(readlink /srv/tiles/serve/planet.pmtiles 2>/dev/null || true)"
if [ -z "$current" ]; then
  if [ "$(systemctl show -p ActiveState --value lunaway-tiles-refresh)" = activating ]; then
    log "the first planet download is running (journalctl -u lunaway-tiles-refresh -f)"
  else
    systemctl start --no-block lunaway-tiles-refresh
    log "no planet on the volume yet: started the first download, about half an hour (journalctl -u lunaway-tiles-refresh -f)"
  fi
else
  log "serving $current; $(df -h --output=used,avail /srv/tiles | tail -n 1 | tr -s ' ') used, free on /srv/tiles"
fi
