// Shiori's settings page where there is no app (Firefox): the Hister server,
// site access, the offline queue, the search switches and the neighbours'
// addresses. Every change goes through the background: the server through
// `set-server` (it fetches the new server's rules and moves the queue), the
// rest through `set-settings`, the same whitelist the results page's gear
// uses (ext/host-local.js). Nothing here can turn AI on.
(async () => {
  const $ = (id) => document.getElementById(id);
  const HOSTS = ['*://*/*'];
  const ROOM_KEYS = ['searxngURL', 'niwaURL', 'konbiniURL', 'smallwebURL', 'obsidianVault'];
  const TOGGLES = ['webResults'];

  /** A message to the background; null when it didn't answer. */
  const send = (message) =>
    new Promise((resolve) => {
      try {
        chrome.runtime.sendMessage(message, (reply) => resolve(chrome.runtime.lastError ? null : reply || null));
      } catch (_) {
        resolve(null);
      }
    });

  /** An http(s) address with its trailing slash, '' for empty, null when it isn't one. */
  function address(text) {
    const value = String(text || '').trim();
    if (!value) return '';
    try {
      const u = new URL(value);
      if (u.protocol !== 'http:' && u.protocol !== 'https:') return null;
      return u.href.endsWith('/') ? u.href : u.href + '/';
    } catch (_) {
      return null;
    }
  }

  function showError(el, text) {
    el.textContent = text || '';
    el.hidden = !text;
  }

  // --- what's stored ---

  await send({ shiori: 'refresh-settings' });
  let { histerURL = '', shioriSettings: settings = {} } = await chrome.storage.local.get(['histerURL', 'shioriSettings']);

  function look(s) {
    if (s.theme === 'night' || s.theme === 'day') document.documentElement.dataset.theme = s.theme;
    else delete document.documentElement.dataset.theme;
    // The rooms' themes (palettes.css, which knows only their keys); Tokyo
    // Night is search.css's own.
    if (typeof s.palette === 'string' && /^[a-z-]+$/.test(s.palette) && s.palette !== 'tokyo-night') document.documentElement.dataset.palette = s.palette;
    else delete document.documentElement.dataset.palette;
  }
  function fill(s) {
    for (const key of TOGGLES) $(key).checked = s[key] !== false;
    for (const key of ROOM_KEYS) $(key).value = typeof s[key] === 'string' ? s[key] : '';
  }
  look(settings);
  fill(settings);
  $('server').value = histerURL;

  // --- the server ---

  let checking = 0;
  let allowed = null; // site access, from showAccess
  async function checkServer() {
    const run = ++checking;
    const status = $('status');
    const base = address(histerURL);
    if (!base) {
      status.textContent = 'Not set';
      status.className = 'value bad';
      return;
    }
    // Without site access this page can't reach the server either.
    if (allowed === false) {
      status.textContent = 'Needs site access (below)';
      status.className = 'value bad';
      return;
    }
    status.textContent = 'Checking…';
    status.className = 'value';
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 6000);
    let text = "Can't reach it (check the address, your network or VPN)";
    let ok = false;
    try {
      // Hister's token, as the background stored it (checked there): this
      // request's header only, never shown.
      const { histerToken } = await chrome.storage.local.get(['histerToken']);
      const headers = histerToken ? { Accept: 'application/json', 'X-Access-Token': histerToken } : { Accept: 'application/json' };
      const reply = await fetch(base + 'api/stats', { headers, signal: controller.signal });
      if (!reply.ok) throw new Error(String(reply.status));
      const count = Number((await reply.json().catch(() => ({}))).doc_count);
      text = Number.isFinite(count) ? `Connected · ${count.toLocaleString()} pages` : 'Connected';
      ok = true;
    } catch (_) {
    } finally {
      clearTimeout(timer);
    }
    if (run !== checking) return;
    status.textContent = text;
    status.className = ok ? 'value ok' : 'value bad';
  }

  $('server-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    const base = address($('server').value);
    if (!base) {
      showError($('server-error'), "That isn't an address: start it with https:// or http://.");
      return;
    }
    showError($('server-error'), '');
    const reply = await send({ shiori: 'set-server', url: base });
    if (!reply || !reply.ok) {
      showError($('server-error'), "Couldn't save it; try again.");
      return;
    }
    histerURL = base;
    $('server').value = base;
    await checkServer();
    void showQueue();
  });

  // --- Hister's token ---
  // Kept by the background (histerToken); this page learns only whether
  // one is set, and never shows it back.

  async function showToken() {
    const reply = await send({ shiori: 'hister-token-status' });
    $('token').value = '';
    $('token').placeholder = reply && reply.ok && reply.set ? 'Saved (type to replace)' : 'Not set';
  }
  $('token-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    const reply = await send({ shiori: 'set-hister-token', token: $('token').value });
    if (!reply || !reply.ok) {
      showError($('token-error'), reply && reply.invalid ? "That isn't a token: it's 8 to 512 characters with no spaces." : "Couldn't save it; try again.");
      return;
    }
    showError($('token-error'), '');
    await showToken();
    await checkServer();
  });
  void showToken();

  // --- Machiya sign-in ---
  // The background pairs and keeps the token (core.js, shioriMachiya); this
  // page sees only who is signed in, never the token.

  async function showMachiya() {
    const reply = await send({ shiori: 'machiya-status' });
    $('machiya-status').textContent = (reply && reply.ok && reply.text) || 'Not signed in';
    $('machiya-sign-out').hidden = !(reply && reply.signedIn);
  }

  $('machiya-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    showError($('machiya-error'), '');
    const entry = $('machiya-entry').value;
    $('machiya-status').textContent = 'Signing in…';
    const reply = await send({ shiori: 'machiya-sign-in', entry, device: $('machiya-device').value });
    if (!reply || !reply.ok) showError($('machiya-error'), (reply && reply.error) || "Couldn't sign in; try again.");
    else $('machiya-entry').value = '';
    await showMachiya();
  });

  $('machiya-sign-out').addEventListener('click', async () => {
    showError($('machiya-error'), '');
    const reply = await send({ shiori: 'machiya-sign-out' });
    if (!reply || !reply.ok) showError($('machiya-error'), "Couldn't sign out; try again.");
    await showMachiya();
  });

  void showMachiya();

  // --- site access ---

  async function showAccess() {
    const was = allowed;
    try {
      allowed = await chrome.permissions.contains({ origins: HOSTS });
    } catch (_) {
      allowed = null;
    }
    const access = $('access');
    access.textContent = allowed === null ? 'Unknown' : allowed ? 'Allowed' : 'Not allowed';
    access.className = allowed ? 'value ok' : 'value bad';
    $('access-help').hidden = allowed !== false;
    $('grant').hidden = allowed !== false;
    if (was !== null && was !== allowed) void checkServer();
  }
  $('grant').addEventListener('click', async () => {
    // Asked from the click itself: Firefox only asks in answer to the user.
    try {
      await chrome.permissions.request({ origins: HOSTS });
    } catch (_) {}
    await showAccess();
  });
  if (chrome.permissions && chrome.permissions.onAdded) chrome.permissions.onAdded.addListener(() => void showAccess());
  if (chrome.permissions && chrome.permissions.onRemoved) chrome.permissions.onRemoved.addListener(() => void showAccess());

  // --- the queue ---

  function queueText(reply) {
    if (!reply || !reply.ok) return 'Unknown';
    if (!reply.count) return 'Nothing';
    const pages = `${reply.count} ${reply.count === 1 ? 'page' : 'pages'}`;
    return reply.oldest ? `${pages}, since ${new Date(reply.oldest).toLocaleString()}` : pages;
  }
  async function showQueue(kind = 'queue-status') {
    const reply = await send({ shiori: kind });
    $('queue').textContent = queueText(reply);
    $('retry').disabled = !reply || !reply.count;
  }
  $('retry').addEventListener('click', async () => {
    $('retry').disabled = true;
    $('queue').textContent = 'Sending…';
    await showQueue('retry-queue');
  });

  // --- search switches and neighbours, through the whitelist ---

  async function save(values) {
    const reply = await send({ shiori: 'set-settings', values });
    if (!reply || !reply.ok || !reply.settings) return null;
    settings = reply.settings;
    look(settings);
    return settings;
  }

  for (const key of TOGGLES) {
    $(key).addEventListener('change', async () => {
      const saved = await save({ [key]: $(key).checked });
      fill(saved || settings);
    });
  }

  $('rooms-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    showError($('rooms-error'), '');
    $('rooms-saved').textContent = '';
    const values = {};
    for (const input of document.querySelectorAll('#rooms-form input[data-url]')) {
      const value = address(input.value);
      if (value === null) {
        showError($('rooms-error'), `${input.labels[0].textContent} isn't an address: start it with https:// or http://.`);
        input.focus();
        return;
      }
      values[input.id] = value;
    }
    const vault = $('obsidianVault').value.trim();
    // The app's rule: a vault is named, never blank (it can't be removed).
    if (vault) values.obsidianVault = vault;
    const saved = await save(values);
    if (!saved) {
      showError($('rooms-error'), "Couldn't save them; try again.");
      return;
    }
    fill(saved);
    $('rooms-saved').textContent = !vault && saved.obsidianVault ? 'Saved (the vault keeps its name)' : 'Saved';
  });

  // --- another device: settings to a file and back (ext/settings-file.js) ---

  const F = globalThis.ShioriSettingsFile;
  const moveStatus = (text) => ($('move-status').textContent = text);

  $('export').addEventListener('click', async () => {
    const got = await chrome.storage.local.get(['histerURL', 'shioriLocalSettings']);
    const doc = F.exportSettings({ server: got.histerURL || '', settings: got.shioriLocalSettings || {} });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(new Blob([JSON.stringify(doc, null, 2) + '\n'], { type: 'application/json' }));
    link.download = F.fileName();
    document.body.append(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(link.href), 10_000);
    moveStatus(`Saved as ${link.download}.`);
  });

  let pending = null; // a file read, waiting for Apply
  $('import').addEventListener('change', async () => {
    const file = $('import').files[0];
    pending = null;
    $('apply').hidden = true;
    if (!file) return;
    const read = F.readImport(await file.text().catch(() => ''));
    $('import').value = ''; // the same file can be chosen again
    if (read.error) {
      moveStatus(read.error);
      return;
    }
    // Counted as the whitelist will judge it: only what it would keep.
    const judged = await send({ shiori: 'judge-settings', values: read.settings });
    if (!judged || !judged.ok) {
      moveStatus("Couldn't read that file's settings here.");
      return;
    }
    const kept = Object.fromEntries(Object.keys(judged.kept || {}).filter((k) => k in read.settings).map((k) => [k, read.settings[k]]));
    pending = { server: read.server, settings: kept, ignored: Object.keys(read.settings).length - Object.keys(kept).length };
    moveStatus(F.describeImport(pending, histerURL));
    $('apply').hidden = false;
  });

  $('apply').addEventListener('click', async () => {
    if (!pending) return;
    const { server, settings: values } = pending;
    pending = null;
    $('apply').hidden = true;
    let serverText = '';
    if (server && server !== histerURL) {
      const reply = await send({ shiori: 'set-server', url: server });
      if (reply && reply.ok) {
        histerURL = server;
        $('server').value = server;
        serverText = 'the server';
      }
    }
    const keys = Object.keys(values);
    if (keys.length) fill((await save(values)) || settings);
    // What the whitelist kept: the same value is now stored.
    const local = (await chrome.storage.local.get(['shioriLocalSettings'])).shioriLocalSettings || {};
    const kept = keys.filter((k) => JSON.stringify(local[k]) === JSON.stringify(values[k])).length;
    const parts = [serverText, kept ? `${kept} ${kept === 1 ? 'setting' : 'settings'}` : ''].filter(Boolean);
    const left = keys.length - kept;
    moveStatus(
      (parts.length ? `Applied ${parts.join(' and ')}.` : 'Nothing applied.') +
        (left ? ` ${left} ${left === 1 ? "wasn't a setting" : "weren't settings"} this page takes, and ${left === 1 ? 'was' : 'were'} left out.` : ''),
    );
    void checkServer();
    void showQueue();
  });

  // --- containers: never saved on their own (ext/containers.js) ---

  const containerStatus = (text) => ($('containers-status').textContent = text || '');

  async function showContainers() {
    const list = $('containers-list');
    const api = (globalThis.browser || chrome).contextualIdentities;
    if (!api) {
      list.replaceChildren();
      containerStatus('This Firefox has no containers.');
      return;
    }
    let found = [];
    try {
      found = await api.query({});
    } catch (_) {
      list.replaceChildren();
      containerStatus('Containers are turned off in Firefox (Settings → General → Tabs).');
      return;
    }
    const chosen = new Set((await chrome.storage.local.get(['shioriSkipContainers'])).shioriSkipContainers || []);
    list.replaceChildren(
      ...found.map((c) => {
        const row = document.createElement('label');
        row.className = 'row toggle';
        const name = document.createElement('span');
        name.textContent = c.name;
        const box = document.createElement('input');
        box.type = 'checkbox';
        box.dataset.id = c.cookieStoreId;
        box.checked = chosen.has(c.cookieStoreId);
        box.addEventListener('change', saveContainers);
        row.append(name, box);
        return row;
      }),
    );
    containerStatus(found.length ? '' : 'No containers yet: make them with Firefox’s container tabs.');
  }

  async function saveContainers() {
    const ids = [...document.querySelectorAll('#containers-list input:checked')].map((box) => box.dataset.id);
    const reply = await send({ shiori: 'set-skip-containers', ids });
    containerStatus(reply && reply.ok ? (ids.length ? `Never saved on their own: ${ids.length} ${ids.length === 1 ? 'container' : 'containers'}.` : 'Every container is saved as usual.') : "Couldn't save that; try again.");
  }

  await showAccess();
  await Promise.all([checkServer(), showQueue(), showContainers()]);
})();
