# shellcheck shell=bash
# Helpers of the scripts that run on the server as root (infra/server/*.sh).
# Sourced, never run.
set -euo pipefail
INFRA="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEBIAN_FRONTEND=noninteractive
umask 022
# Rendered files are staged here (fixed names, overwritten on each run, kept
# for inspection) before install_file compares them with the live copy.
STAGING=/var/lib/lunaway-setup
install -d -m 0700 "$STAGING"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }
need_root() { [ "$(id -u)" -eq 0 ] || die "run as root (sudo)"; }

apt_install() {
  apt-get install -y -q --no-install-recommends -o Dpkg::Options::=--force-confold "$@" >/dev/null
}

# install_file SRC DEST MODE: copies SRC (relative to infra/ or absolute) to
# DEST when its content or mode differs. Succeeds only when it changed
# something, so callers write `install_file ... && changed=1`.
install_file() {
  local src="$1" dest="$2" mode="$3"
  case "$src" in /*) ;; *) src="$INFRA/$src" ;; esac
  [ -f "$src" ] || die "missing source file $src"
  if [ -f "$dest" ] && cmp -s "$src" "$dest" && [ "$(stat -c %a "$dest")" = "${mode#0}" ]; then
    return 1
  fi
  # Callers test the status, which turns set -e off in here: a failed copy
  # must still stop the run.
  install -D -m "$mode" -o root -g root "$src" "$dest" || die "cannot install $dest"
  echo "    updated $dest"
}

mem_mb() { awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo; }

# The backend's PostgreSQL cluster, on the root disk's local NVMe since
# 2026-10-10: the data volume, a network disk, took 1.4 ms a read on
# average and up to 1.4 s to commit a transaction (docs/deploy.md,
# "PostgreSQL on the root disk"). postgres.sh creates it there and
# postgres-move.sh brings an older one there.
# shellcheck disable=SC2034 # read by the scripts that source this file
PG_DATADIR=/var/lib/postgresql/18/main

# pg_datadir_dropin OUT: the drop-in of postgresql@18-main that lets the
# sandboxed cluster write its data directory, installed as
# data-directory.conf by postgres.sh and postgres-move.sh. A file of its own,
# so that the sandbox drop-in (lunaway.conf) names no data path.
pg_datadir_dropin() {
  printf '%s\n' \
    "# Written by infra/server/postgres.sh and postgres-move.sh: the data" \
    "# directory, the one path the cluster writes besides its socket and log." \
    "[Service]" \
    "ReadWritePaths=$PG_DATADIR" > "$1"
}

# mount_volume ID MOUNTPOINT: mounts the Hetzner Volume ID there, through
# fstab, nodev,nosuid,noexec. Never formats anything: a volume is created
# formatted (provision.sh, --format ext4), and a volume without a filesystem
# is an error to look at, not a disk to wipe.
mount_volume() {
  local id="$1" mnt="$2" dev uuid fstype other
  [[ "$id" =~ ^[0-9]+$ ]] || die "unexpected volume id $id"
  dev="/dev/disk/by-id/scsi-0HC_Volume_$id"
  [ -b "$dev" ] || die "volume device $dev not found: is the volume attached to this server?"
  uuid="$(blkid -s UUID -o value "$dev" || true)"
  fstype="$(blkid -s TYPE -o value "$dev" || true)"
  [ -n "$uuid" ] && [ "$fstype" = ext4 ] || die "no ext4 filesystem on $dev; refusing to format a volume"

  # Hetzner's automount may have mounted it under /mnt/HC_Volume_<id>.
  other="$(findmnt -n -o TARGET -S "UUID=$uuid" | grep -vx "$mnt" || true)"
  if [ -n "$other" ]; then
    umount "$other"
    sed -i "\|$other|d" /etc/fstab
  fi

  if ! grep -q "^UUID=$uuid " /etc/fstab; then
    echo "UUID=$uuid $mnt ext4 defaults,nofail,nodev,nosuid,noexec,x-systemd.device-timeout=30s 0 2" >> /etc/fstab
    systemctl daemon-reload
    echo "    added $mnt to /etc/fstab"
  fi

  if ! mountpoint -q "$mnt"; then
    install -d -m 0755 "$mnt"
    # An immutable mount point: should the volume ever be missing at boot,
    # writes into it fail instead of quietly filling the root disk.
    chattr +i "$mnt"
    mount "$mnt"
  fi
  chmod 0755 "$mnt"
  systemctl enable --quiet fstrim.timer
  log "volume $id mounted at $mnt ($(df -h --output=size "$mnt" | tail -n 1 | tr -d ' '))"
}

# A random password of 43 characters from [A-Za-z0-9], safe in a URL.
random_password() {
  local pw=""
  while [ "${#pw}" -lt 43 ]; do
    pw="$pw$(head -c 48 /dev/urandom | base64 -w0 | tr -d '+/=')"
  done
  printf '%s' "${pw:0:43}"
}

# The public key format every forced-command account of these scripts accepts.
# shellcheck disable=SC2034 # read by the scripts that source this file
ED25519_PUBKEY_RE='^ssh-ed25519 [A-Za-z0-9+/=]+( [A-Za-z0-9@._-]+)*$'

# fetch_sha512 URL SHA512 FILE: leaves in FILE what URL serves, accepted
# only when it hashes to SHA512. A FILE already there with that hash is kept
# without a download; one with another hash is removed first. A download
# that hashes to anything else is removed and stops the run.
fetch_sha512() {
  local url="$1" want="$2" file="$3" got
  [[ "$want" =~ ^[0-9a-f]{128}$ ]] || die "no SHA-512 pinned for $url"
  if [ -f "$file" ]; then
    [ "$(sha512sum "$file" | awk '{ print $1 }')" = "$want" ] && return 0
    rm -f -- "$file"
  fi
  rm -f -- "$file.download"
  curl -fsSL --retry 3 -m 600 -A "Lunaway infra (+https://lunaway.net)" -o "$file.download" "$url" \
    || { rm -f -- "$file.download"; die "cannot download $url"; }
  got="$(sha512sum "$file.download" | awk '{ print $1 }')"
  if [ "$got" != "$want" ]; then
    rm -f -- "$file.download"
    die "$url hashes to $got, the pin says $want"
  fi
  mv -f -- "$file.download" "$file"
}

# Caddy's apt repository on Cloudsmith, the source of the first
# installations, has answered 402 Payment Required since 2026-10-09
# (github.com/caddyserver/dist/issues/142), which stopped every
# `apt-get update`. This removes its source line, its signing key, and the
# key copy and keyring directory the former installation checked it with;
# apt-get update then drops the repository's lists by itself.
remove_caddy_apt_source() {
  local file
  for file in /etc/apt/sources.list.d/caddy-stable.list /usr/share/keyrings/caddy-stable-archive-keyring.gpg \
    "$STAGING/caddy-gpg.key"; do
    if [ -e "$file" ]; then
      rm -f -- "$file"
      echo "    removed $file"
    fi
  done
  if [ -d /var/lib/lunaway-setup/gnupg ]; then
    rm -rf /var/lib/lunaway-setup/gnupg
    echo "    removed /var/lib/lunaway-setup/gnupg"
  fi
}

# Caddy from the .deb of its official GitHub release, at the version and
# SHA-512 infra/caddy/version.sh pins. The apt preferences keep Debian's own
# caddy package (2.6 in trixie, 2.11.2 in its backports) from ever replacing
# it. An installed package of the pinned version is left alone; another
# version is replaced, and the package's own script then restarts a running
# Caddy.
install_caddy_package() {
  local arch want deb
  . "$INFRA/caddy/version.sh"
  remove_caddy_apt_source
  install_file files/etc/apt/preferences.d/lunaway-caddy /etc/apt/preferences.d/lunaway-caddy 0644 || true
  if [ "$(dpkg-query -W -f '${Status} ${Version}' caddy 2>/dev/null || true)" = "install ok installed $CADDY_VERSION" ]; then
    return 0
  fi
  arch="$(dpkg --print-architecture)"
  case "$arch" in
    amd64) want="$CADDY_DEB_SHA512_AMD64" ;;
    arm64) want="$CADDY_DEB_SHA512_ARM64" ;;
    *) die "no Caddy package pinned for $arch" ;;
  esac
  deb="$STAGING/caddy_${CADDY_VERSION}_linux_$arch.deb"
  fetch_sha512 "https://github.com/caddyserver/caddy/releases/download/v$CADDY_VERSION/caddy_${CADDY_VERSION}_linux_$arch.deb" \
    "$want" "$deb"
  # The Caddyfile is a conffile of the package: ours stays.
  dpkg --force-confdef --force-confold -i "$deb" >/dev/null
  rm -f -- "$deb"
  echo "    installed caddy $CADDY_VERSION ($arch) from its GitHub release"
}
