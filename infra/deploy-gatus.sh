#!/usr/bin/env bash
# Installs the Gatus binary pinned in infra/ops/gatus/version.sh on the
# backend: pulls the official image by digest for the server's architecture,
# copies /gatus out of it (the container is created, never started), checks
# its SHA-256 against the pin, uploads it, and lets
# infra/server/install-gatus.sh check it again and restart the service.
#
#   infra/deploy-gatus.sh
#
# Needs docker (colima on macOS). Configure the backend first
# (infra/configure.sh backend ops-status): it writes Gatus's configuration
# and unit.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$LUNAWAY_INFRA_DIR/ops/gatus/version.sh"
require_host backend
command -v docker >/dev/null || die "docker is needed (colima start)"
docker info >/dev/null 2>&1 || die "the docker daemon does not answer (colima start)"

case "$(host_ssh backend uname -m)" in
  x86_64) platform=linux/amd64; want="$GATUS_SHA256_AMD64" ;;
  aarch64) platform=linux/arm64; want="$GATUS_SHA256_ARM64" ;;
  *) die "unsupported architecture on the backend" ;;
esac
SCRATCH="${LUNAWAY_SCRATCH_DIR:-$LUNAWAY_REPO_DIR/data/tmp/infra}"
install -d -m 0700 "$SCRATCH"

log "Gatus $GATUS_VERSION for $platform from $GATUS_IMAGE"
docker pull -q --platform "$platform" "$GATUS_IMAGE" >/dev/null
# A container left by an interrupted run has the same name: remove it first.
docker rm lunaway-gatus-extract >/dev/null 2>&1 || true
docker create --platform "$platform" --name lunaway-gatus-extract "$GATUS_IMAGE" >/dev/null
docker cp lunaway-gatus-extract:/gatus "$SCRATCH/gatus.bin" >/dev/null
docker rm lunaway-gatus-extract >/dev/null
got="$(shasum -a 256 "$SCRATCH/gatus.bin" | awk '{ print $1 }')"
[ "$got" = "$want" ] || die "the extracted binary hashes to $got, the pin says $want"

log "uploading"
host_ssh backend 'mkdir -p ~/infra/server'
lunaway_scp "$LUNAWAY_INFRA_DIR/server/common.sh" "$LUNAWAY_INFRA_DIR/server/install-gatus.sh" "lunaway:infra/server/"
lunaway_scp "$SCRATCH/gatus.bin" "lunaway:gatus.upload"
host_ssh backend "sudo bash ~/infra/server/install-gatus.sh /home/$LUNAWAY_ADMIN_USER/gatus.upload $want"
