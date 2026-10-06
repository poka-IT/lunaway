#!/usr/bin/env bash
# Installs the F-Droid repository uploaded by infra/fdroid/publish.sh as a
# new release and switches /srv/lunaway/fdroid to it, run as root. Caddy
# serves /srv/lunaway/fdroid/repo/ and archive/ under /fdroid/ (the
# fdroid_repo snippet of the Caddyfile). The upload directory stays, so the
# next publication sends only what changed; an APK the previous release
# already had is a hard link to it. Old releases stay until removed by name.
#
#   sudo bash ~/infra/server/install-fdroid.sh RELEASE
. "$(dirname "$0")/common.sh"
need_root
name="${1:?release name}"
[[ "$name" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9]+$ ]] || die "unexpected release name $name"
staging=/home/ops/fdroid-staging
for file in repo/entry.jar repo/index-v1.jar repo/index-v2.json; do
  [ -f "$staging/$file" ] || die "no $file in $staging"
done
[ -z "$(find "$staging" ! -type f ! -type d -print -quit)" ] || die "a link or a special file in $staging"
release="/srv/lunaway/releases/fdroid/$name"
[ ! -e "$release" ] || die "release $name already exists"

install -d -m 0755 /srv/lunaway/releases /srv/lunaway/releases/fdroid
install -d -m 0755 "$release"
cp -R "$staging/repo" "$release/repo"
[ -d "$staging/archive" ] && cp -R "$staging/archive" "$release/archive"
chown -R root:root "$release"
find "$release" -type d -exec chmod 0755 {} +
find "$release" -type f -exec chmod 0644 {} +
previous="$(readlink /srv/lunaway/fdroid || true)"
# Every release holds every APK still offered (the archive included), and
# an APK never changes under its name: one identical to the previous
# release's becomes a hard link to it, so a release costs the new APK only.
if [[ "$previous" =~ ^/srv/lunaway/releases/fdroid/[0-9]{8}T[0-9]{6}Z-[0-9]+$ ]] && [ -d "$previous" ]; then
  while IFS= read -r -d '' apk; do
    old="$previous/${apk#"$release"/}"
    if [ -f "$old" ] && [ ! -L "$old" ] && cmp -s "$apk" "$old"; then
      ln -f "$old" "$apk"
    fi
  done < <(find "$release" -type f -name '*.apk' -print0)
fi
ln -sfn "$release" /srv/lunaway/fdroid.new
mv -T /srv/lunaway/fdroid.new /srv/lunaway/fdroid
log "the F-Droid repository now serves $name ($(du -sh "$release" | cut -f1)), previous: ${previous:-none}"
