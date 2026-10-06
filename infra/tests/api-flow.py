# /// script
# requires-python = ">=3.11"
# dependencies = ["cryptography>=42", "pillow>=10"]
# ///
"""The accounts and photos of the deployed API, end to end, from outside.

    uv run infra/tests/api-flow.py https://<api host> [--ssh-host lunaway]
        [--ssh-config FILE] [--hold SECONDS]

Creates an account, checks it, uploads a photo and deletes the account:

  1. a fresh P-256 device key; authChallenge, then signIn with the challenge
     signed (ES256, raw r||s): a new account at level 0;
  2. myAccount with the session;
  3. with --ssh-host, the account is raised to level 1 through
     `sudo lunaway-admin accounts set-level` (photos need level 1), then a
     JPEG carrying a camera name and a GPS position in its EXIF goes to
     POST /upload for a place near Annecy; the WebP files the API serves must
     hold one VP8 chunk and nothing else (no EXIF, no XMP, no position);
  4. search "annecy" names places of Annecy; the first one carries the
     vehicle limits (maxLengthM, maxWidthM, maxWeightT, null when unknown),
     has points of interest around it (nearbyPois), and takes a
     confirmation without `presence` (an argument the API no longer knows),
     deleted at once; searchPois finds supermarkets near it;
  5. deleteAccount: the session stops working and the photo files go. With
     --hold, the account and its photo stay that long first (at most 9
     minutes: deleting needs a sign-in of the last 10), to follow the photo
     through the backups;
  6. authChallenge until the per-client quota (30 a minute) answers
     RATE_LIMITED. Run it last: it spends this machine's quota for a minute.

Prints one line per check, `ok` or `FAIL`, and exits 1 on any FAIL. Nothing
of the session or the key is printed.
"""
import base64
import io
import json
import shlex
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from PIL import Image

USER_AGENT = "Lunaway API check (+https://lunaway.net)"
failures = 0


def report(ok, label, detail=""):
    global failures
    if not ok:
        failures += 1
    print("%s %s%s" % ("ok  " if ok else "FAIL", label, ": " + detail if detail else ""), flush=True)


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def request(url, data=None, headers=None, method=None):
    req = urllib.request.Request(url, data=data, headers={"User-Agent": USER_AGENT, **(headers or {})}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.status, dict(resp.headers), resp.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()


def graphql(base, query, variables=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    body = json.dumps({"query": query, "variables": variables or {}}).encode()
    status, _, raw = request(base + "/graphql", body, headers)
    try:
        return status, json.loads(raw)
    except ValueError:
        return status, {"errors": [{"message": raw[:200].decode(errors="replace")}]}


def error_code(result):
    return ((result.get("errors") or [{}])[0].get("extensions") or {}).get("code")


def sign_in(base, key):
    numbers = key.public_key().public_numbers()
    jwk = json.dumps({"kty": "EC", "crv": "P-256",
                      "x": b64url(numbers.x.to_bytes(32, "big")),
                      "y": b64url(numbers.y.to_bytes(32, "big"))})
    _, result = graphql(base, "mutation { authChallenge { nonce message expiresAt } }")
    challenge = (result.get("data") or {}).get("authChallenge")
    report(challenge is not None and challenge["message"] == "lunaway-auth:v1:" + challenge["nonce"],
           "authChallenge", "message lunaway-auth:v1:<nonce>" if challenge else str(result)[:200])
    if not challenge:
        return None, None
    der = key.sign(challenge["message"].encode(), ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der)
    signature = b64url(r.to_bytes(32, "big") + s.to_bytes(32, "big"))
    _, result = graphql(base, """mutation($k: String!, $n: String!, $s: String!) {
        signIn(publicKeyJwk: $k, nonce: $n, signature: $s, locale: "fr") {
          token created account { id pseudonym trustLevel } } }""",
                        {"k": jwk, "n": challenge["nonce"], "s": signature})
    signed = (result.get("data") or {}).get("signIn")
    report(bool(signed and signed["created"] and signed["account"]["trustLevel"] == 0), "signIn creates an account",
           "level 0, pseudonym %r" % signed["account"]["pseudonym"] if signed else str(result)[:200])
    if not signed:
        return None, None
    return signed["token"], signed["account"]["id"]


def jpeg_with_gps():
    """A 1600x1200 JPEG with a camera name and a GPS position in its EXIF."""
    image = Image.new("RGB", (1600, 1200))
    pixels = image.load()
    seed = uuid.uuid4().int
    for x in range(1600):
        for y in range(0, 1200, 4):
            v = (x * 7 + y * 13 + seed) & 0xFF
            for dy in range(4):
                pixels[x, y + dy] = (v, (v * 3) & 0xFF, (x + y) & 0xFF)
    exif = Image.Exif()
    exif[0x010F] = "LunawayTestMaker"
    exif[0x0110] = "LunawayTestCam"
    exif[0x8825] = {1: "N", 2: (45.0, 54.0, 0.0), 3: "E", 4: (6.0, 7.0, 0.0)}
    out = io.BytesIO()
    image.save(out, "JPEG", quality=90, exif=exif)
    return out.getvalue()


def webp_chunks(data):
    if data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        return None
    chunks, offset = [], 12
    while offset + 8 <= len(data):
        tag, size = data[offset:offset + 4], struct.unpack("<I", data[offset + 4:offset + 8])[0]
        chunks.append(tag.decode(errors="replace"))
        offset += 8 + size + (size & 1)
    return chunks


def multipart(fields, boundary):
    parts = []
    for name, (filename, content, ctype) in fields.items():
        disposition = 'form-data; name="%s"' % name + ('; filename="%s"' % filename if filename else "")
        head = "--%s\r\nContent-Disposition: %s\r\n" % (boundary, disposition)
        if ctype:
            head += "Content-Type: %s\r\n" % ctype
        parts.append(head.encode() + b"\r\n" + content + b"\r\n")
    return b"".join(parts) + ("--%s--\r\n" % boundary).encode()


def exercise(base, token, account, ssh_host, ssh_config, hold):
    """Search, the place checks, the confirmation and the photo; returns the
    photo uploaded, or None."""
    _, result = graphql(base, '{ search(text: "annecy", first: 10) { id name municipality } }')
    found = (result.get("data") or {}).get("search") or []
    annecy = [p for p in found if "annecy" in ((p.get("municipality") or "") + " " + (p.get("name") or "")).lower()]
    report(len(found) > 0 and len(annecy) == len(found), "search annecy",
           "%d results, %d in Annecy or named after it: %s" % (len(found), len(annecy), "; ".join(
               "%s (%s)" % (p.get("name"), p.get("municipality")) for p in found[:5])))

    if found:
        place_id = found[0]["id"]
        _, result = graphql(base, """query($id: UUID!) {
            place(id: $id) { id name maxHeightM maxLengthM maxWidthM maxWeightT } }""", {"id": place_id})
        place = (result.get("data") or {}).get("place") or {}
        limits = {k: place.get(k, "absent") for k in ("maxLengthM", "maxWidthM", "maxWeightT")}
        report("absent" not in limits.values(), "vehicle limits on Place", "%s: %s" % (place.get("name"), limits))
        start = time.time()
        _, result = graphql(base, """query($id: UUID!) {
            nearbyPois(placeId: $id) { category radiusM pois { kind name distanceM openNow { state } } } }""", {"id": place_id})
        elapsed = time.time() - start
        groups = (result.get("data") or {}).get("nearbyPois") or []
        nearest = ["%s %s %.0f m" % (g["category"], g["pois"][0]["kind"], g["pois"][0]["distanceM"]) for g in groups if g["pois"]]
        report(len(nearest) >= 4, "nearbyPois around the place", "%.2f s, %d of %d categories: %s" % (
            elapsed, len(nearest), len(groups), "; ".join(nearest)))
        _, result = graphql(base, """query($at: LatLonInput) {
            searchPois(text: "super u", near: $at, first: 5) { kind name distanceM } }""",
            {"at": {"lat": 45.8992, "lon": 6.1294}})
        hits = (result.get("data") or {}).get("searchPois") or []
        report(len(hits) > 0 and all("u" in (h.get("name") or "").lower() for h in hits), "searchPois super u near Annecy",
               "; ".join("%s %s %.0f m" % (h["kind"], h["name"], h["distanceM"] or 0) for h in hits[:3]))
        _, result = graphql(base, """mutation($id: UUID!) {
            confirm(placeId: $id, status: STILL_OK, presence: HERE) { id } }""", {"id": place_id}, token=token)
        message = ((result.get("errors") or [{}])[0].get("message") or "")
        report("presence" in message and not (result.get("data") or {}).get("confirm"), "confirm refuses presence",
               message[:100])
        _, result = graphql(base, """mutation($id: UUID!) {
            confirm(placeId: $id, status: STILL_OK) { id status } }""", {"id": place_id}, token=token)
        confirmation = (result.get("data") or {}).get("confirm")
        report(bool(confirmation and confirmation["status"] == "STILL_OK"), "confirm without presence",
               str(confirmation or result)[:120])
        if confirmation:
            _, result = graphql(base, "mutation($id: UUID!) { deleteConfirmation(id: $id) }",
                                {"id": confirmation["id"]}, token=token)
            report((result.get("data") or {}).get("deleteConfirmation") is True, "the test confirmation deleted",
                   str(result)[:120])

    photo = None
    if ssh_host and found:
        # The id comes from the API: a UUID or nothing, and quoted for the
        # remote shell, which runs it with sudo.
        account = str(uuid.UUID(account))
        remote = shlex.join(["sudo", "lunaway-admin", "accounts", "set-level", account, "1"])
        cmd = ["ssh"] + (["-F", ssh_config] if ssh_config else []) + [ssh_host, remote]
        done = subprocess.run(cmd, capture_output=True, text=True)
        report(done.returncode == 0, "level 1 granted with lunaway-admin", (done.stdout + done.stderr).strip().splitlines()[-1][:120] if (done.stdout + done.stderr).strip() else "")
        jpeg = jpeg_with_gps()
        gps = Image.open(io.BytesIO(jpeg)).getexif().get_ifd(0x8825)
        report(b"LunawayTestCam" in jpeg and gps.get(1) == "N" and gps.get(3) == "E", "test JPEG carries EXIF",
               "%d bytes, camera name and GPS position %s %s, %s %s" % (len(jpeg), gps.get(2), gps.get(1), gps.get(4), gps.get(3)))
        boundary = "lunaway" + uuid.uuid4().hex
        body = multipart({"placeId": (None, found[0]["id"].encode(), None),
                          "file": ("test.jpg", jpeg, "image/jpeg")}, boundary)
        start = time.time()
        status, _, raw = request(base + "/upload", body, {
            "Content-Type": "multipart/form-data; boundary=" + boundary, "Authorization": "Bearer " + token})
        elapsed = time.time() - start
        try:
            photo = json.loads(raw).get("photo")
        except ValueError:
            photo = None
        report(status == 200 and photo is not None, "photo upload",
               "%s in %.2f s, %sx%s, status %s" % (status, elapsed, (photo or {}).get("width"), (photo or {}).get("height"),
                                                    (photo or {}).get("status")) if photo else "%s %s" % (status, raw[:200]))
        if photo:
            for label in ("largeUrl", "thumbUrl"):
                status, headers, data = request(photo[label])
                chunks = webp_chunks(data)
                ctype = {k.lower(): v for k, v in headers.items()}.get("content-type")
                clean = chunks == ["VP8 "] and b"Exif" not in data and b"LunawayTest" not in data and b"<x:xmpmeta" not in data
                report(status == 200 and ctype == "image/webp" and clean, "served %s has no metadata" % label,
                       "%s %s, %d bytes, chunks %s" % (status, ctype, len(data), chunks))

    if hold and photo:
        print("     holding the account %d s; photo file %s" % (hold, photo["largeUrl"].rsplit("/media/", 1)[-1]), flush=True)
        time.sleep(hold)
    return photo


def retract_confirmations(base, token):
    """Deletes every confirmation of the test account, whatever happened to
    the run: deleteAccount keeps a confirmation, anonymised, and it would
    still date the place's last check."""
    _, result = graphql(base, "{ myAccount { confirmations(first: 50) { nodes { id } } } }", token=token)
    nodes = (((result.get("data") or {}).get("myAccount") or {}).get("confirmations") or {}).get("nodes")
    if nodes is None:
        report(False, "the test account's confirmations listed", str(result)[:120])
        return
    for node in nodes:
        graphql(base, "mutation($id: UUID!) { deleteConfirmation(id: $id) }", {"id": node["id"]}, token=token)
    _, result = graphql(base, "{ myAccount { confirmations(first: 50) { totalCount } } }", token=token)
    left = (((result.get("data") or {}).get("myAccount") or {}).get("confirmations") or {}).get("totalCount")
    report(left == 0, "no confirmation left before the account goes", "%s left" % left)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    base = sys.argv[1].rstrip("/")
    ssh_host = sys.argv[sys.argv.index("--ssh-host") + 1] if "--ssh-host" in sys.argv else None
    ssh_config = sys.argv[sys.argv.index("--ssh-config") + 1] if "--ssh-config" in sys.argv else None
    hold = min(int(sys.argv[sys.argv.index("--hold") + 1]), 540) if "--hold" in sys.argv else 0

    key = ec.generate_private_key(ec.SECP256R1())
    token, account = sign_in(base, key)
    if not token:
        sys.exit(1)
    _, result = graphql(base, "{ myAccount { id pseudonym trustLevel } }", token=token)
    me = (result.get("data") or {}).get("myAccount")
    report(bool(me and me["id"] == account), "myAccount with the session", "same account, level %s" % (me or {}).get("trustLevel"))

    photo = None
    try:
        photo = exercise(base, token, account, ssh_host, ssh_config, hold)
    finally:
        # Whatever failed above, the test account and what it wrote go.
        retract_confirmations(base, token)
        _, result = graphql(base, 'mutation { deleteAccount(confirm: "DELETE") }', token=token)
        report((result.get("data") or {}).get("deleteAccount") is True, "deleteAccount", str(result)[:120])
    _, result = graphql(base, "{ myAccount { id } }", token=token)
    report(error_code(result) == "UNAUTHENTICATED", "the session after deletion", "code %s" % error_code(result))
    if photo:
        gone = None
        for _ in range(10):
            gone, _, _ = request(photo["largeUrl"])
            if gone == 404:
                break
            time.sleep(1)
        report(gone == 404, "photo file after deletion", "status %s" % gone)

    tripped = None
    for i in range(1, 40):
        status, result = graphql(base, "mutation { authChallenge { nonce } }")
        if error_code(result) == "RATE_LIMITED":
            retry = ((result.get("errors") or [{}])[0].get("extensions") or {}).get("retryAfterSeconds")
            tripped = (i, status, retry)
            break
    report(tripped is not None and tripped[0] > 20, "authChallenge quota",
           "RATE_LIMITED at request %s (HTTP %s, retry after %s s)" % tripped if tripped else "never refused in 39 requests")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
