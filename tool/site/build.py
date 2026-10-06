"""Builds the static site of lunaway.net into infra/web/site/.

    python3 data/tmp/site/build.py

Assets come from files already in the repository: the fonts the app derives
(app/assets/fonts, app/tool/fonts/build.sh), the brand (brand/), the app's web
icons (app/web) and the current phone screenshots (plan/screenshots/android).
Fonts, the stylesheet, the script and the lockup get a content hash in their
name, which the Caddy site caches for a year; pages, screenshots and icons
keep stable names (five-minute cache). Pages are assembled from the
fragments in src/pages/<lang>/ and written as plain HTML.

Needs fontTools with brotli, cwebp, magick and rsvg-convert.
"""

import hashlib
import html
import json
import os
import re
import shutil
import subprocess
import sys

from fontTools import subset
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(REPO, "infra", "web", "site")
SRC = os.path.join(HERE, "src")
FONTS = os.path.join(REPO, "app", "assets", "fonts")
SHOTS = os.path.join(REPO, "plan", "screenshots", "android")
SITE = "https://lunaway.net"
DATE = "2026-10-06"

UNICODES = (
    list(range(0x20, 0x7F)) + list(range(0xA0, 0x100))
    + [0x131, 0x152, 0x153, 0x178, 0x2C6, 0x2DA, 0x2DC, 0x2009, 0x2018, 0x2019, 0x201A,
       0x201C, 0x201D, 0x201E, 0x2022, 0x2026, 0x202F, 0x2039, 0x203A, 0x20AC]
)

# Screenshots: (number, name in the site, source screen). The landing shows
# the first two in its hero and the next three in its strip.
SCREENS = [
    (1, "map", "map-region"),
    (2, "place", "place"),
    (3, "night", "place-details"),
    (4, "coordinates", "point"),
    (5, "filters", "filters"),
]
SHOT_SOURCES = {"fr": "fr-1080x1920-light-{}.png", "en": "en-1080x1920-dark-{}.png"}

# Phosphor (MIT) glyphs used inline, by code point of the regular weight
# (app/lib/shared/theme/phosphor_glyphs.dart).
ICONS = {
    "hand-heart": 0xE810,
    "shield-check": 0xE40C,
    "cloud-slash": 0xE1B6,
    "seal-check": 0xE606,
    "path": 0xE39C,
    "code": 0xE1BC,
    "moon-stars": 0xE58E,
    "crosshair": 0xE1D6,
    "globe": 0xE288,
    "download": 0xE20C,
    "trash": 0xE4A6,
    "users": 0xE4C2,
    "map": 0xE31A,
}

PAGES = [
    ("home", "index.html", "/"),
    ("privacy", "privacy.html", "privacy"),
    ("about", "about.html", "about"),
    ("legal", "legal.html", "legal"),
    ("delete", "account/delete.html", "account/delete"),
    ("fdroid", "fdroid/index.html", "fdroid/"),
]

T = {
    "fr": {
        "skip": "Aller au contenu",
        "brand_alt": "Lunaway, page d'accueil",
        "nav_label": "Navigation principale",
        "app": "App web",
        "about": "À propos",
        "privacy": "Confidentialité",
        "other": "en",
        "other_name": "English",
        "og_locale": "fr_FR",
        "og_alt": "en_US",
        "og_image_alt": "Le logo de Lunaway, une épingle de carte avec un croissant de lune, des collines et une route, sur un ciel de nuit.",
    },
    "en": {
        "skip": "Skip to content",
        "brand_alt": "Lunaway, home page",
        "nav_label": "Main navigation",
        "app": "Web app",
        "about": "About",
        "privacy": "Privacy",
        "other": "fr",
        "other_name": "Français",
        "og_locale": "en_US",
        "og_alt": "fr_FR",
        "og_image_alt": "The Lunaway logo, a map pin holding a crescent moon, hills and a road, on a night sky.",
    },
}


def run(*cmd):
    subprocess.run(cmd, check=True)


def digest(data):
    return hashlib.sha256(data).hexdigest()[:10]


def write(rel, data):
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    mode = "wb" if isinstance(data, bytes) else "w"
    with open(path, mode, **({} if isinstance(data, bytes) else {"encoding": "utf-8"})) as f:
        f.write(data)


def hashed(rel_dir, stem, ext, data):
    """Writes data as <rel_dir>/<stem>.<hash>.<ext>, removes older hashes of
    the same stem, and returns the URL path."""
    name = f"{stem}.{digest(data)}.{ext}"
    folder = os.path.join(OUT, rel_dir)
    os.makedirs(folder, exist_ok=True)
    pattern = re.compile(re.escape(stem) + r"\.[0-9a-f]{10}\." + re.escape(ext) + "$")
    for old in os.listdir(folder):
        if pattern.match(old) and old != name:
            os.remove(os.path.join(folder, old))
    write(os.path.join(rel_dir, name), data)
    return "/" + (rel_dir + "/" if rel_dir else "") + name


def read(path, mode="r"):
    with open(path, mode, **({} if "b" in mode else {"encoding": "utf-8"})) as f:
        return f.read()


# Fonts ----------------------------------------------------------------------

def woff2(font, features):
    opts = subset.Options()
    opts.flavor = "woff2"
    opts.layout_features = features
    opts.name_IDs = ["*"]
    opts.name_languages = ["*"]
    opts.hinting = False
    opts.desubroutinize = True
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=UNICODES)
    sub.subset(font)
    font.flavor = "woff2"
    font.recalcTimestamp = False
    tmp = os.path.join(HERE, "font.tmp")
    font.save(tmp)
    data = read(tmp, "rb")
    os.remove(tmp)
    return data


def build_fonts():
    urls = {}
    vf = TTFont(os.path.join(FONTS, "fraunces", "Fraunces-Variable.ttf"), recalcTimestamp=False)
    static = instancer.instantiateVariableFont(vf, {"wght": 600, "opsz": 72}, static=True)
    urls["fraunces"] = hashed("fonts", "fraunces-semibold", "woff2",
                              woff2(static, ["kern", "liga", "clig", "calt"]))
    for weight in ("Regular", "Bold"):
        f = TTFont(os.path.join(FONTS, "atkinson-next-lunaway", f"AtkinsonNextLunaway-{weight}.ttf"),
                   recalcTimestamp=False)
        urls["atkinson-" + weight.lower()] = hashed(
            "fonts", "atkinson-next-lunaway-" + weight.lower(), "woff2",
            woff2(f, ["kern", "liga", "clig", "calt", "case", "tnum"]))
    write("fonts/OFL-Fraunces.txt", read(os.path.join(FONTS, "fraunces", "OFL.txt")))
    write("fonts/OFL-Atkinson-Hyperlegible-Next.txt",
          read(os.path.join(FONTS, "atkinson-next-lunaway", "OFL.txt")))
    return urls


# Icons and decoration ---------------------------------------------------------

def build_icons():
    font = TTFont(os.path.join(FONTS, "phosphor", "Phosphor-Regular.ttf"))
    cmap = font.getBestCmap()
    glyphs = font.getGlyphSet()
    ascent = font["hhea"].ascent
    out = {}
    for name, cp in ICONS.items():
        pen = SVGPathPen(glyphs)
        glyphs[cmap[cp]].draw(TransformPen(pen, (1, 0, 0, -1, 0, ascent)))
        d = re.sub(r"(\d)\.0(?![0-9])", r"\1", pen.getCommands())
        out[name] =('<svg viewBox="0 0 1024 1024" aria-hidden="true">'
                     f'<path fill="currentColor" d="{d}"/></svg>')
    return out


def num(x):
    s = f"{x:.1f}"
    return s[:-2] if s.endswith(".0") else s


# Stars in the manner of the store art (tool/brand/build_sources.py,
# FEATURE_STARS): the same shapes, on a 1024 x 500 canvas anchored to the
# top right of the band, and kept to its right part, away from the titles.
STARS = [
    ("sparkle", 930, 70, 14, 0.9), ("dot", 985, 150, 2.4, 0.7), ("diamond", 878, 196, 5.5, 0.75),
    ("dot", 822, 40, 2.2, 0.6), ("sparkle", 770, 128, 7, 0.55), ("dot", 1004, 262, 2.0, 0.5),
    ("diamond", 960, 360, 4.5, 0.5), ("dot", 840, 300, 1.8, 0.5),
]


def sky():
    parts = ['<svg class="sky" viewBox="0 0 1024 500" preserveAspectRatio="xMaxYMin slice" aria-hidden="true">']
    for kind, x, y, s, o in STARS:
        if kind == "dot":
            parts.append(f'<circle fill="#fdf1db" fill-opacity="{o}" cx="{num(x)}" cy="{num(y)}" r="{num(s)}"/>')
        elif kind == "diamond":
            parts.append(f'<path fill="#fdf1db" fill-opacity="{o}" d="M{num(x)} {num(y - s)}L{num(x + s)} {num(y)}'
                         f'L{num(x)} {num(y + s)}L{num(x - s)} {num(y)}Z"/>')
        else:
            k = s / 34.5
            seg = [((0, -34.5), (1.7, -28.7), (5.7, -13.5), (9.6, -9.6)),
                   ((9.6, -9.6), (13.4, -5.8), (23.9, -2.2), (29.3, 0))]
            d = ["M%s %s" % (num(x), num(y - s))]
            for sx, sy, rev in ((1, 1, False), (1, -1, True), (-1, -1, False), (-1, 1, True)):
                curves = [[(x + px * sx * k, y + py * sy * k) for px, py in c] for c in seg]
                if rev:
                    curves = [c[::-1] for c in curves[::-1]]
                for c in curves:
                    d.append("C" + " ".join("%s %s" % (num(a), num(b)) for a, b in c[1:]))
            parts.append(f'<path fill="#fdf1db" fill-opacity="{o}" d="{"".join(d)}Z"/>')
    parts.append("</svg>")
    return "".join(parts)


def hills():
    """The ridges of the store art (tool/brand/build_sources.py, hills), on a
    1440 x 120 strip: far and mid hills in the teals of the mark, and a near
    ground in the page colour, so the night flows into the page."""
    width, height, horizon = 1440, 120, 0
    band = height - horizon

    def ridge(points):
        pts = [(fx * width, horizon + fy * band) for fx, fy in points]
        d = ["M%s %s" % (num(pts[0][0]), num(pts[0][1]))]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            k = 0.42 * (x1 - x0)
            d.append("C%s %s %s %s %s %s" % (num(x0 + k), num(y0), num(x1 - k), num(y1), num(x1), num(y1)))
        d.append("V%sH0Z" % num(height + 1))
        return "".join(d)

    far = ridge([(0, 0.30), (0.17, 0.06), (0.43, 0.40), (0.79, 0.02), (1, 0.24)])
    mid = ridge([(0, 0.62), (0.29, 0.42), (0.62, 0.70), (1, 0.48)])
    near = ridge([(0, 0.88), (0.47, 0.76), (1, 0.92)])
    return ('<svg class="hills" viewBox="0 0 1440 121" preserveAspectRatio="none" aria-hidden="true">'
            f'<path fill="#409fa7" d="{far}"/><path fill="#15576d" d="{mid}"/>'
            f'<path fill="currentColor" d="{near}"/></svg>')


# Images -------------------------------------------------------------------

def build_images():
    os.makedirs(os.path.join(OUT, "img", "screens"), exist_ok=True)
    tmp = os.path.join(HERE, "shot.tmp.png")
    for lang, pattern in SHOT_SOURCES.items():
        for n, name, screen in SCREENS:
            src = os.path.join(SHOTS, pattern.format(screen))
            out = os.path.join(OUT, "img", "screens", f"{lang}-{n}-{name}.webp")
            # The captures live in the maintainer's local plan/ folder; a
            # clone without them keeps the committed WebP files.
            if not os.path.exists(src):
                continue
            run("magick", src, "-resize", "600x", "-strip", tmp)
            run("cwebp", "-quiet", "-q", "80", "-m", "6", "-metadata", "none", tmp, "-o", out)
    if os.path.exists(tmp):
        os.remove(tmp)
    lockup = read(os.path.join(REPO, "brand", "lunaway-lockup-dark.svg"))
    lockup = re.sub(r"^<!--.*?-->\s*", "", lockup, flags=re.S)
    urls = {"lockup": hashed("img", "lunaway-lockup-dark", "svg", lockup.encode())}
    shutil.copyfile(os.path.join(REPO, "brand", "social-preview.png"), os.path.join(OUT, "img", "social-preview.png"))
    for name in ("favicon.svg", "favicon.png", "apple-touch-icon.png"):
        shutil.copyfile(os.path.join(REPO, "app", "web", name), os.path.join(OUT, name))
    # favicon.ico for the browsers and tools that ask for it unprompted: the
    # mono mark at 16 px (brand/README.md: below 24 px), the full mark above.
    sizes = []
    for size, svg in ((16, "lunaway-mark-mono.svg"), (32, "lunaway-mark.svg"), (48, "lunaway-mark.svg")):
        png = os.path.join(HERE, f"ico-{size}.tmp.png")
        run("rsvg-convert", "-h", str(size), "-o", png, os.path.join(REPO, "brand", svg))
        run("magick", png, "-background", "none", "-gravity", "center", "-extent", f"{size}x{size}", png)
        sizes.append(png)
    run("magick", *sizes, os.path.join(OUT, "favicon.ico"))
    for png in sizes:
        os.remove(png)
    return urls


# Pages ----------------------------------------------------------------------

def other(lang):
    return "en" if lang == "fr" else "fr"


def url_of(lang, path):
    if path == "/":
        return "/" if lang == "fr" else "/en/"
    return "/" + path if lang == "fr" else "/en/" + path


def parse_fragment(text):
    meta, rest = text.split("\n---\n", 1)
    fields = {}
    for line in meta.strip().splitlines():
        key, value = line.split(":", 1)
        fields[key.strip()] = value.strip()
    night, main = rest.split("\n--- main\n", 1)
    return fields, night.strip("\n"), main.strip("\n")


def head(lang, key, path, fields, assets):
    t = T[lang]
    here = url_of(lang, path)
    fr, en = url_of("fr", path), url_of("en", path)
    title = fields["title"]
    desc = fields["description"]
    lines = [
        "<!DOCTYPE html>",
        f'<html lang="{lang}">',
        "<head>",
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        f"<title>{title}</title>",
        f'<meta name="description" content="{desc}">',
        f'<link rel="canonical" href="{SITE}{here}">',
        f'<link rel="alternate" hreflang="fr" href="{SITE}{fr}">',
        f'<link rel="alternate" hreflang="en" href="{SITE}{en}">',
        f'<link rel="alternate" hreflang="x-default" href="{SITE}{fr}">',
        '<meta name="color-scheme" content="light dark">',
        '<meta name="theme-color" content="#020b1b">',
        f'<link rel="preload" href="{assets["fraunces"]}" as="font" type="font/woff2" crossorigin>',
        f'<link rel="preload" href="{assets["atkinson-regular"]}" as="font" type="font/woff2" crossorigin>',
        f'<link rel="stylesheet" href="{assets["css"]}">',
        '<link rel="icon" href="/favicon.png" sizes="32x32" type="image/png">',
        '<link rel="icon" href="/favicon.svg" type="image/svg+xml">',
        '<link rel="apple-touch-icon" href="/apple-touch-icon.png">',
        '<meta property="og:type" content="website">',
        '<meta property="og:site_name" content="Lunaway">',
        f'<meta property="og:title" content="{fields.get("og_title", title)}">',
        f'<meta property="og:description" content="{desc}">',
        f'<meta property="og:url" content="{SITE}{here}">',
        f'<meta property="og:image" content="{SITE}/img/social-preview.png">',
        '<meta property="og:image:width" content="1280">',
        '<meta property="og:image:height" content="640">',
        f'<meta property="og:image:alt" content="{t["og_image_alt"]}">',
        f'<meta property="og:locale" content="{t["og_locale"]}">',
        f'<meta property="og:locale:alternate" content="{t["og_alt"]}">',
        '<meta name="twitter:card" content="summary_large_image">',
        f'<meta name="twitter:title" content="{fields.get("og_title", title)}">',
        f'<meta name="twitter:description" content="{desc}">',
        f'<meta name="twitter:image" content="{SITE}/img/social-preview.png">',
        f'<meta name="twitter:image:alt" content="{t["og_image_alt"]}">',
    ]
    if fields.get("robots"):
        lines.append(f'<meta name="robots" content="{fields["robots"]}">')
    if key == "home":
        lines.append('<script type="application/ld+json">' + json_ld(lang, desc) + "</script>")
    if key == "delete":
        lines.append(f'<script src="{assets["js"]}" defer></script>')
    lines.append("</head>")
    return "\n".join(lines)


def json_ld(lang, desc):
    data = {
        "@context": "https://schema.org",
        "@type": "SoftwareApplication",
        "name": "Lunaway",
        "url": SITE + url_of(lang, "/"),
        "description": html.unescape(desc),
        "applicationCategory": "TravelApplication",
        "operatingSystem": "Android, Web",
        "inLanguage": ["fr", "en"],
        "isAccessibleForFree": True,
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "EUR"},
        "downloadUrl": "https://play.google.com/store/apps/details?id=legal.p2p.lunaway",
        "installUrl": SITE + "/app/",
        "license": "https://www.gnu.org/licenses/agpl-3.0.html",
        "image": SITE + "/img/social-preview.png",
        "screenshot": [f"{SITE}/img/screens/{lang}-{n}-{name}.webp" for n, name, _ in SCREENS],
        "publisher": {"@type": "Organization", "name": "AxiomTeam", "email": "contact@lunaway.net",
                      "url": SITE + "/"},
    }
    return json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")


def header(lang, key, path, assets):
    t = T[lang]
    o = t["other"]

    def item(target_key, href, label):
        current = ' aria-current="page"' if target_key == key else ""
        return f'<li><a href="{href}"{current}>{label}</a></li>'

    return "\n".join([
        f'<a class="skip-link" href="#main">{t["skip"]}</a>',
        '<header class="masthead">',
        '<div class="site-header">',
        f'<a class="brand" href="{url_of(lang, "/")}"><img src="{assets["lockup"]}" width="140" height="40" alt="{t["brand_alt"]}"></a>',
        f'<nav class="site-nav" aria-label="{t["nav_label"]}">',
        "<ul>",
        item("app", "/app/", t["app"]),
        item("about", url_of(lang, "about"), t["about"]),
        item("privacy", url_of(lang, "privacy"), t["privacy"]),
        "</ul>",
        "</nav>",
        f'<a class="lang-switch" href="{url_of(o, path)}" hreflang="{o}" lang="{o}">{t["other_name"]}</a>',
        "</div>",
        "</header>",
        '<main id="main" tabindex="-1">',
        f'<div class="night{" night--hero" if key == "home" else ""}">',
        sky(),
    ])


def expand(text, icons, lang):
    text = re.sub(r"\{icon:([a-z-]+)\}", lambda m: icons[m.group(1)], text)
    return text.replace("{lang}", lang)


def build_pages(assets, icons):
    footers = {lang: read(os.path.join(SRC, "pages", lang, "_footer.html")).strip("\n") for lang in T}
    for key, rel, path in PAGES:
        for lang in T:
            fields, night, main = parse_fragment(read(os.path.join(SRC, "pages", lang, key + ".html")))
            doc = "\n".join([
                head(lang, key, path, fields, assets),
                "<body>",
                header(lang, key, path, assets),
                expand(night, icons, lang),
                hills(),
                "</div>",
                expand(main, icons, lang),
                "</main>",
                expand(footers[lang], icons, lang),
                "</body>",
                "</html>",
                "",
            ])
            write(rel if lang == "fr" else os.path.join("en", rel), doc)
    # The 404 page answers for any path, in both languages.
    fields, night, main = parse_fragment(read(os.path.join(SRC, "pages", "404.html")))
    doc = "\n".join([
        head("fr", "404", "/", fields, assets).replace(
            '<link rel="canonical" href="https://lunaway.net/">\n', ""),
        "<body>",
        header("fr", "404", "/", assets),
        expand(night, icons, "fr"),
        hills(),
        "</div>",
        expand(main, icons, "fr"),
        "</main>",
        expand(footers["fr"], icons, "fr"),
        "</body>",
        "</html>",
        "",
    ])
    # No alternates on the error page: it has no address of its own.
    doc = re.sub(r'<link rel="alternate"[^>]*>\n', "", doc)
    doc = re.sub(r'<meta property="og:url"[^>]*>\n', "", doc)
    write("404.html", doc)


def build_meta():
    write("robots.txt", "User-agent: *\nAllow: /\n\nSitemap: https://lunaway.net/sitemap.xml\n")
    entries = []
    for _, _, path in PAGES:
        for lang in T:
            alts = "".join(
                f'\n    <xhtml:link rel="alternate" hreflang="{l}" href="{SITE}{url_of(l, path)}"/>'
                for l in ("fr", "en"))
            entries.append(f"  <url>\n    <loc>{SITE}{url_of(lang, path)}</loc>\n    <lastmod>{DATE}</lastmod>{alts}\n  </url>")
    write("sitemap.xml", '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n'
          + "\n".join(entries) + "\n</urlset>\n")


def main():
    assets = {}
    assets.update(build_fonts())
    assets.update(build_images())
    css = read(os.path.join(SRC, "style.css"))
    css = (css.replace("__FONT_FRAUNCES__", assets["fraunces"])
              .replace("__FONT_ATKINSON_REGULAR__", assets["atkinson-regular"])
              .replace("__FONT_ATKINSON_BOLD__", assets["atkinson-bold"]))
    assets["css"] = hashed("", "style", "css", css.encode())
    assets["js"] = hashed("js", "delete-account", "js", read(os.path.join(SRC, "delete-account.js")).encode())
    build_pages(assets, build_icons())
    build_meta()
    for k, v in sorted(assets.items()):
        print(f"{k:18} {v}")


if __name__ == "__main__":
    sys.exit(main())
