// Media (docs/media.md): search-core's twin of HisterKit's Media.swift, on
// scripts/media-cases.json, plus the search and the browse run against a fake.
// Run: node --test scripts/*.test.mjs

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const source = readFileSync(fileURLToPath(new URL('../patches/shiori/search-core.js', import.meta.url)), 'utf8');
const ctx = { URL, URLSearchParams };
ctx.globalThis = ctx;
vm.createContext(ctx);
vm.runInContext(source, ctx);
const S = ctx.ShioriSearch;
const cases = JSON.parse(readFileSync(fileURLToPath(new URL('media-cases.json', import.meta.url)), 'utf8'));
// Objects from the page's context have its prototypes: compare as JSON.
const plain = (v) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));

test('each read request has its address', () => {
  assert.ok(cases.urls.length > 20);
  for (const c of cases.urls) assert.equal(S.mediaRequestURL(c.service, c.what, c.base, c.args), c.want, `${c.service}.${c.what} ${JSON.stringify(c.args)}`);
});

test('replies are read, and what can’t be read is left out', () => {
  for (const c of cases.parse) assert.deepEqual(plain(S.mediaParse(c.service, c.what, c.reply, c.ctx)), c.want, `${c.service}.${c.what}`);
});

test('one card per item, played and rated from the right service', () => {
  for (const c of cases.merge) assert.deepEqual(plain(S.mediaMerge(c.lists, c.opts)), c.want, JSON.stringify(c.opts));
});

test('the filters', () => {
  for (const c of cases.filter.cases) assert.deepEqual(plain(S.mediaFilter(cases.filter.items, c.filter).map((x) => x.key)), c.want, JSON.stringify(c.filter));
});

test('what a card says', () => {
  for (const c of cases.lines) assert.equal(S.mediaPlayedLine(c.item, c.offset), c.played, `${c.item.title} ${c.offset}`);
  for (const c of cases.text) {
    assert.equal(S.mediaSubtitle(c.item), c.subtitle, c.item.title);
    assert.equal(S.mediaOutsideLine(c.item), c.outside, c.item.title);
    assert.deepEqual(plain(S.mediaPlaces(c.item)), c.places, c.item.title);
  }
  for (const c of cases.stars) assert.equal(S.mediaStars(c.rating), c.want, String(c.rating));
});

test('matching: titles reduced, ids first', () => {
  for (const c of cases.norm) assert.equal(S.mediaNorm(c.in), c.want, c.in);
  for (const c of cases.same) assert.equal(S.mediaSame(c.a, c.b), c.want, JSON.stringify([c.a, c.b]));
});

test('images only from the service itself or TMDB', () => {
  for (const c of cases.images) assert.equal(S.mediaImageURL(c.raw, c.ctx), c.want, c.raw);
});

test('the hosted pages’ services come from the build, each through this host', () => {
  assert.deepEqual(plain(S.mediaServicesFromBuild('__SHIORI_MEDIA__', '/')), {});
  assert.deepEqual(plain(S.mediaServicesFromBuild('', '/')), {});
  assert.deepEqual(plain(S.mediaServicesFromBuild('koito=https://koito.example.ts.net, plex=https://plex.example.ts.net/,evil=https://x.example/,movary=javascript:alert(1)', '/')), {
    koito: { api: '/koito/', link: 'https://koito.example.ts.net/' },
    plex: { api: '/plex/', link: 'https://plex.example.ts.net/' },
  });
  assert.equal(S.mediaConfigured({}), false);
  assert.equal(S.mediaConfigured({ koito: { api: '/koito/' } }), true);
  assert.equal(S.mediaFailure('plex', { status: 401 }), "Plex refused Shiori's token");
  assert.equal(S.mediaFailure('koito', new Error('x')), "Koito didn't answer");
});

// A fake of the four services, from the cases' replies: answers by path, records every request.
function fake(replies, broken = {}) {
  const asked = [];
  const r = (name) => cases.parse.find((c) => c.service + '.' + c.what === name).reply;
  const get = async (service, url) => {
    asked.push(url);
    if (broken[service]) {
      const e = new Error('down');
      e.status = broken[service];
      throw e;
    }
    const path = new URL(url, 'https://here.example/').pathname;
    const answer = [
      [/koito\/apis\/web\/v1\/search$/, () => r('koito.search')],
      [/koito\/apis\/web\/v1\/(track|album|artist)\/\d+$/, () => r('koito.item')],
      [/koito\/apis\/web\/v1\/listens$/, () => (url.includes('_id=') ? r('koito.last') : r('koito.listens'))],
      [/koito\/apis\/web\/v1\/now-playing$/, () => r('koito.nowPlaying')],
      [/koito\/apis\/web\/v1\/top\/\w+$/, () => r('koito.topArtists')],
      [/movary\/api\/authentication\/token$/, () => r('movary.me')],
      [/movary\/api\/users\/reader\/played\/movies$/, () => r('movary.played')],
      [/movary\/api\/users\/reader\/history\/movies$/, () => r('movary.history')],
      [/movary\/api\/users\/reader\/watchlist\/movies$/, () => r('movary.watchlist')],
      [/jellyfin\/Users\/Me$/, () => r('jellyfin.me')],
      [/jellyfin\/Users\/[0-9a-f]{32}\/Items$/, () => r('jellyfin.search')],
      [/jellyfin\/Users\/[0-9a-f]{32}\/Items\/Latest$/, () => r('jellyfin.latest')],
      [/plex\/identity$/, () => r('plex.identity')],
      [/plex\/hubs\/search$/, () => r('plex.search')],
      [/plex\/library\/recentlyAdded$/, () => r('plex.recent')],
    ].find(([re]) => re.test(path));
    if (!answer) throw Object.assign(new Error('unknown ' + path), { status: 404 });
    return replies && replies[path] ? replies[path] : answer[1]();
  };
  return { get, asked };
}

const hosted = () => S.mediaServicesFromBuild('jellyfin=https://jellyfin.example.ts.net/,plex=https://plex.example.ts.net:32400/,koito=https://koito.example.ts.net/,movary=https://movary.example.ts.net/', '/');

test('a search asks every service once, counts Koito’s matches, and merges', async () => {
  const services = hosted();
  const { get, asked } = fake();
  const res = await S.mediaSearch(services, 'night', get);
  assert.deepEqual(plain(res.failures), []);
  assert.equal(services.movary.user, 'reader');
  assert.equal(services.jellyfin.serverId, 'b2'.repeat(16));
  const top = res.items[0];
  assert.equal(top.title, 'Night Drive');
  assert.equal(top.plays, 12);
  assert.equal(top.playedFrom, 'koito');
  assert.equal(top.last, 1748820600);
  assert.ok(top.image.startsWith('/jellyfin/Items/'));
  // Only reads, never a write endpoint.
  for (const url of asked) assert.doesNotMatch(url, /submit-listens|merge|aliases|apikeys/);
  assert.equal(asked.filter((u) => u.includes('/authentication/token')).length, 1);
  // Facts are kept: a second search doesn't ask them again.
  const before = asked.length;
  await S.mediaSearch(services, 'night', get);
  assert.equal(asked.slice(before).filter((u) => /Users\/Me|identity|authentication/.test(u)).length, 0);
});

test('one service failing never fails the search', async () => {
  const services = hosted();
  const { get } = fake({}, { plex: 401, movary: 503 });
  const res = await S.mediaSearch(services, 'night', get);
  assert.deepEqual(plain(res.failures).sort(), ["Movary didn't answer", "Plex refused Shiori's token"]);
  assert.ok(res.items.some((it) => it.title === 'Night Drive'));
});

test('nothing set up, or no words: nothing asked', async () => {
  const { get, asked } = fake();
  assert.deepEqual(plain(await S.mediaSearch({}, 'night', get)), { items: [], failures: [] });
  assert.deepEqual(plain(await S.mediaSearch(hosted(), '   ', get)), { items: [], failures: [] });
  assert.equal(asked.length, 0);
});

test('the Media tab before a search', async () => {
  const services = hosted();
  const { get, asked } = fake();
  const res = await S.mediaBrowse(services, get, { period: 'year' });
  assert.deepEqual(plain(res.failures), []);
  assert.equal(res.period, 'year');
  assert.equal(res.sections.nowPlaying[0].title, 'Night Drive');
  assert.equal(res.sections.listens.length, 1);
  assert.equal(res.sections.watched[0].when, 1791720000);
  assert.equal(res.sections.artists[0].plays, 55);
  assert.equal(res.sections.watchlist[0].title, 'Next Film');
  assert.deepEqual(plain(res.sections.added.map((x) => x.title)), ['New Film', 'Example Film']);
  assert.ok(asked.some((u) => u.includes('/top/albums?period=year')));
  const down = await S.mediaBrowse(hosted(), fake({}, { koito: 500 }).get);
  assert.deepEqual(plain(down.failures), ["Koito didn't answer"]);
  assert.deepEqual(plain(down.sections.nowPlaying), []);
});
