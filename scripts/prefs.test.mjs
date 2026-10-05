// The preferences that follow the person (machiya docs/contracts/prefs.md):
// search-core's S.prefsSync and its mappings, on the cases HisterKit's
// PrefsSync runs too (prefs-sync-cases.json), and Shiori's keys and values
// against the contract's schema (prefs.schema.json, a copy of machiya's
// docs/contracts/prefs.schema.json).
// Run: node --test scripts/*.test.mjs

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const read = (rel) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');
const ctx = {};
ctx.globalThis = ctx;
vm.createContext(ctx);
vm.runInContext(read('../patches/shiori/search-core.js'), ctx);
const S = ctx.ShioriSearch;
const plain = (v) => JSON.parse(JSON.stringify(v));
const cases = JSON.parse(read('./prefs-sync-cases.json'));
const schema = JSON.parse(read('./prefs.schema.json'));

for (const c of cases.sync) {
  test(`sync: ${c.name}`, () => {
    assert.deepEqual(plain(S.prefsSync({ mine: c.mine, seen: c.seen, answer: c.answer })), { apply: c.apply, send: c.send });
  });
}

test('text size: Shiori\'s sizes and the house\'s five, both ways', () => {
  for (const c of cases.textSize) assert.equal(plain(S.accountValues({ textSize: c.local }, { steps: c.steps })).text_size, c.house, JSON.stringify(c));
  for (const c of cases.textSizeBack) assert.equal(S.localValues({ text_size: c.house }, { steps: c.steps }).textSize, c.local, JSON.stringify(c));
  // An account size that's just this device's rounding keeps its own.
  assert.equal(S.localValues({ text_size: 'small' }, { mine: 'medium' }).textSize, undefined);
});

test('pills: Shiori\'s list and the account\'s {order, hidden}, both ways', () => {
  for (const c of cases.pills) {
    assert.equal(S.pillsToAccount(c.local), c.account);
    assert.deepEqual(plain(S.pillsFromAccount(c.account)), c.local);
  }
});

test('only values the schema and Shiori know are valid', () => {
  for (const c of cases.valid) assert.equal(S.prefsValid(c.key, c.value), c.ok, `${c.key}=${c.value}`);
});

test("Shiori's keys and values are the contract's (prefs.schema.json)", () => {
  for (const [key, spec] of Object.entries(schema.shared)) {
    if (spec.values) assert.deepEqual(Array.from(S.PREFS_SHARED[key]), spec.values, key);
    if (key in S.PREFS_DEFAULTS) assert.equal(S.PREFS_DEFAULTS[key], spec.default, key);
  }
  const appKey = new RegExp('^' + schema.app_key.replace(/\\Z$/, '$'));
  for (const key of Object.values(S.prefsShioriKeys())) {
    assert.match(key, appKey, key);
    assert.ok(!schema.reserved.includes(key));
  }
  // No address, sign-in or AI setting ever follows the person.
  for (const key of Object.values(S.prefsShioriKeys())) assert.doesNotMatch(key, /url|token|obsidian|ai_|server|address/, key);
  // What a client sends from its own settings is always something the account takes.
  const sample = S.accountValues({ theme: 'night', palette: 'nord', textSize: 'xLarge', pills: ['all', '-web'], showInfobox: false, histerCount: 10, resultStyle: 'bar', smallWebOpen: 'direct' });
  for (const [key, value] of Object.entries(plain(sample))) assert.ok(S.prefsValid(key, value), `${key}=${value}`);
});

test('the account\'s values come back as Shiori\'s settings; a removal is the default', () => {
  assert.deepEqual(plain(S.localValues({ theme: 'night', 'shiori.show_infobox': 'off', 'shiori.hister_count': '10', 'shiori.result_style': 'bar' })),
    { theme: 'night', showInfobox: false, histerCount: 10, resultStyle: 'bar' });
  assert.deepEqual(plain(S.localValues({ palette: null, 'shiori.show_infobox': null }, { defaults: { showInfobox: true } })),
    { palette: 'tokyo-night', showInfobox: true });
});
