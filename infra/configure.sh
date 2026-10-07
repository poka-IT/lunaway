#!/usr/bin/env bash
# Copies infra/ to a server and applies infra/server/setup.sh as root for its
# role. Idempotent; reboots the server afterwards when an update asks for it.
#
#   infra/configure.sh ops                  every step of the ops role
#   infra/configure.sh backend              every step of the backend role
#   infra/configure.sh backend caddy api    only these steps
#   LUNAWAY_NO_REBOOT=1 infra/configure.sh backend
#
# The first time, configure ops before backend: the ops step generates the
# two keys the backend's lunaway-pull account accepts (health probe, dump
# replica), and pins the backend's host key, read from the backend itself.
# Every value passed to the server is checked here, then quoted for the
# remote shell.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
role="${1:?usage: $0 backend|ops|geocode [step...]}"
shift
role_get "$role" server >/dev/null
require_host "$role"
volume_id="$(role_var "$role" VOLUME_ID)"
if [ -n "$(role_get "$role" volume)" ]; then
  [[ "$volume_id" =~ ^[0-9]+$ ]] || die "no volume id for $role; run infra/provision.sh"
fi
for step in "$@"; do
  [[ "$step" =~ ^[a-z-]+$ ]] || die "unexpected step name $step"
done

ed25519_re='^ssh-ed25519 [A-Za-z0-9+/=]+( [A-Za-z0-9@._-]+)*$'
# read_pubkey ROLE PATH: a public key file on that server, empty when absent.
read_pubkey() { host_ssh "$1" "cat $2 2>/dev/null" || true; }

ssh_allow="${LUNAWAY_SSH_ALLOW:-}"
if [ -n "$ssh_allow" ]; then
  # shellcheck disable=SC2086 # one CIDR per word
  cidr_list_ok $ssh_allow || die "LUNAWAY_SSH_ALLOW holds something else than CIDRs: $ssh_allow"
fi

declare -a vars=(
  "LUNAWAY_ROLE=$role"
  "LUNAWAY_VOLUME_ID=$volume_id"
  "LUNAWAY_SSH_ALLOW=$ssh_allow"
)
case "$role" in
  backend)
    probe_key="" replica_key=""
    if [ -n "$(role_var ops IPV4)" ]; then
      probe_key="$(read_pubkey ops /etc/lunaway-ops/probe_ed25519.pub)"
      replica_key="$(read_pubkey ops /etc/lunaway-ops/replica_ed25519.pub)"
    fi
    for value in "$probe_key" "$replica_key"; do
      [ -z "$value" ] || [[ "$value" =~ $ed25519_re ]] || die "unexpected key material from the ops server: $value"
    done
    recipient="${LUNAWAY_BACKUP_RECIPIENT:-}"
    [[ "$recipient" =~ ^age1[02-9ac-hj-np-z]{58}$ ]] \
      || die "LUNAWAY_BACKUP_RECIPIENT is not an age recipient; run infra/ops/mac/install.sh keys first"
    tiles_volume_id="$(role_var backend TILES_VOLUME_ID)"
    [[ "$tiles_volume_id" =~ ^[0-9]+$ ]] || die "no tile volume id for the backend; run infra/provision.sh backend"
    # The public address of the photos (lib.sh: https://api.lunaway.net/media/).
    media_base="$LUNAWAY_MEDIA_BASE_URL"
    [[ "$media_base" =~ ^https://[a-z0-9.-]+/media/$ ]] || die "unexpected LUNAWAY_MEDIA_BASE_URL: $media_base"
    vars+=(
      "LUNAWAY_MEDIA_BASE_URL=$media_base"
      "LUNAWAY_TILES_VOLUME_ID=$tiles_volume_id"
      "LUNAWAY_OPS_PRIVATE_IP=$LUNAWAY_OPS_PRIVATE_IP"
      "LUNAWAY_PROBE_PUBKEY=$probe_key"
      "LUNAWAY_REPLICA_PUBKEY=$replica_key"
      "LUNAWAY_BACKUP_RECIPIENT=$recipient"
    )
    ;;
  ops)
    backend_hostkey="$(host_ssh backend 'cat /etc/ssh/ssh_host_ed25519_key.pub' | awk '{ print $1 " " $2 }')"
    [[ "$backend_hostkey" =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+$ ]] || die "unexpected backend host key: $backend_hostkey"
    mac_key=""
    [ -f "$LUNAWAY_CONFIG_DIR/ops-pull_ed25519.pub" ] && mac_key="$(cat "$LUNAWAY_CONFIG_DIR/ops-pull_ed25519.pub")"
    [ -z "$mac_key" ] || [[ "$mac_key" =~ $ed25519_re ]] || die "unexpected key in $LUNAWAY_CONFIG_DIR/ops-pull_ed25519.pub"
    # What the status page checks (the API, the web app, the basemap) and
    # the name the page itself answers to, all public names from lib.sh.
    api_host="$LUNAWAY_API_HOST"
    web_url="$LUNAWAY_WEB_URL"
    tiles_url="$LUNAWAY_TILES_URL"
    status_hosts="$LUNAWAY_STATUS_DOMAIN"
    [[ "$api_host" =~ ^[a-z0-9.-]+$ ]] || die "unexpected API host: $api_host"
    [[ "$tiles_url" =~ ^https://[a-z0-9.-]+\.[a-z]+(/[a-z0-9_-]+)*$ ]] || die "unexpected LUNAWAY_TILES_URL: $tiles_url"
    [ -z "$web_url" ] || [[ "$web_url" =~ ^https://[a-z0-9.-]+(/[A-Za-z0-9/._-]*)?$ ]] || die "unexpected LUNAWAY_WEB_URL: $web_url"
    [[ "$status_hosts" =~ ^[a-z0-9.-]+( [a-z0-9.-]+)?$ ]] || die "unexpected status host names: $status_hosts"
    vars+=(
      "LUNAWAY_BACKEND_PRIVATE_IP=$LUNAWAY_BACKEND_PRIVATE_IP"
      "LUNAWAY_BACKEND_HOSTKEY=$backend_hostkey"
      "LUNAWAY_MAC_PULL_PUBKEY=$mac_key"
      "LUNAWAY_API_HOST=$api_host"
      "LUNAWAY_WEB_URL=$web_url"
      "LUNAWAY_TILES_URL=$tiles_url"
      "LUNAWAY_STATUS_HOSTS=$status_hosts"
    )
    ;;
  geocode)
    vars+=("LUNAWAY_GEOCODE_PRIVATE_IP=$LUNAWAY_GEOCODE_PRIVATE_IP")
    ;;
esac

# One word per assignment, each quoted for the remote shell, so no value can
# end a word or start a command there.
remote="sudo env"
for assignment in "${vars[@]}"; do
  remote+=" $(printf '%q' "$assignment")"
done
remote+=" bash infra/server/setup.sh"
for step in "$@"; do
  remote+=" $(printf '%q' "$step")"
done

log "uploading infra/ to $(role_get "$role" server)"
# A fresh copy each time, so a file removed from the repository does not
# linger on the server.
COPYFILE_DISABLE=1 tar -C "$LUNAWAY_INFRA_DIR" --no-xattrs --no-mac-metadata -cf - . \
  | host_ssh "$role" 'rm -rf ~/infra && mkdir ~/infra && tar -xf - -C ~/infra'

host_ssh "$role" "$remote"

if [ "${LUNAWAY_NO_REBOOT:-0}" != 1 ] && host_ssh "$role" 'test -f /run/reboot-required'; then
  log "rebooting $(role_get "$role" server) for: $(host_ssh "$role" 'cat /run/reboot-required.pkgs 2>/dev/null | tr "\n" " "')"
  host_ssh "$role" 'sudo systemctl reboot' || true
  sleep 20
  for _ in $(seq 1 40); do
    host_ssh "$role" -o BatchMode=yes true 2>/dev/null && break
    sleep 5
  done
  host_ssh "$role" 'uptime; systemctl is-system-running --wait; systemctl --failed --no-legend'
fi
log "configured $(role_get "$role" server)"
