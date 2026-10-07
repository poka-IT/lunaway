#!/bin/sh
# Builds the guidance crate for the browser: WebAssembly plus the
# wasm-bindgen glue that flutter_rust_bridge's web bindings call, written to
# app/web/lunaway_nav/, which the web build copies as it is.
#
#   sh app/packages/lunaway_nav/tool/build_web.sh
#
# The output is a build product and is not committed (app/.gitignore): a
# binary built on the maintainer's Mac did not rebuild byte for byte on the
# Linux CI, so a committed copy could not be tied to its sources. Every web
# build makes it from source instead: infra/deploy-web.sh before a deploy,
# the CI's `web` job, and anyone running the app in a browser. Run it again
# after any change to the crate, its Cargo.lock or the backend's domain
# crate it reuses: flutter_rust_bridge compares the content hash of both
# sides, and with a stale build the web app guides nowhere.
#
# The paths of this machine are mapped to fixed ones (--remap-path-prefix)
# so the account name of whoever builds it does not ship in a public file
# (panic locations carry source paths).
#
# Needs the pinned toolchain's wasm32-unknown-unknown target (rustup installs
# it from rust-toolchain.toml) and wasm-bindgen-cli at the version of
# Cargo.lock: `cargo install wasm-bindgen-cli --version <it> --locked`.
#
# No threads (no atomics, no shared memory): the app only makes synchronous
# calls, so the module runs on the page's own thread and the site needs no
# cross-origin isolation. This builds with the stable toolchain, where
# flutter_rust_bridge's own `build-web` needs a nightly one.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
repo=$(cd "$here/../../.." && pwd)
crate="$here/rust"
out="$repo/app/web/lunaway_nav"

registry="${CARGO_HOME:-$HOME/.cargo}/registry/src"
remap="--remap-path-prefix=$registry=/cargo/registry --remap-path-prefix=$repo=/lunaway"
if [ -n "${RUSTUP_HOME:-}" ] || [ -d "$HOME/.rustup" ]; then
  remap="$remap --remap-path-prefix=${RUSTUP_HOME:-$HOME/.rustup}=/rustup"
fi

bindgen=${WASM_BINDGEN:-wasm-bindgen}
locked=$(awk '/^name = "wasm-bindgen"$/ { getline; gsub(/version = |"/, ""); print; exit }' "$crate/Cargo.lock")
if ! command -v "$bindgen" >/dev/null 2>&1; then
  echo "build_web: wasm-bindgen not found" >&2
  echo "run: cargo install wasm-bindgen-cli --version $locked --locked" >&2
  exit 1
fi
have=$("$bindgen" --version | cut -d' ' -f2)
if [ "$have" != "$locked" ]; then
  echo "build_web: wasm-bindgen $have, Cargo.lock has $locked" >&2
  echo "run: cargo install wasm-bindgen-cli --version $locked --locked" >&2
  exit 1
fi

(cd "$crate" && RUSTFLAGS="$remap" cargo build --locked --release --target wasm32-unknown-unknown)
mkdir -p "$out"
"$bindgen" "$crate/target/wasm32-unknown-unknown/release/lunaway_nav.wasm" \
  --out-dir "$out" --target no-modules --no-typescript
# The glue declares the module with `let`, which a classic script keeps off
# `window`; flutter_rust_bridge looks it up there. `var` puts it there
# without the eval its own loader would need.
glue="$out/lunaway_nav.js"
if ! head -n 1 "$glue" | grep -q '^let wasm_bindgen = '; then
  echo "build_web: unexpected first line in $glue" >&2
  exit 1
fi
sed '1s/^let wasm_bindgen = /var wasm_bindgen = /' "$glue" > "$glue.tmp"
mv "$glue.tmp" "$glue"
ls -l "$out"
