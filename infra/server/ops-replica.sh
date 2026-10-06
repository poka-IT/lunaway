#!/usr/bin/env bash
# The dump replica of the ops server, run as root by setup.sh: a second copy
# of the backend's encrypted dumps in another datacenter, 14 days kept, and
# of its encrypted photos (media/, deletions held 26 days), and the
# read-only account the maintainer's Mac pulls them through.
#
#   lunaway-backup            static user of lunaway-replica.service; owns the
#                             replica and the replica key
#   /srv/data/backups/postgresql   the replica (ciphertext only: the age key
#                             is on the Mac)
#   /etc/lunaway-ops/         the replica key (its public half goes to the
#                             backend's lunaway-pull account), the backend's
#                             pinned host key, an ssh_config with Host
#                             backend-replica
#   lunaway-pull              the Mac's account: its key is forced to
#                             rrsync -ro on the replica and accepted only
#                             from the admin sources
#
#   LUNAWAY_BACKEND_HOSTKEY     the backend's Ed25519 host key
#   LUNAWAY_BACKEND_PRIVATE_IP  its address on the private network
#   LUNAWAY_MAC_PULL_PUBKEY     the Mac's pull key (infra/ops/mac/install.sh),
#                               empty until it exists
#   LUNAWAY_SSH_ALLOW           the admin sources, the only ones the Mac's
#                               key is accepted from
. "$(dirname "$0")/common.sh"
need_root
mountpoint -q /srv/data || die "/srv/data is not mounted; run data-volume.sh first"
backend_ip="${LUNAWAY_BACKEND_PRIVATE_IP:?set LUNAWAY_BACKEND_PRIVATE_IP}"
[[ "$backend_ip" =~ ^10\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "unexpected private address $backend_ip"
hostkey="${LUNAWAY_BACKEND_HOSTKEY:-}"
[[ "$hostkey" =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+$ ]] || die "LUNAWAY_BACKEND_HOSTKEY is not an Ed25519 host key"
apt_install rsync openssh-client
[ -x /usr/bin/rrsync ] || die "rrsync is missing from the rsync package"

log "replica"
getent group lunaway-pull >/dev/null || groupadd --system lunaway-pull
if ! getent passwd lunaway-backup >/dev/null; then
  useradd --system --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin \
    --comment "Lunaway dump replica" --user-group lunaway-backup
fi
install -d -m 0755 -o root -g root /srv/data/backups
# Group lunaway-pull reads it (setgid: new files take the group).
install -d -m 2750 -o lunaway-backup -g lunaway-pull /srv/data/backups/postgresql
# Photos deleted on the backend, held 26 days (lunaway-replica); the Mac's
# key does not reach them.
install -d -m 0750 -o lunaway-backup -g lunaway-backup /srv/data/backups/media-deleted
# The photos' copy: plain 0755 directories, without the setgid bit the
# replica directory would hand down. rsync keeps a setgid bit it finds on a
# directory, and the replica unit's RestrictSUIDSGID refuses that chmod.
# The replica directory (2750) still keeps everyone but lunaway-pull out.
install -d -m 0755 -o lunaway-backup -g lunaway-pull /srv/data/backups/postgresql/media
find /srv/data/backups/postgresql/media -type d -perm -2000 -exec chmod g-s {} +

log "replica key and the backend's host key"
install -d -m 0755 -o root -g root /etc/lunaway-ops
if [ ! -f /etc/lunaway-ops/replica_ed25519 ]; then
  ssh-keygen -q -t ed25519 -N '' -C "lunaway ops replica" -f /etc/lunaway-ops/replica_ed25519
  echo "    generated the replica key; run infra/configure.sh backend ops-access so the backend accepts it"
fi
chown lunaway-backup:lunaway-backup /etc/lunaway-ops/replica_ed25519
chmod 0600 /etc/lunaway-ops/replica_ed25519
chmod 0644 /etc/lunaway-ops/replica_ed25519.pub
echo "$backend_ip $hostkey" > "$STAGING/known_hosts"
install_file "$STAGING/known_hosts" /etc/lunaway-ops/known_hosts 0644 || true
cat > "$STAGING/ssh_config" <<EOF
# Written by infra/server/ops-replica.sh. The backend forces this key to
# rrsync -ro /srv/data/backups/offsite (its lunaway-pull account).
Host backend-replica
  HostName $backend_ip
  User lunaway-pull
  IdentityFile /etc/lunaway-ops/replica_ed25519
  IdentitiesOnly yes
  UserKnownHostsFile /etc/lunaway-ops/known_hosts
  StrictHostKeyChecking yes
  BatchMode yes
  ConnectTimeout 20
EOF
install_file "$STAGING/ssh_config" /etc/lunaway-ops/ssh_config 0644 || true

log "replica service"
changed=0
install_file files/usr/local/sbin/lunaway-replica /usr/local/sbin/lunaway-replica 0755 || true
sed "s/__BACKEND_PRIVATE_IP__/$backend_ip/" "$INFRA/systemd/lunaway-replica.service" > "$STAGING/lunaway-replica.service"
install_file "$STAGING/lunaway-replica.service" /etc/systemd/system/lunaway-replica.service 0644 && changed=1
install_file systemd/lunaway-replica.timer /etc/systemd/system/lunaway-replica.timer 0644 && changed=1
[ "$changed" = 1 ] && systemctl daemon-reload
systemctl enable --quiet --now lunaway-replica.timer

log "the Mac's pull account"
if ! getent passwd lunaway-pull >/dev/null; then
  # A real shell: sshd runs the forced command through it.
  useradd --system --gid lunaway-pull --home-dir /var/lib/lunaway-pull --no-create-home \
    --shell /bin/sh --comment "Lunaway maintainer's Mac, read-only pulls" lunaway-pull
fi
install -d -m 0755 -o root -g root /var/lib/lunaway-pull /var/lib/lunaway-pull/.ssh
: > "$STAGING/pull-authorized_keys"
key="${LUNAWAY_MAC_PULL_PUBKEY:-}"
if [ -n "$key" ]; then
  [[ "$key" =~ $ED25519_PUBKEY_RE ]] || die "LUNAWAY_MAC_PULL_PUBKEY is not an Ed25519 public key"
  # from= takes the admin sources (the same ones the Hetzner firewall lets
  # reach SSH), validated and joined with commas, without any range wider
  # than /16 or /48: after `ssh-access.sh open`, 0.0.0.0/0 is no admin source
  # (the same floor as fail2ban's exemptions in harden.sh).
  # shellcheck disable=SC2086 # one CIDR per word
  sources="$(python3 - ${LUNAWAY_SSH_ALLOW:-} <<'EOF'
import ipaddress, sys
nets = [ipaddress.ip_network(v, strict=False) for v in sys.argv[1:]]
print(",".join(str(n) for n in nets if n.prefixlen >= (16 if n.version == 4 else 48)))
EOF
)" || die "LUNAWAY_SSH_ALLOW is not a list of CIDRs"
  [ -n "$sources" ] || die "no admin source narrower than /16 or /48 in LUNAWAY_SSH_ALLOW to accept the Mac's key from"
  echo "restrict,from=\"$sources\",command=\"/usr/bin/rrsync -ro /srv/data/backups/postgresql\" $key" \
    > "$STAGING/pull-authorized_keys"
else
  log "no LUNAWAY_MAC_PULL_PUBKEY yet (run infra/ops/mac/install.sh keys on the Mac)"
fi
# Root-owned: the account cannot change its own restrictions.
install_file "$STAGING/pull-authorized_keys" /var/lib/lunaway-pull/.ssh/authorized_keys 0644 || true
cat > "$STAGING/12-lunaway-pull.conf" <<'EOF'
# Written by infra/server/ops-replica.sh: the maintainer's Mac pulls the
# replica as lunaway-pull. Its key is forced to a read-only rsync and accepted
# from the admin sources only (authorized_keys).
AllowUsers lunaway-pull
EOF
if install_file "$STAGING/12-lunaway-pull.conf" /etc/ssh/sshd_config.d/12-lunaway-pull.conf 0644; then
  if ! sshd -t; then
    rm -f /etc/ssh/sshd_config.d/12-lunaway-pull.conf
    die "sshd rejects the pull configuration; it was removed, sshd was not reloaded"
  fi
  systemctl reload ssh
fi
log "replica: $(find /srv/data/backups/postgresql -maxdepth 1 -name 'lunaway-*.dump.age' | wc -l) dump(s); next pull $(systemctl show lunaway-replica.timer -p NextElapseUSecRealtime --value)"
