// The host behind the extension, on Safari: the Shiori app, through native
// messaging (its handler reads and writes the App Group). Prepended to
// background.js before ext/core.js, which reaches the host only through
// `shioriHost`.
//
//   settings()          the app's settings (SharedSettings.extensionPayload),
//                       or null when the app can't be reached
//   recordSearch(q)     a search into the app's recent searches
//   setSettings(values) the results page's Settings, validated by the app
//                       (SharedSettings.applyFromPage); rejects without it
//   canReportQueue()    whether reportQueue can reach anything
//   reportQueue(count, oldest)  the offline queue's size, for the app's
//                       Settings → Account → Waiting to Send
//   machiya()           the Machiya sign-in, {token, principal}, from the
//                       app's Keychain; {} when signed out or unreachable.
//                       Never stored here: asked again when needed.
//   histerToken()       Hister's token, from the app's Keychain ('' when
//                       unset or unreachable), sent as X-Access-Token
const shioriHost = (() => {
  const APP_ID = '__SHIORI_APP_ID__';
  const canSend = () =>
    typeof chrome !== 'undefined' && !!chrome.runtime && typeof chrome.runtime.sendNativeMessage === 'function';
  const send = (message) => chrome.runtime.sendNativeMessage(APP_ID, message);
  return {
    async settings() {
      try {
        return await send({ type: 'settings' });
      } catch (_) {
        return null;
      }
    },
    recordSearch: (q) => send({ type: 'recent', q }),
    setSettings: (values) => send({ type: 'set-settings', values }),
    canReportQueue: canSend,
    reportQueue: (count, oldest) => send({ type: 'queue', count, oldest }),
    async machiya() {
      try {
        const reply = await send({ type: 'machiya' });
        return reply && typeof reply === 'object' ? reply : {};
      } catch (_) {
        return {};
      }
    },
    async histerToken() {
      try {
        const reply = await send({ type: 'hister' });
        return reply && typeof reply.token === 'string' ? reply.token : '';
      } catch (_) {
        return '';
      }
    },
  };
})();
