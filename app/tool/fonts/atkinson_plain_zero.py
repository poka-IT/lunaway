"""Derive Atkinson Hyperlegible Next statics with a plain (unslashed) zero.

    python atkinson_plain_zero.py SRC_DIR OUT_DIR    (run by build.sh)

The zero of Atkinson Hyperlegible Next 2.001 is one outer contour and two
counters: the slash is the ink left between them, not a separate contour.
The plain counter is rebuilt from the
quadrants the slash leaves intact: the upper-right arc of one counter and the
lower-left arc of the other, each mirrored about the glyph's vertical axis
(the zero is symmetric) to replace the arc the slash cuts. Every point of the
new counter is a point the designers drew, or its mirror image. The outer contour is kept as drawn.

Also maps U+202F NARROW NO-BREAK SPACE to the thin space glyph: the French
number formatting of package:intl groups thousands with U+202F, which the
font lacks, so Flutter would fall back to a system font for it.

The OFL of Atkinson Hyperlegible Next declares no Reserved Font Name, so the
derivative may keep the name; the family is still renamed so that it can
never be mistaken for, or shadowed by, an installed copy of the original.
"""

import os
import sys

from fontTools.ttLib import TTFont
from fontTools.ttLib.tables import ttProgram
from fontTools.ttLib.tables._g_l_y_f import Glyph, GlyphCoordinates

WEIGHTS = ["Regular", "Medium", "SemiBold", "Bold", "ExtraBold"]
NEW_FAMILY = "Atkinson Next Lunaway"
NEW_PS = "AtkinsonNextLunaway"
NOTE = (
    "Modified by the Lunaway project (https://lunaway.net) in 2026 from Atkinson "
    "Hyperlegible Next 2.001: plain zero without slash, U+202F mapped to the thin "
    "space. Licensed under the SIL Open Font License 1.1."
)


def contours_of(glyph, glyf):
    coords, ends, flags = glyph.getCoordinates(glyf)
    out, start = [], 0
    for end in ends:
        out.append([(coords[i][0], coords[i][1], bool(flags[i] & 1)) for i in range(start, end + 1)])
        start = end + 1
    return out


def arc(contour, first, last):
    """Points of `contour` from index `first` to `last` inclusive, in contour order."""
    n = len(contour)
    pts, i = [contour[first]], first
    while i != last:
        i = (i + 1) % n
        pts.append(contour[i])
    return pts


def extreme(contour, key):
    on = [i for i, p in enumerate(contour) if p[2]]
    return max(on, key=lambda i: key(contour[i]))


def plain_zero(font):
    glyf = font["glyf"]
    glyph = glyf["zero"]
    contours = contours_of(glyph, glyf)
    if len(contours) != 3:
        raise SystemExit("zero has %d contours, expected 3" % len(contours))

    def area(c):
        xs, ys = [p[0] for p in c], [p[1] for p in c]
        return (max(xs) - min(xs)) * (max(ys) - min(ys))

    outer = max(contours, key=area)
    counters = [c for c in contours if c is not outer]
    # The upper counter holds the top of the inner oval, the lower one its bottom.
    upper = max(counters, key=lambda c: max(p[1] for p in c))
    lower = min(counters, key=lambda c: min(p[1] for p in c))
    right = extreme(upper, lambda p: p[0])
    top = extreme(upper, lambda p: p[1])
    left = extreme(lower, lambda p: -p[0])
    bottom = extreme(lower, lambda p: -p[1])
    upper_right = arc(upper, right, top)
    lower_left = arc(lower, left, bottom)
    # The counter's own axis: in Medium the outer contour is centred half a
    # unit away from it.
    cx = (upper_right[0][0] + lower_left[0][0]) / 2.0

    def mirror(points):
        return [(2 * cx - x, y, on) for x, y, on in points]

    # Joints must coincide, or the mirror would leave a step in the counter.
    checks = [
        (upper_right[-1][0], cx),
        (lower_left[-1][0], cx),
        (2 * cx - upper_right[0][0], lower_left[0][0]),
        (upper_right[0][1], lower_left[0][1]),
    ]
    for got, want in checks:
        if abs(got - want) > 1:
            raise SystemExit("zero is not symmetric enough: %s != %s" % (got, want))

    upper_left = list(reversed(mirror(upper_right)))  # top to left
    lower_right = list(reversed(mirror(lower_left)))  # bottom to right
    counter = upper_right + upper_left[1:] + lower_left[1:] + lower_right[1:-1]

    new_contours = [outer, counter]
    coords, flags, ends = [], [], []
    for c in new_contours:
        for x, y, on in c:
            coords.append((round(x), round(y)))
            flags.append(1 if on else 0)
        ends.append(len(coords) - 1)
    new = Glyph()
    new.numberOfContours = len(ends)
    new.coordinates = GlyphCoordinates(coords)
    new.flags = bytearray(flags)
    new.endPtsOfContours = ends
    new.program = ttProgram.Program()
    new.program.fromBytecode(b"")
    new.recalcBounds(glyf)
    glyf["zero"] = new
    adv, _ = font["hmtx"]["zero"]
    font["hmtx"]["zero"] = (adv, new.xMin)
    return {"counter_points": len(counter), "axis": cx}


def rename(font, weight):
    name = font["name"]
    full = "%s %s" % (NEW_FAMILY, weight)
    ps = "%s-%s" % (NEW_PS, weight)
    rib = weight in ("Regular", "Bold")
    for rec in list(name.names):
        if rec.nameID in (1, 2, 3, 4, 6, 16, 17):
            name.removeNames(nameID=rec.nameID)
    if rib:
        name.setName(NEW_FAMILY, 1, 3, 1, 0x409)
        name.setName(weight, 2, 3, 1, 0x409)
    else:
        name.setName("%s %s" % (NEW_FAMILY, weight), 1, 3, 1, 0x409)
        name.setName("Regular", 2, 3, 1, 0x409)
        name.setName(NEW_FAMILY, 16, 3, 1, 0x409)
        name.setName(weight, 17, 3, 1, 0x409)
    name.setName("2.001-lunaway1;%s" % ps, 3, 3, 1, 0x409)
    name.setName(full, 4, 3, 1, 0x409)
    name.setName(ps, 6, 3, 1, 0x409)
    name.setName("Version 2.001; lunaway1 (plain zero)", 5, 3, 1, 0x409)
    name.setName(NOTE, 10, 3, 1, 0x409)
    # Drop any Macintosh-platform copies so the two platforms cannot disagree.
    for rec in list(name.names):
        if rec.platformID == 1:
            name.names.remove(rec)


def add_nnbsp(font):
    thin = font.getBestCmap().get(0x2009)
    if not thin:
        return False
    for table in font["cmap"].tables:
        if table.isUnicode():
            table.cmap.setdefault(0x202F, thin)
    return True


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for w in WEIGHTS:
        # The source's own timestamp is kept, so two builds give the same bytes.
        font = TTFont(os.path.join(src, "AtkinsonHyperlegibleNext-%s.ttf" % w), recalcTimestamp=False)
        stats = plain_zero(font)
        nnbsp = add_nnbsp(font)
        rename(font, w)
        dest = os.path.join(out, "%s-%s.ttf" % (NEW_PS, w))
        font.save(dest)
        print(w, stats, "nnbsp:", nnbsp, os.path.getsize(dest), "bytes")


if __name__ == "__main__":
    main()
