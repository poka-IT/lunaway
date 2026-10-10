#!/usr/bin/env bash
# Proves what each key of the backend's lunaway-pull and extcom-drop
# accounts reaches over SSH on the loopback, run on the backend as root by
# infra/verify.sh: the status page's probe key gets the health JSON
# whatever it asks; the crawler's erasures key gets the list of erased
# authors and nothing else; the crawler's push key may neither list the
# inbox nor open a shell; no key opens a forwarded connection. Nothing is
# written into the inbox: a file there would be imported, or need removing.
# The Mac's key, accepted from the admin sources only, is tried from the Mac
# by verify.sh.
#
#   sudo bash ~/infra/server/test-ops-access.sh
. "$(dirname "$0")/common.sh"
need_root
[ "$#" = 0 ] || die "no argument: the keys are tried on this server's loopback"

# On the loopback no other host can answer, so the host key is not pinned:
# whatever answers 127.0.0.1:22 is this server's own sshd. LogLevel=ERROR
# keeps ssh's "Permanently added" notice out of the answers.
ssh_opts=(-F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null
  -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=20)

expect() {
  # expect ok|refused LABEL COMMAND...
  local want="$1" label="$2" out status=0
  shift 2
  # A probe that hangs counts as a failure, never as a stuck run.
  out="$(timeout 60 "$@" </dev/null 2>&1)" || status=$?
  # A key sshd did not let in is refused everything, which proves nothing
  # about what its forced command allows.
  if [ "$want" = refused ] && grep -qE 'Permission denied \(publickey|Connection refused|Connection timed out' <<<"$out"; then
    echo "FAIL $label: the key was not let in, which proves nothing: $(echo "$out" | tail -n 1 | cut -c1-140)"
    return
  fi
  if { [ "$want" = ok ] && [ "$status" = 0 ]; } || { [ "$want" = refused ] && [ "$status" != 0 ]; }; then
    echo "ok   $label ($want): $(echo "$out" | tail -n 1 | cut -c1-140)"
  else
    echo "FAIL $label (wanted $want, exit $status): $(echo "$out" | tail -n 1 | cut -c1-140)"
  fi
}

# The status page's probe key (ops-status.sh). Its forced command answers
# JSON to any request, a shell included.
if [ -f /etc/lunaway-ops/probe_ed25519 ]; then
  probe=(ssh "${ssh_opts[@]}" -i /etc/lunaway-ops/probe_ed25519)
  answer="$(timeout 60 "${probe[@]}" lunaway-pull@127.0.0.1 id </dev/null 2>&1 || true)"
  if python3 -c 'import json, sys; d = json.loads(sys.argv[1]); assert "postgresql" in d' "$answer" 2>/dev/null; then
    echo "ok   probe key, asked for id, answers the health JSON: $(echo "$answer" | head -c 160)"
  else
    echo "FAIL probe key answered something else: $(echo "$answer" | head -c 160)"
  fi
  expect refused "probe key: a forwarded connection" "${probe[@]}" -W 127.0.0.1:5432 lunaway-pull@127.0.0.1
else
  echo "FAIL no /etc/lunaway-ops/probe_ed25519: run the ops-status step"
fi

# The crawler of the external community feed comes from a private
# deployment, which keeps its keys in a directory of /etc of its own. The
# partner is named nowhere in this repository, so the keys are found by
# their file names.
crawler_key() {
  local key
  for key in /etc/*/"$1"; do
    [ -f "$key" ] && { echo "$key"; return 0; }
  done
  return 1
}

# The erasures key: its forced command prints the SHA-256 of each erased
# author, one per line, whatever was asked, or nothing while no author was
# erased.
if erasures_key="$(crawler_key erasures_ed25519)"; then
  erasures=(ssh "${ssh_opts[@]}" -i "$erasures_key")
  status=0
  list="$(timeout 60 "${erasures[@]}" lunaway-pull@127.0.0.1 id </dev/null 2>"$STAGING/erasures.err")" || status=$?
  said="$(tail -n 1 "$STAGING/erasures.err" | cut -c1-140)"
  other="$(printf '%s\n' "$list" | grep -vxE '([0-9a-f]{64})?' || true)"
  if [ "$status" = 255 ] || [ "$status" = 124 ]; then
    echo "FAIL erasures key ($erasures_key), asked for id: no answer from its forced command (exit $status): $said"
  elif [ -z "$other" ]; then
    echo "ok   erasures key ($erasures_key), asked for id, answers $(printf '%s' "$list" | grep -c .) hash(es) of 64 hex digits and nothing else (exit $status${said:+: $said})"
  else
    echo "FAIL erasures key ($erasures_key) answered something else than hashes: $(echo "$other" | head -n 1 | cut -c1-140)"
  fi
  expect refused "erasures key: a forwarded connection" "${erasures[@]}" -W 127.0.0.1:5432 lunaway-pull@127.0.0.1
else
  echo "note no /etc/*/erasures_ed25519: the crawler is not deployed here, its erasures key is not tried"
fi

# The push key of extcom-drop, forced to a write-only rsync into the inbox:
# what it may not do, never a write.
if push_key="$(crawler_key push_ed25519)"; then
  push=(ssh "${ssh_opts[@]}" -i "$push_key")
  push_rsh="ssh ${ssh_opts[*]} -i $push_key"
  echo "push key: $push_key"
  expect refused "push key: a listing of the inbox" rsync -e "$push_rsh" --list-only extcom-drop@127.0.0.1:
  expect refused "push key: a shell" "${push[@]}" extcom-drop@127.0.0.1 id
  expect refused "push key: a forwarded connection" "${push[@]}" -W 127.0.0.1:5432 extcom-drop@127.0.0.1
else
  echo "note no /etc/*/push_ed25519: the crawler is not deployed here, its push key is not tried"
fi
