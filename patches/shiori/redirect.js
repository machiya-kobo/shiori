// Content script on duckduckgo.com, at document_start. A fresh web search
// (the address bar's, with DuckDuckGo as Safari's engine) goes to Shiori's
// combined results instead. The background decides, from the setting in
// the app, and swaps the tab; until it answers the page stays hidden.
(function () {
  const nav = performance.getEntriesByType('navigation')[0];
  if (!globalThis.ShioriSearch || !ShioriSearch.shouldRedirect(location.href, nav && nav.type)) return;
  const q = new URLSearchParams(location.search).get('q');

  const root = document.documentElement;
  root.style.visibility = 'hidden';
  const show = () => {
    root.style.visibility = '';
  };
  // Never leave the page blank if the background is slow or says no.
  const failsafe = setTimeout(show, 2500);
  try {
    chrome.runtime.sendMessage({ shiori: 'search', q }, (reply) => {
      void chrome.runtime.lastError;
      // The hosted results page: this tab goes there itself.
      if (reply && reply.redirect && typeof reply.url === 'string' && /^https:\/\//.test(reply.url)) {
        location.replace(reply.url);
        return;
      }
      if (!reply || !reply.redirect) {
        clearTimeout(failsafe);
        show();
      }
    });
  } catch (_) {
    clearTimeout(failsafe);
    show();
  }
})();
