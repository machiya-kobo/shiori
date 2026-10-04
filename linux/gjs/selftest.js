// Runs linux/src and search-core.js inside GJS, as the app will
// (docs/linux.md): the Node tests check their logic, this checks
// that GJS itself runs them (its URL shim, TextEncoder, modules).
//
//   gjs -m linux/gjs/selftest.js      (exit 0 when every check passes)

import System from 'system';
import { installURL } from '../src/url.js';
import { newPage, addRequest, titleIn } from '../src/page.js';
import * as outbox from '../src/outbox.js';
import { parseArgs } from '../src/cli.js';
import { providerResults } from '../src/provider.js';
import { histerHeaders } from '../src/hister.js';

installURL(globalThis);
// search-core.js is a script that sets globalThis.ShioriSearch; imported
// for that effect once URL exists.
await import('../../patches/shiori/search-core.js');
const S = globalThis.ShioriSearch;

let failed = 0;
function check(name, got, want) {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) failed++;
  print(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok ? '' : `: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`}`);
}

check('URL is the shim', typeof URL === 'function' && new URL('https://www.Example.com:443/a?b=1').host, 'www.example.com');
check('normalizeURL', S.normalizeURL('https://www.Example.com/a/b/?utm_source=x&q=1'), 'example.com/a/b?q=1');
check('histerText', S.histerText('machi'), 'machi* -label:vault -metadata.source:vault -type:local');
const tokenConfig = { server: 'https://h.example/', smallweb: 'https://sw.example/', histerToken: 'ABCDEFGHJKLMNPQRSTUVWXYZ23' };
check('histerHeaders (server)', histerHeaders(tokenConfig, 'https://h.example/search', S), { 'X-Access-Token': 'ABCDEFGHJKLMNPQRSTUVWXYZ23' });
check('histerHeaders (gateway)', histerHeaders(tokenConfig, 'https://sw.example/api/save', S), {});
check('histerHeaders (none)', histerHeaders({ server: 'https://h.example/' }, 'https://h.example/search', S), {});
check('kuraURL', S.kuraURL('https://kura.example/', 'hister', { limit: 5 }), 'https://kura.example/api/search?limit=5&offset=0&q=hister*&sort=relevance');
check('feedURL', S.feedURL('https://s.example/', { query: 'rust', title: 'Rust' }), 'https://s.example/shiori/feed?q=rust&exclude_label=vault&title=Rust');
check('smallwebSearchURL', S.smallwebSearchURL('https://sw.example/', 'gemini capsule'), 'https://sw.example/api/search?q=gemini+capsule&page=1');
check('titleIn', titleIn('<title>Caf&eacute; &amp; 町家</title>'), 'Caf&eacute; & 町家');
check('addRequest', addRequest('https://h.example', newPage({ url: 'https://a.example/', title: 'A' })).headers.Origin, 'hister://');
check('parseArgs', parseArgs(['save', 'https://a.example/', 'books']), { command: 'save', url: 'https://a.example/', label: 'books' });
check('providerResults', providerResults({ documents: [{ url: 'https://a.example/', title: 'A' }] }, null).map((r) => r.id), ['page:https://a.example/']);

const files = new Map();
const store = {
  list: async () => [...files.keys()],
  read: async (n) => files.get(n) ?? null,
  write: async (n, t) => void files.set(n, t),
  remove: async (n) => void files.delete(n),
};
await outbox.enqueue(store, { url: 'https://a.example/' }, { now: 100, id: 'a' });
const drained = await outbox.drain(store, async () => 201, { now: 200 });
check('outbox drain', drained, { sent: 1, dropped: 0, stopped: false });

print(failed ? `${failed} failed` : 'all passed');
System.exit(failed ? 1 : 0);
