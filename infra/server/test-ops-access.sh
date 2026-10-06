#!/usr/bin/env bash
# Proves, from the ops server, what its two keys reach on the backend's
# lunaway-pull account over the private network, run as root by
# infra/verify.sh: the probe key gets the health JSON whatever it asks, the
# replica key can list and read the off-site directory, and everything else
# is refused (a shell, a write, a path outside the directory, forwarding).
. "$(dirname "$0")/common.sh"
need_root
backend_ip="${1:?backend private address}"
[[ "$backend_ip" =~ ^10\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "unexpected private address $backend_ip"
# rsync takes the replica's ssh command as one string; the probe has no Host
# block of its own.
replica_ssh="ssh -F /etc/lunaway-ops/ssh_config"
replica=(ssh -F /etc/lunaway-ops/ssh_config)
probe=(ssh -F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes -i /etc/lunaway-ops/probe_ed25519
  -o UserKnownHostsFile=/etc/lunaway-ops/known_hosts -o StrictHostKeyChecking=yes -o ConnectTimeout=20)
date -u +%Y-%m-%dT%H:%M:%SZ > "$STAGING/write-probe"

expect() {
  # expect ok|refused LABEL COMMAND...
  local want="$1" label="$2" out status=0
  shift 2
  # A probe that hangs counts as a failure, never as a stuck run.
  out="$(timeout 60 "$@" </dev/null 2>&1)" || status=$?
  if { [ "$want" = ok ] && [ "$status" = 0 ]; } || { [ "$want" = refused ] && [ "$status" != 0 ]; }; then
    echo "ok   $label ($want): $(echo "$out" | tail -n 1 | cut -c1-140)"
  else
    echo "FAIL $label (wanted $want, exit $status): $(echo "$out" | tail -n 1 | cut -c1-140)"
  fi
}

# The probe's forced command answers JSON to any request, a shell included.
answer="$(timeout 60 "${probe[@]}" "lunaway-pull@$backend_ip" id </dev/null 2>&1 || true)"
if python3 -c 'import json, sys; d = json.loads(sys.argv[1]); assert "postgresql" in d' "$answer" 2>/dev/null; then
  echo "ok   probe key, asked for id, answers the health JSON: $answer"
else
  echo "FAIL probe key answered something else: $(echo "$answer" | head -c 160)"
fi
expect refused "probe key: a forwarded connection" "${probe[@]}" -W 127.0.0.1:5432 "lunaway-pull@$backend_ip"

expect ok "replica key: list the off-site directory" rsync -e "$replica_ssh" --list-only backend-replica:
expect refused "replica key: a shell" "${replica[@]}" backend-replica id
expect refused "replica key: a write" rsync -rt -e "$replica_ssh" "$STAGING/write-probe" backend-replica:write-probe
expect refused "replica key: a file outside the directory" rsync -e "$replica_ssh" backend-replica:/etc/passwd "$STAGING/stolen"
expect refused "replica key: a parent path" rsync -r -e "$replica_ssh" backend-replica:../ "$STAGING/stolen"
expect refused "replica key: a forwarded connection" "${replica[@]}" -W 127.0.0.1:5432 backend-replica
expect refused "replica key: a remote forward" "${replica[@]}" -N -o ExitOnForwardFailure=yes -R 15432:127.0.0.1:22 backend-replica
rm -f "$STAGING/write-probe" "$STAGING/stolen"
