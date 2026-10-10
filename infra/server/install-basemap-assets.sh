#!/usr/bin/env bash
# Installs uploaded map styles or a sprite set under /srv/basemap/assets, run as
# root by infra/deploy-basemap-assets.sh. Caddy serves them as
# /styles/<name>.json (through its templates, which fill in the host's base
# URL) and /sprites/<set>/<name>[@2x].json|png.
#
#   sudo bash ~/infra/server/install-basemap-assets.sh styles styles UPLOADED_DIR
#   sudo bash ~/infra/server/install-basemap-assets.sh sprites SET UPLOADED_DIR
#
# A refused upload stays in ~/basemap-upload/<stamp> for inspection; remove it
# by its literal path.
. "$(dirname "$0")/common.sh"
need_root
kind="${1:?styles or sprites}"
set_name="${2:?set name}"
upload="${3:?uploaded directory}"
[[ "$upload" =~ ^/home/[a-z]+/basemap-upload/[0-9]{8}T[0-9]{6}Z$ ]] || die "unexpected upload path $upload"
[[ "$set_name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "unexpected set name $set_name"
[ "$set_name" != protomaps-v4 ] || die "protomaps-v4 comes from basemaps-assets (infra/server/tiles.sh)"
[ -d /srv/basemap/assets ] || die "no /srv/basemap/assets; run infra/configure.sh backend tiles"
# Regular files only: a link would publish, or overwrite, whatever it points at.
[ -z "$(find "$upload" -mindepth 1 ! -type f -print -quit)" ] || die "subdirectories, links or special files in the upload; send a flat directory of files"

case "$kind" in
  styles)
    # A style written for https://tiles.lunaway.net is served by every host
    # with its own address: the prefix becomes the template action of the
    # tiles snippet (backticks, so the file stays JSON).
    python3 - "$upload" <<'EOF'
import json, os, re, sys
upload = sys.argv[1]
action = "{{placeholder `http.vars.tiles_base`}}"
for name in sorted(os.listdir(upload)):
    path = os.path.join(upload, name)
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*\.json", name):
        sys.exit("unexpected file %s: styles are <name>.json" % name)
    text = open(path).read()
    if "{{" in text:
        sys.exit("%s already holds a template action" % name)
    style = json.loads(text)
    if style.get("version") != 8:
        sys.exit("%s is not a MapLibre style" % name)
    text = text.replace("https://tiles.lunaway.net", action)
    json.loads(text)
    with open(path, "w") as f:
        f.write(text)
    print("    %s: %d layers" % (name, len(style.get("layers", []))))
EOF
    for file in "$upload"/*.json; do
      install -m 0644 -o root -g root "$file" "/srv/basemap/assets/styles/$(basename "$file").new"
      mv -f "/srv/basemap/assets/styles/$(basename "$file").new" "/srv/basemap/assets/styles/$(basename "$file")"
    done
    log "styles: $(find /srv/basemap/assets/styles -maxdepth 1 -name '*.json' -printf '%f ')"
    ;;
  sprites)
    for file in "$upload"/*; do
      [[ "$(basename "$file")" =~ ^[a-z0-9][a-z0-9-]*(@2x)?\.(json|png)$ ]] || die "unexpected file $(basename "$file"): sprites are <name>[@2x].json|png"
    done
    # Swapped in as a whole: never half the files of a sheet.
    target="/srv/basemap/assets/sprites/$set_name"
    rm -rf "/srv/basemap/assets/sprites/.incoming"
    install -d -m 0755 /srv/basemap/assets/sprites/.incoming
    install -m 0644 -o root -g root "$upload"/* /srv/basemap/assets/sprites/.incoming/
    rm -rf "/srv/basemap/assets/sprites/.outgoing"
    [ -d "$target" ] && mv "$target" /srv/basemap/assets/sprites/.outgoing
    mv /srv/basemap/assets/sprites/.incoming "$target"
    rm -rf "/srv/basemap/assets/sprites/.outgoing"
    log "sprites/$set_name: $(find "$target" -maxdepth 1 -type f -printf '%f ')"
    ;;
  *) die "unknown kind $kind" ;;
esac
rm -f "$upload"/*
rmdir "$upload"
