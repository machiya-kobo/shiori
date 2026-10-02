#!/usr/bin/env python3
"""Check a built extension bundle (scripts/build-extension.sh's last step):
every file the manifest names is there, Shiori's shims are in place, and
the manifest keeps the rules (no cookies; on Firefox no native messaging,
never in private windows, the fixed ID, update URL and floor).

    check-extension.py ROOT TARGET     (TARGET: safari or firefox)
"""
import json
import os
import sys

FIREFOX_ID = "shiori@machiya-kobo.github.io"
FIREFOX_UPDATE_URL = "https://github.com/machiya-kobo/shiori/releases/latest/download/updates.json"


def problems(root, target):
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
        "search.html": ["search-core.js", "search.js"],
    }
    # The settings page: Safari's shows what the app set, Firefox's sets them.
    if target == "safari":
        marks["shiori-options.html"] = ["shiori-options.js", "search.css"]
    else:
        marks["shiori-settings.html"] = ["shiori-settings.js", "shiori-settings-file.js", "shiori-settings.css", "search.css"]
        if options != "shiori-settings.html":
            out.append("Firefox's settings page must be shiori-settings.html (there's no app to set them)")

    if target == "safari":
        marks["background.js"].append("installIconShim")
        # More than four suggested shortcuts and Safari drops the extension's
        # background without a word: nothing is captured and Safari's
        # searches stay on DuckDuckGo.
        suggested = [k for k, c in (m.get("commands") or {}).items() if c.get("suggested_key")]
        if len(suggested) > 4:
            out.append("manifest suggests %d shortcuts (%s); Safari allows at most 4" % (len(suggested), ", ".join(suggested)))
    elif target == "firefox":
        marks["background.js"] += ["shioriLocalSettings", "root.ShioriSearch", "installOmnibox", "installQueueBadge"]
        if not (m.get("omnibox") or {}).get("keyword"):
            out.append("Firefox's address-bar keyword (omnibox) is missing")
        if background.get("scripts") != ["background.js"] or "service_worker" in background:
            out.append("Firefox's background must be scripts: [background.js] (an event page)")
        if "nativeMessaging" in permissions:
            out.append("Firefox has no app to message: drop nativeMessaging")
        if m.get("incognito") != "not_allowed":
            out.append('Firefox must never load in private windows: incognito "not_allowed"')
        bss = m.get("browser_specific_settings") or {}
        gecko, android = bss.get("gecko") or {}, bss.get("gecko_android") or {}
        if gecko.get("id") != FIREFOX_ID:
            out.append("the add-on ID must stay %s (signing and updates follow it)" % FIREFOX_ID)
        if gecko.get("update_url") != FIREFOX_UPDATE_URL:
            out.append("the update URL must be %s" % FIREFOX_UPDATE_URL)
        floor = gecko.get("strict_min_version")
        if not floor or android.get("strict_min_version") != floor:
            out.append("desktop and Android need the same strict_min_version (the current ESR)")
    else:
        out.append("unknown target %r" % target)

    for name, wanted in marks.items():
        path = os.path.join(root, name)
        if not os.path.isfile(path):
            out.append("%s is missing" % name)
            continue
        s = open(path, encoding="utf-8").read()
        out += ["%s is missing the %s shim" % (name, mark) for mark in wanted if mark not in s]
    if target == "firefox":
        s = open(os.path.join(root, "background.js"), encoding="utf-8").read()
        if "__SHIORI_APP_ID__" in s or "sendNativeMessage" in s:
            out.append("Firefox's background.js carries the app's native messaging (host-native.js)")
    return out


if __name__ == "__main__":
    found = problems(*sys.argv[1:3])
    if found:
        sys.exit("\n".join("error: " + p for p in found))
    print("==> Bundle ok: manifest files present, shims in place")
