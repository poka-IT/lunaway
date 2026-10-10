"""Fails when a fallback font the web engine of the pinned Flutter asks for
is missing from the app's own copy in web/fonts/.

    python3 tool/web/fallback_fonts_check.py --flutter-root "$FLUTTER_ROOT" web/fonts

The CSP of /app/ allows our origin only, so web/flutter_bootstrap.js points
the engine's font fallback (`fontFallbackBaseUrl`) at /app/fonts/, which
mirrors the paths the engine asks fonts.gstatic.com for. A family is kept
when its directory is in web/fonts/; every file the engine lists for a kept
family must then be there, or a character it covers asks for a file the
server answers 404 (the emoji, before 2026-10-10). A new Flutter
can move a family to a new version directory: this check names the files
to download again.

The list is read from the web SDK in the Flutter cache
(bin/cache/flutter_web_sdk), which a web build or `flutter precache --web`
fills. Standard library only.
"""

import argparse
import os
import re
import sys

ENGINE_DATA = os.path.join(
    "bin", "cache", "flutter_web_sdk", "lib", "_engine", "engine", "font_fallback_data.dart"
)
PATH = re.compile(r"'([a-z0-9]+/v[0-9]+/[A-Za-z0-9_.\-]+\.woff2)'")
# The families the app's texts need beyond its own fonts and Roboto:
# extended Latin, Greek and Cyrillic, the symbols, and the emoji travellers
# put in their reviews.
REQUIRED = ("notocoloremoji", "notosans", "notosanssymbols", "notosanssymbols2")


def engine_paths(data: str) -> list[str]:
    """Every font file the engine's fallback data names, as it asks for it."""
    return sorted(set(PATH.findall(data)))


def missing(paths: list[str], fonts_dir: str) -> tuple[list[str], list[str]]:
    """The families kept in `fonts_dir`, and the files of those families the
    engine names that are not there."""
    kept = sorted(
        d for d in os.listdir(fonts_dir) if os.path.isdir(os.path.join(fonts_dir, d))
    )
    absent = [f"{family}/ (the whole family)" for family in REQUIRED if family not in kept]
    absent += [
        p
        for p in paths
        if p.split("/", 1)[0] in kept and not os.path.isfile(os.path.join(fonts_dir, p))
    ]
    return kept, absent


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--flutter-root", default=os.environ.get("FLUTTER_ROOT"))
    parser.add_argument("fonts_dir")
    args = parser.parse_args()
    if not args.flutter_root:
        print("fallback_fonts_check: --flutter-root or FLUTTER_ROOT is needed", file=sys.stderr)
        return 2
    data_file = os.path.join(args.flutter_root, ENGINE_DATA)
    if not os.path.isfile(data_file):
        print(
            f"fallback_fonts_check: no {data_file}; run a web build or `flutter precache --web`",
            file=sys.stderr,
        )
        return 2
    with open(data_file, encoding="utf-8") as f:
        paths = engine_paths(f.read())
    if not paths:
        print(f"fallback_fonts_check: no font path read from {data_file}", file=sys.stderr)
        return 2
    kept, absent = missing(paths, args.fonts_dir)
    if absent:
        print("fallback fonts the engine asks for and web/fonts/ lacks:", file=sys.stderr)
        for p in absent:
            print(f"  https://fonts.gstatic.com/s/{p}", file=sys.stderr)
        return 1
    print(f"fallback_fonts_check: {', '.join(kept)} complete ({len(paths)} files known to the engine)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
