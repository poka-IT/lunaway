"""The deletion page end to end against a real API: an account is created
through the API (device key, signIn, createRecoveryCode), then deleted by
the page in a headless browser, under the page's CSP with connect-src set to
the local API.

    python3 data/tmp/site/e2e_delete.py SITE_BASE API_BASE

The API must run with LUNAWAY_DEV_CORS=1 (pages served from 127.0.0.1).
Nothing of the key, the session or the code is printed.
"""

import base64
import json
import sys
import urllib.error
import urllib.request

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from playwright.sync_api import sync_playwright

SITE, API = sys.argv[1], sys.argv[2]
failures = 0


def expect(name, cond, detail=""):
    global failures
    if not cond:
        failures += 1
    print(("ok   " if cond else "FAIL ") + name + (f": {detail}" if detail and not cond else ""))


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def graphql(query, variables=None, token=None):
    headers = {"Content-Type": "application/json", "User-Agent": "lunaway-site-e2e (+https://lunaway.net)"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(API + "/graphql", json.dumps({"query": query, "variables": variables or {}}).encode(),
                                 headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        return json.loads(e.read())


def new_account():
    key = ec.generate_private_key(ec.SECP256R1())
    n = key.public_key().public_numbers()
    jwk = json.dumps({"kty": "EC", "crv": "P-256", "x": b64url(n.x.to_bytes(32, "big")), "y": b64url(n.y.to_bytes(32, "big"))})
    ch = graphql("mutation { authChallenge { nonce message } }")["data"]["authChallenge"]
    r, s = decode_dss_signature(key.sign(ch["message"].encode(), ec.ECDSA(hashes.SHA256())))
    signed = graphql("""mutation($k: String!, $n: String!, $s: String!) {
        signIn(publicKeyJwk: $k, nonce: $n, signature: $s, locale: "fr") { token created account { id } } }""",
                     {"k": jwk, "n": ch["nonce"], "s": b64url(r.to_bytes(32, "big") + s.to_bytes(32, "big"))})["data"]["signIn"]
    expect("signIn created an account", signed["created"] is True)
    token = signed["token"]
    code = graphql("mutation { createRecoveryCode { code } }", token=token)["data"]["createRecoveryCode"]["code"]
    expect("createRecoveryCode gave a code of 33 characters", len(code) == 33)
    me = graphql("{ myAccount { id } }", token=token)
    expect("myAccount answers before deletion", (me.get("data") or {}).get("myAccount") is not None, str(me)[:120])
    return token, code


def main():
    token, code = new_account()
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()
        console = []
        page.on("console", lambda m: console.append(m.text))

        def attempt(text):
            page.goto(SITE + "/account/delete", wait_until="networkidle")
            page.fill("#recovery-code", text)
            page.click("#delete-form button[type=submit]")
            if not page.is_visible("#delete-confirm"):
                return "client:" + ",".join(page.evaluate(
                    "() => [...document.querySelectorAll('[data-error]')].filter(e => !e.hidden).map(e => e.dataset.error)"))
            page.click("#delete-go")
            page.wait_for_function("() => [...document.querySelectorAll('[data-result]')].some(e => !e.hidden)")
            return page.evaluate("() => [...document.querySelectorAll('[data-result]')].filter(e => !e.hidden)[0].dataset.result")

        # The code as the app shows it, typed in lower case with spaces.
        typed = code.lower().replace("-", " ")
        got = attempt(typed)
        expect("a real recovery code passes the page's checks and deletes the account", got == "deleted", got)
        me = graphql("{ myAccount { id } }", token=token)
        code_after = ((me.get("errors") or [{}])[0].get("extensions") or {}).get("code")
        expect("the session no longer works after deletion", code_after == "UNAUTHENTICATED", str(me)[:160])
        got = attempt(code)
        expect("the same code again: no account", got == "not-found", got)
        # Spend the client's quota (5 an hour): attempts 3 to 5 answer
        # not-found, the sixth is refused with a wait.
        results = [attempt(code) for _ in range(4)]
        expect("the sixth attempt in the hour shows the wait", results[-1] == "limited", str(results))
        minutes = page.inner_text("[data-result=limited] [data-slot=minutes]")
        expect("the wait is given in minutes, at most 60", minutes.isdigit() and 1 <= int(minutes) <= 60, minutes)
        violations = [m for m in console if "Content Security Policy" in m or "Refused" in m]
        expect("no CSP violation", violations == [], str(violations))
        browser.close()
    # Whatever happened above, leave no test account behind.
    left = graphql('mutation { deleteAccount(confirm: "DELETE") }', token=token)
    gone = ((left.get("errors") or [{}])[0].get("extensions") or {}).get("code") == "UNAUTHENTICATED"
    print("cleanup: " + ("account already gone" if gone else "account deleted by the script: " + str(left)[:80]))
    print(f"{failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
