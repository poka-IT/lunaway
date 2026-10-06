"""Screenshots of the real app, through the screens tour test.

Runs integration_test/screens_tour_test.dart (or the test given by `--test`,
such as integration_test/navigation_drive_test.dart) on a device, against an
API (`--api`, real data) or in demo mode (the default), and captures the
screen each time the test prints a `SHOT <name>` line:

- macOS: a window of the given content size, title bar cropped, so 540x960
  gives a 1080x1920 image on a Retina screen (the phone store format). The
  window is shown on every Space for the run, above other windows, and the
  screen must be unlocked.
- Android: an emulator or device (`--device android:emulator-5554`), through
  `adb screencap`. `--size` and `--density` override the screen for the run
  (`adb shell wm size`, reset at the end), so one phone emulator also gives
  the tablet images: `--size 1600x2560 --density 320` is a 10 inch tablet.
- iOS: a simulator (`--device ios:<udid>`), through `xcrun simctl io`.

    python3 tool/screens/capture.py --device macos --size 540x960 --locale fr --theme light --out ../plan/screenshots/macos

Run from app/. Needs Pillow; on macOS also the Xcode command line tools.
"""

import argparse
import os
import subprocess
import sys
import time

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "..", "..", "data", "tmp", "window_id")


def window_id():
    if not os.path.exists(TOOL):
        os.makedirs(os.path.dirname(TOOL), exist_ok=True)
        subprocess.run(["swiftc", "-O", os.path.join(HERE, "window_id.swift"), "-o", TOOL], check=True)
    out = subprocess.run([TOOL, "Lunaway"], capture_output=True, text=True).stdout.strip()
    return out or None


def capture(path, content_height):
    wid = window_id()
    if wid is None:
        print(f"no window for {path}", file=sys.stderr)
        return
    raw = os.path.join(os.path.dirname(TOOL), "capture.png")
    done = subprocess.run(["screencapture", "-o", "-x", "-l", wid, raw], capture_output=True, text=True)
    if done.returncode != 0 or not os.path.exists(raw):
        print(f"screencapture failed for {path}: {done.stderr.strip()}", file=sys.stderr)
        return
    img = Image.open(raw)
    scale = 2 if img.height > content_height * 1.5 else 1
    keep = content_height * scale
    img.crop((0, img.height - keep, img.width, img.height)).save(path)
    os.remove(raw)
    print(f"captured {path} {img.width}x{keep}", flush=True)


def capture_device(device, path):
    kind, _, ident = device.partition(":")
    if kind == "android":
        with open(path, "wb") as out:
            subprocess.run(["adb", "-s", ident, "exec-out", "screencap", "-p"], stdout=out, check=True)
    elif kind == "ios":
        subprocess.run(["xcrun", "simctl", "io", ident, "screenshot", path], check=True, capture_output=True)
    print(f"captured {path}", flush=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--device", default="macos")
    p.add_argument("--size", default="540x960")
    p.add_argument("--locale", default="fr")
    p.add_argument("--theme", default="light")
    p.add_argument("--density", type=int, help="Android only: screen density for the run")
    p.add_argument("--out", required=True)
    p.add_argument(
        "--test",
        default="integration_test/screens_tour_test.dart",
        help="the tour to run, which prints the SHOT lines (integration_test/community_tour_test.dart: "
        "the account and contributions; integration_test/navigation_drive_test.dart: the guidance)",
    )
    p.add_argument(
        "--define",
        action="append",
        default=[],
        help="an extra --dart-define for the tour, NAME=value (repeatable)",
    )
    p.add_argument("--api", help="API base URL for real data; demo mode without it")
    p.add_argument("--fresh", action="store_true", help="start from an empty device")
    p.add_argument(
        "--basemap",
        help="base URL of another basemap host with the same layout (planet.json, fonts/, sprites/)",
    )
    args = p.parse_args()
    width, height = (int(v) for v in args.size.split("x"))
    tag = f"{args.locale}-{args.size}-{args.theme}"
    args.out = os.path.abspath(args.out)
    os.makedirs(args.out, exist_ok=True)
    env = dict(os.environ, LUNAWAY_WINDOW=args.size, LUNAWAY_ALL_SPACES="1")
    kind, _, ident = args.device.partition(":")
    target = ["-d", "macos"] if kind == "macos" else ["-d", ident]
    if kind == "android":
        target += ["--flavor", "store"]
    cmd = [
        "fvm", "flutter", "test", args.test, *target,
        f"--dart-define=LUNAWAY_API_URL={args.api}" if args.api else "--dart-define=LUNAWAY_DEMO=true",
        f"--dart-define=LUNAWAY_TOUR_FRESH={'true' if args.fresh else 'false'}",
        *([f"--dart-define=LUNAWAY_BASEMAP_URL={args.basemap}"] if args.basemap else []),
        f"--dart-define=LUNAWAY_TOUR_LOCALE={args.locale}",
        f"--dart-define=LUNAWAY_TOUR_THEME={args.theme}",
        f"--dart-define=LUNAWAY_TOUR_TAG={tag}",
        *[f"--dart-define={d}" for d in args.define],
    ]
    if kind == "android":
        adb = ["adb", "-s", ident, "shell", "wm"]
        subprocess.run(adb + ["size", args.size], check=True)
        if args.density:
            subprocess.run(adb + ["density", str(args.density)], check=True)
    try:
        code = run(cmd, env, args, kind, height)
    finally:
        if kind == "android":
            subprocess.run(adb + ["size", "reset"], check=False)
            subprocess.run(adb + ["density", "reset"], check=False)
    sys.exit(code)


def run(cmd, env, args, kind, height):
    proc = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for line in proc.stdout:
        # Flushed per line: the log of a long run is read while it runs.
        sys.stdout.write(line)
        sys.stdout.flush()
        marker = line.find("SHOT ")
        if marker >= 0:
            name = line[marker + 5:].strip()
            time.sleep(0.4)
            path = os.path.join(args.out, f"{name}.png")
            if kind == "macos":
                capture(path, height)
            else:
                capture_device(args.device, path)
    return proc.wait()


if __name__ == "__main__":
    main()
