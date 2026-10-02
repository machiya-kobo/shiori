// Tests for patches/ext/badge.js, the toolbar badge with the queue's count
// (Firefox), over a fake toolbar button and storage.
// Run: node --test scripts/*.test.mjs

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const source = readFileSync(fileURLToPath(new URL('../patches/ext/badge.js', import.meta.url)), 'utf8');
const settle = () => new Promise((r) => setTimeout(r, 10));

function load(stored = {}) {
  const calls = [];
  const changed = [];
  const ctx = {
    chrome: {
      action: {
        setBadgeText: (d) => (calls.push(['text', JSON.parse(JSON.stringify(d))]), Promise.resolve()),
        setBadgeBackgroundColor: (d) => (calls.push(['colour', d.color]), Promise.resolve()),
        setBadgeTextColor: (d) => (calls.push(['textColour', d.color]), Promise.resolve()),
        setTitle: (d) => (calls.push(['title', d.title]), Promise.resolve()),
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
  return { calls, queue, action: ctx.chrome.action };
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
