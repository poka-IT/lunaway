#!/usr/bin/env bash
# Runs inside the Rust container started by infra/deploy-api.sh. The only
# mount is the scratch directory, read-only, at /w: the backend sources come
# in as /w/backend-src.tar, and the results (lunaway-api, and the lunaway CLI
# when the revision has it) stay in the container's /out, which
# deploy-api.sh copies out with `docker cp`; on the Hetzner builder /out is
# a mount of the builder's /root/out (infra/build/remote-build.sh).
#
#   TARGET         Rust target triple of the server
#   CROSS_PKGS     Debian packages of the cross linker, empty for a native build
#   CROSS_LINKER   the cross linker command, empty for a native build
set -euo pipefail
: "${TARGET:?}"

if [ -n "${CROSS_PKGS:-}" ]; then
  apt-get update -qq
  # shellcheck disable=SC2086 # one package per word
  apt-get install -y -qq --no-install-recommends $CROSS_PKGS >/dev/null
  linker_var="CARGO_TARGET_$(echo "$TARGET" | tr 'a-z-' 'A-Z_')_LINKER"
  export "$linker_var=$CROSS_LINKER"
fi

mkdir -p /src /out
tar -xf /w/backend-src.tar -C /src
cd /src
# rust-toolchain.toml pins the toolchain; the image carries the same version.
rustup target add "$TARGET" >/dev/null 2>&1
packages=(-p lunaway-api --bin lunaway-api)
binaries=(lunaway-api)
if [ -d crates/lunaway-cli ]; then
  packages+=(-p lunaway-cli --bin lunaway)
  binaries+=(lunaway)
fi
CARGO_PROFILE_RELEASE_STRIP=symbols cargo build --locked --release "${packages[@]}" --target "$TARGET"
for bin in "${binaries[@]}"; do
  cp "target/$TARGET/release/$bin" "/out/$bin"
done
# The highest glibc symbol version the binaries need (readelf reads any ELF).
for bin in "${binaries[@]}"; do
  readelf -W -V "/out/$bin"
done | grep -o 'GLIBC_[0-9][0-9.]*' | sort -uV | tail -n 1 > /out/glibc
echo "built ${binaries[*]} for $TARGET, needs $(cat /out/glibc)"
