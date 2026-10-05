#!/bin/sh
# Runs a hook with whichever Python this machine has (python3, python, or the
# Windows launcher). Exit 1 rather than 0 when none works, so the gap shows
# up as a hook error in the transcript instead of silently disarming the
# guards; exit 2 would block every tool call on a machine without Python.
for p in python3 python; do
  "$p" -c "" >/dev/null 2>&1 && exec "$p" "$@"
done
py -3 -c "" >/dev/null 2>&1 && exec py -3 "$@"
echo "harness: no usable Python, guard skipped" >&2
exit 1
