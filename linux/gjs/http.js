// HTTP for Shiori for Linux (libsoup 3). Only the configured hosts:
// Flatpak can't limit the network by host, so the app refuses any other
// (docs/linux.md). Hister gets `Origin: hister://`, as from HisterKit.
// The Machiya sign-in (config.json's machiyaToken) goes only where
// search-core's host rule allows (../src/machiya.js), and a request that
// carries it follows no redirect. Hister's token (config.json's
// histerToken) goes only to the configured server (../src/hister.js),
// under the same no-redirect rule.

import GLib from 'gi://GLib';
import Soup from 'gi://Soup?version=3.0';
import { roomHeaders } from '../src/machiya.js';
import { histerHeaders } from '../src/hister.js';

const session = new Soup.Session({ timeout: 15, user_agent: 'Shiori-Linux' });

/** The hosts the config names; requests anywhere else are refused. */
export function allowedHosts(config) {
  const hosts = new Set();
  for (const key of ['server', 'kura', 'smallweb', 'webApp']) {
    try {
      if (config[key]) hosts.add(new URL(config[key]).host);
    } catch (_) {}
  }
  return hosts;
}

/**
 * GET or POST JSON: resolves to { status, json }, rejects when the host
 * isn't configured or can't be reached. `hister` adds its Origin;
 * `signIn: false` leaves the Machiya token off even for a room (pairing);
 * `redirects: false` follows none.
 */
export function requestJSON(config, url, { method = 'GET', body = null, hister = false, signIn = true, redirects = true } = {}) {
  return new Promise((resolve, reject) => {
    let host;
    try {
      host = new URL(url).host;
    } catch (_) {
      return reject(new Error(`Not an address: ${url}`));
    }
    if (!allowedHosts(config).has(host)) return reject(new Error(`Not a configured host: ${host}`));
    const message = Soup.Message.new(method, url);
    if (!message) return reject(new Error(`Not an address: ${url}`));
    const headers = message.get_request_headers();
    headers.append('Accept', 'application/json');
    if (hister) headers.append('Origin', 'hister://');
    const auth = signIn && !hister ? roomHeaders(config, url, globalThis.ShioriSearch).Authorization : undefined;
    if (auth) headers.append('Authorization', auth);
    const token = hister ? histerHeaders(config, url, globalThis.ShioriSearch)['X-Access-Token'] : undefined;
    if (token) headers.append('X-Access-Token', token);
    // libsoup would carry the header along a redirect: a request with a token follows none.
    if (auth || token || !redirects) message.set_flags(Soup.MessageFlags.NO_REDIRECT);
    if (body !== null) {
      const bytes = new TextEncoder().encode(typeof body === 'string' ? body : JSON.stringify(body));
      message.set_request_body_from_bytes('application/json', new GLib.Bytes(bytes));
    }
    session.send_and_read_async(message, GLib.PRIORITY_DEFAULT, null, (source, result) => {
      try {
        const bytes = source.send_and_read_finish(result);
        const text = new TextDecoder().decode(bytes.get_data() ?? new Uint8Array());
        let json = null;
        try {
          json = text ? JSON.parse(text) : null;
        } catch (_) {}
        // The number itself: get_status() maps it to Soup.Status, which
        // lacks 429 here and threw ("not a valid value for enumeration"),
        // so a full gateway or a rate-limited Hister read as unreachable.
        resolve({ status: message.status_code, json });
      } catch (error) {
        reject(error);
      }
    });
  });
}
