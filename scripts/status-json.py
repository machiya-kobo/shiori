#!/usr/bin/env python3
"""Writes OUT_DIR/_shiori/status.json for a hosted build (the house's status
page reads it): {"version", "build", "built", "hister"}. Shiori's version
is project.yml's MARKETING_VERSION, the build the commit's short hash (with
"-dirty" when the tree has changes), built the time in UTC, hister the
Hister release Shiori is built against (vendor/hister's tag, or the pinned
commit's short hash when the submodule isn't checked out). Nothing else:
no addresses, no settings.

    scripts/status-json.py OUT_DIR
"""
import datetime
import json
import os
import re
import subprocess
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = sys.argv[1] if len(sys.argv) > 1 else sys.exit("usage: status-json.py OUT_DIR")

with open(os.path.join(root, "project.yml"), encoding="utf-8") as f:
    m = re.search(r'MARKETING_VERSION:\s*"?([0-9][0-9A-Za-z.\-]*)"?', f.read())
version = m.group(1) if m else ""


def git(*args):
    try:
        return subprocess.run(["git", "-C", root, *args], capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


# A build with no git (a container's) says the commit and the Hister release itself.
build = os.environ.get("SHIORI_BUILD_ID") or git("rev-parse", "--short", "HEAD")
if build and not os.environ.get("SHIORI_BUILD_ID") and git("status", "--porcelain", "--untracked-files=no"):
    build += "-dirty"
# The tag when the submodule is checked out, else the commit the superproject pins.
hister = os.environ.get("SHIORI_HISTER_RELEASE") or git("-C", "vendor/hister", "describe", "--tags", "--exact-match")
if not hister:
    pinned = git("ls-tree", "HEAD", "vendor/hister").split()
    hister = pinned[2][:7] if len(pinned) > 2 else ""
built = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

os.makedirs(os.path.join(out, "_shiori"), exist_ok=True)
with open(os.path.join(out, "_shiori", "status.json"), "w", encoding="utf-8") as f:
    json.dump({"version": version, "build": build, "built": built, "hister": hister}, f)
    f.write("\n")
