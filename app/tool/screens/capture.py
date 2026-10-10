"""Screenshots of the real app, through the screens tour test.

Runs integration_test/screens_tour_test.dart (or the test given by `--test`,
such as integration_test/navigation_drive_test.dart) on a device, against an
API (`--api`, real data) or in demo mode (the default), and captures the
screen each time the test prints a `SHOT <name>` line:

- macOS: a window of the given content size, title bar cropped, so 540x960
  gives a 1080x1920 image on a Retina screen (the phone store format). The
  window is shown on every Space for the run, above other windows, and the
  screen must be unlocked; a window minimized meanwhile is brought back from
  the Dock for the shot.
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
its engine moved). A `WRITE <name>.txt <text>` line appends the text to that
file in the output folder, emptied at its first line of the run: the
transcript of what a guidance said (integration_test/radars_real_tour_test.dart).

    python3 tool/screens/capture.py --device android:emulator-5554 --size 1080x1920 \
        --test integration_test/location_grant_test.dart --api https://api.lunaway.net \
        --revoke-location --location 44.4846,4.6806 --out ../data/tmp/grant

The store images come from the release build (`--release`, Android): the
tour is built as the app's entry point (`flutter build apk --release -t`),
installed, launched, and its lines read from logcat, since a release build
has no connection back to `flutter test`. The build goes under an
application id of its own (`--id-suffix`, `.shots` by default in this
mode), signed with the debug key; `--app` reuses one built before (the
phone and both tablets of a language share it). On the iOS simulator, which
runs no release build, `--release` builds the tour as the app in debug
(`flutter build ios --simulator -t`), installs it and reads its lines in
the simulator's log (`log stream`); the permission to locate is granted
before the launch (`simctl privacy`), the dialog being out of a test's
reach, and `--location` places the simulator. `--status` sets the status
bar of the store images (the clock of each shot, full battery, full signal) through
Android's demo mode or `simctl status_bar`, and puts it back at the end.

    python3 tool/screens/capture.py --device android:emulator-5580 --size 1080x1920 \
        --density 420 --release --status --test integration_test/store_tour_test.dart \
        --api https://api.lunaway.net --locale de --out ../data/tmp/screens/play-phone/de

Run from app/. Needs Pillow; on macOS also the Xcode command line tools.
"""

import argparse
import os
import queue
import re
import subprocess
import sys
import threading
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


def restore_window():
    """Brings the window back from the Dock: on a Mac in use, someone may
    minimize it during a long run, and a minimized window draws nothing."""
    subprocess.run(["osascript", "-e", 'tell application "System Events" to tell process "Dock" '
                    'to click UI element "Lunaway" of list 1'], capture_output=True)


def capture(path, content_height):
    wid = window_id()
    if wid is None:
        restore_window()
        time.sleep(1.5)
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


def android_demo(ident, *extra):
    subprocess.run(["adb", "-s", ident, "shell", "am", "broadcast", "-a", "com.android.systemui.demo",
                    *extra], check=False, capture_output=True)


_hours_before = None
_demo_before = None


def demo_status(kind, ident, on, locale):
    """The status bar of the store images (docs/screenshots.md): a full
    battery, full Wi-Fi, no notification icon, the clock set at each shot
    ([status_clock]) in the hours of the language (12 in English, 24 in the
    others); or the device's own, its hour format put back."""
    global _hours_before, _demo_before
    if kind == "android":
        setting = ["adb", "-s", ident, "shell", "settings"]
        if on:
            _hours_before = subprocess.run(setting + ["get", "system", "time_12_24"], capture_output=True,
                                           text=True).stdout.strip()
            _demo_before = subprocess.run(setting + ["get", "global", "sysui_demo_allowed"], capture_output=True,
                                          text=True).stdout.strip()
            subprocess.run(setting + ["put", "system", "time_12_24", "12" if locale == "en" else "24"], check=False)
            subprocess.run(setting + ["put", "global", "sysui_demo_allowed", "1"], check=False)
            android_demo(ident, "-e", "command", "enter")
            android_demo(ident, "-e", "command", "battery", "-e", "level", "100", "-e", "plugged", "false")
            android_demo(ident, "-e", "command", "network", "-e", "wifi", "show", "-e", "level", "4",
                         "-e", "fully", "true")
            android_demo(ident, "-e", "command", "network", "-e", "mobile", "hide")
            android_demo(ident, "-e", "command", "notifications", "-e", "visible", "false")
            status_clock(kind, ident, locale)
        else:
            android_demo(ident, "-e", "command", "exit")
            if _hours_before and _hours_before != "null":
                subprocess.run(setting + ["put", "system", "time_12_24", _hours_before], check=False)
            elif _hours_before == "null":
                subprocess.run(setting + ["delete", "system", "time_12_24"], check=False, capture_output=True)
            if _demo_before and _demo_before != "null":
                subprocess.run(setting + ["put", "global", "sysui_demo_allowed", _demo_before], check=False)
            elif _demo_before == "null":
                subprocess.run(setting + ["delete", "global", "sysui_demo_allowed"], check=False,
                               capture_output=True)
    elif kind == "ios":
        if on:
            subprocess.run(["xcrun", "simctl", "status_bar", ident, "override", "--time", clock_text(locale),
                            "--batteryState", "discharging", "--batteryLevel", "100", "--wifiBars", "3",
                            "--cellularBars", "4", "--dataNetwork", "wifi"], check=False)
        else:
            subprocess.run(["xcrun", "simctl", "status_bar", ident, "clear"], check=False)


def clock_text(locale):
    """The time now as a status bar writes it in [locale]."""
    now = time.localtime()
    if locale == "en":
        return f"{now.tm_hour % 12 or 12}:{now.tm_min:02d}"
    return f"{now.tm_hour:02d}:{now.tm_min:02d}"


def status_clock(kind, ident, locale):
    """The status bar's clock at the time of the shot: the times the app
    shows (an arrival, a stop) are the device's, and a fixed 09:41 beside
    them would contradict them."""
    if kind == "android":
        # The device's own time: its zone may not be the computer's.
        now = subprocess.run(["adb", "-s", ident, "shell", "date", "+%H%M"], capture_output=True,
                             text=True).stdout.strip()
        android_demo(ident, "-e", "command", "clock", "-e", "hhmm", now if len(now) == 4 else time.strftime("%H%M"))
    elif kind == "ios":
        subprocess.run(["xcrun", "simctl", "status_bar", ident, "override", "--time", clock_text(locale)],
                       check=False)


def build_release(args, ident_suffix):
    """The tour built as the app (release, store flavour, debug key), its
    path."""
    defines = tour_defines(args)
    env = dict(os.environ)
    # The Android Gradle plugin of the app compiles for Java 21.
    jdk = "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
    if "JAVA_HOME" not in env and os.path.isdir(jdk):
        env["JAVA_HOME"] = jdk
    cmd = ["fvm", "flutter", "build", "apk", "--release", "--flavor", "store", "-t", args.test,
           "-P", f"testIdSuffix={ident_suffix}", "-P", "allowDebugSigning=true", *defines]
    print(" ".join(cmd), flush=True)
    subprocess.run(cmd, check=True, env=env)
    return os.path.join("build", "app", "outputs", "flutter-apk", "app-store-release.apk")


def tour_defines(args):
    tag = args.tag or f"{args.locale}-{args.size}-{args.theme}"
    return [
        f"--dart-define=LUNAWAY_API_URL={args.api}" if args.api else "--dart-define=LUNAWAY_DEMO=true",
        f"--dart-define=LUNAWAY_TOUR_FRESH={'true' if args.fresh else 'false'}",
        *([f"--dart-define=LUNAWAY_BASEMAP_URL={args.basemap}"] if args.basemap else []),
        f"--dart-define=LUNAWAY_TOUR_LOCALE={args.locale}",
        f"--dart-define=LUNAWAY_TOUR_THEME={args.theme}",
        f"--dart-define=LUNAWAY_TOUR_TAG={tag}",
        *[f"--dart-define={d}" for d in args.define],
    ]


def build_simulator(args):
    """The tour built as the app for the iOS simulator, its path. A
    simulator runs debug builds only."""
    cmd = ["fvm", "flutter", "build", "ios", "--simulator", "--debug", "-t", args.test, *tour_defines(args)]
    print(" ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)
    return os.path.join("build", "ios", "iphonesimulator", "Runner.app")


def follow(proc, timeout_s, alive):
    """The lines a tour launched as the app prints, until it says it is
    done, the app dies ([alive] turns false) or [timeout_s] runs out.
    Yields (line, None) and, once, (None, exit code). The lines are read
    by a thread: logcat and the simulator's log stay open after the app
    dies, and a read that waits for them would wait for ever."""
    lines = queue.Queue()

    def pump():
        for line in proc.stdout:
            lines.put(line)
        lines.put(None)

    threading.Thread(target=pump, daemon=True).start()
    end = time.time() + timeout_s
    checked = time.time()
    code = None
    try:
        while True:
            try:
                line = lines.get(timeout=5)
            except queue.Empty:
                line = ""
            if line is None:
                break
            if line:
                yield line, None
                if "TOUR DONE" in line:
                    code = 0 if "all scenes" in line else 1
                # The test framework's own last line: every test passed, or
                # one failed (without `flutter test` nobody else says it).
                if "All tests passed" in line:
                    code = 0 if code is None else code
                    break
                if "Some tests failed" in line or re.search(r"\+\d+ -\d+:", line):
                    code = 1
                    break
            if time.time() > end:
                print("the tour ran out of time", flush=True)
                code = 1
                break
            if time.time() - checked > 30:
                checked = time.time()
                if not alive():
                    print("the app is no longer running", flush=True)
                    code = 1
                    break
    finally:
        proc.terminate()
    yield None, 1 if code is None else code


def logcat_lines(ident, app_id, timeout_s):
    """The release build launched, its lines read from logcat."""
    subprocess.run(["adb", "-s", ident, "logcat", "-c"], check=False)
    subprocess.run(["adb", "-s", ident, "shell", "am", "start", "-W", "-n",
                    f"{app_id}/legal.p2p.lunaway.MainActivity"], check=True, capture_output=True)
    proc = subprocess.Popen(["adb", "-s", ident, "logcat", "-v", "raw", "-s", "flutter:I"],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    def alive():
        return subprocess.run(["adb", "-s", ident, "shell", "pidof", app_id], capture_output=True).returncode == 0

    try:
        yield from follow(proc, timeout_s, alive)
    finally:
        subprocess.run(["adb", "-s", ident, "shell", "am", "force-stop", app_id], check=False)


IOS_BUNDLE = "legal.p2p.lunaway"


def simulator_lines(ident, timeout_s):
    """The build installed on the simulator launched, its lines read from
    the simulator's log, where an iOS app's Dart prints go (`flutter: `);
    the stream starts first, so the first lines are not missed."""
    proc = subprocess.Popen(["xcrun", "simctl", "spawn", ident, "log", "stream", "--style", "compact",
                             "--level", "debug", "--predicate",
                             'process == "Runner" AND eventMessage BEGINSWITH "flutter: "'],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    time.sleep(2)
    subprocess.run(["xcrun", "simctl", "launch", "--terminate-running-process", ident, IOS_BUNDLE],
                   check=True, capture_output=True)
    def alive():
        listed = subprocess.run(["xcrun", "simctl", "spawn", ident, "launchctl", "list"], capture_output=True,
                                text=True).stdout
        return f"UIKitApplication:{IOS_BUNDLE}" in listed

    try:
        yield from follow(proc, timeout_s, alive)
    finally:
        subprocess.run(["xcrun", "simctl", "terminate", ident, IOS_BUNDLE], check=False, capture_output=True)


def simulator_position(ident, latlon):
    """The permission to locate given before the launch, since no test can
    answer the system's dialog, and the simulator placed at [latlon]."""
    subprocess.run(["xcrun", "simctl", "privacy", ident, "grant", "location", IOS_BUNDLE], check=False)
    if latlon:
        subprocess.run(["xcrun", "simctl", "location", ident, "set", latlon], check=False)


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
    p.add_argument("--location", help="LAT,LON given to the fused provider (Android) or the simulator for the run")
    p.add_argument("--fresh", action="store_true", help="start from an empty device")
    p.add_argument(
        "--basemap",
        help="base URL of another basemap host with the same layout (planet.json, fonts/, sprites/)",
    )
    p.add_argument("--release", action="store_true",
                   help="the tour built as the app and launched like it: a release build read from "
                        "logcat on Android, a debug build read from its console on the iOS simulator")
    p.add_argument("--app", help="with --release: the tour built before (an APK, a Runner.app), installed as it is")
    p.add_argument("--id-suffix",
                   help="Android: the application id's suffix of the build (.name); "
                        "ORG_GRADLE_PROJECT_testIdSuffix otherwise, .shots with --release")
    p.add_argument("--status", action="store_true", help="the store's status bar (full battery and signal, the clock of each shot) for the run")
    p.add_argument("--timeout", type=int, default=2400, help="with --release: seconds before giving up")
    p.add_argument("--tag", help="the prefix of the shots' names; <locale>-<size>-<theme> otherwise")
    args = p.parse_args()
    width, height = (int(v) for v in args.size.split("x"))
    args.out = os.path.abspath(args.out)
    os.makedirs(args.out, exist_ok=True)
    env = dict(os.environ, LUNAWAY_WINDOW=args.size, LUNAWAY_ALL_SPACES="1")
    kind, _, ident = args.device.partition(":")
    suffix = args.id_suffix or os.environ.get("ORG_GRADLE_PROJECT_testIdSuffix") or (
        ".shots" if args.release else "")
    args.app_id = "legal.p2p.lunaway" + suffix
    target = ["-d", "macos"] if kind == "macos" else ["-d", ident]
    if kind == "android":
        # flutter test uninstalls the app after an integration test, and with
        # it the data of whoever uses the device: the emulator is shared.
        target += ["--flavor", "store", "--no-uninstall"]
    elif kind == "ios":
        # The simulator keeps its places and packs from one run to the next.
        target += ["--no-uninstall"]
    cmd = ["fvm", "flutter", "test", args.test, *target, *tour_defines(args)]
    if args.app:
        print("--app: the tour runs with the language, theme, tag and API it was built with; "
              "--locale sets only the hours of the status bar", flush=True)
    if args.release and kind == "android":
        apk = args.app or build_release(args, suffix)
        subprocess.run(["adb", "-s", ident, "install", "-r", apk], check=True)
    if args.release and kind == "ios":
        app = args.app or build_simulator(args)
        subprocess.run(["xcrun", "simctl", "install", ident, app], check=True)
    if kind == "ios":
        simulator_position(ident, args.location)
    if kind == "android":
        adb = ["adb", "-s", ident, "shell", "wm"]
        subprocess.run(adb + ["size", args.size], check=True)
        if args.density:
            subprocess.run(adb + ["density", str(args.density)], check=True)
        if args.revoke_location:
            for perm in ("ACCESS_FINE_LOCATION", "ACCESS_COARSE_LOCATION"):
                subprocess.run(["adb", "-s", ident, "shell", "pm", "revoke", args.app_id,
                                f"android.permission.{perm}"], check=False, capture_output=True)
        if args.location:
            set_test_location(ident, args.location)
    # After the screen's size: set before, a tablet's bar draws its Wi-Fi
    # twice.
    if args.status:
        time.sleep(2)
        demo_status(kind, ident, on=True, locale=args.locale)
    try:
        if args.release and kind == "android":
            code = run(logcat_lines(ident, args.app_id, args.timeout), args, kind, height)
        elif args.release and kind == "ios":
            code = run(simulator_lines(ident, args.timeout), args, kind, height)
        else:
            code = run(lines_of(cmd, env), args, kind, height)
    finally:
        if args.status:
            demo_status(kind, ident, on=False, locale=args.locale)
        if kind == "android":
            subprocess.run(adb + ["size", "reset"], check=False)
            subprocess.run(adb + ["density", "reset"], check=False)
            if args.location:
                subprocess.run(["adb", "-s", ident, "shell", "cmd", "location", "providers",
                                "remove-test-provider", "fused"], check=False, capture_output=True)
        if kind == "ios" and args.location:
            subprocess.run(["xcrun", "simctl", "location", ident, "clear"], check=False)
        if kind == "ios" and args.release:
            # The permission given for the run goes: the app asks again.
            subprocess.run(["xcrun", "simctl", "privacy", ident, "reset", "location", IOS_BUNDLE], check=False)
    sys.exit(code)


def lines_of(cmd, env):
    """The lines `flutter test` prints, then its exit code, as
    [logcat_lines] gives them."""
    proc = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for line in proc.stdout:
        yield line, None
    yield None, proc.wait()


def run(lines, args, kind, height):
    frozen = []
    written = set()
    code = 1
    for line, done in lines:
        if line is None:
            code = done
            break
        # Flushed per line: the log of a long run is read while it runs.
        sys.stdout.write(line if line.endswith("\n") else line + "\n")
        sys.stdout.flush()
        # A tour that shows the device's position asks for it to be granted:
        # the install that `flutter test` makes starts without permissions.
        if kind == "android" and "GRANT LOCATION" in line:
            ident = args.device.partition(":")[2]
            for perm in ("ACCESS_FINE_LOCATION", "ACCESS_COARSE_LOCATION"):
                subprocess.run(["adb", "-s", ident, "shell", "pm", "grant", args.app_id,
                                f"android.permission.{perm}"], check=False)
            # A fresh fix too: the map greys a position that stopped coming.
            if args.location:
                set_test_location(ident, args.location)
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
        # A transcript the tour writes line by line (the sentences of a
        # guidance): emptied at its first line of the run.
        note = line.find("WRITE ")
        if note >= 0:
            name, _, text = line[note + 6:].rstrip("\n").partition(" ")
            if re.fullmatch(r"[A-Za-z0-9._-]+\.txt", name):
                with open(os.path.join(args.out, name), "a" if name in written else "w", encoding="utf-8") as f:
                    f.write(text + "\n")
                written.add(name)
            continue
        marker = line.find("SHOT ")
        if marker >= 0:
            name = line[marker + 5:].strip()
            if args.status:
                status_clock(kind, args.device.partition(":")[2], args.locale)
            time.sleep(0.4)
            path = os.path.join(args.out, f"{name}.png")
            if kind == "macos":
                capture(path, height)
            else:
                capture_device(args.device, path)
    if frozen:
        print(f"the map did not change on screen between {frozen}", flush=True)
        return code or 1
    return code


if __name__ == "__main__":
    main()
