"""mac-bridge's tests: a fake Hister, a fake Kura and a fake hister-login on loopback, and the bridge between them.
Run: python3 -m unittest discover -s classic/bridge (or node --test scripts/classic.test.mjs)."""
import http.client
import http.server
import io
import json
import os
import re
import socket
import tempfile
import threading
import time
import unittest

import bridge

GOOD = "mht_" + "A" * 43          # the Mac's room token, good for the bridge
OTHER = "mht_" + "B" * 43         # good, but another Hister user's
REVOKED = "mht_" + "C" * 43
HISTER_TOKEN = "hister-owner-token-for-tests"


class Recorder(http.server.BaseHTTPRequestHandler):
    """A fake upstream: records each request, answers what the test asked for."""
    protocol_version = "HTTP/1.1"
    seen = None
    answer = None

    def log_message(self, *a):
        pass

    def do_GET(self):
        type(self).seen.append({"path": self.path, "headers": dict(self.headers.items()),
                                "all": [(k.lower(), v) for k, v in self.headers.items()]})
        status, headers, body, chunked, delay = type(self).answer(self.path)
        if delay:
            time.sleep(delay)
        self.send_response(status)
        for k, v in headers:
            self.send_header(k, v)
        if chunked:
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            for i in range(0, len(body), 1000):
                part = body[i:i + 1000]
                self.wfile.write(b"%x\r\n%s\r\n" % (len(part), part))
            self.wfile.write(b"0\r\n\r\n")
        else:
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)


class Helper(http.server.BaseHTTPRequestHandler):
    """A fake hister-login: /v1/check by X-Machiya-Session."""
    calls = None
    down = False

    def log_message(self, *a):
        pass

    def do_GET(self):
        type(self).calls.append(dict(self.headers.items()))
        if type(self).down:
            self.send_response(502)
            self.end_headers()
            return
        token = self.headers.get("X-Machiya-Session")
        if self.path != "/v1/check":
            status, body = 404, {}
        elif token == GOOD and self.headers.get("X-Machiya-Room") == "http://bridge.example:8070":
            status, body = 200, {"kind": "token", "username": "owner"}
        elif token == OTHER:
            status, body = 200, {"kind": "token", "username": "someone"}
        else:
            status, body = 401, {"reason": "revoked"}
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def serve(handler):
    s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    s.daemon_threads = True
    threading.Thread(target=s.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True).start()
    return s


class BridgeTest(unittest.TestCase):
    def setUp(self):
        self.hister_seen, self.kura_seen = [], []
        self.answer = lambda path: (200, [("Content-Type", "application/json")], b'{"ok": true}', False, 0)
        hister = type("H", (Recorder,), {"seen": self.hister_seen, "answer": staticmethod(lambda p: self.answer(p))})
        kura = type("K", (Recorder,), {"seen": self.kura_seen, "answer": staticmethod(lambda p: self.answer(p))})
        self.helper_calls = []
        self.helper = type("L", (Helper,), {"calls": self.helper_calls, "down": False})
        self.servers = [serve(hister), serve(kura), serve(self.helper)]
        tok = tempfile.NamedTemporaryFile("w", delete=False)
        tok.write(HISTER_TOKEN + "\n")
        tok.close()
        self.token_file = tok.name
        self.env = {
            "BRIDGE_HISTER_URL": "http://127.0.0.1:%d" % self.servers[0].server_address[1],
            "BRIDGE_KURA_URL": "http://127.0.0.1:%d" % self.servers[1].server_address[1],
            "BRIDGE_AUTH_URL": "http://127.0.0.1:%d" % self.servers[2].server_address[1],
            "BRIDGE_ALLOW_HTTP_UPSTREAM": "1",
            "BRIDGE_ALLOW": "127.0.0.1",
            "BRIDGE_DENY": "192.0.2.1",
            "BRIDGE_PUBLIC_URL": "http://bridge.example:8070",
            "BRIDGE_HISTER_USERS": "owner",
            "BRIDGE_HISTER_TOKEN_FILE": self.token_file,
            "BRIDGE_VAULTS": "shared",
            "BRIDGE_MAX_BYTES": "4096",
            "BRIDGE_PAGED_MAX_BYTES": "65536",
            "BRIDGE_PART_BYTES": "2048",
            "BRIDGE_TIMEOUT": "2",
        }
        self.log = io.StringIO()
        self.start()

    def start(self, **overrides):
        for s in getattr(self, "bridges", []):
            s.shutdown()
            s.server_close()
        env = dict(self.env, **overrides)
        self.config = bridge.Config(env)
        self.check = bridge.TokenCheck(self.config)
        self.bridges = [bridge.make_server("hister", self.config, self.check, "127.0.0.1", 0, self.log),
                        bridge.make_server("kura", self.config, self.check, "127.0.0.1", 0, self.log)]
        for s in self.bridges:
            threading.Thread(target=s.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True).start()

    def tearDown(self):
        for s in self.servers + self.bridges:
            s.shutdown()
            s.server_close()
        os.unlink(self.token_file)

    def raw(self, service, request):
        """Sends raw bytes to the bridge; returns (status line, headers dict, body)."""
        port = self.bridges[0 if service == "hister" else 1].server_address[1]
        with socket.create_connection(("127.0.0.1", port), timeout=5) as s:
            s.sendall(request)
            data = b""
            while True:
                chunk = s.recv(65536)
                if not chunk:
                    break
                data += chunk
        head, _, body = data.partition(b"\r\n\r\n")
        lines = head.decode("latin-1").split("\r\n")
        headers = {}
        for line in lines[1:]:
            k, _, v = line.partition(":")
            headers.setdefault(k.strip().lower(), []).append(v.strip())
        return lines[0], headers, body

    def get(self, service, target, headers=(), method="GET", token=GOOD):
        """A request as the Mac sends it: with its room token unless the test names its own Authorization (or none)."""
        req = "%s %s HTTP/1.0\r\nHost: bridge\r\n" % (method, target)
        if token and not any(k.lower() == "authorization" for k, _ in headers):
            headers = [("Authorization", "Bearer " + token)] + list(headers)
        for k, v in headers:
            req += "%s: %s\r\n" % (k, v)
        line, h, body = self.raw(service, (req + "\r\n").encode("latin-1"))
        return int(line.split()[1]), h, body, line

    # -- the source address -----------------------------------------------------------------------------------------

    def test_healthz_answers_anyone_without_an_upstream_call(self):
        self.start(BRIDGE_ALLOW="10.9.9.9")
        status, _, body, _ = self.get("hister", "/healthz")
        self.assertEqual((status, body), (200, b"ok\n"))
        self.assertEqual(self.hister_seen, [])

    def test_a_source_off_the_allow_list_is_refused(self):
        self.start(BRIDGE_ALLOW="10.9.9.9")
        for service, path in (("hister", "/search?query=x"), ("kura", "/api/recent")):
            status, *_ = self.get(service, path, [("Authorization", "Bearer " + GOOD)])
            self.assertEqual(status, 403)
        self.assertEqual(self.hister_seen + self.kura_seen, [])

    def test_the_tailnet_and_denied_addresses_can_never_be_allowed(self):
        for allow in ("100.64.0.0/10", "100.100.1.2", "0.0.0.0/0", "192.0.2.0/24", "fd7a:115c:a1e0::/48",
                      "fd7a:115c:a1e0::1", "fd7a::/16", "::/0"):
            with self.assertRaises(bridge.ConfigError):
                bridge.Config(dict(self.env, BRIDGE_ALLOW=allow))
        with self.assertRaises(bridge.ConfigError):
            bridge.Config(dict(self.env, BRIDGE_ALLOW=""))
        self.assertFalse(self.config.admits("100.64.0.1"))
        self.assertFalse(self.config.admits("::ffff:10.0.0.1"))
        self.assertFalse(self.config.admits("fd7a:115c:a1e0::5"))
        self.assertTrue(self.config.admits("::ffff:127.0.0.1"))

    def test_settings_are_checked(self):
        bad = [("BRIDGE_HISTER_USERS", "*"), ("BRIDGE_HISTER_USERS", ""), ("BRIDGE_VAULTS", "all"),
               ("BRIDGE_HISTER_URL", "http://h.example/path"), ("BRIDGE_PUBLIC_URL", "bridge"),
               ("BRIDGE_HISTER_TOKEN_FILE", ""), ("BRIDGE_PART_BYTES", "1000"), ("BRIDGE_PART_BYTES", "4000"),
               ("BRIDGE_PAGED_MAX_BYTES", "100")]
        for key, value in bad:
            with self.assertRaises(bridge.ConfigError, msg=key):
                bridge.Config(dict(self.env, **{key: value}))
        env = dict(self.env)
        del env["BRIDGE_ALLOW_HTTP_UPSTREAM"]
        with self.assertRaises(bridge.ConfigError):
            bridge.Config(env)

    # -- methods and paths ------------------------------------------------------------------------------------------

    def test_only_get(self):
        for method in ("POST", "PUT", "DELETE", "HEAD", "OPTIONS"):
            status, *_ = self.get("kura", "/api/recent", method=method)
            self.assertEqual(status, 405, method)
        self.assertEqual(self.kura_seen, [])

    def test_paths_are_exact_and_never_decoded(self):
        refused = ["/", "/api", "/api/recent/", "/api/recent/../note", "/api/%72ecent", "//api/recent",
                   "/api/./recent", "/API/recent", "/api/recent%2f", "/api/add", "/kura/api/recent",
                   "http://127.0.0.1/api/recent", "/api/recent#x", "/search"]
        for target in refused:
            status, *_ = self.get("kura", target)
            self.assertIn(status, (400, 404), target)
        for target in ("/api/search", "/api/add", "/api/history", "/search/", "/api/recent"):
            status, *_ = self.get("hister", target, [("Authorization", "Bearer " + GOOD)])
            self.assertIn(status, (400, 404), target)
        self.assertEqual(self.kura_seen + self.hister_seen, [])

    def test_allowed_paths_pass_with_their_query_unchanged(self):
        for path in ("/api/search", "/api/recent", "/api/note", "/api/vaults"):
            status, *_ = self.get("kura", path + "?q=caf%C3%A9+pi&limit=20")
            self.assertEqual(status, 200, path)
        self.assertEqual([s["path"] for s in self.kura_seen],
                         [p + "?q=caf%C3%A9+pi&limit=20" for p in ("/api/search", "/api/recent", "/api/note", "/api/vaults")])
        for path in ("/search", "/api/preview", "/api/config"):
            status, *_ = self.get("hister", path + "?query=%7B%7D", [("Authorization", "Bearer " + GOOD)])
            self.assertEqual(status, 200, path)

    def test_a_body_is_refused(self):
        status, *_ = self.get("kura", "/api/recent", [("Content-Length", "3")])
        self.assertEqual(status, 400)

    # -- vaults -----------------------------------------------------------------------------------------------------

    def test_vaults_off_the_list_and_all_are_refused(self):
        for q in ("vault=all", "vault=work", "vault=shared,work", "vault=", "vault=shared&vault=all", "vault=%61ll",
                  "vault=Shared"):
            status, *_ = self.get("kura", "/api/search?q=x&" + q)
            self.assertEqual(status, 403, q)
        self.assertEqual(self.kura_seen, [])
        for q in ("q=x", "vault=shared", "q=vault%3Awork"):
            status, *_ = self.get("kura", "/api/search?" + q)
            self.assertEqual(status, 200, q)

    # -- headers ----------------------------------------------------------------------------------------------------

    def test_only_listed_headers_go_upstream(self):
        sent = [("Authorization", "Bearer " + GOOD), ("Origin", "hister://"), ("Accept", "application/json"),
                ("If-None-Match", '"abc"'), ("Cookie", "hister=secret"), ("X-Access-Token", "client-token"),
                ("Tailscale-User-Login", "owner@example.com"), ("Tailscale-User-Name", "Owner"),
                ("Tailscale-App-Capabilities", "{}"), ("X-Forwarded-For", "1.2.3.4"), ("Forwarded", "for=1.2.3.4"),
                ("Remote-User", "owner"), ("X-Machiya-Session", "mhs_x"), ("Accept-Encoding", "gzip")]
        self.get("kura", "/api/recent", sent)
        got = {k for k, _ in self.kura_seen[0]["all"]}
        self.assertEqual(got, {"host", "accept", "accept-encoding", "connection", "if-none-match", "origin",
                               "authorization"})
        h = self.kura_seen[0]["headers"]
        self.assertEqual(h["Authorization"], "Bearer " + GOOD)
        self.assertEqual(h["Accept-Encoding"], "identity")
        self.assertEqual(h["Host"], "127.0.0.1:%d" % self.servers[1].server_address[1])

        self.get("hister", "/search?query=%7B%7D", sent)
        got = {k for k, _ in self.hister_seen[0]["all"]}
        self.assertEqual(got, {"host", "accept", "accept-encoding", "connection", "if-none-match", "origin",
                               "x-access-token"})
        self.assertEqual(self.hister_seen[0]["headers"]["X-Access-Token"], HISTER_TOKEN)

    def test_origin_passes_only_as_hister(self):
        self.get("kura", "/api/recent", [("Origin", "https://evil.example")])
        self.assertNotIn("Origin", self.kura_seen[0]["headers"])

    def test_only_listed_headers_come_back_and_never_set_cookie(self):
        self.answer = lambda p: (200, [("Content-Type", "application/json"), ("Set-Cookie", "a=b"), ("ETag", '"1"'),
                                       ("X-Secret", "x"), ("Server", "upstream")], b"{}", False, 0)
        _, headers, _, line = self.get("kura", "/api/recent")
        self.assertTrue(line.startswith("HTTP/1.0 200"))
        self.assertNotIn("set-cookie", headers)
        self.assertNotIn("x-secret", headers)
        self.assertEqual(headers["etag"], ['"1"'])
        self.assertEqual(headers["content-length"], ["2"])
        self.assertNotIn("transfer-encoding", headers)

    def test_a_reply_header_with_a_fold_or_control_character_is_dropped(self):
        self.answer = lambda p: (200, [("Content-Type", "application/json"), ("Location", "/a\r\n X-Evil: 1"),
                                       ("ETag", '"1\x01"')], b"{}", False, 0)
        port = self.bridges[1].server_address[1]
        with socket.create_connection(("127.0.0.1", port), timeout=5) as s:
            s.sendall(("GET /api/recent HTTP/1.0\r\nHost: bridge\r\nAuthorization: Bearer %s\r\n\r\n" % GOOD).encode())
            data = b""
            while chunk := s.recv(65536):
                data += chunk
        head, _, body = data.partition(b"\r\n\r\n")
        lines = head.split(b"\r\n")
        self.assertTrue(lines[0].startswith(b"HTTP/1.0 200"), lines[0])
        for line in lines[1:]:
            self.assertFalse(line[:1].isspace(), line)          # no folded line
            self.assertTrue(all(0x20 <= c < 0x7f for c in line), line)
        names = [line.partition(b":")[0].lower() for line in lines[1:]]
        self.assertNotIn(b"location", names)
        self.assertNotIn(b"etag", names)
        self.assertNotIn(b"x-evil", names)
        self.assertIn(b"content-type: application/json", [line.lower() for line in lines[1:]])
        self.assertEqual(body, b"{}")

    # -- the token swap on Hister's port ----------------------------------------------------------------------------

    def test_without_a_room_token_is_401_and_never_reaches_an_upstream(self):
        for service, path in (("hister", "/search?query=%7B%7D"), ("kura", "/api/recent")):
            for auth in ([], [("Authorization", "Bearer " + HISTER_TOKEN)], [("X-Access-Token", HISTER_TOKEN)],
                         [("Authorization", "Basic " + GOOD)], [("Authorization", "Bearer mht_short")],
                         [("Authorization", "Bearer " + GOOD), ("Authorization", "Bearer " + GOOD)],
                         [("Cookie", "machiya_session=x")], [("Tailscale-User-Login", "owner@example.com")]):
                status, _, body, _ = self.get(service, path, auth, token=None)
                self.assertEqual(status, 401, (service, auth))
                self.assertIn(b"error", body)
        self.assertEqual(self.hister_seen + self.kura_seen, [])
        self.assertEqual(self.helper_calls, [])

    def test_a_refused_or_other_users_token_is_401(self):
        for service, path in (("hister", "/search?query=%7B%7D"), ("kura", "/api/recent")):
            for token in (REVOKED, OTHER):
                status, *_ = self.get(service, path, token=token)
                self.assertEqual(status, 401, (service, token))
        self.assertEqual(self.hister_seen + self.kura_seen, [])

    def test_the_check_names_this_bridge_and_is_cached(self):
        for _ in range(3):
            status, *_ = self.get("hister", "/search?query=%7B%7D", [("Authorization", "Bearer " + GOOD)])
            self.assertEqual(status, 200)
        self.assertEqual(len(self.helper_calls), 1)
        self.assertEqual(self.helper_calls[0]["X-Machiya-Session"], GOOD)
        self.assertEqual(self.helper_calls[0]["X-Machiya-Room"], "http://bridge.example:8070")

    def test_the_cache_expires(self):
        now = [1000.0]
        check = bridge.TokenCheck(self.config, fetch=lambda t: (200, b'{"kind": "token", "username": "owner"}'),
                                  clock=lambda: now[0])
        self.assertEqual(check(GOOD), "ok")
        check.fetch = lambda t: (401, b"{}")
        now[0] += 59
        self.assertEqual(check(GOOD), "ok")
        now[0] += 2
        self.assertEqual(check(GOOD), "out")

    def test_helper_down_is_503(self):
        self.helper.down = True
        for service, path in (("hister", "/search?query=%7B%7D"), ("kura", "/api/recent")):
            status, *_ = self.get(service, path)
            self.assertEqual(status, 503, service)
        self.assertEqual(self.hister_seen + self.kura_seen, [])

    def test_no_hister_token_on_disk_is_503(self):
        os.unlink(self.token_file)
        open(self.token_file, "w").close()
        status, *_ = self.get("hister", "/search?query=%7B%7D", [("Authorization", "Bearer " + GOOD)])
        self.assertEqual(status, 503)

    def test_kura_gets_the_checked_token_and_never_histers(self):
        status, *_ = self.get("kura", "/api/recent", [("Authorization", "bearer  " + GOOD)])
        self.assertEqual(status, 200)
        self.assertEqual(self.kura_seen[0]["headers"]["Authorization"], "Bearer " + GOOD)
        self.assertNotIn("X-Access-Token", self.kura_seen[0]["headers"])
        self.assertEqual(len(self.helper_calls), 1)
        self.assertEqual(self.helper_calls[0]["X-Machiya-Session"], GOOD)
        self.assertEqual(self.helper_calls[0]["X-Machiya-Room"], "http://bridge.example:8070")

    def test_a_forwarded_header_with_a_control_character_or_a_fold_is_400(self):
        for service, path in (("hister", "/search?query=%7B%7D"), ("kura", "/api/recent")):
            for extra in (b"Accept: application/json\r\n folded\r\n", b"If-None-Match: \"a\tb\"\r\n",
                          b"Origin: hister://\x01\r\n", b"Accept: caf\xc3\xa9\r\n"):
                req = b"GET " + path.encode() + b" HTTP/1.0\r\nHost: bridge\r\nAuthorization: Bearer " \
                    + GOOD.encode() + b"\r\n" + extra + b"\r\n"
                line, _, _ = self.raw(service, req)
                self.assertEqual(int(line.split()[1]), 400, (service, extra))
        self.assertEqual(self.hister_seen + self.kura_seen, [])

    # -- replies ----------------------------------------------------------------------------------------------------

    def test_over_the_cap_is_413(self):
        self.answer = lambda p: (200, [("Content-Type", "text/html")], b"x" * 5000, True, 0)
        status, headers, body, _ = self.get("kura", "/api/note?path=a.md")
        self.assertEqual(status, 413)
        self.assertEqual(headers["content-type"], ["application/json"])
        self.assertIn(b"too large", body)

    def test_a_chunked_reply_goes_back_with_a_length(self):
        self.answer = lambda p: (200, [("Content-Type", "application/json")], b"y" * 3000, True, 0)
        status, headers, body, line = self.get("kura", "/api/note?path=a.md")
        self.assertEqual((status, len(body)), (200, 3000))
        self.assertEqual(headers["content-length"], ["3000"])
        self.assertNotIn("transfer-encoding", headers)

    def test_a_redirect_is_passed_back_never_followed(self):
        self.answer = lambda p: (302, [("Location", "https://elsewhere.example/")], b"", False, 0)
        status, headers, _, _ = self.get("kura", "/api/recent")
        self.assertEqual(status, 302)
        self.assertEqual(headers["location"], ["https://elsewhere.example/"])
        self.assertEqual(len(self.kura_seen), 1)

    def test_upstream_errors_pass_through(self):
        self.answer = lambda p: (404, [("Content-Type", "application/json")], b'{"error": "no such note"}', False, 0)
        status, _, body, _ = self.get("kura", "/api/note?path=x.md")
        self.assertEqual((status, body), (404, b'{"error": "no such note"}'))

    def test_a_slow_upstream_is_504(self):
        self.answer = lambda p: (200, [], b"{}", False, 2.5)
        status, *_ = self.get("kura", "/api/recent")
        self.assertEqual(status, 504)

    def test_an_unreachable_upstream_is_502(self):
        dead = socket.socket()
        dead.bind(("127.0.0.1", 0))
        port = dead.getsockname()[1]
        dead.close()
        self.start(BRIDGE_KURA_URL="http://127.0.0.1:%d" % port)
        status, *_ = self.get("kura", "/api/recent")
        self.assertEqual(status, 502)

    # -- paging -----------------------------------------------------------------------------------------------------

    def paged_answer(self, field, html_text, extra=None):
        doc = {"title": "A page", field: html_text, "added": 1, "details": {"big": "x" * 3000}}
        doc.update(extra or {})
        body = json.dumps(doc).encode()
        self.answer = lambda p: (200, [("Content-Type", "application/json"), ("ETag", '"e1"')], body, False, 0)

    def test_a_part_comes_alone_and_part_never_goes_upstream(self):
        text = "".join("<p>Paragraph %d has some words in it, enough to fill a line or two.</p>" % i for i in range(200))
        self.paged_answer("content", "<div>" + text + "</div>")
        status, headers, body, _ = self.get("hister", "/api/preview?url=https%3A%2F%2Fexample.com%2Fa&part=2",
                                            [("If-None-Match", '"e1"')])
        self.assertEqual(status, 200)
        self.assertEqual(self.hister_seen[0]["path"], "/api/preview?url=https%3A%2F%2Fexample.com%2Fa")
        self.assertNotIn("If-None-Match", self.hister_seen[0]["headers"])
        self.assertNotIn("etag", headers)
        doc = json.loads(body)
        self.assertEqual((doc["part"], doc["title"], doc["added"]), (2, "A page", 1))
        self.assertGreater(doc["parts"], 3)
        self.assertNotIn("details", doc)
        self.assertTrue(doc["content"].startswith("<div>") and doc["content"].endswith("</div>"))
        self.assertLessEqual(len(body), 2048 + 200)

    def test_parts_put_back_together_are_the_text_and_always_the_same(self):
        text = "<h2>Top</h2><ul>" + "".join("<li>Item <b>%d</b> &amp; more &lt;words&gt;</li>" % i for i in range(300)) \
            + "</ul><pre>" + "line of code\n" * 400 + "</pre><p>" + "word " * 2000 + "</p>"
        parts = bridge.split_html(bridge.simplify_html(text), 2048)
        self.assertEqual(parts, bridge.split_html(bridge.simplify_html(text), 2048))
        plain = lambda h: re.sub(r"<[^>]+>", "", h)
        self.assertEqual("".join(plain(p) for p in parts), plain(text))
        for p in parts:
            self.assertLessEqual(len(p.encode()), 2048 + 64)
            opened = re.findall(r"<([a-z0-9]+)[ >]", p)
            closed = re.findall(r"</([a-z0-9]+)>", p)
            self.assertEqual(sorted(opened), sorted(closed), p[:80])
        self.assertTrue(any(p.startswith("<ul><li>") or p.startswith("<ul>") for p in parts[1:]))
        self.assertTrue(any(p.startswith("<pre>") for p in parts[1:]))

    def test_only_the_readers_tags_href_and_alt_reach_a_part(self):
        dirty = ('<div onclick="steal()" style="background:url(data:image/png;base64,AAAA)"><p class=x>Hello '
                 '<a href="javascript:alert(1)" onmouseover="x()">bad</a> <a href="data:text/html,hi">data</a> '
                 '<a href="/next">next</a> <a href="https://example.org/ok" target=_blank>ok</a>'
                 '<img src="data:image/png;base64,AAAA" alt="A cat" onerror="x()"><img src="b.png">'
                 '<script>evil()</script><style>p{}</style><svg><title>t</title><path d="M0"/></svg>'
                 '<iframe src="https://example.org/"></iframe><span>kept text</span></p></div>')
        part = "".join(bridge.split_html(bridge.simplify_html(dirty, "https://example.com/dir/page"), 2048))
        for bad in ("data:", "javascript:", "script", "evil", "onclick", "onerror", "onmouseover", "style", "class",
                    "svg", "iframe", "src", "target", "span", "<title"):
            self.assertNotIn(bad, part, bad)
        self.assertIn('<a href="https://example.com/next">next</a>', part)
        self.assertIn('<a href="https://example.org/ok">ok</a>', part)
        self.assertIn('<img alt="A cat">', part)
        self.assertIn("kept text", part)
        self.assertIn("<a>bad</a>", part)

    def test_a_dropped_element_left_open_ends_with_its_parent(self):
        for html_text in ('<div><p>one <button>x<span>y</p><p>two</p></div>',
                          '<section><svg><path d="M0"><g></section><p>two</p>',
                          '<p>one<noscript><img src="x"></p><p>two</p>'):
            text = "".join(bridge.split_html(bridge.simplify_html(html_text), 2048))
            self.assertIn("two", text, html_text)
            self.assertNotIn("x", text.replace("text", ""), html_text)
        # a closed drop still swallows what's in it, nested ones too
        text = "".join(bridge.split_html(bridge.simplify_html('<p>a<svg><svg>in</svg>still</svg>b</p>'), 2048))
        self.assertEqual(text, "<p>ab</p>")

    def test_a_kura_note_is_paged_by_its_html(self):
        self.paged_answer("html", "<p>" + "note words " * 600 + "</p>", {"path": "a/b.md"})
        status, _, body, _ = self.get("kura", "/api/note?path=a%2Fb.md&part=1")
        doc = json.loads(body)
        self.assertEqual((status, doc["path"], doc["part"]), (200, "a/b.md", 1))
        self.assertGreater(doc["parts"], 1)
        self.assertEqual(self.kura_seen[0]["path"], "/api/note?path=a%2Fb.md")

    def test_a_part_past_the_end_or_not_a_number_is_400(self):
        self.paged_answer("content", "<p>short</p>")
        status, _, body, _ = self.get("hister", "/api/preview?url=x&part=3")
        self.assertEqual((status, json.loads(body)["parts"]), (400, 1))
        for bad in ("part=0", "part=abc", "part=1&part=2", "part=", "part=12345", "part=-1"):
            status, *_ = self.get("hister", "/api/preview?url=x&" + bad)
            self.assertEqual(status, 400, bad)

    def test_paging_reads_past_the_macs_cap_but_never_past_its_own(self):
        self.paged_answer("content", "<p>" + "y" * 20000 + "</p>")
        status, _, body, _ = self.get("hister", "/api/preview?url=x&part=1")
        self.assertEqual(status, 200)
        self.assertLessEqual(len(body), 4096)
        self.paged_answer("content", "<p>" + "y" * 70000 + "</p>")
        status, *_ = self.get("hister", "/api/preview?url=x&part=1")
        self.assertEqual(status, 413)
        status, *_ = self.get("hister", "/api/preview?url=x")
        self.assertEqual(status, 413)

    def test_without_part_or_elsewhere_nothing_changes(self):
        self.paged_answer("content", "<p>as it came</p>")
        status, _, body, _ = self.get("hister", "/api/preview?url=x")
        self.assertEqual((status, json.loads(body)["content"]), (200, "<p>as it came</p>"))
        status, *_ = self.get("hister", "/search?q=a&part=1")
        self.assertEqual((status, self.hister_seen[-1]["path"]), (200, "/search?q=a&part=1"))

    def test_an_error_or_a_reply_that_isnt_json_passes_as_it_came(self):
        self.answer = lambda p: (404, [("Content-Type", "application/json")], b'{"error": "not found"}', False, 0)
        status, _, body, _ = self.get("hister", "/api/preview?url=x&part=1")
        self.assertEqual((status, body), (404, b'{"error": "not found"}'))
        self.answer = lambda p: (200, [("Content-Type", "text/html")], b"<p>not json</p>", False, 0)
        status, _, body, _ = self.get("hister", "/api/preview?url=x&part=1")
        self.assertEqual((status, body), (200, b"<p>not json</p>"))

    # -- the log ----------------------------------------------------------------------------------------------------

    def test_the_log_holds_no_query_header_or_token(self):
        self.get("hister", "/search?query=secret+words", [("Authorization", "Bearer " + GOOD)])
        self.get("kura", "/api/search?q=private+words", [("Authorization", "Bearer " + GOOD)])
        self.get("kura", "/api/%2e%2e/secret?q=more+words")
        self.get("hister", "/api/preview?url=https%3A%2F%2Fsecret.example%2F&part=2")
        log = self.log.getvalue()
        self.assertIn(" hister 127.0.0.1 GET /search 200 ", log)
        self.assertIn(" kura 127.0.0.1 GET /api/search 200 ", log)
        for word in ("secret", "private", "more", "words", GOOD, HISTER_TOKEN, "query", "%2e", "part="):
            self.assertNotIn(word, log, word)


if __name__ == "__main__":
    unittest.main()
