#!/usr/bin/env python3
"""Stamps the Machiya rooms' addresses into built files.

    scripts/rooms-stamp.py FILE...

Replaces '__SHIORI_ROOMS__' with "key=url,key=url" for the Rooms switcher
(search-core.js's S.rooms): SHIORI_ROOMS from the environment (e.g.
"konbini=https://konbini.example/,niwa=https://niwa.example/,
hister=https://hister.example/,searxng=https://searxng.example/"), with
Kura and Konbini filled from SHIORI_KURA_URL (or its older name,
SHIORI_NIWA_URL) and SHIORI_KONBINI_URL when
it doesn't name them, and Hister and SearXNG from SHIORI_SERVER_URL and
SHIORI_SEARXNG_URL (the extension's build has those). The hostnames stay out of the repo: the server (or
local.yml) passes them in. Unset, the placeholder stays and the switcher
lists only what the page knows (its own Shiori).
"""
import os
import sys

rooms = {}
for pair in os.environ.get("SHIORI_ROOMS", "").split(","):
    key, _, url = pair.partition("=")
    if key.strip() and url.strip():
        rooms[key.strip().lower()] = url.strip()
if not os.environ.get("SHIORI_KURA_URL", "").strip() and os.environ.get("SHIORI_NIWA_URL", "").strip():
    os.environ["SHIORI_KURA_URL"] = os.environ["SHIORI_NIWA_URL"]
for key, name in (
    ("kura", "SHIORI_KURA_URL"),
    ("konbini", "SHIORI_KONBINI_URL"),
    ("hister", "SHIORI_SERVER_URL"),
    ("searxng", "SHIORI_SEARXNG_URL"),
):
    if key not in rooms and os.environ.get(name, "").strip():
        rooms[key] = os.environ[name].strip()
if not rooms:
    sys.exit(0)
value = ",".join(f"{k}={v}" for k, v in rooms.items())
if "'" in value or "\\" in value:
    sys.exit("rooms-stamp: an address holds a quote or backslash")
for path in sys.argv[1:]:
    with open(path) as f:
        text = f.read()
    if "__SHIORI_ROOMS__" not in text:
        sys.exit(f"rooms-stamp: no __SHIORI_ROOMS__ in {path}")
    with open(path, "w") as f:
        f.write(text.replace("__SHIORI_ROOMS__", value))
