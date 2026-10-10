#!/usr/bin/env bash
# Checks infra/files/usr/local/sbin/lunaway-extcom-erasures, the forced
# command that hands the feed's producer the list of erased authors,
# against a scratch copy of the list (the script's path rewritten to it):
# it prints the list and only the list whatever the client asked, refuses
# a symbolic link in its place, and fails while no list exists.
#
#   infra/tests/extcom-erasures.sh
set -euo pipefail
INFRA="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$INFRA/.." && pwd)"
SCRATCH="${LUNAWAY_SCRATCH_DIR:-$REPO/data/tmp/infra}/extcom-erasures-test"
script="$INFRA/files/usr/local/sbin/lunaway-extcom-erasures"

mkdir -p "$SCRATCH"
for f in "$SCRATCH/erased-authors" "$SCRATCH/other" "$SCRATCH/command" "$SCRATCH/out"; do
  if [ -e "$f" ] || [ -L "$f" ]; then rm -f -- "$f"; fi
done
grep -q '^list=/srv/data/extcom-erasures/erased-authors$' "$script" \
  || { echo "FAIL the script no longer reads /srv/data/extcom-erasures/erased-authors"; exit 1; }
sed "s|^list=.*|list=$SCRATCH/erased-authors|" "$script" > "$SCRATCH/command"
chmod 0755 "$SCRATCH/command"

failures=0
check() {
  # check NAME WANTED_STATUS WANTED_OUTPUT: runs the command as sshd would,
  # with the client's request in SSH_ORIGINAL_COMMAND.
  local name="$1" want="$2" want_out="$3" got=0
  SSH_ORIGINAL_COMMAND="cat /etc/passwd" "$SCRATCH/command" > "$SCRATCH/out" 2>/dev/null || got=$?
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

for f in "$SCRATCH/erased-authors" "$SCRATCH/other" "$SCRATCH/command" "$SCRATCH/out"; do
  if [ -e "$f" ] || [ -L "$f" ]; then rm -f -- "$f"; fi
done
rmdir "$SCRATCH"
[ "$failures" = 0 ] || { echo "$failures failure(s)"; exit 1; }
echo "all ok"
