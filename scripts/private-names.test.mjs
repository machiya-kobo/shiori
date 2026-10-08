// No private names in the repository: tests/test_private_names.py (machiya's,
// kept identical), which reads its list from outside the repository and skips
// the scan without it. Run: node --test scripts/*.test.mjs

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import assert from 'node:assert/strict';

const root = fileURLToPath(new URL('..', import.meta.url));
const python = spawnSync('python3', ['--version']).error ? null : 'python3';

test('no private names in tracked files (tests/test_private_names.py)', { skip: python ? false : 'no python3' }, () => {
  const r = spawnSync(python, ['-m', 'unittest', 'tests.test_private_names'], {
    cwd: root, encoding: 'utf8', env: { ...process.env, PYTHONDONTWRITEBYTECODE: '1' },
  });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stderr, /\nOK/);
});
