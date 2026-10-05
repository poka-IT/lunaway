#!/bin/sh
# Shared by the hooks in .githooks/ and by tool/check.sh. Sourced, not run,
# from the repository root.
#
# Toolchain: `fvm` when the repo pins a Flutter version and fvm is on PATH,
# the bare commands otherwise (a CI image, a machine without fvm). A machine
# with neither gets a loud warning and the Dart gates are skipped: the CI
# replays every gate, so a missing local toolchain can delay a defect but
# never let it through.

if command -v fvm >/dev/null 2>&1 && [ -f .fvmrc ]; then
  # In a linked worktree git hands its hooks GIT_DIR, and fvm reads its own
  # SDK cache with git: it would open the worktree's repository instead and
  # crash, which refuses every commit made from a worktree.
  DART="env -u GIT_DIR fvm dart"
  FLUTTER="env -u GIT_DIR fvm flutter"
elif command -v dart >/dev/null 2>&1; then
  DART="dart"
  FLUTTER="flutter"
else
  DART=""
  FLUTTER=""
fi

if command -v cargo >/dev/null 2>&1; then
  CARGO="cargo"
else
  CARGO=""
fi

# Byte pattern for U+2014 (em dash) and U+2013 (en dash), for `LC_ALL=C grep`.
DASH_PATTERN=$(printf '\342\200[\223\224]')

warn() { printf '%s\n' "$*" >&2; }

# `flutter analyze --no-pub` and `flutter test --no-pub` read
# app/.dart_tool/package_config.json as it is. Resolve again when an input is
# newer than the resolution, the rule flutter applies itself when pub is not
# disabled. Runs in a subshell so the caller stays at the root.
ensure_packages() {
  (
    cd app || exit 1
    config=.dart_tool/package_config.json
    for input in pubspec.yaml pubspec.lock pubspec_overrides.yaml; do
      [ -f "$input" ] || continue
      if [ ! -f "$config" ] || [ "$input" -nt "$config" ]; then
        echo "packages: $input is newer than $config, running pub get"
        # pub leaves the file untouched when the resolution did not change,
        # which would rerun pub get on every pass: record that it is current.
        $FLUTTER pub get && touch "$config"
        exit $?
      fi
    done
    echo "packages: resolution up to date"
  )
}

# The machine-local hook of the same name, when the clone has one under
# $GIT_DIR/hooks (a git init template installs identity guards that way).
# Setting core.hooksPath would silence it; chaining keeps it.
chain_local_hook() {
  name="$1"
  shift
  local_hook="$(git rev-parse --git-common-dir)/hooks/$name"
  if [ -x "$local_hook" ]; then
    "$local_hook" "$@" || exit $?
  fi
}
