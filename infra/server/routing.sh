#!/usr/bin/env bash
# The routing engine of the backend, run as root by setup.sh
# (docs/deploy.md, "Routing"; plan/research/15-navigation-backend.md, part 5):
# Podman and the id ranges of UserNS=auto, the pinned Valhalla image, the two
# Quadlet units (valhalla, valhalla-candidate), lunaway-routing-refresh with
# its unit and timer, the route cases and the engine's configuration, the
# build key the graphs are signed with, and /srv/routing on the root disk.
#
# The engine starts once a graph is installed (lunaway-routing-refresh, by
# hand the first time: sudo systemctl start lunaway-routing-refresh); the
# daily timer is enabled only when a graph serves, so a missing release
# never shows as a failed unit every morning.
. "$(dirname "$0")/common.sh"
need_root
. "$INFRA/routing/version.sh"
grep -q "^Image=$VALHALLA_IMAGE\$" "$INFRA/routing/valhalla.container" \
  || die "valhalla.container does not name VALHALLA_IMAGE of infra/routing/version.sh"
grep -q "^Image=$VALHALLA_IMAGE\$" "$INFRA/routing/valhalla-candidate.container" \
  || die "valhalla-candidate.container does not name VALHALLA_IMAGE of infra/routing/version.sh"

log "Podman"
apt_install podman
# UserNS=auto maps each container's root to a free range of these ids.
for f in /etc/subuid /etc/subgid; do
  grep -q '^containers:' "$f" 2>/dev/null || echo 'containers:2147483647:2147483648' >> "$f"
done
# The units reach no network: the image is pulled here, by digest.
if ! podman image exists "$VALHALLA_IMAGE"; then
  podman pull -q "$VALHALLA_IMAGE" >/dev/null
  echo "    pulled Valhalla $VALHALLA_VERSION"
fi

log "files"
install -d -m 0755 -o root -g root /srv/routing /srv/routing/builds /srv/routing/incoming \
  /usr/local/share/lunaway /usr/local/share/lunaway/routing /etc/containers/systemd
changed=0
install_file routing/valhalla.container /etc/containers/systemd/valhalla.container 0644 && changed=1
install_file routing/valhalla-candidate.container /etc/containers/systemd/valhalla-candidate.container 0644 && changed=1
install_file routing/lunaway-routing-refresh.service /etc/systemd/system/lunaway-routing-refresh.service 0644 && changed=1
install_file routing/lunaway-routing-refresh.timer /etc/systemd/system/lunaway-routing-refresh.timer 0644 && changed=1
install_file routing/lunaway-routing-refresh /usr/local/sbin/lunaway-routing-refresh 0755 || true
install_file routing/test-routes.json /usr/local/share/lunaway/routing/test-routes.json 0644 || true
install_file routing/valhalla.json /usr/local/share/lunaway/routing/valhalla.json 0644 || true
# The refresh's lock, held to the end of this step: a restart of the engine
# between a refresh's switch and its live tests would make it switch back.
exec 9>/srv/routing/.lock
flock -w 900 9 || die "a graph refresh has held /srv/routing/.lock for 15 minutes; run this step again later"
# Each graph serves the copy lunaway-routing-refresh put next to it: a new
# configuration reaches the graphs on disk here (the one served and the
# previous one, for a rollback), not only the next refresh.
config_changed=0
for dir in /srv/routing/builds/*/; do
  dir="${dir%/}"
  [[ "$(basename "$dir")" =~ ^[0-9]{8}T[0-9]{4}Z-[a-z0-9]{2,16}$ ]] || continue
  # Real directories and files only: a link would send root's write
  # elsewhere.
  if [ -L "$dir" ] || [ -L "$dir/valhalla.json" ] || [ ! -f "$dir/valhalla.json" ]; then continue; fi
  if ! cmp -s /usr/local/share/lunaway/routing/valhalla.json "$dir/valhalla.json"; then
    install -m 0644 -o root -g root /usr/local/share/lunaway/routing/valhalla.json "$dir/valhalla.json"
    echo "    updated $dir/valhalla.json"
    config_changed=1
  fi
done
# The public halves of the build keys (allowed signers format); the private
# half of the current one lives on the maintainer's Mac (infra/ops/mac-routing/).
install_file routing/routing-signers /etc/lunaway/routing-signers 0644 || true
[ "$changed" = 1 ] && systemctl daemon-reload

if [ -L /srv/routing/current ]; then
  systemctl enable --quiet --now lunaway-routing-refresh.timer
  if [ "$changed" = 1 ] || [ "$config_changed" = 1 ] || ! systemctl is-active --quiet valhalla; then
    systemctl restart valhalla
  fi
  log "graph $(basename "$(readlink /srv/routing/current)"), valhalla $(systemctl is-active valhalla), next refresh $(systemctl show lunaway-routing-refresh.timer -p NextElapseUSecRealtime --value)"
else
  log "no graph yet: publish one (infra/ops/mac-routing/install.sh run on the Mac), then sudo systemctl start lunaway-routing-refresh and run this step again"
fi
