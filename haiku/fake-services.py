#!/usr/bin/env python3
"""A fake Hister and a fake Kura for Shiori for Haiku's UI runs (never test
against the real ones). Each checks the credential it should get, and
shouts when it gets one it never should:

    fake-services.py [HISTER_PORT] [KURA_PORT]      (defaults 8401 8402)

Hister wants X-Access-Token: FAKE-HISTER-TOKEN-0123 (else 403, empty body,
as Hister does with users on). Kura wants Authorization: Bearer
mht_<43 x "K"> (else 401 {"error": "sign in"}). A Hister token at Kura is a
LEAK line. Every request is logged on stdout, tokens masked.
"""
import http.server
import json
import sys
import threading
import urllib.parse

HISTER_TOKEN = "FAKE-HISTER-TOKEN-0123"
ROOM_TOKEN = "mht_" + "K" * 43
HISTER_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8401
KURA_PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8402

PAGES = [
    ("https://www.haiku-os.org/docs/api/", "The Haiku Book", "haiku-os.org", "The Haiku API reference: the Application Kit, the Interface Kit and the Network Kit."),
    ("https://www.haiku-os.org/get-haiku/", "Get Haiku | Haiku Project", "haiku-os.org", "Download Haiku R1/beta5, the open-source operating system inspired by BeOS."),
    ("https://en.wikipedia.org/wiki/BeOS", "BeOS - Wikipedia", "en.wikipedia.org", "BeOS is a discontinued operating system for personal computers, first developed by Be Inc. in 1990."),
    ("https://www.raspberrypi.com/products/raspberry-pi-5/", "Raspberry Pi 5", "raspberrypi.com", "The everything computer. Optimised. Raspberry Pi 5 is up to three times faster than its predecessor."),
    ("https://example.com/machiya/townhouse", "Kyoto machiya townhouses & their history", "example.com", "Machiya are traditional wooden townhouses found throughout Japan and typified in the historical capital of Kyoto."),
    ("https://git.example/owner/shiori", "machiya-kobo/shiori", "git.example", "Shiori: the Machiya search client for iOS, macOS, Linux and now Haiku.", "code"),
    ("javascript:alert(1)", "A stored javascript: link", "evil.example", "This one must never become a row (SHIO-1): haiku search test."),
]

NOTES = [
    ("Projects/Shiori Haiku.md", "Projects", "Shiori Haiku", "A native Be API client for Shiori: search, save, settings. Haiku R1/beta6."),
    ("Systems/tv-haiku.md", "Systems", "tv-haiku", "A Haiku test VM: R1/beta6 x86_64, single user."),
    ("Retro/BeBox.md", "Retro", "BeBox", "Be Inc.'s dual-PowerPC machine that ran BeOS before Haiku existed."),
    ("Projects/Machiya.md", "Projects", "Machiya", "Machiya is the stack of Kura, Shiori, Niwa and Konbini."),
]

LOCK = threading.Lock()


def log(*parts):
    with LOCK:
        print(*parts, flush=True)


def mask(value):
    return value[:4] + "…" + str(len(value)) if value else "-"


def words_of(text):
    out = []
    for w in text.split():
        if w.startswith("-") or ":" in w or w == "*":
            continue
        w = w.strip("()*\"").split("|")[0].strip("*").lower()
        if w:
            out.append(w)
    return out


def mark(text, words):
    out = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    for w in words:
        i = out.lower().find(w)
        if i >= 0:
            out = out[:i] + "<mark>" + out[i:i + len(w)] + "</mark>" + out[i + len(w):]
    return out


class Base(http.server.BaseHTTPRequestHandler):
    who = "?"

    def log_message(self, *args):
        pass

    def reply(self, status, body=None):
        data = b"" if body is None else json.dumps(body).encode()
        self.send_response(status)
        if body is not None:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def creds(self):
        return {
            "x-access-token": mask(self.headers.get("X-Access-Token", "")),
            "authorization": mask(self.headers.get("Authorization", "")),
            "origin": self.headers.get("Origin", "-"),
        }


class Hister(Base):
    def authorized(self):
        if self.headers.get("Authorization"):
            log("LEAK hister got an Authorization header (a room token?)")
        return self.headers.get("X-Access-Token") == HISTER_TOKEN

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        params = urllib.parse.parse_qs(url.query)
        log("hister GET", url.path, self.creds(), "query=" + (params.get("query", [""])[0]))
        if url.path == "/health":
            return self.reply(200, {"ok": True})
        if not self.authorized():
            return self.reply(403)
        if url.path != "/search":
            return self.reply(404, {"error": "not found"})
        q = json.loads(params.get("query", ["{}"])[0] or "{}")
        text = q.get("text", "")
        code = "metadata.source:code" in text.split()
        words = words_of(text)
        docs = []
        for page in PAGES:
            purl, title, domain, body = page[:4]
            source = page[4] if len(page) > 4 else "shiori"
            if (source == "code") != code:
                continue
            hay = (title + " " + body).lower()
            if words and not all(w in hay for w in words):
                continue
            docs.append({"url": purl, "title": title, "domain": domain, "label": "tech", "added": 1790000000,
                         "text": mark(body, words), "metadata": {"source": source}})
        self.reply(200, {"total": len(docs), "documents": docs, "page_key": ""})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        log("hister POST", self.path, self.creds(), "body=" + json.dumps(body))
        if self.headers.get("Origin") != "hister://":
            return self.reply(403)
        if not self.authorized():
            return self.reply(403)
        if self.path != "/api/add":
            return self.reply(404, {"error": "not found"})
        if "secret" in body.get("url", ""):
            return self.reply(422, {"error": "sensitive"})
        PAGES.insert(0, (body["url"], body.get("title") or body["url"], urllib.parse.urlsplit(body["url"]).hostname or "",
                         "Saved from Shiori for Haiku."))
        self.reply(201)


class Kura(Base):
    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        params = urllib.parse.parse_qs(url.query)
        log("kura GET", url.path, self.creds(), "q=" + params.get("q", [""])[0])
        if self.headers.get("X-Access-Token"):
            log("LEAK kura got X-Access-Token (Hister's token must never go to a room)")
        if self.headers.get("Authorization") != "Bearer " + ROOM_TOKEN:
            return self.reply(401, {"error": "sign in", "signin": "http://127.0.0.1/signin"})
        limit = int(params.get("limit", ["20"])[0])
        words = words_of(params.get("q", [""])[0]) if url.path == "/api/search" else []
        if url.path not in ("/api/search", "/api/recent"):
            return self.reply(404, {"error": "not found"})
        results = []
        for path, folder, title, summary in NOTES:
            if words and not all(w in (title + " " + summary).lower() for w in words):
                continue
            slug = urllib.parse.quote(path[:-3])
            note = {"path": path, "slug": path[:-3], "vault": "personal", "folder": folder, "title": title,
                    "url": f"http://127.0.0.1:{KURA_PORT}/n/{slug}", "summary": summary, "tags": [],
                    "created": 1790000000, "changed": 1790500000, "published": False, "card_url": None}
            if url.path == "/api/search":
                note["snippet"] = mark(summary, words)
            results.append(note)
        self.reply(200, {"total": len(results), "took_ms": 1, "results": results[:limit]})


def serve(port, handler):
    http.server.ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()


threading.Thread(target=serve, args=(KURA_PORT, Kura), daemon=True).start()
log(f"fake Hister on :{HISTER_PORT}, fake Kura on :{KURA_PORT}")
serve(HISTER_PORT, Hister)
