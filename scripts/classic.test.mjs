// Shiori for Classic Macintosh (classic/): the LAN bridge's tests (Python,
// fakes on loopback only) and the portable core's (C89, built with the host's cc).
// Run: node --test scripts/*.test.mjs

import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import assert from 'node:assert/strict';

const root = fileURLToPath(new URL('..', import.meta.url));
test("the classic core's vectors are search-core.js's current answers (haiku/tests/gen-vectors.mjs --c)", () => {
  const fresh = execFileSync('node', ['haiku/tests/gen-vectors.mjs', '--c', 'patches/shiori/search-core.js'], { cwd: root, encoding: 'utf8' });
  assert.equal(fresh, readFileSync(new URL('../classic/tests/vectors.h', import.meta.url), 'utf8'));
});

const python = spawnSync('python3', ['--version']).error ? null : 'python3';

test('the classic bridge (classic/bridge) passes its tests', { skip: python ? false : 'no python3' }, () => {
  const r = spawnSync(python, ['-m', 'unittest', 'discover', '-s', 'classic/bridge', '-p', 'test_*.py'], {
    cwd: root, encoding: 'utf8', env: { ...process.env, PYTHONDONTWRITEBYTECODE: '1' },
  });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stderr, /\nOK/);
});

const cc = ['cc', 'clang', 'gcc'].find((c) => !spawnSync(c, ['--version']).error);
test('the classic core builds as C89 and passes its tests', { skip: cc ? false : 'no C compiler here' }, () => {
  const r = spawnSync('make', ['-C', 'classic/tests', 'test', `CC=${cc}`], { cwd: root, encoding: 'utf8' });
  spawnSync('make', ['-C', 'classic/tests', 'clean'], { cwd: root });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stdout, /\d+ passed, 0 failed/);
});
