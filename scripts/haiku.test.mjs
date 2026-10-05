// Shiori for Haiku (haiku/): its portable C++ core's vectors are
// search-core.js's own answers (haiku/tests/gen-vectors.mjs), so they must be
// regenerated whenever search-core changes; and, where a C++ compiler is at
// hand, the core builds and passes (the Be API UI builds only on Haiku).
// Run: node --test scripts/*.test.mjs

import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import assert from 'node:assert/strict';

const root = fileURLToPath(new URL('..', import.meta.url));

test("the Haiku core's vectors are search-core.js's current answers (regenerate with haiku/tests/gen-vectors.mjs)", () => {
  const fresh = execFileSync('node', ['haiku/tests/gen-vectors.mjs', 'patches/shiori/search-core.js'], { cwd: root, encoding: 'utf8' });
  assert.equal(fresh, readFileSync(new URL('../haiku/tests/vectors.inc', import.meta.url), 'utf8'));
});

const compiler = ['c++', 'clang++', 'g++'].find((cc) => !spawnSync(cc, ['--version']).error);
test('the Haiku core builds and passes its tests', { skip: compiler ? false : 'no C++ compiler here' }, () => {
  const r = spawnSync('make', ['-f', 'Makefile.test', 'test', `CXX=${compiler}`], { cwd: `${root}haiku`, encoding: 'utf8' });
  spawnSync('make', ['-f', 'Makefile.test', 'clean'], { cwd: `${root}haiku` });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stdout, /\d+ passed, 0 failed/);
});
