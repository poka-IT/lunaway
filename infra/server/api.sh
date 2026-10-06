#!/usr/bin/env bash
# The lunaway-api service, run as root by setup.sh: release directories, the
# sandboxed unit, the environment file. The binary itself arrives with
# infra/deploy-api.sh; until then the unit is enabled but not started.
. "$(dirname "$0")/common.sh"
need_root

install -d -m 0755 /opt/lunaway /opt/lunaway/releases
install -d -m 0700 -o root -g root /etc/lunaway
if [ ! -f /etc/lunaway/api.env ]; then
  ( umask 077; : > /etc/lunaway/api.env )
fi
chmod 0600 /etc/lunaway/api.env

changed=0
install_file systemd/lunaway-api.service /etc/systemd/system/lunaway-api.service 0644 && changed=1
[ "$changed" = 1 ] && systemctl daemon-reload
systemctl enable --quiet lunaway-api
if [ -x /opt/lunaway/current/lunaway-api ]; then
  if [ "$changed" = 1 ] || ! systemctl is-active --quiet lunaway-api; then
    systemctl restart lunaway-api
  fi
  log "lunaway-api $(systemctl is-active lunaway-api)"
else
  log "lunaway-api installed, waiting for its first binary (infra/deploy-api.sh)"
fi
