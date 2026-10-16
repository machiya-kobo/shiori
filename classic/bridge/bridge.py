"""mac-bridge: Shiori for Classic Macintosh's way into Hister and Kura.

A Mac Plus speaks MacTCP and has no TLS, and the house's services are HTTPS on the tailnet. This small proxy listens on
the LAN in plain HTTP/1.0, one port per service, and passes a short list of read-only requests to a fixed upstream:

    port BRIDGE_HISTER_PORT (8070)  ->  BRIDGE_HISTER_URL   GET /search, /api/preview, /api/config
    port BRIDGE_KURA_PORT   (8071)  ->  BRIDGE_KURA_URL     GET /api/search, /api/recent, /api/note, /api/vaults

The Mac holds one credential, a room token (`Authorization: Bearer mht_…`) with two scopes. On both ports the bridge
first asks hister-login (`GET /v1/check`, as vaultkit's TokenGate does) whether the token is good for this bridge's
token service; a request without one is refused before any upstream is asked, and with the helper down it's a 503.
  - on the Kura port it then goes to Kura as sent, and Kura checks it too (the bridge reaches Kura as its host's own
    tailnet node, so a request Kura couldn't check must never get there);
  - on the Hister port it's dropped and Hister's own token (read from BRIDGE_HISTER_TOKEN_FILE) goes in its place.
    Hister's token never reaches the LAN.

Everything else is refused: another method, another path (matched exactly, before any decoding), a source address off
BRIDGE_ALLOW, `vault=all` or a vault off BRIDGE_VAULTS. Only an allow-list of headers goes upstream, each value plain printable
ASCII (no control characters, no folded lines), and only a short list comes back, held to the same rule (never
Set-Cookie). Replies to the Mac are HTTP/1.0 with Content-Length (never chunked); a reply over
BRIDGE_MAX_BYTES is a 413, a redirect is passed back as is, never followed. Nothing is cached but the token check, and
the log holds the path only: never a query string (search words), a header or a body.

Paging: api/preview (Hister) and api/note (Kura) with part=N go upstream without part, read up to
BRIDGE_PAGED_MAX_BYTES (8 MiB), and come back as one part of their readable HTML (`content`, `html`): only the tags
Shiori's reader renders, with href (http(s), or relative resolved on the page's address) and alt alone, cut at a tag
or a space into parts of about BRIDGE_PART_BYTES (16384), each closing the tags it opened and reopening those it
continues. The reply is compact JSON: the small members as they came, the part, `part` and `parts`. The same upstream
reply always gives the same parts; a part past the end is a 400 that says how many there are now.

`/healthz` on either port answers locally, to any source, for the container's healthcheck and the blackbox probe.

Standard library only. Settings (environment):
    BRIDGE_HISTER_URL, BRIDGE_KURA_URL   the upstreams, https://… (http only with BRIDGE_ALLOW_HTTP_UPSTREAM=1: tests)
    BRIDGE_HISTER_PORT, BRIDGE_KURA_PORT the ports (8070, 8071); BRIDGE_BIND the address (0.0.0.0)
    BRIDGE_ALLOW        the source addresses or networks admitted (required); the tailnet's 100.64.0.0/10 and
                        fd7a:115c:a1e0::/48 are never admitted
    BRIDGE_DENY         addresses or networks never admitted (the host's own LAN address)
    BRIDGE_AUTH_URL     hister-login's internal address (http://hister-login:8081)
    BRIDGE_PUBLIC_URL   the origin this bridge's token service is registered under in HISTER_LOGIN_TOKEN_SERVICES
    BRIDGE_HISTER_USERS the Hister usernames whose room tokens are admitted (never *)
    BRIDGE_HISTER_TOKEN_FILE  Hister's token (a stack secret on tmpfs)
    BRIDGE_VAULTS       Kura vaults a request may name with vault= (besides none: the default vault)
    BRIDGE_MAX_BYTES    the largest reply passed on (524288); BRIDGE_TIMEOUT the upstream timeout in seconds (20)
    BRIDGE_PAGED_MAX_BYTES  the largest upstream reply read for paging (8388608); BRIDGE_PART_BYTES a part (16384)
"""
import collections
import hashlib
import html.parser
import http.client
import http.server
import ipaddress
import json
import os
import re
import socket
import ssl
import sys
import threading
import time
from urllib.parse import parse_qsl, urljoin, urlsplit

VERSION = "0.2.0"

HISTER_PATHS = frozenset({"/search", "/api/preview", "/api/config"})
KURA_PATHS = frozenset({"/api/search", "/api/recent", "/api/note", "/api/vaults"})
NEVER = (ipaddress.ip_network("100.64.0.0/10"),        # the tailnet: its members reach the LAN through a subnet router
         ipaddress.ip_network("fd7a:115c:a1e0::/48"))
RTOKEN_RE = re.compile(r"mht_[A-Za-z0-9_-]{43}\Z")      # a room token (vaultkit's RTOKEN_RE)
VAULT_RE = re.compile(r"[a-z0-9-]{1,64}\Z")
HEADER_VALUE_RE = re.compile(r"[\x20-\x7e]*\Z")          # what a forwarded header's value may hold (no obs-fold)
CHECK_TIMEOUT = 2.0
TTL_OK, TTL_OUT, TTL_DOWN = 60, 5, 5
CACHE_MAX = 256
CLIENT_TIMEOUT = 30                                      # a Mac Plus is slow to send, but not this slow
CHUNK = 65536

# what goes back to the Mac from the upstream's reply
REPLY_HEADERS = ("Content-Type", "ETag", "Cache-Control", "Last-Modified", "Location", "Retry-After")

# Paging (part=N): the readable HTML member of each reply, cut into parts the Mac can hold
PAGED = {"/api/preview": "content", "/api/note": "html"}
PART_RE = re.compile(r"[1-9][0-9]{0,3}\Z")
# the tags Shiori's reader renders (classic/core/notetext.c); every other tag goes, its text stays
KEEP_TAGS = frozenset("h1 h2 h3 h4 h5 h6 p div section article table figure details summary tr dt dd br hr "
                      "blockquote pre ul ol li strong b em i code kbd samp a img td th".split())
VOID_TAGS = frozenset({"br", "hr", "img"})
# elements whose content goes too: nothing in them reads as text
DROP_TAGS = frozenset("script style template svg math iframe object embed video audio canvas noscript head title "
                      "select textarea button".split())
BLOCK_ENDS = frozenset("p div section article table figure details tr li ul ol pre blockquote dd "
                       "h1 h2 h3 h4 h5 h6".split())


def _escape(text, quote=False):
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return text.replace('"', "&quot;") if quote else text


class _Simplifier(html.parser.HTMLParser):
    """The readable HTML down to the reader's tags, href (http(s) or relative) and alt only, as tokens:
    ("start", name, text), ("end", name, text), ("void", name, text) and ("text", raw, None)."""

    def __init__(self, base):
        super().__init__(convert_charrefs=True)
        self.base, self.tokens, self.dropping = base, [], []

    def _start(self, tag, attrs, void):
        if self.dropping:
            if tag == self.dropping[-1] and not void:
                self.dropping.append(tag)
            return
        if tag in DROP_TAGS:
            if not void and tag != "embed":
                self.dropping.append(tag)
            return
        if tag not in KEEP_TAGS:
            return
        out = "<" + tag
        if tag == "a":
            href = _safe_href(dict(attrs).get("href") or "", self.base)
            if href:
                out += ' href="%s"' % _escape(href, True)
        elif tag == "img":
            alt = (dict(attrs).get("alt") or "").strip()
            if not alt:
                return
            out += ' alt="%s"' % _escape(alt, True)
        out += ">"
        self.tokens.append(("void" if tag in VOID_TAGS else "start", tag, out))

    def handle_starttag(self, tag, attrs):
        self._start(tag, attrs, False)

    def handle_startendtag(self, tag, attrs):
        self._start(tag, attrs, True)

    def handle_endtag(self, tag):
        if self.dropping:
            if tag == self.dropping[-1]:
                self.dropping.pop()
            return
        if tag in KEEP_TAGS and tag not in VOID_TAGS:
            self.tokens.append(("end", tag, "</%s>" % tag))

    def handle_data(self, data):
        if not self.dropping and data:
            if self.tokens and self.tokens[-1][0] == "text":
                self.tokens[-1] = ("text", self.tokens[-1][1] + data, None)
            else:
                self.tokens.append(("text", data, None))


def _safe_href(href, base):
    """An http(s) address, a relative one resolved on the page's own when it's known; anything else (javascript:,
    data:, mailto:…) is no link."""
    href = href.strip()
    if not href or any(ord(c) < 32 for c in href):
        return ""
    scheme = urlsplit(href).scheme.lower()
    if scheme in ("http", "https"):
        return href
    if scheme or href.startswith("//"):
        return ""
    if base:
        joined = urljoin(base, href)
        return joined if urlsplit(joined).scheme.lower() in ("http", "https") else ""
    return href


def simplify_html(text, base=""):
    p = _Simplifier(base)
    p.feed(text)
    p.close()
    return p.tokens


def _cut_text(raw, room):
    """The longest head of raw whose escaped form fits room bytes, ending at a space when one is near."""
    lo, hi = 0, min(len(raw), room)          # each character takes a byte at least
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if len(_escape(raw[:mid]).encode("utf-8")) <= room:
            lo = mid
        else:
            hi = mid - 1
    head = raw[:lo]
    space = max(head.rfind(" "), head.rfind("\n"))
    if space > len(head) // 2:
        head = head[:space + 1]
    return head or raw[:1]


def split_html(tokens, limit):
    """Parts of at most about limit bytes, each standing alone: the tags open at a cut are closed at its end and
    opened again at the next part's start. The same tokens always give the same parts."""
    parts, stack, body, size = [], [], [], 0

    def opening():
        return "".join(t for _, t in stack)

    def closing():
        return "".join("</%s>" % n for n, _ in reversed(stack))

    def cut():
        nonlocal body, size
        parts.append(opening_at_start[0] + "".join(body) + closing())
        body, size = [], 0
        opening_at_start[0] = opening()

    opening_at_start = [""]
    for kind, name, text in tokens:
        frame = len(opening_at_start[0]) + len(closing())
        if kind == "text":
            raw = name
            while raw:
                room = limit - frame - size
                piece = _escape(raw)
                if len(piece.encode("utf-8")) <= room:
                    body.append(piece)
                    size += len(piece.encode("utf-8"))
                    break
                if size > 0 and room < limit // 4:
                    cut()
                    frame = len(opening_at_start[0]) + len(closing())
                    continue
                head = _cut_text(raw, max(room, 64))
                body.append(_escape(head))
                raw = raw[len(head):]
                cut()
                frame = len(opening_at_start[0]) + len(closing())
            continue
        n = len(text.encode("utf-8"))
        if size > 0 and frame + size + n > limit:
            cut()
        if kind == "start":
            stack.append((name, text))
        elif kind == "end":
            if not any(s == name for s, _ in stack):
                continue
            while stack:
                top, _ = stack.pop()
                body.append("</%s>" % top)
                size += len(top) + 3
                if top == name:
                    break
            if name in BLOCK_ENDS and size >= limit * 3 // 4:
                cut()
            continue
        body.append(text)
        size += n
    if body or not parts:
        parts.append(opening_at_start[0] + "".join(body) + closing())
    return parts


class ConfigError(Exception):
    pass


def _list(raw):
    return [x.strip() for x in (raw or "").split(",") if x.strip()]


def _networks(raw, what):
    out = []
    for entry in _list(raw):
        try:
            out.append(ipaddress.ip_network(entry, strict=False))
        except ValueError:
            raise ConfigError("%s: %r is not an address or network" % (what, entry))
    return out


def _upstream(url, what, allow_http):
    u = urlsplit(url or "")
    if u.scheme not in ("https", "http") or not u.hostname or u.username or u.path not in ("", "/") or u.query:
        raise ConfigError("%s: %r is not an https://host[:port] address" % (what, url))
    if u.scheme == "http" and not allow_http:
        raise ConfigError("%s: the upstream must be https" % what)
    return u.scheme, u.hostname, u.port or (443 if u.scheme == "https" else 80)


class Config:
    def __init__(self, env):
        allow_http = (env.get("BRIDGE_ALLOW_HTTP_UPSTREAM") or "") == "1"
        self.hister = _upstream(env.get("BRIDGE_HISTER_URL"), "BRIDGE_HISTER_URL", allow_http)
        self.kura = _upstream(env.get("BRIDGE_KURA_URL"), "BRIDGE_KURA_URL", allow_http)
        self.bind = env.get("BRIDGE_BIND") or "0.0.0.0"
        try:
            self.hister_port = int(env.get("BRIDGE_HISTER_PORT") or 8070)
            self.kura_port = int(env.get("BRIDGE_KURA_PORT") or 8071)
            self.max_bytes = int(env.get("BRIDGE_MAX_BYTES") or 524288)
            self.paged_max_bytes = int(env.get("BRIDGE_PAGED_MAX_BYTES") or 8388608)
            self.part_bytes = int(env.get("BRIDGE_PART_BYTES") or 16384)
            self.timeout = float(env.get("BRIDGE_TIMEOUT") or 20)
        except ValueError as e:
            raise ConfigError("a number setting is not a number: %s" % e)
        if self.part_bytes < 2048 or self.part_bytes > self.max_bytes // 2:
            raise ConfigError("BRIDGE_PART_BYTES: 2048 at least, and at most half of BRIDGE_MAX_BYTES")
        if self.paged_max_bytes < self.max_bytes:
            raise ConfigError("BRIDGE_PAGED_MAX_BYTES: at least BRIDGE_MAX_BYTES")
        self.allow = _networks(env.get("BRIDGE_ALLOW"), "BRIDGE_ALLOW")
        self.deny = _networks(env.get("BRIDGE_DENY"), "BRIDGE_DENY") + list(NEVER)
        if not self.allow:
            raise ConfigError("BRIDGE_ALLOW: name the Macs' addresses (nothing is admitted by default)")
        for net in self.allow:
            for bad in self.deny:
                if net.version == bad.version and net.overlaps(bad):
                    raise ConfigError("BRIDGE_ALLOW: %s overlaps %s, which is never admitted" % (net, bad))
        self.auth_url = (env.get("BRIDGE_AUTH_URL") or "").strip().rstrip("/")
        _upstream(self.auth_url, "BRIDGE_AUTH_URL", True)
        self.public = (env.get("BRIDGE_PUBLIC_URL") or "").strip().rstrip("/")
        if not re.match(r"https?://[a-z0-9.-]+(:[0-9]{1,5})?\Z", self.public):
            raise ConfigError("BRIDGE_PUBLIC_URL: the origin registered for this bridge's token service")
        self.users = frozenset(_list(env.get("BRIDGE_HISTER_USERS")))
        if not self.users or "*" in self.users:
            raise ConfigError("BRIDGE_HISTER_USERS: the Hister usernames admitted (never *)")
        self.token_file = env.get("BRIDGE_HISTER_TOKEN_FILE") or ""
        if not self.token_file:
            raise ConfigError("BRIDGE_HISTER_TOKEN_FILE: where Hister's token is")
        self.vaults = frozenset(_list(env.get("BRIDGE_VAULTS")))
        for v in self.vaults:
            if v == "all" or not VAULT_RE.match(v):
                raise ConfigError("BRIDGE_VAULTS: %r is not a vault name" % v)
        self.ca_file = env.get("BRIDGE_CA_FILE") or None

    def admits(self, address):
        try:
            ip = ipaddress.ip_address(address)
        except ValueError:
            return False
        if ip.version == 6 and ip.ipv4_mapped:
            ip = ip.ipv4_mapped
        if any(ip.version == n.version and ip in n for n in self.deny):
            return False
        return any(ip.version == n.version and ip in n for n in self.allow)


class TokenCheck:
    """Whether a room token is good for this bridge: hister-login's GET /v1/check, cached briefly."""

    def __init__(self, config, fetch=None, clock=time.monotonic):
        self.config, self.clock = config, clock
        self.fetch = fetch or self._fetch
        self.cache = collections.OrderedDict()
        self.lock = threading.Lock()

    def _fetch(self, token):
        u = urlsplit(self.config.auth_url)
        cls = http.client.HTTPSConnection if u.scheme == "https" else http.client.HTTPConnection
        conn = cls(u.hostname, u.port, timeout=CHECK_TIMEOUT)
        try:
            conn.request("GET", "/v1/check", headers={"X-Machiya-Session": token, "X-Machiya-Room": self.config.public,
                                                     "Accept": "application/json"})
            r = conn.getresponse()
            return r.status, r.read(1 << 16)
        finally:
            conn.close()

    def __call__(self, token):
        """'ok', 'out' (bad, revoked, another service's or another user's) or 'down' (the helper didn't answer)."""
        key = hashlib.sha256(token.encode("ascii")).hexdigest()
        with self.lock:
            hit = self.cache.get(key)
            if hit and hit[0] > self.clock():
                return hit[1]
        try:
            status, body = self.fetch(token)
            data = json.loads(body) if body else None
        except (OSError, http.client.HTTPException, ValueError):
            status, data = None, None
        if status == 200 and isinstance(data, dict) and data.get("kind") == "token" \
                and isinstance(data.get("username"), str) and data["username"] in self.config.users:
            outcome, ttl = "ok", TTL_OK
        elif status in (200, 400, 401, 403):
            outcome, ttl = "out", TTL_OUT
        else:
            outcome, ttl = "down", TTL_DOWN
        with self.lock:
            self.cache[key] = (self.clock() + ttl, outcome)
            while len(self.cache) > CACHE_MAX:
                self.cache.popitem(last=False)
        return outcome


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    server_version = "mac-bridge/" + VERSION
    sys_version = ""
    timeout = CLIENT_TIMEOUT

    # set per server by make_server
    service = ""          # "hister" or "kura"
    config = None
    check = None
    log_out = sys.stdout

    # -- replies ----------------------------------------------------------------------------------------------------

    def _reply(self, status, body, headers=()):
        if any("\r" in value or "\n" in value for _, value in headers):
            # A backstop: no header value may start a line of its own on the Mac's connection.
            status, body, headers = 500, b'{"error": "a bad reply header"}', [("Content-Type", "application/json")]
        self.send_response(status)
        for name, value in headers:
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        if self.command != "HEAD" and body:
            self.wfile.write(body)
        self._sent = (status, len(body))

    def _error(self, status, message):
        self._reply(status, json.dumps({"error": message}).encode(), [("Content-Type", "application/json")])

    def log_message(self, fmt, *args):      # http.server's own lines carry the request line: never log those
        pass

    def log_error(self, fmt, *args):
        pass

    def _log(self, path, started):
        status, size = getattr(self, "_sent", (0, 0))
        line = "%s %s %s %s %s %d %d %dms\n" % (time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), self.service,
                                                self.client_address[0], self.command, path, status, size,
                                                (time.monotonic() - started) * 1000)
        try:
            self.log_out.write(line)
            self.log_out.flush()
        except (OSError, ValueError):
            pass

    # -- requests ---------------------------------------------------------------------------------------------------

    def do_GET(self):
        started = time.monotonic()
        # the request line's own target: http.server folds a leading "//" in self.path, and nothing may be rewritten
        parts = self.requestline.split()
        target = parts[1] if len(parts) == 3 else ""
        raw_path = target.split("?", 1)[0]
        logged = raw_path if raw_path in HISTER_PATHS | KURA_PATHS | {"/healthz"} else "-"
        try:
            self._handle(target, raw_path)
        except (OSError, http.client.HTTPException):
            pass
        finally:
            self._log(logged, started)

    def _refuse_method(self):
        started = time.monotonic()
        try:
            self._error(405, "only GET is offered here")
        except OSError:
            pass
        self._log("-", started)

    do_POST = do_PUT = do_DELETE = do_PATCH = do_HEAD = do_OPTIONS = do_TRACE = do_CONNECT = _refuse_method

    def _handle(self, target, raw_path):
        if raw_path == "/healthz":
            return self._reply(200, b"ok\n", [("Content-Type", "text/plain")])
        if not self.config.admits(self.client_address[0]):
            return self._error(403, "this address isn't admitted")
        if not target.startswith("/") or target.startswith("//") or "#" in target \
                or any(ord(c) < 33 or ord(c) > 126 for c in target):
            return self._error(400, "not a request this bridge reads")
        if self.headers.get("Content-Length", "0").strip() not in ("", "0") or "Transfer-Encoding" in self.headers:
            return self._error(400, "a GET has no body")
        paths = HISTER_PATHS if self.service == "hister" else KURA_PATHS
        if raw_path not in paths:
            return self._error(404, "not offered here")
        query = target[len(raw_path):]
        try:
            pairs = parse_qsl(query[1:], keep_blank_values=True, max_num_fields=64) if query else []
        except ValueError:
            return self._error(400, "not a query this bridge reads")
        paged = None
        if raw_path in PAGED and any(name == "part" for name, _ in pairs):
            values = [v for name, v in pairs if name == "part"]
            if len(values) != 1 or not PART_RE.match(values[0]):
                return self._error(400, "part is a number from 1")
            paged = (PAGED[raw_path], int(values[0]), dict(pairs).get("url", ""))
            # the upstream gets the query as it came, less part=
            kept = [field for field in query[1:].split("&") if field.split("=", 1)[0] != "part"]
            target = raw_path + ("?" + "&".join(kept) if kept else "")

        forwarded = ("Accept", "If-None-Match", "Origin", "Authorization")
        if any(not HEADER_VALUE_RE.match(v) for name in forwarded for v in self.headers.get_all(name) or []):
            return self._error(400, "not a header this bridge reads")
        headers = [("Accept", self._one("Accept") or "application/json"), ("Accept-Encoding", "identity"),
                   ("Connection", "close")]
        etag = self._one("If-None-Match")
        if etag and not paged:
            headers.append(("If-None-Match", etag))
        if self._one("Origin") == "hister://":
            headers.append(("Origin", "hister://"))

        if self.service == "kura":
            refusal = self._vault_refusal(pairs)
            if refusal:
                return self._error(403, refusal)
        auth = self.headers.get_all("Authorization") or []
        if len(auth) > 1:
            return self._error(401, "one credential, please")
        scheme, _, token = (auth[0] if auth else "").strip().partition(" ")
        token = token.strip()
        if not auth or scheme.lower() != "bearer" or not RTOKEN_RE.match(token):
            return self._error(401, "sign in: this Mac's room token is needed")
        outcome = self.check(token)
        if outcome == "down":
            return self._error(503, "sign-in is unavailable: try again")
        if outcome != "ok":
            return self._error(401, "that room token isn't good for this bridge")

        if self.service == "kura":
            headers.append(("Authorization", "Bearer " + token))
            upstream = self.config.kura
        else:
            try:
                with open(self.config.token_file, encoding="ascii") as f:
                    hister_token = f.read().strip()
            except (OSError, UnicodeDecodeError):
                hister_token = ""
            if not re.match(r"[\x21-\x7e]{8,512}\Z", hister_token):
                return self._error(503, "the bridge has no Hister token")
            headers.append(("X-Access-Token", hister_token))
            upstream = self.config.hister
        return self._forward(upstream, target, headers, paged)

    def _one(self, name):
        values = self.headers.get_all(name) or []
        return values[0].strip() if len(values) == 1 else ""

    def _vault_refusal(self, pairs):
        for name, value in pairs:
            if name != "vault":
                continue
            for v in value.split(","):
                v = v.strip()
                if v == "all":
                    return "every vault isn't offered here"
                if v not in self.config.vaults:
                    return "that vault isn't offered here"
        return None

    def _paged_reply(self, status, body, back, paged):
        """One part of a 200 JSON reply's readable HTML; anything else as it came, held to the Mac's cap."""
        field, part, base = paged
        data = None
        if status == 200:
            try:
                data = json.loads(body.decode("utf-8"))
            except (UnicodeDecodeError, ValueError):
                data = None
        if not isinstance(data, dict) or not isinstance(data.get(field), str):
            if len(body) > self.config.max_bytes:
                return self._error(413, "too large for this Mac (over %d bytes)" % self.config.max_bytes)
            return self._reply(status, body, back)
        parts = split_html(simplify_html(data[field], base if self.service == "hister" else ""),
                           self.config.part_bytes)
        if part > len(parts):
            return self._reply(400, json.dumps({"error": "there's no such part: it may have changed",
                                                "parts": len(parts)}).encode(), [("Content-Type", "application/json")])
        # the small members as they came (title, path, dates); lists, objects and long strings stay behind
        out = {k: v for k, v in data.items()
               if k != field and (v is None or isinstance(v, (bool, int, float)) or (isinstance(v, str) and len(v) <= 1024))}
        out.update({field: parts[part - 1], "part": part, "parts": len(parts)})
        reply = json.dumps(out, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        return self._reply(200, reply, [("Content-Type", "application/json")])

    def _forward(self, upstream, target, headers, paged=None):
        scheme, host, port = upstream
        if scheme == "https":
            ctx = ssl.create_default_context(cafile=self.config.ca_file)
            conn = http.client.HTTPSConnection(host, port, timeout=self.config.timeout, context=ctx)
        else:
            conn = http.client.HTTPConnection(host, port, timeout=self.config.timeout)
        deadline = time.monotonic() + self.config.timeout
        try:
            conn.putrequest("GET", target, skip_host=True, skip_accept_encoding=True)
            default_port = 443 if scheme == "https" else 80
            conn.putheader("Host", host if port == default_port else "%s:%d" % (host, port))
            for name, value in headers:
                conn.putheader(name, value)
            conn.endheaders()
            r = conn.getresponse()
            chunks, size = [], 0
            cap = self.config.paged_max_bytes if paged else self.config.max_bytes
            while True:
                if time.monotonic() > deadline:
                    raise socket.timeout()
                chunk = r.read(CHUNK)
                if not chunk:
                    break
                size += len(chunk)
                if size > cap:
                    return self._error(413, "too large for this Mac (over %d bytes)" % cap)
                chunks.append(chunk)
            # Only printable ASCII comes back: http.client keeps a folded or control-character value as it came.
            back = [(n, v) for n in REPLY_HEADERS for v in [r.getheader(n)] if v and HEADER_VALUE_RE.match(v)]
            if paged:
                return self._paged_reply(r.status, b"".join(chunks), back, paged)
            return self._reply(r.status, b"".join(chunks), back)
        except socket.timeout:
            return self._error(504, "%s didn't answer in time" % ("Hister" if self.service == "hister" else "Kura"))
        except (OSError, http.client.HTTPException):
            return self._error(502, "can't reach %s" % ("Hister" if self.service == "hister" else "Kura"))
        finally:
            conn.close()


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 16


def make_server(service, config, check, bind=None, port=None, log_out=None):
    handler = type("%sHandler" % service.title(), (Handler,),
                   {"service": service, "config": config, "check": check, "log_out": log_out or sys.stdout})
    if port is None:
        port = config.hister_port if service == "hister" else config.kura_port
    return Server((bind if bind is not None else config.bind, port), handler)


def main(env=None):
    try:
        config = Config(os.environ if env is None else env)
    except ConfigError as e:
        sys.stderr.write("mac-bridge: %s\n" % e)
        return 2
    check = TokenCheck(config)
    servers = [make_server("hister", config, check), make_server("kura", config, check)]
    for s in servers[1:]:
        threading.Thread(target=s.serve_forever, daemon=True).start()
    sys.stdout.write("mac-bridge %s: Hister on %d, Kura on %d\n" % (VERSION, config.hister_port, config.kura_port))
    sys.stdout.flush()
    try:
        servers[0].serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
