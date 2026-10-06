#!/bin/bash
# Builds a routing graph bundle for motorhomes, from an OpenStreetMap extract
# and IGN BD TOPO's restricted road sections, and checks it before anyone
# serves it (docs/deploy.md, "Routing"). Run weekly by the GitHub Actions
# workflow .github/workflows/routing-graph.yml; runs as well on any machine
# with Docker, Rust and 25 GB of free disk for France.
#
#   infra/routing/build-graph.sh <extract.osm.pbf> <output dir> [options]
#     --area fr        the area's code, in the graph's name (default fr)
#     --threads 4      threads of the graph build (default 4)
#     --no-ign         without IGN's sections (a test extract)
#     --refresh-ign    reads IGN again instead of its cache
#
# Steps, each stopping the build on failure:
#   1. IGN's restricted sections, through the cache (`lunaway routing fetch-ign`);
#   2. `lunaway routing prepare`: the change file, the restrictions, build.json;
#   3. `osmium apply-changes`: the extract as the graph reads it;
#   4. Valhalla's build (infra/routing/valhalla-build.sh), in the pinned image;
#   5. the route tests (infra/routing/test-routes.json) on the new graph,
#      served on a loopback port of this machine;
#   6. the bundle: graph.tar.gz in parts under 1.9 GB (a GitHub release
#      asset may not exceed 2 GiB), the metadata, SHA256SUMS.
#
# The `lunaway` binary comes from LUNAWAY_BIN (default: the release build of
# this checkout, built when missing). Work files stay in the output dir; the
# prepared extract is removed once the graph is built.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
. infra/routing/version.sh

usage() { echo "usage: $0 <extract.osm.pbf> <output dir> [--area fr] [--threads N] [--no-ign] [--refresh-ign]" >&2; exit 2; }
[ $# -ge 2 ] || usage
pbf=$1
out=$2
shift 2
area=fr
threads=4
ign=yes
refresh=()
while [ $# -gt 0 ]; do
  case "$1" in
    --area) area=${2:?}; shift 2 ;;
    --threads) threads=${2:?}; shift 2 ;;
    --no-ign) ign=no; shift ;;
    --refresh-ign) refresh=(--refresh); shift ;;
    *) usage ;;
  esac
done
[[ "$area" =~ ^[a-z0-9]{2,16}$ ]] || { echo "--area: 2 to 16 lower-case letters or digits" >&2; exit 2; }
[[ "$threads" =~ ^[0-9]+$ ]] || { echo "--threads: a number" >&2; exit 2; }
[ -f "$pbf" ] || { echo "$pbf: no such extract" >&2; exit 2; }
pbf=$(cd "$(dirname "$pbf")" && pwd)/$(basename "$pbf")
mkdir -p "$out"
out=$(cd "$out" && pwd)
if [ -n "$(ls -A "$out")" ]; then
  echo "$out is not empty" >&2
  exit 2
fi

lunaway=${LUNAWAY_BIN:-backend/target/release/lunaway}
if [ ! -x "$lunaway" ]; then
  (cd backend && SQLX_OFFLINE=true cargo build --release -p lunaway-cli)
fi
lunaway=$(cd "$(dirname "$lunaway")" && pwd)/$(basename "$lunaway")
graph_id="$(date -u +%Y%m%dT%H%MZ)-$area"
engine="valhalla $VALHALLA_VERSION $VALHALLA_IMAGE"
log() { echo "[$(date -u +%H:%M:%S)] $*"; }

log "graph $graph_id from $pbf"
prepare=(routing prepare --pbf "$pbf" --out "$out" --graph-id "$graph_id" --engine "$engine")
if [ "$ign" = yes ]; then
  log "1. IGN BD TOPO sections"
  # The WFS may cut a page off mid-answer: an HTTP/2 stream reset after
  # 102 s on page 7 on 2026-10-06, a page it served in 18 s ten minutes
  # later. The fetch does not retry that error and keeps nothing of the
  # pages read, so the whole read runs again after a pause, three times at
  # most.
  for attempt in 1 2 3; do
    if "$lunaway" routing fetch-ign ${refresh[@]+"${refresh[@]}"}; then
      break
    fi
    [ "$attempt" -lt 3 ] || { log "IGN BD TOPO: three reads failed"; exit 1; }
    log "IGN BD TOPO: read $attempt failed, next one in 5 minutes"
    sleep 300
  done
else
  prepare+=(--no-ign)
fi

log "2. prepare"
"$lunaway" "${prepare[@]}" >"$out/prepare.out"
cat "$out/prepare.json"

log "3. apply the change file"
docker build --quiet --tag lunaway-osmium:build --file infra/routing/osmium.Dockerfile infra/routing >/dev/null
docker run --rm \
  --volume "$pbf:/input/extract.osm.pbf:ro" \
  --volume "$out:/work" \
  lunaway-osmium:build apply-changes /input/extract.osm.pbf /work/fixes.osc.gz \
  --output /work/prepared.osm.pbf --overwrite

log "4. graph build"
mkdir "$out/graph"
docker run --rm \
  --volume "$out/prepared.osm.pbf:/input/extract.osm.pbf:ro" \
  --volume "$out/graph:/work" \
  --volume "$PWD/infra/routing/valhalla-build.sh:/opt/lunaway/valhalla-build.sh:ro" \
  --entrypoint /bin/bash \
  "$VALHALLA_IMAGE" /opt/lunaway/valhalla-build.sh "$threads"
rm -f "$out/prepared.osm.pbf"

log "5. route tests"
# The bundle's configuration listens on the server's loopback; inside a
# container, the check listens on all of the container's addresses and is
# published on this machine's loopback only.
sed 's#tcp://127.0.0.1:8002#tcp://0.0.0.0:8002#' "$out/graph/valhalla.json" >"$out/check.json"
port=18102
container="lunaway-routing-check-$graph_id"
docker run --detach --name "$container" \
  --publish "127.0.0.1:$port:8002" \
  --volume "$out/graph:/srv/routing/current:ro" \
  --volume "$out/check.json:/srv/check.json:ro" \
  --entrypoint valhalla_service \
  "$VALHALLA_IMAGE" /srv/check.json 2 >/dev/null
cleanup() { docker rm --force "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT
for _ in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:$port/status" >/dev/null 2>&1 && break
  sleep 2
done
"$lunaway" routing test-routes --url "http://127.0.0.1:$port" --cases infra/routing/test-routes.json | tee "$out/test-routes.txt"
cleanup
trap - EXIT
rm -f "$out/check.json"

log "6. bundle"
mkdir "$out/bundle"
cp "$out/build.json" "$out/prepare.json" "$out/restrictions.ndjson.gz" "$out/test-routes.txt" "$out/bundle/"
tar -C "$out/graph" -cf - valhalla_tiles.tar admins.sqlite valhalla.json \
  | gzip -6 | split -b 1900m -d -a 2 - "$out/bundle/graph.tar.gz.part-"
(
  cd "$out/bundle"
  if command -v sha256sum >/dev/null; then sha256sum -- *; else shasum -a 256 -- *; fi
) >"$out/SHA256SUMS"
mv "$out/SHA256SUMS" "$out/bundle/SHA256SUMS"
ls -l "$out/bundle"
log "done: $out/bundle"
