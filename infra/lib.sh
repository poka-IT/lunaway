# shellcheck shell=bash
# shellcheck disable=SC2034 # the settings are read by the scripts that source this file
# Shared settings and helpers of the local infra scripts. Sourced, never run.
#
# One server, role "backend": lunaway-backend-1 runs the API, PostgreSQL +
# PostGIS, Caddy, the data pipeline (lunaway CLI), the routing engine, the
# basemap, the geocoders (Photon), the translation server, the status page
# (Gatus) and the external community feed's crawler, which talk to each other
# on the loopback. It replaced three servers on 2026-10-10 (docs/deploy.md,
# "Sizing"). The Mac pulls the encrypted dumps from it with a key forced to a
# read-only rsync (infra/server/ops-access.sh).
#
# Private values live in ~/.config/lunaway/env, outside the repository, so this
# public tree names no account, no address and no key:
#
#   LUNAWAY_HCLOUD_CONTEXT    hcloud CLI context of the Hetzner project (required)
#   LUNAWAY_SSH_KEY_NAME      name of the admin public key in that project
#   LUNAWAY_SSH_PUBKEY        its public key file, uploaded when missing
#   LUNAWAY_SSH_IDENTITY      the matching private key on this machine (never read)
#   LUNAWAY_SSH_ALLOW         CIDRs allowed to reach 22/tcp (written by ssh-access.sh)
#   LUNAWAY_BACKUP_RECIPIENT  age public key the dumps are encrypted to; its
#                             private half exists only on the maintainer's Mac
#                             (written by infra/ops/mac/install.sh)
#   LUNAWAY_API_HOST, LUNAWAY_TILES_URL, LUNAWAY_WEB_URL, LUNAWAY_STATUS_DOMAIN,
#   LUNAWAY_MEDIA_BASE_URL    the public names, optional: the lunaway.net
#                             names below unless set (docs/deploy.md, "The domain")
#   LUNAWAY_BACKEND_IPV4/_IPV6/_VOLUME_ID
#                             written by provision.sh

LUNAWAY_INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUNAWAY_REPO_DIR="$(cd "$LUNAWAY_INFRA_DIR/.." && pwd)"
LUNAWAY_CONFIG_DIR="${LUNAWAY_CONFIG_DIR:-$HOME/.config/lunaway}"
LUNAWAY_ENV_FILE="$LUNAWAY_CONFIG_DIR/env"
LUNAWAY_SSH_CONFIG="$LUNAWAY_CONFIG_DIR/ssh_config"

# shellcheck disable=SC1090
[ -f "$LUNAWAY_ENV_FILE" ] && . "$LUNAWAY_ENV_FILE"

# The public names every script checks and renders (docs/deploy.md, "The
# domain"): the API, its photos, the basemap, the website and the status
# page, all on the backend. They are public, so they live here; the env file
# may still override one for a test setup.
: "${LUNAWAY_API_HOST:=api.lunaway.net}"
: "${LUNAWAY_TILES_URL:=https://tiles.lunaway.net}"
: "${LUNAWAY_WEB_URL:=https://lunaway.net}"
: "${LUNAWAY_STATUS_DOMAIN:=status.lunaway.net}"
: "${LUNAWAY_MEDIA_BASE_URL:=https://$LUNAWAY_API_HOST/media/}"

# Every Hetzner resource of the project is named lunaway-* and labelled
# project=lunaway,managed-by=claude; the scripts touch nothing else.
LUNAWAY_NETWORK="lunaway-net"
LUNAWAY_NETWORK_RANGE="10.42.0.0/16"
LUNAWAY_SUBNET_RANGE="10.42.0.0/24"
LUNAWAY_NETWORK_ZONE="eu-central"
# The backend's address on the private network. No service talks over it
# since the geocoding and ops servers were merged into the backend; the
# server stays attached so that a second server can join without
# readdressing.
LUNAWAY_BACKEND_PRIVATE_IP="10.42.0.2"
LUNAWAY_IMAGE="${LUNAWAY_IMAGE:-debian-13}"
# The admin account. Root never logs in over SSH.
LUNAWAY_ADMIN_USER="ops"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

# role_get ROLE FIELD: the fixed properties of the server's role.
role_get() {
  case "$1:$2" in
    backend:server) echo lunaway-backend-1 ;;
    backend:firewall) echo lunaway-backend-fw ;;
    # The import cache, the dumps, the photos, the regional packs of
    # places, the basemap's offline packs, the external feed's inbox and the
    # crawler's state (docs/deploy.md, "The data volume").
    backend:volume) echo lunaway-data ;;
    backend:volume_gb) echo "${LUNAWAY_BACKEND_VOLUME_GB:-150}" ;;
    backend:private_ip) echo "$LUNAWAY_BACKEND_PRIVATE_IP" ;;
    backend:alias) echo lunaway ;;
    backend:env) echo LUNAWAY_BACKEND ;;
    # No Hetzner backup images: the root disk holds the database, so its
    # images would keep it in clear. The age-encrypted dumps, pulled by the
    # Mac, are the backups (docs/deploy.md, "Backups and restore").
    backend:backups) echo no ;;
    # 32 GB of memory and 320 GB of local disk: the database, the routing
    # engine's graphs, Photon's Europe index (48 GB) and the basemap extract
    # (36 GB) live on the local NVMe (docs/deploy.md, "Sizing"). fsn1 first:
    # the data volume is there, and a volume attaches only in its location.
    backend:candidates) echo "${LUNAWAY_BACKEND_CANDIDATES:-cx53:fsn1 cx53:nbg1 cx53:hel1}" ;;
    *) die "unknown role or field: $1 $2" ;;
  esac
}

# role_var ROLE SUFFIX: the value of LUNAWAY_<ROLE>_<SUFFIX> from the env file.
role_var() {
  local name
  name="$(role_get "$1" env)_$2"
  printf '%s' "${!name:-}"
}

require_hcloud() {
  command -v hcloud >/dev/null || die "hcloud CLI not found (brew install hcloud)"
  [ -n "${LUNAWAY_HCLOUD_CONTEXT:-}" ] || die "set LUNAWAY_HCLOUD_CONTEXT in $LUNAWAY_ENV_FILE"
  # Every hcloud call of these scripts goes to this context, whatever the
  # active one is.
  export HCLOUD_CONTEXT="$LUNAWAY_HCLOUD_CONTEXT"
}

require_host() {
  local role="${1:-backend}"
  [ -n "$(role_var "$role" IPV4)" ] || die "no $(role_get "$role" env)_IPV4 in $LUNAWAY_ENV_FILE; run infra/provision.sh first"
  write_ssh_config
}

# Sets KEY=VALUE in the private env file, creating it 0600 in a 0700 dir.
env_set() {
  local key="$1" value="$2" tmp
  install -d -m 0700 "$LUNAWAY_CONFIG_DIR"
  [ -f "$LUNAWAY_ENV_FILE" ] || install -m 0600 /dev/null "$LUNAWAY_ENV_FILE"
  tmp="$(mktemp "$LUNAWAY_CONFIG_DIR/.env.XXXXXX")"
  grep -v "^${key}=" "$LUNAWAY_ENV_FILE" > "$tmp" || true
  printf '%s=%q\n' "$key" "$value" >> "$tmp"
  chmod 0600 "$tmp"
  mv "$tmp" "$LUNAWAY_ENV_FILE"
  printf -v "$key" '%s' "$value"
}

# Removes KEY from the private env file.
env_unset() {
  local key="$1" tmp
  [ -f "$LUNAWAY_ENV_FILE" ] || return 0
  tmp="$(mktemp "$LUNAWAY_CONFIG_DIR/.env.XXXXXX")"
  grep -v "^${key}=" "$LUNAWAY_ENV_FILE" > "$tmp" || true
  chmod 0600 "$tmp"
  mv "$tmp" "$LUNAWAY_ENV_FILE"
  unset "$key"
}

# The admin Host block, plus lunaway-backup-pull: the Mac's nightly job
# (infra/ops/mac/) reads the encrypted dumps with its own key, which the
# backend forces to a read-only rsync and accepts from the admin sources
# only.
write_ssh_config() {
  local ip
  [ -n "${LUNAWAY_SSH_IDENTITY:-}" ] || die "set LUNAWAY_SSH_IDENTITY in $LUNAWAY_ENV_FILE"
  install -d -m 0700 "$LUNAWAY_CONFIG_DIR"
  ip="$(role_var backend IPV4)"
  {
    echo "# Written by infra/lib.sh. Use with: ssh -F $LUNAWAY_SSH_CONFIG lunaway"
    if [ -n "$ip" ]; then
      cat <<EOF
Host $(role_get backend alias)
  HostName $ip
  User $LUNAWAY_ADMIN_USER
  IdentityFile $LUNAWAY_SSH_IDENTITY
  IdentitiesOnly yes
  UserKnownHostsFile $LUNAWAY_CONFIG_DIR/known_hosts
  StrictHostKeyChecking accept-new
  ServerAliveInterval 30
  ConnectTimeout 15

Host lunaway-backup-pull
  HostName $ip
  User lunaway-pull
  IdentityFile $LUNAWAY_CONFIG_DIR/backup-pull_ed25519
  IdentitiesOnly yes
  UserKnownHostsFile $LUNAWAY_CONFIG_DIR/known_hosts
  StrictHostKeyChecking yes
  BatchMode yes
  ConnectTimeout 20
EOF
    fi
  } > "$LUNAWAY_SSH_CONFIG"
  chmod 0600 "$LUNAWAY_SSH_CONFIG"
}

# host_ssh ROLE ARGS...: a command on that server as the admin user.
host_ssh() { local role="$1"; shift; ssh -F "$LUNAWAY_SSH_CONFIG" "$(role_get "$role" alias)" "$@"; }
lunaway_ssh() { host_ssh backend "$@"; }
lunaway_scp() { scp -q -F "$LUNAWAY_SSH_CONFIG" "$@"; }

# cidr_list_ok CIDR...: succeeds when every argument is an IPv4 or IPv6
# network (host bits allowed), so a value can go into a firewall rule or onto
# a remote command line.
cidr_list_ok() {
  python3 - "$@" <<'EOF'
import ipaddress, sys
try:
    for value in sys.argv[1:]:
        ipaddress.ip_network(value, strict=False)
except ValueError:
    sys.exit(1)
EOF
}

# The public address of this machine, as the internet sees it, validated: an
# answer that is not an address (a captive portal page, an error) is dropped.
current_ipv4() {
  local ip
  ip="$(curl -4 -fsS -m 8 https://api.ipify.org 2>/dev/null || true)"
  [ -n "$ip" ] || return 0
  python3 -c 'import ipaddress,sys; print(ipaddress.IPv4Address(sys.argv[1].strip()))' "$ip" 2>/dev/null || true
}
current_ipv6_64() {
  local ip
  ip="$(curl -6 -fsS -m 8 https://api6.ipify.org 2>/dev/null || true)"
  [ -n "$ip" ] || return 0
  # Keep the /64: the host part of a client address rotates (privacy extensions).
  python3 -c 'import ipaddress,sys; print(ipaddress.IPv6Network(sys.argv[1].strip() + "/64", strict=False))' "$ip" 2>/dev/null || true
}

# firewall_rules_json ROLE CIDR...: the Hetzner Cloud Firewall rules. SSH
# from the admin sources only; the web ports and ICMP from anywhere (the
# API, the website, the basemap and the status page). Outbound stays open
# (no "out" rule).
firewall_rules_json() {
  python3 - "$@" <<'EOF'
import json, sys
role, ssh_sources = sys.argv[1], sys.argv[2:]
anywhere = ["0.0.0.0/0", "::/0"]
rules = [
    {"direction": "in", "protocol": "tcp", "port": "22", "source_ips": ssh_sources,
     "description": "SSH, admin sources only (infra/ssh-access.sh)"},
    {"direction": "in", "protocol": "tcp", "port": "80", "source_ips": anywhere,
     "description": "HTTP: ACME challenge and redirect to HTTPS"},
    {"direction": "in", "protocol": "tcp", "port": "443", "source_ips": anywhere,
     "description": "HTTPS"},
    {"direction": "in", "protocol": "udp", "port": "443", "source_ips": anywhere,
     "description": "HTTP/3 (QUIC)"},
    {"direction": "in", "protocol": "icmp", "source_ips": anywhere,
     "description": "ICMP: ping and path MTU discovery"},
]
print(json.dumps(rules, indent=1))
EOF
}
