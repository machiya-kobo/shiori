// The toolbar button's badge: how many pages are waiting to send, on every
// tab, and the button's tooltip says so (Safari on the Mac and iOS, beside
// the app's Waiting to Send).
// Prepended to background.js before upstream's code (which badges single
// tabs: "!" for an error, "✓" for a page saved when its option is on).
// Upstream clears a tab's badge with "", which would hide the count on that
// tab; here that becomes clearTab, "back to the toolbar's own".
(function installQueueBadge() {
  if (typeof chrome === 'undefined' || !chrome.action || !chrome.action.setBadgeText || !chrome.storage) return;
  const INDEX_KEY = 'shioriQueueIndex';
  const COLOURS = { background: '#e0af68', text: '#1a1b26' }; // Tokyo Night's amber, dark text (8.55:1)
  const action = chrome.action;

  const setBadgeText = action.setBadgeText.bind(action);
  const quiet = (p) => (p && typeof p.catch === 'function' ? p.catch(() => {}) : p);
  /** A call that may throw or reject, as a promise. */
  const attempt = (fn) => {
    try {
      return Promise.resolve(fn());
    } catch (error) {
      return Promise.reject(error);
    }
  };

  // The toolbar's own text and tooltip, and the tabs holding a copy of them
  // where the browser refused null (Safari's answer to null hasn't been
  // seen on a device), kept in step by show().
  let current = { text: '', title: 'Shiori' };
  const copies = new Set();

  /** One tab back to the toolbar's badge, colour and tooltip. */
  function clearTab(tabId) {
    if (tabId == null) return Promise.resolve();
    const copy = (fn) => () => (copies.add(tabId), fn());
    return Promise.all([
      attempt(() => setBadgeText({ tabId, text: null })).catch(copy(() => setBadgeText({ tabId, text: current.text }))),
      attempt(() => action.setBadgeBackgroundColor({ tabId, color: null })).catch(() => action.setBadgeBackgroundColor({ tabId, color: COLOURS.background })),
      attempt(() => action.setTitle({ tabId, title: null })).catch(copy(() => action.setTitle({ tabId, title: current.title }))),
    ]).then(() => {}, () => {});
  }

  action.setBadgeText = function badgeWithoutHidingTheCount(details, ...rest) {
    if (details && details.tabId != null && details.text === '') return clearTab(details.tabId);
    if (details && details.tabId != null) copies.delete(details.tabId);
    return setBadgeText(details, ...rest);
  };

  function show(count) {
    current = {
      text: count > 0 ? (count > 999 ? '999+' : String(count)) : '',
      title: count > 0 ? `Shiori · ${count} ${count === 1 ? 'page' : 'pages'} waiting to send` : 'Shiori',
    };
    quiet(setBadgeText({ text: current.text }));
    if (count > 0) {
      quiet(action.setBadgeBackgroundColor({ color: COLOURS.background }));
      if (action.setBadgeTextColor) quiet(action.setBadgeTextColor({ color: COLOURS.text }));
    }
    quiet(action.setTitle({ title: current.title }));
    for (const tabId of copies) {
      // A closed tab refuses: forget it.
      attempt(() => setBadgeText({ tabId, text: current.text })).catch(() => copies.delete(tabId));
      quiet(attempt(() => action.setTitle({ tabId, title: current.title })));
    }
  }
  const countIn = (index) => (Array.isArray(index) ? index.length : 0);

  globalThis.ShioriBadge = { clearTab };
  if (chrome.tabs && chrome.tabs.onRemoved) chrome.tabs.onRemoved.addListener((tabId) => copies.delete(tabId));
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area === 'local' && INDEX_KEY in changes) show(countIn(changes[INDEX_KEY].newValue));
  });
  chrome.storage.local.get([INDEX_KEY]).then((got) => show(countIn(got[INDEX_KEY])), () => {});
})();
