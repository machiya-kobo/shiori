#!/usr/bin/env python3
"""Turn the staged Safari bundle (ShioriExtension/Resources) into a Firefox
one with the fewest changes, so what breaks in the spike is the shims, not
the packaging. Phase 2 of docs/firefox-plan.md replaces this.

    make-firefox.py SRC DST [MIN_VERSION]

MIN_VERSION lowers the floor (153, the current ESR) only to run on an
older Firefox.
"""
import json
import os
import shutil
import sys

src, dst = sys.argv[1:3]
floor = sys.argv[3] if len(sys.argv) > 3 else "153.0"
shutil.rmtree(dst, ignore_errors=True)
shutil.copytree(src, dst)
path = os.path.join(dst, "manifest.json")
m = json.load(open(path))
m["background"] = {"scripts": ["background.js"]}
m["browser_specific_settings"] = {
    "gecko": {
        "id": "shiori@machiya-kobo.github.io",
        "strict_min_version": floor,
        "data_collection_permissions": {"required": ["browsingActivity", "websiteContent"]},
    },
    "gecko_android": {"strict_min_version": floor},
}
m["content_security_policy"] = {"extension_pages": "script-src 'self'"}
m["incognito"] = "not_allowed"
json.dump(m, open(path, "w"), indent=2)
print("==> Firefox bundle:", dst)
