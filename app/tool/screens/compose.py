"""Store images of the release, from the raw shots of the store tour.

Takes the raw shots that `tool/screens/capture.py` wrote for one device
profile and one language (`integration_test/store_tour_test.dart`, one PNG
per scene, named `<tag>-<scene>.png`), adds each scene's caption from
`store_captions.json` in a band at the top, and writes the store's images
where fastlane reads them:

- Google Play: `fastlane/metadata/android/<locale>/images/phoneScreenshots/`,
  `sevenInchScreenshots/`, `tenInchScreenshots/`, named `01-map.jpg` and so
  on (the upload order is the name order);
- App Store: `fastlane/screenshots/ios/<locale>/` (the `screenshots_path`
  of the `deliver` lane, docs/app-store.md), named
  `<nn>_<profile>_<scene>.jpg` (`deliver` sorts by name and tells the
  device class from the size).

The band takes 16 % of the height, in Minuit (light scenes) or Clair de
lune (dark scenes), the caption centred in Fraunces 600 on two lines at
most; the shot is scaled to the rest of the height, centred on the band's
colour. The images are JPEG at quality 90 without chroma subsampling, which
both stores take: a PNG of the same image weighs about 2.4 times as much,
and the repository carries some 230 of them (six languages, five sets).
Before it exits, the script checks every image of the set it wrote: exact
size, no alpha channel, under 8 MB, a count within the store's limits. It
exits non-zero on any failure.

    python3 tool/screens/compose.py --profile play-phone --lang fr \
        --raw ../data/tmp/screens/play-phone/fr

Run from app/. Needs Pillow.
"""

import argparse
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.abspath(os.path.join(HERE, "..", ".."))
REPO = os.path.abspath(os.path.join(APP, ".."))
FONT = os.path.join(APP, "assets", "fonts", "fraunces", "Fraunces-Variable.ttf")
CAPTIONS = os.path.join(HERE, "store_captions.json")

MINUIT = (0x06, 0x1F, 0x43)
CLAIR_DE_LUNE = (0xFD, 0xF1, 0xDB)

PLAY_LOCALES = {"fr": "fr-FR", "en": "en-US", "de": "de-DE", "es": "es-ES", "it": "it-IT", "nl": "nl-NL"}
IOS_LOCALES = {"fr": "fr-FR", "en": "en-US", "de": "de-DE", "es": "es-ES", "it": "it", "nl": "nl-NL"}

# The scenes of each profile, in the order the store shows them
# (docs/screenshots.md). The first three carry the app's main use: a map of
# the places, a place's page, a route for the vehicle. The sets differ so
# that every scene of the tour stands in one store or another.
PROFILES = {
    "play-phone": {
        "size": (1080, 1920),
        "store": "play",
        "folder": "phoneScreenshots",
        "limit": 8,
        "scenes": ["01-map", "03-place", "07-route", "09-guidance", "08-on-the-way", "11-stops",
                   "05-search", "13-offline"],
    },
    "play-7in": {
        "size": (1080, 1920),
        "store": "play",
        "folder": "sevenInchScreenshots",
        "limit": 8,
        "scenes": ["01-map", "03-place", "07-route", "09-guidance", "08-on-the-way", "06-filters"],
    },
    "play-10in": {
        "size": (2560, 1440),
        "store": "play",
        "folder": "tenInchScreenshots",
        "limit": 8,
        "scenes": ["01-map", "03-place", "07-route", "10-camera", "11-stops", "15-favorites"],
    },
    "ios-6.9": {
        "size": (1320, 2868),
        "store": "ios",
        "limit": 10,
        "scenes": ["01-map", "03-place", "07-route", "09-guidance", "08-on-the-way", "11-stops",
                   "05-search", "13-offline", "15-favorites", "12-voice"],
    },
    "ipad-13": {
        "size": (2064, 2752),
        "store": "ios",
        "limit": 10,
        "scenes": ["01-map", "03-place", "07-route", "09-guidance", "10-camera", "08-on-the-way",
                   "11-stops", "06-filters"],
    },
}


def font(size):
    f = ImageFont.truetype(FONT, size)
    # Optical size 72 (display), weight 600 (semibold), as the app's titles.
    f.set_variation_by_axes([72, 600])
    return f


def wrap(draw, text, face, width):
    """The caption on as few lines as fit [width], balanced over two lines
    when one does not fit; None when two lines are not enough."""
    if draw.textlength(text, font=face) <= width:
        return [text]
    words = text.split()
    best = None
    for i in range(1, len(words)):
        a, b = " ".join(words[:i]), " ".join(words[i:])
        wa, wb = draw.textlength(a, font=face), draw.textlength(b, font=face)
        if wa <= width and wb <= width:
            score = abs(wa - wb)
            if best is None or score < best[0]:
                best = (score, [a, b])
    return best[1] if best else None


def caption_size(captions, size):
    """The text's height for a set: a quarter of the band at most, the same
    on every image of the set, so that the largest two lines of its
    captions fit the width with a margin on each side."""
    w, h = size
    band = round(h * 0.16)
    width = w - 2 * round(w * 0.07)
    draw = ImageDraw.Draw(Image.new("RGB", (8, 8)))
    px = round(band * 0.25)
    while any(wrap(draw, c, font(px), width) is None for c in captions):
        px -= 2
        if px < 20:
            raise SystemExit(f"captions too long for {size}")
    return px


def compose(raw_path, caption, size, dark, px):
    w, h = size
    band = round(h * 0.16)
    background = CLAIR_DE_LUNE if dark else MINUIT
    ink = MINUIT if dark else CLAIR_DE_LUNE
    out = Image.new("RGB", (w, h), background)
    shot = Image.open(raw_path).convert("RGB")
    room = h - band
    scale = room / shot.height
    if shot.width * scale > w:
        scale = w / shot.width
    sw, sh = round(shot.width * scale), round(shot.height * scale)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    out.paste(shot, ((w - sw) // 2, band + (room - sh) // 2))
    draw = ImageDraw.Draw(out)
    face = font(px)
    lines = wrap(draw, caption, face, w - 2 * round(w * 0.07))
    leading = round(px * 1.18)
    block = leading * (len(lines) - 1) + px
    top = (band - block) / 2
    for i, line in enumerate(lines):
        draw.text((w / 2, top + i * leading + px / 2), line, font=face, fill=ink, anchor="mm")
    return out


IMAGE_TYPES = (".png", ".jpg", ".jpeg")


def check(paths, size, limit):
    """The store's rules on the images of one set; a list of the faults."""
    faults = []
    if not 1 <= len(paths) <= limit:
        faults.append(f"{len(paths)} images in the set, the store takes 1 to {limit}")
    for path in paths:
        img = Image.open(path)
        if img.size != size:
            faults.append(f"{path}: {img.size}, expected {size}")
        if img.mode != "RGB":
            faults.append(f"{path}: mode {img.mode}, expected RGB without alpha")
        if os.path.getsize(path) >= 8 * 1024 * 1024:
            faults.append(f"{path}: {os.path.getsize(path)} bytes, over 8 MB")
    return faults


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--profile", required=True, choices=sorted(PROFILES))
    p.add_argument("--lang", required=True, choices=sorted(PLAY_LOCALES))
    p.add_argument("--raw", required=True, help="the raw shots of the tour, <tag>-<scene>.png")
    p.add_argument("--dark", action="store_true", help="the raw shots are of the dark theme")
    p.add_argument("--out", help="another root than the repository's fastlane/ folder")
    args = p.parse_args()
    profile = PROFILES[args.profile]
    play = profile["store"] == "play"
    with open(CAPTIONS, encoding="utf-8") as f:
        captions = json.load(f)[args.lang]
    root = args.out or os.path.join(REPO, "fastlane")
    if play:
        folder = os.path.join(root, "metadata", "android", PLAY_LOCALES[args.lang], "images", profile["folder"])
    else:
        folder = os.path.join(root, "screenshots", "ios", IOS_LOCALES[args.lang])
    os.makedirs(folder, exist_ok=True)

    # The set's own images only: an iPhone and an iPad set share the App
    # Store folder of a language.
    def mine(name):
        return name.lower().endswith(IMAGE_TYPES) and (play or f"_{args.profile}_" in name)

    for name in os.listdir(folder):
        if mine(name):
            os.remove(os.path.join(folder, name))
    written = []
    px = caption_size([captions[scene] for scene in profile["scenes"]], profile["size"])
    for i, scene in enumerate(profile["scenes"], start=1):
        found = sorted(f for f in os.listdir(args.raw) if f.endswith(f"-{scene}.png") or f == f"{scene}.png")
        if len(found) != 1:
            raise SystemExit(f"{len(found)} raw shots of {scene} in {args.raw}, expected one")
        image = compose(os.path.join(args.raw, found[0]), captions[scene], profile["size"], args.dark, px)
        # Play shows its images in the order of their names: the scene's
        # place in the set leads.
        short = scene.split("-", 1)[1]
        name = f"{i:02d}-{short}.jpg" if play else f"{i:02d}_{args.profile}_{scene}.jpg"
        path = os.path.join(folder, name)
        image.save(path, quality=90, subsampling=0, optimize=True)
        written.append(path)
        print(f"wrote {path}")
    faults = check(written, profile["size"], profile["limit"])
    for fault in faults:
        print(f"FAULT {fault}", file=sys.stderr)
    sys.exit(1 if faults else 0)


if __name__ == "__main__":
    main()
