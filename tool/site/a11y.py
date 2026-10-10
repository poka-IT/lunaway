"""axe-core (WCAG 2.2 A and AA rules) on every page, at 390 and 1440 px, in
light and dark, plus the delete page's confirmation and result states.

    python3 data/tmp/site/a11y.py [BASE_URL]
"""

import os
import sys

from playwright.sync_api import sync_playwright

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://lunaway.net:18080"
AXE = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "package", "axe.min.js")).read()
PAGES = [prefix + page for prefix in ("/", "/en/", "/de/", "/es/", "/it/", "/nl/")
         for page in ("", "privacy", "about", "legal", "account/delete", "fdroid/")] + ["/nope"]
TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa", "best-practice"]


def audit(page, label):
    page.evaluate(AXE)
    result = page.evaluate("(tags) => axe.run(document, {runOnly: {type: 'tag', values: tags}})", TAGS)
    problems = [(v["id"], v["impact"], len(v["nodes"]), v["nodes"][0]["target"], v["nodes"][0].get("failureSummary", "")[:160])
                for v in result["violations"]]
    for p in problems:
        print(f"VIOLATION {label}: {p}")
    return len(problems)


def main():
    total = 0
    with sync_playwright() as p:
        browser = p.chromium.launch(args=["--host-resolver-rules=MAP lunaway.net 127.0.0.1"])
        for width in (390, 1440):
            for scheme in ("light", "dark"):
                ctx = browser.new_context(viewport={"width": width, "height": 900}, color_scheme=scheme)
                page = ctx.new_page()
                for path in PAGES:
                    page.goto(BASE + path, wait_until="networkidle")
                    total += audit(page, f"{path} {width} {scheme}")
                # The deletion page in its other states.
                page.route("https://api.lunaway.net/graphql", lambda r: r.fulfill(
                    status=200, headers={"Access-Control-Allow-Origin": BASE, "Content-Type": "application/json"},
                    body='{"data":{"deleteAccountWithRecoveryCode":true}}') if r.request.method == "POST" else r.fulfill(
                    status=204, headers={"Access-Control-Allow-Origin": BASE, "Access-Control-Allow-Headers": "content-type"}))
                page.goto(BASE + "/account/delete", wait_until="networkidle")
                page.fill("#recovery-code", "ABCD")
                page.click("#delete-form button[type=submit]")
                total += audit(page, f"delete error {width} {scheme}")
                page.fill("#recovery-code", "2W3Y-9GFA-J1DR-1DGC-WVE0-7C88-CF1")
                page.click("#delete-form button[type=submit]")
                if page.is_visible("#delete-confirm"):
                    total += audit(page, f"delete confirm {width} {scheme}")
                    page.click("#delete-go")
                    page.wait_for_selector("[data-result=deleted]:not([hidden])")
                    total += audit(page, f"delete done {width} {scheme}")
                else:
                    print("note: the sample code from the backend report did not pass the page's check")
                ctx.close()
        browser.close()
    print(f"{total} violation group(s)")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
