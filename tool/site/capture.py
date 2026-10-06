"""Full-page captures of every page of the site, at 390 px and 1440 px, in
light and dark, through serve.py (the real CSP), plus the console messages
(CSP violations show there) and the bytes each page transfers.

    python3 data/tmp/site/capture.py [BASE_URL] [OUT_DIR] [--only NAME,...]
"""

import json
import os
import sys
import time

from playwright.sync_api import sync_playwright

ARGS = sys.argv[1:]
ONLY = ARGS[ARGS.index("--only") + 1].split(",") if "--only" in ARGS else None
POSITIONAL = [a for i, a in enumerate(ARGS) if a != "--only" and (i == 0 or ARGS[i - 1] != "--only")]
BASE = POSITIONAL[0] if POSITIONAL else "http://127.0.0.1:18790"
OUT = POSITIONAL[1] if len(POSITIONAL) > 1 else os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "plan", "screenshots", "site"))

PAGES = [
    ("fr-home", "/"), ("fr-privacy", "/privacy"), ("fr-about", "/about"), ("fr-legal", "/legal"),
    ("fr-delete", "/account/delete"), ("fr-fdroid", "/fdroid/"),
    ("en-home", "/en/"), ("en-privacy", "/en/privacy"), ("en-about", "/en/about"), ("en-legal", "/en/legal"),
    ("en-delete", "/en/account/delete"), ("en-fdroid", "/en/fdroid/"),
    ("404", "/nope"),
]
VIEWS = [(390, 844, 2, True), (1440, 900, 1, False)]


def main():
    os.makedirs(OUT, exist_ok=True)
    report = {}
    with sync_playwright() as p:
        browser = p.chromium.launch(args=["--host-resolver-rules=MAP lunaway.net 127.0.0.1"])
        for name, path in PAGES:
            if ONLY and name not in ONLY:
                continue
            for width, height, scale, mobile in VIEWS:
                for scheme in ("light", "dark"):
                    ctx = browser.new_context(viewport={"width": width, "height": height}, device_scale_factor=scale,
                                              is_mobile=mobile, has_touch=mobile, color_scheme=scheme,
                                              locale="fr-FR" if not name.startswith("en") else "en-GB")
                    page = ctx.new_page()
                    messages, requests = [], []
                    page.on("console", lambda m: messages.append(f"{m.type}: {m.text}"))
                    page.on("pageerror", lambda e: messages.append(f"pageerror: {e}"))
                    page.on("requestfinished", lambda r: requests.append(r))
                    page.on("requestfailed", lambda r: messages.append(f"failed: {r.url} {r.failure}"))
                    page.goto(BASE + path, wait_until="networkidle")
                    initial = sum(r.sizes()["responseBodySize"] + r.sizes()["responseHeadersSize"] for r in list(requests))
                    # Bring every lazy image in, then back to the top.
                    page.evaluate("""async () => {
                        for (let y = 0; y < document.body.scrollHeight; y += 600) {
                            window.scrollTo(0, y); await new Promise(r => setTimeout(r, 60));
                        }
                        window.scrollTo(0, 0);
                    }""")
                    page.wait_for_load_state("networkidle")
                    time.sleep(0.3)
                    total = sum(r.sizes()["responseBodySize"] + r.sizes()["responseHeadersSize"] for r in list(requests))
                    file = os.path.join(OUT, f"{name}-{width}-{scheme}.png")
                    page.screenshot(path=file, full_page=True)
                    report[f"{name}-{width}-{scheme}"] = {
                        "initial_bytes": initial, "all_bytes": total, "requests": len(requests),
                        "messages": messages,
                        "resources": sorted({r.url.replace(BASE, "") for r in requests}),
                    }
                    ctx.close()
        browser.close()
    with open(os.path.join(os.path.dirname(__file__), "capture-report.json"), "w") as f:
        json.dump(report, f, indent=1)
    for key, r in report.items():
        flag = " MESSAGES" if r["messages"] else ""
        print(f"{key:28} initial {r['initial_bytes']/1024:6.1f} KiB  all {r['all_bytes']/1024:6.1f} KiB  {r['requests']:2} req{flag}")
        for m in r["messages"]:
            print("    ", m[:200])


if __name__ == "__main__":
    main()
