#!/usr/bin/env python3
"""Fills a local Hister with a dozen invented pages, for the Quickstart.

    tools/quickstart/seed-hister.py [HISTER_URL]     (default http://127.0.0.1:4433/)
    HISTER_TOKEN=… tools/quickstart/seed-hister.py URL   (a test Hister with an access token)
    tools/quickstart/seed-hister.py --notes URL       (the sample notes too, as Kura pushes them)

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

ARGS = [a for a in sys.argv[1:] if a != "--notes"]
WITH_NOTES = "--notes" in sys.argv[1:]
URL = (ARGS[0] if ARGS else "http://127.0.0.1:4433/").rstrip("/") + "/"
if urllib.parse.urlsplit(URL).hostname not in ("127.0.0.1", "localhost", "::1"):
    sys.exit(f"seed-hister: {URL} isn't on this machine; it only fills a local test Hister.")

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sampledata import DAY, NOW, NOTES, PAGES  # noqa: E402

# Two collections ("@"-aliases over labels), so the sidebars have some.
COLLECTIONS = {"@crafts": "label:(lanterns|paper|workshop)", "@travel": "label:travel"}


def call(path, body=None, content_type="application/json"):
    headers = {"Origin": "hister://", "Content-Type": content_type}
    if os.environ.get("HISTER_TOKEN"):          # a test Hister with app.access_token set
        headers["X-Access-Token"] = os.environ["HISTER_TOKEN"]
    request = urllib.request.Request(URL + path, data=body, headers=headers)
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
if WITH_NOTES:
    # The sample vault's notes as Kura's push sends them (kura/app/push.py): label vault, its
    # metadata, the note's Kura address. Plus one note under another vault's address, which
    # Kura never pushes from a private vault: there only so a test sees every client hide it.
    import html as _html
    kura = "https://kura.example/"
    notes = [(path, tags, days, summary, items, False) for path, tags, days, summary, items in NOTES]
    notes.append(("Plans/Quarterly lanterns budget", ["work"], 1, "A lantern budget from another vault: never shown.",
                  ["Hidden from every Shiori"], True))
    for path, tags, days, summary, items, other in notes:
        name = path.rsplit("/", 1)[-1]
        url = kura + ("v/work/" if other else "") + "n/" + urllib.parse.quote(path)
        body = "<h1>%s</h1><p>%s</p><ul>%s</ul>" % (
            _html.escape(name), _html.escape(summary), "".join("<li>%s</li>" % _html.escape(i) for i in items))
        doc = {"url": url, "title": name, "text": summary + "\n" + "\n".join(items), "label": "vault",
               "html": "<!doctype html><html><head><title>%s</title></head><body>%s</body></html>" % (_html.escape(name), body),
               "added": NOW - days * DAY,
               "metadata": {"source": "vault", "tags": tags, "vault_path": path + ".md", "vault_published": False,
                            "ignore_skip_rules": True}}
        status = call("api/add", json.dumps(doc).encode())
        if status >= 300:
            sys.exit(f"seed-hister: {url} answered {status}.")
    print(f"Added {len(PAGES)} sample pages and {len(notes)} notes to {URL}")
else:
    print(f"Added {len(PAGES)} sample pages to {URL}")
