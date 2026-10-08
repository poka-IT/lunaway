#!/usr/bin/env bash
# Checks infra/files/usr/local/sbin/lunaway-unit-result, which keeps how a
# unit's last finished run ended for the health probe, on a copy pointed at
# a scratch directory: a failure and a success are recorded, a run the
# condition skipped leaves the record as it was, a bad name or a missing
# $SERVICE_RESULT is refused, a result outside the expected letters is not
# written as is, a link planted where the record is written is not
# followed, and a directory that is a link is refused. The values of
# $SERVICE_RESULT are those measured on the backend's systemd 257
# (2026-10-08).
#
#   infra/tests/unit-result.sh
set -euo pipefail
INFRA="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$INFRA/.." && pwd)"
SCRATCH="${LUNAWAY_SCRATCH_DIR:-$REPO/data/tmp/infra}/unit-result-test"
original="$INFRA/files/usr/local/sbin/lunaway-unit-result"

# A fresh scratch directory each run, emptied by literal names only.
mkdir -p "$SCRATCH/records"
for f in "$SCRATCH/records/extcom-import.result" "$SCRATCH/records/extcom-import.result.new" \
  "$SCRATCH/out" "$SCRATCH/target" "$SCRATCH/linked" "$SCRATCH/script" "$SCRATCH/script-linked"; do
  if [ -e "$f" ] || [ -L "$f" ]; then rm -f -- "$f"; fi
done
# The script with its directory moved to the scratch one; the production
# copy takes no directory from its caller.
grep -q '^dir=/var/lib/lunaway-unit-result$' "$original"
sed "s|^dir=/var/lib/lunaway-unit-result\$|dir=$SCRATCH/records|" "$original" > "$SCRATCH/script"
ln -s "$SCRATCH/records" "$SCRATCH/linked"
sed "s|^dir=/var/lib/lunaway-unit-result\$|dir=$SCRATCH/linked|" "$original" > "$SCRATCH/script-linked"

failures=0
# expect NAME WANTED_STATUS SCRIPT SERVICE_RESULT ARG: the exit status.
expect() {
  local name="$1" want="$2" script="$3" result="$4" got=0
  shift 4
  SERVICE_RESULT="$result" sh "$SCRATCH/$script" "$@" > "$SCRATCH/out" 2>&1 || got=$?
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
  if [ -e "$SCRATCH/records/extcom-import.result" ]; then
    got="$(cut -d ' ' -f 1,3 "$SCRATCH/records/extcom-import.result")"
  fi
  if [ "$got" = "$want" ]; then
    echo "ok   $name: $got"
  else
    echo "FAIL $name: $got (want $want)"
    failures=$((failures + 1))
  fi
}

expect "a skipped first run" 0 script exec-condition extcom-import
record "a skipped first run writes nothing" none
expect "a failed run" 0 script exit-code extcom-import
record "a failed run is recorded" "failed exit-code"
expect "a skipped retry" 0 script exec-condition extcom-import
record "a skipped run leaves the failure" "failed exit-code"
expect "a timed out run" 0 script timeout extcom-import
record "a timeout is a failure" "failed timeout"
ln -s "$SCRATCH/target" "$SCRATCH/records/extcom-import.result.new"
expect "a run that succeeds" 0 script success extcom-import
record "a success clears the failure" "ok success"
if [ -e "$SCRATCH/target" ]; then
  echo "FAIL a link planted where the record is written was followed"
  failures=$((failures + 1))
else
  echo "ok   a link planted where the record is written is not followed"
fi
expect "an odd result" 0 script 'exit code; rm' extcom-import
record "an odd result is written as other" "failed other"
expect "no name" 2 script success
expect "a name with a slash" 2 script success ../etc
expect "no SERVICE_RESULT" 2 script "" extcom-import
expect "a directory that is a link" 1 script-linked exit-code extcom-import
record "refused calls change nothing" "failed other"
mode="$(stat -f '%Lp' "$SCRATCH/records/extcom-import.result" 2>/dev/null \
  || stat -c '%a' "$SCRATCH/records/extcom-import.result")"
if [ "$mode" = 644 ]; then
  echo "ok   the record is readable by the probe's user: 644"
else
  echo "FAIL the record's mode is $mode, not 644"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all passed"
