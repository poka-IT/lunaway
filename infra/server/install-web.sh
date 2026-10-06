#!/usr/bin/env bash
# Installs an uploaded static tree as a new release of the landing site or of
# the web app and switches its root to it, run as root by
# infra/deploy-web.sh. Caddy serves /srv/lunaway/site (lunaway.net/) and
# /srv/lunaway/web (lunaway.net/app/), both symlinks into
# /srv/lunaway/releases/<kind>/. Old releases stay until removed by name.
#
#   sudo bash ~/infra/server/install-web.sh site|app RELEASE UPLOADED_DIR
. "$(dirname "$0")/common.sh"
need_root
kind="${1:?site or app}"
name="${2:?release name}"
upload="${3:?uploaded directory}"
case "$kind" in
  site) root=/srv/lunaway/site ;;
  app) root=/srv/lunaway/web ;;
  *) die "unknown kind $kind" ;;
esac
[[ "$name" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-z]+$ ]] || die "unexpected release name $name"
[[ "$upload" =~ ^/home/[a-z]+/web-upload/[0-9]{8}T[0-9]{6}Z-[0-9a-z]+$ ]] || die "unexpected upload path $upload"
[ -f "$upload/index.html" ] || die "no index.html in $upload"
release="/srv/lunaway/releases/$kind/$name"
[ ! -e "$release" ] || die "release $name already exists"

install -d -m 0755 "/srv/lunaway/releases/$kind"
mv "$upload" "$release"
chown -R root:root "$release"
find "$release" -type d -exec chmod 0755 {} +
find "$release" -type f -exec chmod 0644 {} +
previous="$(readlink "$root" || true)"
ln -sfn "$release" "$root.new"
mv -T "$root.new" "$root"
log "$kind now serves $name ($(du -sh "$release" | cut -f1)), previous: ${previous:-none}"
