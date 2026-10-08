#!/usr/bin/env bash
# Checks infra/files/usr/local/sbin/lunaway-unit-result, which keeps how a
# unit's last finished run ended for the health probe, against a scratch
# status directory: a failure and a success are recorded, a run the
# condition skipped leaves the record as it was, a bad name or a missing
# $SERVICE_RESULT is refused, and a result outside the expected letters is
# not written as is. The values of $SERVICE_RESULT are those measured on
# the backend's systemd 257 (2026-10-08).
#
#   infra/tests/unit-result.sh
set -euo pipefail
INFRA="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$INFRA/.." && pwd)"
SCRATCH="${LUNAWAY_SCRATCH_DIR:-$REPO/data/tmp/infra}/unit-result-test"
script="$INFRA/files/usr/local/sbin/lunaway-unit-result"

# A fresh scratch directory each run, emptied by literal names only.
mkdir -p "$SCRATCH"
for f in "$SCRATCH/extcom-import.result" "$SCRATCH/extcom-import.result.new" "$SCRATCH/out"; do
  if [ -e "$f" ]; then rm -f -- "$f"; fi
done

failures=0
# expect NAME WANTED_STATUS SERVICE_RESULT ARG: the exit status.
expect() {
  local name="$1" want="$2" result="$3" got=0
  shift 3
  SERVICE_RESULT="$result" LUNAWAY_STATUS_DIR="$SCRATCH" sh "$script" "$@" > "$SCRATCH/out" 2>&1 || got=$?
  if [ "$got" = "$want" ]; then
    echo "ok   $name: exit $got"
  else
    echo "FAIL $name: exit $got (want $want): $(head -c 200 "$SCRATCH/out" | tr '\n' ' ')"
    failures=$((failures + 1))
  fi
}
# record NAME WANTED: the state and result the file holds ("none" without
# a file).
record() {
  local name="$1" want="$2" got=none
  if [ -e "$SCRATCH/extcom-import.result" ]; then
    got="$(cut -d ' ' -f 1,3 "$SCRATCH/extcom-import.result")"
  fi
  if [ "$got" = "$want" ]; then
    echo "ok   $name: $got"
  else
    echo "FAIL $name: $got (want $want)"
    failures=$((failures + 1))
  fi
}

expect "a skipped first run" 0 exec-condition extcom-import
record "a skipped first run writes nothing" none
expect "a failed run" 0 exit-code extcom-import
record "a failed run is recorded" "failed exit-code"
expect "a skipped retry" 0 exec-condition extcom-import
record "a skipped run leaves the failure" "failed exit-code"
expect "a timed out run" 0 timeout extcom-import
record "a timeout is a failure" "failed timeout"
expect "a run that succeeds" 0 success extcom-import
record "a success clears the failure" "ok success"
expect "an odd result" 0 'exit code; rm' extcom-import
record "an odd result is written as other" "failed other"
expect "no name" 2 success
expect "a name with a slash" 2 success ../etc
expect "no SERVICE_RESULT" 2 "" extcom-import
record "a refused call changes nothing" "failed other"
if [ "$(stat -f '%Lp' "$SCRATCH/extcom-import.result" 2>/dev/null || stat -c '%a' "$SCRATCH/extcom-import.result")" = 644 ]; then
  echo "ok   the record is readable by the probe's user: 644"
else
  echo "FAIL the record's mode is not 644"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all passed"
