#!/usr/bin/env python3
"""Fills __SHIORI_STATUS_URL__ (your server's status page) in a page, or
drops the lines that hold it when no address is given, so the repo never
names the host. Usage: status-link.py FILE [URL]. URL `@runtime` leaves the
placeholder for the shiori-web image to fill when it starts."""
import sys

path, url = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "").strip()
if url == "@runtime":              # the shiori-web image fills it, or drops it, when it starts
    sys.exit(0)
if url and not url.startswith(("https://", "http://")):
    sys.exit(f"status-link: {url!r} must start with http:// or https://")
text = open(path, encoding="utf-8").read()
if "__SHIORI_STATUS_URL__" not in text:
    sys.exit(f"status-link: no __SHIORI_STATUS_URL__ in {path}")
if url:
    text = text.replace("__SHIORI_STATUS_URL__", url.replace("&", "&amp;").replace('"', "&quot;"))
else:
    text = "".join(line for line in text.splitlines(keepends=True) if "__SHIORI_STATUS_URL__" not in line)
open(path, "w", encoding="utf-8").write(text)
