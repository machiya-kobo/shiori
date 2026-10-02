// What containers give an extension without the cookies permission
// (docs/firefox-plan.md, feature E). Run from probe.html by run.mjs.
globalThis.probe = async () => {
  const out = {};
  try {
    out.names = (await browser.contextualIdentities.query({})).map((c) => [c.name, c.cookieStoreId]);
  } catch (e) {
    out.names = 'error: ' + e;
  }
  try {
    out.tabStores = (await browser.tabs.query({})).map((t) => t.cookieStoreId);
  } catch (e) {
    out.tabStores = 'error: ' + e;
  }
  try {
    const tab = await browser.tabs.create({ url: 'about:blank', cookieStoreId: 'firefox-container-1' });
    out.openInContainer = tab.cookieStoreId;
  } catch (e) {
    out.openInContainer = 'error: ' + e;
  }
  return out;
};
