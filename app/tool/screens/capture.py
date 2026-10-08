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

A tour that asks for the position the way a user grants it (Android):
`--revoke-location` takes the permission back before the run, so the app
asks; `--location LAT,LON` gives the emulator's fused provider that position
through a test provider (removed at the end), since the app's balanced
request never reaches the emulated GPS; when the test prints `ALLOW
LOCATION`, the host taps the system prompt's "While using the app". A
`CHECK MOVED <a> <b>` line compares the map band of two shots already taken
and fails the run when the screen did not change (a map that froze while
its engine moved).

    python3 tool/screens/capture.py --device android:emulator-5554 --size 1080x1920 \
        --test integration_test/location_grant_test.dart --api https://api.lunaway.net \
        --revoke-location --location 44.4846,4.6806 --out ../data/tmp/grant

Run from app/. Needs Pillow; on macOS also the Xcode command line tools.
"""

import argparse
import os
import re
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


# The system prompt's button that grants the position while the app is in
# use, in the languages the tours run in.
WHILE_IN_USE = ("Lorsque vous utilisez l'appli", "While using the app", "Pendant l'utilisation de l'appli")


def tap_while_in_use(ident, wait=12.0):
    """Taps the system prompt's "While using the app" once it shows."""
    end = time.time() + wait
    while time.time() < end:
        subprocess.run(["adb", "-s", ident, "shell", "uiautomator", "dump", "/sdcard/lw-ui.xml"],
                       capture_output=True)
        xml = subprocess.run(["adb", "-s", ident, "exec-out", "cat", "/sdcard/lw-ui.xml"],
                             capture_output=True).stdout.decode("utf-8", "replace")
        for node in re.finditer(r"<node [^>]*>", xml):
            text = re.search(r' text="([^"]*)"', node.group(0))
            bounds = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node.group(0))
            if text and bounds and text.group(1) in WHILE_IN_USE:
                x1, y1, x2, y2 = map(int, bounds.groups())
                subprocess.run(["adb", "-s", ident, "shell", "input", "tap",
                                str((x1 + x2) // 2), str((y1 + y2) // 2)], check=False)
                print(f"tapped {text.group(1)!r}", flush=True)
                return True
        time.sleep(0.5)
    print("no location prompt to answer", flush=True)
    return False


def moved(a, b):
    """Share of the pixels of the map band (between the chips and the list)
    that differ between two shots."""
    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    w, h = ia.size
    box = (0, int(h * 0.24), w, int(h * 0.57))
    da = ia.crop(box).tobytes()
    db = ib.crop(box).tobytes()
    differ = sum(1 for i in range(0, len(da), 3) if abs(da[i] - db[i]) + abs(da[i + 1] - db[i + 1]) + abs(da[i + 2] - db[i + 2]) > 48)
    return differ / (len(da) // 3)


def set_test_location(ident, latlon):
    run = ["adb", "-s", ident, "shell", "cmd", "location", "providers"]
    subprocess.run(run + ["add-test-provider", "fused"], check=False, capture_output=True)
    subprocess.run(run + ["set-test-provider-enabled", "fused", "true"], check=False, capture_output=True)
    subprocess.run(run + ["set-test-provider-location", "fused", "--location", latlon, "--accuracy", "10"],
                   check=False, capture_output=True)


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
    p.add_argument("--revoke-location", action="store_true",
                   help="Android: take the location permission back before the run")
    p.add_argument("--location", help="Android: LAT,LON given to the fused provider for the run")
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
        # flutter test uninstalls the app after an integration test, and with
        # it the data of whoever uses the device: the emulator is shared.
        target += ["--flavor", "store", "--no-uninstall"]
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
        if args.revoke_location:
            for perm in ("ACCESS_FINE_LOCATION", "ACCESS_COARSE_LOCATION"):
                subprocess.run(["adb", "-s", ident, "shell", "pm", "revoke", "legal.p2p.lunaway",
                                f"android.permission.{perm}"], check=False, capture_output=True)
        if args.location:
            set_test_location(ident, args.location)
    try:
        code = run(cmd, env, args, kind, height)
    finally:
        if kind == "android":
            subprocess.run(adb + ["size", "reset"], check=False)
            subprocess.run(adb + ["density", "reset"], check=False)
            if args.location:
                subprocess.run(["adb", "-s", ident, "shell", "cmd", "location", "providers",
                                "remove-test-provider", "fused"], check=False, capture_output=True)
    sys.exit(code)


def run(cmd, env, args, kind, height):
    proc = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    frozen = []
    for line in proc.stdout:
        # Flushed per line: the log of a long run is read while it runs.
        sys.stdout.write(line)
        sys.stdout.flush()
        # A tour that shows the device's position asks for it to be granted:
        # the install that `flutter test` makes starts without permissions.
        if kind == "android" and "GRANT LOCATION" in line:
            ident = args.device.partition(":")[2]
            for perm in ("ACCESS_FINE_LOCATION", "ACCESS_COARSE_LOCATION"):
                subprocess.run(["adb", "-s", ident, "shell", "pm", "grant", "legal.p2p.lunaway",
                                f"android.permission.{perm}"], check=False)
        if kind == "android" and "ALLOW LOCATION" in line:
            ident = args.device.partition(":")[2]
            if args.location:
                set_test_location(ident, args.location)
            tap_while_in_use(ident)
        check = line.find("CHECK MOVED ")
        if check >= 0:
            a, b = line[check + 12:].split()[:2]
            share = moved(os.path.join(args.out, f"{a}.png"), os.path.join(args.out, f"{b}.png"))
            verdict = "MOVED" if share >= 0.02 else "FROZEN"
            print(f"{verdict} {a} -> {b}: {share:.1%} of the map changed", flush=True)
            if verdict == "FROZEN":
                frozen.append((a, b))
        marker = line.find("SHOT ")
        if marker >= 0:
            name = line[marker + 5:].strip()
            time.sleep(0.4)
            path = os.path.join(args.out, f"{name}.png")
            if kind == "macos":
                capture(path, height)
            else:
                capture_device(args.device, path)
    code = proc.wait()
    if frozen:
        print(f"the map did not change on screen between {frozen}", flush=True)
        return code or 1
    return code


if __name__ == "__main__":
    main()
