"""Vendors what the map needs offline besides a pack: glyphs and sprites.

    python3 tool/map_offline/vendor.py      # from app/

An offline pack holds tiles only (docs/deploy.md, "Offline packs"). The
styles also name glyphs (three Noto Sans stacks) and a sprite sheet, which
online come from the tile host. This copies them, from the repository the
tile host installs them from (protomaps/basemaps-assets, at the commit
pinned in infra/tiles/version.sh), into assets/map/offline/:

- the seven glyph ranges of Latin, Greek and Cyrillic (0-255 to 1024-1279,
  7680-7935, 8192-8447) of each stack: about 0.7 MB a stack. Labels in
  other scripts stay blank offline, as they would online with these fonts;
- the light and dark sprite sheets of the v4 set, at 1x and 2x;
- the fonts' licence (SIL OFL 1.1), and the licence of tangrams/icons
  (MIT), which the sprites derive from, at its last commit.

Every file is checked against the SHA-256 recorded in
tool/map_offline/vendor.sha256; a first run writes that file. A changed
upstream file stops the run.
"""

import hashlib
import os
import sys
import urllib.parse
import urllib.request

COMMIT = "028c18f713baecad011301ff7a69acc39bcc2ae7"
BASE = "https://raw.githubusercontent.com/protomaps/basemaps-assets/" + COMMIT + "/"
STACKS = ["Noto Sans Regular", "Noto Sans Medium", "Noto Sans Italic"]
RANGES = ["0-255", "256-511", "512-767", "768-1023", "1024-1279", "7680-7935", "8192-8447"]
SPRITES = ["light.json", "light.png", "light@2x.json", "light@2x.png",
           "dark.json", "dark.png", "dark@2x.json", "dark@2x.png"]
TANGRAMS = ("https://raw.githubusercontent.com/tangrams/icons/"
            "92510779634f4a006c61ea70e50cb8c52c765a81/LICENSE.md")


def files():
    for stack in STACKS:
        for r in RANGES:
            yield BASE + urllib.parse.quote("fonts/%s/%s.pbf" % (stack, r)), "glyphs/%s/%s.pbf" % (stack, r)
    for name in SPRITES:
        yield BASE + "sprites/v4/" + name, "sprites/" + name
    yield BASE + "fonts/OFL.txt", "glyphs/OFL.txt"
    yield TANGRAMS, "sprites/LICENSE.md"


def main():
    app = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    out = os.path.join(app, "assets", "map", "offline")
    sums_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor.sha256")
    expected = {}
    if os.path.exists(sums_path):
        for line in open(sums_path):
            digest, path = line.rstrip("\n").split("  ", 1)
            expected[path] = digest
    got = {}
    for url, dest in files():
        with urllib.request.urlopen(url, timeout=60) as r:
            data = r.read()
        digest = hashlib.sha256(data).hexdigest()
        if dest in expected and expected[dest] != digest:
            sys.exit("sha256 mismatch for %s: %s" % (dest, digest))
        got[dest] = digest
        path = os.path.join(out, dest)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
    if not expected:
        with open(sums_path, "w") as f:
            for dest, digest in sorted(got.items()):
                f.write("%s  %s\n" % (digest, dest))
    total = sum(os.path.getsize(os.path.join(out, d)) for d in got)
    print("wrote %d files, %d bytes" % (len(got), total))


if __name__ == "__main__":
    main()
