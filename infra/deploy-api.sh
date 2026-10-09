#!/usr/bin/env bash
# Builds lunaway-api and the lunaway CLI for the server's architecture in a
# Debian 13 Rust container (same glibc as the server), uploads them as a new
# release and lets infra/server/install-release.sh switch to it: migrations
# first (as lunaway_owner, the long jobs paused meanwhile by
# infra/server/pause-jobs.sh), then the API, with a rollback when the new
# release does not answer. Ends with a check over HTTPS from this machine.
#
#   infra/deploy-api.sh                          the backend of HEAD
#   LUNAWAY_DEPLOY_REV=<commit> infra/deploy-api.sh
#   LUNAWAY_BUILDER=hetzner infra/deploy-api.sh  the same build on a throwaway
#                                                Hetzner server, without local
#                                                Docker (infra/build/remote-build.sh)
#
# Builds a committed revision (git archive), never the working tree: what
# runs in production is always a commit anyone can check out. Needs docker
# (colima on macOS). The container sees only the scratch directory
# (data/tmp/infra, gitignored), read-only: the sources go in as a tarball,
# the binaries come out with `docker cp`. The toolchain is the one pinned in
# the revision's backend/rust-toolchain.toml, and the image of that toolchain
# is pinned by digest below: a tag of the official image is rebuilt in place
# now and then, a digest never changes.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
require_host
builder="${LUNAWAY_BUILDER:-docker}"
case "$builder" in
  docker)
    command -v docker >/dev/null || die "docker is needed (colima start), or LUNAWAY_BUILDER=hetzner"
    docker info >/dev/null 2>&1 || die "the docker daemon does not answer (colima start), or LUNAWAY_BUILDER=hetzner" ;;
  hetzner) . "$LUNAWAY_INFRA_DIR/build/remote-build.sh" ;;
  *) die "LUNAWAY_BUILDER is docker or hetzner" ;;
esac

SCRATCH="${LUNAWAY_SCRATCH_DIR:-$LUNAWAY_REPO_DIR/data/tmp/infra}"
CONTAINER=lunaway-api-build
rev="$(git -C "$LUNAWAY_REPO_DIR" rev-parse --verify "${LUNAWAY_DEPLOY_REV:-HEAD}^{commit}")"
toolchain="$(git -C "$LUNAWAY_REPO_DIR" show "$rev:backend/rust-toolchain.toml" | sed -n 's/^channel = "\(.*\)"/\1/p')"
# The multi-architecture index of rust:<toolchain>-trixie, per toolchain. A
# new toolchain needs its line: docker buildx imagetools inspect rust:<v>-trixie.
case "$toolchain" in
  1.99.0) rust_digest=sha256:3745c050d12adc738eff16ebfc81ed044bfb2cc27c6828850ff1666beb1c7a49 ;; # 2026-10-06
  *) die "no pinned image digest for Rust $toolchain in $0; add it (docker buildx imagetools inspect rust:$toolchain-trixie)" ;;
esac
RUST_IMAGE="${LUNAWAY_RUST_IMAGE:-rust:$toolchain-trixie@$rust_digest}"

server_arch="$(lunaway_ssh uname -m)"
case "$server_arch" in
  x86_64) target=x86_64-unknown-linux-gnu; cross_pkgs="gcc-x86-64-linux-gnu libc6-dev-amd64-cross"; cross_linker=x86_64-linux-gnu-gcc ;;
  aarch64) target=aarch64-unknown-linux-gnu; cross_pkgs="gcc-aarch64-linux-gnu libc6-dev-arm64-cross"; cross_linker=aarch64-linux-gnu-gcc ;;
  *) die "unsupported server architecture $server_arch" ;;
esac
if [ "$builder" = hetzner ]; then
  builder_arch=x86_64
else
  builder_arch="$(docker info --format '{{.Architecture}}')"
fi
if [ "$builder_arch" = "$server_arch" ]; then
  cross_pkgs=""
  cross_linker=""
fi

release="$(date -u +%Y%m%dT%H%M%SZ)-${rev:0:12}"

log "building lunaway-api for $target in $RUST_IMAGE (builder: $builder_arch), release $release"
install -d -m 0700 "$SCRATCH"
git -C "$LUNAWAY_REPO_DIR" archive --format=tar --output="$SCRATCH/backend-src.tar" "$rev:backend"
cp "$LUNAWAY_INFRA_DIR/build/build-api.sh" "$SCRATCH/build-api.sh"
if [ "$builder" = hetzner ]; then
  [ "$server_arch" = x86_64 ] || die "the Hetzner builder is x86_64; the server is $server_arch"
  remote_build "$RUST_IMAGE" "$target"
else
  # A container left by an interrupted run has the same name: remove it first.
  docker rm lunaway-api-build >/dev/null 2>&1 || true
  docker run --name "$CONTAINER" -v "$SCRATCH:/w:ro" \
    -e TARGET="$target" -e CROSS_PKGS="$cross_pkgs" -e CROSS_LINKER="$cross_linker" \
    "$RUST_IMAGE" bash /w/build-api.sh
  rm -f "$SCRATCH/release/lunaway-api" "$SCRATCH/release/lunaway" "$SCRATCH/glibc"
  install -d -m 0700 "$SCRATCH/release"
  docker cp "$CONTAINER:/out/lunaway-api" "$SCRATCH/release/lunaway-api"
  # The CLI exists from the revisions that carry backend/crates/lunaway-cli on.
  docker cp "$CONTAINER:/out/lunaway" "$SCRATCH/release/lunaway" 2>/dev/null || true
  docker cp "$CONTAINER:/out/glibc" "$SCRATCH/glibc"
  docker rm lunaway-api-build >/dev/null
fi

needed_glibc="$(sed 's/GLIBC_//' "$SCRATCH/glibc")"
server_glibc="$(lunaway_ssh getconf GNU_LIBC_VERSION | awk '{ print $2 }')"
python3 - "$needed_glibc" "$server_glibc" <<'EOF' || die "the binary needs glibc $needed_glibc, the server has $server_glibc"
import sys
need, have = (tuple(int(x) for x in v.split(".")) for v in sys.argv[1:3])
sys.exit(0 if need <= have else 1)
EOF
for bin in "$SCRATCH"/release/*; do
  log "binary $(basename "$bin"): $(du -h "$bin" | cut -f1), $(file -b "$bin" | cut -d, -f1,2)"
done
log "the binaries need glibc $needed_glibc, the server has $server_glibc"

log "uploading release $release"
lunaway_ssh 'mkdir -p ~/infra/server && rm -rf ~/release-upload && mkdir ~/release-upload'
lunaway_scp "$LUNAWAY_INFRA_DIR/server/common.sh" "$LUNAWAY_INFRA_DIR/server/install-release.sh" \
  "$LUNAWAY_INFRA_DIR/server/pause-jobs.sh" "lunaway:infra/server/"
lunaway_scp "$SCRATCH"/release/* "lunaway:release-upload/"
lunaway_ssh "sudo bash ~/infra/server/install-release.sh $release /home/$LUNAWAY_ADMIN_USER/release-upload"

log "checking https://$LUNAWAY_API_HOST from here"
health="$(curl -fsS -m 10 "https://$LUNAWAY_API_HOST/health")"
[ "$health" = ok ] || die "/health answered: $health"
version="$(curl -fsS -m 10 -H 'Content-Type: application/json' -d '{"query":"{ apiVersion }"}' "https://$LUNAWAY_API_HOST/graphql")"
log "/health: $health; apiVersion: $version"
