"""Instance and subset Fraunces 1.003 (upstream commit 7ccdec31) for the app.

    python fraunces_subset.py SRC.ttf OUT_DIR    (run by build.sh)

Keeps the optical size and weight axes, pins SOFT at 0 (the wordmark's
setting) and WONK at 0 (no leaning h, m, n), and subsets to the Latin set the
app needs. Fraunces' OFL declares no Reserved Font Name, so the modified
font keeps its name. Writes OUT_DIR/Fraunces-Variable.ttf.
"""
import os
import sys

from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

# Basic Latin, Latin-1 Supplement, Latin Extended-A, the Romanian comma
# letters, combining diacritics (decomposed input), general punctuation,
# euro, numero, trade mark, arrows, minus and the typographic apostrophe.
UNICODES = (
    list(range(0x20, 0x7F)) + list(range(0xA0, 0x100)) + list(range(0x100, 0x180))
    + [0x0218, 0x0219, 0x021A, 0x021B, 0x02C6, 0x02C7, 0x02D8, 0x02D9, 0x02DA, 0x02DB, 0x02DC, 0x02DD]
    + list(range(0x0300, 0x0370)) + list(range(0x2000, 0x2070))
    + [0x20AC, 0x2116, 0x2122, 0x2212] + list(range(0x2190, 0x2200))
)

# The whole optical size and weight range: the app sets both per text style.
LIMITS = {"SOFT": 0, "WONK": 0}


def nnbsp(font):
    cmap = font.getBestCmap()
    thin = cmap.get(0x2009) or cmap.get(0x0020)
    for t in font["cmap"].tables:
        if t.isUnicode():
            t.cmap.setdefault(0x202F, thin)


def build(src, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for name, limits in {"Variable": LIMITS}.items():
        # The source's own timestamp is kept, so two builds give the same bytes.
        font = TTFont(src, recalcTimestamp=False)
        font = instancer.instantiateVariableFont(font, limits, updateFontNames=False)
        opts = Options()
        opts.layout_features = ["*"]
        opts.name_IDs = ["*"]
        opts.name_languages = ["*"]
        opts.notdef_outline = True
        opts.glyph_names = False
        opts.hinting = False
        sub = Subsetter(opts)
        sub.populate(unicodes=UNICODES)
        sub.subset(font)
        nnbsp(font)
        font["name"].setName(
            "Instanced (SOFT 0, WONK 0) and subset to Latin by the Lunaway project "
            "(https://lunaway.net) from Fraunces 1.003, upstream commit 7ccdec31; U+202F "
            "mapped to the thin space. Licensed under the SIL Open Font License 1.1.",
            10, 3, 1, 0x409,
        )
        dest = os.path.join(out_dir, "Fraunces-%s.ttf" % name)
        font.save(dest)
        print(name, os.path.getsize(dest), "bytes", [(a.axisTag, a.minValue, a.defaultValue, a.maxValue) for a in font["fvar"].axes], "cmap", len(font.getBestCmap()))


if __name__ == "__main__":
    build(sys.argv[1], sys.argv[2])
