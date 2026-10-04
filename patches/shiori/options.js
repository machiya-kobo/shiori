// Shiori's extension settings page: what the extension is using, read from
// its storage (the app writes the server address and the settings there),
// and whether Hister answers. Nothing is changed here: the Shiori app is
// where settings are made, so "Open Shiori Settings" opens it.
(async () => {
  const $ = (id) => document.getElementById(id);
  const got = await chrome.storage.local.get(['histerURL', 'shioriSettings', 'shioriQueueIndex']);
  const settings = got.shioriSettings || {};
  if (settings.theme === 'night' || settings.theme === 'day') document.documentElement.dataset.theme = settings.theme;
  // The rooms' themes (palettes.css); Tokyo Night is search.css's own.
  const PALETTES = globalThis.ShioriSearch.PALETTES;
  if (Object.hasOwn(PALETTES, settings.palette) && settings.palette !== 'tokyo-night') document.documentElement.dataset.palette = settings.palette;

  const onOff = (value) => (value === false ? 'Off' : 'On');
  const orNone = (text) => (typeof text === 'string' && text.trim() ? text.trim() : 'Not set');
  $('combined').textContent = onOff(settings.combinedSearch);
  $('web').textContent = settings.combinedSearch === false ? 'Off' : onOff(settings.webResults);
  $('searxng').textContent = orNone(settings.searxngURL);
  const hosted = '__SHIORI_SEARCH_PAGE_URL__';
  $('results-at').textContent = /^https?:\/\//.test(hosted) ? hosted : "The extension's page";
  for (const el of document.querySelectorAll('[data-flag]')) el.textContent = onOff(settings[el.dataset.flag]);
  $('result-style').textContent = { solid: 'Solid', bar: 'Left Bar', none: 'None' }[settings.resultStyle] || 'Tint';
  $('palette').textContent = (PALETTES[settings.palette] || PALETTES['tokyo-night']).name;
  $('theme').textContent = { night: 'Dark', day: 'Light' }[settings.theme] || 'System';
  // The app's names (TextSize.name): xxLarge read "Large", below xLarge's "Larger".
  const sizes = { xSmall: 'Extra Small', small: 'Small', medium: 'Medium', large: 'Large', xLarge: 'Extra Large', xxLarge: 'Extra Extra Large', xxxLarge: 'Largest' };
  $('text-size').textContent = sizes[settings.textSize] || 'Standard';
  $('vault').textContent = orNone(settings.obsidianVault);
  $('niwa').textContent = orNone(settings.niwaURL);
  $('konbini').textContent = orNone(settings.konbiniURL);
  // Who the app signed in as (the background asks it; this page never sees the token).
  try {
    chrome.runtime.sendMessage({ shiori: 'machiya-status' }, (reply) => {
      void chrome.runtime.lastError;
      $('machiya').textContent = (reply && reply.ok && reply.text) || 'Not signed in';
    });
  } catch (_) {
    $('machiya').textContent = 'Unknown';
  }
  const queued = Array.isArray(got.shioriQueueIndex) ? got.shioriQueueIndex.length : 0;
  $('queue').textContent = queued ? `${queued} ${queued === 1 ? 'page' : 'pages'}` : 'Nothing';

  // Safari resets this on every reinstall, without asking; with it off
  // nothing is captured and searches go straight to DuckDuckGo.
  try {
    const allowed = await chrome.permissions.contains({ origins: ['https://duckduckgo.com/*', 'https://example.com/*'] });
    $('access').textContent = allowed ? 'Allowed' : 'Not allowed';
    $('access').className = allowed ? 'value ok' : 'value bad';
    $('access-help').hidden = allowed;
  } catch (_) {
    $('access').textContent = 'Unknown';
  }

  let server = (got.histerURL || '').trim();
  if (server && !server.endsWith('/')) server += '/';
  $('server').textContent = server || 'Not set';
  const status = $('status');
  if (!server) {
    status.textContent = 'Set it in the Shiori app';
    status.className = 'value bad';
    return;
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 6000);
  try {
    // Hister's token from the app (the background keeps it): this request's header only.
    const { histerToken } = await chrome.storage.local.get(['histerToken']);
    // With the token, no redirect is followed (S.histerFetchOptions).
    const headers = histerToken ? { Accept: 'application/json', 'X-Access-Token': histerToken } : { Accept: 'application/json' };
    const reply = await fetch(`${server}api/stats`, { headers, signal: controller.signal, ...(histerToken ? { redirect: 'error' } : {}) });
    if (!reply.ok) throw new Error(String(reply.status));
    const stats = await reply.json().catch(() => ({}));
    const count = Number(stats.doc_count);
    status.textContent = Number.isFinite(count) ? `Connected · ${count.toLocaleString()} pages` : 'Connected';
    status.className = 'value ok';
  } catch (_) {
    status.textContent = "Can't reach it (check your network or VPN)";
    status.className = 'value bad';
  } finally {
    clearTimeout(timer);
  }
})();
