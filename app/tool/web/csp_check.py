"""Loads the web build in a headless browser under the production headers and
fails on anything the Content-Security-Policy refuses.

    sh packages/lunaway_nav/tool/build_web.sh
    fvm flutter build web --release --base-href /app/ --no-web-resources-cdn \\
        --dart-define=LUNAWAY_API_URL=http://127.0.0.1:18793
    python3 tool/web/csp_check.py --api https://api.lunaway.net/graphql --out ../plan/screenshots/web-csp

Starts serve_csp.py (headers parsed from infra/caddy/lunaway.net.caddy) on
--port, which must be the port baked into LUNAWAY_API_URL, and a headless Brave or
Chrome of its own (fresh profile under data/tmp/, its own debugging port).
Over the DevTools protocol, on the page and on every worker it starts, it
records the console, every network request and every CSP violation (the
securitypolicyviolation event, security log entries, Audits issues, requests
blocked for "csp"). Then it checks:

  - no CSP violation at all;
  - the loading screen is gone and the Flutter view is in the page;
  - a click on the "Favourites" destination changes the screen;
  - no request leaves for a host the CSP does not name (fonts.gstatic.com
    included), and Roboto, the engine's default text fallback, comes from
    the app's own origin;
  - text typed in the search field with Greek, Cyrillic, extended Latin,
    symbols and emoji loads its fallback fonts from /app/fonts/ and the
    engine reports no missing glyph.

Screenshots and a report go to --out. Exits 1 on a failed check. Needs the
`websockets` Python package.
"""

import argparse
import asyncio
import base64
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import serve_csp  # noqa: E402

REPO = serve_csp.REPO
TMP = os.path.join(REPO, "data", "tmp")
BROWSERS = [
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
]
# Characters missing from Atkinson Hyperlegible Next and Roboto, so the web
# engine has to fetch Noto Sans (polytonic Greek, Latin Extended-B) and the
# Noto symbol fonts; the rest checks the fonts already loaded.
GLYPHS = "Ἀθῆναι Ǥ ẞ Ştefan Łódź Пловдив Þingvellir → ★ ✓ 🚐 ⛺ 😀"
FONT_WARNINGS = ("Could not find a set of Noto fonts", "Failed to parse font data", "permanently unavailable",
                 "Failed to load font")

# Recorded in every document before its own scripts run: the CSP violations
# the page sees, and the moment Flutter draws its first frame.
PROBE = """
window.__csp = [];
document.addEventListener('securitypolicyviolation', function (e) {
  window.__csp.push({directive: e.violatedDirective, blocked: e.blockedURI,
                     source: e.sourceFile, line: e.lineNumber, sample: e.sample});
});
window.addEventListener('flutter-first-frame', function () { window.__firstFrame = Date.now(); });
"""


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def csp_hosts(csp):
    """Origins (scheme://host) named anywhere in the policy."""
    hosts = set()
    for directive in csp.split(";"):
        for source in directive.split()[1:]:
            if "://" in source:
                parsed = urllib.parse.urlsplit(source)
                hosts.add(f"{parsed.scheme}://{parsed.netloc}")
    return hosts


class Cdp:
    """A DevTools client over one browser connection, with flattened sessions."""

    def __init__(self, ws):
        self.ws = ws
        self.ids = iter(range(1, 10_000_000))
        self.pending = {}
        self.handlers = []

    async def reader(self):
        async for raw in self.ws:
            msg = json.loads(raw)
            if "id" in msg:
                future = self.pending.pop(msg["id"], None)
                if future and not future.done():
                    future.set_result(msg)
            else:
                # Handlers run in the reader and must not wait on a reply,
                # which only this loop can deliver.
                for handler in self.handlers:
                    handler(msg)

    async def call(self, method, params=None, session=None, check=True):
        mid = next(self.ids)
        future = asyncio.get_running_loop().create_future()
        self.pending[mid] = future
        message = {"id": mid, "method": method, "params": params or {}}
        if session:
            message["sessionId"] = session
        await self.ws.send(json.dumps(message))
        msg = await asyncio.wait_for(future, timeout=60)
        if "error" in msg and check:
            raise RuntimeError(f"{method}: {msg['error']}")
        return msg.get("result", {})


class Recorder:
    def __init__(self, cdp):
        self.cdp = cdp
        self.requests = {}
        self.order = []
        self.console = []
        self.violations = []
        self.attached = set()

    def on_event(self, msg):
        method = msg.get("method", "")
        p = msg.get("params", {})
        session = msg.get("sessionId", "")
        if method == "Target.attachedToTarget":
            info = p["targetInfo"]
            # The page is set up by run() before it navigates; workers here.
            if info["type"] != "page" and info["targetId"] not in self.attached:
                self.attached.add(info["targetId"])
                asyncio.ensure_future(self.attach(p["sessionId"], info))
        elif method == "Target.targetCreated":
            info = p["targetInfo"]
            if info["type"] in ("shared_worker", "service_worker") and info["targetId"] not in self.attached:
                asyncio.ensure_future(self.cdp.call("Target.attachToTarget",
                                                    {"targetId": info["targetId"], "flatten": True}, check=False))
        elif method == "Network.requestWillBeSent":
            key = (session, p["requestId"])
            if key not in self.requests:
                self.order.append(key)
            self.requests[key] = {"url": p["request"]["url"], "method": p["request"]["method"],
                                  "type": p.get("type", ""), "status": None, "mime": None, "failed": None}
        elif method == "Network.responseReceived":
            r = self.requests.get((session, p["requestId"]))
            if r:
                r["status"], r["mime"] = p["response"]["status"], p["response"].get("mimeType")
        elif method == "Network.loadingFailed":
            r = self.requests.get((session, p["requestId"]))
            if r:
                r["failed"] = p.get("blockedReason") or p.get("errorText")
                if p.get("blockedReason") == "csp":
                    self.violations.append(f"request blocked by CSP: {r['url']}")
        elif method == "Log.entryAdded":
            e = p["entry"]
            self.console.append(f"[log {e['source']} {e['level']}] {e['text']}")
            if e["source"] == "security" or "Content Security Policy" in e["text"]:
                self.violations.append(f"log: {e['text']}")
        elif method == "Runtime.consoleAPICalled":
            text = " ".join(str(a.get("value", a.get("description", ""))) for a in p["args"])
            self.console.append(f"[console {p['type']}] {text}")
            if "Content Security Policy" in text:
                self.violations.append(f"console: {text}")
        elif method == "Runtime.exceptionThrown":
            d = p["exceptionDetails"]
            self.console.append(f"[exception] {d.get('exception', {}).get('description', d.get('text'))}"[:2000])
        elif method == "Audits.issueAdded":
            issue = p["issue"]
            if issue.get("code") == "ContentSecurityPolicyIssue":
                details = issue.get("details", {}).get("contentSecurityPolicyIssueDetails", {})
                self.violations.append(f"audit: {details.get('violatedDirective')} {details.get('blockedURL', '')}")

    async def attach(self, session, info):
        """Enables the recording domains on a page or worker and lets it run."""
        self.attached.add(info["targetId"])
        for method in ("Network.enable", "Log.enable", "Runtime.enable"):
            await self.cdp.call(method, session=session, check=False)
        if info["type"] == "page":
            await self.cdp.call("Audits.enable", session=session, check=False)
        await self.cdp.call("Target.setAutoAttach", {"autoAttach": True, "waitForDebuggerOnStart": True, "flatten": True},
                            session=session, check=False)
        await self.cdp.call("Runtime.runIfWaitingForDebugger", session=session, check=False)


async def run(args, origin, csp):
    import websockets

    version = json.load(urllib.request.urlopen(f"http://127.0.0.1:{args.debug_port}/json/version"))
    async with websockets.connect(version["webSocketDebuggerUrl"], max_size=200_000_000) as ws:
        cdp = Cdp(ws)
        rec = Recorder(cdp)
        cdp.handlers.append(rec.on_event)
        reader = asyncio.ensure_future(cdp.reader())
        await cdp.call("Target.setDiscoverTargets", {"discover": True})
        target = await cdp.call("Target.createTarget", {"url": "about:blank"})
        session = (await cdp.call("Target.attachToTarget", {"targetId": target["targetId"], "flatten": True}))["sessionId"]
        await rec.attach(session, {"targetId": target["targetId"], "type": "page"})

        async def page(method, params=None):
            return await cdp.call(method, params, session=session)

        async def js(expression):
            result = await page("Runtime.evaluate", {"expression": expression, "returnByValue": True, "awaitPromise": True})
            return result.get("result", {}).get("value")

        async def shot(name):
            data = (await page("Page.captureScreenshot", {"format": "png"}))["data"]
            path = os.path.join(args.out, name)
            with open(path, "wb") as f:
                f.write(base64.b64decode(data))
            return data

        async def click(x, y):
            await page("Input.dispatchMouseEvent", {"type": "mouseMoved", "x": x, "y": y})
            await page("Input.dispatchMouseEvent", {"type": "mousePressed", "x": x, "y": y, "button": "left", "clickCount": 1})
            await page("Input.dispatchMouseEvent", {"type": "mouseReleased", "x": x, "y": y, "button": "left", "clickCount": 1})

        async def find(pattern):
            """Centre of the first semantics node whose label matches."""
            return await js(f"""(() => {{
              const re = new RegExp({json.dumps(pattern)}, 'i');
              for (const el of document.querySelectorAll('flt-semantics, flt-semantics input, flt-semantics textarea')) {{
                const label = (el.getAttribute('aria-label') || '') + ' ' + (el.getAttribute('placeholder') || '')
                  + ' ' + (el.childElementCount === 0 ? el.textContent : '');
                const r = el.getBoundingClientRect();
                if (re.test(label) && r.width > 0 && r.height > 0) return [r.x + r.width / 2, r.y + r.height / 2, label.trim()];
              }}
              return null;
            }})()""")

        await page("Page.enable")
        await page("Emulation.setDeviceMetricsOverride", {"width": 1440, "height": 900, "deviceScaleFactor": 1, "mobile": False})
        await page("Emulation.setLocaleOverride", {"locale": args.lang})
        await page("Page.addScriptToEvaluateOnNewDocument", {"source": PROBE + (
            f"Object.defineProperty(navigator, 'language', {{get: () => '{args.lang}'}});"
            f"Object.defineProperty(navigator, 'languages', {{get: () => ['{args.lang}']}});")})
        await page("Page.navigate", {"url": f"{origin}/app/"})

        failures, notes = [], []
        deadline = time.monotonic() + args.timeout
        state = None
        while time.monotonic() < deadline:
            state = await js("({view: !!document.querySelector('flutter-view'), splash: !!document.getElementById('splash'),"
                             " firstFrame: window.__firstFrame || null, hash: location.hash})")
            if state and state["view"] and not state["splash"]:
                break
            await asyncio.sleep(0.5)
        notes.append(f"after load: {state}")
        if not state or not state["view"]:
            failures.append("no <flutter-view> in the page: the app did not start")
        if not state or state["splash"]:
            failures.append("the loading screen (#splash) is still in the page")
        await asyncio.sleep(args.settle)
        first = await shot("1-start.png")

        # Semantics give each destination a DOM node with its label and box.
        await js("document.querySelector('flt-semantics-placeholder')?.click()")
        await asyncio.sleep(1.5)
        before = await js("location.hash")
        target_nav = await find(args.nav_label)
        if not target_nav:
            failures.append(f"no navigation destination labelled /{args.nav_label}/ in the semantics tree")
        else:
            await click(target_nav[0], target_nav[1])
            await asyncio.sleep(2.5)
            after = await js("location.hash")
            second = await shot("2-after-nav-click.png")
            notes.append(f"clicked {target_nav[2]!r} at ({target_nav[0]:.0f}, {target_nav[1]:.0f}): hash {before!r} -> {after!r}")
            if after == before:
                failures.append(f"a click on {target_nav[2]!r} left the route at {before!r}")
            if second == first:
                failures.append("the screen did not change after the navigation click")

        # Back to the map, then type uncommon glyphs into the search field.
        home = await find(args.home_label)
        if home:
            await click(home[0], home[1])
            await asyncio.sleep(2.5)
        field = await find(args.search_label)
        fonts_before = len(rec.order)
        if not field:
            failures.append(f"no search field labelled /{args.search_label}/ in the semantics tree")
        else:
            await click(field[0], field[1])
            await asyncio.sleep(1)
            await page("Input.insertText", {"text": GLYPHS})
            await asyncio.sleep(args.settle)
            await shot("3-uncommon-glyphs.png")
            typed = await js("Array.from(document.querySelectorAll('input, textarea')).map(e => e.value).join(' | ')")
            notes.append(f"text fields now hold: {typed!r}")
            if GLYPHS not in (typed or ""):
                failures.append("the glyph sample did not reach the search field")

        rec.violations.extend(f"page: {v}" for v in (await js("window.__csp") or []))
        await asyncio.sleep(0.5)
        reader.cancel()

    # Every check below reads what the browser recorded.
    allowed = csp_hosts(csp) | {origin}
    outside, fonts = [], []
    for key in rec.order:
        r = rec.requests[key]
        parts = urllib.parse.urlsplit(r["url"])
        if parts.scheme in ("data", "blob", "about", "chrome-extension", "devtools"):
            continue
        host = f"{parts.scheme}://{parts.netloc}"
        if host not in allowed:
            outside.append(r["url"])
        if "/app/fonts/" in r["url"]:
            fonts.append(r)
    if rec.violations:
        failures.append(f"{len(rec.violations)} CSP violation(s)")
    if outside:
        failures.append(f"{len(outside)} request(s) to hosts the CSP does not name: " + ", ".join(sorted(set(outside))[:10]))
    # The engine's default fallback: bundled as assets/fonts/fallback/ by a
    # --no-web-resources-cdn build, fetched from fontFallbackBaseUrl otherwise.
    roboto = [rec.requests[k] for k in rec.order if "roboto" in rec.requests[k]["url"].lower()]
    if not roboto or any(not r["url"].startswith(origin + "/app/") or r["status"] != 200 for r in roboto):
        failures.append(f"Roboto did not come from the app's own origin: {roboto}")
    noto = [r for r in fonts if "/fonts/noto" in r["url"]]
    if field and not noto:
        failures.append("typing the glyph sample fetched no Noto font from /app/fonts/")
    for r in noto:
        if r["status"] != 200 or r["mime"] != "font/woff2":
            failures.append(f"fallback font not served: {r['url']} ({r['status']} {r['mime']} {r['failed']})")
    font_warnings = [line for line in rec.console if any(w in line for w in FONT_WARNINGS)]
    if font_warnings:
        failures.append(f"{len(font_warnings)} font warning(s) in the console")

    report = [f"origin {origin}", f"CSP {csp}", ""] + notes + ["", "CSP violations:"]
    report += [f"  {v}" for v in rec.violations] or ["  none"]
    report += ["", "requests:"]
    for key in rec.order:
        r = rec.requests[key]
        report.append(f"  {r['status'] or '-'} {r['method']} {r['type']} {r['url'][:160]}"
                      + (f"  FAILED {r['failed']}" if r["failed"] else ""))
    report += ["", f"fonts fetched after typing the sample: {[r['url'] for r in noto]}", "", "console:"]
    report += [f"  {line[:400]}" for line in rec.console]
    report += ["", "result: " + ("FAIL" if failures else "PASS")] + [f"  - {f}" for f in failures]
    with open(os.path.join(args.out, "report.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(report) + "\n")
    hosts = {}
    for key in rec.order:
        h = urllib.parse.urlsplit(rec.requests[key]["url"]).netloc or urllib.parse.urlsplit(rec.requests[key]["url"]).scheme
        hosts[h] = hosts.get(h, 0) + 1
    print("\n".join(notes))
    print(f"requests by host: {hosts}")
    print(f"CSP violations: {len(rec.violations)}")
    for v in rec.violations[:20]:
        print(f"  {v}")
    print(f"fallback fonts: {[(r['url'].split('/app/')[1], r['status']) for r in fonts]}")
    print(f"report and screenshots: {args.out}")
    return failures


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--port", type=int, default=18793, help="the port baked into LUNAWAY_API_URL at build time")
    p.add_argument("--api", default="https://api.lunaway.net/graphql", help="GraphQL endpoint the test server forwards to")
    p.add_argument("--root", default=serve_csp.DEFAULT_ROOT)
    p.add_argument("--caddyfile", default=serve_csp.DEFAULT_CADDYFILE)
    p.add_argument("--out", default=os.path.join(REPO, "plan", "screenshots", "web-csp"))
    p.add_argument("--lang", default="fr")
    p.add_argument("--nav-label", default="^\\s*(Favoris|Favourites|Favorites)\\b")
    p.add_argument("--home-label", default="^\\s*(Carte|Map)\\b")
    p.add_argument("--search-label", default="Un lieu, une commune|A place, a town")
    p.add_argument("--timeout", type=float, default=90, help="seconds to wait for the first frame")
    p.add_argument("--settle", type=float, default=8, help="seconds to let the app work after each step")
    args = p.parse_args()
    args.out = os.path.abspath(args.out)
    os.makedirs(args.out, exist_ok=True)
    os.makedirs(TMP, exist_ok=True)

    server = serve_csp.make_server(args.port, args.root, args.caddyfile, args.api)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    origin = f"http://127.0.0.1:{args.port}"

    browser = next((b for b in BROWSERS if os.path.exists(b)), None)
    if not browser:
        raise SystemExit("csp_check: no Brave, Chrome or Chromium found")
    # A fresh profile per run: nothing cached, nothing from a previous build.
    profile = tempfile.mkdtemp(prefix="csp-check-", dir=TMP)
    args.debug_port = free_port()
    proc = subprocess.Popen(
        [browser, "--headless=new", f"--remote-debugging-port={args.debug_port}", f"--user-data-dir={profile}",
         "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--no-first-run", "--no-default-browser-check",
         "--disable-extensions", "--disable-component-update", "--hide-scrollbars", "about:blank"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    failures = ["the check did not run"]
    try:
        for _ in range(150):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{args.debug_port}/json/version", timeout=1)
                break
            except OSError:
                time.sleep(0.2)
        failures = asyncio.run(run(args, origin, server.route.csp))
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            proc.kill()
        server.shutdown()
        server.server_close()
        # Only the profile this run created, and only inside data/tmp/.
        real = os.path.realpath(profile)
        if os.path.dirname(real) == os.path.realpath(TMP) and os.path.basename(real).startswith("csp-check-"):
            shutil.rmtree(real, ignore_errors=True)
    if failures:
        print("csp_check: FAIL")
        for f in failures:
            print(f"  - {f}")
        sys.exit(1)
    print("csp_check: PASS")


if __name__ == "__main__":
    main()
