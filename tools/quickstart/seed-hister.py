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
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

URL = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:4433/").rstrip("/") + "/"
if urllib.parse.urlsplit(URL).hostname not in ("127.0.0.1", "localhost", "::1"):
    sys.exit(f"seed-hister: {URL} isn't on this machine; it only fills a local test Hister.")

DAY = 86400
NOW = int(time.time()) // DAY * DAY
# (url, title, label, text, days ago): the paper-lantern workshop and the
# Kyoto trip of Machiya's sample vault.
PAGES = [
    ("https://lanterns.example/chochin-folding", "Folding a chōchin lantern", "lanterns",
     "A chōchin collapses flat: a spiral bamboo rib under washi, folded along each turn of the spiral.", 0),
    ("https://lanterns.example/bamboo-frames", "Bending bamboo frames with steam", "lanterns",
     "Steam the split bamboo for ten minutes, bend it round a jig, and let it set overnight.", 1),
    ("https://washi.example/making", "How washi paper is made", "paper",
     "Kozo bark is soaked, beaten and spread on a screen; the long fibres make the paper strong.", 1),
    ("https://washi.example/kinds", "Kozo, mitsumata and gampi", "paper",
     "Three plants give washi its character: kozo is tough, mitsumata smooth, gampi glossy.", 2),
    ("https://paste.example/nori", "Nori paste for paper and bamboo", "workshop",
     "Wheat-starch nori paste holds washi to bamboo and stays reversible with a damp brush.", 3),
    ("https://light.example/candle-vs-led", "Candle or LED inside a paper lantern?", "lanterns",
     "A candle gives a warm flicker but scorches washi; a warm-white LED runs cool and safe.", 4),
    ("https://bamboo.example/sourcing", "Sourcing bamboo for craft work", "workshop",
     "Cut madake in winter, when the culms hold less sugar and resist beetles.", 5),
    ("https://kyoto.example/lantern-festival", "Kyoto's summer lantern festival", "travel",
     "Thousands of lanterns line the lanes after dark; arrive early and walk up from the river.", 6),
    ("https://kyoto.example/machiya", "Staying in a Kyoto machiya townhouse", "travel",
     "Machiya are narrow wooden townhouses with a shop at the front and a small garden at the back.", 8),
    ("https://travel.example/packing-japan", "Packing light for two weeks in Japan", "travel",
     "One carry-on, layers, slip-on shoes for temples, and a small towel for the trains.", 10),
    ("https://workbench.example/layout", "Laying out a small craft workbench", "workshop",
     "Keep cutting on the left, gluing on the right, and drying racks above the bench.", 12),
    ("https://lanterns.example/restoring", "Restoring an old paper lantern", "lanterns",
     "Strip the torn washi, re-glue loose ribs with nori, and re-cover one panel at a time.", 15),
]


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
