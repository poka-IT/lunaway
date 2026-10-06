#!/usr/bin/env bash
# Deploys map styles or a sprite set to the basemap host (docs/deploy.md,
# "Basemap"), where tiles.lunaway.net/styles/ and /sprites/ serve them, and
# the sslip.io name under /tiles/.
#
#   infra/deploy-basemap-assets.sh styles DIR       every DIR/<name>.json becomes /styles/<name>.json
#   infra/deploy-basemap-assets.sh sprites SET DIR  DIR/<name>[@2x].json|png become /sprites/SET/...
#
# Write styles for https://tiles.lunaway.net: on the server that prefix
# becomes a template action, so each host serves the style with its own
# address. A sprite set replaces the set of that name as a whole.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
require_host
kind="${1:-}"
case "$kind" in
  styles) set_name=styles dir="${2:-}" ;;
  sprites) set_name="${2:-}" dir="${3:-}" ;;
  *) die "usage: $0 styles DIR | sprites SET DIR" ;;
esac
[[ "$set_name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "a sprite set is named with lowercase letters, digits and dashes"
[ -n "$dir" ] && [ -d "$dir" ] || die "no directory '$dir'"

# The same checks as on the server, here first, so a mistake costs no upload.
case "$kind" in
  styles)
    ls "$dir"/*.json >/dev/null 2>&1 || die "no .json style in $dir"
    for file in "$dir"/*.json; do
      python3 -c 'import json, sys; s = json.load(open(sys.argv[1])); sys.exit(0 if s.get("version") == 8 else 1)' "$file" \
        || die "$file is not a MapLibre style (JSON with version 8)"
    done
    ;;
  sprites)
    ls "$dir"/*.json "$dir"/*.png >/dev/null 2>&1 || die "no sprite .json and .png in $dir"
    ;;
esac

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
upload="/home/$LUNAWAY_ADMIN_USER/basemap-upload/$stamp"
log "uploading $kind from $dir"
lunaway_ssh "mkdir -p ~/infra/server $upload"
lunaway_scp "$LUNAWAY_INFRA_DIR/server/common.sh" "$LUNAWAY_INFRA_DIR/server/install-basemap-assets.sh" "lunaway:infra/server/"
COPYFILE_DISABLE=1 tar -C "$dir" --no-xattrs --no-mac-metadata -cf - . | lunaway_ssh "tar -xf - -C $upload"
lunaway_ssh "sudo bash ~/infra/server/install-basemap-assets.sh $kind $set_name $upload"
