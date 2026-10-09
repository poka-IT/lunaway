"""An integration tour in a browser, captured as capture.py captures it on a
device: the web build of the tour, served on 127.0.0.1 with the API's paths
forwarded to the API on the same origin (the production API answers the
pages of lunaway.net only, a page of 127.0.0.1 gets no CORS headers), opened
in Playwright's Chromium at a viewport, a screenshot at each `SHOT <name>`
line of the console, a `WRITE <name>.txt <text>` line appended to that file.

    python3 tool/screens/tour_web.py --test integration_test/radars_real_tour_test.dart \
        --viewport 412x732 --locale fr --out ../plan/screenshots/radars \
        --define LUNAWAY_RADARS_SCENARIO=es

Run from app/, after `sh packages/lunaway_nav/tool/build_web.sh` (the
guidance library). Builds the tour in profile mode into build/web-tour/
unless `--no-build`. Needs the `playwright` Python package and its
Chromium. The forwarded requests carry the app's User-Agent.
"""

import argparse
import http.server
import os
import queue
import re
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

FORWARD = ("/graphql", "/poi/", "/media/", "/health", "/packs/")
USER_AGENT = "Lunaway/tour-web (+https://lunaway.net)"


def serve(port, web, api):
    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *a, **k):
            super().__init__(*a, directory=web, **k)

        def _forward(self, method):
            body = None
            if method == "POST":
                body = self.rfile.read(int(self.headers.get("content-length", 0)))
            headers = {k: v for k, v in self.headers.items()
                       if k.lower() in ("content-type", "authorization", "accept", "accept-language")}
            headers["user-agent"] = USER_AGENT
            req = urllib.request.Request(api + self.path, data=body, headers=headers, method=method)
            try:
                resp = urllib.request.urlopen(req, timeout=120)
                status, data, rh = resp.status, resp.read(), resp.headers
            except urllib.error.HTTPError as e:
                status, data, rh = e.code, e.read(), e.headers
            self.send_response(status)
            for k in ("content-type", "cache-control", "etag", "content-encoding"):
                if rh.get(k):
                    self.send_header(k, rh.get(k))
            self.send_header("content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path.startswith(FORWARD):
                return self._forward("GET")
            return super().do_GET()

        def do_POST(self):
            return self._forward("POST")

        def log_message(self, *a):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--test", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--viewport", default="412x732")
    p.add_argument("--scale", type=float, default=2)
    p.add_argument("--locale", default="fr")
    p.add_argument("--theme", default="light")
    p.add_argument("--api", default="https://api.lunaway.net")
    p.add_argument("--port", type=int, default=18793)
    p.add_argument("--define", action="append", default=[])
    p.add_argument("--no-build", action="store_true")
    p.add_argument("--headed", action="store_true", help="a visible browser, which has the system's voices")
    p.add_argument("--minutes", type=float, default=45)
    args = p.parse_args()
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    web = os.path.abspath(os.path.join("build", "web-tour"))
    origin = f"http://127.0.0.1:{args.port}"
    width, height = (int(v) for v in args.viewport.split("x"))
    tag = f"{args.locale}-web{args.viewport}-{args.theme}"
    if not args.no_build:
        subprocess.run([
            "fvm", "flutter", "build", "web", "--profile", "-t", args.test, "--output", web,
            f"--dart-define=LUNAWAY_API_URL={origin}",
            f"--dart-define=LUNAWAY_TOUR_LOCALE={args.locale}",
            f"--dart-define=LUNAWAY_TOUR_THEME={args.theme}",
            f"--dart-define=LUNAWAY_TOUR_TAG={tag}",
            *[f"--dart-define={d}" for d in args.define],
        ], check=True)
    server = serve(args.port, web, args.api)

    from playwright.sync_api import sync_playwright

    lines = queue.Queue()
    written = set()
    code = 1
    with sync_playwright() as pw:
        browser = pw.chromium.launch(
            headless=not args.headed,
            args=["--autoplay-policy=no-user-gesture-required", "--use-angle=swiftshader",
                  "--enable-unsafe-swiftshader"],
        )
        context = browser.new_context(
            viewport={"width": width, "height": height},
            device_scale_factor=args.scale,
            locale=args.locale,
            color_scheme=args.theme,
        )
        page = context.new_page()
        page.on("console", lambda m: lines.put(m.text))
        page.on("pageerror", lambda e: lines.put(f"PAGE ERROR {e}"))
        page.goto(origin + "/")
        # A click on the page, as a user's: a browser speaks only once the
        # page had a gesture.
        page.wait_for_timeout(1500)
        page.mouse.click(2, 2)
        end = time.time() + args.minutes * 60
        while time.time() < end:
            page.wait_for_timeout(150)
            while not lines.empty():
                for line in lines.get().splitlines():
                    print(line, flush=True)
                    note = line.find("WRITE ")
                    if note >= 0:
                        name, _, text = line[note + 6:].partition(" ")
                        if re.fullmatch(r"[A-Za-z0-9._-]+\.txt", name):
                            with open(os.path.join(out, name), "a" if name in written else "w",
                                      encoding="utf-8") as f:
                                f.write(text + "\n")
                            written.add(name)
                        continue
                    shot = line.find("SHOT ")
                    if shot >= 0:
                        name = line[shot + 5:].strip()
                        # A name of the test's own, never a path out of the folder.
                        if re.fullmatch(r"[A-Za-z0-9._-]+", name):
                            path = os.path.join(out, name + ".png")
                            page.screenshot(path=path)
                            print(f"captured {path}", flush=True)
                        else:
                            print(f"refused shot name {name!r}", flush=True)
                    if "TOUR DONE" in line:
                        code = 0
                        end = 0
                    if "Test failed" in line or "EXCEPTION CAUGHT" in line:
                        end = time.time() + 5
        browser.close()
    server.shutdown()
    sys.exit(code)


if __name__ == "__main__":
    main()
