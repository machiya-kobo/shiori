#!/usr/bin/env python3
"""A stand-in Hister for the Firefox spike (run.mjs). Unlike
linux/fake-hister.py it serves skip rules (anything with "skipme"), stats
and a profile, and logs each request as one JSON line, a PDF's inner
document included. Never point the extension at a real Hister for writes.

    fake-hister.py PORT LOGFILE
"""
import http.server
import json
import sys

PORT = int(sys.argv[1])
LOG = open(sys.argv[2], "a", buffering=1)


class Handler(http.server.BaseHTTPRequestHandler):
    def _log(self, body=None):
        rec = {"m": self.command, "p": self.path, "origin": self.headers.get("Origin")}
        if isinstance(body, dict):
            pdf = None
            if isinstance(body.get("document"), dict):  # api/add_pdf: {document, pdf}
                pdf = len(body.get("pdf") or "")
                body = body["document"]
            rec.update(url=body.get("url"), title=body.get("title"), label=body.get("label"),
                       added=body.get("added"), meta=body.get("metadata"),
                       html=len(body.get("html") or ""), text=len(body.get("text") or ""), pdf=pdf)
        LOG.write(json.dumps(rec) + "\n")

    def _reply(self, code, obj):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self._log()
        path = self.path.split("?")[0]
        replies = {
            "/api/rules": {"skip": ["skipme"], "allow": [], "aliases": {}},
            "/api/stats": {"doc_count": 3},
            "/api/profile": {"user_id": 0},
            "/search": {"total": 0, "documents": []},
        }
        if path in replies:
            return self._reply(200, replies[path])
        return self._reply(404, {"error": "not found"})

    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)) or 0)
        try:
            body = json.loads(raw or b"{}")
        except ValueError:
            body = {}
        self._log(body)
        return self._reply(201 if self.path.startswith("/api/add") else 200, {})

    def log_message(self, *args):
        pass


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
