// Tests for the popup's Open Elsewhere row (patches/shiori-popup.js). Run: node --test scripts/

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const read = (p) => readFileSync(fileURLToPath(new URL(p, import.meta.url)), 'utf8');

// A tiny DOM: enough for the row to be drawn and its buttons pressed.
function element(tag) {
  return {
    tag, children: [], listeners: {}, textContent: '', title: '', id: '', type: '',
    append(...kids) { this.children.push(...kids); },
    addEventListener(name, fn) { this.listeners[name] = fn; },
  };
}

async function popupFor(url, frontends) {
  const body = element('body');
  const updated = [];
  let closed = false;
  const sandbox = {
    URL, URLSearchParams, Promise, setTimeout, clearTimeout,
    chrome: {
      storage: { local: { get: async () => ({}) } },
      runtime: { sendMessage: () => {}, lastError: undefined },
      tabs: {
        query: async () => [{ id: 7, url }],
        update: async (id, props) => void updated.push({ id, url: props.url }),
      },
    },
    document: {
      readyState: 'complete', body, documentElement: { dataset: {} },
      querySelector: () => null, createElement: element,
    },
    MutationObserver: class { observe() {} disconnect() {} },
    window: { close: () => void (closed = true) },
    fetch: async () => new Response('{}'),
  };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(read('../patches/shiori/search-core.js'), sandbox);
  const popup = read('../patches/shiori-popup.js')
    .replaceAll('__SHIORI_FRONTENDS__', frontends);
  vm.runInContext(popup, sandbox);
  await new Promise((r) => setTimeout(r, 0));
  const section = body.children.find((c) => c.id === 'shiori-elsewhere');
  const buttons = section ? section.children[1].children : [];
  return {
    labels: buttons.map((b) => b.textContent),
    async press(label) {
      await buttons.find((b) => b.textContent === label).listeners.click();
      return { updated, closed };
    },
  };
}

const FRONTENDS = 'redlib=https://redlib.example.ts.net/,invidious=https://invidious.example.ts.net/';

test('Open Elsewhere offers the archives and the front ends for the page in the tab', async () => {
  const reddit = await popupFor('https://www.reddit.com/r/unix/comments/abc/x/', FRONTENDS);
  assert.deepEqual(reddit.labels, ['Archive.org', 'Archive.is', 'Redlib']);
  const { updated, closed } = await reddit.press('Redlib');
  assert.deepEqual(updated, [{ id: 7, url: 'https://redlib.example.ts.net/r/unix/comments/abc/x/' }]);
  assert.ok(closed);

  const plain = await popupFor('https://example.com/a', FRONTENDS);
  assert.deepEqual(plain.labels, ['Archive.org', 'Archive.is']);
  assert.equal((await plain.press('Archive.is')).updated[0].url, 'https://archive.is/newest/https://example.com/a');

  // No row for a page that isn't on the web, or with no build settings at all.
  assert.deepEqual((await popupFor('about:blank', FRONTENDS)).labels, []);
  assert.deepEqual((await popupFor('https://www.reddit.com/r/unix/', '__SHIORI_FRONTENDS__')).labels,
    ['Archive.org', 'Archive.is']);
});

test('from a front end, the way back to the original site is marked to stay there', async () => {
  const redlib = await popupFor('https://redlib.example.ts.net/r/unix/', FRONTENDS);
  assert.deepEqual(redlib.labels, ['Reddit', 'Archive.org', 'Archive.is']);
  assert.equal((await redlib.press('Reddit')).updated[0].url, 'https://www.reddit.com/r/unix/#shiori-stay');
  // A path Redlib can't show is never redirected, so it needs no mark.
  const media = await popupFor('https://redlib.example.ts.net/settings', FRONTENDS);
  assert.equal((await media.press('Reddit')).updated[0].url, 'https://www.reddit.com/settings');
});
