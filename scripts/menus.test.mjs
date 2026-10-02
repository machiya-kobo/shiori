// Tests for patches/ext/menus.js, the right-click menu (Firefox), loaded as
// the Firefox background has it (search-core before; resultsBase from the
// core stubbed). A fake Hister, web and gateway.
// Run: node --test scripts/*.test.mjs

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const read = (rel) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');
const source = read('../patches/shiori/search-core.js') + '\n' + read('../patches/ext/menus.js');
const BASE = 'https://hister.example/';
const GATEWAY = 'https://smallweb.example/';
const plain = (v) => JSON.parse(JSON.stringify(v));
const HTML = '<!doctype html><title>Paper &amp; Lanterns</title><p>Kyoto</p>';

const html = (body = HTML, url) => {
  const r = new Response(body, { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
  if (url) Object.defineProperty(r, 'url', { value: url });
  return r;
};

// `web(url, init)` answers everything not Hister's search; `held` is what Hister holds.
function load({ held = [], web = () => html(), settings = {}, stored } = {}) {
  const fetched = [];
  const added = [];
  const created = [];
  const clicked = [];
  const commands = [];
  const badges = [];
  const ctx = {
    chrome: {
      storage: { local: { get: async (keys) => Object.fromEntries(keys.map((k) => [k, (stored || { histerURL: BASE, shioriSettings: settings })[k]])) } },
      commands: { onCommand: { addListener: () => {} } },
      menus: {
        removeAll: async () => {},
        create: (item, done) => (created.push(item), done && done()),
        onClicked: { addListener: (l) => clicked.push(l) },
      },
      tabs: { create: async (props) => created.push({ tab: props }) },
      action: {
        setBadgeText: (d) => (badges.push(d), Promise.resolve()),
        setBadgeBackgroundColor: () => Promise.resolve(),
        setBadgeTextColor: () => Promise.resolve(),
        setTitle: (d) => (badges.push(d), Promise.resolve()),
      },
      runtime: {},
    },
    resultsBase: async () => 'moz-extension://x/search.html',
    fetch: async (input, init = {}) => {
      const url = typeof input === 'string' ? input : input.url;
      fetched.push({ url, init });
      if (url.startsWith(BASE + 'search?')) {
        const text = JSON.parse(new URL(url).searchParams.get('query')).text;
        return new Response(JSON.stringify({ documents: held.filter((u) => text.includes(u)).map((u) => ({ url: u })) }));
      }
      if (url === BASE + 'api/add') {
        added.push(JSON.parse(init.body));
        return web(url, init);
      }
      return web(url, init);
    },
    Response, Headers, URL, URLSearchParams, JSON, Promise, Set, Map, setTimeout, clearTimeout, console,
  };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  // Upstream's command listener, added after the menu's code runs (as upstream's is).
  vm.runInContext(source + '\nchrome.commands.onCommand.addListener((c, tab) => globalThis.__ran.push([c, tab && tab.id]));', Object.assign(ctx, { __ran: commands }));
  // A click's work runs on after the listener returns: give it a moment.
  const click = async (info, tab = { id: 4, index: 2 }) => {
    clicked.forEach((l) => l(info, tab));
    await new Promise((r) => setTimeout(r, 20));
  };
  return { menus: ctx.ShioriMenus, fetched, added, created, commands, badges, click };
}
const noWait = { wait: async () => {} };

test('a fresh page is downloaded without cookies and saved, with its title and where it came from', async () => {
  const t = load({ web: (url) => (url === BASE + 'api/add' ? new Response('{}', { status: 201 }) : html()) });
  const result = plain(await t.menus.saveLink('https://a.example/lanterns'));
  assert.deepEqual(result, { outcome: 'saved' });
  const download = t.fetched.find((f) => f.url === 'https://a.example/lanterns');
  assert.equal(download.init.credentials, 'omit');
  assert.deepEqual(plain(t.added), [{ url: 'https://a.example/lanterns', title: 'Paper & Lanterns', html: HTML, metadata: { via: 'context-menu' } }]);
});

test('skip rules hold: no ignore_skip_rules, and a 406 says skipped', async () => {
  const t = load({ web: (url) => (url === BASE + 'api/add' ? new Response('{}', { status: 406 }) : html()) });
  assert.deepEqual(plain(await t.menus.saveLink('https://bank.example/')), { outcome: 'skipped' });
  assert.equal('ignore_skip_rules' in t.added[0].metadata, false);
});

test('never a page Hister holds: looked up first, and again after a redirect', async () => {
  const before = load({ held: ['https://a.example/held'] });
  assert.deepEqual(plain(await before.menus.saveLink('https://a.example/held')), { outcome: 'held' });
  assert.equal(before.fetched.some((f) => f.url === 'https://a.example/held'), false, 'not even downloaded');

  const after = load({ held: ['https://a.example/new-home'], web: () => html(HTML, 'https://a.example/new-home') });
  assert.deepEqual(plain(await after.menus.saveLink('https://a.example/old')), { outcome: 'held' });
  assert.equal(after.added.length, 0);
});

test('never a file, never a page that is not HTML', async () => {
  const t = load({ web: () => new Response('%PDF', { headers: { 'Content-Type': 'application/pdf' } }) });
  assert.equal((await t.menus.saveLink('https://a.example/release.zip')).outcome, 'failed');
  assert.equal(t.fetched.length, 0);
  assert.match((await t.menus.saveLink('https://a.example/report')).reason, /isn't a web page/);
  assert.equal(t.added.length, 0);
});

test('http:// is tried as https:// first, and kept as http:// when that fails', async () => {
  const t = load({ web: (url) => (url.startsWith('https://plain.example') ? Promise.reject(new TypeError('no TLS')) : url === BASE + 'api/add' ? new Response('{}', { status: 201 }) : html()) });
  await t.menus.saveLink('http://plain.example/page');
  const tried = t.fetched.filter((f) => !f.url.startsWith(BASE)).map((f) => f.url);
  assert.deepEqual(tried, ['https://plain.example/page', 'http://plain.example/page']);
  assert.equal(t.added[0].url, 'http://plain.example/page');
});

test('queued while Hister is out of reach (the core answers 201 with X-Shiori-Queued)', async () => {
  const t = load({ web: (url) => (url === BASE + 'api/add' ? new Response('{}', { status: 201, headers: { 'X-Shiori-Queued': '1' } }) : html()) });
  assert.deepEqual(plain(await t.menus.saveLink('https://a.example/')), { outcome: 'queued' });
});

test('gemini:// and gopher:// go through the small-web gateway, which may ask to wait', async () => {
  let asked = 0;
  const t = load({
    settings: { smallwebURL: GATEWAY },
    web: (url, init) => (url === GATEWAY + 'api/save' ? new Response('{}', { status: ++asked < 2 ? 429 : 202 }) : html()),
  });
  assert.deepEqual(plain(await t.menus.saveLink('gemini://capsule.example/lanterns.gmi', noWait)), { outcome: 'saved' });
  const posts = t.fetched.filter((f) => f.url === GATEWAY + 'api/save');
  assert.equal(posts.length, 2);
  assert.deepEqual(JSON.parse(posts[0].init.body), { url: 'gemini://capsule.example/lanterns.gmi' });
  assert.equal(t.added.length, 0, 'never through api/add');
  const none = load();
  assert.match((await none.menus.saveLink('gopher://hole.example/1/', noWait)).reason, /small-web gateway/);
});

test('the menu has its items, and each does its part', async () => {
  const t = load({ web: (url) => (url === BASE + 'api/add' ? new Response('{}', { status: 201 }) : html()) });
  await new Promise((r) => setTimeout(r, 5));
  assert.deepEqual(t.created.filter((c) => c.id).map((c) => c.id), ['shiori-search', 'shiori-save-link', 'shiori-save-page', 'shiori-never-page', 'shiori-never-site']);
  await t.click({ menuItemId: 'shiori-search', selectionText: '  paper\n lanterns ' });
  assert.deepEqual(plain(t.created.find((c) => c.tab).tab), { url: 'moz-extension://x/search.html?q=paper%20lanterns', index: 3, openerTabId: 4 });
  await t.click({ menuItemId: 'shiori-save-page' });
  await t.click({ menuItemId: 'shiori-never-site' });
  assert.deepEqual(plain(t.commands), [['index-current-page', 4], ['disable-indexing-current-domain', 4]]);
  await t.click({ menuItemId: 'shiori-save-link', linkUrl: 'https://a.example/' });
  assert.deepEqual(plain(t.badges.slice(0, 2)), [{ tabId: 4, text: '✓' }, { tabId: 4, title: 'Shiori · Saved to Hister' }]);
});
