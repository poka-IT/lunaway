#!/bin/bash
# Runs the API's end-to-end routing tests (backend/crates/lunaway-api/tests/
# route_e2e.rs) against a real Valhalla and a real graph, as a CI runner or
# a build server can: about 100 MB of download and a minute of build for
# Limousin. Never on the maintainer's Mac, which builds and serves no graph
# (docs/deploy.md, "Routing"); there, point LUNAWAY_E2E_VALHALLA_URL at an
# engine on another machine through an SSH tunnel and run the tests alone.
#
#   infra/routing/e2e.sh                 builds the Limousin graph first
#   infra/routing/e2e.sh <build dir>     uses a build of build-graph.sh (its
#                                        graph/ and restrictions.ndjson.gz)
#
# Needs Docker, the local database of backend/compose.yaml (DATABASE_URL,
# default the compose one) and IGN's sections in the cache
# (`lunaway routing fetch-ign`; the build fetches them when missing).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
. infra/routing/version.sh

export DATABASE_URL=${DATABASE_URL:-postgres://lunaway:lunaway@127.0.0.1:54329/lunaway}
build=${1:-}
if [ -z "$build" ]; then
  extract=data/tmp/routing/limousin-latest.osm.pbf
  if [ ! -f "$extract" ]; then
    mkdir -p data/tmp/routing
    curl --proto "=https" --fail --location --silent --show-error \
      -A "Lunaway routing tests (+https://lunaway.net)" \
      -o "$extract.partial" https://download.geofabrik.de/europe/france/limousin-latest.osm.pbf
    mv "$extract.partial" "$extract"
  fi
  build=data/tmp/routing/e2e-limousin
  if [ ! -f "$build/graph/valhalla_tiles.tar" ]; then
    infra/routing/build-graph.sh "$extract" "$build" --area e2e
  fi
fi
build=$(cd "$build" && pwd)
[ -f "$build/graph/valhalla_tiles.tar" ] || { echo "$build has no graph" >&2; exit 2; }

port=18202
container=lunaway-routing-e2e
sed 's#tcp://127.0.0.1:8002#tcp://0.0.0.0:8002#' "$build/graph/valhalla.json" >"$build/e2e.json"
docker rm --force "$container" >/dev/null 2>&1 || true
docker run --detach --name "$container" \
  --publish "127.0.0.1:$port:8002" \
  --volume "$build/graph:/srv/routing/current:ro" \
  --volume "$build/e2e.json:/srv/e2e.json:ro" \
  --entrypoint valhalla_service \
  "$VALHALLA_IMAGE" /srv/e2e.json 2 >/dev/null
trap 'docker rm --force "$container" >/dev/null 2>&1 || true; rm -f "$build/e2e.json"' EXIT
for _ in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:$port/status" >/dev/null 2>&1 && break
  sleep 1
done

cd backend
# The end-to-end tests are their own binary today and a module of the
# crate's integration binary once the backend folds them in: the filter
# takes both, so neither form selects nothing (nextest fails on no test).
LUNAWAY_E2E_VALHALLA_URL="http://127.0.0.1:$port" \
LUNAWAY_E2E_RESTRICTIONS="$build/restrictions.ndjson.gz" \
  cargo nextest run -p lunaway-api -E 'test(/^route_e2e::/)' --run-ignored only --no-capture
