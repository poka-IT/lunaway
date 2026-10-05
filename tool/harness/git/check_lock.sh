#!/bin/sh
# Committed lockfiles resolve from the public registries only.
#
#   - app/pubspec.lock never resolves a package from a local path: a path
#     source comes from a gitignored pubspec_overrides.yaml and the CI cannot
#     resolve it;
#   - backend/Cargo.lock never resolves a crate from git: deny.toml refuses
#     unknown git sources, and a git dependency is a reviewed decision that
#     starts in deny.toml, not in the lockfile.
#
#   tool/harness/git/check_lock.sh --cached     # the staged locks (pre-commit)
#   tool/harness/git/check_lock.sh <rev>        # the locks of a commit (CI)
set -u
cd "$(git rev-parse --show-toplevel)" || exit 2
fail=0

lock_at() {
  case "$1" in
    --cached)
      git diff --cached --name-only --diff-filter=ACMR | grep -qx "$2" || return 1
      git show ":$2" 2>/dev/null
      ;;
    *) git show "$1:$2" 2>/dev/null ;;
  esac
}

[ -n "${1:-}" ] || { echo "usage: $0 --cached | <rev>" >&2; exit 2; }

if pub=$(lock_at "$1" app/pubspec.lock); then
  # Package entries sit at two spaces of indent, their `source:` at four.
  local_pkgs=$(printf '%s\n' "$pub" | awk '
    /^  [^ ]/ { pkg = $1; sub(":", "", pkg) }
    /^    source: path$/ { print pkg }
  ')
  if [ -n "$local_pkgs" ]; then
    echo "BLOCKED: app/pubspec.lock resolves these packages from a local path:" >&2
    printf '%s\n' "$local_pkgs" | sed 's/^/  /' >&2
    echo "That entry comes from a pubspec_overrides.yaml and must not be committed." >&2
    fail=1
  fi
fi

if cargo_lock=$(lock_at "$1" backend/Cargo.lock); then
  git_crates=$(printf '%s\n' "$cargo_lock" | awk '
    /^name = / { name = $3 }
    /^source = "git\+/ { print name }
  ')
  if [ -n "$git_crates" ]; then
    echo "BLOCKED: backend/Cargo.lock resolves these crates from git:" >&2
    printf '%s\n' "$git_crates" | sed 's/^/  /' >&2
    echo "Use a crates.io release, or allow the repository in backend/deny.toml [sources] first, with the reason." >&2
    fail=1
  fi
fi
exit $fail
