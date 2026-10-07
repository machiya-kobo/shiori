#!/usr/bin/env python3
"""The fake house for Shiori for Classic Macintosh in Snow and Basilisk II: the real bridge
(classic/bridge/bridge.py) in front of haiku/fake-services.py's fake Hister and Kura, with a
fake hister-login that knows one room token. Nothing here reaches a real service.

    classic/tests/fake_house.py --allow 192.168.1.0/24 [--hister-port 8070] [--kura-port 8071]

The emulated Mac then uses http://<this host's LAN address>:8070/ and :8071/ with the room token
mht_KKKK… (43 K's), the one fake-services' Kura and this helper accept. The bridge swaps it for
fake Hister's token, as the real one does. Snow's NAT connects from this host's own LAN address;
Basilisk II's bridged guest from its own. Every request is logged (the bridge's log and
fake-services' credential checks, which shout LEAK when a credential goes astray).
"""
import argparse
import http.server
import json
import os
import subprocess
import sys
import tempfile
import threading

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
sys.path.insert(0, os.path.join(root, "classic", "bridge"))
import bridge  # noqa: E402

ROOM_TOKEN = "mht_" + "K" * 43
HISTER_TOKEN = "FAKE-HISTER-TOKEN-0123"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--allow", required=True, help="source addresses or networks the bridge admits")
    ap.add_argument("--hister-port", type=int, default=8070)
    ap.add_argument("--kura-port", type=int, default=8071)
    ap.add_argument("--fake-ports", default="8401,8402,8403", help="fake Hister, Kura and hister-login (loopback)")
    args = ap.parse_args()
    fh, fk, fl = (int(p) for p in args.fake_ports.split(","))
    public = "http://bridge.invalid:%d" % args.hister_port

    class Helper(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_GET(self):
            ok = (self.path == "/v1/check" and self.headers.get("X-Machiya-Session") == ROOM_TOKEN
                  and self.headers.get("X-Machiya-Room") == public)
            body = json.dumps({"kind": "token", "username": "alex"} if ok else {"reason": "unknown"}).encode()
            self.send_response(200 if ok else 401)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            print("helper /v1/check", "ok" if ok else "refused", flush=True)

    helper = http.server.ThreadingHTTPServer(("127.0.0.1", fl), Helper)
    threading.Thread(target=helper.serve_forever, daemon=True).start()
    fakes = subprocess.Popen([sys.executable, os.path.join(root, "haiku", "fake-services.py"), str(fh), str(fk)])

    token = tempfile.NamedTemporaryFile("w", prefix="fake-hister-token-", delete=False)
    token.write(HISTER_TOKEN)
    token.close()
    env = {
        "BRIDGE_HISTER_URL": "http://127.0.0.1:%d" % fh, "BRIDGE_KURA_URL": "http://127.0.0.1:%d" % fk,
        "BRIDGE_ALLOW_HTTP_UPSTREAM": "1", "BRIDGE_ALLOW": args.allow,
        "BRIDGE_AUTH_URL": "http://127.0.0.1:%d" % fl, "BRIDGE_PUBLIC_URL": public,
        "BRIDGE_HISTER_USERS": "alex", "BRIDGE_HISTER_TOKEN_FILE": token.name,
        "BRIDGE_HISTER_PORT": str(args.hister_port), "BRIDGE_KURA_PORT": str(args.kura_port),
    }
    try:
        config = bridge.Config(env)
    except bridge.ConfigError as e:
        sys.exit("fake_house: %s" % e)
    check = bridge.TokenCheck(config)
    servers = [bridge.make_server("hister", config, check), bridge.make_server("kura", config, check)]
    threading.Thread(target=servers[1].serve_forever, daemon=True).start()
    print("fake house: bridge on :%d (Hister) and :%d (Kura), admitting %s; room token %s…"
          % (args.hister_port, args.kura_port, args.allow, ROOM_TOKEN[:8]), flush=True)
    try:
        servers[0].serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        fakes.terminate()
        os.unlink(token.name)


if __name__ == "__main__":
    main()
