// Shiori's touches on upstream's popup, which Svelte draws after load:
// Shiori's theme, Shiori's name, and the gear opening Shiori's settings
// page (upstream's settings view sets the server, a token and browser-
// session sign-in, which the app owns or which have no use here).
//
// And Hister's token: upstream's popup reads it from storage, where it no
// longer is (the background keeps it in memory and hands it to the
// extension's own pages). Its requests to the configured Hister server get
// it here, with no redirect followed. Installed before popup.js runs, which
// looks fetch up at each call.
(() => {
  if (typeof globalThis.fetch !== 'function') return;
  const originalFetch = globalThis.fetch.bind(globalThis);
  let tokenReady = null;
  const histerToken = () =>
    (tokenReady ??= new Promise((resolve) => {
      setTimeout(() => resolve(''), 500);
      try {
        chrome.runtime.sendMessage({ shiori: 'hister-token' }, (reply) => {
          void chrome.runtime.lastError;
          resolve((reply && reply.ok && reply.token) || '');
        });
      } catch (_) {
        resolve('');
      }
    }));
  const plainHeaders = (h) => {
    if (!h) return {};
    if (typeof Headers !== 'undefined' && h instanceof Headers) return Object.fromEntries(h.entries());
    return Array.isArray(h) ? Object.fromEntries(h) : { ...h };
  };
  globalThis.fetch = async function shioriPopupFetch(input, init) {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : (input && input.url) || '';
    let base = '';
    try {
      base = String((await chrome.storage.local.get(['histerURL'])).histerURL || '').trim();
    } catch (_) {}
    if (base && !base.endsWith('/')) base += '/';
    if (!base || !/^https?:\/\//i.test(base) || !url.startsWith(base)) return originalFetch(input, init);
    const headers = plainHeaders((init && init.headers) || (input && typeof input === 'object' && input.headers));
    if (!Object.keys(headers).some((k) => k.toLowerCase() === 'x-access-token')) {
      const token = await histerToken();
      if (token) headers['X-Access-Token'] = token;
    }
    if (!Object.keys(headers).some((k) => k.toLowerCase() === 'x-access-token')) return originalFetch(input, init);
    return originalFetch(input, { ...(init || {}), headers, redirect: 'error' });
  };
})();

(async () => {
  try {
    const { shioriSettings } = await chrome.storage.local.get(['shioriSettings']);
    const theme = shioriSettings && shioriSettings.theme;
    if (theme === 'night' || theme === 'day') document.documentElement.dataset.shioriTheme = theme;
  } catch (_) {}

  function touch() {
    const header = document.querySelector('main > div:first-child');
    if (!header) return false;
    const name = header.querySelector('a');
    if (name && name.textContent.trim() !== 'Shiori') {
      name.textContent = 'Shiori';
      name.title = 'Open Hister';
    }
    const gear = header.querySelector('button[aria-label="Settings"]');
    if (gear && !gear.dataset.shiori) {
      gear.dataset.shiori = '1';
      gear.title = 'Shiori Settings';
      gear.addEventListener(
        'click',
        (event) => {
          event.stopImmediatePropagation();
          event.preventDefault();
          chrome.runtime.openOptionsPage();
          window.close();
        },
        true,
      );
    }
    return !!(name && gear);
  }
  if (!touch()) {
    const watch = new MutationObserver(() => touch() && watch.disconnect());
    watch.observe(document.documentElement, { childList: true, subtree: true });
  }
})();
