# shellcheck shell=bash
# shellcheck disable=SC2034 # the settings are read by the scripts that source this file
# Shared settings and helpers of the local infra scripts. Sourced, never run.
#
# Two servers, one role each, on a private network (10.42.0.0/16):
#   backend   lunaway-backend-1   10.42.0.2   API, PostgreSQL + PostGIS, Caddy,
#                                             the data pipeline (lunaway CLI),
#                                             the basemap (pmtiles, own volume)
#   ops       lunaway-sync-1      10.42.0.3   status page and checks (Gatus),
#                                             replica of the nightly dumps
# The ops server reads two things from the backend over the private network,
# each through a key forced to one read-only command (infra/server/ops-access.sh):
# the health facts and the encrypted dumps. The backend never connects to it.
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
#   LUNAWAY_API_HOST, LUNAWAY_WEB_URL, LUNAWAY_STATUS_DOMAIN
#                             what the status page checks and its public name,
#                             optional (see docs/deploy.md, "Status page")
#   LUNAWAY_TILES_URL         the basemap's public base URL the status page
#                             checks, optional (https://<backend sslip.io name>/tiles
#                             until DNS exists, then https://tiles.lunaway.net)
#   LUNAWAY_BACKEND_IPV4/_IPV6/_VOLUME_ID/_TILES_VOLUME_ID,
#   LUNAWAY_OPS_IPV4/_IPV6/_VOLUME_ID,
#   LUNAWAY_HOSTNAME          written by provision.sh

LUNAWAY_INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUNAWAY_REPO_DIR="$(cd "$LUNAWAY_INFRA_DIR/.." && pwd)"
LUNAWAY_CONFIG_DIR="${LUNAWAY_CONFIG_DIR:-$HOME/.config/lunaway}"
LUNAWAY_ENV_FILE="$LUNAWAY_CONFIG_DIR/env"
LUNAWAY_SSH_CONFIG="$LUNAWAY_CONFIG_DIR/ssh_config"

# shellcheck disable=SC1090
[ -f "$LUNAWAY_ENV_FILE" ] && . "$LUNAWAY_ENV_FILE"

# Every Hetzner resource of the project is named lunaway-* and labelled
# project=lunaway,managed-by=claude; the scripts touch nothing else.
LUNAWAY_NETWORK="lunaway-net"
LUNAWAY_NETWORK_RANGE="10.42.0.0/16"
LUNAWAY_SUBNET_RANGE="10.42.0.0/24"
LUNAWAY_NETWORK_ZONE="eu-central"
LUNAWAY_BACKEND_PRIVATE_IP="10.42.0.2"
LUNAWAY_OPS_PRIVATE_IP="10.42.0.3"
LUNAWAY_IMAGE="${LUNAWAY_IMAGE:-debian-13}"
# The admin account on both servers. Root never logs in over SSH.
LUNAWAY_ADMIN_USER="ops"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

# role_get ROLE FIELD: the fixed properties of each role.
role_get() {
  case "$1:$2" in
    backend:server) echo lunaway-backend-1 ;;
    backend:firewall) echo lunaway-backend-fw ;;
    backend:volume) echo lunaway-data ;;
    backend:volume_gb) echo "${LUNAWAY_BACKEND_VOLUME_GB:-150}" ;;
    # The basemap: two planet archives (the one served and the next, about
    # 139 GB each in October 2026) and some margin (docs/deploy.md, "Basemap").
    backend:tiles_volume) echo lunaway-tiles ;;
    backend:tiles_volume_gb) echo "${LUNAWAY_TILES_VOLUME_GB:-300}" ;;
    backend:private_ip) echo "$LUNAWAY_BACKEND_PRIVATE_IP" ;;
    backend:alias) echo lunaway ;;
    backend:env) echo LUNAWAY_BACKEND ;;
    backend:backups) echo yes ;;
    # Best value first; the API refuses a type out of stock and the next is tried.
    backend:candidates) echo "${LUNAWAY_BACKEND_CANDIDATES:-cx43:nbg1 cx43:fsn1 cax31:nbg1 cax31:fsn1 cx33:nbg1 cx33:fsn1 cx43:hel1 cax31:hel1 cx23:nbg1}" ;;
    # The ops role runs on the server first provisioned as the sync server; its
    # Hetzner names stay, only its role changed.
    ops:server) echo lunaway-sync-1 ;;
    ops:firewall) echo lunaway-sync-fw ;;
    ops:volume) echo lunaway-sync-data ;;
    ops:volume_gb) echo "${LUNAWAY_OPS_VOLUME_GB:-20}" ;;
    ops:private_ip) echo "$LUNAWAY_OPS_PRIVATE_IP" ;;
    ops:alias) echo lunaway-ops ;;
    ops:env) echo LUNAWAY_OPS ;;
    ops:backups) echo no ;;
    ops:candidates) echo "${LUNAWAY_OPS_CANDIDATES:-cax11:nbg1 cax11:fsn1 cx23:nbg1 cx23:fsn1 cax11:hel1 cx23:hel1}" ;;
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

# One Host block per server already provisioned, plus lunaway-ops-pull: the
# nightly job of infra/ops/mac/ reads the dump replica on the ops server with
# its own key, which the server forces to a read-only rsync.
write_ssh_config() {
  local role ip aliases
  [ -n "${LUNAWAY_SSH_IDENTITY:-}" ] || die "set LUNAWAY_SSH_IDENTITY in $LUNAWAY_ENV_FILE"
  install -d -m 0700 "$LUNAWAY_CONFIG_DIR"
  {
    echo "# Written by infra/lib.sh. Use with: ssh -F $LUNAWAY_SSH_CONFIG lunaway (or lunaway-ops)"
    for role in backend ops; do
      ip="$(role_var "$role" IPV4)"
      [ -n "$ip" ] || continue
      aliases="$(role_get "$role" alias)"
      # The name the ops server had as the sync server keeps working.
      [ "$role" = ops ] && aliases="$aliases lunaway-sync"
      cat <<EOF
Host $aliases
  HostName $ip
  User $LUNAWAY_ADMIN_USER
  IdentityFile $LUNAWAY_SSH_IDENTITY
  IdentitiesOnly yes
  UserKnownHostsFile $LUNAWAY_CONFIG_DIR/known_hosts
  StrictHostKeyChecking accept-new
  ServerAliveInterval 30
  ConnectTimeout 15
EOF
    done
    ip="$(role_var ops IPV4)"
    if [ -n "$ip" ]; then
      cat <<EOF
Host lunaway-ops-pull
  HostName $ip
  User lunaway-pull
  IdentityFile $LUNAWAY_CONFIG_DIR/ops-pull_ed25519
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
# from the admin sources only on both; both also take the web ports and ICMP
# from anywhere (the API on the backend, the status page on the ops server).
# Outbound stays open (no "out" rule). Hetzner firewalls do not filter the
# private network; nftables does.
firewall_rules_json() {
  python3 - "$@" <<'EOF'
import json, sys
role, ssh_sources = sys.argv[1], sys.argv[2:]
anywhere = ["0.0.0.0/0", "::/0"]
rules = [
    {"direction": "in", "protocol": "tcp", "port": "22", "source_ips": ssh_sources,
     "description": "SSH, admin sources only (infra/ssh-access.sh)"},
]
if role in ("backend", "ops"):
    rules += [
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
