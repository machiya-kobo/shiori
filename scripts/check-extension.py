#!/usr/bin/env python3
"""Check the built Safari extension bundle (scripts/build-extension.sh's
last step): every file the manifest names is there, Shiori's shims are in
place, and the manifest keeps the rules (no cookies, at most four suggested
shortcuts).

    check-extension.py ROOT [safari]
"""
import json
import os
import sys


def problems(root, target="safari"):
    m = json.load(open(os.path.join(root, "manifest.json")))
    out = []
    background = m.get("background") or {}
    options = m.get("options_page") or (m.get("options_ui") or {}).get("page")

    paths = list((m.get("icons") or {}).values())
    paths += list(((m.get("action") or {}).get("default_icon") or {}).values())
    paths += [background.get("service_worker")] + list(background.get("scripts") or [])
    paths += [(m.get("action") or {}).get("default_popup"), options]
    paths += [js for cs in m.get("content_scripts", []) for js in cs["js"]]
    missing = [p for p in paths if p and not os.path.isfile(os.path.join(root, p))]
    if missing:
        out.append("bundle is missing files named by the manifest: " + ", ".join(missing))
    if not options:
        out.append("manifest names no settings page")

    permissions = m.get("permissions", [])
    if "cookies" in permissions:
        out.append("manifest still asks for cookies")

    marks = {
        "background.js": ["const shioriHost", "installCaptureQueue", "installCombinedSearch"],
        "content.js": ["installPageSizeCap"],
        "popup.html": ["safari-popup.css", "shiori-popup.js"],
        "search.html": ["search-core.js", "search.js", "palettes.css"],
        # The rooms' other themes (web/app/palettes.css), for every page on search.css.
        "palettes.css": [':root[data-palette="nord"]'],
    }
    # The settings page shows what the app set.
    marks["shiori-options.html"] = ["shiori-options.js", "search.css"]
    if target != "safari":
        out.append("unknown target %r (Safari is the only one)" % target)

    marks["background.js"] += ["installIconShim", "root.ShioriSearch", "installQueueBadge", "installMenus"]
    if "contextMenus" not in permissions:
        out.append("Safari's right-click menu (ext/menus.js) needs contextMenus")
    # More than four suggested shortcuts and Safari drops the extension's
    # background without a word: nothing is captured and Safari's
    # searches stay on DuckDuckGo.
    suggested = [k for k, c in (m.get("commands") or {}).items() if c.get("suggested_key")]
    if len(suggested) > 4:
        out.append("manifest suggests %d shortcuts (%s); Safari allows at most 4" % (len(suggested), ", ".join(suggested)))

    for name, wanted in marks.items():
        path = os.path.join(root, name)
        if not os.path.isfile(path):
            out.append("%s is missing" % name)
            continue
        s = open(path, encoding="utf-8").read()
        out += ["%s is missing the %s shim" % (name, mark) for mark in wanted if mark not in s]
    return out


if __name__ == "__main__":
    found = problems(*sys.argv[1:3])
    if found:
        sys.exit("\n".join("error: " + p for p in found))
    print("==> Bundle ok: manifest files present, shims in place")
