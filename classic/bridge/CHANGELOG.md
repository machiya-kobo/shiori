# mac-bridge changelog

## 0.2.1 (2026-10-16)

- Paging: an element whose content is dropped (an `svg`, a `button`, a
  `noscript`…) and whose end tag never comes now ends with the element
  around it, instead of dropping the rest of the page.

## 0.2.0 (2026-10-16)

- Paging: `api/preview` and `api/note` take `part=N` (from 1), which
  never goes upstream. The reply is that part of the readable HTML, about
  `BRIDGE_PART_BYTES` (16384), with only the tags Shiori's reader renders
  and `href` (http(s) or relative) and `alt` alone, so no script, style,
  `on…` attribute or `data:` address reaches the Mac. Parts are cut at a
  tag or a space and stand alone, the same reply always gives the same
  parts, and the JSON says `part` and `parts`. A part past the end is a
  400 with the count. The upstream reply may be up to
  `BRIDGE_PAGED_MAX_BYTES` (8 MiB) for this; the Mac still gets one part.

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
