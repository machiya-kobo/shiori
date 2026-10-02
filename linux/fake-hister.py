#!/usr/bin/env python3
"""A stand-in Hister for linux/save-test.sh: answers every POST with one
status and logs what arrived. Never test `shiori save` against the real one.

    linux/fake-hister.py PORT [STATUS]
"""
import http.server
import json
import sys

STATUS = int(sys.argv[2]) if len(sys.argv) > 2 else 201


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # Holds nothing (a search finds nothing) and has no aliases.
        body = b'{"total":0,"documents":[]}' if self.path.startswith("/search") else b'{"aliases":{}}'
        print("GET", self.path.split("?")[0], flush=True)
        self.send_response(200 if self.path.startswith(("/search", "/api/rules")) else 404)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        meta = body.get("metadata") or {}
        print("POST", self.path, self.headers.get("Origin"), body.get("url"), body.get("label"), meta, "html" if body.get("html") else "no html", flush=True)
        self.send_response(STATUS)
        self.end_headers()

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
