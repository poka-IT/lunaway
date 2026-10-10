#!/usr/bin/env bash
# The translation server of the backend, run as root by setup.sh
# (docs/deploy.md, "Translation"): the translate account, the Python
# packages pinned with their hashes (infra/translate/requirements.txt) in
# a virtual environment, the models of infra/translate/models.txt
# (lunaway-translate-models), and lunaway-translate.service listening on
# 127.0.0.1:2324 for Caddy alone (geocoders.caddy).
. "$(dirname "$0")/common.sh"
need_root

log "packages"
apt_install python3 python3-venv curl ca-certificates

log "translate account and directories"
getent group translate >/dev/null || groupadd --system translate
getent passwd translate >/dev/null || useradd --system --gid translate --home-dir /srv/translate --no-create-home --shell /usr/sbin/nologin translate
install -d -m 0755 -o root -g root /opt/lunaway-translate /usr/local/lib/lunaway-translate /usr/local/share/lunaway/translate
install -d -m 0750 -o translate -g translate /srv/translate

log "Python packages"
# One environment per set of pins, built beside the one in use and then
# switched to: a failed install leaves the running server as it was.
pins="$(sha256sum "$INFRA/translate/requirements.txt" | cut -c1-12)"
venv="/opt/lunaway-translate/venv-$pins"
changed=0
if [ ! -x "$venv/bin/python" ] || [ ! -f "$venv/.complete" ]; then
  rm -rf --one-file-system "$venv"
  python3 -m venv "$venv"
  # Wheels only, each checked against its hash: no package runs code of
  # its own at install time.
  "$venv/bin/pip" install -q --disable-pip-version-check --no-cache-dir \
    --require-hashes --only-binary=:all: --no-deps -r "$INFRA/translate/requirements.txt"
  touch "$venv/.complete"
  echo "    installed $venv"
fi
if [ "$(readlink /opt/lunaway-translate/venv 2>/dev/null || true)" != "$venv" ]; then
  ln -sfn "$venv" /opt/lunaway-translate/venv
  changed=1
fi
# Environments of older pins.
for old in /opt/lunaway-translate/venv-*; do
  [ "$old" = "$venv" ] && continue
  [[ "$(basename "$old")" =~ ^venv-[0-9a-f]{12}$ ]] && rm -rf --one-file-system "$old"
done

log "files and units"
install_file translate/lunaway-translate.py /usr/local/lib/lunaway-translate/server.py 0644 && changed=1
install_file translate/models.txt /usr/local/share/lunaway/translate/models.txt 0644 || true
install_file translate/lunaway-translate-models /usr/local/sbin/lunaway-translate-models 0755 || true
install_file translate/lunaway-translate.service /etc/systemd/system/lunaway-translate.service 0644 && changed=1
install_file translate/lunaway-translate-models.service /etc/systemd/system/lunaway-translate-models.service 0644 || true
systemctl daemon-reload

log "models"
# The releases served, to restart the server when one changed.
served() { find /srv/translate/models -mindepth 2 -maxdepth 2 -name current -printf '%h %l\n' 2>/dev/null | sort; }
before="$(served || true)"
# About 9.6 GB to download the first time (5.6 GB took under three
# minutes, conversion included, on 2026-10-09), then nothing while
# models.txt is unchanged.
systemctl start lunaway-translate-models.service
after="$(served)"
[ "$before" = "$after" ] || changed=1
log "$(printf '%s\n' "$after" | grep -c . || true) pairs served"

systemctl enable --quiet lunaway-translate.service
if [ "$changed" = 1 ] || ! systemctl is-active --quiet lunaway-translate.service; then
  systemctl restart lunaway-translate.service
fi
for _ in $(seq 1 60); do
  curl -fsS -o /dev/null --max-time 5 http://127.0.0.1:2324/health 2>/dev/null && break
  sleep 2
done
log "lunaway-translate: $(curl -fsS --max-time 10 http://127.0.0.1:2324/health || echo 'no answer')"
