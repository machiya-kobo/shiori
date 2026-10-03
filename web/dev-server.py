#!/usr/bin/env python3
"""Serves Shiori's web page locally, routed as its host routes it.

    scripts/build-web.sh /tmp/shiori-site http://localhost:8765/
    HISTER_URL=https://hister.example/ SEARXNG_URL=https://search.example/ \\
    KONBINI_URL=https://konbini.example/ web/dev-server.py /tmp/shiori-site

Routes (the same as web/README.md asks of the real host):
  /, /_shiori/*, and (the web app) /sw.js, /manifest.webmanifest: the build
  /searx/*             SearXNG, prefix removed
  /konbini/*           Konbini, prefix removed (only api/cards is used)
  /kura/<path>         Kura, prefix removed, for only the paths Shiori asks
                       for (KURA_PATHS); anything else under /kura/ is a 404
  /smallweb/*          the small-web gateway, prefix removed (api/search, api/save)
  anything else        the Hister host (Hister's API, /shiori/feed,
                       /shiori/ai/*)

AI_STUB=1 answers /shiori/ai/* here instead, with a canned summary or
answer (a URL or query containing "fail-<code>", e.g. fail-cap, answers
that error), since the real endpoint refuses a localhost origin.

Requests pass through unchanged: in particular no `Origin: hister://` is
added, so Hister's own check (same-origin allowed, cross-site refused)
still guards writes. One exception: the Machiya sign-in's cookie
(`machiya_session`) goes only to the rooms, /kura/ and /konbini/, and is
taken out of the Cookie header everywhere else (Hister, SearXNG, the
gateway). Replies pass back as they are, Set-Cookie included. For testing
only; stdlib, no dependencies.
"""

import http.server
import json
import os
import re
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
AI_STUB = os.environ.get("AI_STUB") == "1"
AI_ERRORS = {"cap": 429, "note": 403, "not_indexed": 404, "empty": 422, "engine": 502, "declined": 502, "unavailable": 503, "no_results": 422, "searx": 504}
# The paths whose upstream is a Machiya room, which may read the sign-in cookie.
ROOMS = ("/kura/", "/konbini/")
SESSION_COOKIE = "machiya_session"
HOP = {"connection", "keep-alive", "transfer-encoding", "upgrade", "host", "content-length", "proxy-connection"}


def without_session(cookie):
    """A Cookie header without the Machiya session ('' when nothing is left)."""
    kept = [part.strip() for part in cookie.split(";")
            if part.strip() and part.split("=", 1)[0].strip() != SESSION_COOKIE]
    return "; ".join(kept)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def route(self):
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html", "/sw.js", "/manifest.webmanifest") or path.startswith("/_shiori/"):
            return None
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
        if not self.path.startswith(ROOMS):
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

    def do_GET(self):
        if AI_STUB and self.path.startswith("/shiori/ai/"):
            return self.ai_stub()
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
