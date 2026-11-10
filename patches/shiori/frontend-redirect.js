// Content script, at document_start, on the sites the build's privacy front
// ends (SHIORI_FRONTENDS) stand in for. With Settings → Safari → Open Sites
// in Your Front Ends on (off by default; this device's own), the page is
// swapped for the front end's (Reddit's for Redlib's) before it loads,
// replacing this history entry so Back doesn't land on the site and bounce.
// Back and Forward stay, and so does a visit marked to (Open Elsewhere's way
// back to the original), whose mark is then taken off the address.
//
// The switch is read from the settings the background keeps from the app
// (storage.local), with no wait on the background, so a page loads as fast
// with it off; the background is then asked to bring them up to date, so a
// switch just flipped counts from the next page.
(function () {
  const S = globalThis.ShioriSearch;
  if (!S || typeof chrome === 'undefined' || !chrome.storage || !chrome.storage.local) return;
  const instances = S.frontendInstances(S.fromBuild('__SHIORI_FRONTENDS__'));
  if (!instances.length) return;
  if (location.hash === '#' + S.STAY_MARK) {
    history.replaceState(history.state, '', location.href.slice(0, location.href.indexOf('#')));
    return;
  }
  const nav = performance.getEntriesByType('navigation')[0];
  const to = S.frontendRedirect(location.href, instances, nav && nav.type);
  if (!to) return;
  chrome.storage.local.get(['shioriSettings']).then((got) => {
    if (got && got.shioriSettings && got.shioriSettings.frontendRedirect === true) location.replace(to);
  }, () => {});
  try {
    chrome.runtime.sendMessage({ shiori: 'refresh-settings' }, () => void chrome.runtime.lastError);
  } catch (_) {}
})();
