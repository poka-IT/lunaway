#!/usr/bin/env bash
# Installs, runs or removes the nightly ops job on the maintainer's Mac
# (launchd user agent legal.p2p.lunaway.ops, script lunaway-ops.sh).
#
#   infra/ops/mac/install.sh keys     the two keys only (first installation,
#                                     before infra/configure.sh)
#   infra/ops/mac/install.sh          keys, then the agent (idempotent)
#   infra/ops/mac/install.sh run      one run now, through launchd
#   infra/ops/mac/install.sh drill    one run now with a fake failure, which
#                                     opens (or updates) the alert issue; the
#                                     next normal run closes it
#   infra/ops/mac/install.sh remove   the agent goes; keys and backups stay
#
# Keys, both created once and never overwritten:
#   ~/.config/lunaway/backup-age.key       the age identity that decrypts the
#       dumps; the only copy, so keep an offline copy of it (a password
#       manager): without it every backup is unreadable. Its public half is
#       recorded as LUNAWAY_BACKUP_RECIPIENT and goes to the backend.
#   ~/.config/lunaway/ops-pull_ed25519     the pull key; the ops server
#       forces it to a read-only rsync of its replica.
set -euo pipefail
. "$(dirname "$0")/../../lib.sh"
label=legal.p2p.lunaway.ops
domain="gui/$(id -u)"
plist="$HOME/Library/LaunchAgents/$label.plist"
support="$HOME/Library/Application Support/Lunaway"
script="$support/lunaway-ops.sh"
log_file="$HOME/Library/Logs/lunaway-ops.log"
here="$(cd "$(dirname "$0")" && pwd)"

status_url() {
  if [ -n "${LUNAWAY_STATUS_DOMAIN:-}" ]; then
    echo "https://$LUNAWAY_STATUS_DOMAIN"
  else
    [ -n "$(role_var ops IPV4)" ] || die "no ops server in $LUNAWAY_ENV_FILE"
    echo "https://$(role_var ops IPV4 | tr . -).sslip.io"
  fi
}

make_keys() {
  local key="$LUNAWAY_CONFIG_DIR/backup-age.key" pull="$LUNAWAY_CONFIG_DIR/ops-pull_ed25519" recipient
  command -v age-keygen >/dev/null || die "age is needed (brew install age)"
  install -d -m 0700 "$LUNAWAY_CONFIG_DIR"
  if [ ! -f "$key" ]; then
    ( umask 077; age-keygen -o "$key" 2>/dev/null )
    log "created $key: keep an offline copy, it is the only key that decrypts the backups"
  fi
  chmod 0600 "$key"
  recipient="$(age-keygen -y "$key")"
  [ "${LUNAWAY_BACKUP_RECIPIENT:-}" = "$recipient" ] || env_set LUNAWAY_BACKUP_RECIPIENT "$recipient"
  if [ ! -f "$pull" ]; then
    ssh-keygen -q -t ed25519 -N '' -C "lunaway mac pull" -f "$pull"
    log "created $pull"
  fi
  chmod 0600 "$pull"
  write_ssh_config
  log "keys ready; the backend takes the recipient (configure.sh backend backups), the ops server the pull key (configure.sh ops ops-replica)"
}

install_agent() {
  local tool
  for tool in age jq gh rsync; do
    command -v "$tool" >/dev/null || die "$tool is needed"
  done
  [ -x /opt/homebrew/opt/libpq/bin/pg_restore ] || die "pg_restore is needed to verify the dumps (brew install libpq)"
  mkdir -p "$HOME/Backups"
  install -d -m 0700 "$support" "$HOME/Backups/lunaway"
  install -m 0700 "$here/lunaway-ops.sh" "$script"
  sed -e "s|__SCRIPT__|$script|" \
      -e "s|__STATUS_URL__|$(status_url)|" \
      -e "s|__ALERT_REPO__|${LUNAWAY_ALERT_REPO:-poka-IT/lunaway}|" \
      -e "s|__ALERT_GH_USER__|${LUNAWAY_ALERT_GH_USER:-poka-IT}|" \
      -e "s|__LOG__|$log_file|" \
      "$here/$label.plist" > "$plist.new"
  plutil -lint "$plist.new" >/dev/null || die "the rendered plist does not parse"
  chmod 0644 "$plist.new"
  mv "$plist.new" "$plist"
  launchctl bootout "$domain/$label" 2>/dev/null || true
  launchctl bootstrap "$domain" "$plist"
  log "installed $label: $(launchctl print "$domain/$label" | awk -F' = ' '/state =/ { print $2; exit }'), next run at 04:30"
}

case "${1:-install}" in
  keys) make_keys ;;
  install)
    make_keys
    install_agent
    ;;
  run)
    launchctl kickstart "$domain/$label"
    log "started; follow it with: tail -f $log_file"
    ;;
  drill)
    LUNAWAY_OPS_DRILL=1 LUNAWAY_STATUS_URL="$(status_url)" \
      LUNAWAY_ALERT_REPO="${LUNAWAY_ALERT_REPO:-poka-IT/lunaway}" LUNAWAY_ALERT_GH_USER="${LUNAWAY_ALERT_GH_USER:-poka-IT}" \
      /bin/sh "$script" 2>&1 | tee -a "$log_file"
    ;;
  remove)
    launchctl bootout "$domain/$label" 2>/dev/null || true
    rm -f "$plist" "$script"
    log "removed $label; kept the keys in $LUNAWAY_CONFIG_DIR and the backups in ~/Backups/lunaway"
    ;;
  *) die "usage: $0 [keys|install|run|drill|remove]" ;;
esac
