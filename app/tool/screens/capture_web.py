"""Screenshots of the web build in a headless browser, over the Chrome
DevTools protocol: a phone, a tablet and a desktop viewport, a language and a
colour scheme, and the app's own links (`#/map?place=<id>`, `#/favorites`,
`#/profile`, `#/route?lat=..&lon=..` for a route preview) to reach each
screen. `--geo lat,lon` gives the browser a position, for the route's start.

    python3 tool/screens/capture_web.py --url http://127.0.0.1:18791/app/ --out ../plan/screenshots/web

Serve the web build first (`fvm flutter build web --base-href /app/
--dart-define=LUNAWAY_DEMO=true`, then any static server over a directory
whose `app/` is build/web). Uses Brave or Chrome with a profile of its own;
needs the `websockets` Python package.
"""

import argparse
import asyncio
import base64
import json
import os
import socket
import subprocess
import time
import urllib.parse
import urllib.request

BROWSERS = [
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
]
VIEWPORTS = {"phone": (412, 732, 2.625, True), "tablet": (800, 1280, 2, True), "desktop": (1440, 900, 2, False)}
PAGES = {
    "map": "#/map",
    "place": "#/map?place={place}",
    "poi": "#/map?poi={poi}",
    "route": "#/route?{route}",
    "offline-maps": "#/profile/offline-maps",
    "favorites": "#/favorites",
    "profile": "#/profile",
    # The account's pages, by their links (reached from the profile in the app).
    "recover": "#/profile/recover",
    "recovery-card": "#/profile/recovery-card",
    "contributions": "#/profile/contributions",
    "devices": "#/profile/devices",
    "muted": "#/profile/muted",
    "delete-account": "#/profile/delete-account",
}


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


async def shoot(ws_url, url, path, width, height, scale, mobile, lang, scheme, wait, console_dir, geo=None):
    import websockets

    async with websockets.connect(ws_url, max_size=100_000_000) as ws:
        ids = iter(range(1, 1_000_000))

        async def call(method, params=None):
            mid = next(ids)
            await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
            while True:
                msg = json.loads(await ws.recv())
                if msg.get("id") == mid:
                    return msg.get("result", {})

        await call("Emulation.setDeviceMetricsOverride", {
            "width": width, "height": height, "deviceScaleFactor": scale, "mobile": mobile,
        })
        await call("Emulation.setLocaleOverride", {"locale": lang})
        await call("Emulation.setEmulatedMedia", {"features": [{"name": "prefers-color-scheme", "value": scheme}]})
        if geo:
            lat, lon = geo
            await call("Browser.grantPermissions", {"permissions": ["geolocation"]})
            await call("Emulation.setGeolocationOverride", {"latitude": lat, "longitude": lon, "accuracy": 10})
        await call("Network.enable")
        await call("Network.setExtraHTTPHeaders", {"headers": {"Accept-Language": lang}})
        await call("Runtime.enable")
        await call("Log.enable")
        await call("Page.enable")
        # Flutter takes the device language from navigator.languages, which the
        # locale override leaves alone.
        await call("Page.addScriptToEvaluateOnNewDocument", {"source": (
            f"Object.defineProperty(navigator, 'language', {{get: () => '{lang}'}});"
            f"Object.defineProperty(navigator, 'languages', {{get: () => ['{lang}']}});"
        )})
        # A blank page first: a change of the #fragment alone would not reload
        # the app, which would keep the language, theme and selection of the
        # previous shot.
        await call("Page.navigate", {"url": "about:blank"})
        await asyncio.sleep(0.3)
        await call("Page.navigate", {"url": url})
        # Collect the console while the page settles, for diagnosis.
        lines = []
        end = time.monotonic() + wait
        while time.monotonic() < end:
            try:
                msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=max(0.1, end - time.monotonic())))
            except asyncio.TimeoutError:
                break
            method = msg.get("method", "")
            if method == "Runtime.consoleAPICalled":
                lines.append(" ".join(str(a.get("value", a.get("description", ""))) for a in msg["params"]["args"]))
            elif method == "Log.entryAdded":
                lines.append(f"{msg['params']['entry']['level']}: {msg['params']['entry']['text']}")
            elif method == "Runtime.exceptionThrown":
                lines.append("exception: " + str(msg["params"]["exceptionDetails"].get("exception", {}).get("description", ""))[:1500])
        with open(os.path.join(console_dir, os.path.basename(path) + ".console.txt"), "w") as f:
            f.write("\n".join(lines))
        shot = await call("Page.captureScreenshot", {"format": "png"})
        with open(path, "wb") as f:
            f.write(base64.b64decode(shot["data"]))
        print(f"captured {path}", flush=True)


async def recover(ws_url, base_url, code, out):
    """Brings the account of [code] into the browser profile, as a person
    would: the recovery page, the code typed into its field, the keyboard's
    go key. The key then stays in the profile's IndexedDB for the shots."""
    import websockets

    async with websockets.connect(ws_url, max_size=100_000_000) as ws:
        ids = iter(range(1, 1_000_000))

        async def call(method, params=None):
            mid = next(ids)
            await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
            while True:
                msg = json.loads(await ws.recv())
                if msg.get("id") == mid:
                    return msg.get("result", {})

        width, height, scale, mobile = VIEWPORTS["phone"]
        await call("Emulation.setDeviceMetricsOverride", {
            "width": width, "height": height, "deviceScaleFactor": scale, "mobile": mobile,
        })
        await call("Page.enable")
        await call("Page.navigate", {"url": "about:blank"})
        await asyncio.sleep(0.3)
        await call("Page.navigate", {"url": base_url + PAGES["recover"]})
        await asyncio.sleep(12)
        # The code field sits under the page title and its two lines of
        # introduction, across the width of the phone.
        for kind in ("mousePressed", "mouseReleased"):
            await call("Input.dispatchMouseEvent", {
                "type": kind, "x": width / 2, "y": 160, "button": "left", "clickCount": 1,
            })
        await asyncio.sleep(1)
        await call("Input.insertText", {"text": code})
        await asyncio.sleep(1)
        for kind in ("keyDown", "keyUp"):
            await call("Input.dispatchKeyEvent", {
                "type": kind, "key": "Enter", "code": "Enter", "windowsVirtualKeyCode": 13,
            })
        await asyncio.sleep(8)
        shot = await call("Page.captureScreenshot", {"format": "png"})
        with open(os.path.join(out, "recover-step.png"), "wb") as f:
            f.write(base64.b64decode(shot["data"]))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--url", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--place", default="demo-0002")
    p.add_argument("--poi", default="", help="a point of interest to open (the poi page)")
    p.add_argument("--route", default="45.845089,1.286339,Rue Maurice Utrillo",
                   help="lat,lon,name of the destination of the route page")
    p.add_argument("--geo", help="lat,lon: the browser's position")
    p.add_argument("--wait", type=float, default=12)
    p.add_argument("--langs", default="fr,en")
    p.add_argument("--schemes", default="light,dark")
    p.add_argument("--viewports", default=",".join(VIEWPORTS))
    p.add_argument("--pages", default=",".join(PAGES))
    p.add_argument("--recover", help="a recovery code to bring its account into the profile first")
    p.add_argument("--profile", default="web-capture-browser",
                   help="browser profile directory under data/tmp; a new name starts from an empty store")
    args = p.parse_args()
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    lat, lon, name = args.route.split(",", 2)
    route = urllib.parse.urlencode({"lat": lat, "lon": lon, "name": name})
    geo = tuple(float(v) for v in args.geo.split(",")) if args.geo else None
    browser = next(b for b in BROWSERS if os.path.exists(b))
    port = free_port()
    # A profile of its own, kept between runs (the demo store lives in it).
    tmp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "data", "tmp")
    profile = os.path.join(tmp, args.profile)
    # The browser console of every shot, for diagnosis, out of the image folder.
    console_dir = os.path.join(tmp, "web-console")
    os.makedirs(console_dir, exist_ok=True)
    proc = subprocess.Popen(
        [browser, "--headless=new", f"--remote-debugging-port={port}", f"--user-data-dir={profile}",
         "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--no-first-run", "--disable-extensions",
         "--hide-scrollbars", "about:blank"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(100):
            try:
                tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json"))
                break
            except OSError:
                time.sleep(0.2)
        page = next(t for t in tabs if t["type"] == "page")["webSocketDebuggerUrl"]
        if args.recover:
            asyncio.run(recover(page, args.url, args.recover, out))
        for lang in args.langs.split(","):
            for scheme in args.schemes.split(","):
                for vp in args.viewports.split(","):
                    w, h, scale, mobile = VIEWPORTS[vp]
                    for name in args.pages.split(","):
                        frag = PAGES[name]
                        url = args.url + frag.format(place=args.place, poi=args.poi, route=route)
                        path = os.path.join(out, f"{lang}-{vp}-{scheme}-{name}.png")
                        asyncio.run(shoot(page, url, path, w, h, scale, mobile, lang, scheme, args.wait, console_dir, geo))
    finally:
        proc.terminate()
        proc.wait(timeout=10)


if __name__ == "__main__":
    main()
