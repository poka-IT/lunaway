#!/usr/bin/env bash
# Caddy on the backend, run as root by setup.sh: the package (pinned signing
# key, common.sh), the rendered Caddyfile, the lunaway.net sites (available,
# enabled only by infra/enable-domain.sh), the web roots with a placeholder
# page, and a sandbox drop-in for the service. Every public site is a
# lunaway.net name: until infra/enable-domain.sh links them, Caddy serves
# nothing but the API's loopback way to the geocoders (geocoders.caddy).
. "$(dirname "$0")/common.sh"
need_root

log "Caddy package"
install_caddy_package

log "configuration"
reload=0 restart=0
install_file caddy/Caddyfile /etc/caddy/Caddyfile 0644 && reload=1
install_file caddy/lunaway.net.caddy /etc/caddy/sites-available/lunaway.net.caddy 0644 && reload=1
install -d -m 0755 /etc/caddy/sites-enabled
# The API's way to the geocoders, on the loopback only: served with or
# without the domain.
install_file caddy/geocoders.caddy /etc/caddy/sites-enabled/geocoders.caddy 0644 && reload=1
install_file systemd/caddy.service.d/lunaway.conf /etc/systemd/system/caddy.service.d/lunaway.conf 0644 && restart=1
[ "$restart" = 1 ] && systemctl daemon-reload

log "web roots"
# Photos are served under /media/ (the api snippet of the Caddyfile) from
# /srv/data/media, which infra/server/api.sh creates for the API to write.
# /srv/lunaway/site (lunaway.net/) and /srv/lunaway/web (lunaway.net/app/)
# are symlinks into /srv/lunaway/releases/, switched by infra/deploy-web.sh.
# A placeholder release fills a root that was never deployed; an existing
# root is left alone.
install -d -m 0755 /srv/lunaway /srv/lunaway/releases /srv/lunaway/releases/site /srv/lunaway/releases/app
for kind in site app; do
  root=/srv/lunaway/web
  [ "$kind" = site ] && root=/srv/lunaway/site
  if [ ! -e "$root" ] && [ ! -L "$root" ]; then
    placeholder="/srv/lunaway/releases/$kind/00000000T000000Z-placeholder"
    install -d -m 0755 "$placeholder"
    for file in "$INFRA/web/$kind"/*; do
      install -m 0644 "$file" "$placeholder/"
    done
    ln -sfn "$placeholder" "$root"
    echo "    $root: placeholder"
  fi
done

runuser -u caddy -- env HOME=/var/lib/caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 \
  || { runuser -u caddy -- env HOME=/var/lib/caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile; die "Caddyfile does not validate"; }

systemctl enable --quiet caddy
if [ "$restart" = 1 ] || ! systemctl is-active --quiet caddy; then
  systemctl restart caddy
elif [ "$reload" = 1 ]; then
  systemctl reload caddy
fi
if [ -e /etc/caddy/sites-enabled/lunaway.net.caddy ]; then
  log "caddy $(caddy version | cut -d' ' -f1) serving the lunaway.net sites"
else
  log "caddy $(caddy version | cut -d' ' -f1) serving nothing until infra/enable-domain.sh"
fi
