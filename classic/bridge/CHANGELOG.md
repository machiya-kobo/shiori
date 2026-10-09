# mac-bridge changelog

## 0.1.2 (2026-10-08)

- A reply header from Hister or Kura whose value isn't printable ASCII (a
  folded line or a control character) is dropped, as a forwarded one is
  refused; any value with a line break left is a 500, never sent.

## 0.1.1 (2026-10-07)

- The Kura port checks the room token with hister-login too, as the
  Hister port does: no token or a refused one is a 401, the helper down a
  503, and Kura is never asked. The bridge reaches Kura as its host's own
  tailnet node, so nothing unchecked may pass.
- The tailnet's IPv6 range (fd7a:115c:a1e0::/48) can never be admitted.
- A forwarded header whose value isn't printable ASCII (a control
  character or a folded line) is a 400.

## 0.1.0 (2026-10-07)

- First version: plain HTTP/1.0 on two LAN ports for Shiori for Classic
  Macintosh, GET only, exact paths, a source allow-list (never the
  tailnet), header allow-lists both ways, the Mac's room token checked
  with hister-login and swapped for Hister's token on the Hister port,
  Kura vaults limited to a list, a 413 over the reply cap, redirects
  passed back, and a log with no query strings, headers or bodies.
