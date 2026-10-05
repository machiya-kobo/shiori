// Tests for web/dev-server.py's routing (the same routes web/README.md asks
// of the real host), through python3.
// Run: node --test scripts/*.test.mjs

import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import assert from 'node:assert/strict';

const server = fileURLToPath(new URL('../web/dev-server.py', import.meta.url));

/** What route() answers for each path: null (the build), '' (a 404) or the upstream URL. */
function routes(paths) {
  const script = `
import importlib.util, json, sys, types
spec = importlib.util.spec_from_file_location("dev_server", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(json.dumps([m.Handler.route(types.SimpleNamespace(path=p)) for p in json.loads(sys.argv[2])]))
`;
  const env = { ...process.env, HISTER_URL: 'https://hister.example/', KURA_URL: 'https://kura.example/', SEARXNG_URL: 'https://searx.example/' };
  return JSON.parse(execFileSync('python3', ['-c', script, server, JSON.stringify(paths)], { env, encoding: 'utf8' }));
}

test('Kura: only the API paths Shiori asks for, never its reader', () => {
  const asked = ['/kura/api/search?q=x&limit=5', '/kura/api/recent?limit=5', '/kura/api/note?path=a.md', '/kura/api/vaults', '/kura/api/prefs', '/kura/feed.xml?q=x'];
  assert.deepEqual(routes(asked), [
    'https://kura.example/api/search?q=x&limit=5',
    'https://kura.example/api/recent?limit=5',
    'https://kura.example/api/note?path=a.md',
    'https://kura.example/api/vaults',
    'https://kura.example/api/prefs',
    'https://kura.example/feed.xml?q=x',
  ]);
  // A work note's reader page (and every way Kura would reach it), the
  // default vault's, and Kura's other pages and API: a 404 here.
  const refused = ['/kura/v/work/n/Plan', '/kura//v/work/n/Plan', '/kura/%76/work/n/Plan', '/kura/n/Plan', '/kura/', '/kura/search?q=x',
    '/kura/api/links?path=a.md', '/kura/api/offline', '/kura/signin', '/kura/signout', '/kura/api/pair', '/kura/api/note/../../v/work/n/Plan', '/kura/%61pi/note?path=a.md'];
  const targets = routes(refused);
  refused.forEach((path, i) => assert.equal(targets[i], '', path));
});

test('the other routes are as they were', () => {
  assert.deepEqual(routes(['/', '/_shiori/search.js', '/searx/search?q=x', '/api/stats']), [
    null,
    null,
    'https://searx.example/search?q=x',
    'https://hister.example/api/stats',
  ]);
});

/**
 * Requests through the dev server to upstreams that record what they got:
 * for each path, the Cookie header the upstream saw and the Set-Cookie
 * headers that came back.
 */
function throughProxy(paths, cookie) {
  const script = `
import http.server, importlib.util, json, sys, threading, urllib.request
seen = {}
class Up(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        seen[self.path] = self.headers.get("Cookie")
        self.send_response(200)
        self.send_header("Set-Cookie", "machiya_session=renewed; Path=/; HttpOnly")
        self.send_header("Set-Cookie", "machiya_theme=night; Path=/")
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"{}")
    def log_message(self, *a): pass
up = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Up)
threading.Thread(target=up.serve_forever, daemon=True).start()
base = "http://127.0.0.1:%d/" % up.server_address[1]
import os
for name in ("HISTER_URL", "KURA_URL", "KONBINI_URL", "SEARXNG_URL", "SMALLWEB_URL"):
    os.environ[name] = base + name.split("_")[0].lower() + "/"
spec = importlib.util.spec_from_file_location("dev_server", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.Handler.log_message = lambda *a: None
dev = http.server.ThreadingHTTPServer(("127.0.0.1", 0), m.Handler)
threading.Thread(target=dev.serve_forever, daemon=True).start()
out = []
for path in json.loads(sys.argv[2]):
    request = urllib.request.Request("http://127.0.0.1:%d%s" % (dev.server_address[1], path), headers={"Cookie": sys.argv[3]})
    reply = urllib.request.urlopen(request, timeout=10)
    upstream = [p for p in seen if p.endswith(path.split("/")[-1])]
    out.append({"cookie": seen.get(upstream[-1]) if upstream else None, "setCookie": reply.headers.get_all("Set-Cookie")})
    seen.clear()
print(json.dumps(out))
`;
  return JSON.parse(execFileSync('python3', ['-c', script, server, JSON.stringify(paths), cookie], { encoding: 'utf8' }));
}

test("the Machiya session cookie reaches only the rooms, and their Set-Cookie comes back", () => {
  const cookie = 'machiya_session=abc.def; machiya_theme=night';
  const [kura, konbini, hister, searx, smallweb] = throughProxy(
    ['/kura/api/vaults', '/konbini/api/cards', '/api/stats', '/searx/search', '/smallweb/api/search'],
    cookie,
  );
  assert.equal(kura.cookie, cookie);
  assert.equal(konbini.cookie, cookie);
  for (const other of [hister, searx, smallweb]) assert.equal(other.cookie, 'machiya_theme=night');
  // A renewed session (and the house's settings) pass back unchanged.
  assert.deepEqual(kura.setCookie, ['machiya_session=renewed; Path=/; HttpOnly', 'machiya_theme=night; Path=/']);
});

test('a Cookie header holding only the session is dropped for the others', () => {
  const [hister] = throughProxy(['/api/stats'], 'machiya_session=abc.def');
  assert.equal(hister.cookie, null);
});

test("the Hister sign-in helper's cookie (machiya_sso) reaches only the rooms too", () => {
  const cookie = 'machiya_sso=opaque; machiya_session=abc.def; machiya_theme=night';
  const [kura, hister, searx] = throughProxy(['/kura/api/vaults', '/api/stats', '/searx/search'], cookie);
  assert.equal(kura.cookie, cookie);
  for (const other of [hister, searx]) assert.equal(other.cookie, 'machiya_theme=night');
});
