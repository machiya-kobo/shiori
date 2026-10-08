#!/usr/bin/env python3
"""A fake house for tools/container-test: every service shiori-web proxies to, each on its own port, each answering JSON
that says what it was asked (method, path, the headers it received). Not for anything but tests.

    fake-upstream.py            ports: 9001 Hister, 9002 SearXNG, 9003 Kura, 9004 Konbini, 9005 feed, 9006 AI,
                                9007 small web, 9008 helper (public), 9009 helper (nginx auth)
    FAKE_SEARX_JSON=403         SearXNG refuses format=json, as a stock one does
"""
import json
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SERVICES = {9001: "hister", 9002: "searxng", 9003: "kura", 9004: "konbini", 9005: "feed", 9006: "ai", 9007: "smallweb",
            9008: "helper", 9009: "helper-auth"}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *args):
        pass

    def reply(self, status, body, headers=()):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        for k, v in headers:
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        service = SERVICES[self.server.server_address[1]]
        seen = {k.lower(): v for k, v in self.headers.items()}
        echo = {"service": service, "method": self.command, "path": self.path, "headers": seen}
        cookie = seen.get("cookie", "")
        if service == "hister":
            if self.path == "/api/profile":                       # Hister with users: a good session, else 403
                return self.reply(200 if "hister=good" in cookie or "hister=sessionfromhelper" in cookie else 403, echo)
            return self.reply(200, echo, [("Set-Cookie", "hister=fromupstream; Path=/; HttpOnly")])
        if service == "searxng" and self.path.startswith("/search") and "format=json" in self.path:
            if os.environ.get("FAKE_SEARX_JSON") == "403":
                return self.reply(403, {"error": "forbidden"})
            return self.reply(200, {**echo, "results": []})
        if service == "helper-auth":                              # hister-login's /v1/nginx
            ok = seen.get("x-machiya-session", "").startswith("mhr_")
            return self.reply(200 if ok else 401, echo, [("X-Hister-Cookie", "hister=sessionfromhelper")] if ok else [])
        if service == "ai" and self.path == "/status":
            return self.reply(200, {"enabled": True, **echo})
        self.reply(200, echo)

    do_POST = do_PUT = do_GET


def main():
    for port in SERVICES:
        server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
    print("fake house on", ", ".join(f"{p} {n}" for p, n in SERVICES.items()), flush=True)
    threading.Event().wait()


if __name__ == "__main__":
    sys.exit(main())
