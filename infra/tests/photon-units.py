"""Tests of the start of the two Photon instances (infra/geocode,
infra/server/geocode.sh), on any machine with bash and curl.

    python3 infra/tests/photon-units.py

Each instance's embedded OpenSearch takes the first HTTP port from 9201 that
nothing answers on, and binds it seconds later: started together, both took
9201 and the second failed (2026-10-10 and 2026-10-11, docs/deploy.md,
"Photon on the server"). So:

1. the instances have distinct Photon ports, inside what their unit may
   bind;
2. a unit is active only once its Photon answers (ExecStartPost=
   lunaway-photon-ready), within its start timeout, and Morocco is ordered
   after Europe, both files installed where the unit reads them;
3. lunaway-photon-ready waits for an answer, and gives up past its limit,
   on a refused connection or an error status alike.
"""

import pathlib
import re
import socket
import subprocess
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

INFRA = pathlib.Path(__file__).resolve().parent.parent
UNIT = INFRA / "geocode" / "photon@.service"
DROP_IN = INFRA / "geocode" / "photon@morocco.service.d" / "after-europe.conf"
READY = INFRA / "geocode" / "lunaway-photon-ready"
GEOCODE = INFRA / "server" / "geocode.sh"


def span_s(text):
    """A systemd time span of the forms the unit uses, in seconds."""
    m = re.fullmatch(r"(\d+)\s*(s|min)?", text.strip())
    if not m:
        raise ValueError(f"unreadable time span {text!r}")
    return int(m.group(1)) * (60 if m.group(2) == "min" else 1)


def ports_written():
    """The PHOTON_PORT geocode.sh writes for each instance."""
    found = re.findall(r"printf 'PHOTON_PORT=(\d+)\\n[^']*' > \"\$STAGING/(\w+)\.env\"", GEOCODE.read_text())
    return {instance: int(port) for port, instance in found}


def bind_ranges():
    """The TCP ports photon@.service allows its processes to bind."""
    ranges = []
    for low, high in re.findall(r"^SocketBindAllow=tcp:(\d+)-(\d+)$", UNIT.read_text(), re.M):
        ranges.append((int(low), int(high)))
    return ranges


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Status(BaseHTTPRequestHandler):
    """/status answers the server's `code`, after its `ready_at`."""

    def do_GET(self):  # noqa: N802 (the handler's name)
        if time.monotonic() < self.server.ready_at:
            self.send_response(503)
        else:
            self.send_response(self.server.code)
        self.end_headers()
        self.wfile.write(b'{"status":"Ok"}')

    def log_message(self, *_):
        pass


def serve(port, ready_after_s, code=200):
    server = ThreadingHTTPServer(("127.0.0.1", port), Status)
    server.ready_at = time.monotonic() + ready_after_s
    server.code = code
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def ready(port, limit_s):
    started = time.monotonic()
    done = subprocess.run(["bash", str(READY), str(port), str(limit_s)], capture_output=True, text=True)
    return done.returncode, time.monotonic() - started


class Units(unittest.TestCase):
    def test_each_instance_has_its_own_photon_port_inside_what_it_may_bind(self):
        ports = ports_written()
        self.assertEqual(set(ports), {"europe", "morocco"}, "geocode.sh writes both instances' ports")
        self.assertNotEqual(ports["europe"], ports["morocco"], "two instances on one port: one fails to start")
        for instance, port in ports.items():
            self.assertTrue(
                any(low <= port <= high for low, high in bind_ranges()),
                f"{instance}'s port {port} is outside SocketBindAllow=",
            )

    def test_a_unit_is_active_once_photon_answers_within_its_start_timeout(self):
        text = UNIT.read_text()
        post = re.findall(r"^ExecStartPost=(\S+) \$\{PHOTON_PORT\} (\d+)$", text, re.M)
        self.assertEqual(len(post), 1, "one readiness wait, on the instance's own port")
        path, limit = post[0]
        self.assertEqual(path, "/usr/local/sbin/lunaway-photon-ready")
        timeout = re.findall(r"^TimeoutStartSec=(.+)$", text, re.M)
        self.assertLess(
            int(limit),
            span_s(timeout[-1]),
            "the wait gives up before systemd kills it, so the journal says why",
        )
        geocode = GEOCODE.read_text()
        self.assertIn("install_file geocode/lunaway-photon-ready /usr/local/sbin/lunaway-photon-ready 0755", geocode)

    def test_morocco_starts_after_europe_and_the_order_is_installed(self):
        self.assertRegex(DROP_IN.read_text(), r"(?m)^\[Unit\]\nAfter=photon@europe\.service$")
        self.assertIn(
            '"/etc/systemd/system/photon@morocco.service.d/after-europe.conf" 0644',
            GEOCODE.read_text(),
            "geocode.sh installs the order where systemd reads photon@morocco's drop-ins",
        )
        self.assertNotIn("After=photon@", UNIT.read_text(), "in the template, Europe would be ordered after itself")


class Ready(unittest.TestCase):
    def test_it_waits_for_photon_to_answer(self):
        port = free_port()
        server = serve(port, ready_after_s=1.5)
        try:
            code, took = ready(port, 10)
        finally:
            server.shutdown()
        self.assertEqual(code, 0)
        self.assertGreaterEqual(took, 1.4, "not before Photon answers")
        self.assertLess(took, 4.0, "soon after it answers")

    def test_it_gives_up_past_its_limit_when_nothing_listens(self):
        code, took = ready(free_port(), 3)
        self.assertEqual(code, 1)
        # Bash counts whole seconds: the limit holds to one.
        self.assertGreaterEqual(took, 2.0)
        self.assertLess(took, 5.0)

    def test_an_error_status_is_no_answer(self):
        port = free_port()
        server = serve(port, ready_after_s=0, code=503)
        try:
            code, _ = ready(port, 2)
        finally:
            server.shutdown()
        self.assertEqual(code, 1, "an error status is no answer")

    def test_a_port_that_is_no_number_is_refused(self):
        for args in (["x"], [], ["2322", "soon"]):
            done = subprocess.run(["bash", str(READY), *args], capture_output=True, text=True)
            self.assertEqual(done.returncode, 2, args)


if __name__ == "__main__":
    unittest.main()
