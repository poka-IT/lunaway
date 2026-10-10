#!/usr/bin/env bash
# Who may read what from the backend over SSH, run as root by setup.sh. One
# account, lunaway-pull, with up to three keys, each forced to one read-only
# command by a root-owned authorized_keys:
#
#   probe key     /usr/local/sbin/lunaway-health: the health facts as JSON,
#                 which Gatus checks every few minutes; Gatus runs on this
#                 server (ops-status.sh made the key), so the key is
#                 accepted from the loopback only
#   erasures key  /usr/local/sbin/lunaway-extcom-erasures: the SHA-256 of
#                 every author of the external community source erased at
#                 the partner's request, which the feed's producer purges
#                 from its own copy (docs/deploy.md, "The external
#                 community feed"); the producer runs on this server too, so
#                 from the loopback only
#   Mac's key     rrsync -ro /srv/data/backups/offsite: the age-encrypted
#                 dumps and their markers, the encrypted photos (media/) and
#                 journals, pulled every night by the maintainer's Mac,
#                 accepted from the admin sources only
#
#   LUNAWAY_MAC_PULL_PUBKEY   the Mac's public key (infra/configure.sh reads
#       ~/.config/lunaway/backup-pull_ed25519.pub); empty until it exists
#   LUNAWAY_SSH_ALLOW         the admin sources, the only ones the Mac's key
#       is accepted from
#
# The probe key's public half is read from /etc/lunaway-ops/probe_ed25519.pub
# (ops-status.sh), the producer's from
# /etc/lunaway-ops/extcom-erasures_ed25519.pub, which its private deployment
# leaves there.
. "$(dirname "$0")/common.sh"
need_root
apt_install rsync
[ -x /usr/bin/rrsync ] || die "rrsync is missing from the rsync package"
getent group lunaway-pull >/dev/null || die "no group lunaway-pull; run the backups step first"

log "account"
if ! getent passwd lunaway-pull >/dev/null; then
  # A real shell: sshd runs the forced commands through it. The keys allow
  # nothing else (restrict, command=).
  useradd --system --gid lunaway-pull --home-dir /var/lib/lunaway-pull --no-create-home \
    --shell /bin/sh --comment "Lunaway read-only pulls: status probe, erasures list, the Mac's backups" lunaway-pull
fi
install_file files/usr/local/sbin/lunaway-health /usr/local/sbin/lunaway-health 0755 || true
install_file files/usr/local/sbin/lunaway-extcom-erasures /usr/local/sbin/lunaway-extcom-erasures 0755 || true

# The admin sources the Mac's key is accepted from: validated, joined with
# commas, without any range wider than /16 or /48 (after `ssh-access.sh
# open`, 0.0.0.0/0 is no admin source; the same floor as fail2ban's
# exemptions in harden.sh).
# shellcheck disable=SC2086 # one CIDR per word
admin_sources="$(python3 - ${LUNAWAY_SSH_ALLOW:-} <<'EOF'
import ipaddress, sys
nets = [ipaddress.ip_network(v, strict=False) for v in sys.argv[1:]]
print(",".join(str(n) for n in nets if n.prefixlen >= (16 if n.version == 4 else 48)))
EOF
)" || die "LUNAWAY_SSH_ALLOW is not a list of CIDRs"

log "keys"
install -d -m 0755 -o root -g root /var/lib/lunaway-pull /var/lib/lunaway-pull/.ssh
: > "$STAGING/pull-authorized_keys"
# add_key NAME SOURCES COMMAND KEY [WHEN MISSING]: one line of
# authorized_keys, from SOURCES only, forced to COMMAND.
add_key() {
  local name="$1" sources="$2" command="$3" key="$4" missing="${5:-}"
  if [ -z "$key" ]; then
    log "no $name key yet${missing:+ ($missing)}"
    return 0
  fi
  key="$(printf '%s' "$key" | cut -d' ' -f1,2)"
  [[ "$key" =~ $ED25519_PUBKEY_RE ]] || die "the $name key is not an Ed25519 public key"
  echo "restrict,from=\"$sources\",command=\"$command\" $key" >> "$STAGING/pull-authorized_keys"
}
read_key() { [ -f "$1" ] && head -n 1 "$1" || true; }
add_key probe "127.0.0.1,::1" /usr/local/sbin/lunaway-health \
  "$(read_key /etc/lunaway-ops/probe_ed25519.pub)" "run the ops-status step first"
add_key extcom-erasures "127.0.0.1,::1" /usr/local/sbin/lunaway-extcom-erasures \
  "$(read_key /etc/lunaway-ops/extcom-erasures_ed25519.pub)" "deploy the external community feed's producer first"
if [ -n "${LUNAWAY_MAC_PULL_PUBKEY:-}" ]; then
  [ -n "$admin_sources" ] || die "no admin source narrower than /16 or /48 in LUNAWAY_SSH_ALLOW to accept the Mac's key from"
fi
add_key "Mac's pull" "$admin_sources" "/usr/bin/rrsync -ro /srv/data/backups/offsite" \
  "${LUNAWAY_MAC_PULL_PUBKEY:-}" "infra/ops/mac/install.sh keys on the Mac"
# Root-owned: the account cannot change its own restrictions.
install_file "$STAGING/pull-authorized_keys" /var/lib/lunaway-pull/.ssh/authorized_keys 0644 || true

# sshd lets the account in from the loopback and the admin sources only, a
# second wall behind each key's from= (the Hetzner firewall already limits
# SSH to the admin sources from outside).
allow="AllowUsers lunaway-pull@127.0.0.1 lunaway-pull@::1"
for net in ${admin_sources//,/ }; do
  allow="$allow lunaway-pull@$net"
done
cat > "$STAGING/12-lunaway-pull.conf" <<EOF
# Written by infra/server/ops-access.sh: the read-only account, from the
# loopback (Gatus, the feed's producer) and the admin sources (the Mac's
# backups) only. Each key is forced to one command.
$allow
EOF
if install_file "$STAGING/12-lunaway-pull.conf" /etc/ssh/sshd_config.d/12-lunaway-pull.conf 0644; then
  if ! sshd -t; then
    rm -f /etc/ssh/sshd_config.d/12-lunaway-pull.conf
    die "sshd rejects the pull configuration; it was removed, sshd was not reloaded"
  fi
  systemctl reload ssh
fi
log "lunaway-pull: $(grep -c . /var/lib/lunaway-pull/.ssh/authorized_keys) key(s)"
