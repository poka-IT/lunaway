"""Serves infra/web/site/ the way the lunaway.net Caddy site does, for
local checks while Docker is unavailable: try_files {path} {path}.html
{path}/index.html, the security headers and the per-path CSP of
infra/caddy/lunaway.net.caddy, the cache rule for hashed names, the 404 page,
and gzip for text (Caddy encodes zstd or gzip).

    python3 data/tmp/site/serve.py [PORT] [--csp-api URL]

--csp-api replaces https://api.lunaway.net in the deletion page's
connect-src and in its form's data-endpoint, for an end-to-end test against
a local API.
"""

import gzip
import http.server
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "infra", "web", "site"))
PORT = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 18790
API = sys.argv[sys.argv.index("--csp-api") + 1] if "--csp-api" in sys.argv else "https://api.lunaway.net"

CSP_PAGES = ("default-src 'none'; style-src 'self'; img-src 'self' data:; font-src 'self'; "
             "base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
CSP_DELETE = (f"default-src 'none'; script-src 'self'; connect-src {API}; style-src 'self'; "
              "img-src 'self' data:; font-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
DELETE_PATHS = {prefix + "account/delete" + ext
                for prefix in ("/", "/en/", "/de/", "/es/", "/it/", "/nl/") for ext in ("", ".html")}
HASHED = re.compile(r"\.[0-9a-f]{8,}\.(css|js|woff2|svg|png|jpg|jpeg|webp|avif|ico)$")
TYPES = {
    ".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8", ".js": "text/javascript; charset=utf-8",
    ".woff2": "font/woff2", ".webp": "image/webp", ".png": "image/png", ".svg": "image/svg+xml",
    ".ico": "image/vnd.microsoft.icon", ".txt": "text/plain; charset=utf-8", ".xml": "text/xml; charset=utf-8",
}
COMPRESS = (".html", ".css", ".js", ".svg", ".txt", ".xml", ".ico")


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def resolve(self, path):
        candidates = [path, path + ".html", path.rstrip("/") + "/index.html"]
        if path.endswith("/"):
            candidates = [path + "index.html"]
        for c in candidates:
            full = os.path.normpath(os.path.join(ROOT, c.lstrip("/")))
            if full.startswith(ROOT) and os.path.isfile(full):
                return full
        return None

    def do_GET(self):
        self.serve(head=False)

    def do_HEAD(self):
        self.serve(head=True)

    def serve(self, head):
        path = self.path.split("?", 1)[0]
        file = self.resolve(path)
        status = 200
        if file is None:
            status, file = 404, os.path.join(ROOT, "404.html")
        with open(file, "rb") as f:
            body = f.read()
        if API != "https://api.lunaway.net" and path in DELETE_PATHS:
            # The end-to-end test: the form calls the local API instead.
            body = body.replace(b'data-endpoint="https://api.lunaway.net/graphql"',
                                f'data-endpoint="{API}/graphql"'.encode())
        ext = os.path.splitext(file)[1]
        self.send_response(status)
        self.send_header("Content-Type", TYPES.get(ext, "application/octet-stream"))
        self.send_header("Content-Security-Policy", CSP_DELETE if path in DELETE_PATHS and status == 200 else CSP_PAGES)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cache-Control", "public, max-age=31536000, immutable" if HASHED.search(path) else "public, max-age=300")
        if ext in COMPRESS and "gzip" in self.headers.get("Accept-Encoding", ""):
            body = gzip.compress(body, 6)
            self.send_header("Content-Encoding", "gzip")
            self.send_header("Vary", "Accept-Encoding")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if not head:
            self.wfile.write(body)


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
