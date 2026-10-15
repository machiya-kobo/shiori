#!/usr/bin/env python3
"""Serves Shiori's web page locally, routed as its host routes it.

    scripts/build-web.sh /tmp/shiori-site http://localhost:8765/
    HISTER_URL=https://hister.example/ SEARXNG_URL=https://search.example/ \\
    KONBINI_URL=https://konbini.example/ web/dev-server.py /tmp/shiori-site

Routes (the same as web/README.md asks of the real host):
  /, /_shiori/*, and (the web app) /sw.js, /manifest.webmanifest: the build
  /basic               Basic Search, rendered here by web/basic.mjs under Node
                       (scripts/basic-dev.mjs), as the image's njs renders it
  /searx/*             SearXNG, prefix removed
  /konbini/*           Konbini, prefix removed (only api/cards is used)
  /kura/<path>         Kura, prefix removed, for only the paths Shiori asks
                       for (KURA_PATHS); anything else under /kura/ is a 404
  /smallweb/*          the small-web gateway, prefix removed (api/search, api/save)
  /jellyfin/, /plex/,  the media services (JELLYFIN_URL and JELLYFIN_TOKEN, and so
  /koito/, /movary/    on), prefix removed: GET only, the read paths shiori-web
                       passes (configure.py's MEDIA), the token added here
  anything else        the Hister host (Hister's API, /shiori/feed,
                       /shiori/ai/*)

AI_STUB=1 answers /shiori/ai/* here instead (for a build made with
SHIORI_AI=1: without it the pages never ask), with a canned summary or
answer (a URL or query containing "fail-<code>", e.g. fail-cap, answers
that error), since the real endpoint refuses a localhost origin.

Requests pass through unchanged: in particular no `Origin: hister://` is
added, so Hister's own check (same-origin allowed, cross-site refused)
still guards writes. One exception: the Machiya sign-ins' cookies (the
rooms' `machiya_session` and Hister's sign-in helper's `machiya_sso`) go
only to the rooms, /kura/ and /konbini/, and are taken out of the Cookie
header everywhere else (Hister, SearXNG, the gateway), as the hosts'
shiori-routes.inc does. Replies pass back as they are, Set-Cookie included. For testing
only; stdlib, no dependencies.
"""

import http.server
import importlib.util
import json
import os
import re
import subprocess
import time
import sys
import urllib.error
import urllib.request

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "/tmp/shiori-site")
PORT = int(os.environ.get("PORT", "8765"))
UPSTREAMS = {
    "/searx/": os.environ.get("SEARXNG_URL", ""),
    "/konbini/": os.environ.get("KONBINI_URL", ""),
    "/kura/": os.environ.get("KURA_URL", ""),
    "/smallweb/": os.environ.get("SMALLWEB_URL", ""),
}
# What Shiori asks Kura for. Kura's reader pages stay at Kura's own address:
# under /kura/ a work vault's note would have an address Shiori can't tell
# from any other page's (it looks for /v/ at the start of the path).
KURA_PATHS = {"api/search", "api/recent", "api/note", "api/vaults", "api/prefs", "feed.xml"}
NOT_ROUTED = ""  # route()'s answer for a path no one serves here
HISTER = os.environ.get("HISTER_URL", "")
# The media services: the paths and token headers are shiori-web's own (configure.py's MEDIA), so the two agree.
_spec = importlib.util.spec_from_file_location(
    "shiori_web_configure", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docker", "shiori-web", "configure.py"))
_configure = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_configure)
MEDIA = {name: (os.environ.get(f"{name.upper()}_URL", ""), os.environ.get(f"{name.upper()}_TOKEN", ""), header, re.compile(f"^({paths})$"))
         for name, (header, paths) in _configure.MEDIA.items()}
# The Hister sign-in helper's /machiya/ paths (sign-in, the account's
# preferences): on Hister's host, as in production, unless MACHIYA_URL
# names another (a stand-in for testing). The path is kept whole.
MACHIYA = os.environ.get("MACHIYA_URL", "")
AI_STUB = os.environ.get("AI_STUB") == "1"
AI_ERRORS = {"cap": 429, "note": 403, "not_indexed": 404, "empty": 422, "engine": 502, "declined": 502, "unavailable": 503, "no_results": 422, "searx": 504}
# The paths whose upstream is a Machiya room, which may read the sign-in cookie.
ROOMS = ("/kura/", "/konbini/")
# The sign-ins' cookies: the rooms' session (identity file) and Hister's
# sign-in helper's (whose nginx adds Hister's own session on its hop).
SESSION_COOKIES = ("machiya_session", "machiya_sso")
HOP = {"connection", "keep-alive", "transfer-encoding", "upgrade", "host", "content-length", "proxy-connection"}


def without_session(cookie):
    """A Cookie header without the Machiya sign-ins' cookies ('' when nothing is left)."""
    kept = [part.strip() for part in cookie.split(";")
            if part.strip() and part.split("=", 1)[0].strip() not in SESSION_COOKIES]
    return "; ".join(kept)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def route(self):
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html", "/sw.js", "/manifest.webmanifest") or path.startswith("/_shiori/"):
            return None
        if MACHIYA and self.path.startswith("/machiya/"):
            return MACHIYA.rstrip("/") + self.path
        for name, (base, token, _, paths) in MEDIA.items():
            if self.path.startswith(f"/{name}/"):
                rest = self.path[len(name) + 2:]
                if not (base and token) or not paths.match(rest.split("?", 1)[0]):
                    return NOT_ROUTED
                return base.rstrip("/") + "/" + rest
        for prefix, base in UPSTREAMS.items():
            if self.path.startswith(prefix):
                if prefix == "/kura/" and path[len(prefix):] not in KURA_PATHS:
                    return NOT_ROUTED
                return base.rstrip("/") + "/" + self.path[len(prefix):]
        return HISTER.rstrip("/") + self.path

    def proxy(self, target):
        body = None
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            body = self.rfile.read(length)
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP}
        media = next((m for name, m in MEDIA.items() if self.path.startswith(f"/{name}/")), None)
        if media:
            # Nothing of the browser's: no cookie, no Authorization; Shiori's token instead.
            headers = {k: v for k, v in headers.items() if k.lower() not in ("cookie", "authorization", "x-plex-token")}
            field, value = media[2].format(t=media[1]).split(" ", 1)
            headers[field] = value.strip('"')
        elif not self.path.startswith(ROOMS):
            for key in [k for k in headers if k.lower() == "cookie"]:
                rest = without_session(headers.pop(key))
                if rest:
                    headers[key] = rest
        request = urllib.request.Request(target, data=body, headers=headers, method=self.command)
        try:
            response = urllib.request.urlopen(request, timeout=30)
            status, reply_headers, data = response.status, response.headers, response.read()
        except urllib.error.HTTPError as error:
            status, reply_headers, data = error.code, error.headers, error.read()
        except Exception as error:  # unreachable upstream
            self.send_error(502, str(error))
            return
        self.send_response(status)
        for key, value in reply_headers.items():
            if key.lower() not in HOP:
                self.send_header(key, value)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def reply_json(self, status, value):
        data = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def ai_stub(self):
        path = self.path.split("?", 1)[0]
        if path == "/shiori/ai/status" and self.command == "GET":
            return self.reply_json(200, {"enabled": True, "answer": True, "engine": "anthropic", "model": "claude-sonnet-5-5", "remaining": 99})
        if path == "/shiori/ai/answer" and self.command == "POST":
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
            q = body.get("q") or ""
            failure = re.search(r"fail-(\w+)", q)
            if failure and failure.group(1) in AI_ERRORS:
                return self.reply_json(AI_ERRORS[failure.group(1)], {"error": failure.group(1), "message": "Stubbed failure."})
            time.sleep(1.5)
            return self.reply_json(200, {
                "answer": f"A stub answer about {q} [1], with a second source [2].\n• A point from the first [1].\n• One from the third [3].",
                "sources": [
                    {"n": 1, "title": "Example one", "url": "https://example.com/one"},
                    {"n": 2, "title": "Example &#34;two&#34;", "url": "https://example.org/two"},
                    {"n": 3, "title": "Example three", "url": "https://example.net/three"},
                    {"n": 4, "title": "Not cited", "url": "https://example.edu/four"},
                ],
                "engine": "anthropic", "model": "claude-sonnet-5-5", "cached": not body.get("refresh"),
            })
        if path != "/shiori/ai/summarize" or self.command != "POST":
            return self.reply_json(404, {"error": "not_found", "message": "No such endpoint."})
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
        url = body.get("url") or ""
        failure = re.search(r"fail-(\w+)", url)
        if failure and failure.group(1) in AI_ERRORS:
            return self.reply_json(AI_ERRORS[failure.group(1)], {"error": failure.group(1), "message": "Stubbed failure."})
        time.sleep(1.5)
        return self.reply_json(200, {
            "summary": f"A stub summary of {url}.\n• The first point.\n• The second point.\n• The third point.",
            "engine": "anthropic", "model": "claude-sonnet-5-5", "partial": False,
            "cached": not body.get("refresh"), "updated": 0,
        })

    def basic(self):
        req = {"args": self.path.partition("?")[2], "cookie": self.headers.get("Cookie", ""), "referer": self.headers.get("Referer", ""),
               "host": self.headers.get("Host", ""), "port": PORT, "kura": bool(UPSTREAMS["/kura/"])}
        run = subprocess.run(["node", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts", "basic-dev.mjs")],
                             input=json.dumps(req), capture_output=True, text=True, timeout=60)
        if run.returncode:
            return self.send_error(500, run.stderr.strip()[-200:])
        out = json.loads(run.stdout)
        data = out["body"].encode()
        self.send_response(out["status"])
        for key, value in out["headers"].items():
            self.send_header(key, value)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if AI_STUB and self.path.startswith("/shiori/ai/"):
            return self.ai_stub()
        if self.path.split("?", 1)[0] == "/basic":
            return self.basic()
        target = self.route()
        if target is None:
            if self.path.startswith("/?") or self.path == "/":
                self.path = "/index.html"
            return super().do_GET()
        if target == NOT_ROUTED:
            return self.send_error(404)
        self.proxy(target)

    def do_POST(self):
        if AI_STUB and self.path.startswith("/shiori/ai/"):
            return self.ai_stub()
        if any(self.path.startswith(f"/{name}/") for name in MEDIA):
            return self.send_error(403)
        target = self.route()
        if target:
            self.proxy(target)
        else:
            self.send_error(404 if target == NOT_ROUTED else 405)

    do_PUT = do_POST
    do_DELETE = do_POST


if __name__ == "__main__":
    if not HISTER:
        sys.exit("Set HISTER_URL (and SEARXNG_URL, KONBINI_URL).")
    print(f"Shiori web page on http://localhost:{PORT}/ from {ROOT}")
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
