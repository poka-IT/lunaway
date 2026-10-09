"""Serves the web build the way production does, to test it under the real
response headers.

    python3 tool/web/serve_csp.py --port 18793 --api https://api.lunaway.net/graphql

Reads infra/caddy/lunaway.net.caddy at start-up and replays, for every
response under /app/, the headers of the `lunaway.net` site block and of its
`handle_path /app/*` route (the Content-Security-Policy among them, and the
headers a named matcher sets, such as Cache-Control), the `redir /app /app/`,
and the route's fallback to index.html: `rewrite @matcher /index.html` with
the matchers Caddy evaluates (`path`, `path_regexp`, `file`, `not`), or the
older `try_files {path} /index.html`. A file the route serves by name and
does not have answers a bare 404, as the site's `handle_errors` does for
/app/. `file_server { precompressed br }` serves name.br to a browser that
accepts Brotli. The CSP is never copied here: when the Caddy file changes,
the test follows. A route directive or matcher this server cannot replay
stops it with an error rather than serve something production would not.

POST /graphql and /app/graphql are forwarded to --api from this process, so a
build made with --dart-define=LUNAWAY_API_URL=http://127.0.0.1:<port> reaches a
real API on its own origin: the CSP allows 'self', and the production API
answers browsers from https://lunaway.net only (CORS), which a request from
this server does not need. Every other GET outside /app/ goes to the API too
(the places' and points' tiles, the photos of /media/ and /external-photos/),
and the API's own address in its JSON answers and its redirects is replaced
by this server's: the API names itself in the URLs it hands out (a photo's
`thumbUrl`, the tiles of a TileJSON), and the app fetches a photo only from
its API's address (`ImageFetcher.accepts`), so without it such a build drew
every photo mark as a pictogram, with no request for the photo at all.

Standard library only. Tests: `python3 tool/web/test_serve_csp.py`.
"""

import argparse
import http.server
import os
import re
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

# The matchers this server evaluates; any other stops it.
MATCHERS = ("path", "path_regexp", "file")


def _tokens(text):
    """A Caddyfile line split as Caddy does: quotes group, and a backslash
    outside them is a plain character (a regular expression's `\\.`)."""
    lexer = shlex.shlex(text, posix=True)
    lexer.whitespace_split = True
    lexer.escape = ""
    lexer.commenters = ""
    return list(lexer)


def _inside(root, path):
    """The file [path] names under [root], or None when it would leave it."""
    rel = urllib.request.url2pathname(path.lstrip("/"))
    candidate = os.path.realpath(os.path.join(root, rel))
    if candidate != root and not candidate.startswith(root + os.sep):
        return None
    return candidate


def _path_pattern(pattern, path):
    """Caddy's `path` matcher: exact, or a prefix, a suffix or a substring
    around `*`, case-insensitively."""
    pattern, path = pattern.lower(), path.lower()
    if len(pattern) > 1 and pattern.startswith("*") and pattern.endswith("*"):
        return pattern[1:-1] in path
    if pattern.endswith("*"):
        return path.startswith(pattern[:-1])
    if pattern.startswith("*"):
        return path.endswith(pattern[1:])
    return path == pattern


def _condition(kind, args, path, root):
    if kind == "path":
        return any(_path_pattern(p, path) for p in args)
    if kind == "path_regexp":
        # An optional name comes before the expression.
        return re.search(args[-1], path) is not None
    # `file`: the request's own path names a file of the root, or a
    # directory when it ends with a slash.
    candidate = _inside(root, path)
    if candidate is None:
        return False
    return os.path.isdir(candidate) if path.endswith("/") else os.path.isfile(candidate)


def _parse_condition(tokens, where):
    """One matcher line, `[not] kind args...`, as (negated, kind, args)."""
    negated = bool(tokens) and tokens[0] == "not"
    if negated:
        tokens = tokens[1:]
    if not tokens or tokens[0] not in MATCHERS:
        raise SystemExit(f"serve_csp: {where}: cannot replay the matcher `{' '.join(tokens)}`")
    kind, args = tokens[0], tokens[1:]
    if kind == "path_regexp":
        if not args:
            raise SystemExit(f"serve_csp: {where}: path_regexp without an expression")
        re.compile(args[-1])
    if kind == "file" and args:
        raise SystemExit(f"serve_csp: {where}: cannot replay `file {' '.join(args)}`, only a bare `file`")
    return (negated, kind, args)


class Matcher:
    """A named matcher of the /app/ route: every condition holds. Its paths
    are the route's own, /app stripped by handle_path."""

    def __init__(self, name, conditions):
        self.name = name
        self.conditions = conditions  # [(negated, kind, args)]

    def matches(self, path, root):
        return all(_condition(kind, args, path, root) != negated for negated, kind, args in self.conditions)


class RouteConfig:
    """What the Caddy file says about responses under /app/."""

    def __init__(self, headers, removed, try_files, redirects, matched_headers=(), rewrites=(), precompressed=()):
        self.headers = headers  # [(name, value)], site block first, then the route
        self.removed = removed  # header names the site deletes (`header -Server`)
        self.try_files = try_files
        self.redirects = redirects  # {path: (target, status)}
        self.matched_headers = list(matched_headers)  # [(Matcher, name, value)], in file order
        self.rewrites = list(rewrites)  # [(Matcher, target)]
        self.precompressed = list(precompressed)  # ["br"]

    @property
    def csp(self):
        for name, value in self.headers:
            if name.lower() == "content-security-policy":
                return value
        raise SystemExit("serve_csp: the /app/ route sets no Content-Security-Policy")

    def headers_for(self, path, root):
        """The headers of a request for [path], as the route has it: Caddy
        runs `header` before `rewrite`, so its matchers see the request's
        own path. A matched header replaces an unconditional one of the
        same name."""
        matched = [(n, v) for m, n, v in self.matched_headers if m.matches(path, root)]
        names = {n.lower() for n, _ in matched}
        return [(n, v) for n, v in self.headers if n.lower() not in names] + matched

    def target(self, path, root):
        """The path file_server looks for: the first rewrite whose matcher
        holds, else try_files' fallback for a missing file, else [path]."""
        for matcher, target in self.rewrites:
            if matcher.matches(path, root):
                return target
        if self.try_files is not None:
            candidate = _inside(root, path)
            if candidate is None or not os.path.exists(candidate):
                return self.try_files[-1]
        return path


def load_route(caddyfile=DEFAULT_CADDYFILE):
    """Parses the site block of lunaway.net in the Caddy file."""
    site_headers, route_headers, removed, redirects = [], [], [], {}
    try_files = None
    matchers, matched_headers, rewrites, precompressed = {}, [], [], []
    stack = []
    with open(caddyfile, encoding="utf-8") as f:
        for number, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            here = f"{caddyfile}:{number}"
            if line == "}":
                stack.pop()
                continue
            opens = line.endswith("{")
            tokens = _tokens(line[:-1] if opens else line)
            where = tuple(stack)
            if opens:
                stack.append(" ".join(tokens))
                if where == (SITE, ROUTE):
                    if len(tokens) == 1 and tokens[0].startswith("@"):
                        matchers[tokens[0]] = Matcher(tokens[0], [])
                    elif tokens != ["file_server"]:
                        raise SystemExit(f"serve_csp: {here}: unknown block in the /app/ route: `{line}`")
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
            elif len(where) == 3 and where[:2] == (SITE, ROUTE) and where[2] in matchers:
                matchers[where[2]].conditions.append(_parse_condition(tokens, here))
            elif where == (SITE, ROUTE, "file_server"):
                if tokens[0] != "precompressed":
                    raise SystemExit(f"serve_csp: {here}: cannot replay `{line}` in file_server")
                precompressed.extend(tokens[1:])
            elif where == (SITE, ROUTE):
                if tokens[0].startswith("@"):
                    matchers[tokens[0]] = Matcher(tokens[0], [_parse_condition(tokens[1:], here)])
                elif tokens[0] == "header" and len(tokens) == 4 and tokens[1] in matchers:
                    matched_headers.append((matchers[tokens[1]], tokens[2], tokens[3]))
                elif tokens[0] == "header" and len(tokens) == 3 and not tokens[1].startswith(("@", "-")):
                    route_headers.append((tokens[1], tokens[2]))
                elif tokens[0] == "header":
                    raise SystemExit(f"serve_csp: {here}: cannot replay `{line}`")
                elif tokens[0] == "rewrite":
                    if len(tokens) != 3 or tokens[1] not in matchers:
                        raise SystemExit(f"serve_csp: {here}: cannot replay `{line}`, only `rewrite @matcher /path`")
                    rewrites.append((matchers[tokens[1]], tokens[2]))
                elif tokens[0] == "try_files":
                    try_files = tokens[1:]
                elif tokens[0] not in ("root", "file_server"):
                    raise SystemExit(f"serve_csp: {here}: unknown directive in the /app/ route: `{line}`")
    if try_files is not None and try_files != ["{path}", "/index.html"]:
        raise SystemExit(f"serve_csp: the /app/ route's try_files is {try_files}, this server replays {{path}} /index.html only")
    if try_files is None and not any(target == "/index.html" for _, target in rewrites):
        raise SystemExit("serve_csp: the /app/ route has no fallback to /index.html (a rewrite or try_files)")
    if not route_headers:
        raise SystemExit(f"serve_csp: no `{ROUTE}` block with headers in the `{SITE}` site of {caddyfile}")
    # A route header replaces a site header of the same name.
    names = {n.lower() for n, _ in route_headers}
    headers = [(n, v) for n, v in site_headers if n.lower() not in names] + route_headers
    return RouteConfig(headers, removed, try_files, redirects, matched_headers, rewrites, precompressed)


def api_base(api):
    """The API's base URL: the GraphQL endpoint --api names, without its
    `/graphql`."""
    return api[: -len("/graphql")] if api.endswith("/graphql") else api.rstrip("/")


# Answers whose body may name the API's address: the GraphQL answers and the
# TileJSON files. A tile or a photo is passed as it came.
JSON_TYPES = ("application/json", "application/graphql-response+json")

# The headers of an API answer passed on to the browser.
PASSED = ("Content-Type", "Cache-Control", "Retry-After", "ETag", "Last-Modified")


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """The browser follows the API's redirects itself, to this server."""

    def redirect_request(self, *args, **kwargs):
        return None


def make_handler(root, route, api):
    root = os.path.realpath(root)
    base = api_base(api) if api else None
    upstream = urllib.request.build_opener(_NoRedirect)

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

        def _send(self, code, body, content_type, head_only=False, headers=None, encoding=None):
            self.send_response(code)
            for name, value in route.headers if headers is None else headers:
                self.send_header(name, value)
            self.send_header("Content-Type", content_type)
            if encoding:
                self.send_header("Content-Encoding", encoding)
                self.send_header("Vary", "Accept-Encoding")
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
                if base:
                    self._forward_get(head_only)
                else:
                    self._send(404, b"not found\n", "text/plain; charset=utf-8", head_only)
                return
            # handle_path strips the prefix: the headers match the path asked
            # for, then the rewrite picks the file.
            own = path[len("/app"):]
            headers = route.headers_for(own, root)
            candidate = _inside(root, route.target(own, root))
            if candidate is not None and os.path.isdir(candidate):
                candidate = os.path.join(candidate, "index.html")
            if candidate is None or not os.path.isfile(candidate):
                # A file asked for by name and missing (a fallback font):
                # the site's handle_errors answers an empty 404.
                self._send(404, b"", "text/plain; charset=utf-8", head_only, headers)
                return
            ext = os.path.splitext(candidate)[1].lower()
            accepted = {e.split(";")[0].strip() for e in (self.headers.get("Accept-Encoding") or "").split(",")}
            encoding = None
            if "br" in route.precompressed and "br" in accepted and os.path.isfile(candidate + ".br"):
                candidate, encoding = candidate + ".br", "br"
            with open(candidate, "rb") as f:
                body = f.read()
            self._send(200, body, TYPES.get(ext, "application/octet-stream"), head_only, headers, encoding)

        def _origin(self):
            """This server's address as the browser named it."""
            return f"http://{self.headers.get('Host') or '127.0.0.1:%d' % self.server.server_address[1]}"

        def _local(self, content, kind):
            """[content] with the API's address replaced by this server's, in
            a JSON answer only."""
            if (kind or "").split(";")[0].strip().lower() not in JSON_TYPES:
                return content
            return content.replace(base.encode(), self._origin().encode())

        def _forward_get(self, head_only):
            # A target that is no path would join the API's address into
            # another host's (`@host/x`).
            if not self.path.startswith("/"):
                self._send(400, b"bad request\n", "text/plain; charset=utf-8", head_only, [])
                return
            # A HEAD is asked as a GET: its length is that of the body
            # rewritten.
            request = urllib.request.Request(base + self.path, headers={
                "Accept": self.headers.get("Accept", "*/*"),
                "User-Agent": USER_AGENT,
            })
            try:
                with upstream.open(request, timeout=60) as answer:
                    status, headers, content = answer.status, answer.headers, answer.read()
            except urllib.error.HTTPError as e:
                with e:
                    status, headers, content = e.code, e.headers, e.read()
            except OSError as e:
                self._send(502, f"proxy error: {e}\n".encode(), "text/plain; charset=utf-8", head_only, [])
                return
            content = self._local(content, headers.get("Content-Type"))
            self.send_response(status)
            for name in PASSED:
                if headers.get(name):
                    self.send_header(name, headers[name])
            if location := headers.get("Location"):
                if location.startswith(base):
                    location = self._origin() + location[len(base):]
                self.send_header("Location", location)
            self.send_header("Content-Length", str(len(content)))
            try:
                self.end_headers()
                if not head_only:
                    self.wfile.write(content)
            except (BrokenPipeError, ConnectionResetError):
                # The map cancels the tiles it no longer shows while the
                # API answers them.
                pass

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
            content = self._local(content, kind)
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
    p.add_argument("--api", help="GraphQL endpoint that POST /graphql is forwarded to; the other API paths go to its host")
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
