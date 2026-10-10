#!/usr/bin/env bash
# Creates the Hetzner Cloud resources of Lunaway, or finds them: the admin
# SSH key, the private network, then the server's firewall, the server
# (first boot hardened by cloud-init.yaml), its primary IPs and its data
# volume. Idempotent: an existing resource is kept as it is, and only
# resources named lunaway-* are ever created or changed.
#
#   infra/provision.sh                        the server (role backend)
#   infra/provision.sh --render-only backend FILE   only render cloud-init.yaml, for review
#
# Server types are tried in order of value for each role (role_get in
# lib.sh); the API refuses a type out of stock in a location, and the next
# candidate is tried. The type list's "available" flag is not a reliable
# stock signal (docs/deploy.md).
set -euo pipefail
. "$(dirname "$0")/lib.sh"
require_hcloud
command -v python3 >/dev/null || die "python3 is needed"
[ -n "${LUNAWAY_SSH_KEY_NAME:-}" ] || die "set LUNAWAY_SSH_KEY_NAME in $LUNAWAY_ENV_FILE"
[ -n "${LUNAWAY_SSH_IDENTITY:-}" ] || die "set LUNAWAY_SSH_IDENTITY in $LUNAWAY_ENV_FILE"

LABEL_ARGS=(--label project=lunaway --label managed-by=claude)

json_field() { python3 -c 'import json,sys; d=json.load(sys.stdin)
for k in sys.argv[1].split("."): d = d[k] if d is not None else None
print("" if d is None else d)' "$1"; }

# render_user_data ROLE: prints the rendered user data on stdout.
render_user_data() {
  local role="$1" key
  key="$(hcloud ssh-key describe "$LUNAWAY_SSH_KEY_NAME" -o json | json_field public_key)"
  [ -n "$key" ] || die "no public key named $LUNAWAY_SSH_KEY_NAME in the project"
  python3 - "$LUNAWAY_INFRA_DIR" "$(role_get "$role" server)" "$role" "$key" <<'EOF'
import base64, pathlib, re, sys
infra, hostname, role, key = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
text = (infra / "cloud-init.yaml").read_text()
text = text.replace("@@HOSTNAME@@", hostname).replace("@@ROLE@@", role).replace("@@ADMIN_SSH_KEY@@", key)
text = re.sub(r"@@B64:([^@]+)@@",
              lambda m: base64.b64encode((infra / m.group(1)).read_bytes()).decode(), text)
assert "@@" not in text, "unrendered placeholder"
assert len(text.encode()) < 32 * 1024, "user data over the 32 KiB limit"
sys.stdout.write(text)
EOF
}

if [ "${1:-}" = "--render-only" ]; then
  render_user_data "${2:?role}" > "${3:?usage: $0 --render-only ROLE FILE}"
  exit 0
fi
roles="${*:-backend}"

# The admin key, from its public half on this machine.
if hcloud ssh-key describe "$LUNAWAY_SSH_KEY_NAME" >/dev/null 2>&1; then
  log "SSH key $LUNAWAY_SSH_KEY_NAME exists"
else
  [ -f "${LUNAWAY_SSH_PUBKEY:-}" ] || die "set LUNAWAY_SSH_PUBKEY to the admin public key file"
  log "uploading SSH key $LUNAWAY_SSH_KEY_NAME from $LUNAWAY_SSH_PUBKEY"
  hcloud ssh-key create --name "$LUNAWAY_SSH_KEY_NAME" --public-key-from-file "$LUNAWAY_SSH_PUBKEY" "${LABEL_ARGS[@]}" >/dev/null
fi

# The private network (lib.sh: nothing talks over it today).
if hcloud network describe "$LUNAWAY_NETWORK" >/dev/null 2>&1; then
  log "network $LUNAWAY_NETWORK exists"
else
  log "creating network $LUNAWAY_NETWORK ($LUNAWAY_NETWORK_RANGE, subnet $LUNAWAY_SUBNET_RANGE in $LUNAWAY_NETWORK_ZONE)"
  hcloud network create --name "$LUNAWAY_NETWORK" --ip-range "$LUNAWAY_NETWORK_RANGE" "${LABEL_ARGS[@]}" >/dev/null
  hcloud network add-subnet "$LUNAWAY_NETWORK" --type cloud --network-zone "$LUNAWAY_NETWORK_ZONE" --ip-range "$LUNAWAY_SUBNET_RANGE" >/dev/null
fi

# SSH sources default to this machine's current public address.
allow="${LUNAWAY_SSH_ALLOW:-}"
if [ -z "$allow" ]; then
  v4="$(current_ipv4)"
  v6="$(current_ipv6_64)"
  allow="$(echo "${v4:+$v4/32}" "$v6")"
  [ -n "$allow" ] || die "cannot detect this machine's public address; set LUNAWAY_SSH_ALLOW"
  env_set LUNAWAY_SSH_ALLOW "$allow"
fi

provision_role() {
  local role="$1" server firewall volume prefix created candidate type location out json id family name
  server="$(role_get "$role" server)"
  firewall="$(role_get "$role" firewall)"
  volume="$(role_get "$role" volume)"
  prefix="$(role_get "$role" env)"

  # Firewall, attached at creation so the server is never reachable unfiltered.
  if hcloud firewall describe "$firewall" >/dev/null 2>&1; then
    log "firewall $firewall exists"
  else
    log "creating firewall $firewall (SSH from: $allow)"
    # shellcheck disable=SC2086 # one CIDR per word
    firewall_rules_json "$role" $allow | hcloud firewall create --name "$firewall" --rules-file - "${LABEL_ARGS[@]}" >/dev/null
  fi

  if hcloud server describe "$server" >/dev/null 2>&1; then
    log "server $server exists"
  else
    local backup_args=() user_data
    [ "$(role_get "$role" backups)" = yes ] && backup_args=(--enable-backup)
    # Rendered first: a failed render piped into the create would give a
    # server with no user data, hence no hardening.
    user_data="$(render_user_data "$role")" || die "cannot render the user data of $role"
    [ -n "$user_data" ] || die "empty user data for $role"
    created=""
    for candidate in $(role_get "$role" candidates); do
      type="${candidate%%:*}"
      location="${candidate##*:}"
      log "trying $type in $location for $server"
      # Created stopped: the private network is attached before the first
      # boot, so cloud-init configures its interface.
      if out="$(printf '%s' "$user_data" | hcloud server create --name "$server" --type "$type" --location "$location" \
          --image "$LUNAWAY_IMAGE" --ssh-key "$LUNAWAY_SSH_KEY_NAME" --firewall "$firewall" \
          --user-data-from-file - "${backup_args[@]}" --enable-protection delete,rebuild \
          --start-after-create=false "${LABEL_ARGS[@]}" --label "role=$role" 2>&1)"; then
        created="$candidate"
        break
      fi
      echo "    refused: $(echo "$out" | tail -n 1)"
      # A create that failed late may still have left the server behind.
      hcloud server describe "$server" >/dev/null 2>&1 && { created="$candidate"; break; }
    done
    [ -n "$created" ] || die "no candidate type was accepted for $server; see the refusals above"
    log "server $server created as $created, stopped"
  fi

  json="$(hcloud server describe "$server" -o json)"
  if ! echo "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["private_net"] else 1)'; then
    log "attaching $server to $LUNAWAY_NETWORK as $(role_get "$role" private_ip)"
    hcloud server attach-to-network --network "$LUNAWAY_NETWORK" --ip "$(role_get "$role" private_ip)" "$server" >/dev/null
  fi

  # The primary IPs outlive the server (auto-delete off), so a rebuild or a
  # recreate keeps the addresses the DNS records point at.
  for family in ipv4 ipv6; do
    id="$(echo "$json" | json_field "public_net.$family.id")"
    [ -n "$id" ] || continue
    name="$(hcloud primary-ip describe "$id" -o json | json_field name)"
    case "$name" in
      "lunaway-$role-$family") ;;
      primary_ip-*)
        hcloud primary-ip update "$id" --name "lunaway-$role-$family" --auto-delete=false >/dev/null
        hcloud primary-ip add-label --overwrite "$id" project=lunaway >/dev/null
        hcloud primary-ip add-label --overwrite "$id" managed-by=claude >/dev/null
        hcloud primary-ip enable-protection "$id" delete >/dev/null
        log "primary IP $id named lunaway-$role-$family, kept on server deletion"
        ;;
      *) die "primary IP $id is named $name, not this mission's; leaving it alone" ;;
    esac
  done

  if hcloud volume describe "$volume" >/dev/null 2>&1; then
    log "volume $volume exists"
    if [ -z "$(hcloud volume describe "$volume" -o json | json_field server)" ]; then
      hcloud volume attach --server "$server" "$volume" >/dev/null
      log "volume $volume attached"
    fi
  else
    log "creating volume $volume ($(role_get "$role" volume_gb) GB, ext4) for $server"
    # --server places the volume in the server's location and attaches it.
    hcloud volume create --name "$volume" --size "$(role_get "$role" volume_gb)" \
      --format ext4 --server "$server" --enable-protection delete "${LABEL_ARGS[@]}" >/dev/null
  fi

  json="$(hcloud server describe "$server" -o json)"
  if [ "$(echo "$json" | json_field status)" = off ]; then
    log "starting $server"
    hcloud server poweron "$server" >/dev/null
  fi
  local ipv4 ipv6_net
  ipv4="$(echo "$json" | json_field public_net.ipv4.ip)"
  ipv6_net="$(echo "$json" | json_field public_net.ipv6.ip)"
  env_set "${prefix}_IPV4" "$ipv4"
  env_set "${prefix}_IPV6" "${ipv6_net%%/*}1"
  env_set "${prefix}_VOLUME_ID" "$(hcloud volume describe "$volume" -o json | json_field id)"
  env_set "${prefix}_SERVER_TYPE" "$(echo "$json" | json_field server_type.name)"
  env_set "${prefix}_LOCATION" "$(echo "$json" | json_field location.name)"
  return 0
}

wait_for_role() {
  local role="$1" status=0
  log "waiting for SSH on $(role_get "$role" server)"
  for _ in $(seq 1 60); do
    host_ssh "$role" -o BatchMode=yes true 2>/dev/null && break
    sleep 5
  done
  host_ssh "$role" -o BatchMode=yes true || die "SSH does not answer; see the server console in the Hetzner panel"
  log "waiting for cloud-init on $(role_get "$role" server)"
  host_ssh "$role" 'cloud-init status --wait >/dev/null; cloud-init status --long' || status=$?
  case "$status" in
    0) ;;
    2) log "cloud-init finished with recoverable errors (above); infra/configure.sh re-applies everything" ;;
    *) die "cloud-init failed (above)" ;;
  esac
}

for role in $roles; do
  role_get "$role" server >/dev/null
  provision_role "$role"
done
write_ssh_config
for role in $roles; do
  wait_for_role "$role"
  log "$(role_get "$role" server): $(role_var "$role" SERVER_TYPE) in $(role_var "$role" LOCATION), $(role_var "$role" IPV4), $(role_var "$role" IPV6), private $(role_get "$role" private_ip)"
done
log "next: infra/ops/mac/install.sh keys, infra/configure.sh backend, infra/enable-domain.sh, infra/deploy-api.sh, infra/deploy-gatus.sh"
