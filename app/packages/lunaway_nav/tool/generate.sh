#!/bin/sh
# Regenerates the bridge after a change to rust/src/api/: the Dart side in
# lib/src/rust/ and rust/src/frb_generated.rs.
#
#   sh app/packages/lunaway_nav/tool/generate.sh      # from the repository root
#
# Needs flutter_rust_bridge_codegen 2.13.0, the version the Dart runtime is
# pinned to (`cargo install flutter_rust_bridge_codegen --version 2.13.0
# --locked`, or FRB_CODEGEN=/path/to/it), and the Flutter that .fvmrc pins:
# the codegen formats its output with that SDK's dart.
set -eu
cd "$(dirname "$0")/.."
codegen=${FRB_CODEGEN:-flutter_rust_bridge_codegen}
have=$("$codegen" --version)
if [ "$have" != "flutter_rust_bridge_codegen 2.13.0" ]; then
  echo "generate: found $have; the Dart runtime is pinned to 2.13.0" >&2
  exit 1
fi
pinned=$(sed -n 's/.*"flutter": "\([^"]*\)".*/\1/p' ../../../.fvmrc)
sdk="${FVM_CACHE_PATH:-$HOME/fvm}/versions/$pinned/bin"
if [ ! -x "$sdk/dart" ]; then
  echo "generate: no Flutter $pinned at $sdk (fvm install $pinned)" >&2
  exit 1
fi
# The codegen runs `fvm install` whenever it finds fvm, and that rewrites
# .fvmrc; without fvm on its PATH it uses the pinned SDK's dart directly.
PATH="$sdk:${CARGO_HOME:-$HOME/.cargo}/bin:/usr/bin:/bin" "$codegen" generate
# The codegen formats with its own rustfmt settings; the crate's gate checks
# with the pinned toolchain's.
(cd rust && cargo fmt)
