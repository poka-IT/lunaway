"""Plays the journeys of the map screen on a web build, as a phone (touch,
Chromium and WebKit, and Firefox in a small window) and as a computer (mouse,
Chromium, Firefox and WebKit), and checks the screen each one reaches.
Run it on the build about to be deployed, before infra/deploy-web.sh:

    sh packages/lunaway_nav/tool/build_web.sh
    fvm flutter build web --release --wasm --base-href /app/ --no-web-resources-cdn \\
        --dart-define=LUNAWAY_API_URL=http://127.0.0.1:18793
    python3 tool/web/serve_csp.py --port 18793 --api https://api.lunaway.net/graphql &
    python3 tool/web/journeys.py --url http://127.0.0.1:18793/app/

Run from app/. Needs the playwright Python package and its three browsers
(`python3 -m playwright install chromium firefox webkit`). Exits 1 when a
journey fails; writes a screenshot at each step and a report.json under
--out (build/journeys by default).

The journeys: a town found and touched (the map goes there); an address
found (its card stays), its route, "C'est parti !" (the guidance), a back
during it ("Arrêter le guidage ?", then the card), a second guidance and
its end, the close; a place found and guided to; a point of the map ("Ici")
and its route; on a phone, the browser's back over the filters and over the
photo viewer; on a computer, the button of a message over the map, and
Escape on a card the search opened.

A phone's browser sends the mouse events of a tap (mousedown, mouseup,
click) after its touch, up to a few hundred milliseconds later, to whatever
element lies under the finger by then. Each tap on a phone is followed by
those events (--late-click, 150 ms by default), sent to the element under
the point that the app does not draw itself: the condition under which a
search result once cut the map's flight short, closed the card it had just
opened, or opened a point instead. The app's controls are found through
Flutter's semantics (the tree a screen reader reads), which the tool turns
on.
"""

import argparse
import json
import math
import os
import re
import sys
import time

DEVICES = {
    # width, height, touch
    "phone": (390, 844, True),
    "desktop": (1440, 900, False),
}

# Where each journey starts from, and what it looks for. Public places only.
LYON = (45.7578, 4.8320)
PARIS = (48.8566, 2.3522)
MONTELIMAR = (44.5581, 4.7508)
ANNECY = (45.8992, 6.1294)
# What the national geocoder names "20 avenue de Ségur 75007 Paris", with
# or without its number.
SEGUR = "Avenue de Ségur"

# Turns the map's camera and the history into something a step can read,
# and sends a tap's late mouse events where a browser would.
PAGE_SCRIPT = r"""
(() => {
  window.__history = [];
  const rec = (kind, extra) => window.__history.push({kind, at: location.hash, ...extra});
  const push = history.pushState.bind(history);
  const replace = history.replaceState.bind(history);
  const go = history.go.bind(history);
  history.pushState = function (s, t, u) { const r = push(s, t, u); rec('push', {to: String(u)}); return r; };
  history.replaceState = function (s, t, u) { const r = replace(s, t, u); rec('replace', {to: String(u)}); return r; };
  history.go = function (n) { rec('go', {n}); return go(n); };
  window.addEventListener('popstate', () => rec('popstate', {}));
  const hook = () => {
    const gl = window.maplibregl;
    if (!gl || !gl.Map) return false;
    if (gl.Map.prototype.__journeys) return true;
    gl.Map.prototype.__journeys = true;
    for (const name of ['jumpTo', 'easeTo', 'flyTo', 'fitBounds', 'resize']) {
      const own = gl.Map.prototype[name];
      gl.Map.prototype[name] = function (...args) {
        (window.__maps = window.__maps || new Set()).add(this);
        return own.apply(this, args);
      };
    }
    return true;
  };
  if (!hook()) { const timer = setInterval(() => { if (hook()) clearInterval(timer); }, 50); }
  // The cameras of the maps laid out on the page.
  window.__cameras = () => [...(window.__maps || [])]
    .filter((m) => m.getContainer().clientWidth > 0 && m.getContainer().isConnected)
    .map((m) => { const c = m.getCenter(); return {lat: c.lat, lon: c.lng, zoom: m.getZoom()}; });
  // The mouse events a phone's browser sends after a tap, [delay] ms late,
  // to the element under the point that the app does not draw itself
  // (Flutter's semantics, which this tool turns on, would not be there for
  // a user).
  window.__lateClick = (x, y, delay) => setTimeout(() => {
    const el = document.elementsFromPoint(x, y)
      .find((e) => !e.closest('flt-semantics-host') && e.tagName !== 'FLT-SEMANTICS-PLACEHOLDER');
    if (!el) return;
    const at = {bubbles: true, cancelable: true, composed: true, clientX: x, clientY: y, button: 0, view: window};
    el.dispatchEvent(new MouseEvent('mousedown', {...at, buttons: 1}));
    el.dispatchEvent(new MouseEvent('mouseup', at));
    el.dispatchEvent(new MouseEvent('click', at));
    rec('late click', {on: el.tagName.toLowerCase()});
  }, delay);
})();
"""


class Failed(Exception):
    pass


def metres(a, b):
    r = math.pi / 180
    x = (b[1] - a[1]) * r * math.cos((a[0] + b[0]) / 2 * r)
    y = (b[0] - a[0]) * r
    return math.hypot(x, y) * 6371008.8


class Run:
    """One journey in a fresh browser context: the page, its device, its
    steps and their screenshots."""

    def __init__(self, browser, engine, device, journey, args, geo):
        self.engine = engine
        self.device = device
        self.journey = journey
        self.args = args
        width, height, touch = DEVICES[device]
        # Firefox has no mobile mode: the phone is a small window it
        # clicks in.
        self.touch = touch and engine != "firefox"
        options = dict(
            viewport={"width": width, "height": height},
            locale="fr-FR",
            geolocation={"latitude": geo[0], "longitude": geo[1]},
            service_workers="block",
        )
        if engine != "firefox":
            options["permissions"] = ["geolocation"]
        if self.touch:
            options.update(is_mobile=True, has_touch=True, device_scale_factor=2)
        self.context = browser.new_context(**options)
        if engine == "firefox":
            self.context.grant_permissions(["geolocation"])
        self.context.add_init_script(PAGE_SCRIPT)
        self.page = self.context.new_page()
        self.page.set_default_timeout(60000)
        self.steps = []
        self.dir = os.path.join(args.out, f"{engine}-{device}", journey)
        os.makedirs(self.dir, exist_ok=True)

    def close(self):
        self.context.close()

    def step(self, name):
        path = os.path.join(self.dir, f"{len(self.steps) + 1:02d}-{name}.png")
        self.page.screenshot(path=path)
        self.steps.append({"step": name, "hash": self.hash(), "shot": path})

    def hash(self):
        return self.page.evaluate("location.hash")

    def open(self):
        self.page.goto("about:blank")
        self.page.goto(self.args.url, wait_until="domcontentloaded")
        self.page.wait_for_selector("flutter-view")
        # The map's first camera, then the semantics a screen reader reads.
        self.wait(lambda: self.page.evaluate("(window.__cameras ? window.__cameras() : []).length > 0"),
                  "the map", timeout=60)
        self.page.evaluate("document.querySelector('flt-semantics-placeholder')?.click()")
        self.wait(lambda: self.page.evaluate("document.querySelectorAll('flt-semantics[role=button]').length > 3"),
                  "the app's controls")
        time.sleep(1)
        self.step("open")

    def wait(self, ready, what, timeout=None):
        end = time.time() + (timeout or self.args.wait)
        while time.time() < end:
            if ready():
                return
            time.sleep(0.25)
        self.step("timeout")
        raise Failed(f"{what} did not come")

    def find(self, label, role="button", exact=False, within=False, top=False):
        """The centre of the first control in sight named [label]: its words
        begin with it, are it when [exact], hold it when [within] (a row of
        results may carry its section's title first). Near its top edge with
        [top], for one a bar may cover the foot of. None when none is."""
        return self.page.evaluate(
            """([label, role, exact, within, top]) => {
              const norm = (s) => (s || '').replace(/\\s+/g, ' ').trim();
              const w = innerWidth, h = innerHeight;
              const host = document.querySelector('flt-semantics-host') || document;
              const selector = role === 'textbox' ? '[role="textbox"], input, textarea' : `[role="${role}"]`;
              for (const e of host.querySelectorAll(selector)) {
                const name = norm(e.getAttribute('aria-label') || e.innerText || e.value);
                if (exact ? name !== label : within ? !name.includes(label) : !name.startsWith(label)) continue;
                const r = e.getBoundingClientRect();
                const x = r.x + r.width / 2, y = top ? r.y + Math.min(24, r.height / 2) : r.y + r.height / 2;
                if (r.width < 1 || x < 0 || y < 0 || x > w || y > h) continue;
                return [x, y];
              }
              return null;
            }""",
            [label, role, exact, within, top],
        )

    def shows(self, text):
        """Whether the app's words (its semantics, the text a screen reader
        reads) hold [text]."""
        return self.page.evaluate(
            """(text) => {
              const host = document.querySelector('flt-semantics-host');
              const norm = (s) => (s || '').replace(/\\s+/g, ' ');
              if (!host) return false;
              if (norm(host.innerText).includes(text)) return true;
              return [...host.querySelectorAll('[aria-label]')]
                .some((e) => norm(e.getAttribute('aria-label')).includes(text));
            }""",
            text,
        )

    def tap_at(self, x, y):
        if self.touch:
            self.page.touchscreen.tap(x, y)
            if self.args.late_click >= 0:
                self.page.evaluate(f"window.__lateClick({x}, {y}, {self.args.late_click})")
        else:
            self.page.mouse.click(x, y)

    def tap(self, label, role="button", exact=False, within=False, top=False, name=None):
        self.wait(lambda: self.find(label, role, exact, within, top) is not None, f'"{label}"')
        x, y = self.find(label, role, exact, within, top)
        self.tap_at(x, y)
        time.sleep(0.4)
        self.step(name or re.sub(r"[^a-z0-9]+", "-", label.lower()).strip("-")[:40])

    def type_search(self, text):
        # The field takes the keyboard once the app is ready for it: touched
        # again until the page's focus is in a field.
        for _ in range(4):
            self.wait(lambda: self.find("", role="textbox") is not None, "the search field")
            x, y = self.find("", role="textbox")
            self.tap_at(x, y)
            time.sleep(0.8)
            if self.page.evaluate("['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName)"):
                break
        self.page.keyboard.type(text, delay=30)
        time.sleep(1.5)

    def back(self):
        self.page.evaluate("history.back()")
        time.sleep(1.5)
        self.step("back")

    def expect(self, ok, why):
        if not ok:
            self.step("failed")
            raise Failed(why)

    def expect_soon(self, ready, why, timeout=None):
        try:
            self.wait(ready, why, timeout)
        except Failed:
            raise Failed(why) from None

    def camera_near(self, place, metres_within, zoom_at_least):
        for c in self.page.evaluate("window.__cameras ? window.__cameras() : []"):
            if metres((c["lat"], c["lon"]), place) <= metres_within and c["zoom"] >= zoom_at_least:
                return True
        return False

    def start_guidance(self):
        """From a preview: the vehicle described when asked, then "C'est
        parti !", and the guidance shown."""
        self.wait(lambda: self.find("C'est parti") or self.find("Décrire mon véhicule"), "the preview's action")
        if self.find("Décrire mon véhicule"):
            self.tap("Décrire mon véhicule")
            self.tap("Enregistrer")
        # The button turns active once the route is there.
        self.wait(lambda: self.page.evaluate(
            """() => [...document.querySelectorAll('flt-semantics[role=button]')]
                 .some((e) => (e.innerText || '').startsWith("C'est parti") && e.getAttribute('aria-disabled') !== 'true')"""),
            "a route to start")
        self.tap("C'est parti")
        self.expect_soon(lambda: self.find("Terminer") is not None, "the guidance after \"C'est parti !\"")
        self.expect(not self.shows("C'est parti"), "the preview left under the guidance")
        self.step("guidance")

    def end_guidance(self):
        self.tap("Terminer", name="terminer")
        self.tap("Terminer", exact=True, name="terminer-confirme")
        self.expect_soon(lambda: self.find("Terminer") is None, "the guidance ended")


def journey_town(run):
    """A town found and touched: the map goes there, nothing opens."""
    run.open()
    run.type_search("Annecy")
    run.step("results")
    run.tap("Annecy 74", within=True, name="town")
    run.expect_soon(lambda: run.camera_near(ANNECY, 4000, 11.5), "the map at Annecy after the town touched")
    time.sleep(1.5)
    run.expect(run.hash() == "#/map", f"nothing open after the town, not {run.hash()}")
    run.expect(run.camera_near(ANNECY, 4000, 11.5), "the map still at Annecy")


def journey_address(run):
    """An address found: its card stays, its route, the guidance, a back
    that asks, the card again, a second guidance, the close."""
    run.open()
    run.type_search("20 avenue de Ségur 75007 Paris")
    run.step("results")
    run.tap(SEGUR, within=True, name="address")
    time.sleep(2)
    run.expect(run.hash() == "#/map?point", f"the address's card open, not {run.hash()}")
    run.expect(run.shows(SEGUR), "the card names the address")
    run.tap("Itinéraire jusqu'ici")
    run.expect_soon(lambda: run.shows("Vers ") and run.shows(SEGUR + ", Paris"),
                    "the preview named after the address")
    run.start_guidance()
    run.back()
    run.expect_soon(lambda: run.shows("Arrêter le guidage"), "the question of a back during a guidance")
    run.tap("Arrêter", exact=True, name="arreter")
    run.expect_soon(lambda: run.hash() == "#/map?point" and run.find("Itinéraire jusqu'ici"),
                    "the address's card after the guidance stopped")
    run.tap("Itinéraire jusqu'ici", name="second-route")
    run.start_guidance()
    run.end_guidance()
    run.expect_soon(lambda: run.find("Itinéraire jusqu'ici") is not None, "the card after the second guidance")
    run.tap("Fermer", exact=True, name="close")
    run.expect_soon(lambda: run.hash() == "#/map", "the bare map after the close")


def journey_place(run):
    """A place found: its card, its route, the guidance and its end."""
    run.open()
    run.type_search("Camping-car Park Viviers")
    run.step("results")
    run.tap("Camping-car Park Viviers", within=True, name="place")
    run.expect_soon(lambda: run.hash().startswith("#/map?place="), "the place's card")
    run.tap("Itinéraire", exact=True)
    run.start_guidance()
    run.end_guidance()
    run.expect_soon(lambda: run.hash().startswith("#/map?place="), "the place's card after the guidance")


def journey_point(run):
    """A point of the map at the street: its card "Ici", its route, back to
    the card."""
    run.open()
    run.type_search("20 avenue de Ségur 75007 Paris")
    run.tap(SEGUR, within=True, name="address")
    run.expect_soon(lambda: run.camera_near(PARIS, 5000, 15), "the map at the street")
    run.tap("Fermer", exact=True, name="close")
    time.sleep(1.5)
    width, height, _ = DEVICES[run.device]
    # Above the middle of the map: clear of the list and of the panes.
    x = width * (0.5 if run.device == "phone" else 0.7)
    run.tap_at(x, height * 0.35)
    time.sleep(1.5)
    run.step("point")
    run.expect_soon(lambda: run.hash() == "#/map?point", "the card of the point touched")
    run.tap("Itinéraire jusqu'ici")
    run.expect_soon(lambda: run.shows("Point sur la carte"), "the preview of the point")
    run.tap("Retour", exact=True, name="preview-back")
    run.expect_soon(lambda: run.hash() == "#/map?point" and run.find("Itinéraire jusqu'ici"),
                    "the point's card after the preview")


def journey_filters(run):
    """On a phone, the browser's back over the filters closes them."""
    run.open()
    run.tap("Filtres", exact=True)
    run.expect_soon(lambda: run.shows("Réinitialiser") or run.shows("Afficher"), "the filters")
    run.back()
    run.expect(run.hash() == "#/map", f"still on the map, not {run.hash() or 'out of the app'}")
    run.expect_soon(lambda: run.find("Filtres", exact=True) is not None, "the map after the back")


def journey_viewer(run):
    """On a phone, the browser's back over the photo viewer closes it, the
    place stays."""
    run.open()
    run.type_search("Camping-car Park Viviers")
    run.tap("Camping-car Park Viviers", within=True, name="place")
    run.expect_soon(lambda: run.hash().startswith("#/map?place="), "the place's card")
    place = run.hash()
    run.tap("Photo 1 sur", top=True, name="photo")
    run.expect_soon(lambda: run.find("Photo suivante") is not None, "the viewer")
    run.back()
    run.expect(run.hash() == place, f"the place still open, not {run.hash()}")
    run.expect(run.find("Photo suivante") is None, "the viewer closed")


def journey_message(run):
    """On a computer, the button of a message over the map ("Listes" after
    "Enregistrer") acts on the message alone: the card stays."""
    run.open()
    run.type_search("Camping-car Park Viviers")
    run.tap("Camping-car Park Viviers", within=True, name="place")
    run.expect_soon(lambda: run.hash().startswith("#/map?place="), "the place's card")
    place = run.hash()
    run.tap("Enregistrer", exact=True)
    # "Ajouté à Mes favoris · Listes", over the map beside the card.
    run.tap("Listes", exact=True, name="listes-message")
    time.sleep(1.5)
    run.expect(run.hash() == place, f"the card still open after the message's button, not {run.hash()}")


def journey_escape(run):
    """On a computer, Escape closes a card the search opened."""
    run.open()
    run.type_search("Camping-car Park Viviers")
    run.tap("Camping-car Park Viviers", within=True, name="place")
    run.expect_soon(lambda: run.hash().startswith("#/map?place="), "the place's card")
    run.page.keyboard.press("Escape")
    time.sleep(1)
    run.step("escape")
    run.expect_soon(lambda: run.hash() == "#/map", "the card closed by Escape")


JOURNEYS = {
    # name: (function, start, devices)
    "town": (journey_town, LYON, ("phone", "desktop")),
    "address": (journey_address, PARIS, ("phone", "desktop")),
    "place": (journey_place, MONTELIMAR, ("phone", "desktop")),
    "point": (journey_point, PARIS, ("phone", "desktop")),
    "filters": (journey_filters, LYON, ("phone",)),
    "viewer": (journey_viewer, MONTELIMAR, ("phone",)),
    "message": (journey_message, MONTELIMAR, ("desktop",)),
    "escape": (journey_escape, MONTELIMAR, ("desktop",)),
}


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--url", required=True, help="the app, ending in /app/")
    p.add_argument("--engines", default="chromium,webkit,firefox")
    p.add_argument("--devices", default="phone,desktop")
    p.add_argument("--journeys", default=",".join(JOURNEYS), help="among " + ", ".join(JOURNEYS))
    p.add_argument("--out", default=os.path.join("build", "journeys"))
    p.add_argument("--late-click", type=int, default=150,
                   help="ms after a phone's tap for its mouse events; -1 for none")
    p.add_argument("--wait", type=float, default=20, help="seconds a step may wait for the screen")
    p.add_argument("--headed", action="store_true")
    args = p.parse_args()
    os.makedirs(args.out, exist_ok=True)

    from playwright.sync_api import sync_playwright

    results = []
    with sync_playwright() as pw:
        for engine in args.engines.split(","):
            launch = {"headless": not args.headed}
            if engine == "chromium":
                launch["args"] = ["--use-angle=swiftshader", "--enable-unsafe-swiftshader"]
            browser = getattr(pw, engine).launch(**launch)
            for device in args.devices.split(","):
                for name in args.journeys.split(","):
                    play, start, devices = JOURNEYS[name]
                    if device not in devices:
                        continue
                    run = Run(browser, engine, device, name, args, start)
                    began = time.time()
                    try:
                        play(run)
                        outcome = "passed"
                        why = None
                    except Failed as e:
                        outcome, why = "failed", str(e)
                    except Exception as e:  # noqa: BLE001 - a broken page is a failed journey
                        outcome, why = "failed", f"{type(e).__name__}: {e}"
                    history = run.page.evaluate("window.__history || []")
                    run.close()
                    results.append({
                        "engine": engine, "device": device, "journey": name, "outcome": outcome,
                        "why": why, "seconds": round(time.time() - began, 1), "steps": run.steps,
                        "history": history,
                    })
                    print(f"{outcome:6} {engine:8} {device:7} {name:8} {why or ''}", flush=True)
            browser.close()
    with open(os.path.join(args.out, "report.json"), "w") as f:
        json.dump(results, f, indent=1, ensure_ascii=False)
    failed = [r for r in results if r["outcome"] != "passed"]
    print(f"{len(results) - len(failed)} passed, {len(failed)} failed; {args.out}/report.json")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
