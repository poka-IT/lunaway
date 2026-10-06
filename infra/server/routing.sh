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
# The public half of the build key (allowed signers format); the private half
# lives only in GitHub's environment secret.
install_file routing/routing-signers /etc/lunaway/routing-signers 0644 || true
[ "$changed" = 1 ] && systemctl daemon-reload

if [ -L /srv/routing/current ]; then
  systemctl enable --quiet --now lunaway-routing-refresh.timer
  if [ "$changed" = 1 ] || ! systemctl is-active --quiet valhalla; then
    systemctl restart valhalla
  fi
  log "graph $(basename "$(readlink /srv/routing/current)"), valhalla $(systemctl is-active valhalla), next refresh $(systemctl show lunaway-routing-refresh.timer -p NextElapseUSecRealtime --value)"
else
  log "no graph yet: publish one (.github/workflows/routing-graph.yml), then sudo systemctl start lunaway-routing-refresh and run this step again"
fi
