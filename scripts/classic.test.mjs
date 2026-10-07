// Shiori for Classic Macintosh (classic/): the LAN bridge's tests (Python,
// fakes on loopback only).
// Run: node --test scripts/*.test.mjs

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import assert from 'node:assert/strict';

const root = fileURLToPath(new URL('..', import.meta.url));
const python = spawnSync('python3', ['--version']).error ? null : 'python3';

test('the classic bridge (classic/bridge) passes its tests', { skip: python ? false : 'no python3' }, () => {
  const r = spawnSync(python, ['-m', 'unittest', 'discover', '-s', 'classic/bridge', '-p', 'test_*.py'], {
    cwd: root, encoding: 'utf8', env: { ...process.env, PYTHONDONTWRITEBYTECODE: '1' },
  });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stderr, /\nOK/);
});
