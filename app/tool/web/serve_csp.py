"""Serves the web build the way production does, to test it under the real
response headers.

    python3 tool/web/serve_csp.py --port 18793 --api https://api.lunaway.net/graphql

Reads infra/caddy/lunaway.net.caddy at start-up and replays, for every
response under /app/, the headers of the `lunaway.net` site block and of its
`handle_path /app/*` route (the Content-Security-Policy among them), the
`redir /app /app/` and the `try_files {path} /index.html` fallback. The CSP is
never copied here: when the Caddy file changes, the test follows. A route
directive this server cannot replay stops it with an error rather than serve
something production would not.

POST /graphql and /app/graphql are forwarded to --api from this process, so a
build made with --dart-define=LUNAWAY_API_URL=http://127.0.0.1:<port> reaches a
real API on its own origin: the CSP allows 'self', and the production API
answers browsers from https://lunaway.net only (CORS), which a request from
this server does not need.

Standard library only.
"""

import argparse
import http.server
import os
import shlex
import sys
import urllib.error
import urllib.request

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
DEFAULT_CADDYFILE = os.path.join(REPO, "infra", "caddy", "lunaway.net.caddy")
DEFAULT_ROOT = os.path.join(REPO, "app", "build", "web")
SITE = "lunaway.net"
ROUTE = "handle_path /app/*"
USER_AGENT = "Lunaway web CSP check (+https://lunaway.net)"

# The types Caddy's file_server sends for the files of a Flutter web build.
# WebAssembly must be application/wasm for streaming compilation.
TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8",
    ".json": "application/json",
    ".wasm": "application/wasm",
    ".css": "text/css; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".ico": "image/x-icon",
    ".woff2": "font/woff2",
    ".ttf": "font/ttf",
    ".otf": "font/otf",
    ".txt": "text/plain; charset=utf-8",
    ".bin": "application/octet-stream",
    ".frag": "application/octet-stream",
}


class RouteConfig:
    """What the Caddy file says about responses under /app/."""

    def __init__(self, headers, removed, try_files, redirects):
        self.headers = headers  # [(name, value)], site block first, then the route
        self.removed = removed  # header names the site deletes (`header -Server`)
        self.try_files = try_files
        self.redirects = redirects  # {path: (target, status)}

    @property
    def csp(self):
        for name, value in self.headers:
            if name.lower() == "content-security-policy":
                return value
        raise SystemExit("serve_csp: the /app/ route sets no Content-Security-Policy")


def load_route(caddyfile=DEFAULT_CADDYFILE):
    """Parses the site block of lunaway.net in the Caddy file."""
    site_headers, route_headers, removed, redirects = [], [], [], {}
    try_files = None
    stack = []
    with open(caddyfile, encoding="utf-8") as f:
        for number, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line == "}":
                stack.pop()
                continue
            opens = line.endswith("{")
            tokens = shlex.split(line[:-1] if opens else line)
            where = tuple(stack)
            if opens:
                stack.append(" ".join(tokens))
                continue
            if where == (SITE, "header"):
                site_headers.append((tokens[0], tokens[1]))
            elif where == (SITE,) and tokens[0] == "header":
                if len(tokens) == 2 and tokens[1].startswith("-"):
                    removed.append(tokens[1][1:])
                else:
                    site_headers.append((tokens[1], tokens[2]))
            elif where == (SITE,) and tokens[0] == "redir":
                status = {"permanent": 301, "temporary": 302}.get(tokens[3] if len(tokens) > 3 else "", 302)
                redirects[tokens[1]] = (tokens[2], status)
            elif where == (SITE, ROUTE):
                if tokens[0] == "header":
                    if tokens[1].startswith("@") or len(tokens) != 3:
                        raise SystemExit(f"serve_csp: {caddyfile}:{number}: cannot replay `{line}`")
                    route_headers.append((tokens[1], tokens[2]))
                elif tokens[0] == "try_files":
                    try_files = tokens[1:]
                elif tokens[0] not in ("root", "file_server"):
                    raise SystemExit(f"serve_csp: {caddyfile}:{number}: unknown directive in the /app/ route: `{line}`")
    if try_files != ["{path}", "/index.html"]:
        raise SystemExit(f"serve_csp: the /app/ route's try_files is {try_files}, this server replays {{path}} /index.html only")
    if not route_headers:
        raise SystemExit(f"serve_csp: no `{ROUTE}` block with headers in the `{SITE}` site of {caddyfile}")
    # A route header replaces a site header of the same name.
    names = {n.lower() for n, _ in route_headers}
    headers = [(n, v) for n, v in site_headers if n.lower() not in names] + route_headers
    return RouteConfig(headers, removed, try_files, redirects)


def make_handler(root, route, api):
    root = os.path.realpath(root)

    class Handler(http.server.BaseHTTPRequestHandler):
        server_version = ""
        sys_version = ""

        def log_message(self, fmt, *args):
            if os.environ.get("SERVE_CSP_VERBOSE"):
                sys.stderr.write("serve_csp: " + (fmt % args) + "\n")

        # Caddy drops its Server header on this site (`header -Server`).
        def send_response(self, code, message=None):
            self.log_request(code)
            self.send_response_only(code, message)
            if "Server" not in route.removed:
                self.send_header("Server", "serve_csp")
            self.send_header("Date", self.date_time_string())

        def _route_headers(self):
            for name, value in route.headers:
                self.send_header(name, value)

        def _send(self, code, body, content_type, head_only=False):
            self.send_response(code)
            self._route_headers()
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if not head_only:
                self.wfile.write(body)

        def _static(self, head_only):
            path = self.path.split("?", 1)[0].split("#", 1)[0]
            if path in route.redirects:
                target, status = route.redirects[path]
                self.send_response(status)
                self.send_header("Location", target)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if not path.startswith("/app/"):
                self._send(404, b"not found\n", "text/plain; charset=utf-8", head_only)
                return
            # handle_path strips the prefix; try_files {path} /index.html.
            rel = urllib.request.url2pathname(path[len("/app/"):])
            candidate = os.path.realpath(os.path.join(root, rel))
            if not candidate.startswith(root + os.sep) and candidate != root:
                self._send(404, b"not found\n", "text/plain; charset=utf-8", head_only)
                return
            if os.path.isdir(candidate):
                candidate = os.path.join(candidate, "index.html")
            if not os.path.isfile(candidate):
                candidate = os.path.join(root, "index.html")
            with open(candidate, "rb") as f:
                body = f.read()
            ext = os.path.splitext(candidate)[1].lower()
            self._send(200, body, TYPES.get(ext, "application/octet-stream"), head_only)

        def do_GET(self):
            self._static(head_only=False)

        def do_HEAD(self):
            self._static(head_only=True)

        def do_POST(self):
            path = self.path.split("?", 1)[0]
            if path not in ("/graphql", "/app/graphql") or not api:
                self._send(404, b"not found\n", "text/plain; charset=utf-8")
                return
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length)
            request = urllib.request.Request(api, data=body, method="POST", headers={
                "Content-Type": self.headers.get("Content-Type", "application/json"),
                "Accept": self.headers.get("Accept", "application/json"),
                "User-Agent": USER_AGENT,
            })
            try:
                with urllib.request.urlopen(request, timeout=60) as upstream:
                    status, content, kind = upstream.status, upstream.read(), upstream.headers.get("Content-Type")
                    retry_after = upstream.headers.get("Retry-After")
            except urllib.error.HTTPError as e:
                status, content, kind = e.code, e.read(), e.headers.get("Content-Type")
                retry_after = e.headers.get("Retry-After")
            except OSError as e:
                status, content, kind, retry_after = 502, f"proxy error: {e}\n".encode(), "text/plain; charset=utf-8", None
            self.send_response(status)
            self.send_header("Content-Type", kind or "application/json")
            self.send_header("Content-Length", str(len(content)))
            if retry_after:
                self.send_header("Retry-After", retry_after)
            self.end_headers()
            self.wfile.write(content)

    return Handler


def make_server(port, root=DEFAULT_ROOT, caddyfile=DEFAULT_CADDYFILE, api=None, host="127.0.0.1"):
    """A server ready for serve_forever(); the caller shuts it down."""
    if not os.path.isfile(os.path.join(root, "index.html")):
        raise SystemExit(f"serve_csp: no web build in {root} (fvm flutter build web --release --base-href /app/ --no-web-resources-cdn)")
    route = load_route(caddyfile)
    server = http.server.ThreadingHTTPServer((host, port), make_handler(root, route, api))
    server.daemon_threads = True
    server.route = route
    return server


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--port", type=int, default=18793)
    p.add_argument("--root", default=DEFAULT_ROOT, help="the web build (app/build/web)")
    p.add_argument("--caddyfile", default=DEFAULT_CADDYFILE)
    p.add_argument("--api", help="GraphQL endpoint that POST /graphql is forwarded to")
    args = p.parse_args()
    server = make_server(args.port, args.root, args.caddyfile, args.api)
    print(f"serve_csp: http://127.0.0.1:{args.port}/app/ from {args.root}")
    for name, value in server.route.headers:
        print(f"  {name}: {value}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
