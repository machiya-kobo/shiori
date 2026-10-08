# mac-bridge

Shiori for Classic Macintosh runs on a Mac Plus with MacTCP, which has no
TLS. This proxy lets it reach Hister and Kura: plain HTTP/1.0 on the LAN,
one port per service, a few read-only paths, passed to a fixed HTTPS
upstream. `bridge.py`'s docstring is the full description and lists the
settings.

- **One credential on the Mac:** a room token (`mht_…`) issued by
  hister-login with two scopes, `kura` and the bridge's own token
  service. On both ports the bridge checks it with hister-login first: no
  token, or one refused, is a 401, and with the helper down a 503, before
  any upstream is asked. Kura then gets it as sent and checks it too; on
  the Hister port Hister's token goes in its place. Hister's token never
  reaches the LAN.
- **What it refuses:** any method but GET, any path not listed (matched
  before decoding), sources off `BRIDGE_ALLOW` (the tailnet's
  100.64.0.0/10 and fd7a:115c:a1e0::/48 can't be listed), `vault=all`,
  vaults off `BRIDGE_VAULTS`, and a forwarded header whose value isn't
  printable ASCII (a control character or a folded line).
- **What passes:** a short list of headers each way (never `Cookie`,
  `Set-Cookie`, `Tailscale-*` or `X-Forwarded-*`). Replies come back with
  `Content-Length`, never chunked. A reply over `BRIDGE_MAX_BYTES` is a
  413. Redirects are passed back, never followed.
- **The log** has the path, status and size only: never a query string,
  a header or a body.
- **The trust boundary:** the LAN. The room token crosses it in clear,
  and an address allow-list can be spoofed.

Tests: `python3 -m unittest discover -s classic/bridge` (also run by
`node --test scripts/*.test.mjs`). They use fakes on loopback only.

Deploying: the image is built from this directory (`Dockerfile`) and
runs in the deployment's hister stack, published on the LAN address only.
