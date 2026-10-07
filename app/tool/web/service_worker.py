"""Writes the service worker of a web build: lunaway_sw.js in BUILD_DIR.

    python3 tool/web/service_worker.py build/web

A second visit to the web app should not wait on the network for the app
itself: every file of /app/ is served with `Cache-Control: no-cache` (their
names carry no content hash, infra/caddy/lunaway.net.caddy), so without a
service worker each visit revalidates each file, one round trip each.

The worker keeps the files of one build in a cache named after the build
(a digest of every file it serves), answers from it first, and fetches what
it lacks once. The files the app needs to start are fetched when the worker
installs, after the first visit has drawn its map (web/sw_register.js); the
others (pin images, fonts, the CanvasKit variant of another browser) when
first asked. A new build has a new worker: it installs in the background,
takes over at once, and drops the previous build's cache; the page that was
open goes on with what it loaded.

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

# Fetched at install: what the app needs before its first frame and its map.
START = [
    "index.html",
    "flutter_bootstrap.js",
    "main.dart.js",
    "splash.js",
    "lunaway_maplibre.js",
    "premap.js",
    "sw_register.js",
    "manifest.json",
    "version.json",
    "sqlite3.wasm",
    "drift_worker.js",
    "maplibre-gl/maplibre-gl.mjs",
    "maplibre-gl/maplibre-gl-shared.mjs",
    "maplibre-gl/maplibre-gl-worker.mjs",
    "maplibre-gl/maplibre-gl.css",
    "assets/AssetManifest.bin.json",
    "assets/AssetManifest.bin",
    "assets/FontManifest.json",
    "assets/assets/map/styles/aube.json",
    "assets/assets/map/styles/minuit.json",
    "icons/lunaway-mark.svg",
]

# Never served from the worker's cache: the worker itself.
SKIP = {"lunaway_sw.js", "flutter_service_worker.js"}

TEMPLATE = """// Written by app/tool/web/service_worker.py for one build; see its header.
'use strict';

const BUILD = '{build}';
const CACHE = 'lunaway-app-' + BUILD;
const TILEJSON = 'lunaway-tilejson';
const START = {start};
const FILES = new Set({files});
const SCOPE = new URL('./', self.location).href;

self.addEventListener('install', (event) => {{
  event.waitUntil(
    caches.open(CACHE)
      .then((cache) => cache.addAll(START.map((path) => new Request(SCOPE + path, {{ cache: 'no-cache' }}))))
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


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    root = sys.argv[1]
    if not os.path.isfile(os.path.join(root, "index.html")):
        print(f"no index.html in {root}", file=sys.stderr)
        return 1
    files = []
    digest = hashlib.sha256()
    for directory, _, names in os.walk(root):
        for name in sorted(names):
            full = os.path.join(directory, name)
            path = os.path.relpath(full, root).replace(os.sep, "/")
            if path in SKIP or path.endswith(".symbols"):
                continue
            files.append(path)
    files.sort()
    for path in files:
        with open(os.path.join(root, path), "rb") as f:
            digest.update(path.encode() + b"\0" + hashlib.sha256(f.read()).digest())
    missing = [p for p in START if p not in files]
    if missing:
        print("missing from the build: " + ", ".join(missing), file=sys.stderr)
        return 1
    out = TEMPLATE.format(
        build=digest.hexdigest()[:16],
        start=json.dumps(START),
        files=json.dumps(files),
    )
    with open(os.path.join(root, "lunaway_sw.js"), "w") as f:
        f.write(out)
    print(f"lunaway_sw.js: build {digest.hexdigest()[:16]}, {len(files)} files, {len(START)} at install")
    return 0


if __name__ == "__main__":
    sys.exit(main())
