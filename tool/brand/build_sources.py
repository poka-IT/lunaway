#!/usr/bin/env python3
"""Build the derived brand SVG sources from brand/lunaway-mark.svg and the Fraunces font.

    python3 tool/brand/build_sources.py

Writes, in brand/:
  lunaway-mark-mono.svg         one colour, moon, star and road cut out
  lunaway-lockup.svg            mark and wordmark, navy text for light backgrounds
  lunaway-lockup-dark.svg       the same with cream text for dark backgrounds
  feature-graphic-<lang>.svg    store feature graphic (1024 x 500), tagline in en, fr, de, es, it, nl
  social-preview.svg            repository social preview (1280 x 640)

Text is converted to outlines, so the outputs need no font. The fonts are
fetched once from the official Fraunces repository at a pinned commit, checked
against their SHA-256, and kept in the gitignored data/tmp/brand/fonts/.
Needs fontTools (pip install fonttools) and hb-shape (HarfBuzz utilities,
`brew install harfbuzz` or the distribution package) for kerning and accents.
The rasters are made from these files by tool/brand/generate.sh.
"""

import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.request
import xml.etree.ElementTree as ET

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BRAND = os.path.join(ROOT, "brand")
FONT_DIR = os.path.join(ROOT, "data", "tmp", "brand", "fonts")

FRAUNCES_COMMIT = "7ccdec31c6028118dce3e47fe864e3744460371d"
FRAUNCES_URL = "https://raw.githubusercontent.com/undercasetype/Fraunces/%s/fonts/ttf/%s"
FONTS = {
    "Fraunces72pt-SemiBold.ttf": "ea45a557b4dd7e9fee6e263211b72986879d6bde518dbe18338d0478b91ab93c",
    "Fraunces72pt-Regular.ttf": "12681469ade31179b299a8cdf23765f16a717a7563e4d3c17d9c21e938cdf2b7",
}

NAVY = "#061F43"
CREAM = "#FDF1DB"
LIGHT_TEAL = "#409FA7"
DARK_TEAL = "#15576D"
NIGHT = "#020B1B"   # the deep end of the night gradient behind the mark (store art)

SVG_NS = "http://www.w3.org/2000/svg"
TAGLINES = {
    "en": "Where to sleep tonight, anywhere, even offline",
    "fr": "Où dormir ce soir, partout, même hors ligne",
    "de": "Ihr Platz für heute Nacht, überall, auch offline",
    "es": "Dónde dormir esta noche, donde sea, sin conexión",
    "it": "Dove dormire stasera, ovunque, anche offline",
    "nl": "Waar slaap je vannacht, overal, ook offline",
}


def fetch_fonts():
    os.makedirs(FONT_DIR, exist_ok=True)
    for name, digest in FONTS.items():
        path = os.path.join(FONT_DIR, name)
        if not os.path.exists(path):
            req = urllib.request.Request(FRAUNCES_URL % (FRAUNCES_COMMIT, name),
                                         headers={"User-Agent": "lunaway-brand (+https://lunaway.net)"})
            with urllib.request.urlopen(req, timeout=60) as r, open(path, "wb") as out:
                out.write(r.read())
        with open(path, "rb") as f:
            got = hashlib.sha256(f.read()).hexdigest()
        if got != digest:
            sys.exit("%s: SHA-256 %s, expected %s" % (path, got, digest))
    return {name: os.path.join(FONT_DIR, name) for name in FONTS}


def num(v):
    s = ("%.1f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def round_path(d):
    return re.sub(r"-?\d+\.\d+|-?\d+", lambda m: num(float(m.group())), d)


class Text:
    """A line of text shaped by HarfBuzz and drawn as one SVG path."""

    def __init__(self, font_path, text, size, tracking=0.0, kerning=None):
        self.font = TTFont(font_path)
        self.glyphs = self.font.getGlyphSet()
        self.upm = self.font["head"].unitsPerEm
        self.scale = size / self.upm
        out = subprocess.run(["hb-shape", "--output-format=json", font_path, text],
                             check=True, capture_output=True, text=True).stdout
        self.run = json.loads(out)
        self.tracking = tracking * self.upm   # in font units, added after every glyph but the last
        self.kerning = kerning or {}          # manual optical kerning, font units, keyed by glyph pair
        self.size = size

    def advances(self):
        adv = []
        for i, g in enumerate(self.run):
            a = g["ax"]
            if i + 1 < len(self.run):
                a += self.tracking + self.kerning.get((g["g"], self.run[i + 1]["g"]), 0)
            adv.append(a)
        return adv

    def width(self):
        return sum(self.advances()) * self.scale

    def path(self, x, baseline):
        pen = SVGPathPen(self.glyphs)
        pos = 0.0
        for g, a in zip(self.run, self.advances()):
            t = (self.scale, 0, 0, -self.scale, x + (pos + g["dx"]) * self.scale, baseline - g["dy"] * self.scale)
            self.glyphs[g["g"]].draw(TransformPen(pen, t))
            pos += a
        return round_path(pen.getCommands())


def mark_parts():
    """The mark's elements as serialised SVG, keyed by id, plus its view box."""
    ET.register_namespace("", SVG_NS)
    tree = ET.parse(os.path.join(BRAND, "lunaway-mark.svg"))
    root = tree.getroot()
    w, h = (float(v) for v in root.get("viewBox").split()[2:])
    parts = {}
    for el in root.iter():
        if el.get("id"):
            parts[el.get("id")] = el
    return parts, w, h


PARTS, MARK_W, MARK_H = mark_parts()


def d_of(name):
    return PARTS[name].get("d")


def dot_attrs():
    c = PARTS["dot"]
    return 'cx="%s" cy="%s" r="%s"' % (c.get("cx"), c.get("cy"), c.get("r"))


def mark_markup(prefix, x, y, height, indent="  "):
    """The full-colour mark, inline, scaled to `height` with its top-left corner at (x, y)."""
    s = height / MARK_H
    i = indent
    fill = {name: PARTS[name].get("fill") for name in ("sky", "far-hills", "mid-hills", "near-ground", "road", "dashes")}
    return "\n".join([
        f'{i}<g transform="translate({num(x)} {num(y)}) scale({s:.5f})">',
        f'{i}  <mask id="{prefix}-pin"><path fill="#fff" d="{d_of("pin")}"/></mask>',
        f'{i}  <g mask="url(#{prefix}-pin)">',
        f'{i}    <path fill="{fill["sky"]}" d="{d_of("sky")}"/>',
        f'{i}    <g fill="{CREAM}">',
        f'{i}      <path d="{d_of("moon")}"/>',
        f'{i}      <path d="{d_of("star")}"/>',
        f'{i}      <circle {dot_attrs()}/>',
        f'{i}      <path d="{d_of("diamond")}"/>',
        f'{i}    </g>',
        f'{i}    <path fill="{fill["far-hills"]}" d="{d_of("far-hills")}"/>',
        f'{i}    <path fill="{fill["mid-hills"]}" d="{d_of("mid-hills")}"/>',
        f'{i}    <path fill="{fill["near-ground"]}" d="{d_of("near-ground")}"/>',
        f'{i}    <path fill="{fill["road"]}" d="{d_of("road")}"/>',
        f'{i}    <path fill="{fill["dashes"]}" d="{d_of("dashes")}"/>',
        f'{i}  </g>',
        f'{i}</g>',
    ])


HEADER = "<!-- Lunaway brand, generated by tool/brand/build_sources.py from brand/lunaway-mark.svg. -->\n"


def write(name, body):
    with open(os.path.join(BRAND, name), "w", encoding="utf-8") as f:
        f.write(body)
    print("wrote brand/" + name)


def mono():
    w, h = num(MARK_W), num(MARK_H)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}">
  <title>Lunaway</title>
  <!-- One colour: the pin with the moon, the star and the road cut out (themed icons, monochrome favicon). -->
  <defs>
    <mask id="lunaway-pin-mono">
      <path fill="#fff" d="{d_of("pin")}"/>
      <g fill="#000">
        <path d="{d_of("moon")}"/>
        <path d="{d_of("star")}"/>
        <circle {dot_attrs()}/>
        <path d="{d_of("diamond")}"/>
        <path d="{d_of("road")}"/>
      </g>
      <path fill="#fff" d="{d_of("dashes")}"/>
    </mask>
  </defs>
  <path class="mark" fill="{NAVY}" mask="url(#lunaway-pin-mono)" d="M0 0H{w}V{h}H0Z"/>
</svg>
"""


# Lockup proportions, in mark units (the mark is MARK_H = 552 tall).
WORD_SIZE = 335.0          # font size: the capital L is 0.70 em, about 0.42 of the pin height
WORD_GAP = 118.0           # between the pin and the L
WORD_CENTRE = 250.0        # the x-height band is centred here, between the head's centre and the pin's middle
WORD_KERNING = {("uni004C", "uni0075"): -70}   # L-u: the open right side of the L reads as a gap


def wordmark(fonts, size):
    return Text(fonts["Fraunces72pt-SemiBold.ttf"], "Lunaway", size, kerning=WORD_KERNING)


def lockup_layout(fonts, mark_h):
    """Positions of the lockup parts for a mark `mark_h` tall, with the mark's top-left at (0, 0)."""
    k = mark_h / MARK_H
    word = wordmark(fonts, WORD_SIZE * k)
    x_height = 0.458 * WORD_SIZE * k
    baseline = WORD_CENTRE * k + x_height / 2
    x = MARK_W * k + WORD_GAP * k
    return word, x, baseline, x + word.width()


def lockup(fonts, text_fill, title):
    word, x, baseline, right = lockup_layout(fonts, MARK_H)
    w = right + 4
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {num(w)} {num(MARK_H)}">
  <title>{title}</title>
{mark_markup("lockup", 0, 0, MARK_H)}
  <path fill="{text_fill}" d="{word.path(x, baseline)}"/>
</svg>
"""


def stars(items):
    """Small cream marks of the night sky: (kind, x, y, size, opacity) in canvas units."""
    out = []
    for kind, x, y, s, o in items:
        if kind == "dot":
            out.append(f'  <circle fill="{CREAM}" fill-opacity="{o}" cx="{num(x)}" cy="{num(y)}" r="{num(s)}"/>')
        elif kind == "diamond":
            out.append(f'  <path fill="{CREAM}" fill-opacity="{o}" d="M{num(x)} {num(y - s)}L{num(x + s)} {num(y)}'
                       f'L{num(x)} {num(y + s)}L{num(x - s)} {num(y)}Z"/>')
        else:   # a four-point sparkle with the proportions of the star in the mark
            k = s / 34.5
            seg = [((0, -34.5), (1.7, -28.7), (5.7, -13.5), (9.6, -9.6)), ((9.6, -9.6), (13.4, -5.8), (23.9, -2.2), (29.3, 0))]
            d = ["M%s %s" % (num(x), num(y - s))]
            for sx, sy, rev in ((1, 1, False), (1, -1, True), (-1, -1, False), (-1, 1, True)):
                curves = [[(x + px * sx * k, y + py * sy * k) for px, py in c] for c in seg]
                if rev:
                    curves = [c[::-1] for c in curves[::-1]]
                for c in curves:
                    d.append("C" + " ".join("%s %s" % (num(a), num(b)) for a, b in c[1:]))
            out.append(f'  <path fill="{CREAM}" fill-opacity="{o}" d="{"".join(d)}Z"/>')
    return "\n".join(out)


def hills(width, height, horizon):
    """Rolling hills along the bottom, in the colours of the mark: a far ridge, a nearer one, the ground.

    Each ridge goes through its crests and hollows (fractions of the width, and of the band under the
    horizon) with level tangents there, which keeps the curves round like the hills of the mark.
    """
    band = height - horizon

    def ridge(points):
        pts = [(fx * width, horizon + fy * band) for fx, fy in points]
        d = ["M%s %s" % (num(pts[0][0]), num(pts[0][1]))]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            k = 0.42 * (x1 - x0)
            d.append("C%s %s %s %s %s %s" % (num(x0 + k), num(y0), num(x1 - k), num(y1), num(x1), num(y1)))
        d.append("V%sH0Z" % num(height))
        return "".join(d)

    far = ridge([(0, 0.34), (0.17, 0.04), (0.43, 0.42), (0.79, -0.08), (1, 0.22)])
    mid = ridge([(0, 0.66), (0.29, 0.44), (0.62, 0.74), (1, 0.50)])
    near = ridge([(0, 0.90), (0.47, 0.80), (1, 0.94)])
    return "\n".join([
        f'  <path fill="{LIGHT_TEAL}" d="{far}"/>',
        f'  <path fill="{DARK_TEAL}" d="{mid}"/>',
        f'  <path fill="{NAVY}" d="{near}"/>',
    ])


def scene(fonts, width, height, mark_h, tagline, tag_size, star_items, title):
    """Night scene: gradient sky, a halo behind the mark, the lockup and a tagline, hills at the bottom."""
    word, wx, baseline, right = lockup_layout(fonts, mark_h)
    tag = Text(fonts["Fraunces72pt-Regular.ttf"], tagline, tag_size) if tagline else None
    block_w = max(right, wx + (tag.width() if tag else 0))
    left = (width - block_w) / 2
    top = (height - mark_h) / 2 - 0.08 * height
    halo_cx, halo_cy = left + MARK_W * mark_h / MARK_H / 2, top + 0.45 * mark_h
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}">',
        f"  <title>{title}</title>",
        "  <defs>",
        '    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">',
        f'      <stop offset="0" stop-color="{NIGHT}"/>',
        f'      <stop offset="1" stop-color="{NAVY}"/>',
        "    </linearGradient>",
        '    <radialGradient id="halo">',
        f'      <stop offset="0" stop-color="{CREAM}" stop-opacity="0.16"/>',
        f'      <stop offset="0.55" stop-color="{CREAM}" stop-opacity="0.05"/>',
        f'      <stop offset="1" stop-color="{CREAM}" stop-opacity="0"/>',
        "    </radialGradient>",
        "  </defs>",
        f'  <rect width="{width}" height="{height}" fill="url(#sky)"/>',
        stars(star_items),
        hills(width, height, 0.74 * height),
        f'  <circle fill="url(#halo)" cx="{num(halo_cx)}" cy="{num(halo_cy)}" r="{num(0.95 * mark_h)}"/>',
        mark_markup("scene", left, top, mark_h),
        f'  <path fill="{CREAM}" d="{word.path(left + wx, top + baseline)}"/>',
    ]
    if tag:
        tag_baseline = top + mark_h - 0.06 * mark_h
        parts.append(f'  <path fill="{CREAM}" fill-opacity="0.86" d="{tag.path(left + wx + 0.04 * mark_h, tag_baseline)}"/>')
    parts.append("</svg>\n")
    return "\n".join(parts)


FEATURE_STARS = [
    ("sparkle", 862, 92, 15, 0.9), ("sparkle", 118, 136, 10, 0.7), ("dot", 214, 70, 2.6, 0.8), ("dot", 742, 54, 2.2, 0.6),
    ("dot", 935, 196, 2.4, 0.7), ("dot", 60, 262, 2.0, 0.5), ("diamond", 958, 128, 5.5, 0.75), ("diamond", 322, 38, 4.5, 0.5),
    ("dot", 560, 34, 1.8, 0.5), ("dot", 980, 60, 1.8, 0.5), ("sparkle", 600, 72, 7, 0.55),
]
SOCIAL_STARS = [(k, x * 1.25, y * 1.28, s * 1.25, o) for k, x, y, s, o in FEATURE_STARS]


def main():
    fonts = fetch_fonts()
    write("lunaway-mark-mono.svg", mono())
    write("lunaway-lockup.svg", HEADER + lockup(fonts, NAVY, "Lunaway"))
    write("lunaway-lockup-dark.svg", HEADER + lockup(fonts, CREAM, "Lunaway"))
    for lang, tagline in TAGLINES.items():
        write("feature-graphic-%s.svg" % lang,
              HEADER + scene(fonts, 1024, 500, 196, tagline, 30, FEATURE_STARS, "Lunaway: " + tagline))
    write("social-preview.svg", HEADER + scene(fonts, 1280, 640, 250, TAGLINES["en"], 38, SOCIAL_STARS,
                                               "Lunaway: " + TAGLINES["en"]))


if __name__ == "__main__":
    main()
