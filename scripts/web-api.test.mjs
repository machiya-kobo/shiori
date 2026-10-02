// Tests for web/app/api.js, the web app's server calls, against a fake
// server: which vaults are shared comes from Kura, and another vault's note
// reaches Hister only while Kura, asked afresh, still shares it. Also how
// the search page (patches/shiori/search.js) and the web app (web/app/app.js)
// are wired to it: those need a browser, so their source is checked.
// Run: node --test scripts/*.test.mjs

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const read = (rel) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');

// search-core in its own context, as the page has it on globalThis.
const core = { URL, URLSearchParams };
core.globalThis = core;
vm.createContext(core);
vm.runInContext(read('../patches/shiori/search-core.js'), core);
globalThis.ShioriSearch = core.ShioriSearch;
const S = core.ShioriSearch;

// The fake server: `vaults` is Kura's answer (null: Kura is down); every
// request is recorded.
const server = { vaults: null, calls: [] };
globalThis.fetch = async (url, init = {}) => {
  server.calls.push({ url, init });
  if (url === '/kura/api/vaults') {
    if (!server.vaults) throw new TypeError('Load failed');
    return new Response(JSON.stringify({ vaults: server.vaults }));
  }
  if (url === '/api/delete') return new Response(JSON.stringify({ matched: 1 }));
  return new Response('{}');
};
const api = await import('../web/app/api.js');

const WORK = 'https://kura.example/v/work/n/Plan';
const vaults = (workPrivate) => [
  { name: 'personal', default: true, private: false },
  { name: 'work', default: false, private: workPrivate },
];
const sentToHister = () => server.calls.filter((c) => /^\/api\/(history|label|delete)$/.test(c.url));
function reset(list) {
  server.vaults = list;
  server.calls = [];
}

test("the web app's vaults come from Kura and say which are shared; a failure shares none", async () => {
  reset(vaults(false));
  assert.equal((await api.kuraVaults()).length, 2);
  assert.equal(S.isPrivateNote(WORK), false);
  reset(null);
  assert.equal((await api.kuraVaults()).length, 0);
  assert.equal(S.isPrivateNote(WORK), true);
});

test('a vault made private after the app read it: nothing about its note reaches Hister', async () => {
  reset(vaults(false));
  await api.kuraVaults();
  assert.equal(S.isPrivateNote(WORK), false, 'shared, as cached');
  reset(vaults(true));
  await api.recordOpened(WORK, 'Plan', 'plan');
  await assert.rejects(api.setLabel(WORK, 'x'));
  await assert.rejects(api.deletePage(WORK));
  await assert.rejects(api.forgetOpened(WORK, 'plan'));
  assert.deepEqual(sentToHister(), []);
  assert.equal(server.calls.filter((c) => c.url === '/kura/api/vaults').length, 4, 'Kura asked before each');
});

test("Kura out of reach: another vault's note is private; while Kura shares it, it goes", async () => {
  reset(vaults(false));
  await api.kuraVaults();
  reset(null);
  await api.recordOpened(WORK, 'Plan', 'plan');
  assert.deepEqual(sentToHister(), []);
  // Shared again: the label asks afresh (and keeps the answer); an open,
  // already refused by the copy, then goes too.
  reset(vaults(false));
  await api.setLabel(WORK, 'x');
  await api.recordOpened(WORK, 'Plan', 'plan');
  assert.deepEqual(sentToHister().map((c) => c.url), ['/api/label', '/api/history']);
});

test("the default vault's notes and pages never wait on Kura", async () => {
  reset(null);
  await api.recordOpened('https://kura.example/n/Plan', 'Plan', 'plan');
  await api.setLabel('https://example.com/', 'x');
  assert.equal(server.calls.some((c) => c.url === '/kura/api/vaults'), false);
  assert.equal(sentToHister().length, 2);
});

test('the search page and the web app read the vaults through S.loadVaults, and ask afresh before Hister', () => {
  const page = read('../patches/shiori/search.js');
  assert.match(page, /const vaultsReady = \(\) => S\.loadVaults\(readVaultsNow\)/);
  assert.match(page, /S\.isPrivateNoteNow\(url, readVaultsNow\)\.then/);
  assert.doesNotMatch(page, /S\.useVaults\(/, 'only through S.loadVaults');
  const app = read('../web/app/app.js');
  assert.match(app, /const loadVaults = \(\) => \{[\s\S]*?api\.kuraVaults\(\)/);
  assert.match(app, /Promise\.all\(\[[^\]]*loadVaults\(\)/, 'read at start');
  assert.doesNotMatch(app, /S\.useVaults\(/, 'only through api.kuraVaults');
});
