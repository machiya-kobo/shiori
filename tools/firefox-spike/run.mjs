// The Firefox build in headless Firefox, against fake-hister.py (begun as
// phase 0 of docs/firefox-plan.md). One line per check; exits 1 if any
// fails. Started by run.sh, which builds the bundle and serves the pages.
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
import { By } from 'selenium-webdriver';
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

    const perms = await inPage(driver, EXT_URL + 'shiori-settings.html', async () => ({
      allUrls: await browser.permissions.contains({ origins: ['<all_urls>'] }),
      nativeMessaging: await browser.permissions.contains({ permissions: ['nativeMessaging'] }),
      histerURL: (await browser.storage.local.get('histerURL')).histerURL || null,
      commands: (await browser.commands.getAll()).map((c) => `${c.name}=${c.shortcut || '(none)'}`),
    }));
    note('at install', JSON.stringify({ ...perms, commands: undefined }));
    check('no native messaging (Firefox has no app)', perms.nativeMessaging === false);
    note('shortcuts Firefox assigned', perms.commands.join(' '));

    // The results page's Settings: kept by ext/host-local.js, AI refused.
    const kept = await inPage(driver, EXT_URL + 'search.html', async () => {
      const reply = await browser.runtime.sendMessage({ shiori: 'set-settings', values: { theme: 'day', histerCount: 10, aiProvider: 'x' } });
      const stored = (await browser.storage.local.get('shioriLocalSettings')).shioriLocalSettings || {};
      return { ok: reply && reply.ok, theme: reply && reply.settings && reply.settings.theme, stored };
    });
    check('a settings change is kept on this device, AI keys refused', kept.ok === true && kept.theme === 'day' && kept.stored.histerCount === 10 && !('aiProvider' in kept.stored), JSON.stringify(kept.stored));
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
    const queued = await inPage(driver, EXT_URL + 'shiori-settings.html', async () => (await browser.storage.local.get('shioriQueueIndex')).shioriQueueIndex || []);
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

    await driver.get(EXT_URL + 'shiori-settings.html');
    await sleep(3000);
    note('settings page', await driver.executeScript(
      "return ['status', 'access', 'queue'].map((id) => id + ': ' + (document.getElementById(id)?.textContent || '?')).join(' | ')"));

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

// The settings page, driven as a person would: it opens on first install;
// saving a server fetches that server's rules at once; a bad address is
// refused on the page; a switch and a neighbour's address are kept.
async function settingsSession() {
  const driver = await browser({ 'extensions.webextensions.uuids': JSON.stringify({ [ID]: UUID }) });
  const text = async (id) => (await driver.findElement(By.id(id)).getText()).trim();
  try {
    await hister(true);
    await install(driver, EXT);
    await sleep(2500);
    // Every tab's address, from Firefox itself: the page may open in the
    // empty start tab, where WebDriver sees no new window.
    const tabs = await chrome(driver,
      'return [...Services.wm.getEnumerator("navigator:browser")].flatMap((w) => w.gBrowser.tabs.map((t) => t.linkedBrowser.currentURI.spec))');
    check('first install opens the settings page', tabs.includes(EXT_URL + 'shiori-settings.html'), JSON.stringify(tabs));
    await driver.get(EXT_URL + 'shiori-settings.html');
    await sleep(2500);
    check('  it finds the server and site access', /^Connected/.test(await text('status')) && (await text('access')) === 'Allowed',
      `status=${await text('status')} access=${await text('access')}`);

    // A server written another way (localhost, no trailing slash): same fake.
    const server = driver.findElement(By.id('server'));
    await server.clear();
    await server.sendKeys('ftp://nope.example');
    await driver.findElement(By.css('#server-form button')).click();
    await sleep(500);
    const refused = await text('server-error');
    setMark();
    await server.clear();
    await server.sendKeys(`http://localhost:${HISTER_PORT}`);
    await driver.findElement(By.css('#server-form button')).click();
    const rules = await waitFor((r) => r.m === 'GET' && r.p.startsWith('/api/rules'), 5000);
    await sleep(1500);
    const stored = await driver.executeAsyncScript('const done = arguments[arguments.length - 1]; browser.storage.local.get(["histerURL", "shioriCachedRules"]).then(done)');
    check('a bad address is refused on the page', /isn't an address/.test(refused), refused);
    check('saving the server stores it and fetches its rules at once', stored.histerURL === `http://localhost:${HISTER_PORT}/` && !!rules && typeof stored.shioriCachedRules === 'string',
      `histerURL=${stored.histerURL} rules=${!!rules} status=${await text('status')}`);

    await driver.findElement(By.id('combinedSearch')).click();
    await driver.findElement(By.id('searxngURL')).sendKeys('https://searx.example');
    await driver.findElement(By.css('#rooms-form button[type=submit]')).click();
    await sleep(1500);
    const local = await driver.executeAsyncScript('const done = arguments[arguments.length - 1]; browser.storage.local.get("shioriLocalSettings").then((r) => done(r.shioriLocalSettings || {}))');
    check('a switch and a neighbour are kept on this device', local.combinedSearch === false && local.searxngURL === 'https://searx.example/',
      JSON.stringify(local) + ' ' + (await text('rooms-saved')));
    check('  the web-results switch follows the take-over switch', !(await driver.findElement(By.id('webResults')).isEnabled()));

    // Site access taken away, as about:addons does: both the host
    // permission and the content script's <all_urls> (Firefox counts that
    // as one too). The page says so and offers Grant; its click asks
    // Firefox, which WebDriver can't answer, so that part is a hand check.
    await driver.executeAsyncScript('const done = arguments[arguments.length - 1]; browser.permissions.remove({ origins: ["*://*/*", "<all_urls>"] }).then(() => done(), () => done())');
    await driver.navigate().refresh();
    await sleep(1500);
    const grant = await driver.findElement(By.id('grant')).isDisplayed();
    check('without site access the page says so and offers Grant', (await text('access')) === 'Not allowed' && grant, `access=${await text('access')} grant=${grant}`);
    check("  and doesn't blame the network for the server", /site access/.test(await text('status')), await text('status'));
    if (env('SHOTS')) {
      for (const [theme, width] of [['night', 1000], ['day', 1000], ['night', 400]]) {
        await driver.executeScript(`document.documentElement.dataset.theme = '${theme}'`);
        await driver.manage().window().setRect({ width, height: 1400 });
        await sleep(300);
        fs.writeFileSync(path.join(env('SHOTS'), `settings-${theme}-${width}.png`), await driver.takeScreenshot(), 'base64');
      }
    }
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

for (const session of [settingsSession, captureSession, privateSession, containerSession]) {
  try {
    await session();
  } catch (e) {
    check(session.name, false, String((e && e.stack) || e).split('\n')[0]);
  }
}
fs.writeFileSync(path.join(WORK, 'results.json'), JSON.stringify(results, null, 2) + '\n');
process.exit(results.some((r) => r.ok === false) ? 1 : 0);
