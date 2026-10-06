#!/bin/sh
# No em dash (U+2014) or en dash (U+2013) in the repository.
#
#   tool/harness/git/check_dashes.sh --all             # every tracked text file (CI, tool/check.sh)
#   tool/harness/git/check_dashes.sh --cached          # lines staged for commit
#   tool/harness/git/check_dashes.sh <base> <head>     # lines added in a range
#
# The tree carries none, so --all is the reference check; the two diff forms
# exist for the hooks, where only the change at hand is at stake. Binary
# files, lock files, generated code (regenerated from sources we do not
# author) and the hook sources (which spell the code points as escapes) are
# skipped, and so are the third-party files listed in tool/harness/vendored.txt.
set -u
cd "$(git rev-parse --show-toplevel)" || exit 2
DASH_PATTERN=$(printf '\342\200[\223\224]')
VENDORED=tool/harness/vendored.txt

# Drops the paths listed in $VENDORED (third-party files as published) from a
# list of paths on stdin.
skip_vendored() {
  awk -v list="$VENDORED" '
    BEGIN { while ((getline line < list) > 0) if (line !~ /^#/ && line != "") v[++n] = line }
    { for (i = 1; i <= n; i++) if (index($0, v[i]) == 1) next; print }'
}

if [ "${1:-}" = "--all" ]; then
  hits=$(git ls-files -z \
    | tr '\0' '\n' \
    | grep -vE '\.(lock|png|jpg|jpeg|gif|svg|pdf|ico|woff|woff2|ttf|zip|jar|keystore|p12|mobileprovision|gguf|bin|webp|mp3|wav|dylib|so|a)$' \
    | grep -v '^tool/harness/hooks/' \
    | grep -vE '\.g\.dart$|\.graphql\.dart$|\.freezed\.dart$|^LICENSE$|^schema/lunaway\.graphql$' \
    | skip_vendored \
    | LC_ALL=C xargs grep -nI -e "$DASH_PATTERN" 2>/dev/null)
  if [ -n "$hits" ]; then
    echo "BLOCKED: em or en dashes in tracked files. Use a comma, a colon, a period, parentheses, or reword." >&2
    echo "$hits" | head -20 | cut -c1-200 >&2
    exit 1
  fi
  echo "dashes: none in tracked files"
  exit 0
fi

case "${1:-}" in
  --cached) diff_args="--cached" ;;
  "") echo "usage: $0 --all | --cached | <base> <head>" >&2; exit 2 ;;
  *) diff_args="$1 ${2:-HEAD}" ;;
esac

set -- . ':(exclude)*.lock' ':(exclude)*.png' ':(exclude)*.jpg' ':(exclude)*.svg' ':(exclude)*.pdf'
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  set -- "$@" ":(exclude)$line"
done < "$VENDORED"
# shellcheck disable=SC2086
hits=$(git diff $diff_args -U0 --diff-filter=ACMR --no-color -- "$@" \
  | awk '/^\+\+\+ /{f=substr($2,3); next} /^@@/{split($3,a,","); n=substr(a[1],2); next} /^\+/{print f ":" n ": " substr($0,2); n++}' \
  | LC_ALL=C grep -e "$DASH_PATTERN")

if [ -n "$hits" ]; then
  echo "BLOCKED: an em dash or en dash is being added. Use a comma, a colon, a period, parentheses, or reword." >&2
  echo "$hits" | head -20 | cut -c1-200 >&2
  exit 1
fi
exit 0
