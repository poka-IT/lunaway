"""Checks every link, asset and fragment of the site through serve.py, and
the external links once each.

    python3 data/tmp/site/linkcheck.py [BASE_URL]
"""

import re
import sys
import urllib.error
import urllib.request
from html.parser import HTMLParser
from urllib.parse import urljoin, urldefrag, urlparse

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:18790"
START = ["/", "/en/", "/privacy", "/en/privacy", "/about", "/en/about", "/legal", "/en/legal",
         "/account/delete", "/en/account/delete", "/fdroid/", "/en/fdroid/", "/nope",
         "/robots.txt", "/sitemap.xml", "/favicon.ico", "/favicon.svg", "/favicon.png", "/apple-touch-icon.png",
         "/img/social-preview.png"]
UA = "lunaway-site-linkcheck (+https://lunaway.net)"


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs, self.ids = [], set()

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a:
            self.ids.add(a["id"])
        for key in ("href", "src"):
            if key in a and a[key]:
                self.refs.append(a[key])
        if tag == "meta" and a.get("property") in ("og:image", "og:url") or a.get("name") == "twitter:image":
            self.refs.append(a["content"])


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except Exception as e:  # noqa: BLE001
        return f"error {e}", b""


def main():
    pages, internal, external, fragments = {}, set(), set(), set()
    queue = list(START)
    seen = set()
    while queue:
        path = queue.pop()
        if path in seen:
            continue
        seen.add(path)
        status, body = fetch(BASE + path)
        expected = 404 if path == "/nope" else 200
        if status != expected:
            print(f"FAIL {path}: {status}")
        if path.endswith((".css",)):
            for ref in re.findall(r'url\("?([^")]+)"?\)', body.decode()):
                internal.add(urljoin(path, ref))
        if not body.lstrip().startswith(b"<!DOCTYPE html"):
            continue
        parser = Links()
        parser.feed(body.decode())
        pages[path] = parser.ids
        for ref in parser.refs:
            if ref.startswith("mailto:"):
                continue
            absolute = urljoin("https://lunaway.net" + path, ref)
            url, frag = urldefrag(absolute)
            host = urlparse(url).netloc
            if host == "lunaway.net":
                local = urlparse(url).path
                if local.startswith("/app/") or local == "/app":
                    external.add(url)
                    continue
                if frag:
                    fragments.add((local, frag, path))
                if local not in seen:
                    queue.append(local)
                internal.add(local)
            else:
                external.add(url)
    for local in sorted(internal - seen):
        status, _ = fetch(BASE + local)
        print(("ok  " if status == 200 else "FAIL") + f" asset {local}: {status}")
    bad_frag = 0
    for local, frag, origin in sorted(fragments):
        ids = pages.get(local)
        if ids is None or frag not in ids:
            bad_frag += 1
            print(f"FAIL fragment {local}#{frag} (from {origin})")
    print(f"internal pages and files: {len(seen | internal)}, fragments checked: {len(fragments)}, broken fragments: {bad_frag}")
    for url in sorted(external):
        status, _ = fetch(url)
        print(f"external {status} {url}")


if __name__ == "__main__":
    main()
