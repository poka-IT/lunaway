# shellcheck shell=bash
# Sourced by infra/deploy-api.sh when LUNAWAY_BUILDER=hetzner: the same build
# (infra/build/build-api.sh in the pinned Rust image) on a throwaway Hetzner
# server instead of the local Docker, for a machine whose Docker does not
# work (the maintainer's Mac on 2026-10-06). The builder is a cx33 in fsn1
# (x86_64, the backend's architecture, so no cross linker), labelled
# project=lunaway,managed-by=claude,purpose=build, behind the backend's
# firewall (SSH from the admin sources only), and is deleted when the build
# ends, failed or not. A build costs well under a cent (0.0136 EUR excl. VAT
# an hour on 2026-10-06).
#
# Third-party build code (crates' build scripts) runs there, never on a
# production server.
#
# The binaries that come back go to production, so the builder is
# authenticated: its ed25519 host key is generated here for each build,
# handed over by cloud-init, and pinned before the first connection
# (StrictHostKeyChecking=yes). Trust on first use would accept whoever
# answers first, at every deploy, from whatever network this machine is on.
#
# LUNAWAY_BUILDER_IPV6=1 creates the builder without an IPv4 address: the
# project holds few, and throwaway servers can take them all ("Primary IP
# limit exceeded" on 2026-10-07). Everything the build reaches (Docker Hub,
# Debian, crates.io) answers over IPv6, and so must this machine.
# LUNAWAY_BUILDER_TYPE picks another server type than the cx33, a ccx23
# when the project's shared vCPUs are all taken (dedicated ones count
# apart; 0.118 EUR an hour excl. VAT on 2026-10-07).

BUILDER_NAME=lunaway-builder-1

builder_cleanup() {
  if hcloud server describe "$BUILDER_NAME" >/dev/null 2>&1; then
    hcloud server delete "$BUILDER_NAME" >/dev/null && log "builder $BUILDER_NAME deleted"
  fi
  rm -f "$SCRATCH/builder_known_hosts" "$SCRATCH/builder_host_ed25519" \
    "$SCRATCH/builder_host_ed25519.pub" "$SCRATCH/builder-user-data.yaml"
}

# remote_build RUST_IMAGE TARGET: leaves the binaries in $SCRATCH/release/
# and the glibc they need in $SCRATCH/glibc, like the local build.
remote_build() {
  local image="$1" target="$2" ip host
  local -a ssh_opts
  require_hcloud
  [ -n "${LUNAWAY_SSH_KEY_NAME:-}" ] && [ -n "${LUNAWAY_SSH_IDENTITY:-}" ] || die "LUNAWAY_SSH_KEY_NAME and LUNAWAY_SSH_IDENTITY are needed"
  if hcloud server describe "$BUILDER_NAME" >/dev/null 2>&1; then
    die "$BUILDER_NAME already exists: another build runs, or one was left; check, then hcloud server delete $BUILDER_NAME"
  fi
  trap builder_cleanup EXIT
  install -d -m 0700 "$SCRATCH"
  rm -f "$SCRATCH/builder_host_ed25519" "$SCRATCH/builder_host_ed25519.pub" "$SCRATCH/builder_known_hosts"
  ssh-keygen -q -t ed25519 -N "" -C "$BUILDER_NAME" -f "$SCRATCH/builder_host_ed25519"
  (
    umask 077
    {
      echo "#cloud-config"
      echo "ssh_keys:"
      echo "  ed25519_private: |"
      sed 's/^/    /' "$SCRATCH/builder_host_ed25519"
      echo "  ed25519_public: $(cat "$SCRATCH/builder_host_ed25519.pub")"
    } >"$SCRATCH/builder-user-data.yaml"
  )
  local -a family=()
  [ "${LUNAWAY_BUILDER_IPV6:-0}" = 1 ] && family=(--without-ipv4)
  local type="${LUNAWAY_BUILDER_TYPE:-cx33}"
  log "creating the builder $BUILDER_NAME ($type, fsn1${family[*]:+, IPv6 only})"
  hcloud server create --name "$BUILDER_NAME" --type "$type" --location fsn1 --image debian-13 \
    --ssh-key "$LUNAWAY_SSH_KEY_NAME" --firewall lunaway-backend-fw "${family[@]}" \
    --user-data-from-file "$SCRATCH/builder-user-data.yaml" \
    --label project=lunaway --label managed-by=claude --label purpose=build >/dev/null
  rm -f "$SCRATCH/builder_host_ed25519" "$SCRATCH/builder-user-data.yaml"
  if [ ${#family[@]} -gt 0 ]; then
    ip="$(hcloud server ip -6 "$BUILDER_NAME")"
    # scp reads an IPv6 address only between brackets.
    host="[$ip]"
  else
    ip="$(hcloud server ip "$BUILDER_NAME")"
    host="$ip"
  fi
  echo "$ip $(cut -d' ' -f1,2 "$SCRATCH/builder_host_ed25519.pub")" >"$SCRATCH/builder_known_hosts"
  # -F /dev/null: nothing from the user's SSH configuration (agent
  # forwarding, another identity) reaches the builder.
  ssh_opts=(-F /dev/null -o IdentitiesOnly=yes -i "$LUNAWAY_SSH_IDENTITY" -o BatchMode=yes -o ConnectTimeout=10
    -o UserKnownHostsFile="$SCRATCH/builder_known_hosts" -o StrictHostKeyChecking=yes
    -o HostKeyAlgorithms=ssh-ed25519)
  for _ in $(seq 1 60); do
    ssh "${ssh_opts[@]}" "root@$ip" true 2>/dev/null && break
    sleep 5
  done
  ssh "${ssh_opts[@]}" "root@$ip" 'cloud-init status --wait >/dev/null; apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends podman >/dev/null && mkdir -p /root/w /root/out' \
    || die "the builder could not install podman"
  scp -q "${ssh_opts[@]}" "$SCRATCH/backend-src.tar" "$SCRATCH/build-api.sh" "root@$host:/root/w/"
  log "building on the builder"
  # Podman refuses a reference with both a tag and a digest: the digest alone.
  # The results land in /root/out through a mount: `podman cp` out of the
  # exited container found no /out on a ccx23 on 2026-10-07.
  # Podman's default bridge has no IPv6: on a builder without IPv4 the build
  # reaches crates.io through the host's network.
  local net=""
  [ ${#family[@]} -gt 0 ] && net="--network host"
  ssh "${ssh_opts[@]}" "root@$ip" "podman run --name lunaway-api-build $net -v /root/w:/w:ro -v /root/out:/out -e TARGET=$target -e CROSS_PKGS= -e CROSS_LINKER= docker.io/library/rust@${image##*@} bash /w/build-api.sh" \
    || die "the build failed on the builder"
  rm -f "$SCRATCH/release/lunaway-api" "$SCRATCH/release/lunaway" "$SCRATCH/glibc"
  install -d -m 0700 "$SCRATCH/release"
  scp -q "${ssh_opts[@]}" "root@$host:/root/out/lunaway-api" "$SCRATCH/release/lunaway-api"
  scp -q "${ssh_opts[@]}" "root@$host:/root/out/lunaway" "$SCRATCH/release/lunaway" 2>/dev/null || true
  scp -q "${ssh_opts[@]}" "root@$host:/root/out/glibc" "$SCRATCH/glibc"
  builder_cleanup
  trap - EXIT
}
