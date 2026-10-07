"""Gives the startup files of a web build names that carry their content's
digest, so that /app/ can serve them immutable (infra/caddy/lunaway.net.caddy)
and a returning browser takes them from its HTTP cache without asking.

    python3 tool/web/fingerprint.py [--compress] BUILD_DIR

Run after `flutter build web` and before tool/web/service_worker.py, which
reads the list this writes. Why it matters, measured on 2026-10-07 in
Chrome 155 on a returning visit: a script served from the HTTP cache gets
V8's code cache on a returning visit, one served by the service worker from
Cache Storage did not (main.dart.js ran in about 240 ms instead of 45 ms),
and MapLibre's worker no longer revalidates its module before it can parse
the first tiles.

Renamed, each as name.<digest>.ext (the digest is the first 12 hex digits of
the SHA-256 of the file as served, after its own references were renamed):
the MapLibre GL JS modules and stylesheet, the Dart program (main.dart.js
and its deferred parts, or the dart2wasm module and its loader), the page's
own scripts, and CanvasKit, whose directory becomes canvaskit-<digest>/.
The files that name them are rewritten: index.html, flutter_bootstrap.js,
premap.js, lunaway_maplibre.js and the MapLibre modules themselves. Every
rewrite expects the text it replaces; a build that no longer has it fails
here rather than in a browser.

Writes BUILD_DIR/hashed.txt, one renamed path per line: the service worker
leaves them to the HTTP cache, and infra/server/install-web.sh carries them
into the next releases, so a page a service worker serves from an older
build still finds them.

--compress also writes a Brotli copy (name.br, quality 11) of every
compressible file of the build, which Caddy serves to browsers that accept
it (`file_server { precompressed br }`): about a quarter fewer bytes than
the on-the-fly compression for the Dart program and CanvasKit. It needs the
`brotli` command.

Standard library only.
"""

import concurrent.futures
import hashlib
import os
import re
import shutil
import subprocess
import sys

DIGITS = 12

# Names that look renamed already: the tool refuses to run twice.
HASHED = re.compile(r"\.[0-9a-f]{%d}\.(?:js|mjs|css|wasm)$|^canvaskit-[0-9a-f]{%d}/" % (DIGITS, DIGITS))

# What --compress writes a Brotli copy of: text, and the WebAssembly modules.
COMPRESSIBLE = (".js", ".mjs", ".css", ".json", ".html", ".wasm", ".svg", ".ttf", ".otf", ".txt", ".map")


class BuildError(Exception):
    pass


class AlreadyDone(Exception):
    """The page names renamed files already: a release passed in again."""


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()[:DIGITS]


def hashed_name(path: str, data: bytes) -> str:
    """dir/name.ext as dir/name.<digest>.ext."""
    head, tail = os.path.split(path)
    stem, ext = os.path.splitext(tail)
    return os.path.join(head, f"{stem}.{digest(data)}{ext}").replace(os.sep, "/")


class Build:
    def __init__(self, root: str):
        self.root = root
        self.renamed: dict[str, str] = {}

    def path(self, rel: str) -> str:
        return os.path.join(self.root, rel)

    def exists(self, rel: str) -> bool:
        return os.path.isfile(self.path(rel))

    def read(self, rel: str) -> str:
        with open(self.path(rel), encoding="utf-8") as f:
            return f.read()

    def write(self, rel: str, text: str) -> None:
        with open(self.path(rel), "w", encoding="utf-8") as f:
            f.write(text)

    def rewrite(self, rel: str, pairs: list[tuple[str, str]]) -> None:
        """Replaces each old text of pairs in rel; each must occur."""
        text = self.read(rel)
        for old, new in pairs:
            if old not in text:
                raise BuildError(f"{rel} no longer contains {old!r}: update tool/web/fingerprint.py")
            text = text.replace(old, new)
        self.write(rel, text)

    def rename(self, rel: str) -> str:
        """Moves rel to its hashed name; returns the new relative path."""
        with open(self.path(rel), "rb") as f:
            data = f.read()
        new = hashed_name(rel, data)
        os.replace(self.path(rel), self.path(new))
        self.renamed[rel] = new
        return new


def fingerprint(root: str) -> list[str]:
    b = Build(root)
    if not b.exists("index.html"):
        raise BuildError(f"no index.html in {root}")
    if re.search(r'src="flutter_bootstrap\.[0-9a-f]{%d}\.js"' % DIGITS, b.read("index.html")):
        raise AlreadyDone()
    # `flutter build web` writes over its output without emptying it: the
    # renamed files of an earlier run of this tool are still there, listed
    # in its hashed.txt, and go before this build is renamed.
    stale = b.path("hashed.txt")
    if os.path.isfile(stale):
        with open(stale) as f:
            listed = [line.strip() for line in f if line.strip()]
        for rel in listed:
            if not HASHED.search(rel) or ".." in rel.split("/"):
                raise BuildError(f"hashed.txt names {rel!r}, which this tool never writes")
            for path in (b.path(rel), b.path(rel) + ".br"):
                if os.path.isfile(path):
                    os.remove(path)
        os.remove(stale)
        for rel in sorted({r.split("/")[0] for r in listed if r.startswith("canvaskit-")}):
            for directory, _, _ in sorted(os.walk(b.path(rel)), key=lambda t: -len(t[0])):
                if not os.listdir(directory):
                    os.rmdir(directory)
    for directory, _, names in os.walk(root):
        for name in names:
            rel = os.path.relpath(os.path.join(directory, name), root).replace(os.sep, "/")
            if HASHED.search(rel):
                raise BuildError(f"{rel} is fingerprinted already; run on a fresh build")

    # MapLibre GL JS: the shared chunk, then the worker and the library,
    # which import it by relative name; the library names the worker too
    # (`new URL('./maplibre-gl-worker.mjs', import.meta.url)`).
    shared = b.rename("maplibre-gl/maplibre-gl-shared.mjs")
    shared_name = os.path.basename(shared)
    b.rewrite("maplibre-gl/maplibre-gl-worker.mjs", [('"./maplibre-gl-shared.mjs"', f'"./{shared_name}"')])
    worker = b.rename("maplibre-gl/maplibre-gl-worker.mjs")
    b.rewrite(
        "maplibre-gl/maplibre-gl.mjs",
        [('"./maplibre-gl-shared.mjs"', f'"./{shared_name}"'), ("`maplibre-gl-worker.mjs`", f"`{os.path.basename(worker)}`")],
    )
    library = b.rename("maplibre-gl/maplibre-gl.mjs")
    css = b.rename("maplibre-gl/maplibre-gl.css")

    # The page's scripts that import the library.
    for rel in ("lunaway_maplibre.js", "premap.js"):
        b.rewrite(rel, [("'maplibre-gl/maplibre-gl.mjs'", f"'{library}'")])
    page_scripts = {rel: b.rename(rel) for rel in ("lunaway_maplibre.js", "premap.js", "splash.js", "sw_register.js")}

    # CanvasKit (and skwasm): one directory per engine, renamed whole. The
    # loader finds it through canvasKitBaseUrl, set in web/flutter_bootstrap.js.
    ck = hashlib.sha256()
    ck_files = []
    for directory, _, names in os.walk(b.path("canvaskit")):
        for name in sorted(names):
            full = os.path.join(directory, name)
            ck_files.append(os.path.relpath(full, b.path("canvaskit")).replace(os.sep, "/"))
    for rel in sorted(ck_files):
        with open(os.path.join(b.path("canvaskit"), rel), "rb") as f:
            ck.update(rel.encode() + b"\0" + hashlib.sha256(f.read()).digest())
    if not ck_files:
        raise BuildError("no canvaskit/ in the build: build with --no-web-resources-cdn")
    ck_dir = f"canvaskit-{ck.hexdigest()[:DIGITS]}"
    os.replace(b.path("canvaskit"), b.path(ck_dir))

    # The Dart program. dart2js deferred parts are named in main.dart.js;
    # dart2wasm's module and its loader are named in the build config.
    config_pairs = [("canvasKitBaseUrl: 'canvaskit/'", f"canvasKitBaseUrl: '{ck_dir}/'")]
    if b.exists("main.dart.js"):
        parts = sorted(n for n in os.listdir(root) if re.fullmatch(r"main\.dart\.js_\d+\.part\.js", n))
        part_pairs = []
        for part in parts:
            part_pairs.append((f'"{part}"', f'"{os.path.basename(b.rename(part))}"'))
        if part_pairs:
            b.rewrite("main.dart.js", part_pairs)
        main_js = b.rename("main.dart.js")
        config_pairs.append(('"mainJsPath":"main.dart.js"', f'"mainJsPath":"{main_js}"'))
    if b.exists("main.dart.wasm"):
        config_pairs.append(('"mainWasmPath":"main.dart.wasm"', f'"mainWasmPath":"{b.rename("main.dart.wasm")}"'))
        config_pairs.append(('"jsSupportRuntimePath":"main.dart.mjs"', f'"jsSupportRuntimePath":"{b.rename("main.dart.mjs")}"'))
    b.rewrite("flutter_bootstrap.js", config_pairs)
    bootstrap = b.rename("flutter_bootstrap.js")

    # The page names them all.
    pairs = [
        ('href="maplibre-gl/maplibre-gl.mjs"', f'href="{library}"'),
        ('href="maplibre-gl/maplibre-gl-shared.mjs"', f'href="{shared}"'),
        ('href="maplibre-gl/maplibre-gl-worker.mjs"', f'href="{worker}"'),
        ('href="maplibre-gl/maplibre-gl.css"', f'href="{css}"'),
        ('src="flutter_bootstrap.js"', f'src="{bootstrap}"'),
    ]
    pairs += [(f'src="{old}"', f'src="{new}"') for old, new in page_scripts.items()]
    b.rewrite("index.html", pairs)

    listed = sorted(b.renamed.values()) + sorted(f"{ck_dir}/{rel}" for rel in ck_files)
    with open(b.path("hashed.txt"), "w") as f:
        f.write("".join(p + "\n" for p in listed))
    return listed


def compress(root: str) -> int:
    if shutil.which("brotli") is None:
        raise BuildError("--compress needs the brotli command (brew install brotli, apt install brotli)")
    todo = []
    for directory, _, names in os.walk(root):
        for name in names:
            full = os.path.join(directory, name)
            # The service worker is written after this, by
            # tool/web/service_worker.py: a copy made now would be of the
            # previous build's worker, which Caddy would then serve.
            if name == "lunaway_sw.js":
                continue
            if name.endswith(COMPRESSIBLE) and os.path.getsize(full) >= 1024:
                todo.append(full)

    def one(full: str) -> bool:
        subprocess.run(["brotli", "-q", "11", "-f", "-o", full + ".br", full], check=True)
        # A copy that saves nothing is not worth a second file.
        if os.path.getsize(full + ".br") >= os.path.getsize(full):
            os.remove(full + ".br")
            return False
        return True

    # Quality 11 takes seconds per megabyte: one file per core.
    with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
        return sum(pool.map(one, todo))


def main() -> int:
    args = sys.argv[1:]
    want_compress = "--compress" in args
    args = [a for a in args if a != "--compress"]
    if len(args) != 1:
        print("usage: fingerprint.py [--compress] BUILD_DIR", file=sys.stderr)
        return 2
    try:
        listed = fingerprint(args[0])
        print(f"fingerprint: {len(listed)} files renamed, listed in hashed.txt")
        if want_compress:
            print(f"fingerprint: {compress(args[0])} Brotli copies")
    except AlreadyDone:
        print("fingerprint: the page names renamed files already, nothing to do")
    except BuildError as e:
        print(f"fingerprint: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
