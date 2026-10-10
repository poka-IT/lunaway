#!/usr/bin/env bash
# What the ops server may read from the backend, run as root by setup.sh on
# the backend. One account, lunaway-pull, reachable over SSH from the ops
# server's private address only, with up to three keys, each forced to one
# read-only command by a root-owned authorized_keys:
#
#   probe key     /usr/local/sbin/lunaway-health: the health facts as JSON,
#                 which Gatus checks every few minutes
#   replica key   rrsync -ro /srv/data/backups/offsite: the age-encrypted
#                 dumps and their markers, and the age-encrypted photos
#                 (media/), pulled every night
#   erasures key  /usr/local/sbin/lunaway-extcom-erasures: the SHA-256 of
#                 every author of the external community source erased at
#                 the partner's request, which the feed's producer purges
#                 from its own copy (docs/deploy.md, "The external
#                 community feed")
#
# The backend never connects to the ops server.
#
#   LUNAWAY_PROBE_PUBKEY, LUNAWAY_REPLICA_PUBKEY   the first two public
#       keys, generated on the ops server (infra/configure.sh reads them
#       there); empty before the ops server is configured
#   LUNAWAY_EXTCOM_ERASURES_PUBKEY   the producer's key, made by its private
#       deployment, which leaves the public half in
#       /etc/lunaway-ops/extcom-erasures_ed25519.pub (configure.sh reads it
#       there); empty while the producer is not deployed
#   LUNAWAY_OPS_PRIVATE_IP   the ops server's address on the private network
. "$(dirname "$0")/common.sh"
need_root
ops_ip="${LUNAWAY_OPS_PRIVATE_IP:?set LUNAWAY_OPS_PRIVATE_IP}"
[[ "$ops_ip" =~ ^10\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "unexpected private address $ops_ip"
apt_install rsync
[ -x /usr/bin/rrsync ] || die "rrsync is missing from the rsync package"
getent group lunaway-pull >/dev/null || die "no group lunaway-pull; run the backups step first"

log "account"
if ! getent passwd lunaway-pull >/dev/null; then
  # A real shell: sshd runs the forced commands through it. The keys allow
  # nothing else (restrict, command=).
  useradd --system --gid lunaway-pull --home-dir /var/lib/lunaway-pull --no-create-home \
    --shell /bin/sh --comment "Lunaway ops server, read-only pulls" lunaway-pull
fi
install_file files/usr/local/sbin/lunaway-health /usr/local/sbin/lunaway-health 0755 || true
install_file files/usr/local/sbin/lunaway-extcom-erasures /usr/local/sbin/lunaway-extcom-erasures 0755 || true

log "keys"
install -d -m 0755 -o root -g root /var/lib/lunaway-pull /var/lib/lunaway-pull/.ssh
: > "$STAGING/pull-authorized_keys"
# add_key NAME COMMAND KEY [WHEN MISSING]: one line of authorized_keys, from
# the ops server only, forced to COMMAND.
add_key() {
  local name="$1" command="$2" key="$3" missing="${4:-configure the ops server first}"
  if [ -z "$key" ]; then
    log "no $name key yet ($missing)"
    return 0
  fi
  [[ "$key" =~ $ED25519_PUBKEY_RE ]] || die "the $name key is not an Ed25519 public key"
  echo "restrict,from=\"$ops_ip\",command=\"$command\" $key" >> "$STAGING/pull-authorized_keys"
}
add_key probe /usr/local/sbin/lunaway-health "${LUNAWAY_PROBE_PUBKEY:-}"
add_key replica "/usr/bin/rrsync -ro /srv/data/backups/offsite" "${LUNAWAY_REPLICA_PUBKEY:-}"
add_key extcom-erasures /usr/local/sbin/lunaway-extcom-erasures "${LUNAWAY_EXTCOM_ERASURES_PUBKEY:-}" \
  "deploy the external community feed's producer first"
# Root-owned: the account cannot change its own restrictions.
install_file "$STAGING/pull-authorized_keys" /var/lib/lunaway-pull/.ssh/authorized_keys 0644 || true

cat > "$STAGING/12-lunaway-pull.conf" <<EOF
# Written by infra/server/ops-access.sh: the ops server's read-only account,
# from its private address only. Each key is forced to one command.
AllowUsers lunaway-pull@$ops_ip
EOF
if install_file "$STAGING/12-lunaway-pull.conf" /etc/ssh/sshd_config.d/12-lunaway-pull.conf 0644; then
  if ! sshd -t; then
    rm -f /etc/ssh/sshd_config.d/12-lunaway-pull.conf
    die "sshd rejects the pull configuration; it was removed, sshd was not reloaded"
  fi
  systemctl reload ssh
fi
log "lunaway-pull: $(grep -c . /var/lib/lunaway-pull/.ssh/authorized_keys) key(s), from $ops_ip only"
