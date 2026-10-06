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
  install -D -m "$mode" -o root -g root "$src" "$dest"
  echo "    updated $dest"
}

mem_mb() { awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo; }

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

# Caddy from the Caddy project's repository. The signing key is fetched from
# Cloudsmith but accepted only with the primary fingerprint pinned here
# (checked again on every run, without network, against the installed
# keyring); the source line comes from the repository.
CADDY_KEY_FPR=65760C51EDEA2017CEA2CA15155B6D79CA56EA34
CADDY_KEYRING=/usr/share/keyrings/caddy-stable-archive-keyring.gpg

# primary_fingerprints FILE: the primary key fingerprints of a key file,
# armored or not, one per line.
primary_fingerprints() {
  install -d -m 0700 "$STAGING/gnupg"
  gpg --homedir "$STAGING/gnupg" --batch --with-colons --show-keys "$1" 2>/dev/null \
    | awk -F: '$1 == "pub" { want = 1; next } $1 == "fpr" && want { print $10; want = 0 }'
}

install_caddy_package() {
  local changed=0
  if [ "$(primary_fingerprints "$CADDY_KEYRING" 2>/dev/null)" != "$CADDY_KEY_FPR" ]; then
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key -o "$STAGING/caddy-gpg.key"
    [ "$(primary_fingerprints "$STAGING/caddy-gpg.key")" = "$CADDY_KEY_FPR" ] \
      || die "the Caddy signing key from Cloudsmith does not have the pinned fingerprint $CADDY_KEY_FPR"
    gpg --homedir "$STAGING/gnupg" --batch --yes --dearmor -o "$CADDY_KEYRING.new" "$STAGING/caddy-gpg.key"
    chmod 0644 "$CADDY_KEYRING.new"
    mv "$CADDY_KEYRING.new" "$CADDY_KEYRING"
    echo "    installed the Caddy signing key $CADDY_KEY_FPR"
    changed=1
  fi
  install_file files/etc/apt/sources.list.d/caddy-stable.list /etc/apt/sources.list.d/caddy-stable.list 0644 && changed=1
  if [ "$changed" = 1 ] || ! dpkg-query -W -f '${Status}' caddy 2>/dev/null | grep -q 'install ok installed'; then
    apt-get update -q >/dev/null
  fi
  apt_install caddy
}
