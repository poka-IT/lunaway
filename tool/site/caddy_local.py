"""The lunaway.net part of infra/tests/caddy-layout.sh, with a native Caddy
2.11.7 binary instead of the Docker image (Docker is down on this Mac).
Renders infra/caddy/ the way the test does (plain HTTP, no admin API, test
roots), serves infra/web/site as the site root, and checks the routes,
headers and pages of the landing site.

    python3 data/tmp/site/caddy_local.py
"""

import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
RUN = os.path.join(HERE, "caddy-run")
CADDY = os.path.join(HERE, "bin", "caddy")
PORT = 18080
SITE = os.path.join(REPO, "infra", "web", "site")


def render():
    os.makedirs(os.path.join(RUN, "web"), exist_ok=True)
    os.makedirs(os.path.join(RUN, "data", "media"), exist_ok=True)
    os.makedirs(os.path.join(RUN, "tiles"), exist_ok=True)
    with open(os.path.join(RUN, "web", "index.html"), "w") as f:
        f.write('<!doctype html><base href="/app/"><title>app</title>\n')
    main = open(os.path.join(REPO, "infra", "caddy", "Caddyfile")).read()
    main = main.replace("admin unix//run/caddy/admin.sock", "admin off")
    main = re.sub(r"acme_ca .*", "auto_https off", main)
    main = main.replace("import /etc/caddy/sites-enabled/*.caddy", f"import {RUN}/lunaway.net.caddy")
    main = main.replace("/srv/data", f"{RUN}/data").replace("/srv/tiles", f"{RUN}/tiles")
    main = main.replace("output file /var/log/caddy/access.log", f"output file {RUN}/access.log")
    with open(os.path.join(RUN, "Caddyfile"), "w") as f:
        f.write(main)
    site = open(os.path.join(REPO, "infra", "caddy", "lunaway.net.caddy")).read()
    for host in ("api.lunaway.net", "lunaway.net", "www.lunaway.net", "tiles.lunaway.net"):
        site = re.sub(rf"^{re.escape(host)} {{", f"http://{host}:{PORT} {{", site, flags=re.M)
    site = site.replace("/srv/lunaway/site", SITE).replace("/srv/lunaway/web", f"{RUN}/web")
    # Loopback only: the test sites must not answer on the local network.
    site = re.sub(rf"^(http://[a-z.]+:{PORT} {{)$", r"\1\n\tbind 127.0.0.1", site, flags=re.M)
    main = open(os.path.join(RUN, "Caddyfile")).read()
    main = re.sub(rf"^(http://[a-z.]+:{PORT} {{)$", r"\1\n\tbind 127.0.0.1", main, flags=re.M)
    main = main.replace("http://:8484 {", "http://127.0.0.1:8484 {")
    with open(os.path.join(RUN, "Caddyfile"), "w") as f:
        f.write(main)
    with open(os.path.join(RUN, "lunaway.net.caddy"), "w") as f:
        f.write(site)


failures = 0


def curl(url, *extra):
    host = re.match(r"http://([^:/]+):", url).group(1)
    out = subprocess.run(["curl", "-sS", "-D", "-", "-o", os.path.join(RUN, "body.out"),
                          "--connect-to", f"{host}:{PORT}:127.0.0.1:{PORT}", *extra, url],
                         capture_output=True, text=True, check=False)
    path = os.path.join(RUN, "body.out")
    return out.stdout, open(path, "rb").read() if os.path.exists(path) else b""


def check(name, url, status, header=None, absent=None, body=None):
    global failures
    headers, data = curl(url)
    got = headers.split("\n", 1)[0].split(" ")[1] if headers else "none"
    ok = got == str(status)
    if header and not re.search(header, headers, re.I | re.M):
        ok = False
    if absent and re.search(absent, headers, re.I | re.M):
        ok = False
    if body and body.encode() not in data:
        ok = False
    if not ok:
        failures += 1
    print(("ok   " if ok else "FAIL ") + f"{name}: {got}" + ("" if ok else f" (want {status}) {header or ''} {absent or ''} {body or ''}"))


def main():
    render()
    subprocess.run([CADDY, "validate", "--config", os.path.join(RUN, "Caddyfile"), "--adapter", "caddyfile"],
                   check=True, capture_output=True)
    print("ok   caddy validate")
    log = open(os.path.join(RUN, "caddy.log"), "w")
    proc = subprocess.Popen([CADDY, "run", "--config", os.path.join(RUN, "Caddyfile"), "--adapter", "caddyfile"],
                            stdout=log, stderr=log)
    if "--serve" in sys.argv:
        print(f"serving on 127.0.0.1:{PORT}; stop with Ctrl-C")
        proc.wait()
        return 0
    try:
        for _ in range(40):
            if curl(f"http://lunaway.net:{PORT}/")[0]:
                break
            time.sleep(0.25)
        css = next(n for n in os.listdir(SITE) if re.match(r"style\.[0-9a-f]+\.css$", n))
        js = next(n for n in os.listdir(os.path.join(SITE, "js")) if n.startswith("delete-account."))
        font = next(n for n in os.listdir(os.path.join(SITE, "fonts")) if n.startswith("atkinson-next-lunaway-regular."))
        L = f"http://lunaway.net:{PORT}"
        no_script = r"^content-security-policy: default-src 'none'; style-src 'self'; img-src 'self' data:; font-src 'self'; base-uri 'none'"
        delete_csp = r"^content-security-policy: default-src 'none'; script-src 'self'; connect-src https://api\.lunaway\.net; style-src 'self'"
        check("landing", f"{L}/", 200, no_script, absent="script-src")
        check("landing html cache", f"{L}/", 200, r"^cache-control: public, max-age=300")
        check("hashed stylesheet", f"{L}/{css}", 200, r"^cache-control: public, max-age=31536000, immutable")
        check("stylesheet type", f"{L}/{css}", 200, r"^content-type: text/css")
        check("font", f"{L}/fonts/{font}", 200, r"^content-type: font/woff2")
        check("screenshot", f"{L}/img/screens/fr-1-map.webp", 200, r"^content-type: image/webp")
        check("screenshot cache", f"{L}/img/screens/fr-1-map.webp", 200, r"^cache-control: public, max-age=300")
        for path in ("/en/", "/en", "/privacy", "/en/privacy", "/about", "/en/about", "/legal", "/en/legal",
                     "/fdroid/", "/fdroid", "/en/fdroid/"):
            check(path, f"{L}{path}", 200, no_script, absent="script-src")
        for path in ("/account/delete", "/en/account/delete", "/account/delete.html"):
            check(path, f"{L}{path}", 200, delete_csp)
        check("/account/delete has one CSP", f"{L}/account/delete", 200,
              absent=r"(?s)content-security-policy.*content-security-policy")
        check("deletion script", f"{L}/js/{js}", 200, r"^content-type: text/javascript")
        check("deletion script cache", f"{L}/js/{js}", 200, r"immutable")
        check("robots.txt", f"{L}/robots.txt", 200, r"^content-type: text/plain")
        check("sitemap.xml", f"{L}/sitemap.xml", 200, r"^content-type: (text|application)/xml")
        check("favicon.ico", f"{L}/favicon.ico", 200)
        check("unknown page", f"{L}/nope", 404, no_script, absent="script-src", body="This page does not exist")
        check("unknown page under /en/", f"{L}/en/nope", 404, body="Page introuvable")
        check("unknown page headers", f"{L}/nope", 404, r"^strict-transport-security: max-age=31536000; includeSubDomains")
        check("unknown page frame denial", f"{L}/nope", 404, r"^x-frame-options: DENY")
        check("unknown page no Server header", f"{L}/nope", 404, absent=r"^server:")
        check("unknown page cache", f"{L}/nope", 404, r"^cache-control: public, max-age=300")
        check("landing no Server header", f"{L}/", 200, absent=r"^server:")
        check("/app redirect", f"{L}/app", 301, r"^location: /app/")
        check("/app/ keeps its CSP", f"{L}/app/", 200, r"wasm-unsafe-eval")
        check("www redirect", f"http://www.lunaway.net:{PORT}/privacy", 301, r"^location: https://lunaway.net/privacy")
        check("no media on the site", f"{L}/media/ab/0123abcd.jpg", 404)
    finally:
        proc.terminate()
        proc.wait(timeout=10)
        log.close()
    print(f"{failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
