#!/bin/sh
# Builds the guidance crate for the browser: WebAssembly plus the
# wasm-bindgen glue that flutter_rust_bridge's web bindings call, written to
# app/web/lunaway_nav/, which the web build copies as it is.
#
#   sh app/packages/lunaway_nav/tool/build_web.sh            # build, then stamp
#   sh app/packages/lunaway_nav/tool/build_web.sh --check    # is the build current?
#   sh app/packages/lunaway_nav/tool/build_web.sh --verify   # does it rebuild byte for byte?
#
# Rebuild after any change to the crate, its Cargo.lock or the backend's
# domain crate it reuses: the stamp (SOURCES.sha256) records what the build
# came from, and --check (run by tool/check.sh) fails when a source moved
# since. A stale build would also fail at run time: flutter_rust_bridge
# compares the content hash of both sides and the web app then guides
# nowhere.
#
# The stamp alone does not tie the committed binary to the sources: anyone
# can write both. --verify (run by the CI) builds again in a scratch
# directory and compares the files byte for byte. The paths of this machine
# are mapped to fixed ones (--remap-path-prefix) so the build does not
# depend on where the repository and the cargo registry lie, and the
# maintainer's account name does not ship in a public file.
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

sources_hash() {
  (
    cd "$repo"
    {
      find app/packages/lunaway_nav/rust/src backend/crates/lunaway-domain/src \
        backend/crates/lunaway-domain/data backend/crates/lunaway-domain/words -type f
      printf '%s\n' app/packages/lunaway_nav/rust/Cargo.toml app/packages/lunaway_nav/rust/Cargo.lock \
        app/packages/lunaway_nav/rust/rust-toolchain.toml backend/Cargo.toml \
        backend/crates/lunaway-domain/Cargo.toml
    } | LC_ALL=C sort | while read -r f; do
      shasum -a 256 "$f"
    done | shasum -a 256 | cut -d' ' -f1
  )
}

# Paths written into the binary (panic locations), the same on every machine.
registry="${CARGO_HOME:-$HOME/.cargo}/registry/src"
remap="--remap-path-prefix=$registry=/cargo/registry --remap-path-prefix=$repo=/lunaway"
if [ -n "${RUSTUP_HOME:-}" ] || [ -d "$HOME/.rustup" ]; then
  remap="$remap --remap-path-prefix=${RUSTUP_HOME:-$HOME/.rustup}=/rustup"
fi

if [ "${1:-}" = --check ]; then
  want=$(sources_hash)
  have=$(cat "$out/SOURCES.sha256" 2>/dev/null || echo none)
  if [ "$want" != "$have" ]; then
    echo "build_web: app/web/lunaway_nav/ was built from other sources than the crate's;" >&2
    echo "run: sh app/packages/lunaway_nav/tool/build_web.sh" >&2
    exit 1
  fi
  exit 0
fi

bindgen=${WASM_BINDGEN:-wasm-bindgen}
locked=$(awk '/^name = "wasm-bindgen"$/ { getline; gsub(/version = |"/, ""); print; exit }' "$crate/Cargo.lock")
have=$("$bindgen" --version | cut -d' ' -f2)
if [ "$have" != "$locked" ]; then
  echo "build_web: wasm-bindgen $have, Cargo.lock has $locked" >&2
  echo "run: cargo install wasm-bindgen-cli --version $locked --locked" >&2
  exit 1
fi

if [ "${1:-}" = --verify ]; then
  out="$crate/target/web-verify"
  rm -f "$out/lunaway_nav.js" "$out/lunaway_nav_bg.wasm"
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
if [ "${1:-}" = --verify ]; then
  committed="$repo/app/web/lunaway_nav"
  for f in lunaway_nav.js lunaway_nav_bg.wasm; do
    if ! cmp -s "$out/$f" "$committed/$f"; then
      echo "build_web: app/web/lunaway_nav/$f is not what the crate builds to;" >&2
      echo "run: sh app/packages/lunaway_nav/tool/build_web.sh" >&2
      exit 1
    fi
  done
  echo "build_web: app/web/lunaway_nav/ rebuilds byte for byte"
  exit 0
fi
sources_hash > "$out/SOURCES.sha256"
ls -l "$out"
