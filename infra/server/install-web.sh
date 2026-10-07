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

# A page that a browser's service worker serves from an older build names
# that build's renamed startup files (app/tool/web/fingerprint.py lists
# them in hashed.txt). They are carried into the new release from the last
# twenty app releases, so that such a page still finds them until its worker
# moves to the new build (a browser that misses more deploys and lost them
# from its HTTP cache stays on the loading screen until its worker updates,
# at the next visit). Only the files each build renamed are listed, so
# nothing older than twenty builds is kept, about 15 MB each.
if [ "$kind" = app ]; then
  carried=0
  for earlier in $(find /srv/lunaway/releases/app -mindepth 1 -maxdepth 1 -type d ! -name "$name" -printf '%f\n' | sort | tail -n 20); do
    list="/srv/lunaway/releases/app/$earlier/hashed.txt"
    [ -f "$list" ] || continue
    while IFS= read -r rel; do
      # Only the names the tool writes; nothing may leave the release.
      if ! [[ "$rel" =~ ^[A-Za-z0-9_./-]+$ ]] || [[ "$rel" == *..* ]]; then continue; fi
      src="/srv/lunaway/releases/app/$earlier/$rel"
      if [ ! -f "$src" ] || [ -e "$release/$rel" ]; then continue; fi
      install -D -m 0644 -o root -g root "$src" "$release/$rel"
      if [ -f "$src.br" ]; then install -D -m 0644 -o root -g root "$src.br" "$release/$rel.br"; fi
      carried=$((carried + 1))
    done < "$list"
  done
  log "carried $carried renamed files of earlier releases"
fi

previous="$(readlink "$root" || true)"
ln -sfn "$release" "$root.new"
mv -T "$root.new" "$root"
log "$kind now serves $name ($(du -sh "$release" | cut -f1)), previous: ${previous:-none}"
