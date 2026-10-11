"""Derive Figtree Lunaway from the Figtree variable font (Google Fonts build).

    python figtree_lunaway.py SRC.ttf OUT_DIR    (run by build.sh)

Two changes, both for the readers of the app:

- the lowercase l takes the tailed form the designer drew for his
  "Disambiguation" set (ss02), with its accented forms, so "Il", "Ille" and
  "11 l" no longer read as three identical bars. The rest of that set stays
  out: its capital I has serifs and its zero a slash, which reads as a "Ø"
  in "30 jours";
- U+2009 THIN SPACE and U+202F NARROW NO-BREAK SPACE, which Figtree lacks,
  get a space half as wide as the word space at every weight. The French
  number formatting of package:intl groups thousands with U+202F, and French
  typography puts it before ";", "!" and "?": without it, Flutter would draw
  that one character with a system font.

The OFL of Figtree declares no Reserved Font Name, so the derivative may
keep the name; the family is still renamed so that it can never be mistaken
for, or shadowed by, an installed copy of the original. Writes
OUT_DIR/FigtreeLunaway-Variable.ttf.
"""

import os
import sys

from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._g_l_y_f import Glyph
from fontTools.ttLib.tables.TupleVariation import TupleVariation

FAMILY = "Figtree Lunaway"
PS = "FigtreeLunaway"
THIN = "uni2009"
# The l and its accented forms; the other members of ss02 are left alone.
TAILED = {
    0x006C: ("l", "l.ss02"),
    0x013A: ("lacute", "lacute.ss02"),
    0x013C: ("uni013C", "uni013C.ss02"),
    0x013E: ("lcaron", "lcaron.ss02"),
    0x0142: ("lslash", "lslash.ss02"),
}
NOTE = (
    "Modified by the Lunaway project (https://lunaway.net) in 2026 from Figtree 2.002 "
    "(google/fonts, commit a60a77e1): tailed l from the ss02 set by default, U+2009 and "
    "U+202F mapped to a thin space. Licensed under the SIL Open Font License 1.1."
)


def stylistic_set(font, tag):
    """The single substitutions of one GSUB feature, as a dict."""
    gsub = font["GSUB"].table
    mapping = {}
    for record in gsub.FeatureList.FeatureRecord:
        if record.FeatureTag != tag:
            continue
        for index in record.Feature.LookupListIndex:
            for sub in gsub.LookupList.Lookup[index].SubTable:
                sub = getattr(sub, "ExtSubTable", sub)
                mapping.update(getattr(sub, "mapping", {}) or {})
    return mapping


def tail_the_l(font):
    ss02 = stylistic_set(font, "ss02")
    cmap = font.getBestCmap()
    for code, (plain, tailed) in TAILED.items():
        if cmap.get(code) != plain or ss02.get(plain) != tailed:
            raise SystemExit("U+%04X: expected %s -> %s in ss02, found %s -> %s"
                             % (code, plain, tailed, cmap.get(code), ss02.get(plain)))
    for table in font["cmap"].tables:
        if table.isUnicode():
            for code, (_, tailed) in TAILED.items():
                if code in table.cmap:
                    table.cmap[code] = tailed


def add_thin_space(font):
    """An empty glyph half as wide as the space, varying with the weight as
    the space does, mapped from U+2009 and U+202F."""
    order = font.getGlyphOrder()
    if THIN in order:
        raise SystemExit("the font already has %s" % THIN)
    space = font.getBestCmap()[0x20]
    advance, _ = font["hmtx"][space]
    order.append(THIN)
    font.setGlyphOrder(order)
    font["glyf"][THIN] = Glyph()
    font["hmtx"][THIN] = (round(advance / 2), 0)

    # The phantom points carry the advance for renderers that read gvar.
    font["gvar"].variations[THIN] = [
        TupleVariation(dict(v.axes), [(round(x / 2), round(y / 2)) for x, y in v.coordinates])
        for v in font["gvar"].variations.get(space, [])
    ]

    # HVAR, which the others read: a delta set of half the space's deltas.
    hvar = font["HVAR"].table
    index = hvar.AdvWidthMap.mapping[space]
    outer, inner = index >> 16, index & 0xFFFF
    data = hvar.VarStore.VarData[outer]
    data.Item.append([round(d / 2) for d in data.Item[inner]])
    data.ItemCount = len(data.Item)
    hvar.AdvWidthMap.mapping[THIN] = (outer << 16) | (len(data.Item) - 1)

    for table in font["cmap"].tables:
        if table.isUnicode():
            table.cmap[0x2009] = THIN
            table.cmap[0x202F] = THIN


def rename(font):
    name = font["name"]
    for record in list(name.names):
        text = record.toUnicode()
        if record.nameID in (6, 25) or text.startswith("Figtree-"):
            new = text.replace("Figtree", PS, 1)
        elif record.nameID in (1, 4, 16):
            new = text.replace("Figtree", FAMILY, 1)
        elif record.nameID == 3:
            new = text.replace("2.002;", "2.002-lunaway1;", 1).replace("Figtree-", PS + "-", 1)
        elif record.nameID == 5:
            new = text + "; lunaway1 (tailed l, thin space)"
        else:
            continue
        name.setName(new, record.nameID, record.platformID, record.platEncID, record.langID)
    name.setName(NOTE, 10, 3, 1, 0x409)
    # Only Windows-platform names: none on the Macintosh platform to disagree.
    for record in list(name.names):
        if record.platformID == 1:
            name.names.remove(record)


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    # The source's own timestamp is kept, so two builds give the same bytes.
    font = TTFont(src, recalcTimestamp=False)
    # Every table read before the glyph order grows: gvar checks its count.
    font.ensureDecompiled()
    tail_the_l(font)
    add_thin_space(font)
    rename(font)
    dest = os.path.join(out, "%s-Variable.ttf" % PS)
    font.save(dest)
    check = TTFont(dest)
    cmap = check.getBestCmap()
    print(dest, os.path.getsize(dest), "bytes,", len(cmap), "characters,",
          "l ->", cmap[0x6C], "U+202F ->", cmap[0x202F], check["hmtx"][THIN])


if __name__ == "__main__":
    main()
