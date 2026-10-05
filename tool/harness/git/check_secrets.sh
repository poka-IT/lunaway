#!/bin/sh
# Key material must never be committed. Cheap, specific patterns: a file
# name that is always a secret, and the token formats this project handles.
#
#   tool/harness/git/check_secrets.sh --cached          # staged changes
#   tool/harness/git/check_secrets.sh <base> <head>     # a range (CI)
set -u
cd "$(git rev-parse --show-toplevel)" || exit 2

case "${1:-}" in
  --cached) diff_args="--cached" ;;
  "") echo "usage: $0 --cached | <base> <head>" >&2; exit 2 ;;
  *) diff_args="$1 ${2:-HEAD}" ;;
esac

# shellcheck disable=SC2086
files=$(git diff $diff_args --name-only --diff-filter=ACMR)
[ -z "$files" ] && exit 0

bad_files=$(echo "$files" | grep -E '(^|/)(\.env|key\.properties|.*\.jks|.*\.keystore|.*\.p8|.*\.p12|.*\.pem|.*\.mobileprovision)$' | grep -v '\.env\.example$' || true)
if [ -n "$bad_files" ]; then
  echo "BLOCKED: these files are secrets and must stay out of git (see .gitignore):" >&2
  echo "$bad_files" | sed 's/^/  /' >&2
  exit 1
fi

# shellcheck disable=SC2086
hits=$(git diff $diff_args -U0 --diff-filter=ACMR --no-color -- . ':(exclude)*.lock' \
  | grep '^+' | grep -v '^+++' \
  | grep -nE -e '-----BEGIN [A-Z ]*PRIVATE KEY' -e 'AIza[0-9A-Za-z_-]{35}' -e 'glpat-[A-Za-z0-9_-]{20,}' -e 'AKIA[0-9A-Z]{16}' -e 'sntrys_[A-Za-z0-9_-]{20,}' -e 'xox[abpr]-[0-9A-Za-z-]{10,}' \
  -e '(api[_-]?key|secret|password|mnemonic)[A-Za-z_]*["'"'"']?\s*[:=]\s*["'"'"'][A-Za-z0-9+/_=-]{24,}["'"'"']' || true)
if [ -n "$hits" ]; then
  echo "BLOCKED: an added line looks like a credential. Move it to the environment or a gitignored file." >&2
  echo "$hits" | head -10 | cut -c1-160 >&2
  echo "(a false positive is silenced by rewording the line, never by --no-verify)" >&2
  exit 1
fi
exit 0
