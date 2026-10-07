#!/usr/bin/env python3
"""A stand-in Hister for linux/save-test.sh: answers every POST with one
status and logs what arrived. Never test `shiori save` against the real one.
FAKE_SEARCH_STATUS=403 makes its searches refused, as a Hister with users
answers one that isn't signed in (linux/desktop-test.sh).

    linux/fake-hister.py PORT [STATUS]
"""
import http.server
import json
import os
import sys

STATUS = int(sys.argv[2]) if len(sys.argv) > 2 else 201
SEARCH_STATUS = int(os.environ.get("FAKE_SEARCH_STATUS", "200"))


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # Holds nothing (a search finds nothing) and has no aliases.
        body = b'{"total":0,"documents":[]}' if self.path.startswith("/search") else b'{"aliases":{}}'
        print("GET", self.path.split("?")[0], flush=True)
        status = SEARCH_STATUS if self.path.startswith("/search") else 200 if self.path.startswith("/api/rules") else 404
        if status in (401, 403):
            body = b'{"error":"unauthorized"}'
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def do_HEAD(self):
        # A document lookup (api/document): it holds nothing.
        print("HEAD", self.path.split("?")[0], flush=True)
        self.send_response(404)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        meta = body.get("metadata") or {}
        print("POST", self.path, self.headers.get("Origin"), body.get("url"), body.get("label"), meta, "html" if body.get("html") else "no html", flush=True)
        self.send_response(STATUS)
        self.end_headers()

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
