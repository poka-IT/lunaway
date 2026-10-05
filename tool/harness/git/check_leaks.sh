#!/bin/sh
# No term of the untracked `.leak-denylist` in what is about to be committed.
#
#   tool/harness/git/check_leaks.sh --cached          # lines staged for commit
#   tool/harness/git/check_leaks.sh --message <file>  # a commit message
#
# The list lives outside git on purpose: it names what must never be written
# in this public repository, so it cannot be committed itself. One term per
# line, matched case-insensitively as a plain substring. Without the file (a
# fresh clone, the CI) the check passes: it guards the machines that know
# the terms.
set -u
cd "$(git rev-parse --show-toplevel)" || exit 2
list=.leak-denylist
[ -s "$list" ] || exit 0

case "${1:-}" in
  --cached)
    hits=$(git diff --cached -U0 --diff-filter=ACMR --no-color -- . \
      | awk '/^\+\+\+ /{f=substr($2,3); next} /^\+/{print f ": " substr($0,2)}' \
      | grep -i -F -f "$list" || true)
    what="a staged line"
    ;;
  --message)
    hits=$(grep -v '^#' "${2:-/dev/null}" | grep -i -F -f "$list" || true)
    what="the commit message"
    ;;
  *) echo "usage: $0 --cached | --message <file>" >&2; exit 2 ;;
esac

if [ -n "$hits" ]; then
  echo "BLOCKED: $what contains a term listed in .leak-denylist; it must never appear in this repository." >&2
  echo "Use the generic name (.claude/rules/data-sources.md). Lines:" >&2
  printf '%s\n' "$hits" | head -10 | cut -c1-160 >&2
  exit 1
fi
exit 0
