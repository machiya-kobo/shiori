#!/usr/bin/env python3
"""Fails a web build that references a file it doesn't ship.

    scripts/check-assets.py OUT

Reads every page (.html), manifest (.webmanifest) and stylesheet (.css) in
OUT and checks that each local file they name exists in OUT: a relative
address, anything under /_shiori/, and a root file such as /sw.js. Other
root paths (/searx/, /kura/, Hister's API…) are routes the host proxies,
not files, and are left alone, as are other origins, data: URIs and links
within the page (?…, #…). Both web builds run it last (scripts/build-web.sh,
scripts/build-pwa.sh): a logo the build didn't rewrite showed broken on the
hosted page.
"""

import json
import os
import re
import sys
from urllib.parse import urlsplit, unquote

ATTR = re.compile(r'\b(?:src|href)\s*=\s*"([^"]*)"')
CSS_URL = re.compile(r'url\(\s*[\'"]?([^\'")]+)[\'"]?\s*\)')


def local_file(ref, page, out):
    """The file in OUT a reference names, or None when it isn't one of ours."""
    ref = ref.strip()
    # A placeholder a later step fills (the shiori-web image stamps its settings when it starts) names no file yet.
    if not ref or ref.startswith(("#", "?", "data:", "mailto:", "javascript:", "//", "__SHIORI_")):
        return None
    parts = urlsplit(ref)
    if parts.scheme or parts.netloc:
        return None
    path = unquote(parts.path)
    if not path:
        return None
    if path.startswith("/"):
        first = path.lstrip("/").split("/", 1)[0]
        # /_shiori/… is the build's; /name.ext at the root is a file; the
        # rest are proxied routes.
        if not (path.startswith("/_shiori/") or ("/" not in path.lstrip("/") and "." in first)):
            return None
        return os.path.join(out, path.lstrip("/"))
    return os.path.normpath(os.path.join(os.path.dirname(page), path))


def references(page):
    text = open(page, encoding="utf-8").read()
    if page.endswith(".webmanifest"):
        data = json.loads(text)
        refs = [i.get("src", "") for i in data.get("icons", [])]
        for s in data.get("shortcuts", []):
            refs += [i.get("src", "") for i in s.get("icons", [])]
        return refs
    if page.endswith(".css"):
        return CSS_URL.findall(text)
    return ATTR.findall(text)


def missing(out):
    gone = []
    for root, _, files in os.walk(out):
        for name in files:
            if not name.endswith((".html", ".webmanifest", ".css")):
                continue
            page = os.path.join(root, name)
            for ref in references(page):
                target = local_file(ref, page, out)
                if target and not os.path.isfile(target):
                    gone.append(f"{os.path.relpath(page, out)}: {ref}")
    return gone


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: check-assets.py OUT")
    gone = missing(sys.argv[1])
    if gone:
        sys.exit("check-assets: referenced but not in the build:\n  " + "\n  ".join(gone))


if __name__ == "__main__":
    main()
