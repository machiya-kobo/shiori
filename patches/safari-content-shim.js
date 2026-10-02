// Safari compatibility shim, prepended to content.js at build time.
//
// No text beside the HTML. Upstream sends the page's innerText as well as
// its HTML, but Hister derives the text from the HTML: every extractor
// either sets it or leaves the page unindexed (server/extractor, v0.20.0),
// so the text was carried to the background, through the offline queue and
// up to the server only to be replaced. It stays when there's no HTML.
//
// Size cap. Upstream sends the page's whole documentElement.innerHTML and
// innerText to the background script. On a heavy page that message can
// get Mobile Safari to kill the extension, and it has to fit the offline
// queue in storage.local. So oversized html/text are truncated (never
// dropped: a cut-off body still indexes and previews). HTML is cut at the
// last '>' before the cap so no tag is split; Hister's parser closes
// whatever is left open.

(function installPageSizeCap() {
  if (typeof chrome === 'undefined' || !chrome.runtime || !chrome.runtime.sendMessage) return;

  const HTML_MAX = 2 * 1024 * 1024; // UTF-16 code units
  const TEXT_MAX = 1 * 1024 * 1024;

  function cutText(s, max) {
    if (typeof s !== 'string' || s.length <= max) return s;
    let end = max;
    // Do not leave half a surrogate pair at the end.
    const c = s.charCodeAt(end - 1);
    if (c >= 0xd800 && c <= 0xdbff) end -= 1;
    return s.slice(0, end);
  }

  function cutHTML(s, max) {
    if (typeof s !== 'string' || s.length <= max) return s;
    const lastClose = s.lastIndexOf('>', max - 1);
    return lastClose > 0 ? s.slice(0, lastClose + 1) : cutText(s, max);
  }

  const originalSendMessage = chrome.runtime.sendMessage.bind(chrome.runtime);

  chrome.runtime.sendMessage = function cappedSendMessage(message, ...rest) {
    if (message && message.pageData) {
      let d = message.pageData;
      if (typeof d.html === 'string' && d.html && 'text' in d) {
        const { text: _, ...withoutText } = d;
        d = withoutText;
        message = { ...message, pageData: d };
      }
      if (
        (typeof d.html === 'string' && d.html.length > HTML_MAX) ||
        (typeof d.text === 'string' && d.text.length > TEXT_MAX)
      ) {
        message = {
          ...message,
          pageData: {
            ...d,
            html: cutHTML(d.html, HTML_MAX),
            ...('text' in d ? { text: cutText(d.text, TEXT_MAX) } : {}),
          },
        };
      }
    }
    return originalSendMessage(message, ...rest);
  };
})();
