#!/usr/bin/env bash
# Checks infra/files/usr/local/sbin/lunaway-extcom-inbox, the step that takes
# the external community feed from its inbox, against a scratch inbox and a
# stand-in for the CLI that records what it was asked: which feed is
# waiting; that a feed without its checksum file, with a wrong checksum,
# under another name or behind a symbolic link is never imported; that only
# the newest complete feed counts, and every waiting feed in order once a
# delta is among them; that a failed import is tried again; that a feed
# dated ahead of the clock, or a record of a feed newer than the inbox,
# fails the condition instead of skipping.
#
#   infra/tests/extcom-inbox.sh
set -euo pipefail
INFRA="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$INFRA/.." && pwd)"
SCRATCH="${LUNAWAY_SCRATCH_DIR:-$REPO/data/tmp/infra}/extcom-inbox-test"
script="$INFRA/files/usr/local/sbin/lunaway-extcom-inbox"

# A fresh scratch directory each run, emptied by literal names only.
mkdir -p "$SCRATCH/inbox" "$SCRATCH/data" "$SCRATCH/bin"
for f in "$SCRATCH"/inbox/* "$SCRATCH"/data/* "$SCRATCH/calls" "$SCRATCH/fail" "$SCRATCH/elsewhere.jsonl.gz"; do
  if [ -e "$f" ] || [ -L "$f" ]; then rm -f -- "$f"; fi
done
# The stand-in CLI: appends its arguments to calls, fails when told to.
cat > "$SCRATCH/cli" <<EOF
#!/bin/sh
echo "\$*" >> "$SCRATCH/calls"
[ ! -e "$SCRATCH/fail" ]
EOF
chmod 0755 "$SCRATCH/cli"
# A stand-in for util-linux's flock (none on macOS): flock -w SECONDS FILE
# COMMAND...; it records the lock file it was given and runs the command.
cat > "$SCRATCH/bin/flock" <<EOF
#!/bin/sh
[ "\$1" = -w ] || exit 64
echo "lock \$3" >> "$SCRATCH/calls"
shift 3
exec "\$@"
EOF
chmod 0755 "$SCRATCH/bin/flock"

failures=0
run() {
  PATH="$SCRATCH/bin:$PATH" LUNAWAY_EXTCOM_INBOX="$SCRATCH/inbox" LUNAWAY_DATA_DIR="$SCRATCH/data" \
    LUNAWAY_CLI="$SCRATCH/cli" bash "$script" "$@" > "$SCRATCH/out" 2>&1
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
# calls NAME EXPECTED: the feeds the stand-in CLI imported so far, by name.
calls() {
  local got=""
  [ -f "$SCRATCH/calls" ] && got="$(sed -nE 's|^ingest extcom --file .*/||p' "$SCRATCH/calls" | tr '\n' ' ')"
  if [ "$got" = "$2" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1: imported '$got' (want '$2')"
    failures=$((failures + 1))
  fi
}
# feed NAME [CHECKSUM] [delta]: a feed, complete unless "delta", and,
# unless CHECKSUM is "none", its checksum file as the producer writes it
# (its own SHA-256 when CHECKSUM is empty).
feed() {
  local name="$1" sum="${2:-}" complete=true
  [ "${3:-}" = delta ] && complete=false
  printf '{"type":"header","format":"lunaway-extcom-1","complete":%s}\n{"type":"place","id":"%s"}\n' \
    "$complete" "$name" | gzip -c > "$SCRATCH/inbox/$name"
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

feed extcom-20260108T105000Z.jsonl.gz none
expect "a feed without its checksum file waits for it" 1 pending

shasum -a 256 "$I/extcom-20260108T105000Z.jsonl.gz" | sed 's|  .*|  extcom-20260108T105000Z.jsonl.gz|' > "$I/extcom-20260108T105000Z.jsonl.gz.sha256"
expect "with its checksum file, the feed waits" 0 pending
expect "it is imported" 0 import
calls "the CLI imports it" "extcom-20260108T105000Z.jsonl.gz "
if grep -q "^lock $SCRATCH/data/extcom.lock$" "$SCRATCH/calls"; then
  echo "ok   the import holds the lock lunaway-admin's extcom commands take"
else
  echo "FAIL the import does not hold $SCRATCH/data/extcom.lock"
  failures=$((failures + 1))
fi
expect "once imported, nothing waits" 1 pending
expect "a second run imports nothing" 0 import
calls "the CLI is not called again" "extcom-20260108T105000Z.jsonl.gz "

# Two newer complete feeds: only the newest is imported, and the older one
# stays behind for good.
feed extcom-20260109T020000Z.jsonl.gz
feed extcom-20260110T020000Z.jsonl.gz
expect "two newer complete feeds: the newest is imported" 0 import
calls "the older of the two is skipped" "extcom-20260108T105000Z.jsonl.gz extcom-20260110T020000Z.jsonl.gz "
expect "the skipped one never waits after the newer" 1 pending

# A delta among the waiting feeds: every one is imported, in order.
feed extcom-20260110T080000Z.jsonl.gz "" delta
feed extcom-20260110T140000Z.jsonl.gz
expect "a delta waits behind a newer feed: both are imported" 0 import
calls "in order, the delta first" "extcom-20260108T105000Z.jsonl.gz extcom-20260110T020000Z.jsonl.gz extcom-20260110T080000Z.jsonl.gz extcom-20260110T140000Z.jsonl.gz "

# A symbolic link named as a feed is never taken.
printf 'x' | gzip -c > "$SCRATCH/elsewhere.jsonl.gz"
ln -s "$SCRATCH/elsewhere.jsonl.gz" "$I/extcom-20260110T150000Z.jsonl.gz"
shasum -a 256 "$SCRATCH/elsewhere.jsonl.gz" | sed 's|  .*|  extcom-20260110T150000Z.jsonl.gz|' > "$I/extcom-20260110T150000Z.jsonl.gz.sha256"
expect "a symbolic link is not a feed" 1 pending
rm -f -- "$I/extcom-20260110T150000Z.jsonl.gz" "$I/extcom-20260110T150000Z.jsonl.gz.sha256"

# A wrong checksum: refused, the CLI never called, nothing recorded.
feed extcom-20260111T020000Z.jsonl.gz 0000000000000000000000000000000000000000000000000000000000000000
expect "a feed that does not match its checksum is refused" 1 import
calls "the CLI is not called for it" "extcom-20260108T105000Z.jsonl.gz extcom-20260110T020000Z.jsonl.gz extcom-20260110T080000Z.jsonl.gz extcom-20260110T140000Z.jsonl.gz "
expect "it still waits, for a person to look" 0 pending

# A checksum file that names another file.
feed extcom-20260112T020000Z.jsonl.gz
shasum -a 256 "$I/extcom-20260112T020000Z.jsonl.gz" | sed 's|  .*|  ../other.jsonl.gz|' > "$I/extcom-20260112T020000Z.jsonl.gz.sha256"
expect "a checksum file naming another file is refused" 1 import

# A failed import: the feed waits again, and is imported on the next run.
feed extcom-20260113T020000Z.jsonl.gz
: > "$SCRATCH/fail"
expect "a failed import fails the run" 1 import
expect "the feed still waits after a failure" 0 pending
rm -f -- "$SCRATCH/fail"
expect "the next run imports it" 0 import
expect "then nothing waits" 1 pending
if [ "$(cat "$SCRATCH/data/extcom-inbox.last")" = extcom-20260113T020000Z.jsonl.gz ]; then
  echo "ok   the last feed imported is recorded"
else
  echo "FAIL the last feed imported: $(cat "$SCRATCH/data/extcom-inbox.last")"
  failures=$((failures + 1))
fi

# A record newer than every feed of the inbox: the condition fails.
printf 'extcom-20991231T000000Z.jsonl.gz\n' > "$SCRATCH/data/extcom-inbox.last"
expect "a last feed newer than the inbox fails the condition" 255 pending
printf 'extcom-20260113T020000Z.jsonl.gz\n' > "$SCRATCH/data/extcom-inbox.last"

# A feed dated a year ahead of the clock: the condition fails, nothing is
# imported.
ahead="extcom-$(TZ=UTC printf '%(%Y%m%dT%H%M%SZ)T' "$(($(date +%s) + 31536000))").jsonl.gz"
feed "$ahead"
expect "a feed dated ahead of the clock fails the condition" 255 pending
expect "and is not imported" 255 import
rm -f -- "$I/$ahead" "$I/$ahead.sha256"

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
