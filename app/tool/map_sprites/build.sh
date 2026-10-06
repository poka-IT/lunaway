#!/bin/sh
# Renders the map pins (generate_sprites_test.dart) for every pixel ratio,
# then shrinks the PNGs losslessly. From anywhere:
#
#   app/tool/map_sprites/build.sh
#
# Needs oxipng (brew install oxipng). Two runs on the same machine give
# byte-identical files. With LUNAWAY_SPRITE_SHEET_DIR=<dir> it also packs the
# pins into a sprite set for the tile host (generate_sprites_test.dart).
set -eu
cd "$(dirname "$0")/../.."
mkdir -p assets/map/pins/2x assets/map/pins/3x
fvm flutter test tool/map_sprites/generate_sprites_test.dart
oxipng -q -o 4 --strip all assets/map/pins/2x/*.png assets/map/pins/3x/*.png
if [ -n "${LUNAWAY_SPRITE_SHEET_DIR:-}" ]; then
  oxipng -q -o 4 --strip all "$LUNAWAY_SPRITE_SHEET_DIR"/*.png
fi
