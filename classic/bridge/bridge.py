"""mac-bridge: Shiori for Classic Macintosh's way into Hister and Kura.

A Mac Plus speaks MacTCP and has no TLS, and the house's services are HTTPS on the tailnet. This small proxy listens on
the LAN in plain HTTP/1.0, one port per service, and passes a short list of read-only requests to a fixed upstream:

    port BRIDGE_HISTER_PORT (8070)  ->  BRIDGE_HISTER_URL   GET /search, /api/preview, /api/config
    port BRIDGE_KURA_PORT   (8071)  ->  BRIDGE_KURA_URL     GET /api/search, /api/recent, /api/note, /api/vaults

The Mac holds one credential, a room token (`Authorization: Bearer mht_…`) with two scopes:
  - on the Kura port it goes to Kura untouched, and Kura checks it;
  - on the Hister port the bridge asks hister-login (`GET /v1/check`, as vaultkit's TokenGate does) whether the token
    is good for this bridge's token service, and only then drops it and adds Hister's own token (read from
    BRIDGE_HISTER_TOKEN_FILE). Hister's token never reaches the LAN.

Everything else is refused: another method, another path (matched exactly, before any decoding), a source address off
BRIDGE_ALLOW, `vault=all` or a vault off BRIDGE_VAULTS. Only an allow-list of headers goes upstream, and only a short
list comes back (never Set-Cookie). Replies to the Mac are HTTP/1.0 with Content-Length (never chunked); a reply over
BRIDGE_MAX_BYTES is a 413, a redirect is passed back as is, never followed. Nothing is cached but the token check, and
the log holds the path only: never a query string (search words), a header or a body.

`/healthz` on either port answers locally, to any source, for the container's healthcheck and the blackbox probe.

Standard library only. Settings (environment):
    BRIDGE_HISTER_URL, BRIDGE_KURA_URL   the upstreams, https://… (http only with BRIDGE_ALLOW_HTTP_UPSTREAM=1: tests)
    BRIDGE_HISTER_PORT, BRIDGE_KURA_PORT the ports (8070, 8071); BRIDGE_BIND the address (0.0.0.0)
    BRIDGE_ALLOW        the source addresses or networks admitted (required); 100.64.0.0/10 is never admitted
    BRIDGE_DENY         addresses or networks never admitted (the host's own LAN address)
    BRIDGE_AUTH_URL     hister-login's internal address (http://hister-login:8081)
    BRIDGE_PUBLIC_URL   the origin this bridge's token service is registered under in HISTER_LOGIN_TOKEN_SERVICES
    BRIDGE_HISTER_USERS the Hister usernames whose room tokens are admitted (never *)
    BRIDGE_HISTER_TOKEN_FILE  Hister's token (a stack secret on tmpfs)
    BRIDGE_VAULTS       Kura vaults a request may name with vault= (besides none: the default vault)
    BRIDGE_MAX_BYTES    the largest reply passed on (524288); BRIDGE_TIMEOUT the upstream timeout in seconds (20)
"""
import collections
import hashlib
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
from urllib.parse import parse_qsl, urlsplit

VERSION = "0.1.0"

HISTER_PATHS = frozenset({"/search", "/api/preview", "/api/config"})
KURA_PATHS = frozenset({"/api/search", "/api/recent", "/api/note", "/api/vaults"})
NEVER = (ipaddress.ip_network("100.64.0.0/10"),)        # the tailnet: its members reach the LAN through a subnet router
RTOKEN_RE = re.compile(r"mht_[A-Za-z0-9_-]{43}\Z")      # a room token (vaultkit's RTOKEN_RE)
VAULT_RE = re.compile(r"[a-z0-9-]{1,64}\Z")
CHECK_TIMEOUT = 2.0
TTL_OK, TTL_OUT, TTL_DOWN = 60, 5, 5
CACHE_MAX = 256
CLIENT_TIMEOUT = 30                                      # a Mac Plus is slow to send, but not this slow
CHUNK = 65536

# what goes back to the Mac from the upstream's reply
REPLY_HEADERS = ("Content-Type", "ETag", "Cache-Control", "Last-Modified", "Location", "Retry-After")


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
            self.timeout = float(env.get("BRIDGE_TIMEOUT") or 20)
        except ValueError as e:
            raise ConfigError("a number setting is not a number: %s" % e)
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

        headers = [("Accept", self._one("Accept") or "application/json"), ("Accept-Encoding", "identity"),
                   ("Connection", "close")]
        etag = self._one("If-None-Match")
        if etag:
            headers.append(("If-None-Match", etag))
        if self._one("Origin") == "hister://":
            headers.append(("Origin", "hister://"))
        auth = self.headers.get_all("Authorization") or []
        if len(auth) > 1:
            return self._error(401, "one credential, please")

        if self.service == "kura":
            refusal = self._vault_refusal(pairs)
            if refusal:
                return self._error(403, refusal)
            if auth:
                headers.append(("Authorization", auth[0].strip()))
            upstream = self.config.kura
        else:
            scheme, _, token = (auth[0] if auth else "").strip().partition(" ")
            token = token.strip()
            if not auth or scheme.lower() != "bearer" or not RTOKEN_RE.match(token):
                return self._error(401, "sign in: this Mac's room token is needed")
            outcome = self.check(token)
            if outcome == "down":
                return self._error(503, "sign-in is unavailable: try again")
            if outcome != "ok":
                return self._error(401, "that room token isn't good for this bridge")
            try:
                with open(self.config.token_file, encoding="ascii") as f:
                    hister_token = f.read().strip()
            except (OSError, UnicodeDecodeError):
                hister_token = ""
            if not re.match(r"[\x21-\x7e]{8,512}\Z", hister_token):
                return self._error(503, "the bridge has no Hister token")
            headers.append(("X-Access-Token", hister_token))
            upstream = self.config.hister
        return self._forward(upstream, target, headers)

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

    def _forward(self, upstream, target, headers):
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
            while True:
                if time.monotonic() > deadline:
                    raise socket.timeout()
                chunk = r.read(CHUNK)
                if not chunk:
                    break
                size += len(chunk)
                if size > self.config.max_bytes:
                    return self._error(413, "too large for this Mac (over %d bytes)" % self.config.max_bytes)
                chunks.append(chunk)
            back = [(n, r.getheader(n)) for n in REPLY_HEADERS if r.getheader(n)]
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
