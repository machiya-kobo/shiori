// The toolbar button's badge where there is no app to show the queue
// (Firefox): how many pages are waiting to send, on every tab, and the
// button's tooltip says so. Prepended to background.js before upstream's
// code (which badges single tabs: "!" for an error, "✓" for a page saved
// when its option is on). Upstream clears a tab's badge with "", which would
// hide the count on that tab; here that becomes null, "use the count".
(function installQueueBadge() {
  if (typeof chrome === 'undefined' || !chrome.action || !chrome.action.setBadgeText || !chrome.storage) return;
  const INDEX_KEY = 'shioriQueueIndex';
  const COLOURS = { background: '#e0af68', text: '#1a1b26' }; // Tokyo Night's amber, dark text (8.55:1)

  const setBadgeText = chrome.action.setBadgeText.bind(chrome.action);
  chrome.action.setBadgeText = function badgeWithoutHidingTheCount(details, ...rest) {
    if (details && details.tabId != null && details.text === '') details = { ...details, text: null };
    return setBadgeText(details, ...rest);
  };

  const quiet = (p) => (p && typeof p.catch === 'function' ? p.catch(() => {}) : p);
  function show(count) {
    const text = count > 0 ? (count > 999 ? '999+' : String(count)) : '';
    quiet(setBadgeText({ text }));
    if (count > 0) {
      quiet(chrome.action.setBadgeBackgroundColor({ color: COLOURS.background }));
      if (chrome.action.setBadgeTextColor) quiet(chrome.action.setBadgeTextColor({ color: COLOURS.text }));
    }
    quiet(chrome.action.setTitle({ title: count > 0 ? `Shiori · ${count} ${count === 1 ? 'page' : 'pages'} waiting to send` : 'Shiori' }));
  }
  const countIn = (index) => (Array.isArray(index) ? index.length : 0);

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area === 'local' && INDEX_KEY in changes) show(countIn(changes[INDEX_KEY].newValue));
  });
  chrome.storage.local.get([INDEX_KEY]).then((got) => show(countIn(got[INDEX_KEY])), () => {});
})();
