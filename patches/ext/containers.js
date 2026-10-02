// Container rules (Firefox): pages in the containers you choose (Banking,
// Work) are never captured on their own. Prepended to background.js before
// ext/core.js (which hides `shiori:` messages from every listener added
// after it, this one's own included) and before upstream, whose listeners
// it filters as upstream adds them: a page's
// automatic capture from a tab in a chosen container is answered as a skip
// rule would be (406), and a PDF tab there is never fetched. A deliberate
// save ("Index this page now", Save Page to Hister) still goes through.
//
// The list is the tabs' cookieStoreIds, set only by the settings page
// (`set-skip-containers`, as `set-server`). The page reads the containers'
// names with contextualIdentities, a required permission (Firefox refuses
// it as optional); matching a tab needs only `tabs`.
(function installContainerRules() {
  if (typeof chrome === 'undefined' || !chrome.runtime || !chrome.runtime.onMessage || !chrome.storage) return;
  const KEY = 'shioriSkipContainers';
  const ID = /^firefox-container-\d+$/;

  let skip = new Set();
  let changed = false; // a change seen before the first read answers wins over it
  const listOf = (ids) => new Set((Array.isArray(ids) ? ids : []).filter((id) => ID.test(id)));
  const loaded = chrome.storage.local.get([KEY]).then((got) => {
    if (!changed) skip = listOf(got[KEY]);
  }, () => {});
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== 'local' || !(KEY in changes)) return;
    changed = true;
    skip = listOf(changes[KEY].newValue);
  });
  const skipped = (tab) => !!tab && typeof tab.cookieStoreId === 'string' && skip.has(tab.cookieStoreId);

  // Upstream's message listener: an automatic capture from a chosen
  // container is skipped. Shiori's own messages and everything else pass.
  const onMessage = chrome.runtime.onMessage;
  const addMessageListener = onMessage.addListener.bind(onMessage);
  onMessage.addListener = function skippingContainers(listener) {
    return addMessageListener((request, sender, sendResponse) => {
      const automatic = request && request.pageData && request.action !== 'reindex' && !request.shiori;
      if (!automatic || !sender || !sender.tab) return listener(request, sender, sendResponse);
      loaded.then(() => {
        if (skipped(sender.tab)) sendResponse({ status: 'ok', status_code: 406 });
        else listener(request, sender, sendResponse);
      });
      return true;
    });
  };

  // Upstream's tab listener fetches a PDF tab to save it: never in a chosen container.
  if (chrome.tabs && chrome.tabs.onUpdated) {
    const onUpdated = chrome.tabs.onUpdated;
    const addTabListener = onUpdated.addListener.bind(onUpdated);
    onUpdated.addListener = function skippingContainerTabs(listener) {
      return addTabListener((tabId, change, tab) => {
        if (skipped(tab)) return;
        return listener(tabId, change, tab);
      });
    };
  }

  // The settings page's list: only from that page, only container IDs.
  addMessageListener((request, sender, sendResponse) => {
    if (!request || request.shiori !== 'set-skip-containers') return false;
    const fromSettings =
      !!sender && typeof sender.url === 'string' && sender.url.split(/[?#]/)[0] === chrome.runtime.getURL('shiori-settings.html');
    const ids = Array.isArray(request.ids) ? [...new Set(request.ids.filter((id) => typeof id === 'string' && ID.test(id)))] : null;
    if (!fromSettings || !ids) {
      sendResponse({ ok: false });
      return false;
    }
    chrome.storage.local.set({ [KEY]: ids }).then(
      () => sendResponse({ ok: true, ids }),
      () => sendResponse({ ok: false }),
    );
    return true;
  });
})();
