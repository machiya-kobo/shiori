// Phase 0 of docs/firefox-plan.md: the Safari-shimmed bundle in headless
// Firefox, against fake-hister.py. One line per check; exits 1 if any fails.
// Started by run.sh, which builds the bundle and serves the pages.
//
// Environment: FIREFOX (binary), FIREFOX_MAJOR (its version), GECKODRIVER
// (default: on PATH), EXT (the Firefox bundle), PROBE (container-probe/),
// WORK (logs), HISTER_PORT, PAGES_PORT.
//
// Extensions are installed unpacked (geckodriver's `path`), not as a zip:
// in some containers Firefox can't hand a zipped add-on's content script
// to the content process ("IPDL protocol Error: Received an invalid file
// descriptor", then "Unable to load script: …/content.js"). Plain upstream
// fails the same way there; a signed .xpi on a desktop is unaffected.

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { Builder } from 'selenium-webdriver';
import firefox from 'selenium-webdriver/firefox.js';
import { Command } from 'selenium-webdriver/lib/command.js';

const env = (name, fallback) => process.env[name] || fallback;
const FIREFOX = env('FIREFOX');
const GECKODRIVER = env('GECKODRIVER', 'geckodriver');
const EXT = path.resolve(env('EXT'));
const PROBE = path.resolve(env('PROBE'));
const WORK = path.resolve(env('WORK'));
const HISTER_PORT = env('HISTER_PORT', '8775');
const PAGES = `http://localhost:${env('PAGES_PORT', '8776')}/`;
const LOG = path.join(WORK, 'hister.log');
const HERE = path.dirname(new URL(import.meta.url).pathname);

const ID = 'shiori@machiya-kobo.github.io';
const UUID = '5a1e0000-0000-4000-8000-000000000001';
const EXT_URL = `moz-extension://${UUID}/`;
const PROBE_ID = 'container-probe@shiori.invalid';
const PROBE_UUID = 'c0000000-0000-4000-8000-000000000001';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
function check(name, ok, detail = '') {
  results.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  ' + detail : ''}`);
}
function note(name, detail) {
  results.push({ name, ok: null, detail });
  console.log(`NOTE  ${name}  ${detail}`);
}

// The fake Hister's log, and a mark so each check only sees its own requests.
function requests() {
  if (!fs.existsSync(LOG)) return [];
  return fs.readFileSync(LOG, 'utf8').split('\n').filter((l) => l.endsWith('}')).map((l) => JSON.parse(l));
}
let mark = 0;
const setMark = () => (mark = requests().length);
async function waitFor(pred, ms = 8000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const hit = requests().slice(mark).find(pred);
    if (hit) return hit;
    await sleep(250);
  }
  return null;
}
const posted = (suffix, p = '/api/add') => (r) => r.m === 'POST' && r.p === p && String(r.url || '').endsWith(suffix);

// "Offline" stops the fake's process (connection refused). A server that
// drops the socket instead makes Firefox retry idempotent GETs on its own.
let fake = null;
async function hister(up) {
  if (!up) {
    fake?.kill();
    fake = null;
    await sleep(300);
  } else if (!fake) {
    fake = spawn('python3', [path.join(HERE, 'fake-hister.py'), HISTER_PORT, LOG], { stdio: 'ignore' });
    await sleep(600);
  }
}

async function browser(prefs = {}) {
  const opts = new firefox.Options().setBinary(FIREFOX).addArguments('-headless');
  for (const [k, v] of Object.entries(prefs)) opts.setPreference(k, v);
  const out = fs.openSync(path.join(WORK, 'firefox.log'), 'a');
  const service = new firefox.ServiceBuilder(GECKODRIVER).setStdio(['ignore', out, out]);
  // Firefox 140 and later refuse the chrome context (and 153 navigating
  // WebDriver to moz-extension:// pages) unless geckodriver passes this on.
  if (Number(env('FIREFOX_MAJOR', '0')) >= 140) service.addArguments('--allow-system-access');
  return new Builder().forBrowser('firefox').setFirefoxOptions(opts).setFirefoxService(service).build();
}
const install = (driver, dir) =>
  driver.execute(new Command('install addon').setParameter('path', dir).setParameter('temporary', true));
async function chrome(driver, script, ...args) {
  await driver.setContext(firefox.Context.CHROME);
  try {
    return await driver.executeScript(script, ...args);
  } finally {
    await driver.setContext(firefox.Context.CONTENT);
  }
}
async function inPage(driver, url, fn) {
  await driver.get(url);
  await sleep(500);
  return driver.executeAsyncScript(
    `const done = arguments[arguments.length - 1]; (${fn})().then(done, (e) => done({ error: String(e) }));`,
  );
}

async function captureSession() {
  const driver = await browser({
    'extensions.webextensions.uuids': JSON.stringify({ [ID]: UUID }),
    // Firefox unloads an idle event page; 3 s instead of 30 s shows it here.
    'extensions.background.idle.timeout': 3000,
    'devtools.console.stdout.content': true,
    'devtools.console.stdout.chrome': true,
  });
  const backgroundState = () =>
    chrome(
      driver,
      `const { ExtensionParent } = ChromeUtils.importESModule('resource://gre/modules/ExtensionParent.sys.mjs');
       const ext = ExtensionParent.GlobalManager.extensionMap.get(arguments[0]);
       return ext ? String(ext.backgroundState) : 'not installed';`,
      ID,
    ).catch((e) => 'unknown: ' + String(e).slice(0, 100));
  try {
    await hister(true);
    note('Firefox', await driver.getCapabilities().then((c) => `${c.get('browserName')} ${c.get('browserVersion')}`));
    setMark();
    await install(driver, EXT);
    check('installs (background.scripts, incognito not_allowed)', true);

    const perms = await inPage(driver, EXT_URL + 'shiori-options.html', async () => ({
      allUrls: await browser.permissions.contains({ origins: ['<all_urls>'] }),
      chromeNamespace: typeof chrome !== 'undefined' && !!chrome.storage,
      histerURL: (await browser.storage.local.get('histerURL')).histerURL || null,
    }));
    note('at install', JSON.stringify(perms));
    const early = requests().slice(mark).filter((r) => r.p.startsWith('/api/rules')).length;
    note('skip rules fetched before the first capture', `${early} (0: the queue's start-up fetch runs before upstream stores histerURL on a fresh install)`);

    setMark();
    await driver.get(PAGES + 'page1.html');
    const add = await waitFor(posted('page1.html'));
    check('a visited page reaches api/add', !!add);
    if (add) {
      const m = add.meta || {};
      check('  metadata: source, client, client_version', m.source === 'shiori' && m.client === 'shiori' && !!m.client_version, JSON.stringify(m));
      check('  HTML without text (installPageSizeCap)', add.html > 0 && add.text === 0, `html=${add.html} text=${add.text}`);
      check('  Origin moz-extension://', String(add.origin).startsWith('moz-extension://'), String(add.origin));
    }

    setMark();
    await driver.get(PAGES + 'skipme.html');
    check('a skip rule keeps the page off the server', !(await waitFor(posted('skipme.html'), 5000)));

    setMark();
    await hister(false);
    await driver.get(PAGES + 'page2.html');
    await sleep(4000);
    const queued = await inPage(driver, EXT_URL + 'shiori-options.html', async () => (await browser.storage.local.get('shioriQueueIndex')).shioriQueueIndex || []);
    check('offline: the capture is queued', queued.length === 1, JSON.stringify(queued.map((q) => q.pageURL)));

    setMark();
    await hister(true);
    await driver.get(PAGES + 'page3.html');
    const drained = await waitFor(posted('page2.html'), 10000);
    check('back online: the queue drains', !!drained, drained ? `added=${drained.added} (${typeof drained.added})` : '');

    await driver.get('about:blank');
    await sleep(8000);
    const idle = await backgroundState();
    check('an idle background is unloaded (event page)', idle === 'stopped', idle);
    await hister(false);
    await driver.get(PAGES + 'page4.html');
    await sleep(4000);
    await driver.get('about:blank');
    await sleep(8000);
    note('offline, one page queued, idle again', await backgroundState());
    setMark();
    await hister(true);
    await driver.get(PAGES + 'page1.html?again');
    check('the queue survives an unloaded background and drains on wake', !!(await waitFor(posted('page4.html'), 12000)));

    setMark();
    await driver.get(PAGES + 'doc.pdf');
    const pdf = await waitFor((r) => r.m === 'POST' && r.p === '/api/add_pdf', 10000);
    check('a PDF tab reaches api/add_pdf', !!pdf, pdf ? `title=${pdf.title} pdf=${pdf.pdf} chars` : '');
    if (pdf) check('  with metadata.source = shiori (prepPDF)', pdf.meta?.source === 'shiori', JSON.stringify(pdf.meta));

    await driver.get(EXT_URL + 'shiori-options.html');
    await sleep(3000);
    note('settings page', await driver.executeScript(
      "return ['server', 'status', 'access', 'queue'].map((id) => id + ': ' + (document.getElementById(id)?.textContent || '?')).join(' | ')"));

    setMark();
    await driver.get(EXT_URL + 'search.html?q=lantern');
    await sleep(5000);
    const search = requests().slice(mark).find((r) => r.p.startsWith('/search'));
    check('search.html runs and queries Hister', !!search, search ? decodeURIComponent(search.p).slice(0, 140) : '');

    await driver.get(EXT_URL + 'popup.html');
    await sleep(2000);
    note('popup', JSON.stringify((await driver.executeScript('return document.body.innerText')).replace(/\s+/g, ' ').slice(0, 160)));
  } finally {
    await driver.quit().catch(() => {});
    await hister(false);
  }
}

async function privateSession() {
  const driver = await browser({ 'browser.privatebrowsing.autostart': true });
  try {
    await hister(true);
    await install(driver, EXT);
    await sleep(2000);
    setMark();
    await driver.get(PAGES + 'page1.html');
    await sleep(6000);
    const isPrivate = await chrome(driver, 'return PrivateBrowsingUtils.isWindowPrivate(window)');
    const seen = requests().slice(mark).length;
    check('private browsing: not loaded, nothing sent', isPrivate === true && seen === 0, `private=${isPrivate} requests=${seen}`);
  } finally {
    await driver.quit().catch(() => {});
    await hister(false);
  }
}

async function containerSession() {
  const driver = await browser({ 'extensions.webextensions.uuids': JSON.stringify({ [PROBE_ID]: PROBE_UUID }) });
  const enabled = () => chrome(driver, "return Services.prefs.getBoolPref('privacy.userContext.enabled')");
  try {
    const before = await enabled();
    await install(driver, PROBE);
    await sleep(1500);
    note('containers switched on by installing contextualIdentities', `before=${before} after=${await enabled()}`);
    const got = await inPage(driver, `moz-extension://${PROBE_UUID}/probe.html`, async () => globalThis.probe());
    check('without cookies: container names readable', Array.isArray(got.names), JSON.stringify(got.names));
    check("without cookies: a tab's container readable", Array.isArray(got.tabStores), JSON.stringify(got.tabStores));
    note('without cookies: opening a tab in a container', String(got.openInContainer));
  } finally {
    await driver.quit().catch(() => {});
  }
}

for (const session of [captureSession, privateSession, containerSession]) {
  try {
    await session();
  } catch (e) {
    check(session.name, false, String((e && e.stack) || e).split('\n')[0]);
  }
}
fs.writeFileSync(path.join(WORK, 'results.json'), JSON.stringify(results, null, 2) + '\n');
process.exit(results.some((r) => r.ok === false) ? 1 : 0);
