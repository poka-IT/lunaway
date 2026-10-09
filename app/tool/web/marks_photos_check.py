"""Checks, in real browsers, that the route maps of the web app draw their
places' photos: the route preview from Viviers to Le Teil (Ardèche), then
a guidance along it with a simulated position.

    # production
    python3 tool/web/marks_photos_check.py --url https://lunaway.net/app/
    # a local build, served the way production serves it
    sh packages/lunaway_nav/tool/build_web.sh
    fvm flutter build web --release --wasm --base-href /app/ --no-web-resources-cdn \\
        --dart-define=LUNAWAY_API_URL=http://127.0.0.1:18793
    python3 tool/web/marks_photos_check.py --serve build/web --api https://api.lunaway.net/graphql

--serve starts serve_csp.py on --port, which must be the port baked into
LUNAWAY_API_URL. Chromium, Firefox and WebKit by default (--browser for one).
For each, it records the GraphQL requests, the photos the API names in its
`PlaceThumbs` answers and every request for a photo, then fails when:

  - the API names a photo on another address than the one the app asks
    its GraphQL from: the app refuses to fetch it (`ImageFetcher.accepts`)
    and the mark stays a pictogram, without any request for the photo;
  - no photo is asked for, or none is answered with an image, on the
    preview or during the guidance.

Screenshots and the log of each browser go to --out. Needs Playwright for
Python and its browsers (`pip install playwright`, `playwright install`).
"""

import argparse
import asyncio
import json
import math
import os
import re
import sys
import threading
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import serve_csp  # noqa: E402

START = (44.4826, 4.6888)  # Viviers
DEST = (44.5455, 4.6827)  # Le Teil
STEP_M = 14.0  # a fix a second: about 50 km/h
PHOTO_PATH = re.compile(r"/(media|external-photos)/")


def decode6(s):
    """A polyline with six decimals, as the route's OSRM answer carries it."""
    coords, i, lat, lon = [], 0, 0, 0
    while i < len(s):
        for which in (0, 1):
            shift = result = 0
            while True:
                b = ord(s[i]) - 63
                i += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            d = ~(result >> 1) if result & 1 else result >> 1
            if which == 0:
                lat += d
            else:
                lon += d
        coords.append((lat / 1e6, lon / 1e6))
    return coords


def along(line, m):
    """The point [m] metres along [line]."""
    for a, b in zip(line, line[1:]):
        p1, p2 = math.radians(a[0]), math.radians(b[0])
        h = (math.sin((p2 - p1) / 2) ** 2
             + math.cos(p1) * math.cos(p2) * math.sin(math.radians(b[1] - a[1]) / 2) ** 2)
        d = 2 * 6371000.0 * math.asin(math.sqrt(h))
        if m <= d and d > 0:
            f = m / d
            return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
        m -= d
    return line[-1]


def origin(url):
    u = urllib.parse.urlsplit(url)
    return f"{u.scheme}://{u.netloc}"


async def check(p, browser_name, base, out):
    """The failures of one browser, empty when its marks drew photos."""
    lines = []
    t0 = time.time()

    def log(*parts):
        lines.append(f"[{time.time() - t0:6.1f}] " + " ".join(str(x) for x in parts))

    state = {"line": None, "m": 0.0, "moving": False, "phase": "preview",
             "graphql": set(), "named": set(), "asked": {"preview": 0, "guidance": 0},
             "images": {"preview": 0, "guidance": 0}}
    browser = await getattr(p, browser_name).launch(headless=True)
    ctx = await browser.new_context(
        viewport={"width": 1280, "height": 800},
        locale="fr-FR",
        geolocation={"latitude": START[0], "longitude": START[1], "accuracy": 5},
    )
    await ctx.grant_permissions(["geolocation"])
    page = await ctx.new_page()
    page.on("console", lambda m: m.type == "error" and log("console", m.text[:240]))
    page.on("pageerror", lambda e: log("pageerror", str(e)[:240]))

    def on_request(req):
        if req.method == "POST" and req.url.endswith("/graphql"):
            state["graphql"].add(origin(req.url))
        elif PHOTO_PATH.search(urllib.parse.urlsplit(req.url).path):
            state["asked"][state["phase"]] += 1
            log("photo asked", req.url)

    async def on_response(resp):
        url = resp.url
        if PHOTO_PATH.search(urllib.parse.urlsplit(url).path):
            kind = (await resp.all_headers()).get("content-type", "")
            if resp.status == 200 and kind.startswith("image/"):
                state["images"][state["phase"]] += 1
            log("photo answered", resp.status, kind, url)
            return
        if not (url.endswith("/graphql") and resp.request.method == "POST"):
            return
        try:
            body = await resp.json()
        except Exception:
            return
        data = body.get("data") if isinstance(body, dict) else None
        if not isinstance(data, dict):
            return
        for value in data.values():
            if isinstance(value, dict):
                for photo in (value.get("externalPhotos") or []) + (value.get("coverPhotos") or []):
                    if photo.get("thumbUrl"):
                        state["named"].add(photo["thumbUrl"])
        route = data.get("route")
        if route and route.get("osrmJson") and state["line"] is None:
            state["line"] = decode6(json.loads(route["osrmJson"])["routes"][0]["geometry"])

    page.on("request", on_request)
    page.on("response", lambda r: asyncio.ensure_future(on_response(r)))

    async def mover():
        while True:
            await asyncio.sleep(1.0)
            if state["moving"] and state["line"]:
                state["m"] += STEP_M
                lat, lon = along(state["line"], state["m"])
                await ctx.set_geolocation({"latitude": lat, "longitude": lon, "accuracy": 5})

    async def find(pattern):
        nodes = await page.evaluate(
            """() => [...document.querySelectorAll('flt-semantics')].map(el => {
              const r = el.getBoundingClientRect();
              const label = ((el.getAttribute('aria-label') || '') + ' ' +
                (el.childElementCount === 0 ? el.textContent : '')).trim();
              return {label, x: r.x + r.width / 2, y: r.y + r.height / 2, w: r.width};
            }).filter(n => n.label && n.w > 0)"""
        )
        rx = re.compile(pattern, re.I)
        return next((n for n in nodes if rx.search(n["label"])), None)

    async def click(pattern, timeout=60):
        for _ in range(timeout * 2):
            n = await find(pattern)
            if n:
                await page.mouse.click(n["x"], n["y"])
                return
            await asyncio.sleep(0.5)
        raise RuntimeError(f"nothing named {pattern!r} on the page")

    async def wait_photos(phase, seconds):
        for _ in range(seconds * 2):
            if state["images"][phase]:
                return
            await asyncio.sleep(0.5)

    moving = asyncio.ensure_future(mover())
    failures = []
    try:
        await page.goto(base + f"#/route?lat={DEST[0]}&lon={DEST[1]}&name=Le%20Teil")
        await page.wait_for_selector("flutter-view", timeout=90000)
        await asyncio.sleep(5)
        await page.evaluate("document.querySelector('flt-semantics-placeholder')?.click()")
        await asyncio.sleep(2)
        if await find("Décrire mon véhicule"):
            await click("Décrire mon véhicule")
            await asyncio.sleep(2)
            await click("^Enregistrer")
        # The route is there once its button is.
        for _ in range(180):
            if await find("C'est parti"):
                break
            await asyncio.sleep(0.5)
        await wait_photos("preview", 30)
        # The marks are drawn a moment after their photo came.
        await asyncio.sleep(3)
        await page.screenshot(path=os.path.join(out, f"{browser_name}-apercu.png"))
        state["phase"] = "guidance"
        await click("C'est parti")
        await asyncio.sleep(2)
        if await find("J'ai compris"):
            await click("J'ai compris")
        state["moving"] = True
        await wait_photos("guidance", 40)
        await asyncio.sleep(3)
        await page.screenshot(path=os.path.join(out, f"{browser_name}-guidage.png"))
    except Exception as e:  # noqa: BLE001 - reported as a failure of this browser
        failures.append(f"the tour stopped: {e}")
    finally:
        moving.cancel()
        await browser.close()

    asked_from = sorted(state["graphql"])
    for url in sorted(state["named"]):
        if origin(url) not in state["graphql"]:
            failures.append(f"the API names {url}, the app asks its GraphQL from {asked_from}: it refuses that photo")
            break
    if not state["named"]:
        failures.append("no PlaceThumbs answer named a photo")
    for phase in ("preview", "guidance"):
        if not state["asked"][phase]:
            failures.append(f"{phase}: no photo asked for")
        elif not state["images"][phase]:
            failures.append(f"{phase}: no photo answered with an image")
    log("summary", json.dumps({"asked": state["asked"], "images": state["images"],
                               "named": len(state["named"]), "graphql": asked_from}))
    with open(os.path.join(out, f"{browser_name}-log.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines + [f"FAIL {x}" for x in failures]) + "\n")
    return failures


async def run(args):
    from playwright.async_api import async_playwright

    os.makedirs(args.out, exist_ok=True)
    browsers = ["chromium", "firefox", "webkit"] if args.browser == "all" else [args.browser]
    failed = False
    async with async_playwright() as p:
        for name in browsers:
            failures = await check(p, name, args.url, args.out)
            print(f"{name}: {'ok' if not failures else 'FAILED'}")
            for f in failures:
                print(f"  {f}")
            failed = failed or bool(failures)
    return 1 if failed else 0


def main():
    a = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    a.add_argument("--url", help="the app's address, ending in /app/")
    a.add_argument("--serve", help="a web build to serve with serve_csp.py instead")
    a.add_argument("--port", type=int, default=18793)
    a.add_argument("--api", default="https://api.lunaway.net/graphql", help="the GraphQL endpoint --serve forwards to")
    a.add_argument("--browser", default="all", choices=["all", "chromium", "firefox", "webkit"])
    a.add_argument("--out", default=os.path.join(serve_csp.REPO, "data", "tmp", "marks-photos"))
    args = a.parse_args()
    if bool(args.url) == bool(args.serve):
        a.error("give --url or --serve")
    server = None
    if args.serve:
        server = serve_csp.make_server(args.port, args.serve, api=args.api)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        args.url = f"http://127.0.0.1:{args.port}/app/"
    try:
        return asyncio.run(run(args))
    finally:
        if server:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    sys.exit(main())
