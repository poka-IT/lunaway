"""Tests of serve_csp.py against the Caddy file in infra/ and small ones of
its own: the headers, the fallback to index.html and the 404s the
production route gives.

    python3 tool/web/test_serve_csp.py

Standard library only.
"""

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

    def __init__(self, caddyfile=serve_csp.DEFAULT_CADDYFILE):
        self.dir = tempfile.TemporaryDirectory()
        _build(self.dir.name)
        self.server = serve_csp.make_server(0, self.dir.name, caddyfile)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def get(self, path, headers=None):
        """(status, headers, body); a redirect is not followed."""

        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs):
                return None

        opener = urllib.request.build_opener(NoRedirect)
        request = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", headers=headers or {})
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
