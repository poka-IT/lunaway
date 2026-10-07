#!/usr/bin/env bash
# Checks infra/files/usr/local/sbin/lunaway-extcom-inbox, the step that takes
# the external community feed from its inbox, against a scratch inbox and a
# stand-in for the CLI that records what it was asked: which feed is
# waiting, that a feed without its checksum file, with a wrong checksum or
# under another name is never imported, that only the newest feed counts,
# and that a failed import is tried again.
#
#   infra/tests/extcom-inbox.sh
set -euo pipefail
INFRA="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$INFRA/.." && pwd)"
SCRATCH="${LUNAWAY_SCRATCH_DIR:-$REPO/data/tmp/infra}/extcom-inbox-test"
script="$INFRA/files/usr/local/sbin/lunaway-extcom-inbox"

# A fresh scratch directory each run, emptied by literal names only.
mkdir -p "$SCRATCH/inbox" "$SCRATCH/data"
for f in "$SCRATCH"/inbox/* "$SCRATCH"/data/* "$SCRATCH/calls" "$SCRATCH/fail"; do
  [ -e "$f" ] && rm -f -- "$f"
done
# The stand-in CLI: appends its arguments to calls, fails when told to.
cat > "$SCRATCH/cli" <<EOF
#!/bin/sh
echo "\$*" >> "$SCRATCH/calls"
[ ! -e "$SCRATCH/fail" ]
EOF
chmod 0755 "$SCRATCH/cli"

failures=0
run() {
  LUNAWAY_EXTCOM_INBOX="$SCRATCH/inbox" LUNAWAY_DATA_DIR="$SCRATCH/data" LUNAWAY_CLI="$SCRATCH/cli" \
    bash "$script" "$@" > "$SCRATCH/out" 2>&1
}
# expect NAME WANTED_STATUS COMMAND...: the exit status of the script.
expect() {
  local name="$1" want="$2" got=0
  shift 2
  run "$@" || got=$?
  if [ "$got" = "$want" ]; then
    echo "ok   $name: exit $got"
  else
    echo "FAIL $name: exit $got (want $want): $(head -c 200 "$SCRATCH/out" | tr '\n' ' ')"
    failures=$((failures + 1))
  fi
}
# calls NAME EXPECTED: what the stand-in CLI was asked, all calls so far.
calls() {
  local got=""
  [ -f "$SCRATCH/calls" ] && got="$(tr '\n' '|' < "$SCRATCH/calls")"
  if [ "$got" = "$2" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1: calls '$got' (want '$2')"
    failures=$((failures + 1))
  fi
}
# feed NAME [CHECKSUM]: a feed and, unless CHECKSUM is "none", its
# checksum file as the producer writes it (its own SHA-256 by default).
feed() {
  local name="$1" sum="${2:-}"
  printf '{"type":"header","n":"%s"}\n' "$name" | gzip -c > "$SCRATCH/inbox/$name"
  [ "$sum" = none ] && return
  [ -n "$sum" ] || sum="$(shasum -a 256 "$SCRATCH/inbox/$name" | cut -d ' ' -f 1)"
  printf '%s  %s\n' "$sum" "$name" > "$SCRATCH/inbox/$name.sha256"
}
I="$SCRATCH/inbox"

expect "empty inbox: nothing waits" 1 pending
expect "empty inbox: import does nothing" 0 import
calls "empty inbox: the CLI is not called" ""

feed test-ardeche-extcom.jsonl.gz
expect "a feed under another name is not taken" 1 pending

feed extcom-20261008T105000Z.jsonl.gz none
expect "a feed without its checksum file waits for it" 1 pending

shasum -a 256 "$I/extcom-20261008T105000Z.jsonl.gz" | sed 's|  .*|  extcom-20261008T105000Z.jsonl.gz|' > "$I/extcom-20261008T105000Z.jsonl.gz.sha256"
expect "with its checksum file, the feed waits" 0 pending
expect "it is imported" 0 import
calls "the CLI imports it by its path" "ingest extcom --file $I/extcom-20261008T105000Z.jsonl.gz|"
expect "once imported, nothing waits" 1 pending
expect "a second run imports nothing" 0 import
calls "the CLI is not called again" "ingest extcom --file $I/extcom-20261008T105000Z.jsonl.gz|"

# Two newer feeds: only the newest is imported, and the older one stays
# behind for good.
feed extcom-20261009T020000Z.jsonl.gz
feed extcom-20261010T020000Z.jsonl.gz
expect "two newer feeds: the newest is imported" 0 import
calls "the older of the two is skipped" "ingest extcom --file $I/extcom-20261008T105000Z.jsonl.gz|ingest extcom --file $I/extcom-20261010T020000Z.jsonl.gz|"
expect "the skipped one never waits after the newer" 1 pending

# A wrong checksum: refused, the CLI never called, nothing recorded.
feed extcom-20261011T020000Z.jsonl.gz 0000000000000000000000000000000000000000000000000000000000000000
expect "a feed that does not match its checksum is refused" 1 import
calls "the CLI is not called for it" "ingest extcom --file $I/extcom-20261008T105000Z.jsonl.gz|ingest extcom --file $I/extcom-20261010T020000Z.jsonl.gz|"
expect "it still waits, for a person to look" 0 pending

# A checksum file that names another file.
feed extcom-20261012T020000Z.jsonl.gz
shasum -a 256 "$I/extcom-20261012T020000Z.jsonl.gz" | sed 's|  .*|  ../other.jsonl.gz|' > "$I/extcom-20261012T020000Z.jsonl.gz.sha256"
expect "a checksum file naming another file is refused" 1 import

# A failed import: the feed waits again, and is imported on the next run.
feed extcom-20261013T020000Z.jsonl.gz
: > "$SCRATCH/fail"
expect "a failed import fails the run" 1 import
expect "the feed still waits after a failure" 0 pending
rm -f -- "$SCRATCH/fail"
expect "the next run imports it" 0 import
expect "then nothing waits" 1 pending
if [ "$(cat "$SCRATCH/data/extcom-inbox.last")" = extcom-20261013T020000Z.jsonl.gz ]; then
  echo "ok   the last feed imported is recorded"
else
  echo "FAIL the last feed imported: $(cat "$SCRATCH/data/extcom-inbox.last")"
  failures=$((failures + 1))
fi

# An inbox that cannot be read fails the condition instead of skipping.
got=0
LUNAWAY_EXTCOM_INBOX="$SCRATCH/missing" LUNAWAY_DATA_DIR="$SCRATCH/data" bash "$script" pending > /dev/null 2>&1 || got=$?
if [ "$got" = 255 ]; then
  echo "ok   an inbox that cannot be read: exit 255"
else
  echo "FAIL an inbox that cannot be read: exit $got (want 255)"
  failures=$((failures + 1))
fi

echo "$failures failure(s)"
[ "$failures" = 0 ]
