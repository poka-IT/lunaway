#!/bin/sh
# Committed lockfiles resolve from the public registries only.
#
#   - app/pubspec.lock never resolves a package from a local path outside
#     the repository: such a source comes from a gitignored
#     pubspec_overrides.yaml and the CI cannot resolve it. The app's own
#     packages, committed under app/packages/ (lunaway_nav), are the one
#     exception: a relative path into that directory resolves on every
#     clone;
#   - backend/Cargo.lock and the lockfile of the app's guidance crate
#     (app/packages/lunaway_nav/rust/Cargo.lock) never resolve a crate from
#     git: deny.toml refuses unknown git sources, and a git dependency is a
#     reviewed decision that starts in deny.toml, not in the lockfile.
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
  # Package entries sit at two spaces of indent, their `source:` at four and
  # a path's description at six. A path counts as in the repository when it
  # is relative, under packages/ and never climbs (`..`).
  local_pkgs=$(printf '%s\n' "$pub" | awk '
    /^  [^ ]/ { pkg = $1; sub(":", "", pkg); path = ""; relative = 0 }
    /^      path: / { path = $2; gsub("\"", "", path) }
    /^      relative: true$/ { relative = 1 }
    /^    source: path$/ {
      inside = relative && path ~ /^packages\// && path !~ /(^|\/)\.\.(\/|$)/
      if (!inside) print pkg
    }
  ')
  if [ -n "$local_pkgs" ]; then
    echo "BLOCKED: app/pubspec.lock resolves these packages from a local path:" >&2
    printf '%s\n' "$local_pkgs" | sed 's/^/  /' >&2
    echo "That entry comes from a pubspec_overrides.yaml and must not be committed;" >&2
    echo "a package of the app itself lives under app/packages/." >&2
    fail=1
  fi
fi

for lock in backend/Cargo.lock app/packages/lunaway_nav/rust/Cargo.lock; do
  cargo_lock=$(lock_at "$1" "$lock") || continue
  git_crates=$(printf '%s\n' "$cargo_lock" | awk '
    /^name = / { name = $3 }
    /^source = "git\+/ { print name }
  ')
  if [ -n "$git_crates" ]; then
    echo "BLOCKED: $lock resolves these crates from git:" >&2
    printf '%s\n' "$git_crates" | sed 's/^/  /' >&2
    echo "Use a crates.io release, or allow the repository in backend/deny.toml [sources] first, with the reason." >&2
    fail=1
  fi
done
exit $fail
