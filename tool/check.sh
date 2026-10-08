#!/usr/bin/env bash
# The whole Lunaway gate, in one pass. The CI runs the same list; the git hooks
# run the cheap subset at commit and the analyses at push.
#
#   tool/check.sh            # harness, app and backend gates, then both test suites
#   tool/check.sh --fix      # rewrite formatting and regenerate code instead of failing on it
#   tool/check.sh --quick    # everything but the test suites
#
# Every check runs even after an earlier one fails, so one pass shows the whole
# list. Exits non-zero when any of them failed.
set -uo pipefail
cd "$(dirname "$0")/.."
. tool/harness/git/common.sh

FIX=0
QUICK=0
for arg in "$@"; do
  case "$arg" in
    --fix) FIX=1 ;;
    --quick) QUICK=1 ;;
    *) echo "usage: tool/check.sh [--fix] [--quick]" >&2; exit 2 ;;
  esac
done

FAILED=""
run() {
  label="$1"; shift
  echo ""
  echo "==> $label"
  if ! "$@"; then FAILED="$FAILED [$label]"; fi
}
in_app() { (cd app && "$@"); }
in_backend() { (cd backend && "$@"); }
# The app's guidance crate: a workspace of its own, built into the app by
# its build hook.
in_nav() { (cd app/packages/lunaway_nav/rust && "$@"); }

# Generated code is committed; regenerating must not change it. Compares a
# digest of every generated file before and after the generators run.
generated_digests() { find app/lib -name '*.g.dart' -type f | LC_ALL=C sort | xargs shasum 2>/dev/null; }
codegen_fresh() {
  before=$(generated_digests)
  in_app $DART run slang >/dev/null || return 1
  in_app $DART run build_runner build --delete-conflicting-outputs >/dev/null 2>&1 || {
    echo "codegen: build_runner failed; run it in app/ to see why." >&2
    return 1
  }
  after=$(generated_digests)
  if [ "$before" != "$after" ]; then
    changed=$(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | sed -n 's/^> [0-9a-f]*  /  /p')
    if [ "$FIX" -eq 1 ]; then
      echo "codegen: regenerated (commit them):"
      printf '%s\n' "$changed"
      return 0
    fi
    echo "codegen: these generated files were stale and have been regenerated; commit them:" >&2
    printf '%s\n' "$changed" >&2
    return 1
  fi
  echo "codegen: up to date"
}

run "harness wiring" tool/harness/git/check_harness.sh
run "dashes" tool/harness/git/check_dashes.sh --all
run "lockfiles" tool/harness/git/check_lock.sh HEAD
if command -v actionlint >/dev/null 2>&1; then
  run "workflow lint" actionlint
else
  echo "==> workflow lint: skipped (brew install actionlint); the CI runs it"
fi
if command -v python3 >/dev/null 2>&1; then
  run "hook tests" python3 tool/harness/hooks/tests/test_guards.py
  run "liveness tests" python3 tool/harness/hooks/tests/test_agent_liveness.py
  run "web server tests" python3 app/tool/web/test_serve_csp.py
else
  echo "==> hook tests: skipped (no python3)"
fi

if [ -z "$DART" ]; then
  echo "tool/check.sh: no dart toolchain on PATH (install fvm, then \`fvm install\`)" >&2
  FAILED="$FAILED [dart toolchain]"
else
  pinned=$(sed -n 's/.*"flutter": "\([^"]*\)".*/\1/p' .fvmrc)
  have=$($FLUTTER --version 2>/dev/null | sed -n '1s/^Flutter \([^ ]*\).*/\1/p')
  if [ "$have" != "$pinned" ]; then
    echo "Flutter $have on PATH, .fvmrc pins $pinned: run through fvm (\`fvm install\` once)." >&2
    FAILED="$FAILED [flutter toolchain]"
  fi
  run "packages" ensure_packages
  # Generated files stay as their generator wrote them (build_runner does not
  # format to our page width), so the format gate skips them.
  authored=$(find app/lib app/test app/integration_test tool -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' 2>/dev/null | LC_ALL=C sort)
  if [ "$FIX" -eq 1 ]; then
    run "dart format" $DART format $authored
  else
    run "dart format" $DART format --output=none --set-exit-if-changed $authored
  fi
  run "i18n" $DART tool/i18n_check.dart
  run "structure" $DART tool/structure_check.dart
  run "codegen" codegen_fresh
  # dart, not flutter: only `dart analyze` loads the riverpod_lint plugin.
  run "dart analyze" in_app $DART analyze --fatal-infos
  if [ "$QUICK" -eq 0 ]; then
    # The bridge tests load the guidance crate built for this machine; they
    # skip without it.
    if [ -n "$CARGO" ]; then
      run "guidance library" in_nav cargo build --locked --release
    fi
    run "flutter test" in_app $FLUTTER test --no-pub
  fi
fi

if [ -z "$CARGO" ]; then
  echo "tool/check.sh: no cargo on PATH (https://rustup.rs)" >&2
  FAILED="$FAILED [rust toolchain]"
else
  if [ "$FIX" -eq 1 ]; then
    run "cargo fmt" in_backend cargo fmt --all
  else
    run "cargo fmt" in_backend cargo fmt --all -- --check
  fi
  run "structure rs" sh tool/structure_rs.sh
  run "clippy" in_backend cargo clippy --locked --workspace --all-targets -- -D warnings
  if command -v cargo-deny >/dev/null 2>&1; then
    run "cargo deny" in_backend cargo deny --log-level error check bans licenses sources advisories
  else
    echo "==> cargo deny: skipped (cargo install cargo-deny --locked); the CI runs it"
  fi
  if [ "$FIX" -eq 1 ]; then
    run "cargo fmt guidance" in_nav cargo fmt
  else
    run "cargo fmt guidance" in_nav cargo fmt -- --check
  fi
  run "clippy guidance" in_nav cargo clippy --locked --all-targets -- -D warnings
  # The browser runs the same crate compiled to WebAssembly, built from
  # source before each web build (app/packages/lunaway_nav/tool/build_web.sh,
  # the CI's `web` job): it must still compile for that target.
  run "clippy guidance web" in_nav cargo clippy --locked --target wasm32-unknown-unknown -- -D warnings
  if command -v cargo-deny >/dev/null 2>&1; then
    run "cargo deny guidance" cargo deny --manifest-path app/packages/lunaway_nav/rust/Cargo.toml \
      --config backend/deny.toml --log-level error check bans licenses sources advisories
  else
    echo "==> cargo deny guidance: skipped (cargo install cargo-deny --locked)"
  fi
  if [ "$QUICK" -eq 0 ]; then
    run "cargo test guidance" in_nav cargo test --locked
  fi
  if [ "$QUICK" -eq 0 ]; then
    # The database tests need the compose database (backend/compose.yaml).
    export DATABASE_URL="${DATABASE_URL:-postgres://lunaway:lunaway@127.0.0.1:54329/lunaway}"
    # Each test database then starts from the migrated template1 instead of
    # creating PostGIS and running every migration (about ten times faster).
    run "test database template" in_backend sh tool/test-template.sh
    if command -v cargo-nextest >/dev/null 2>&1; then
      run "cargo nextest" in_backend cargo nextest run --locked --workspace --all-targets
    else
      run "cargo test" in_backend cargo test --locked --workspace --all-targets
    fi
  fi
fi

echo ""
if [ -n "$FAILED" ]; then
  echo "FAILED:$FAILED" >&2
  exit 1
fi
echo "tool/check.sh: all green."
