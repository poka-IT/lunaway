#!/bin/bash
# Runs on the ephemeral measurement server of measure-remote.sh, as root,
# from the copy of the repository it receives (the routing scripts, the
# backend sources, IGN's cached sections). Two measurements of the France graph, one after the other:
#
#   1. the bare build (measure-build.sh): time, memory and disk of Valhalla
#      on the raw extract, with 4 threads and a 16 GB cap, as on a
#      GitHub-hosted runner (4 vCPU, 16 GB);
#   2. the whole pipeline (build-graph.sh): prepare, osmium, build, route
#      tests and bundle, timed step by step, with the lunaway CLI built here.
#
#   measure-remote-run.sh            both
#   measure-remote-run.sh pipeline   the second only (the extract already there)
#
# Small results go to data/tmp/routing/ (collected by measure-remote.sh);
# `run.done` marks the end.
set -euo pipefail
cd "$(dirname "$0")/../.."
phase=${1:-all}
export DEBIAN_FRONTEND=noninteractive
UA="Lunaway routing graph measurement (+https://lunaway.net)"
t() { echo "[$(date -u +%H:%M:%S)] $*"; }

# measure-build.sh and build-graph.sh find the repository root with git.
git init -q . >/dev/null 2>&1 || true

extract=/root/france-latest.osm.pbf
if [ ! -f "$extract" ]; then
  t "extract"
  curl --proto "=https" --fail --location --silent --show-error -A "$UA" \
    -o "$extract.partial" https://download.geofabrik.de/europe/france-latest.osm.pbf
  mv "$extract.partial" "$extract"
fi
ls -l "$extract"

if [ "$phase" = all ]; then
  t "1. bare build"
  infra/routing/measure-build.sh "$extract" france-x86 4 16g
  rm -f data/tmp/routing/measure-france-x86/valhalla_tiles.tar data/tmp/routing/measure-france-x86/admins.sqlite
fi

t "2. lunaway CLI"
apt-get update -q >/dev/null
apt-get install -y -q build-essential pkg-config >/dev/null
curl --proto "=https" --fail --silent --show-error -A "$UA" -o /root/rustup-init \
  https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init
chmod +x /root/rustup-init
/root/rustup-init -y --default-toolchain none --profile minimal >/dev/null
export PATH="/root/.cargo/bin:$PATH"
(cd backend && SQLX_OFFLINE=true cargo build --release -p lunaway-cli -q)

t "2. pipeline"
mkdir -p data/tmp/routing
start=$(date +%s)
LUNAWAY_DATA_DIR="$PWD/data" /usr/bin/time -v \
  infra/routing/build-graph.sh "$extract" /root/out --area fr --threads 4 \
  >data/tmp/routing/pipeline.log 2>&1 || echo "pipeline failed: $?"
end=$(date +%s)
mkdir -p data/tmp/routing/pipeline
cp data/tmp/routing/pipeline.log data/tmp/routing/pipeline/
for f in prepare.json build.json test-routes.txt; do
  cp "/root/out/$f" data/tmp/routing/pipeline/ 2>/dev/null || true
done
ls -l /root/out/bundle >data/tmp/routing/pipeline/bundle.txt 2>&1 || true
cp /root/out/graph/build.log data/tmp/routing/pipeline/graph-build.log 2>/dev/null || true
echo "pipeline wall time: $((end - start)) s" >data/tmp/routing/pipeline/times.txt
date -u >run.done
t "done"
