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
  const asked = ['/kura/api/search?q=x&limit=5', '/kura/api/recent?limit=5', '/kura/api/note?path=a.md', '/kura/api/vaults', '/kura/feed.xml?q=x'];
  assert.deepEqual(routes(asked), [
    'https://kura.example/api/search?q=x&limit=5',
    'https://kura.example/api/recent?limit=5',
    'https://kura.example/api/note?path=a.md',
    'https://kura.example/api/vaults',
    'https://kura.example/feed.xml?q=x',
  ]);
  // A work note's reader page (and every way Kura would reach it), the
  // default vault's, and Kura's other pages and API: a 404 here.
  const refused = ['/kura/v/work/n/Plan', '/kura//v/work/n/Plan', '/kura/%76/work/n/Plan', '/kura/n/Plan', '/kura/', '/kura/search?q=x',
    '/kura/api/links?path=a.md', '/kura/api/offline', '/kura/api/note/../../v/work/n/Plan', '/kura/%61pi/note?path=a.md'];
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
