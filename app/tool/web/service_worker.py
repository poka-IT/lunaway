"""Writes the service worker of a web build: lunaway_sw.js in BUILD_DIR.

    python3 tool/web/service_worker.py build/web
    python3 tool/web/service_worker.py --remove build/web

A second visit to the web app should not wait on the network for the app
itself. The startup files renamed by tool/web/fingerprint.py (listed in the
build's hashed.txt) are served immutable and come from the browser's HTTP
cache, where V8 keeps their compiled code; the worker leaves them alone,
since a script it answers from Cache Storage was measured to run without
that code cache (main.dart.js in about 240 ms instead of 45 ms on a
returning visit). Every other file of /app/ is served with
`Cache-Control: no-cache` (its name carries no content hash,
infra/caddy/lunaway.net.caddy), so without a service worker each visit
would revalidate it, one round trip each: those the worker keeps.

The worker keeps the files of one build in a cache named after the build
(a digest of every file it serves), answers from it first, and fetches what
it lacks once. Every file it keeps that the app may need to start (its
fonts, styles and manifests, and in a build that was not fingerprinted its
code and the CanvasKit of this browser) is fetched when the worker
installs, after the app's first frame (web/sw_register.js), so a
visit never starts one build's code with another build's fonts. The page a
worker serves names the renamed files of the worker's own build: the server
keeps those of the last releases (infra/server/install-web.sh).
What is fetched when first asked (pin images, the licences page, the fallback
fonts) does not depend on the build. A new build has a new worker: it
installs in the background, takes over at once, and drops the previous
build's cache; the page that was open goes on with what it loaded.

`--remove` writes a worker that empties its caches and unregisters itself
instead: the way to take the worker out of every browser. Never delete
lunaway_sw.js from a build: the browsers keep the worker they have.

It also keeps the TileJSON files of the API and of the tile host
(`.../tiles.json`, `.../planet.json`), served from the copy while a fresh one
is fetched for the next visit: they name the current version of the tiles,
which moves at most every few minutes, and the tiles themselves are cached by
the browser for a year under each version.

Standard library only.
"""

import hashlib
import json
import os
import sys

# Files the app needs to start that the worker keeps, which must come from
# one build.
REQUIRED = [
    "index.html",
    "assets/FontManifest.json",
    "assets/assets/map/styles/aube.json",
]

# Fetched when first asked rather than at install: they do not depend on the
# build (pins, licences, the engine's fallback fonts) or are not the web's
# (the desktop map page, the offline map files of the phones).
LAZY = (
    "assets/assets/map/pins/",
    "assets/assets/map/offline/",
    "assets/assets/map/maplibre-gl",
    "assets/assets/map/lunaway_map.js",
    "assets/assets/map/map.html",
    "assets/assets/map/LICENSE",
    "assets/NOTICES",
    "fonts/",
)

# CanvasKit comes in two builds: Chromium's and the others'. The worker
# fetches the one of its browser at install.
CHROMIUM = "canvaskit/chromium/"
GENERIC = ("canvaskit/canvaskit.js", "canvaskit/canvaskit.wasm")

# Never served from the worker's cache: the worker itself and the list of
# renamed files. The Brotli copies (.br) are Caddy's to pick.
SKIP = {"lunaway_sw.js", "flutter_service_worker.js", "hashed.txt"}

TEMPLATE = """// Written by app/tool/web/service_worker.py for one build; see its header.
'use strict';

const BUILD = '{build}';
const CACHE = 'lunaway-app-' + BUILD;
const TILEJSON = 'lunaway-tilejson';
const START = {start};
const CHROMIUM = {chromium};
const GENERIC = {generic};
const FILES = new Set({files});
const SCOPE = new URL('./', self.location).href;

// The CanvasKit build the Flutter loader picks for this browser.
function isChromium() {{
  const brands = (self.navigator.userAgentData && self.navigator.userAgentData.brands) || [];
  return brands.some((b) => /Chromium|Google Chrome|Microsoft Edge/.test(b.brand));
}}

self.addEventListener('install', (event) => {{
  const files = START.concat(isChromium() ? CHROMIUM : GENERIC);
  event.waitUntil(
    caches.open(CACHE)
      .then((cache) => cache.addAll(files.map((path) => new Request(SCOPE + path, {{ cache: 'no-cache' }}))))
      .then(() => self.skipWaiting())
  );
}});

self.addEventListener('activate', (event) => {{
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((key) => key.startsWith('lunaway-app-') && key !== CACHE).map((key) => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
}});

// A file of this build: from the cache, else from the network once.
async function fromBuild(request, path) {{
  const cache = await caches.open(CACHE);
  const key = SCOPE + path;
  const hit = await cache.match(key);
  if (hit) return hit;
  const response = await fetch(new Request(key, {{ cache: 'no-cache' }}));
  if (response.ok) await cache.put(key, response.clone());
  return response;
}}

// A TileJSON: the copy at once, a fresh one for the next time.
async function staleWhileRevalidate(request) {{
  const cache = await caches.open(TILEJSON);
  const hit = await cache.match(request);
  const fresh = fetch(request).then(async (response) => {{
    if (response.ok) await cache.put(request, response.clone());
    return response;
  }});
  if (hit) {{
    fresh.catch(() => {{}});
    return hit;
  }}
  return fresh;
}}

self.addEventListener('fetch', (event) => {{
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.href.startsWith(SCOPE)) {{
    let path = url.pathname.slice(new URL(SCOPE).pathname.length);
    // The app's routes are under its hash; a page load asks for the shell.
    if (request.mode === 'navigate') path = 'index.html';
    if (url.search || !FILES.has(path)) return;
    event.respondWith(fromBuild(request, path));
    return;
  }}
  if (/\\/(tiles|planet)\\.json$/.test(url.pathname) &&
      (url.origin === 'https://api.lunaway.net' || url.origin === 'https://tiles.lunaway.net')) {{
    event.respondWith(staleWhileRevalidate(request));
  }}
}});
"""


REMOVE = """// Written by app/tool/web/service_worker.py --remove: takes the app's
// service worker out of the browser. It empties its caches, unregisters
// itself and reloads the pages it held, which then load from the network.
'use strict';

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter((key) => key.startsWith('lunaway-')).map((key) => caches.delete(key)));
    await self.registration.unregister();
    const clients = await self.clients.matchAll({ type: 'window' });
    clients.forEach((client) => client.navigate(client.url));
  })());
});
"""


def main() -> int:
    args = sys.argv[1:]
    remove = "--remove" in args
    args = [a for a in args if a != "--remove"]
    if len(args) != 1:
        print("usage: service_worker.py [--remove] BUILD_DIR", file=sys.stderr)
        return 2
    root = args[0]
    if not os.path.isfile(os.path.join(root, "index.html")):
        print(f"no index.html in {root}", file=sys.stderr)
        return 1
    if remove:
        with open(os.path.join(root, "lunaway_sw.js"), "w") as f:
            f.write(REMOVE)
        print("lunaway_sw.js: removes the worker from every browser that has it")
        return 0
    hashed = set()
    listing = os.path.join(root, "hashed.txt")
    if os.path.isfile(listing):
        with open(listing) as f:
            hashed = {line.strip() for line in f if line.strip()}
    files = []
    digest = hashlib.sha256()
    for directory, _, names in os.walk(root):
        for name in sorted(names):
            full = os.path.join(directory, name)
            path = os.path.relpath(full, root).replace(os.sep, "/")
            if path in SKIP or path in hashed or path.endswith((".symbols", ".br")):
                continue
            files.append(path)
    files.sort()
    for path in files:
        with open(os.path.join(root, path), "rb") as f:
            digest.update(path.encode() + b"\0" + hashlib.sha256(f.read()).digest())
    missing = [p for p in REQUIRED if p not in files]
    if missing:
        print("missing from the build: " + ", ".join(missing), file=sys.stderr)
        return 1
    chromium = [p for p in files if p.startswith(CHROMIUM)]
    generic = [p for p in files if p in GENERIC]
    start = [
        p
        for p in files
        if not p.startswith(LAZY)
        and not p.startswith("canvaskit/")
        and not p.endswith(".LICENSE.txt")
    ]
    out = TEMPLATE.format(
        build=digest.hexdigest()[:16],
        start=json.dumps(start),
        chromium=json.dumps(chromium),
        generic=json.dumps(generic),
        files=json.dumps(files),
    )
    with open(os.path.join(root, "lunaway_sw.js"), "w") as f:
        f.write(out)
    print(
        f"lunaway_sw.js: build {digest.hexdigest()[:16]}, {len(files)} files, "
        f"{len(start)} at install with {len(chromium)} or {len(generic)} of CanvasKit"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
