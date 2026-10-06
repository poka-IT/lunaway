#!/usr/bin/env bash
# Proves the sshd jail end to end without locking anyone out, run as root by
# infra/verify.sh: the filter recognises this boot's failed SSH attempts in
# the journal, and a ban reaches nftables. The ban targets 192.0.2.10, an
# address reserved for documentation (RFC 5737) that no client uses, and is
# lifted at once.
. "$(dirname "$0")/common.sh"
need_root
test_ip=192.0.2.10

echo "filter, on this boot's sshd journal:"
fail2ban-regex --journalmatch='_SYSTEMD_UNIT=ssh.service + _COMM=sshd' \
  systemd-journal 'sshd[mode=aggressive]' 2>/dev/null | grep -E '^Lines:|^Failregex:' || true

fail2ban-client set sshd banip "$test_ip" >/dev/null
sleep 1
if nft list table inet f2b-table 2>/dev/null | grep -q "$test_ip"; then
  echo "ban action: $test_ip is in nftables table inet f2b-table"
else
  echo "ban action: $test_ip NOT found in nftables"
fi
fail2ban-client set sshd unbanip "$test_ip" >/dev/null
sleep 1
if nft list table inet f2b-table 2>/dev/null | grep -q "$test_ip"; then
  echo "unban: $test_ip still in nftables"
else
  echo "unban: $test_ip removed"
fi
