// The shiori-web image's start-up step (docker/shiori-web/configure.py): it checks the settings, stamps them into a
// copy of the pages built once with placeholders, and writes nginx's routes. Run here with no container engine; the
// container itself is tools/container-test. Run: node --test scripts/*.test.mjs

import { spawn, spawnSync, execFileSync } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtempSync, readFileSync, rmSync, existsSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import assert from 'node:assert/strict';

const repo = fileURLToPath(new URL('..', import.meta.url));
const python = spawnSync('python3', ['--version']).error ? null : 'python3';
const skip = python ? false : 'no python3';

// The pages as the Dockerfile builds them: every setting left a placeholder, the status link left for start-up.
const dist = mkdtempSync(join(tmpdir(), 'shiori-web-dist-'));
const env0 = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith('SHIORI_')));
if (python) {
  execFileSync('bash', ['scripts/build-web.sh', join(dist, 'search'), 'http://shiori-web.invalid/', '@runtime'], { cwd: repo, env: { ...env0, SHIORI_BUILD_ID: 'abc1234' }, stdio: 'pipe' });
  execFileSync('bash', ['scripts/build-pwa.sh', join(dist, 'app'), '@runtime'], { cwd: repo, env: { ...env0, SHIORI_BUILD_ID: 'abc1234' }, stdio: 'pipe' });
}
test.after(() => rmSync(dist, { recursive: true, force: true }));

const BASE = { SHIORI_HISTER_URL: 'http://hister:4433', SHIORI_SEARXNG_URL: 'http://searxng:8080' };

function run(env, extra = []) {
  const out = mkdtempSync(join(tmpdir(), 'shiori-web-out-'));
  const r = spawnSync(python, ['docker/shiori-web/configure.py', '--dist', dist, '--out', out, '--scripts', 'scripts', '--resolver', '127.0.0.11', '--no-probe', ...extra],
    { cwd: repo, env: { ...env0, ...env }, encoding: 'utf8' });
  const read = (rel) => readFileSync(join(out, rel), 'utf8');
  return { r, out, read, sites: () => read('sites.conf'), cleanup: () => rmSync(out, { recursive: true, force: true }) };
}

test('Hister and SearXNG are required, and the message says how to set them', { skip }, () => {
  for (const env of [{}, { SHIORI_HISTER_URL: 'http://hister:4433' }, { SHIORI_SEARXNG_URL: 'http://searxng:8080' }]) {
    const x = run(env);
    assert.equal(x.r.status, 2);
    assert.match(x.r.stderr, /shiori-web needs/);
    assert.match(x.r.stderr, /SHIORI_HISTER_URL.*where Hister is/s);
    assert.match(x.r.stderr, /SHIORI_SEARXNG_URL.*where SearXNG is/s);
    assert.equal(existsSync(join(x.out, 'sites.conf')), false);
    x.cleanup();
  }
});

test('settings that could break the config or a page are refused, by name', { skip }, () => {
  const bad = [
    ['SHIORI_HISTER_URL', 'http://hister:4433/path'], ['SHIORI_HISTER_URL', 'ftp://hister'], ['SHIORI_HISTER_URL', 'http://hister;x'],
    ['SHIORI_HISTER_URL', 'http://hister:4433 {'], ['SHIORI_KURA_URL', 'http://kura/\n}'], ['SHIORI_AI_URL', 'http://ai:99999'],
    ['SHIORI_HISTER_HOST', 'bad host'], ['SHIORI_ROOM_COOKIE', 'a;b'], ['SHIORI_SEARCH_PORT', '80'], ['SHIORI_APP_PORT', '8080'],
    ['SHIORI_SOURCE_URL', "https://x.example/'+alert(1)+'"], ['SHIORI_KURA_PUBLIC_URL', 'https://x.example/\\'],
    ['SHIORI_APP_URL', 'https://app.example/path'], ['SHIORI_HISTER_VERSION', 'v0.20.0 (abc)'],
  ];
  for (const [name, value] of bad) {
    const x = run({ ...BASE, [name]: value });
    assert.equal(x.r.status, 2, `${name}=${JSON.stringify(value)}`);
    assert.ok(x.r.stderr.includes(name), `${name} named in: ${x.r.stderr}`);
    x.cleanup();
  }
  // A quote smuggled into a stamped value is refused before it reaches a script.
  const x = run({ ...BASE, SHIORI_OBSIDIAN_VAULT: "my'vault" });
  assert.equal(x.r.status, 2);
  assert.match(x.r.stderr, /quote, a backslash or a control character/);
  x.cleanup();
});

test('with only Hister and SearXNG: both pages, SearXNG and Hister proxied, everything else off and 404', { skip }, () => {
  const x = run(BASE);
  try {
    assert.equal(x.r.status, 0, x.r.stderr);
    assert.match(x.r.stdout, /search page :8080, web app :8081/);
    assert.match(x.r.stdout, /sign-in: Hister's own/);
    const conf = x.sites();
    assert.match(conf, /listen 8080;/);
    assert.match(conf, /listen 8081;/);
    assert.match(conf, /location \/searx\/ \{[^}]*set \$searx http:\/\/searxng:8080;/s);
    assert.match(conf, /location \/ \{[^}]*set \$hister http:\/\/hister:4433;/s);
    // Off: their routes answer 404, never fall through to Hister (whose UI answers any path 200).
    for (const route of ['/kura/', '/konbini/', '/smallweb/', '/shiori/ai/', '/shiori/', '/machiya/']) {
      assert.match(conf, new RegExp(`location ${route.replace(/\//g, '\\/')} \\{[^}]*return 404`), route);
    }
    assert.doesNotMatch(conf, /set \$(kura|konbini|smallweb|ai|feed) /);
    assert.doesNotMatch(conf, /_machiya_auth/);
    assert.match(conf, /location = \/_hister_auth/);
    // Never Origin: Hister's CSRF check depends on it passing through untouched.
    assert.doesNotMatch(conf, /Origin\b/i.test(conf) ? /^$/ : /(?!)/);
    for (const line of conf.split('\n')) assert.ok(!/proxy_set_header\s+Origin/i.test(line), line);
    // Only the cookies that belong to a service go to it.
    assert.match(conf, /proxy_set_header Cookie \$hister_cookie_own;/);
    assert.match(conf, /proxy_set_header Cookie "";/);
    assert.doesNotMatch(conf, /proxy_set_header Cookie \$http_cookie/);
    assert.doesNotMatch(conf, /proxy_hide_header Set-Cookie/);
    // The pages: unset services are stamped off.
    const app = x.read('www/app/_shiori/app.js');
    assert.doesNotMatch(app, /__SHIORI_FEED__/);
    assert.match(app, /fromBuild\('off'\) !== 'off'/);
    assert.match(x.read('www/search/_shiori/search-core.js'), /fromBuild\('hister'\) === 'hister'/);
    assert.match(app, /__SHIORI_KURA_URL__/, 'unset: left for the page to read as empty');
    assert.doesNotMatch(x.read('www/search/index.html'), /__SHIORI_STATUS_URL__|data-shiori-status/);
    const cfg = JSON.parse(x.read('www/search/_shiori/config.json'));
    assert.deepEqual(cfg.services, { hister: true, searxng: true, kura: false, konbini: false, smallweb: false, feed: false, ai: false });
    assert.equal(cfg.signin, 'hister');
  } finally {
    x.cleanup();
  }
});

test('every optional service set: routed, stamped, and the status link and rooms filled', { skip }, () => {
  const x = run({
    ...BASE, SHIORI_KURA_URL: 'https://kura.example', SHIORI_KONBINI_URL: 'http://konbini:8081', SHIORI_SMALLWEB_URL: 'http://smallweb:8080',
    SHIORI_FEED_URL: 'http://feed:8080', SHIORI_AI_URL: 'http://ai:8080', SHIORI_STATUS_URL: 'https://status.example/',
    SHIORI_SOURCE_URL: 'https://github.com/example/fork', SHIORI_OBSIDIAN_VAULT: 'Notes', SHIORI_ROOMS: 'machiya=https://home.example/',
    SHIORI_KONBINI_PUBLIC_URL: 'https://konbini.example/', SHIORI_SEARCH_PAGE_URL: 'https://search.example/',
  });
  try {
    assert.equal(x.r.status, 0, x.r.stderr);
    const conf = x.sites();
    assert.match(conf, /location ~ \^\/kura\/\(api\/\(search\|recent\|note\|vaults\|prefs\)\|feed\\\.xml\)\$ \{[^}]*set \$kura https:\/\/kura\.example;/s);
    assert.match(conf, /proxy_ssl_server_name on;\n\s+proxy_ssl_name kura\.example;\n\s+proxy_ssl_verify on;/);
    assert.match(conf, /set \$konbini http:\/\/konbini:8081;/);
    assert.match(conf, /location \/smallweb\/api\/ \{[^}]*set \$smallweb http:\/\/smallweb:8080;/s);
    assert.match(conf, /location \/shiori\/ai\/ \{\s+auth_request \/_hister_auth;/);
    assert.match(conf, /location \/shiori\/ \{\s+auth_request \/_hister_auth;[^}]*set \$feed http:\/\/feed:8080;/s);
    assert.match(conf, /return 503 '\{"error":"unavailable"/);
    // Kura's reader pages are never passed under /kura/.
    assert.match(conf, /location \/kura\/ \{\n\s+return 404;/);
    // Kura and Konbini get only the rooms' own session cookie.
    assert.match(conf, /proxy_set_header Cookie \$machiya_session_cookie;/);
    const search = x.read('www/search/_shiori/search.js');
    assert.match(search, /Notes/);
    assert.match(search, /https:\/\/github\.com\/example\/fork/);
    // The Rooms menu lists the addresses given for people (a *_PUBLIC_URL or SHIORI_ROOMS), never an upstream's own.
    assert.match(search, /S\.rooms\('machiya=https:\/\/home\.example\/,konbini=https:\/\/konbini\.example\/'/);
    assert.doesNotMatch(search, /kura=https:\/\/kura\.example/);
    assert.match(x.read('www/search/index.html'), /<a href="https:\/\/status\.example\/">Status<\/a>/);
    assert.match(x.read('www/app/_shiori/app.js'), /fromBuild\('1'\) === '1'/);   // AI on
    assert.match(x.read('www/search/_shiori/opensearch.xml'), /https:\/\/search\.example\/\?q=\{searchTerms\}/);
    assert.doesNotMatch(x.read('www/app/_shiori/app.js'), /__SHIORI_(AI|SMALLWEB_URL|SOURCE_URL)__/);
    assert.match(x.read('www/app/_shiori/app.js'), /fromBuild\('__SHIORI_FEED__'\) !== 'off'/);   // a feed service: left unstamped, so on
    const cfg = JSON.parse(x.read('www/app/_shiori/config.json'));
    assert.deepEqual(cfg.services, { hister: true, searxng: true, kura: true, konbini: true, smallweb: true, feed: true, ai: true });
    assert.equal(cfg.links.status, 'https://status.example/');
  } finally {
    x.cleanup();
  }
});

test("Machiya's sign-in helper takes over when SHIORI_LOGIN_URL is set: the auth request, one cookie per service", { skip }, () => {
  const x = run({ ...BASE, SHIORI_LOGIN_URL: 'http://hister-login:8080', SHIORI_KURA_URL: 'http://kura:8080', SHIORI_KONBINI_URL: 'http://konbini:8081',
    SHIORI_FEED_URL: 'http://feed:8080', SHIORI_APP_URL: 'https://app.example' });
  try {
    assert.equal(x.r.status, 0, x.r.stderr);
    assert.match(x.r.stdout, /sign-in: Machiya's sign-in helper/);
    const conf = x.sites();
    assert.match(conf, /location = \/_machiya_auth \{\s+internal;\s+set \$helper http:\/\/hister-login:8081;\s+proxy_pass \$helper\/v1\/nginx;/);
    assert.match(conf, /proxy_set_header X-Machiya-Session \$machiya_room_sid;/);
    assert.match(conf, /proxy_set_header X-Machiya-Room \$site_origin;/);
    assert.match(conf, /set \$site_origin https:\/\/app\.example;/);
    assert.match(conf, /location ~ \^\/machiya\/\(start\|callback\|signed-out\|signout\|api\/prefs\)\$ \{\s+set \$helper_pub http:\/\/hister-login:8080;/);
    assert.match(conf, /\(\?:\^\|;\\s\*\)__Host-machiya_sso_shiori=\(\?<v>mhr_\[A-Za-z0-9_-\]\{43\}\)/);
    assert.match(conf, /location \/ \{\s+auth_request \/_machiya_auth;\s+auth_request_set \$hister_cookie \$upstream_http_x_hister_cookie;/);
    assert.match(conf, /proxy_set_header Cookie \$hister_cookie;[\s\S]*?proxy_hide_header Set-Cookie;/);
    assert.match(conf, /proxy_set_header Cookie "__Host-machiya_sso_kura=\$machiya_room_sid";/);
    assert.match(conf, /proxy_set_header Cookie "__Host-machiya_sso_konbini=\$machiya_room_sid";/);
    assert.doesNotMatch(conf, /_hister_auth|hister_cookie_own/);
    // The pages keep the helper's sign-in (not Hister's own page).
    assert.doesNotMatch(x.read('www/search/_shiori/search-core.js'), /fromBuild\('hister'\)/);
    assert.equal(JSON.parse(x.read('www/search/_shiori/config.json')).signin, 'hister-login');
  } finally {
    x.cleanup();
  }
});

test("the page's address carries the settings, so a page never runs with another run's settings", { skip }, () => {
  const a = run(BASE);
  const b = run({ ...BASE, SHIORI_FEED_URL: 'http://feed:8080' });
  const c = run(BASE);
  try {
    const v = (x) => /\/_shiori\/search\.js\?v=([A-Za-z0-9._-]+)/.exec(x.read('www/search/index.html'))[1];
    assert.match(v(a), /^abc1234-[0-9a-f]{8}$/);
    assert.notEqual(v(a), v(b));
    assert.equal(v(a), v(c));
    // The service worker's cache name follows it.
    assert.match(a.read('www/app/sw.js'), /shiori-app-[0-9a-f]{12}-[0-9a-f]{8}/);
    // Nothing keeps the build's bare version where the settings changed.
    assert.doesNotMatch(readdirSync(join(a.out, 'www/app/_shiori')).join('\n'), /\?v=/);
  } finally {
    a.cleanup();
    b.cleanup();
    c.cleanup();
  }
});

test('an https upstream is verified unless told not to; the start-up line names what is on and off', { skip }, () => {
  const x = run({ ...BASE, SHIORI_HISTER_URL: 'https://hister.example:8443', SHIORI_UPSTREAM_TLS_VERIFY: '0' });
  try {
    const conf = x.sites();
    assert.match(conf, /proxy_ssl_name hister\.example;/);
    assert.doesNotMatch(conf, /proxy_ssl_verify on/);
    assert.match(conf, /set \$hister https:\/\/hister\.example:8443;/);
    assert.match(conf, /proxy_set_header Host hister\.example:8443;/);
    assert.match(x.r.stdout, /off: Kura \(notes\), Konbini \(cards\)/);
  } finally {
    x.cleanup();
  }
  const y = run({ ...BASE, SHIORI_HISTER_URL: 'https://hister.example', SHIORI_HISTER_HOST: 'hister.internal' });
  assert.match(y.sites(), /proxy_set_header Host hister\.internal;/);
  y.cleanup();
});

test("status.json names the Hister release: the build's, or SHIORI_HISTER_VERSION's", { skip }, () => {
  const a = run(BASE);
  const b = run({ ...BASE, SHIORI_HISTER_VERSION: 'v0.20.0' });
  try {
    for (const key of ['search', 'app']) {
      const built = JSON.parse(readFileSync(join(dist, key, '_shiori', 'status.json'), 'utf8'));
      assert.deepEqual(JSON.parse(a.read(`www/${key}/_shiori/status.json`)), built);
      assert.deepEqual(JSON.parse(b.read(`www/${key}/_shiori/status.json`)), { ...built, hister: 'v0.20.0' });
    }
  } finally {
    a.cleanup();
    b.cleanup();
  }
});

// The start-up probe, against a fake Hister and SearXNG on this machine.
async function probe(answer) {
  const server = createServer((req, res) => {
    if (!req.url.startsWith('/search?')) return res.end('ok');
    res.writeHead(answer.status ?? 200, { 'Content-Type': answer.type ?? 'application/json' });
    res.end(answer.body);
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const up = `http://127.0.0.1:${server.address().port}`;
  try {
    const child = spawn(python, ['docker/shiori-web/configure.py', '--check'],
      { cwd: repo, env: { ...env0, SHIORI_HISTER_URL: up, SHIORI_SEARXNG_URL: up } });
    let stdout = '';
    child.stdout.on('data', (d) => { stdout += d; });
    const code = await new Promise((resolve) => child.on('close', resolve));
    return { code, stdout };
  } finally {
    server.close();
  }
}

test("the probe reads SearXNG's whole JSON answer, however long, and says when it isn't JSON", { skip }, async () => {
  const results = Array.from({ length: 400 }, (_, i) => ({ url: `https://example.com/${i}`, title: `Result ${i}`, content: 'x'.repeat(300) }));
  const big = JSON.stringify({ query: 'shiori', results });
  assert.ok(big.length > 1 << 16);
  let p = await probe({ body: big });
  assert.equal(p.code, 0);
  assert.match(p.stdout, /Hister and SearXNG answer\./);
  assert.doesNotMatch(p.stdout, /wasn't JSON/);
  // Past the cap, the content type says it.
  p = await probe({ body: JSON.stringify({ results: [{ content: 'x'.repeat(3 << 20) }] }) });
  assert.match(p.stdout, /Hister and SearXNG answer\./);
  p = await probe({ body: '<!doctype html><title>SearXNG</title>', type: 'text/html' });
  assert.match(p.stdout, /SearXNG's answer to a JSON search wasn't JSON/);
  p = await probe({ status: 403, body: 'Forbidden', type: 'text/plain' });
  assert.match(p.stdout, /doesn't allow JSON results/);
});
