#!/bin/bash
# Builds a Valhalla graph from a prepared OSM extract. Runs inside the
# Valhalla image pinned in infra/routing/version.sh, as one step of
# infra/routing/build-graph.sh (and of measure-build.sh, which measures it),
# with fixed mounts so nothing it removes is a computed path:
#
#   /input/extract.osm.pbf   the extract, read-only
#   /work                    the output directory
#
#   valhalla-build.sh [threads]
#
# Writes into /work:
#   valhalla_tiles.tar   the graph, the only file the server reads
#   admins.sqlite        administrative areas (country and state of each edge,
#                        baked into the tiles; kept for a rebuild)
#   build-config.json    the configuration the build used
#   build.log            what Valhalla printed, with the time of each stage
#
# Only roads a vehicle may drive on are kept (no pedestrian- or
# bicycle-only ways): the graph serves the `auto` costing alone, and the
# smaller graph builds faster and maps less memory. No time zones and no
# elevation yet: the API never sends a departure time, and slopes are a
# later feature (docs/deploy.md, "Routing").
set -euo pipefail

threads=${1:-4}
pbf=/input/extract.osm.pbf
config=/work/build-config.json
log=/work/build.log

mkdir -p /work/tiles
: >"$log"

valhalla_build_config \
  --mjolnir-tile-dir /work/tiles \
  --mjolnir-tile-extract /work/valhalla_tiles.tar \
  --mjolnir-traffic-extract "" \
  --mjolnir-admin /work/admins.sqlite \
  --mjolnir-timezone "" \
  --mjolnir-concurrency "$threads" \
  --mjolnir-include-pedestrian False \
  --mjolnir-include-bicycle False \
  --additional-data-elevation "" \
  --logging-color False \
  >"$config"

stage() {
  local name=$1
  shift
  local start end
  start=$(date +%s)
  echo "stage $name: start $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$log"
  "$@" >>"$log" 2>&1
  end=$(date +%s)
  echo "stage $name: done in $((end - start)) s" | tee -a "$log"
}

stage admins valhalla_build_admins --config "$config" "$pbf"
stage tiles valhalla_build_tiles --config "$config" "$pbf"
stage extract valhalla_build_extract --config "$config" --overwrite
# The tar holds every tile; the loose copy is never served.
rm -r /work/tiles
echo "graph: $(du -h /work/valhalla_tiles.tar | cut -f1)" | tee -a "$log"

# The configuration the server reads, for the layout of the backend
# (infra/routing/valhalla.container): the graph under
# /srv/routing/current, a listener on loopback only, and only the actions
# the API and the route tests use, so nothing else (isochrones, matrices,
# tiles) can be computed even from the host. Limits: one trip across
# France and back, the origin, five waypoints and the destination, and
# the exclusion rings of the check after each route.
valhalla_build_config \
  --mjolnir-tile-dir /srv/routing/current/tiles \
  --mjolnir-tile-extract /srv/routing/current/valhalla_tiles.tar \
  --mjolnir-traffic-extract "" \
  --mjolnir-admin /srv/routing/current/admins.sqlite \
  --mjolnir-timezone "" \
  --additional-data-elevation "" \
  --httpd-service-listen tcp://127.0.0.1:8002 \
  --httpd-service-timeout-seconds 30 \
  --loki-actions route,trace_attributes,status \
  --service-limits-auto-max-distance 2500000 \
  --service-limits-auto-max-locations 7 \
  --service-limits-max-alternates 2 \
  --service-limits-max-exclude-polygons-length 20000 \
  --logging-color False \
  >/work/valhalla.json
