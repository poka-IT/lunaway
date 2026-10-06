"""Browser tests of the account deletion form, under the page's real CSP
(serve.py), with the API answers mocked at the network layer.

    python3 data/tmp/site/test_delete.py [BASE_URL]
"""

import json
import secrets
import sys

from playwright.sync_api import sync_playwright

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:18790"
API = "https://api.lunaway.net/graphql"
ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


def check_value(symbols):
    total = 0
    for i, v in enumerate(reversed(symbols)):
        addend = v * (2 if i % 2 == 0 else 1)
        total += addend // 32 + addend % 32
    return (32 - total % 32) % 32


def make_code(value=None):
    """A recovery code as recovery.rs displays one."""
    value = secrets.randbits(128) if value is None else value
    data = [(value >> (5 * (25 - i))) & 31 for i in range(26)]
    symbols = data + [check_value(data)]
    text = "".join(ALPHABET[v] for v in symbols)
    return "-".join(text[i:i + 4] for i in range(0, len(text), 4))


failures = 0


def expect(name, cond, detail=""):
    global failures
    if cond:
        print(f"ok   {name}")
    else:
        failures += 1
        print(f"FAIL {name} {detail}")


def visible_result(page):
    return page.evaluate("""() => [...document.querySelectorAll('[data-result]')]
        .filter(e => !e.hidden).map(e => e.getAttribute('data-result'))""")


def visible_error(page):
    return page.evaluate("""() => [...document.querySelectorAll('[data-error]')]
        .filter(e => !e.hidden).map(e => e.getAttribute('data-error'))""")


def run(lang_path):
    with sync_playwright() as p:
        browser = p.chromium.launch(args=["--host-resolver-rules=MAP lunaway.net 127.0.0.1"])
        ctx = browser.new_context()
        page = ctx.new_page()
        console = []
        page.on("console", lambda m: console.append(m.text))
        sent = []
        plan = {"mode": "ok"}

        def handle(route):
            req = route.request
            if req.method == "OPTIONS":
                route.fulfill(status=204, headers={
                    "Access-Control-Allow-Origin": BASE, "Access-Control-Allow-Methods": "POST, OPTIONS",
                    "Access-Control-Allow-Headers": "content-type"})
                return
            sent.append({"body": json.loads(req.post_data), "headers": req.headers})
            cors = {"Access-Control-Allow-Origin": BASE, "Access-Control-Expose-Headers": "retry-after",
                    "Content-Type": "application/json"}
            mode = plan["mode"]
            if mode == "ok":
                route.fulfill(status=200, headers=cors, body='{"data":{"deleteAccountWithRecoveryCode":true}}')
            elif mode == "false":
                route.fulfill(status=200, headers=cors, body='{"data":{"deleteAccountWithRecoveryCode":false}}')
            elif mode == "not-found":
                route.fulfill(status=200, headers=cors, body=json.dumps({"data": None, "errors": [
                    {"message": "no such account with this recovery code", "extensions": {"code": "NOT_FOUND"}}]}))
            elif mode == "invalid":
                route.fulfill(status=200, headers=cors, body=json.dumps({"data": None, "errors": [
                    {"message": "code: not a recovery code", "extensions": {"code": "INVALID_INPUT"}}]}))
            elif mode == "limited":
                route.fulfill(status=429, headers={**cors, "Retry-After": "1790"}, body=json.dumps({"data": None, "errors": [
                    {"message": "too many recovery attempts", "extensions": {"code": "RATE_LIMITED", "retryAfterSeconds": 1790}}]}))
            elif mode == "limited-header":
                route.fulfill(status=429, headers={**cors, "Retry-After": "120"}, body="{}")
            elif mode == "internal":
                route.fulfill(status=200, headers=cors, body=json.dumps({"data": None, "errors": [
                    {"message": "internal error", "extensions": {"code": "INTERNAL"}}]}))
            elif mode == "502":
                route.fulfill(status=502, headers={"Access-Control-Allow-Origin": BASE, "Content-Type": "text/html"},
                              body="<html>bad gateway</html>")
            elif mode == "abort":
                route.abort("connectionrefused")

        page.route(API, handle)
        page.goto(BASE + lang_path, wait_until="networkidle")
        expect(f"{lang_path}: the script enabled the form",
               page.evaluate("() => !document.querySelector('#delete-form fieldset').disabled"))
        expect(f"{lang_path}: the no-script note is hidden",
               page.evaluate("() => document.getElementById('delete-noscript').hidden"))

        def submit(text):
            page.fill("#recovery-code", text)
            page.click("#delete-form button[type=submit]")

        # Client-side checks: nothing is sent.
        for text, kind in [("", "empty"), ("ABCD-EFGH", "length"), ("ABCU" + make_code()[4:], "char")]:
            submit(text)
            expect(f"{lang_path}: '{text[:12]}' gives the {kind} error", visible_error(page) == [kind],
                   str(visible_error(page)))
        submit("ABCD-EFGH")
        expect(f"{lang_path}: the count of symbols is 8", page.inner_text("#error-length [data-slot=count]") == "8")
        expect(f"{lang_path}: aria-invalid set", page.get_attribute("#recovery-code", "aria-invalid") == "true")
        good = make_code()
        flipped = good[:-1] + ("0" if good[-1] != "0" else "1")
        submit(flipped)
        expect(f"{lang_path}: a wrong check symbol is a typo", visible_error(page) == ["typo"], str(visible_error(page)))
        # Every single-symbol substitution of a valid code is refused, as
        # recovery.rs tests it, by the page's own code.
        subs = [good[:i] + c + good[i + 1:] for i in range(len(good)) if good[i] != "-"
                for c in ALPHABET if c != good[i]]
        refused = page.evaluate("""(codes) => {
            const form = document.getElementById('delete-form');
            const input = document.getElementById('recovery-code');
            let n = 0;
            for (const code of codes) {
                input.value = code;
                form.requestSubmit();
                const shown = [...document.querySelectorAll('[data-error]')].filter(e => !e.hidden)
                    .map(e => e.getAttribute('data-error'));
                if (shown.length === 1 && shown[0] === 'typo') n += 1;
                if (!document.getElementById('delete-confirm').hidden) {
                    document.getElementById('delete-back').click();
                }
            }
            return n;
        }""", subs)
        expect(f"{lang_path}: all {len(subs)} single-symbol typos refused", refused == len(subs), f"{refused}/{len(subs)}")
        expect(f"{lang_path}: nothing sent for invalid codes", sent == [], str(sent))

        # Lower case, spaces, O for 0 and I or L for 1 are accepted, as on the server.
        loose = good.lower().replace("-", " ").replace("0", "o").replace("1", "l")
        submit(loose)
        expect(f"{lang_path}: a loosely typed code passes", visible_error(page) == [] and
               page.is_visible("#delete-confirm"), str(visible_error(page)))
        expect(f"{lang_path}: the confirmation shows the code", page.inner_text("#code-echo") == good,
               page.inner_text("#code-echo"))
        expect(f"{lang_path}: focus on the confirmation heading",
               page.evaluate("() => document.activeElement.tagName") == "H3")
        page.click("#delete-back")
        expect(f"{lang_path}: going back shows the form again",
               page.is_visible("#delete-form") and not page.is_visible("#delete-confirm"))
        expect(f"{lang_path}: going back sends nothing", sent == [])

        for mode, result in [("not-found", "not-found"), ("false", "not-found"), ("invalid", "invalid"),
                             ("limited", "limited"), ("limited-header", "limited"), ("internal", "unknown"),
                             ("502", "unknown"), ("abort", "unknown"), ("ok", "deleted")]:
            plan["mode"] = mode
            submit(good)
            page.click("#delete-go")
            page.wait_for_function("() => [...document.querySelectorAll('[data-result]')].some(e => !e.hidden)")
            got = visible_result(page)
            expect(f"{lang_path}: API answer '{mode}' shows '{result}'", got == [result], str(got))
            if mode == "limited":
                expect(f"{lang_path}: 1790 s are 30 minutes", page.inner_text("[data-result=limited] [data-slot=minutes]") == "30")
            if mode == "limited-header":
                expect(f"{lang_path}: Retry-After 120 is 2 minutes",
                       page.inner_text("[data-result=limited] [data-slot=minutes]") == "2")
            expect(f"{lang_path}: focus on the '{result}' heading",
                   page.evaluate("() => document.activeElement.closest('[data-result]')?.getAttribute('data-result')") == result)
            if result != "deleted":
                expect(f"{lang_path}: the form is back after '{mode}'", page.is_visible("#delete-form"))
        expect(f"{lang_path}: after deletion the form is gone and the field empty",
               not page.is_visible("#delete-form") and page.input_value("#recovery-code") == "")
        last = sent[-1]
        body = last["body"]
        expect(f"{lang_path}: the request is the mutation with the normalised code",
               body.get("operationName") == "DeleteAccount"
               and "deleteAccountWithRecoveryCode(code: $code)" in body.get("query", "")
               and body.get("variables") == {"code": good.replace("-", "")}, json.dumps(body))
        expect(f"{lang_path}: JSON content type", last["headers"].get("content-type") == "application/json",
               str(last["headers"]))
        expect(f"{lang_path}: no cookie or referer sent",
               "cookie" not in last["headers"] and "referer" not in last["headers"], str(last["headers"]))
        violations = [m for m in console if "Content Security Policy" in m or "Refused" in m]
        expect(f"{lang_path}: no CSP violation", violations == [], str(violations))
        browser.close()


if __name__ == "__main__":
    run("/account/delete")
    run("/en/account/delete")
    print(f"{failures} failure(s)")
    sys.exit(1 if failures else 0)
