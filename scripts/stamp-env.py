#!/usr/bin/env python3
"""Stamps a build's settings into built files, replacing each `__SHIORI_NAME__`
placeholder with its value. The two build scripts call it with the environment
(a setting left unset leaves its placeholder, which the pages read as empty);
the shiori-web container calls `stamp()` with its own settings when it starts.

    scripts/stamp-env.py FILE...

Each placeholder, the setting that fills it (an older name after a slash):

    __SHIORI_KURA_URL__        SHIORI_KURA_URL / SHIORI_NIWA_URL
    __SHIORI_KONBINI_URL__     SHIORI_KONBINI_URL
    __SHIORI_SMALLWEB_URL__    SHIORI_SMALLWEB_URL
    __SHIORI_OBSIDIAN_VAULT__  SHIORI_OBSIDIAN_VAULT
    __SHIORI_SOURCE_URL__      SHIORI_SOURCE_URL
    __SHIORI_FRONTENDS__       SHIORI_FRONTENDS
    __SHIORI_AI__              SHIORI_AI ("1": the host has the AI companion)
    __SHIORI_FEED__            SHIORI_FEED ("off": the host has no feed service)
    __SHIORI_SIGNIN__          SHIORI_SIGNIN ("hister": Hister's own sign-in page)

The values land inside single-quoted JavaScript strings: one holding a quote,
a backslash or a control character is refused.
"""
import os
import re
import sys

PLACEHOLDERS = (
    ("__SHIORI_KURA_URL__", ("SHIORI_KURA_URL", "SHIORI_NIWA_URL")),
    ("__SHIORI_KONBINI_URL__", ("SHIORI_KONBINI_URL",)),
    ("__SHIORI_SMALLWEB_URL__", ("SHIORI_SMALLWEB_URL",)),
    ("__SHIORI_OBSIDIAN_VAULT__", ("SHIORI_OBSIDIAN_VAULT",)),
    ("__SHIORI_SOURCE_URL__", ("SHIORI_SOURCE_URL",)),
    ("__SHIORI_FRONTENDS__", ("SHIORI_FRONTENDS",)),
    ("__SHIORI_AI__", ("SHIORI_AI",)),
    ("__SHIORI_FEED__", ("SHIORI_FEED",)),
    ("__SHIORI_SIGNIN__", ("SHIORI_SIGNIN",)),
)
UNSAFE = re.compile(r"['\\\x00-\x1f\x7f]")


def values_from(environ):
    """{placeholder: value} for what the environment sets."""
    out = {}
    for placeholder, names in PLACEHOLDERS:
        value = next((environ[n] for n in names if environ.get(n)), "")
        if value:
            out[placeholder] = value
    return out


def stamp(text, values):
    """`text` with each placeholder in `values` replaced."""
    for placeholder, value in values.items():
        if UNSAFE.search(value):
            raise ValueError(f"{placeholder}: the value holds a quote, a backslash or a control character")
        text = text.replace(placeholder, value)
    return text


def main(paths):
    try:
        values = values_from(os.environ)
        stamp("", values)
    except ValueError as e:
        sys.exit(f"stamp-env: {e}")
    for path in paths:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        with open(path, "w", encoding="utf-8") as f:
            f.write(stamp(text, values))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
