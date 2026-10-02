// Shiori's touches on upstream's popup, which Svelte draws after load:
// Shiori's theme, Shiori's name, and the gear opening Shiori's settings
// page (upstream's settings view sets the server, a token and browser-
// session sign-in, which the app owns or which have no use here).
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
