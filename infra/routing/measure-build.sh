#!/bin/bash
# Measures a Valhalla graph build: wall time per stage, peak memory of the
# build's cgroup (anonymous and file-backed), peak disk of the work
# directory, size of the graph. This is the evidence behind where the
# weekly build runs (docs/deploy.md, "Routing").
#
#   infra/routing/measure-build.sh <extract.osm.pbf> <name> [threads] [memory cap]
#
# Runs infra/routing/valhalla-build.sh in the pinned Valhalla image, in a
# container named lunaway-routing-measure-<name>, capped at [memory cap]
# (default 16g, the memory of a GitHub-hosted runner) with no swap, so a
# build that needs more is killed inside its own cgroup and touches no other
# container. Work files go to data/tmp/routing/measure-<name>/ (gitignored)
# on the host through a bind mount, not into the Docker VM's disk, so they
# are freed when that directory is removed. Results land in the same
# directory: memory.csv (one sample every 2 s), disk.csv (every 30 s),
# build.log, summary.txt.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
. infra/routing/version.sh

pbf=${1:?usage: measure-build.sh <extract.osm.pbf> <name> [threads] [memory cap]}
name=${2:?usage: measure-build.sh <extract.osm.pbf> <name> [threads] [memory cap]}
threads=${3:-4}
cap=${4:-16g}
case "$name" in
  *[!a-z0-9-]* | "") echo "name: lower-case letters, digits and dashes only" >&2; exit 2 ;;
esac
pbf=$(cd "$(dirname "$pbf")" && pwd)/$(basename "$pbf")
work="$PWD/data/tmp/routing/measure-$name"
container="lunaway-routing-measure-$name"
if [ -e "$work" ]; then
  echo "$work exists: remove it first" >&2
  exit 2
fi
mkdir -p "$work"

docker run --detach --name "$container" \
  --memory "$cap" --memory-swap "$cap" --cpus "$threads" \
  --volume "$pbf:/input/extract.osm.pbf:ro" \
  --volume "$work:/work" \
  --volume "$PWD/infra/routing/valhalla-build.sh:/opt/lunaway/valhalla-build.sh:ro" \
  --entrypoint /bin/bash \
  "$VALHALLA_IMAGE" /opt/lunaway/valhalla-build.sh "$threads" >/dev/null

started=$(date +%s)
echo "seconds,current_bytes,peak_bytes,anon_bytes,file_bytes" >"$work/memory.csv"
echo "seconds,work_kib" >"$work/disk.csv"
tick=0
# memory.peak is the kernel's own high-water mark of the cgroup, page cache
# included; the samples split it into anonymous memory (what a memory cap
# cannot reclaim) and file pages (the memory-mapped work files, which it
# can).
while [ "$(docker inspect --format '{{.State.Running}}' "$container")" = true ]; do
  now=$(( $(date +%s) - started ))
  if stats=$(docker exec "$container" cat /sys/fs/cgroup/memory.current /sys/fs/cgroup/memory.peak /sys/fs/cgroup/memory.stat 2>/dev/null); then
    echo "$stats" | awk -v t="$now" '
      NR == 1 { current = $1 }
      NR == 2 { peak = $1 }
      $1 == "anon" { anon = $2 }
      $1 == "file" { file = $2 }
      END { printf "%s,%s,%s,%s,%s\n", t, current, peak, anon, file }' >>"$work/memory.csv"
  fi
  if [ $((tick % 15)) -eq 0 ]; then
    echo "$now,$(du -sk "$work" | cut -f1)" >>"$work/disk.csv"
  fi
  tick=$((tick + 1))
  sleep 2
done
code=$(docker inspect --format '{{.State.ExitCode}}' "$container")
oom=$(docker inspect --format '{{.State.OOMKilled}}' "$container")
docker rm "$container" >/dev/null

{
  echo "extract: $pbf ($(wc -c <"$pbf" | tr -d ' ') bytes)"
  echo "image: $VALHALLA_IMAGE"
  echo "threads: $threads, memory cap: $cap, exit code: $code, OOM killed: $oom"
  echo "wall time: $(( $(date +%s) - started )) s"
  grep '^stage' "$work/build.log" || true
  awk -F, 'NR > 1 { if ($2 > c) c = $2; if ($3 > p) p = $3; if ($4 > a) a = $4; if ($5 > f) f = $5 }
    END { printf "cgroup memory.peak: %.0f MiB; sampled peaks: current %.0f MiB, anonymous %.0f MiB, file %.0f MiB\n",
      p / 1048576, c / 1048576, a / 1048576, f / 1048576 }' "$work/memory.csv"
  awk -F, 'NR > 1 && $2 > d { d = $2 } END { printf "peak work directory: %.1f GiB\n", d / 1048576 }' "$work/disk.csv"
  ls -l "$work"
} | tee "$work/summary.txt"
