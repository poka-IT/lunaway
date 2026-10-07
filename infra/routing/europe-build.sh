#!/bin/bash
# Builds the Europe routing graph bundle on a throwaway Hetzner server, as
# root, from a checkout of this repository in /root/lunaway. Started and
# watched by the maintainer's Mac (infra/ops/mac-routing/lunaway-routing-build.sh),
# which then collects /root/out/bundle, signs it and publishes it; this
# server holds no signing key, no Hetzner token and no GitHub token.
#
#   infra/routing/europe-build.sh YYMMDD     the whole build, from Geofabrik's
#                                            extracts of that day
#
# Steps, each stopping the build on failure:
#   1. the extracts of infra/routing/europe-extracts.txt from Geofabrik, all
#      of the same day (the dated files, <name>-YYMMDD.osm.pbf), three at a
#      time, each checked against Geofabrik's MD5, then their replication
#      timestamps compared: merging two days leaves two versions of the
#      objects changed in between (the Germany extract was a day behind the
#      others on 2026-10-06, plan/research/31-routage-europe.md);
#   2. `osmium merge`, the common timestamp written into the header (the
#      preparation refuses an extract without one), the extracts removed;
#   3. infra/routing/build-graph.sh on the merged file, area `eu`, 8
#      threads, IGN read again (heights of France only: the sections are
#      matched to the ways they lie on, and IGN covers France alone).
#
# Measured on a ccx33 (8 dedicated vCPU, 32 GB, 240 GB) on 2026-10-06:
# 3 h 26 min in all, 16.5 GiB of anonymous memory and about 171 GB of disk
# at the peak, a bundle of 8.3 GB in 5 parts.
#
# State for the Mac, in /root/run: `state` (running <step> | done |
# failed <code>), `build.log`, `extracts.tsv`, `source.txt`. Exit codes:
# 0 done, 3 the extracts of the day carry different timestamps, 1 anything
# else.
set -euo pipefail

cd /root/lunaway
RUN=/root/run
X=/root/extracts
MERGED=/root/merged
OUT=/root/out
UA="Lunaway routing graph build (+https://lunaway.net)"
GEOFABRIK=https://download.geofabrik.de
DAY=${1:-}
[[ "$DAY" =~ ^[0-9]{6}$ ]] || { echo "usage: $0 YYMMDD" >&2; exit 2; }
mkdir -p "$RUN" "$X" "$MERGED"
export DEBIAN_FRONTEND=noninteractive

t() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
state() { echo "$*" >"$RUN/state"; t "state: $*"; }
fail() {
  local code=$1
  shift
  t "error: $*"
  state "failed $code"
  exit "$code"
}
trap 'state "failed 1"' ERR

state "running setup"
# build-graph.sh finds the repository root with git; the checkout is one.
git rev-parse HEAD >"$RUN/source.txt" 2>/dev/null || echo unknown >"$RUN/source.txt"

mapfile -t paths < <(grep -E '^[a-z-]+/[a-z-]+$' infra/routing/europe-extracts.txt)
[ "${#paths[@]}" -ge 2 ] || fail 1 "no extract listed in infra/routing/europe-extracts.txt"

t "CLI build, in the background"
(
  apt-get update -q >/dev/null
  apt-get install -y -q build-essential pkg-config >/dev/null
  curl --proto "=https" --fail --silent --show-error -A "$UA" -o /root/rustup-init \
    https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init
  chmod +x /root/rustup-init
  /root/rustup-init -y --default-toolchain none --profile minimal >/dev/null
  export PATH="/root/.cargo/bin:$PATH"
  cd backend
  start=$(date +%s)
  SQLX_OFFLINE=true CARGO_INCREMENTAL=0 cargo build --release --locked -p lunaway-cli -q
  echo "cli build: $(($(date +%s) - start)) s"
) >"$RUN/cli-build.log" 2>&1 &
cli=$!

docker build --quiet --tag lunaway-osmium:build --file infra/routing/osmium.Dockerfile infra/routing >/dev/null

name_of() { basename "$1"; }

# One extract of the day asked, its MD5 checked against Geofabrik's; a
# failure leaves a marker, since a background job's status is not kept.
# The dated file, not -latest: Geofabrik sends -latest of the largest
# extracts to a mirror that may lag a day (germany-latest was the extract of
# 2026-10-04 there at 23:08 UTC on 2026-10-06, while Geofabrik had published
# 2026-10-05), and keeps the dated files of the last days itself. Three
# attempts, five minutes apart, for a transient error.
fetch() {
  local path=$1 name attempt
  name=$(name_of "$path")
  rm -f "$X/$name.failed"
  for attempt in 1 2 3; do
    if curl --proto "=https" --fail --silent --show-error --connect-timeout 20 --retry 3 -A "$UA" \
      -o "$X/$name.osm.pbf.partial" "$GEOFABRIK/$path-$DAY.osm.pbf" \
      && curl --proto "=https" --fail --silent --show-error --connect-timeout 20 --retry 3 -A "$UA" \
        -o "$X/$name.md5" "$GEOFABRIK/$path-$DAY.osm.pbf.md5" \
      && [ "$(md5sum <"$X/$name.osm.pbf.partial" | cut -d' ' -f1)" = "$(cut -d' ' -f1 "$X/$name.md5")" ]; then
      mv "$X/$name.osm.pbf.partial" "$X/$name.osm.pbf"
      rm -f "$X/$name.md5"
      return 0
    fi
    rm -f "$X/$name.osm.pbf.partial" "$X/$name.md5"
    t "$name: attempt $attempt failed"
    [ "$attempt" = 3 ] || sleep 300
  done
  : >"$X/$name.failed"
}

# Fetches the paths given, three at a time (Geofabrik asks for restraint).
# Waits on its own jobs only: the CLI build runs in the background too.
fetch_all() {
  local path pid running
  local -a pids=()
  for path in "$@"; do
    while :; do
      running=0
      for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then running=$((running + 1)); fi
      done
      [ "$running" -lt 3 ] && break
      sleep 2
    done
    fetch "$path" &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do wait "$pid" || true; done
  for path in "$@"; do
    [ ! -e "$X/$(name_of "$path").failed" ] || return 1
  done
}

stamp_of() {
  docker run --rm --volume "$X:/x:ro" lunaway-osmium:build fileinfo \
    -g header.option.osmosis_replication_timestamp "/x/$1.osm.pbf"
}

state "running extracts"
start=$(date +%s)
fetch_all "${paths[@]}" || fail 1 "a download of $DAY failed or did not match its MD5"
t "downloaded in $(($(date +%s) - start)) s"
: >"$RUN/extracts.tsv"
for path in "${paths[@]}"; do
  name=$(name_of "$path")
  printf '%s\t%s\t%s\n' "$name" "$(stat -c %s "$X/$name.osm.pbf")" "$(stamp_of "$name")" >>"$RUN/extracts.tsv"
done
# The files of one day must carry one replication timestamp: merging two
# leaves two versions of the objects changed in between.
if awk -F'\t' '$3 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ { bad = 1 } END { exit !bad }' "$RUN/extracts.tsv"; then
  fail 1 "an extract has no replication timestamp"
fi
newest=$(cut -f3 "$RUN/extracts.tsv" | sort | tail -n 1)
oldest=$(cut -f3 "$RUN/extracts.tsv" | sort | head -n 1)
[ "$newest" = "$oldest" ] || fail 3 "the extracts of $DAY range from $oldest to $newest"
t "every extract at $newest"

state "running merge"
inputs=()
for path in "${paths[@]}"; do inputs+=("/x/$(name_of "$path").osm.pbf"); done
docker run --rm --volume "$X:/x:ro" --volume "$MERGED:/m" \
  lunaway-osmium:build merge "${inputs[@]}" -o /m/europe.osm.pbf --overwrite \
  --output-header="osmosis_replication_timestamp=$newest"
t "merged: $(stat -c %s "$MERGED/europe.osm.pbf") bytes"
for path in "${paths[@]}"; do rm -f "$X/$(name_of "$path").osm.pbf"; done
df -h /

state "running cli"
wait "$cli" || { cat "$RUN/cli-build.log"; fail 1 "the lunaway CLI did not build"; }
cat "$RUN/cli-build.log"

state "running graph"
LUNAWAY_BIN=/root/lunaway/backend/target/release/lunaway LUNAWAY_DATA_DIR=/root/lunaway/data \
  infra/routing/build-graph.sh "$MERGED/europe.osm.pbf" "$OUT" --area eu --threads 8 --refresh-ign
rm -f "$MERGED/europe.osm.pbf"
cp "$OUT/test-routes.txt" "$OUT/prepare.json" "$OUT/build.json" "$RUN/"
cp "$OUT/graph/build.log" "$RUN/graph-build.log" 2>/dev/null || true
df -h /
state "done"
