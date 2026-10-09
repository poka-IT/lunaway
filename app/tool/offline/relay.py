"""A local relay in front of the API and the basemap host, for device tests.

    python3 app/tool/offline/relay.py      (aiohttp)

A simulator shares the computer's network and has no airplane mode: the
relay stands for the network instead. It listens on 127.0.0.1:18781 (the
API, upstream https://api.lunaway.net) and 127.0.0.1:18782 (the basemap,
upstream https://tiles.lunaway.net), for an app built with
`--dart-define=LUNAWAY_API_URL=http://127.0.0.1:18781` and
`--dart-define=LUNAWAY_BASEMAP_URL=http://127.0.0.1:18782` (10.0.2.2 for
the Android emulator, whose debug builds allow it). An iOS build needs
`NSAllowsLocalNetworking` in its Info.plist for MapLibre's requests. The
control port, 127.0.0.1:18790, answers:

    /online          listen again
    /offline         stop listening (connections refused) and cut the
                     transfers under way, as a phone loses its network
    /shape?down_kbps=20000&up_kbps=5000&rtt_ms=50   a simulated link: one
                     bucket of bytes shared by every transfer, and the
                     round trip added once per request
    /noshape         full speed
    /state           what is set
    /shot?name=x     a screenshot of the booted iOS simulator, in
                     LUNAWAY_SHOTS (data/tmp/shots by default)
    /mark?what=x     a line of the caller's in the log

Every upstream URL of the two hosts in a text answer is rewritten to the
relay as the client named it (Host header), so a pack, a tile or a photo
goes through the relay too. One line per request in data/tmp/relay.log:
time, port, method, path, status, bytes, seconds.
`integration_test/offline_tour_test.dart` drives it.
"""

import asyncio
import gzip
import json
import os
import time

import aiohttp
from aiohttp import web

HERE = os.path.dirname(os.path.abspath(__file__))
# data/tmp of the checkout, which git ignores.
SCRATCH = os.path.normpath(os.path.join(HERE, "..", "..", "..", "data", "tmp"))
SHOTS = os.environ.get("LUNAWAY_SHOTS", os.path.join(SCRATCH, "shots"))
os.makedirs(SCRATCH, exist_ok=True)
LOG = open(os.path.join(SCRATCH, "relay.log"), "a", buffering=1)

UPSTREAMS = {
    18781: "https://api.lunaway.net",
    18782: "https://tiles.lunaway.net",
}
CONTROL = 18790

state = {"online": True, "down_kbps": 0, "up_kbps": 0, "rtt_ms": 0}
sites = {}
runners = {}
active = set()
session: aiohttp.ClientSession | None = None


class Bucket:
    """One link shared by every transfer: bytes per second, refilled continuously."""

    def __init__(self):
        self.tokens = 0.0
        self.at = time.monotonic()
        self.lock = asyncio.Lock()

    async def take(self, n, rate):
        if rate <= 0:
            return
        async with self.lock:
            while True:
                now = time.monotonic()
                self.tokens = min(rate * 0.25, self.tokens + (now - self.at) * rate)
                self.at = now
                if self.tokens >= n:
                    self.tokens -= n
                    return
                await asyncio.sleep((n - self.tokens) / rate)


down = Bucket()
up = Bucket()


def rewrite(text, host_of):
    for port, upstream in UPSTREAMS.items():
        text = text.replace(upstream, f"http://{host_of(port)}")
    return text


async def handle(request: web.Request):
    port = request.transport.get_extra_info("sockname")[1]
    upstream = UPSTREAMS[port]
    started = time.monotonic()
    client_host = request.headers.get("Host", f"127.0.0.1:{port}").rsplit(":", 1)[0]

    def host_of(p):
        return f"{client_host}:{p}"

    body = await request.read()
    rtt = state["rtt_ms"] / 1000
    if rtt:
        await asyncio.sleep(rtt)
    if body:
        await up.take(len(body), state["up_kbps"] * 125)
    headers = {
        k: v
        for k, v in request.headers.items()
        if k.lower() not in ("host", "accept-encoding", "content-length", "connection")
    }
    headers["Accept-Encoding"] = "identity"
    task = asyncio.current_task()
    active.add(task)
    sent = 0
    status = 0
    try:
        async with session.request(
            request.method,
            upstream + request.path_qs,
            headers=headers,
            data=body or None,
            allow_redirects=False,
        ) as up_resp:
            status = up_resp.status
            ctype = up_resp.headers.get("Content-Type", "")
            out_headers = {
                k: v
                for k, v in up_resp.headers.items()
                if k.lower()
                not in ("content-length", "transfer-encoding", "content-encoding", "connection", "strict-transport-security")
            }
            if "Location" in out_headers:
                out_headers["Location"] = rewrite(out_headers["Location"], host_of)
            textual = "json" in ctype or ctype.startswith("text/") or "javascript" in ctype
            if textual:
                raw = await up_resp.read()
                # A host that compresses whatever was asked.
                if up_resp.headers.get("Content-Encoding", "").lower() == "gzip":
                    raw = gzip.decompress(raw)
                data = rewrite(raw.decode("utf-8", "replace"), host_of).encode()
                if "gzip" in request.headers.get("Accept-Encoding", "") and len(data) > 512:
                    data = gzip.compress(data, 6)
                    out_headers["Content-Encoding"] = "gzip"
                resp = web.StreamResponse(status=status, headers=out_headers)
                resp.content_length = len(data)
                await resp.prepare(request)
                for i in range(0, len(data), 16384):
                    chunk = data[i : i + 16384]
                    await down.take(len(chunk), state["down_kbps"] * 125)
                    await resp.write(chunk)
                    sent += len(chunk)
                await resp.write_eof()
                return resp
            # Passed through as sent: compressed tiles stay compressed.
            if "Content-Encoding" in up_resp.headers:
                out_headers["Content-Encoding"] = up_resp.headers["Content-Encoding"]
            resp = web.StreamResponse(status=status, headers=out_headers)
            length = up_resp.headers.get("Content-Length")
            if length is not None:
                resp.content_length = int(length)
            await resp.prepare(request)
            async for chunk in up_resp.content.iter_chunked(16384):
                await down.take(len(chunk), state["down_kbps"] * 125)
                await resp.write(chunk)
                sent += len(chunk)
            await resp.write_eof()
            return resp
    finally:
        active.discard(task)
        LOG.write(
            f"{time.strftime('%H:%M:%S')} {port} {request.method} {request.path_qs[:160]} "
            f"{status} {sent} {time.monotonic() - started:.3f}\n"
        )


async def start_sites():
    for port in UPSTREAMS:
        if port in sites:
            continue
        site = web.TCPSite(runners[port], "127.0.0.1", port)
        await site.start()
        sites[port] = site


async def stop_sites():
    for port, site in list(sites.items()):
        await site.stop()
        del sites[port]
    for task in list(active):
        task.cancel()


async def control(request: web.Request):
    action = request.path.strip("/")
    if action == "offline":
        state["online"] = False
        await stop_sites()
    elif action == "online":
        state["online"] = True
        await start_sites()
    elif action == "shape":
        for key in ("down_kbps", "up_kbps", "rtt_ms"):
            if key in request.query:
                state[key] = int(request.query[key])
    elif action == "noshape":
        state.update(down_kbps=0, up_kbps=0, rtt_ms=0)
    elif action == "shot":
        # A screenshot of the booted simulator, asked by the tour inside it.
        name = os.path.basename(request.query.get("name", "shot"))
        os.makedirs(SHOTS, exist_ok=True)
        path = os.path.join(SHOTS, f"{name}.png")
        proc = await asyncio.create_subprocess_exec(
            "xcrun", "simctl", "io", "booted", "screenshot", "--type=png", path,
            stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL,
        )
        await proc.wait()
        LOG.write(f"{time.strftime('%H:%M:%S')} shot {path}\n")
        return web.json_response({"shot": path})
    elif action == "mark":
        # A line of the tour's own in the log, to time what it did.
        LOG.write(f"{time.strftime('%H:%M:%S')} mark {request.query.get('what', '')}\n")
        return web.json_response({})
    LOG.write(f"{time.strftime('%H:%M:%S')} control {action} {json.dumps(state)}\n")
    return web.json_response(state)


async def main():
    global session
    session = aiohttp.ClientSession(
        timeout=aiohttp.ClientTimeout(total=None, sock_connect=20),
        headers={"User-Agent": "lunaway-relay-test (+https://lunaway.net)"},
        auto_decompress=False,
    )
    for port in UPSTREAMS:
        app = web.Application(client_max_size=64 * 1024 * 1024)
        app.router.add_route("*", "/{tail:.*}", handle)
        runner = web.AppRunner(app, access_log=None)
        await runner.setup()
        runners[port] = runner
    await start_sites()
    capp = web.Application()
    capp.router.add_get("/{action}", control)
    crunner = web.AppRunner(capp, access_log=None)
    await crunner.setup()
    await web.TCPSite(crunner, "127.0.0.1", CONTROL).start()
    print("relay up", flush=True)
    await asyncio.Event().wait()


if __name__ == "__main__":
    asyncio.run(main())
