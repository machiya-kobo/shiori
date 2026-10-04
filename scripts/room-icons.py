#!/usr/bin/env python3
"""Writes the Machiya rooms' icons into the web pages' stylesheets.

    scripts/room-icons.py [--logos DIR] [FILE…]

The rooms' icons are the Machiya rooms' home-screen icons, and the house's
(machiya.svg, its landing and status page), copied to assets/rooms/. The neighbours, Hister and SearXNG, get neutral line glyphs
(assets/rooms/neutral/): the repository carries no other project's logo.
`--logos DIR` puts their own logos in instead, read from DIR (hister.png
and searxng.svg, which a build keeps outside the repository and names in
SHIORI_ROOM_LOGOS: local.yml, or the web builds' environment).

They go in as data URIs, between the ROOM ICONS markers. Without FILEs: the
committed search.css and web/app/app.css (always the neutral set; run it
after changing an icon). With FILEs: those (a build's copies, which the
build scripts rewrite for --logos).
"""
import base64
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ROOMS = ["shiori.svg", "konbini.svg", "niwa.svg", "kura.svg", "machiya.svg"]
NEUTRAL = ["neutral/hister.svg", "neutral/searxng.svg"]
LOGOS = ["hister.png", "searxng.svg"]
START = "/* ROOM ICONS (scripts/room-icons.py from assets/rooms/; don't edit by hand) */"
END = "/* END ROOM ICONS */"

args = sys.argv[1:]
logos = None
if "--logos" in args:
    at = args.index("--logos")
    if at + 1 >= len(args):
        sys.exit("--logos needs the folder holding hister.png and searxng.svg")
    logos = pathlib.Path(args[at + 1]).expanduser()
    if not logos.is_absolute():
        logos = ROOT / logos
    del args[at:at + 2]
    missing = [n for n in LOGOS if not (logos / n).is_file()]
    if missing:
        sys.exit(f"{logos}: missing {', '.join(missing)}")
files = args

rules = []
rooms = ROOT / "assets/rooms"
for path in [rooms / n for n in ROOMS] + ([logos / n for n in LOGOS] if logos else [rooms / n for n in NEUTRAL]):
    room, _, kind = path.name.partition(".")
    mime = "image/png" if kind == "png" else "image/svg+xml"
    data = base64.b64encode(path.read_bytes()).decode()
    rules.append(f'.room-icon[data-room="{room}"] {{ background-image: url("data:{mime};base64,{data}"); }}')
block = "\n".join([START, *rules, END])

targets = [pathlib.Path(f) for f in files] or [ROOT / "patches/shiori/search.css", ROOT / "web/app/app.css"]
for path in targets:
    text = path.read_text()
    if START in text:
        text = re.sub(re.escape(START) + r".*?" + re.escape(END), lambda _: block, text, flags=re.S)
    elif files:
        sys.exit(f"{path}: no ROOM ICONS block")
    else:
        text = text.rstrip("\n") + "\n\n" + block + "\n"
    path.write_text(text)
    print(f"==> {path}{' (logos)' if logos else ''}")
