#!/usr/bin/env bash
# Which addresses may reach SSH (22/tcp) through the Hetzner Cloud Firewalls
# of both servers.
# The host firewall leaves 22/tcp open (keys only, fail2ban), so this rule is
# the allowlist, and changing it needs only the Hetzner API: nobody is locked
# out for good by a new home address, a hotel or a phone hotspot.
#
#   infra/ssh-access.sh show
#   infra/ssh-access.sh add-current     add this machine's current address
#   infra/ssh-access.sh set CIDR...     replace the list
#   infra/ssh-access.sh open            any address (keys and fail2ban still apply)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
require_hcloud

apply() {
  local role
  [ "$#" -gt 0 ] || die "no CIDR given"
  cidr_list_ok "$@" || die "not a list of CIDRs: $*"
  for role in backend ops; do
    hcloud firewall describe "$(role_get "$role" firewall)" >/dev/null 2>&1 || continue
    firewall_rules_json "$role" "$@" | hcloud firewall replace-rules --rules-file - "$(role_get "$role" firewall)" >/dev/null
  done
  env_set LUNAWAY_SSH_ALLOW "$*"
  log "SSH allowed from: $*"
  log "run infra/configure.sh backend harden and infra/configure.sh ops harden ops-replica to refresh fail2ban's ignore lists and the pull key's sources"
}

case "${1:-show}" in
  show)
    for role in backend ops; do
      echo "$(role_get "$role" firewall):"
      hcloud firewall describe "$(role_get "$role" firewall)" -o json 2>/dev/null | python3 -c '
import json, sys
for r in json.load(sys.stdin)["rules"]:
    print("  ", r["direction"], r["protocol"], r.get("port") or "-", ",".join(r["source_ips"]), "#", r.get("description") or "")'
    done
    ;;
  add-current)
    v4="$(current_ipv4)"
    v6="$(current_ipv6_64)"
    # shellcheck disable=SC2086,SC2046 # one CIDR per word
    apply $(printf '%s\n' ${LUNAWAY_SSH_ALLOW:-} ${v4:+$v4/32} $v6 | awk 'NF && !seen[$0]++')
    ;;
  set)
    shift
    [ "$#" -gt 0 ] || die "usage: $0 set CIDR..."
    apply "$@"
    ;;
  open)
    apply 0.0.0.0/0 ::/0
    ;;
  *)
    die "usage: $0 show | add-current | set CIDR... | open"
    ;;
esac
