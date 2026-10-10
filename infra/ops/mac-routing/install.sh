#!/usr/bin/env bash
# Installs, runs or removes the routing graph build on the maintainer's
# Mac: two launchd user agents, legal.p2p.lunaway.routing-build (triggered
# every Sunday at 03:00 local time, building every other week: the script
# stops at once while the published graph is less than 9 days old) and
# legal.p2p.lunaway.routing-sweep (hourly), both running
# lunaway-routing-build.sh (docs/deploy.md, "Routing").
#
#   infra/ops/mac-routing/install.sh keys      the signing key, created once
#   infra/ops/mac-routing/install.sh backup    an age-encrypted copy of the key
#                                              into the backup chain (backend,
#                                              ops server, this Mac)
#   infra/ops/mac-routing/install.sh           the script, its files, both agents
#   infra/ops/mac-routing/install.sh run       one build now, through launchd
#   infra/ops/mac-routing/install.sh sweep     one sweep now, through launchd
#   infra/ops/mac-routing/install.sh remove    both agents go; the key stays
#
# The signing key, ~/.config/lunaway/routing-signing_ed25519, signs the
# graph's SHA256SUMS; the backend accepts a graph only when its public half
# is a line of /etc/lunaway/routing-signers (infra/routing/routing-signers,
# installed by `infra/configure.sh backend routing`). It has no passphrase,
# since launchd runs the job unattended; the file is 0600 in a 0700
# directory, like the other keys of this Mac.
set -euo pipefail
. "$(dirname "$0")/../../lib.sh"
domain="gui/$(id -u)"
agents="$HOME/Library/LaunchAgents"
support="$HOME/Library/Application Support/Lunaway/routing"
script="$support/lunaway-routing-build.sh"
log_file="$HOME/Library/Logs/lunaway-routing-build.log"
here="$(cd "$(dirname "$0")" && pwd)"
key="$LUNAWAY_CONFIG_DIR/routing-signing_ed25519"
build_label=legal.p2p.lunaway.routing-build
sweep_label=legal.p2p.lunaway.routing-sweep

make_key() {
  install -d -m 0700 "$LUNAWAY_CONFIG_DIR"
  if [ ! -f "$key" ]; then
    ssh-keygen -q -t ed25519 -N "" -C lunaway-routing-mac -f "$key"
    log "created $key; back it up now: $0 backup"
  fi
  chmod 0600 "$key"
  local line
  line="lunaway-routing namespaces=\"lunaway-routing-graph\" $(cut -d' ' -f1,2 "$key.pub")"
  if grep -qF "$(cut -d' ' -f2 "$key.pub")" "$LUNAWAY_INFRA_DIR/routing/routing-signers"; then
    log "infra/routing/routing-signers already trusts this key"
  else
    log "add this line to infra/routing/routing-signers, commit, then run infra/configure.sh backend routing:"
    echo "$line"
  fi
}

backup_key() {
  # Same path as the F-Droid keys (infra/fdroid/keys.sh backup): encrypted
  # here to the backup recipient, written at the top of the backend's
  # off-site directory, pulled every night by the ops server and this Mac,
  # never pruned. The plaintext never leaves this machine.
  local recipient="${LUNAWAY_BACKUP_RECIPIENT:-}" stamp name out local_sum remote_sum
  [[ "$recipient" =~ ^age1[02-9ac-hj-np-z]{58}$ ]] || die "LUNAWAY_BACKUP_RECIPIENT is not an age recipient"
  [ -f "$key" ] || die "no key $key: $0 keys"
  require_host
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  name="routing-signing-key-$stamp.age"
  out="$LUNAWAY_REPO_DIR/data/tmp/routing-key/$name"
  install -d -m 0700 "$LUNAWAY_REPO_DIR/data/tmp/routing-key"
  age -r "$recipient" -o "$out" "$key"
  # The copy must open with the identity, and give back this key, before it
  # counts as a backup.
  age --decrypt --identity "$LUNAWAY_CONFIG_DIR/backup-age.key" "$out" | cmp -s - "$key" \
    || die "the encrypted copy does not give the key back"
  local_sum="$(shasum -a 256 "$out" | awk '{ print $1 }')"
  lunaway_ssh "sudo tee /srv/data/backups/offsite/$name >/dev/null \
    && sudo chown root:lunaway-pull /srv/data/backups/offsite/$name \
    && sudo chmod 0640 /srv/data/backups/offsite/$name" <"$out"
  remote_sum="$(lunaway_ssh "sudo sha256sum /srv/data/backups/offsite/$name" | awk '{ print $1 }')"
  [ "$remote_sum" = "$local_sum" ] || die "the copy on the backend differs from the one encrypted here"
  rm -f "$out"
  log "backend:/srv/data/backups/offsite/$name ($local_sum); the ops server pulls it at 01:15 UTC, this Mac at 04:30"
}

render() {
  local label=$1
  sed -e "s|__SCRIPT__|$script|" -e "s|__LOG__|$log_file|" \
    -e "s|__ALERT_GH_USER__|${LUNAWAY_ALERT_GH_USER:-poka-IT}|" \
    "$here/$label.plist" >"$agents/$label.plist.new"
  plutil -lint "$agents/$label.plist.new" >/dev/null || die "the rendered $label plist does not parse"
  chmod 0644 "$agents/$label.plist.new"
  mv "$agents/$label.plist.new" "$agents/$label.plist"
  launchctl bootout "$domain/$label" 2>/dev/null || true
  launchctl bootstrap "$domain" "$agents/$label.plist"
}

install_agents() {
  local tool
  [ -x /opt/homebrew/bin/bash ] || die "Homebrew's bash is needed (brew install bash)"
  for tool in hcloud gh jq age python3; do
    command -v "$tool" >/dev/null || die "$tool is needed"
  done
  [ -f "$key" ] || die "no signing key: $0 keys"
  grep -qF "$(cut -d' ' -f2 "$key.pub")" "$LUNAWAY_INFRA_DIR/routing/routing-signers" \
    || die "infra/routing/routing-signers does not trust $key.pub yet: $0 keys"
  install -d -m 0700 "$support"
  install -m 0700 "$here/lunaway-routing-build.sh" "$script"
  install -m 0600 "$LUNAWAY_INFRA_DIR/routing/routing-signers" "$support/routing-signers"
  install -m 0600 "$LUNAWAY_INFRA_DIR/routing/europe-extracts.txt" "$support/europe-extracts.txt"
  mkdir -p "$agents"
  render "$build_label"
  render "$sweep_label"
  log "installed $build_label (triggered Sundays 03:00, a build every two weeks) and $sweep_label (hourly); log: $log_file"
}

case "${1:-install}" in
  keys) make_key ;;
  backup) backup_key ;;
  install) install_agents ;;
  run)
    launchctl kickstart "$domain/$build_label"
    log "started; follow it with: tail -f $log_file"
    ;;
  sweep) launchctl kickstart "$domain/$sweep_label" ;;
  remove)
    launchctl bootout "$domain/$build_label" 2>/dev/null || true
    launchctl bootout "$domain/$sweep_label" 2>/dev/null || true
    rm -f "$agents/$build_label.plist" "$agents/$sweep_label.plist" "$script"
    log "removed both agents; kept $key and $support/state"
    ;;
  *) die "usage: $0 [keys|backup|install|run|sweep|remove]" ;;
esac
