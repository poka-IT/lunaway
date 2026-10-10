#!/usr/bin/env bash
# Checks infra/files/usr/local/sbin/lunaway-extcom-erasures, the forced
# command that hands the feed's producer the list of erased authors,
# against a scratch copy of the list (the script's path rewritten to it):
# it prints the list and only the list whatever the client asked, and
# refuses, at once, a symbolic link, a named pipe or a file longer than any
# list in its place, and fails while no list exists.
#
#   infra/tests/extcom-erasures.sh
set -euo pipefail
INFRA="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$INFRA/.." && pwd)"
SCRATCH="${LUNAWAY_SCRATCH_DIR:-$REPO/data/tmp/infra}/extcom-erasures-test"
script="$INFRA/files/usr/local/sbin/lunaway-extcom-erasures"

clean() {
  for f in "$SCRATCH/erased-authors" "$SCRATCH/other" "$SCRATCH/command" "$SCRATCH/out"; do
    if [ -e "$f" ] || [ -L "$f" ] || [ -p "$f" ]; then rm -f -- "$f"; fi
  done
}
mkdir -p "$SCRATCH"
clean
grep -q '^LIST = "/srv/data/extcom-erasures/erased-authors"$' "$script" \
  || { echo "FAIL the script no longer reads /srv/data/extcom-erasures/erased-authors"; exit 1; }
sed "s|^LIST = .*|LIST = \"$SCRATCH/erased-authors\"|" "$script" > "$SCRATCH/command"

failures=0
check() {
  # check NAME WANTED_STATUS WANTED_OUTPUT: runs the command as sshd would,
  # with the client's request in SSH_ORIGINAL_COMMAND; a hang fails.
  local name="$1" want="$2" want_out="$3" got=0
  # No timeout(1) on macOS: Python's own, exit 124 on a hang.
  SSH_ORIGINAL_COMMAND="cat /etc/passwd" python3 -c '
import subprocess, sys
try:
    sys.exit(subprocess.run(sys.argv[1:], timeout=10).returncode)
except subprocess.TimeoutExpired:
    sys.exit(124)' python3 -I "$SCRATCH/command" > "$SCRATCH/out" 2>/dev/null || got=$?
  if [ "$got" = "$want" ] && [ "$(cat "$SCRATCH/out")" = "$want_out" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: exit $got (want $want), printed $(head -c 200 "$SCRATCH/out" | tr '\n' ' ')"
    failures=$((failures + 1))
  fi
}

check "no list yet" 1 ""
a=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
b=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
printf '%s\n%s\n' "$a" "$b" > "$SCRATCH/erased-authors"
check "the list, whatever the client asked" 0 "$(printf '%s\n%s' "$a" "$b")"
: > "$SCRATCH/erased-authors"
check "an empty list" 0 ""
rm -f -- "$SCRATCH/erased-authors"
echo "not the list" > "$SCRATCH/other"
ln -s "$SCRATCH/other" "$SCRATCH/erased-authors"
check "a symbolic link in its place" 1 ""
rm -f -- "$SCRATCH/erased-authors"
mkfifo "$SCRATCH/erased-authors"
check "a named pipe in its place, without waiting on it" 1 ""
rm -f -- "$SCRATCH/erased-authors"
python3 -c "import sys; sys.stdout.write('$a\n' * 100001)" > "$SCRATCH/erased-authors"
check "a file longer than any list" 1 ""

clean
rmdir "$SCRATCH"
[ "$failures" = 0 ] || { echo "$failures failure(s)"; exit 1; }
echo "all ok"
