// Tests for patches/ext/badge.js, the toolbar badge with the queue's count
// (Safari), over a fake toolbar button and storage.
// Run: node --test scripts/*.test.mjs

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const source = readFileSync(fileURLToPath(new URL('../patches/ext/badge.js', import.meta.url)), 'utf8');
const settle = () => new Promise((r) => setTimeout(r, 10));
const plain = (v) => JSON.parse(JSON.stringify(v));

// `refuseNull`: a browser that won't take null for "the toolbar's own"
// ('throw' at once, or 'reject' the promise).
function load(stored = {}, { refuseNull = null } = {}) {
  const calls = [];
  const changed = [];
  const answer = (d, value) => {
    if (refuseNull && d.tabId != null && value === null) {
      if (refuseNull === 'throw') throw new TypeError('null is not a string');
      return Promise.reject(new TypeError('null is not a string'));
    }
    return Promise.resolve();
  };
  const ctx = {
    chrome: {
      action: {
        setBadgeText: (d) => (calls.push(['text', JSON.parse(JSON.stringify(d))]), answer(d, d.text)),
        setBadgeBackgroundColor: (d) => (calls.push(['colour', d.color, d.tabId]), answer(d, d.color)),
        setBadgeTextColor: (d) => (calls.push(['textColour', d.color]), Promise.resolve()),
        setTitle: (d) => (calls.push(['title', d.title, d.tabId]), answer(d, d.title)),
      },
      storage: {
        local: { get: async (keys) => Object.fromEntries(keys.filter((k) => k in stored).map((k) => [k, stored[k]])) },
        onChanged: { addListener: (l) => changed.push(l) },
      },
    },
  };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(source, ctx);
  const queue = (n) => changed.forEach((l) => l({ shioriQueueIndex: { newValue: Array.from({ length: n }, (_, i) => ({ key: String(i) })) } }, 'local'));
  return { calls, queue, action: ctx.chrome.action, badge: ctx.ShioriBadge };
}
const texts = (calls) => calls.filter((c) => c[0] === 'text').map((c) => c[1]);
const titles = (calls) => calls.filter((c) => c[0] === 'title').map((c) => c[1]);

test('at start the badge shows what is already waiting, with a tooltip that says so', async () => {
  const { calls } = load({ shioriQueueIndex: [{}, {}, {}] });
  await settle();
  assert.deepEqual(texts(calls), [{ text: '3' }]);
  assert.deepEqual(titles(calls), ['Shiori · 3 pages waiting to send']);
  assert.ok(calls.some((c) => c[0] === 'colour'));
});

test('it follows the queue, and clears once nothing waits', async () => {
  const { calls, queue } = load();
  await settle();
  queue(1);
  queue(0);
  assert.deepEqual(texts(calls), [{ text: '' }, { text: '1' }, { text: '' }]);
  assert.deepEqual(titles(calls), ['Shiori', 'Shiori · 1 page waiting to send', 'Shiori']);
});

test("upstream clearing a tab's badge lets the count show there; its own marks stay", async () => {
  const { calls, action } = load();
  await settle();
  calls.length = 0;
  action.setBadgeText({ text: '', tabId: 4 });
  action.setBadgeText({ text: '✓', tabId: 4 });
  action.setBadgeText({ text: '!', tabId: 5 });
  assert.deepEqual(texts(calls), [{ text: null, tabId: 4 }, { text: '✓', tabId: 4 }, { text: '!', tabId: 5 }]);
});

test('a very long queue still fits the badge', async () => {
  const { calls, queue } = load();
  await settle();
  queue(1200);
  assert.deepEqual(texts(calls).at(-1), { text: '999+' });
});

test("a tab cleared after its own mark gets the toolbar's colour and tooltip back too", async () => {
  const { calls, badge } = load();
  await settle();
  calls.length = 0;
  await badge.clearTab(4);
  assert.deepEqual(plain(calls), [['text', { tabId: 4, text: null }], ['colour', null, 4], ['title', null, 4]]);
});

for (const refuseNull of ['throw', 'reject']) {
  test(`where null is refused (${refuseNull}), a cleared tab copies the count and keeps it in step`, async () => {
    const { calls, queue, badge } = load({ shioriQueueIndex: [{}, {}] }, { refuseNull });
    await settle();
    calls.length = 0;
    await badge.clearTab(4);
    const onTab = (kind) => calls.filter((c) => c[0] === kind && (c[0] === 'text' ? c[1].tabId : c[2]) === 4 && (c[0] === 'text' ? c[1].text : c[1]) !== null);
    assert.deepEqual(plain(onTab('text').map((c) => c[1])), [{ tabId: 4, text: '2' }]);
    assert.deepEqual(plain(onTab('colour').map((c) => c[1])), ['#e0af68']);
    assert.deepEqual(plain(onTab('title').map((c) => c[1])), ['Shiori · 2 pages waiting to send']);
    calls.length = 0;
    queue(1);
    await settle();
    assert.deepEqual(plain(texts(calls)), [{ text: '1' }, { tabId: 4, text: '1' }]);
    assert.ok(titles(calls).filter((t) => t === 'Shiori · 1 page waiting to send').length === 2);
  });
}

test("a tab given its own mark again isn't overwritten by the count", async () => {
  const { calls, queue, badge, action } = load({}, { refuseNull: 'reject' });
  await settle();
  await badge.clearTab(4);
  action.setBadgeText({ tabId: 4, text: '✓' });
  calls.length = 0;
  queue(3);
  await settle();
  assert.deepEqual(plain(texts(calls)), [{ text: '3' }]);
});
