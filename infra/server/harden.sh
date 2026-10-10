#!/usr/bin/env bash
# Base hardening of a Lunaway server (Debian 13, any role), run as root by
# setup.sh with LUNAWAY_ROLE set.
# Installs the files of infra/files (the ones cloud-init wrote at first boot),
# the SSH algorithm policy once this OpenSSH is known to support it, swap on
# compressed memory (zram), and enables the services that enforce the policy.
# Idempotent: a second run changes and reloads only what differs.
. "$(dirname "$0")/common.sh"
need_root
# shellcheck disable=SC1091
. /etc/os-release
[ "${VERSION_CODENAME:-}" = trixie ] || die "expected Debian 13 (trixie), found ${PRETTY_NAME:-unknown}"

log "packages"
# Caddy's former apt source answers 402 and would stop the update below.
remove_caddy_apt_source
apt-get update -q >/dev/null
apt_install nftables fail2ban python3-systemd unattended-upgrades needrestart chrony \
  apparmor apparmor-utils ca-certificates curl gnupg openssl systemd-zram-generator

log "configuration files"
ssh_changed=0 nft_changed=0 sysctl_changed=0 f2b_changed=0 journald_changed=0 units_changed=0
install_file files/etc/ssh/sshd_config.d/10-lunaway.conf /etc/ssh/sshd_config.d/10-lunaway.conf 0644 && ssh_changed=1
# The role file goes in first: the base ruleset includes it, and the check
# below parses both together before anything is loaded.
role="${LUNAWAY_ROLE:?set LUNAWAY_ROLE (backend)}"
[ -f "$INFRA/files/roles/$role/nftables.nft" ] || die "unknown role $role"
install_file "files/roles/$role/nftables.nft" /etc/nftables.d/lunaway-role.nft 0644 && nft_changed=1
nft -c -f "$INFRA/files/etc/nftables.conf" || die "nftables ruleset does not parse"
install_file files/etc/nftables.conf /etc/nftables.conf 0755 && nft_changed=1
install_file files/etc/sysctl.d/90-lunaway.conf /etc/sysctl.d/90-lunaway.conf 0644 && sysctl_changed=1
install_file files/etc/modprobe.d/lunaway-blacklist.conf /etc/modprobe.d/lunaway-blacklist.conf 0644 || true
install_file files/etc/security/limits.d/90-lunaway-nocore.conf /etc/security/limits.d/90-lunaway-nocore.conf 0644 || true
install_file files/etc/fail2ban/jail.d/lunaway.local /etc/fail2ban/jail.d/lunaway.local 0644 && f2b_changed=1
# The admin sources (LUNAWAY_SSH_ALLOW, passed by configure.sh) are the only
# ones the Hetzner firewall lets reach SSH; banning them protects nothing with
# keys-only logins and would lock the maintainer out. Every other address
# stays subject to the jail, which matters once SSH is opened wider. A range
# wider than /16 (IPv4) or /48 (IPv6), such as the 0.0.0.0/0 of
# `ssh-access.sh open`, is no admin source and never exempt.
admin_sources="${LUNAWAY_SSH_ALLOW:-}"
# shellcheck disable=SC2086 # one CIDR per word
exempt="$(python3 - $admin_sources <<'EOF'
import ipaddress, sys
kept = []
for value in sys.argv[1:]:
    try:
        net = ipaddress.ip_network(value, strict=False)
    except ValueError:
        sys.exit("LUNAWAY_SSH_ALLOW holds something else than CIDRs: " + value)
    if net.prefixlen >= (16 if net.version == 4 else 48):
        kept.append(str(net))
    else:
        print("    not exempt from fail2ban, too wide: " + str(net), file=sys.stderr)
print(" ".join(kept))
EOF
)" || die "LUNAWAY_SSH_ALLOW is not a list of CIDRs"
# The loopback stays exempt: Gatus's probe and the crawler log in as
# lunaway-pull and extcom-drop on 127.0.0.1, and a ban (it happened on
# 2026-10-06, when Gatus started before the backend knew the account) would
# turn every backend check red, for no gain with key-only logins.
cat > "$STAGING/lunaway-ignore.local" <<EOF
# Written by infra/server/harden.sh from LUNAWAY_SSH_ALLOW (infra/ssh-access.sh).
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 $exempt
EOF
install_file "$STAGING/lunaway-ignore.local" /etc/fail2ban/jail.d/lunaway-ignore.local 0644 && f2b_changed=1
install_file files/etc/apt/apt.conf.d/20auto-upgrades /etc/apt/apt.conf.d/20auto-upgrades 0644 || true
install_file files/etc/apt/apt.conf.d/52lunaway-unattended-upgrades /etc/apt/apt.conf.d/52lunaway-unattended-upgrades 0644 || true
install_file files/etc/needrestart/conf.d/lunaway.conf /etc/needrestart/conf.d/lunaway.conf 0644 || true
install_file files/etc/systemd/journald.conf.d/lunaway.conf /etc/systemd/journald.conf.d/lunaway.conf 0644 && journald_changed=1
install_file systemd/apt-daily.timer.d/lunaway.conf /etc/systemd/system/apt-daily.timer.d/lunaway.conf 0644 && units_changed=1
install_file systemd/apt-daily-upgrade.timer.d/lunaway.conf /etc/systemd/system/apt-daily-upgrade.timer.d/lunaway.conf 0644 && units_changed=1

log "SSH algorithms"
crypto="$INFRA/files/etc/ssh/sshd_config.d/11-lunaway-crypto.conf"
check_algorithms() {
  local keyword="$1" query="$2" known name
  known="$(ssh -Q "$query")"
  for name in $(awk -v k="$keyword" '$1 == k { gsub(",", " ", $2); print $2 }' "$crypto"); do
    grep -qxF "$name" <<<"$known" || die "this OpenSSH does not know $keyword $name"
  done
}
check_algorithms KexAlgorithms kex
check_algorithms Ciphers cipher
check_algorithms MACs mac
check_algorithms HostKeyAlgorithms HostKeyAlgorithms
[ -f /etc/ssh/ssh_host_ed25519_key ] || die "no Ed25519 host key"
rsa_bits="$(ssh-keygen -l -f /etc/ssh/ssh_host_rsa_key.pub | awk '{ print $1 }')"
[ "$rsa_bits" -ge 3072 ] || die "RSA host key has $rsa_bits bits, below the 3072 the policy requires"
install_file files/etc/ssh/sshd_config.d/11-lunaway-crypto.conf /etc/ssh/sshd_config.d/11-lunaway-crypto.conf 0644 && ssh_changed=1
if [ "$ssh_changed" = 1 ]; then
  if ! sshd -t; then
    rm -f /etc/ssh/sshd_config.d/11-lunaway-crypto.conf
    die "sshd rejects the new configuration; the algorithm file was removed, sshd was not reloaded"
  fi
  # A reload keeps the open sessions, this one included.
  systemctl reload ssh
fi

log "root account"
passwd --lock root >/dev/null
if [ -s /root/.ssh/authorized_keys ]; then : > /root/.ssh/authorized_keys; fi

log "firewall, kernel, fail2ban, journal"
[ "$sysctl_changed" = 1 ] && sysctl --quiet --system
systemctl enable --quiet nftables
if systemctl is-active --quiet nftables; then
  # reload, not restart: the unit's stop step flushes the whole ruleset,
  # fail2ban's bans included.
  [ "$nft_changed" = 1 ] && systemctl reload nftables
else
  systemctl start nftables
fi
systemctl enable --quiet fail2ban
if [ "$f2b_changed" = 1 ] || ! systemctl is-active --quiet fail2ban; then systemctl restart fail2ban; fi
[ "$journald_changed" = 1 ] && systemctl restart systemd-journald
[ "$units_changed" = 1 ] && systemctl daemon-reload
systemctl enable --quiet --now chrony unattended-upgrades apt-daily.timer apt-daily-upgrade.timer
[ "$(aa-enabled 2>/dev/null)" = "Yes" ] || die "AppArmor is not enabled"

log "time zone"
[ "$(timedatectl show -p Timezone --value)" = "Etc/UTC" ] || timedatectl set-timezone Etc/UTC

log "swap on zram"
# Swap lives in compressed memory (half the RAM at most, 4 GiB at most): room
# for an index build peak, and nothing swapped out ever reaches a disk, which
# the root disk's Hetzner backups would otherwise capture. It replaces the
# swap file of the first installations.
# A changed size applies at the next boot: restarting the setup unit under
# an active swap made the swap unit flap into its start limit (2026-10-06).
install_file files/etc/systemd/zram-generator.conf /etc/systemd/zram-generator.conf 0644 && systemctl daemon-reload
systemctl reset-failed dev-zram0.swap 2>/dev/null || true
systemctl start dev-zram0.swap
swapon --show=NAME --noheadings | grep -qx /dev/zram0 || die "no swap on /dev/zram0"
if swapon --show=NAME --noheadings | grep -qx /swapfile; then
  swapoff /swapfile
  echo "    swap file turned off"
fi
if grep -q '^/swapfile ' /etc/fstab; then
  sed -i '\|^/swapfile |d' /etc/fstab
  systemctl daemon-reload
fi
rm -f /swapfile

if [ -f /run/reboot-required ]; then
  log "a reboot is required ($(tr '\n' ' ' < /run/reboot-required.pkgs 2>/dev/null))"
fi
log "hardening applied"
