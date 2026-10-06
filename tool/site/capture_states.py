"""Captures of the deletion form's states (a typing error, the confirmation,
the account deleted), with the API answer mocked, under the real CSP.

    python3 data/tmp/site/capture_states.py [BASE_URL]
"""

import os
import sys

from playwright.sync_api import sync_playwright

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://lunaway.net:18080"
OUT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "plan", "screenshots", "site"))
SAMPLE = "2w3y 9gfa j1dr 1dgc wve0 7c88 cf1"  # the example code of plan/research/12-backend-iteration2.md


def api(route):
    if route.request.method == "OPTIONS":
        route.fulfill(status=204, headers={"Access-Control-Allow-Origin": BASE, "Access-Control-Allow-Headers": "content-type"})
        return
    route.fulfill(status=200, headers={"Access-Control-Allow-Origin": BASE, "Content-Type": "application/json"},
                  body='{"data":{"deleteAccountWithRecoveryCode":true}}')


with sync_playwright() as p:
    browser = p.chromium.launch(args=["--host-resolver-rules=MAP lunaway.net 127.0.0.1"])
    for lang, path in (("fr", "/account/delete"), ("en", "/en/account/delete")):
        for (w, h, scale, mobile), scheme in (((390, 844, 2, True), "light"), ((1440, 900, 1, False), "dark")):
            ctx = browser.new_context(viewport={"width": w, "height": h}, device_scale_factor=scale, is_mobile=mobile,
                                      color_scheme=scheme)
            page = ctx.new_page()
            page.route("https://api.lunaway.net/graphql", api)
            page.goto(BASE + path, wait_until="networkidle")
            page.fill("#recovery-code", "2W3Y-9GFA-J1DR-1DGU-WVE0-7C88-CF1")
            page.click("#delete-form button[type=submit]")
            page.locator(".form-card").screenshot(path=f"{OUT}/{lang}-delete-state-error-{w}-{scheme}.png")
            page.fill("#recovery-code", SAMPLE)
            page.click("#delete-form button[type=submit]")
            page.locator(".form-card").screenshot(path=f"{OUT}/{lang}-delete-state-confirm-{w}-{scheme}.png")
            page.click("#delete-go")
            page.wait_for_selector("[data-result=deleted]:not([hidden])")
            page.locator(".form-card").screenshot(path=f"{OUT}/{lang}-delete-state-done-{w}-{scheme}.png")
            ctx.close()
    browser.close()
