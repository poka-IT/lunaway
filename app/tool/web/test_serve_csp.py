"""Tests of serve_csp.py against the Caddy file in infra/ and small ones of
its own: the headers, the fallback to index.html and the 404s the
production route gives.

    python3 tool/web/test_serve_csp.py

Standard library only.
"""

import http.server
import json
import os
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import serve_csp  # noqa: E402

HASH = "0123456789ab"


def _build(root):
    """A web build in miniature: the page, a fingerprinted script, an asset,
    the engine's directory and a Brotli copy of the page."""
    files = {
        "index.html": b"<!doctype html><title>app</title>",
        "index.html.br": b"brotli bytes",
        f"main.dart.{HASH}.js": b"// main",
        "flutter_service_worker.js": b"// worker",
        "assets/AssetManifest.json": b"{}",
        f"canvaskit-{HASH}/canvaskit.wasm": b"\0asm",
    }
    for name, body in files.items():
        path = os.path.join(root, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(body)


class _Served:
    """serve_csp on a free port over a build in a temporary directory."""

    def __init__(self, caddyfile=serve_csp.DEFAULT_CADDYFILE, api=None):
        self.dir = tempfile.TemporaryDirectory()
        _build(self.dir.name)
        self.server = serve_csp.make_server(0, self.dir.name, caddyfile, api)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    @property
    def origin(self):
        return f"http://127.0.0.1:{self.port}"

    def get(self, path, headers=None, data=None):
        """(status, headers, body); a redirect is not followed. With [data],
        a POST."""

        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs):
                return None

        opener = urllib.request.build_opener(NoRedirect)
        request = urllib.request.Request(f"{self.origin}{path}", headers=headers or {}, data=data)
        try:
            with opener.open(request, timeout=10) as r:
                return r.status, r.headers, r.read()
        except urllib.error.HTTPError as e:
            with e:
                return e.code, e.headers, e.read()

    def close(self):
        self.server.shutdown()
        self.server.server_close()
        self.dir.cleanup()


class TheProductionRoute(unittest.TestCase):
    """infra/caddy/lunaway.net.caddy as it is."""

    @classmethod
    def setUpClass(cls):
        cls.served = _Served()

    @classmethod
    def tearDownClass(cls):
        cls.served.close()

    def test_the_caddy_file_loads_with_its_csp(self):
        route = serve_csp.load_route()
        self.assertIn("default-src 'self'", route.csp)
        self.assertTrue(route.rewrites, "the rewrite to index.html is replayed")

    def test_an_app_route_falls_back_to_the_page_revalidated(self):
        status, headers, body = self.served.get("/app/place/42")
        self.assertEqual(status, 200)
        self.assertIn(b"<title>app</title>", body)
        self.assertEqual(headers["Cache-Control"], "no-cache")
        self.assertIn("default-src 'self'", headers["Content-Security-Policy"])
        self.assertIsNone(headers["Server"])

    def test_a_fingerprinted_file_is_cached_for_a_year(self):
        status, headers, body = self.served.get(f"/app/main.dart.{HASH}.js")
        self.assertEqual(status, 200)
        self.assertEqual(body, b"// main")
        self.assertEqual(headers["Cache-Control"], "public, max-age=31536000, immutable")
        status, headers, _ = self.served.get(f"/app/canvaskit-{HASH}/canvaskit.wasm")
        self.assertEqual(status, 200)
        self.assertEqual(headers["Content-Type"], "application/wasm")
        self.assertEqual(headers["Cache-Control"], "public, max-age=31536000, immutable")

    def test_another_file_is_revalidated(self):
        status, headers, _ = self.served.get("/app/flutter_service_worker.js")
        self.assertEqual(status, 200)
        self.assertEqual(headers["Cache-Control"], "no-cache")

    def test_a_missing_file_asked_by_name_is_a_bare_404(self):
        for path in ("/app/fonts/NotoSans.ttf", "/app/assets/missing.json", "/app/missing.js", "/app/icons/x"):
            status, _, body = self.served.get(path)
            self.assertEqual(status, 404, path)
            self.assertEqual(body, b"", path)

    def test_the_bare_app_path_redirects(self):
        status, headers, _ = self.served.get("/app")
        self.assertEqual(status, 301)
        self.assertEqual(headers["Location"], "/app/")

    def test_a_brotli_copy_goes_to_a_browser_that_accepts_it(self):
        status, headers, body = self.served.get("/app/", {"Accept-Encoding": "gzip, br"})
        self.assertEqual(status, 200)
        self.assertEqual(headers["Content-Encoding"], "br")
        self.assertEqual(body, b"brotli bytes")
        status, headers, body = self.served.get("/app/", {"Accept-Encoding": "gzip"})
        self.assertIsNone(headers["Content-Encoding"])
        self.assertIn(b"<title>app</title>", body)


class _FakeApi:
    """An API on a free port that names itself in its answers, as the real
    one does (`LUNAWAY_PUBLIC_URL`): a GraphQL answer with a photo's URL, a
    TileJSON, a tile, an external photo's redirect to its copy, the copy."""

    WEBP = b"RIFF\x10\x00\x00\x00WEBPVP8 "

    def __init__(self):
        api = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, fmt, *args):
                pass

            def _answer(self, status, kind, body, headers=()):
                self.send_response(status)
                self.send_header("Content-Type", kind)
                for name, value in headers:
                    self.send_header(name, value)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(body)

            def do_GET(self):
                me = api.origin
                if self.path == "/places/tiles.json":
                    body = json.dumps({"tiles": [f"{me}/places/7/{{z}}/{{x}}/{{y}}.mvt"]}).encode()
                    self._answer(200, "application/json", body, [("Cache-Control", "public, max-age=60")])
                elif self.path == "/places/7/14/8404/5926.mvt":
                    # A tile's bytes may hold any text, the API's address included.
                    self._answer(200, "application/vnd.mapbox-vector-tile", b"\x1a\x02" + me.encode())
                elif self.path == f"/external-photos/{PHOTO}/thumb":
                    self._answer(302, "text/plain", b"", [("Location", f"{me}/media/photos/ab/cd/x.webp")])
                elif self.path == "/media/photos/ab/cd/x.webp":
                    self._answer(200, "image/webp", api.WEBP, [("Cache-Control", "public, max-age=31536000, immutable")])
                elif self.path == "/media/photos/none.webp":
                    self._answer(404, "text/plain", b"", [("Retry-After", "3")])
                else:
                    self._answer(404, "text/plain", b"not found\n")

            def do_HEAD(self):
                self.do_GET()

            def do_POST(self):
                self.rfile.read(int(self.headers.get("Content-Length") or 0))
                body = json.dumps({"data": {"t0": {"externalPhotos": [
                    {"thumbUrl": f"{api.origin}/external-photos/{PHOTO}/thumb"},
                    {"thumbUrl": f"{api.origin}/media/photos/ab/cd/x.webp"},
                ]}}}).encode()
                self._answer(200, "application/json", body)

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.origin = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()


PHOTO = "01a11893-6c29-71b2-a283-2426b26c8b7d"


class TheApiOnTheSameOrigin(unittest.TestCase):
    """A build whose LUNAWAY_API_URL is this server gets what the production
    build gets from the API, on its own origin."""

    @classmethod
    def setUpClass(cls):
        cls.api = _FakeApi()
        cls.served = _Served(api=f"{cls.api.origin}/graphql")

    @classmethod
    def tearDownClass(cls):
        cls.served.close()
        cls.api.close()

    def test_a_photo_url_in_a_graphql_answer_names_this_server(self):
        status, _, body = self.served.get("/graphql", {"Content-Type": "application/json"}, b"{}")
        self.assertEqual(status, 200)
        urls = [p["thumbUrl"] for p in json.loads(body)["data"]["t0"]["externalPhotos"]]
        self.assertEqual(urls, [
            f"{self.served.origin}/external-photos/{PHOTO}/thumb",
            f"{self.served.origin}/media/photos/ab/cd/x.webp",
        ])

    def test_the_tiles_come_through_this_server(self):
        status, headers, body = self.served.get("/places/tiles.json")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["tiles"], [f"{self.served.origin}/places/7/{{z}}/{{x}}/{{y}}.mvt"])
        self.assertEqual(headers["Cache-Control"], "public, max-age=60")
        status, headers, body = self.served.get("/places/7/14/8404/5926.mvt")
        self.assertEqual(status, 200)
        self.assertEqual(headers["Content-Type"], "application/vnd.mapbox-vector-tile")
        self.assertEqual(body, b"\x1a\x02" + self.api.origin.encode(), "a tile is passed as it came")

    def test_an_external_photo_redirects_to_its_copy_on_this_server(self):
        status, headers, _ = self.served.get(f"/external-photos/{PHOTO}/thumb")
        self.assertEqual(status, 302)
        self.assertEqual(headers["Location"], f"{self.served.origin}/media/photos/ab/cd/x.webp")
        status, headers, body = self.served.get("/media/photos/ab/cd/x.webp")
        self.assertEqual(status, 200)
        self.assertEqual(headers["Content-Type"], "image/webp")
        self.assertEqual(body, _FakeApi.WEBP)

    def test_a_refusal_of_the_api_keeps_its_status_and_its_wait(self):
        status, headers, _ = self.served.get("/media/photos/none.webp")
        self.assertEqual(status, 404)
        self.assertEqual(headers["Retry-After"], "3")

    def test_the_app_still_comes_from_the_build(self):
        status, _, body = self.served.get("/app/place/42")
        self.assertEqual(status, 200)
        self.assertIn(b"<title>app</title>", body)


class WithoutAnApi(unittest.TestCase):
    def test_a_path_outside_the_app_is_not_found(self):
        served = _Served()
        try:
            status, _, _ = served.get("/places/tiles.json")
            self.assertEqual(status, 404)
        finally:
            served.close()


def _caddyfile(route_body):
    """A Caddy file whose lunaway.net site holds [route_body] in its /app/ route."""
    f = tempfile.NamedTemporaryFile("w", suffix=".caddy", delete=False, encoding="utf-8")
    f.write(
        "lunaway.net {\n"
        "\theader -Server\n"
        "\thandle_path /app/* {\n"
        "\t\troot * /srv/lunaway/web\n"
        "\t\theader Content-Security-Policy \"default-src 'self'\"\n"
        f"{route_body}"
        "\t}\n"
        "}\n"
    )
    f.close()
    return f.name


class OtherRoutes(unittest.TestCase):
    def tearDown(self):
        for path in getattr(self, "files", []):
            os.unlink(path)

    def _file(self, body):
        path = _caddyfile(body)
        self.files = [*getattr(self, "files", []), path]
        return path

    def test_the_older_try_files_still_replays(self):
        served = _Served(self._file("\t\ttry_files {path} /index.html\n\t\tfile_server\n"))
        try:
            status, _, body = served.get("/app/fonts/missing.ttf")
            self.assertEqual(status, 200)
            self.assertIn(b"<title>app</title>", body)
        finally:
            served.close()

    def test_a_directive_it_cannot_replay_stops_it(self):
        path = self._file("\t\treverse_proxy 127.0.0.1:9\n\t\ttry_files {path} /index.html\n")
        with self.assertRaises(SystemExit):
            serve_csp.load_route(path)

    def test_a_matcher_it_cannot_replay_stops_it(self):
        path = self._file("\t\t@m header Accept text/html\n\t\trewrite @m /index.html\n")
        with self.assertRaises(SystemExit):
            serve_csp.load_route(path)

    def test_a_route_without_a_fallback_stops_it(self):
        with self.assertRaises(SystemExit):
            serve_csp.load_route(self._file("\t\tfile_server\n"))


if __name__ == "__main__":
    unittest.main()
