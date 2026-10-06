"""Vendors the Phosphor icons (MIT) the app uses.

    python3 tool/icons/phosphor.py      # from app/

The phosphor_flutter package (2.1.0, its latest release) no longer compiles
on Flutter 3.47, where IconData is a final class. This takes the same fonts
and code points from the package's repository at a pinned commit, checks
their SHA-256, copies the regular and fill fonts into assets/fonts/phosphor/
with the licence, and writes lib/shared/theme/phosphor_glyphs.dart with a
const IconData for each icon listed in ICONS. To add an icon, add its name
(as phosphor_flutter spells it) to ICONS and run the script again.
"""

import hashlib
import os
import re
import sys
import urllib.request

COMMIT = "0646a965ca3d8de8951f6fdd980f38320229f653"  # tag v2.1.0
BASE = "https://raw.githubusercontent.com/phosphor-icons/flutter/" + COMMIT + "/"
FILES = {
    "lib/fonts/Phosphor.ttf": "",
    "lib/fonts/Phosphor-Fill.ttf": "",
    "lib/src/phosphor_icons_regular.dart": "",
    "lib/src/phosphor_icons_fill.dart": "",
    "LICENSE": "",
}

# Every icon the app shows, by style. Keep sorted.
ICONS = {
    "regular": """
        arrowClockwise arrowLeft arrowsClockwise arrowsHorizontal arrowSquareOut arrowsVertical
        baby bank barricade basket bicycle binoculars bookmarkSimple bookmarksSimple bread
        buildings calendarBlank camera cameraPlus caretDown caretRight carSimple cellSignalHigh
        chatsCircle check checkCircle circleHalf clock clockCountdown clockCounterClockwise
        cloudArrowDown cloudArrowUp cloudCheck cloudSlash code compass copy crosshair deviceMobile
        dotsThree dotsThreeVertical downloadSimple drop dropHalfBottom eyeSlash fileImage fileText
        firstAid fish fishSimple flag gasCan gasPump gear globe globeHemisphereEast gpsFix
        gpsSlash handHeart hardDrives heart hourglass image imageBroken images info key leaf
        listBullets listChecks magnifyingGlass mapPin mapPinPlus mapPinSimpleLine mapTrifold
        megaphone minus moon moonStars motorcycle mountains navigationArrow notePencil path pause
        pawPrint pencilSimple personSimpleHike personSimpleSwim phone pizza play plug plus printer
        prohibit qrCode ruler scales scan sealCheck sealQuestion shareNetwork shieldCheck
        shieldStar shower signOut signpost slidersHorizontal smileyAngry snowflake speakerHigh
        speakerSlash squaresFour stack star sun
        sunHorizon swimmingPool tag textAlignLeft toilet toiletPaper translate trash
        truckTrailer user userCircle van warning warningCircle washingMachine waves wifiHigh
        wind wrench x
    """,
    "fill": """
        barn basket bread carProfile carrot chargingStation checkCircle cheese coffee crosshair
        cylinder drop dropHalfBottom egg envelopeSimple firstAid gasPump heart hospital
        houseLine info jeep knife letterCircleP mapPin mapTrifold money navigationArrow package
        pawPrint picnicTable pizza recycle shoppingCart shower snowflake star stethoscope
        storefront tent toilet toiletPaper treeEvergreen user van washingMachine wrench
    """,
}


def fetch(path, cache):
    dest = os.path.join(cache, path.replace("/", "_"))
    if not os.path.exists(dest):
        with urllib.request.urlopen(BASE + path, timeout=60) as r, open(dest + ".part", "wb") as f:
            f.write(r.read())
        os.rename(dest + ".part", dest)
    with open(dest, "rb") as f:
        data = f.read()
    return data, hashlib.sha256(data).hexdigest()


def code_points(dart_source):
    return {
        m.group(1): int(m.group(2), 16)
        for m in re.finditer(r"static const (\w+) = Phosphor\w*IconData\(0x([0-9a-f]+)", dart_source)
    }


def main():
    app = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    cache = os.path.join(app, "..", "data", "tmp", "phosphor-" + COMMIT[:12])
    os.makedirs(cache, exist_ok=True)
    got = {path: fetch(path, cache) for path in FILES}
    expected = {}
    sums = os.path.join(os.path.dirname(os.path.abspath(__file__)), "phosphor.sha256")
    if os.path.exists(sums):
        for line in open(sums):
            digest, path = line.split()
            expected[path] = digest
    for path, (_, digest) in got.items():
        if path in expected and expected[path] != digest:
            sys.exit("sha256 mismatch for %s: %s" % (path, digest))
    if not expected:
        with open(sums, "w") as f:
            for path, (_, digest) in sorted(got.items()):
                f.write("%s  %s\n" % (digest, path))

    fonts = os.path.join(app, "assets", "fonts", "phosphor")
    os.makedirs(fonts, exist_ok=True)
    for src, name in [("lib/fonts/Phosphor.ttf", "Phosphor-Regular.ttf"), ("lib/fonts/Phosphor-Fill.ttf", "Phosphor-Fill.ttf"), ("LICENSE", "LICENSE.txt")]:
        with open(os.path.join(fonts, name), "wb") as f:
            f.write(got[src][0])

    tables = {
        "regular": code_points(got["lib/src/phosphor_icons_regular.dart"][0].decode()),
        "fill": code_points(got["lib/src/phosphor_icons_fill.dart"][0].decode()),
    }
    lines = [
        "// Written by tool/icons/phosphor.py from Phosphor's Flutter repository",
        "// (MIT) at commit " + COMMIT[:12] + ". Add an icon there, never here.",
        "import 'package:flutter/widgets.dart';",
        "",
        "/// Phosphor icons, regular weight: the interface.",
        "abstract final class PhosphorRegular {",
    ]
    for style, family, cls in [("regular", "PhosphorRegular", None), ("fill", "PhosphorFill", "PhosphorFill")]:
        if cls:
            lines += ["}", "", "/// Phosphor icons, fill: active states, pins and avatars.", "abstract final class " + cls + " {"]
        for name in sorted(ICONS[style].split()):
            if name not in tables[style]:
                sys.exit("unknown %s icon: %s" % (style, name))
            lines.append(
                "  static const %s = IconData(0x%x, fontFamily: '%s');" % (name, tables[style][name], family)
            )
    lines += ["}", ""]
    out = os.path.join(app, "lib", "shared", "theme", "phosphor_glyphs.dart")
    with open(out, "w") as f:
        f.write("\n".join(lines))
    print("wrote %d regular and %d fill icons" % (len(ICONS["regular"].split()), len(ICONS["fill"].split())))


if __name__ == "__main__":
    main()
