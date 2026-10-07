#!/usr/bin/env python3
"""A fake Hister and a fake Kura for Shiori for Haiku's UI runs (never test
against the real ones). Each checks the credential it should get, and
shouts when it gets one it never should:

    fake-services.py [HISTER_PORT] [KURA_PORT]      (defaults 8401 8402)

Hister wants X-Access-Token: FAKE-HISTER-TOKEN-0123 (else 403, empty body,
as Hister does with users on). Kura wants Authorization: Bearer
mht_<43 x "K"> (else 401 {"error": "sign in"}). A Hister token at Kura is a
LEAK line. Every request is logged on stdout, tokens masked.

The Hister sign-in (docs/signing-in.md) is faked too: /machiya/healthz says
Hister has users, POST /api/login takes alex / fake-password and sets
`hister=<session>`, /machiya/api/app-session trades it for an mhs_ id, and
/machiya/signout ends both. Hister then takes the session's Cookie, Kura the
Bearer mhs_; the session at Kura, or the id at Hister, is a LEAK.
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

# The sign-in's state: the live session and id (one user, alex).
SESSION = "S" * 40 + "abc"
SID = "mhs_" + "I" * 43
SIGNED_IN = {"session": False, "sid": False}


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
            # The scheme dropped, so the log shows which kind (mht_ or mhs_).
            "authorization": mask(self.headers.get("Authorization", "").removeprefix("Bearer ")),
            "origin": self.headers.get("Origin", "-"),
        }


class Hister(Base):
    def authorized(self):
        if self.headers.get("Authorization") and not self.path.startswith("/machiya/"):
            log("LEAK hister got an Authorization header (a room token or the sign-in's id?)")
        if self.headers.get("X-Access-Token") == HISTER_TOKEN:
            return True
        return SIGNED_IN["session"] and self.headers.get("Cookie", "") == "hister=" + SESSION

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        params = urllib.parse.parse_qs(url.query)
        log("hister GET", url.path, self.creds(), "cookie=" + mask(self.headers.get("Cookie", "")),
            "query=" + (params.get("query", [""])[0]))
        if url.path == "/health":
            return self.reply(200, {"ok": True})
        if url.path == "/machiya/healthz":
            return self.reply(200, {"ok": True, "hister": "ok"})
        if not self.authorized():
            return self.reply(403)
        if url.path == "/api/preview":
            # Hister's readable copy of a page, for Classic's reader.
            page = params.get("url", [""])[0]
            body = "".join(f"<p>Section {k} of the readable copy of {page}: Hister kept this text when the "
                           f"page was saved, so a Mac Plus can read it without a browser.</p>" for k in range(15))
            return self.reply(200, {"title": "A page from Hister", "content": "<h1>A saved page</h1>" + body,
                                    "added": 1790000000, "updated": 1790500000})
        if url.path != "/search":
            return self.reply(404, {"error": "not found"})
        q = json.loads(params.get("query", ["{}"])[0] or "{}")
        text = q.get("text", "")
        # "many": 45 pages, 30 then 15, through page_key (as Hister pages).
        if "many" in words_of(text):
            first = q.get("page_key") != "p2"
            n = range(30) if first else range(30, 45)
            docs = [{"url": f"https://example.com/many/{i}", "title": f"Many {i}", "domain": "example.com",
                     "added": 1790000000, "text": "one of <mark>many</mark>", "metadata": {"source": "shiori"}} for i in n]
            return self.reply(200, {"total": 45, "documents": docs, "page_key": "p2" if first else ""})
        # "heavy": 20 pages shaped like a real Hister reply (long highlighted
        # snippets, metadata, dates), for timing a slow client (Classic's probe).
        if "heavy" in words_of(text):
            filler = ("Lorem ipsum &amp; dolor sit amet, the <mark>heavy</mark> reply goes on with words "
                      "about caf\u00e9s, Ch\u014dchin lanterns and \"quoted\" text to decode. ") * 3
            docs = [{"url": f"https://example.com/heavy/{i}?ref=search&page={i}",
                     "title": f"Heavy page {i}: a longer title with UTF-8 \u2014 dashes and \u201cquotes\u201d",
                     "domain": "example.com", "label": "tech", "added": 1790000000 + i, "updated": 1790500000 + i,
                     "score": 12.5 - i / 10, "text": filler,
                     "metadata": {"source": "shiori", "client": "shiori", "client_version": "1.2.3"}} for i in range(20)]
            return self.reply(200, {"total": 230, "documents": docs, "page_key": "p2", "query_suggestion": ""})
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
        shown = dict(body)
        for secret in ("password", "hister"):
            if secret in shown:
                shown[secret] = mask(str(shown[secret]))
        log("hister POST", self.path, self.creds(), "cookie=" + mask(self.headers.get("Cookie", "")),
            "body=" + json.dumps(shown))
        # The sign-in helper (on Hister's host, no Origin needed).
        if self.path == "/machiya/api/app-session":
            if self.headers.get("Cookie") or self.headers.get("X-Access-Token"):
                log("LEAK the trade carried a credential of its own")
            if not SIGNED_IN["session"] or body.get("hister") != SESSION:
                return self.reply(401, {"error": "sign in"})
            SIGNED_IN["sid"] = True
            return self.reply(200, {"sid": SID, "username": "alex"})
        if self.path == "/machiya/signout":
            if self.headers.get("Authorization") != "Bearer " + SID:
                return self.reply(401, {"error": "sign in"})
            SIGNED_IN["sid"] = SIGNED_IN["session"] = False
            return self.reply(200, {"ok": True})
        if self.headers.get("Origin") != "hister://":
            return self.reply(403)
        if self.path == "/api/login":
            if self.headers.get("X-Access-Token") or self.headers.get("Cookie"):
                log("LEAK the login carried a credential")
            if body.get("username") != "alex" or body.get("password") != "fake-password":
                return self.reply(401, {"error": "invalid credentials"})
            SIGNED_IN["session"] = True
            data = b'{"ok":true}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Set-Cookie", "hister=" + SESSION + "; Path=/; HttpOnly; SameSite=Lax")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if self.path == "/api/logout":
            SIGNED_IN["session"] = False
            return self.reply(200, {"ok": True})
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
        if "hister=" in self.headers.get("Cookie", ""):
            log("LEAK kura got Hister's session cookie")
        bearer = self.headers.get("Authorization")
        if SIGNED_IN["sid"] and bearer == "Bearer " + ROOM_TOKEN:
            log("NOTE kura got the room token while signed in (the id should win)")
        if bearer != "Bearer " + ROOM_TOKEN and not (SIGNED_IN["sid"] and bearer == "Bearer " + SID):
            return self.reply(401, {"error": "sign in", "signin": "http://127.0.0.1/signin"})
        # Classic's error probes (search words): a redirect, a slow answer, and
        # answers too large for the Mac (300 KB) and for the bridge (600 KB).
        q = params.get("q", [""])[0]
        if q.startswith("redirect"):
            self.send_response(302)
            self.send_header("Location", "https://elsewhere.example/")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if q.startswith("slow"):
            import time
            time.sleep(12)
        if q.startswith("big") or q.startswith("huge"):
            size = 300_000 if q.startswith("big") else 600_000
            note = {"path": "Big/x.md", "url": "http://127.0.0.1/n/Big/x", "title": "Big", "summary": "x" * 1000}
            return self.reply(200, {"total": 1, "results": [note] * (size // 1100)})
        limit = int(params.get("limit", ["20"])[0])
        offset = int(params.get("offset", ["0"])[0])
        log("kura vault=" + params.get("vault", ["-"])[0], "offset=" + str(offset))
        log("kura " + url.path, "vault=" + params.get("vault", ["-"])[0], "offset=" + str(offset),
            "q=" + params.get("q", [""])[0])
        if url.path == "/api/note":
            path = params.get("path", [""])[0]
            # Classic's reader: the "many" notes are long, with every kind of
            # markup Kura's sanitized HTML has, and a wikilink to the next note.
            if path.startswith("Many/") and path.endswith(".md"):
                n = path[5:-3]
                nxt = str(int(n) + 1) if n.isdigit() else "0"
                base = f"http://127.0.0.1:{KURA_PORT}"
                body = "".join(
                    f"<p>Paragraph {k}: the <strong>Mac Plus</strong> reads this note from Kura through the bridge, "
                    f"with <em>italics</em>, <code>code</code> and caf\u00e9 \u2014 Ch\u014dchin text that wraps "
                    f"across lines on a 512-pixel screen.</p>" for k in range(12))
                html = (f"<h1>Many note {n}</h1><p>See <a class=\"wikilink\" href=\"{base}/n/Many/{nxt}\">Many note {nxt}</a> "
                        f"and <a href=\"https://example.com/elsewhere\">a page elsewhere</a>.</p>"
                        "<h2>A list</h2><ul><li>First <strong>point</strong></li><li>Second<ul><li>Nested</li></ul></li></ul>"
                        "<ol><li>one</li><li>two</li></ol>"
                        "<blockquote><p><strong>Note:</strong> a callout, as Kura sends one.</p></blockquote>"
                        "<pre><code>int main(void)\n{\n    return 0;\n}</code></pre>"
                        "<table><tr><th>Model</th><th>CPU</th></tr><tr><td>Plus</td><td>68000</td></tr></table>"
                        "<p><img src=\"/a/x.png\" alt=\"a diagram\"></p><hr>" + body)
                return self.reply(200, {"path": path, "title": f"Many note {n}", "url": f"{base}/n/Many/{n}",
                                        "html": html, "markdown": "(the body again, as Kura sends it)"})
            for npath, folder, title, summary in NOTES:
                if npath == path:
                    html = (f"<h1>{title}</h1><p>{summary}</p><ul><li>One <strong>point</strong></li></ul>"
                            '<p>See <a href="https://www.haiku-os.org/">Haiku</a>.</p>')
                    return self.reply(200, {"path": path, "title": title, "html": html})
            return self.reply(404, {"error": "not found"})
        if url.path == "/api/vaults":
            return self.reply(200, {"vaults": [{"name": "personal", "title": "Personal", "default": True},
                                               {"name": "work", "title": "Work", "private": True}]})
        words = words_of(params.get("q", [""])[0]) if url.path == "/api/search" else []
        if url.path not in ("/api/search", "/api/recent"):
            return self.reply(404, {"error": "not found"})
        results = []
        notes = list(NOTES)
        # "many": 45 notes, for the Notes pill's paging by offset.
        if "many" in words:
            notes = [(f"Many/{i}.md", "Many", f"Many note {i}", "one of many") for i in range(45)]
        for path, folder, title, summary in notes:
            if words and not all(w in (title + " " + summary).lower() for w in words):
                continue
            slug = urllib.parse.quote(path[:-3])
            note = {"path": path, "slug": path[:-3], "vault": "personal", "folder": folder, "title": title,
                    "url": f"http://127.0.0.1:{KURA_PORT}/n/{slug}", "summary": summary, "tags": [],
                    "created": 1790000000, "changed": 1790500000, "published": False, "card_url": None}
            if url.path == "/api/search":
                note["snippet"] = mark(summary, words)
            results.append(note)
        self.reply(200, {"total": len(results), "took_ms": 1, "results": results[offset:offset + limit]})


BIND = "127.0.0.1"


def serve(port, handler):
    http.server.ThreadingHTTPServer((BIND, port), handler).serve_forever()


threading.Thread(target=serve, args=(KURA_PORT, Kura), daemon=True).start()
log(f"fake Hister on :{HISTER_PORT}, fake Kura on :{KURA_PORT}")
serve(HISTER_PORT, Hister)
