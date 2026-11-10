// Tests for the content script that opens sites through their front ends
// (patches/shiori/frontend-redirect.js). Run: node --test scripts/

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const read = (p) => readFileSync(fileURLToPath(new URL(p, import.meta.url)), 'utf8');
const FRONTENDS = 'redlib=https://redlib.example.ts.net/';

async function visit(href, { settings, navType = 'navigate', frontends = FRONTENDS } = {}) {
  const replaced = [];
  const sent = [];
  const stateReplaced = [];
  const sandbox = {
    URL, URLSearchParams, Promise,
    location: { href, hash: new URL(href).hash, replace: (u) => void replaced.push(u) },
    history: { state: null, replaceState: (s, t, u) => void stateReplaced.push(u) },
    performance: { getEntriesByType: () => [{ type: navType }] },
    chrome: {
      storage: { local: { get: async () => (settings === undefined ? {} : { shioriSettings: settings }) } },
      runtime: { sendMessage: (m, cb) => (sent.push(m), cb && cb()), lastError: undefined },
    },
  };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(read('../patches/shiori/search-core.js'), sandbox);
  vm.runInContext(read('../patches/shiori/frontend-redirect.js').replaceAll('__SHIORI_FRONTENDS__', frontends), sandbox);
  await new Promise((r) => setTimeout(r, 0));
  return { replaced, sent: JSON.parse(JSON.stringify(sent)), stateReplaced };
}

const POST = 'https://www.reddit.com/r/unix/comments/abc/x/';

test('off by default: the site loads as it is, and the settings are brought up to date', async () => {
  for (const settings of [undefined, {}, { frontendRedirect: false }]) {
    const v = await visit(POST, { settings });
    assert.deepEqual(v.replaced, []);
    assert.deepEqual(v.sent, [{ shiori: 'refresh-settings' }]);
  }
});

test('on: the page opens through the front end, replacing the entry', async () => {
  const v = await visit(POST, { settings: { frontendRedirect: true } });
  assert.deepEqual(v.replaced, ['https://redlib.example.ts.net/r/unix/comments/abc/x/']);
  assert.deepEqual((await visit(POST, { settings: { frontendRedirect: true }, navType: 'back_forward' })).replaced, []);
  assert.deepEqual((await visit('https://www.reddit.com/login', { settings: { frontendRedirect: true } })).replaced, []);
});

test('a visit marked to stay stays, and loses its mark', async () => {
  const v = await visit(POST + '#shiori-stay', { settings: { frontendRedirect: true } });
  assert.deepEqual(v.replaced, []);
  assert.deepEqual(v.stateReplaced, [POST]);
});

test('a build with no front ends does nothing', async () => {
  const v = await visit(POST, { settings: { frontendRedirect: true }, frontends: '__SHIORI_FRONTENDS__' });
  assert.deepEqual(v.replaced, []);
  assert.deepEqual(v.sent, []);
});
