#!/usr/bin/env python3
"""Fills a local Hister with a dozen invented pages, for the Quickstart.

    tools/quickstart/seed-hister.py [HISTER_URL]     (default http://127.0.0.1:4433/)

Every page is made up (hosts under .example, the paper-lantern workshop
and Kyoto trip of Machiya's sample vault), so screenshots and tests never show anyone's real history.
It waits up to a minute for Hister to answer, then adds the pages with
api/add. It refuses any Hister that isn't on this machine: a Quickstart
must never write to a real index. Stdlib only.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

URL = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:4433/").rstrip("/") + "/"
if urllib.parse.urlsplit(URL).hostname not in ("127.0.0.1", "localhost", "::1"):
    sys.exit(f"seed-hister: {URL} isn't on this machine; it only fills a local test Hister.")

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sampledata import DAY, NOW, PAGES  # noqa: E402

# Two collections ("@"-aliases over labels), so the sidebars have some.
COLLECTIONS = {"@crafts": "label:(lanterns|paper|workshop)", "@travel": "label:travel"}


def call(path, body=None, content_type="application/json"):
    request = urllib.request.Request(URL + path, data=body, headers={"Origin": "hister://", "Content-Type": content_type})
    with urllib.request.urlopen(request, timeout=10) as reply:
        return reply.status


for attempt in range(60):
    try:
        call("api/config")
        break
    except (urllib.error.URLError, ConnectionError, OSError):
        time.sleep(1)
else:
    sys.exit(f"seed-hister: {URL} didn't answer within a minute.")

for url, title, label, text, days in PAGES:
    html = f"<!doctype html><html><head><title>{title}</title></head><body><h1>{title}</h1><p>{text}</p></body></html>"
    page = {"url": url, "title": title, "html": html, "added": NOW - days * DAY + 3600 * (len(title) % 9),
            "metadata": {"source": "quickstart"}}
    if label:
        page["label"] = label
    status = call("api/add", json.dumps(page).encode())
    if status >= 300:
        sys.exit(f"seed-hister: {url} answered {status}.")
for keyword, value in COLLECTIONS.items():
    form = urllib.parse.urlencode({"alias-keyword": keyword, "alias-value": value}).encode()
    call("api/add_alias", form, "application/x-www-form-urlencoded")
print(f"Added {len(PAGES)} sample pages to {URL}")
