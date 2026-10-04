// `shiori save <url> [label]`, `shiori send`, `shiori status` (docs/linux.md):
// the one native write. The page is downloaded (3 MB cap, as the iOS
// share extension does), saved to Hister with `Origin: hister://`, and
// queued in the outbox when Hister can't be reached or is unwell; the
// queue follows the iOS rules (../src/outbox.js).

import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import Soup from 'gi://Soup?version=3.0';
import { newPage, addRequest, titleIn, capped, rejectionReason, MAX_BYTES } from '../src/page.js';
import * as outbox from '../src/outbox.js';
import { requestJSON } from './http.js';

export const VERSION = '0.5.7';

/** The outbox: one JSON file per page in $XDG_DATA_HOME/shiori/outbox. */
export function fileStore(dir = GLib.build_filenamev([GLib.get_user_data_dir(), 'shiori', 'outbox'])) {
  GLib.mkdir_with_parents(dir, 0o700);
  const path = (name) => GLib.build_filenamev([dir, name]);
  return {
    dir,
    list: async () => {
      const names = [];
      const enumerator = Gio.File.new_for_path(dir).enumerate_children('standard::name', Gio.FileQueryInfoFlags.NONE, null);
      let info;
      while ((info = enumerator.next_file(null))) names.push(info.get_name());
      return names;
    },
    read: async (name) => {
      try {
        return new TextDecoder().decode(GLib.file_get_contents(path(name))[1]);
      } catch (_) {
        return null;
      }
    },
    write: async (name, text) => void GLib.file_set_contents(path(name), text),
    remove: async (name) => void GLib.unlink(path(name)),
  };
}

const fetcher = new Soup.Session({ timeout: 15, user_agent: 'Shiori-Linux', max_conns_per_host: 2 });

/**
 * Downloads the page asked to be saved: the one address outside the
 * configured hosts the app fetches, because the user named it. HTML or
 * plain text only, up to 3 MB; anything else is saved as the link alone.
 */
export function fetchPage(url) {
  return new Promise((resolve) => {
    const message = Soup.Message.new('GET', url);
    if (!message) return resolve({ url, title: '', html: '' });
    message.get_request_headers().append('Accept', 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.5');
    fetcher.send_async(message, GLib.PRIORITY_DEFAULT, null, (source, result) => {
      let stream;
      try {
        stream = source.send_finish(result);
      } catch (_) {
        return resolve({ url, title: '', html: '' });
      }
      const type = (message.get_response_headers().get_content_type()[0] || '').toLowerCase();
      if (!type.includes('html') && !type.includes('text/plain')) return resolve({ url: message.get_uri().to_string(), title: '', html: '' });
      const chunks = [];
      let total = 0;
      const next = () =>
        stream.read_bytes_async(64 * 1024, GLib.PRIORITY_DEFAULT, null, (s, r) => {
          let bytes;
          try {
            bytes = s.read_bytes_finish(r);
          } catch (_) {
            bytes = null;
          }
          const data = bytes && bytes.get_data();
          if (data && data.length && total < MAX_BYTES) {
            chunks.push(data);
            total += data.length;
            return next();
          }
          stream.close_async(GLib.PRIORITY_DEFAULT, null, null);
          const all = new Uint8Array(total);
          let at = 0;
          for (const c of chunks) all.set(c, (at += c.length) - c.length);
          const html = new TextDecoder().decode(all.subarray(0, MAX_BYTES));
          resolve({ url: message.get_uri().to_string(), title: titleIn(html), html: capped(html) });
        });
      next();
    });
  });
}

/** Sends one page: the HTTP status, or throws when Hister can't be reached. */
export async function send(config, page) {
  const req = addRequest(config.server, page);
  const reply = await requestJSON(config, req.url, { method: 'POST', body: req.body, hister: true });
  return reply.status;
}

/** `shiori save`: resolves to { code, message } for the command line. */
export async function save(config, { url, label = null }) {
  if (!config.server) return { code: 2, message: 'No Hister server in ~/.config/shiori/config.json' };
  const fetched = await fetchPage(url);
  const page = newPage({ url: fetched.url || url, title: fetched.title, html: fetched.html || null, label, clientVersion: VERSION });
  const store = fileStore();
  let status;
  try {
    status = await send(config, page);
  } catch (_) {
    await outbox.enqueue(store, page);
    return { code: 0, message: 'Hister is out of reach: queued, and sent when it’s back (shiori send).' };
  }
  const result = outbox.outcome(status);
  if (result === 'sent') {
    const drained = await outbox.drain(store, (p) => send(config, p));
    return { code: 0, message: `Saved${label ? ` as ${label}` : ''}.${drained.sent ? ` Also sent ${drained.sent} waiting.` : ''}` };
  }
  if (result === 'retry') {
    await outbox.enqueue(store, page);
    return { code: 0, message: `Hister answered ${status}: queued, and sent later (shiori send).` };
  }
  return { code: 1, message: rejectionReason(status, `Hister refused it (${status}).`) };
}

/** `shiori send`: what's waiting, now. */
export async function sendWaiting(config) {
  const store = fileStore();
  const r = await outbox.drain(store, (p) => send(config, p));
  const left = (await outbox.status(store)).count;
  return { code: r.stopped ? 1 : 0, message: `Sent ${r.sent}, dropped ${r.dropped}; ${left} waiting${r.stopped ? ' (Hister is out of reach or unwell)' : ''}.` };
}

/** `shiori status`: how many wait, and since when. */
export async function waitingStatus() {
  const s = await outbox.status(fileStore());
  if (!s.count) return { code: 0, message: 'Nothing waiting.' };
  const since = s.oldest ? GLib.DateTime.new_from_unix_local(s.oldest).format('%Y-%m-%d %H:%M') : 'unknown';
  return { code: 0, message: `${s.count} waiting, the oldest from ${since}.` };
}
