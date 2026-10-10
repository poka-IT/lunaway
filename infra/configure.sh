#!/usr/bin/env bash
# Copies infra/ to a server and applies infra/server/setup.sh as root for its
# role. Idempotent; reboots the server afterwards when an update asks for it.
#
#   infra/configure.sh backend              every step
#   infra/configure.sh backend caddy api    only these steps
#   LUNAWAY_NO_REBOOT=1 infra/configure.sh backend
#
# The keys the backend's lunaway-pull account accepts are read on the
# server itself by the ops-access step (Gatus's probe key, made by the
# ops-status step; the external community feed producer's erasures key, made
# by its private deployment), except the Mac's pull key, whose public half
# is read here. Every value passed to the server is checked here, then
# quoted for the remote shell.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
role="${1:?usage: $0 backend [step...]}"
shift
role_get "$role" server >/dev/null
require_host "$role"
volume_id="$(role_var "$role" VOLUME_ID)"
[[ "$volume_id" =~ ^[0-9]+$ ]] || die "no volume id for $role; run infra/provision.sh"
for step in "$@"; do
  [[ "$step" =~ ^[a-z-]+$ ]] || die "unexpected step name $step"
done

ed25519_re='^ssh-ed25519 [A-Za-z0-9+/=]+( [A-Za-z0-9@._-]+)*$'

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
recipient="${LUNAWAY_BACKUP_RECIPIENT:-}"
[[ "$recipient" =~ ^age1[02-9ac-hj-np-z]{58}$ ]] \
  || die "LUNAWAY_BACKUP_RECIPIENT is not an age recipient; run infra/ops/mac/install.sh keys first"
# The public address of the photos (lib.sh: https://api.lunaway.net/media/).
media_base="$LUNAWAY_MEDIA_BASE_URL"
[[ "$media_base" =~ ^https://[a-z0-9.-]+/media/$ ]] || die "unexpected LUNAWAY_MEDIA_BASE_URL: $media_base"
# The Mac's pull key (infra/ops/mac/install.sh keys), empty until it exists.
mac_key=""
[ -f "$LUNAWAY_CONFIG_DIR/backup-pull_ed25519.pub" ] && mac_key="$(cat "$LUNAWAY_CONFIG_DIR/backup-pull_ed25519.pub")"
[ -z "$mac_key" ] || [[ "$mac_key" =~ $ed25519_re ]] || die "unexpected key in $LUNAWAY_CONFIG_DIR/backup-pull_ed25519.pub"
# What the status page checks (the API, the web app, the basemap), all
# public names from lib.sh.
api_host="$LUNAWAY_API_HOST"
web_url="$LUNAWAY_WEB_URL"
tiles_url="$LUNAWAY_TILES_URL"
[[ "$api_host" =~ ^[a-z0-9.-]+$ ]] || die "unexpected API host: $api_host"
[[ "$tiles_url" =~ ^https://[a-z0-9.-]+\.[a-z]+(/[a-z0-9_-]+)*$ ]] || die "unexpected LUNAWAY_TILES_URL: $tiles_url"
[ -z "$web_url" ] || [[ "$web_url" =~ ^https://[a-z0-9.-]+(/[A-Za-z0-9/._-]*)?$ ]] || die "unexpected LUNAWAY_WEB_URL: $web_url"
vars+=(
  "LUNAWAY_MEDIA_BASE_URL=$media_base"
  "LUNAWAY_BACKUP_RECIPIENT=$recipient"
  "LUNAWAY_MAC_PULL_PUBKEY=$mac_key"
  "LUNAWAY_API_HOST=$api_host"
  "LUNAWAY_WEB_URL=$web_url"
  "LUNAWAY_TILES_URL=$tiles_url"
)

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
