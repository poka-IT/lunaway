#!/usr/bin/env python3
"""Hash of the basemaps-assets subset Lunaway serves, pinned in version.sh.

GitHub may regenerate the tarball of a commit with other bytes, so the pin is
taken over the files: for each installed file, in byte order of its path
relative to the checkout, the line "<path>\\0<sha256 of its content>\\n"
(symlinks followed), and the SHA-256 of all the lines.

    python3 infra/tiles/assets-hash.py <extracted basemaps-assets directory>
"""
import hashlib
import os
import sys

# What infra/server/tiles.sh installs: the Noto Sans glyph ranges the
# Protomaps styles name, their licence, and the v4 sprites.
SUBSET = (
    "fonts/Noto Sans Regular",
    "fonts/Noto Sans Medium",
    "fonts/Noto Sans Italic",
    "fonts/Noto Sans Devanagari Regular v1",
    "fonts/OFL.txt",
    "sprites/v4",
)


def checked(root, rel):
    """rel, after making sure it is a regular file, or a symlink to one
    inside the subset (some glyph ranges are links between font stacks)."""
    path = os.path.join(root, rel)
    target = os.path.realpath(path)
    real_root = os.path.realpath(root)
    inside = any(target == os.path.join(real_root, top) or target.startswith(os.path.join(real_root, top) + os.sep)
                 for top in SUBSET)
    if not inside or not os.path.isfile(target):
        sys.exit("refused: %s is not a file of the subset" % rel)
    return rel


def files(root):
    for top in SUBSET:
        path = os.path.join(root, top)
        if os.path.islink(path) or not os.path.exists(path):
            sys.exit("missing or a link in the checkout: " + top)
        if os.path.isfile(path):
            yield checked(root, top)
            continue
        for directory, subdirs, names in os.walk(path):
            for name in subdirs:
                if os.path.islink(os.path.join(directory, name)):
                    sys.exit("refused: a directory link in the checkout: " + os.path.join(directory, name))
            for name in names:
                yield checked(root, os.path.relpath(os.path.join(directory, name), root))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    root = sys.argv[1]
    total = hashlib.sha256()
    count = 0
    for rel in sorted(files(root), key=lambda p: p.encode()):
        with open(os.path.join(root, rel), "rb") as f:
            digest = hashlib.sha256(f.read()).hexdigest()
        total.update(rel.encode() + b"\0" + digest.encode() + b"\n")
        count += 1
    print(total.hexdigest(), count)


if __name__ == "__main__":
    main()
