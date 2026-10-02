// URL and URLSearchParams for GJS, which has neither (docs/linux.md).
// Only what search-core.js and these modules use: absolute URLs, their
// parts, and query parameters with the WHATWG form encoding (space as
// "+"). Node's own are the reference: scripts/linux.test.mjs checks these
// against them. `installURL()` adds them only where they're missing.

const FORM_SAFE = /[A-Za-z0-9*\-._]/;

function formEncode(text) {
  let out = '';
  for (const ch of String(text)) {
    if (ch === ' ') out += '+';
    else if (FORM_SAFE.test(ch)) out += ch;
    else for (const byte of new TextEncoder().encode(ch)) out += '%' + byte.toString(16).toUpperCase().padStart(2, '0');
  }
  return out;
}

function formDecode(text) {
  const bytes = [];
  const s = String(text).replace(/\+/g, ' ');
  for (let i = 0; i < s.length; i++) {
    if (s[i] === '%' && /^[0-9a-fA-F]{2}$/.test(s.slice(i + 1, i + 3))) {
      bytes.push(parseInt(s.slice(i + 1, i + 3), 16));
      i += 2;
    } else {
      bytes.push(...new TextEncoder().encode(s[i]));
    }
  }
  return new TextDecoder().decode(new Uint8Array(bytes));
}

export class ShimURLSearchParams {
  constructor(init = '') {
    this._list = [];
    if (typeof init === 'string') {
      for (const part of init.replace(/^\?/, '').split('&')) {
        if (!part) continue;
        const i = part.indexOf('=');
        this._list.push(i < 0 ? [formDecode(part), ''] : [formDecode(part.slice(0, i)), formDecode(part.slice(i + 1))]);
      }
    } else if (init && typeof init[Symbol.iterator] === 'function') {
      for (const [k, v] of init) this._list.push([String(k), String(v)]);
    } else if (init && typeof init === 'object') {
      for (const [k, v] of Object.entries(init)) this._list.push([k, String(v)]);
    }
  }
  get(name) {
    const hit = this._list.find(([k]) => k === name);
    return hit ? hit[1] : null;
  }
  getAll(name) {
    return this._list.filter(([k]) => k === name).map(([, v]) => v);
  }
  has(name) {
    return this._list.some(([k]) => k === name);
  }
  set(name, value) {
    const i = this._list.findIndex(([k]) => k === name);
    if (i < 0) return this.append(name, value);
    this._list[i][1] = String(value);
    this._list = this._list.filter(([k], j) => k !== name || j === i);
  }
  append(name, value) {
    this._list.push([String(name), String(value)]);
  }
  delete(name) {
    this._list = this._list.filter(([k]) => k !== name);
  }
  entries() {
    return this._list.map(([k, v]) => [k, v])[Symbol.iterator]();
  }
  [Symbol.iterator]() {
    return this.entries();
  }
  toString() {
    return this._list.map(([k, v]) => `${formEncode(k)}=${formEncode(v)}`).join('&');
  }
}

const SPECIAL = { 'http:': '80', 'https:': '443' };
const PATTERN = /^([a-zA-Z][a-zA-Z0-9+.-]*:)(?:\/\/([^/?#]*))?([^?#]*)(\?[^#]*)?(#.*)?$/;

export class ShimURL {
  constructor(input) {
    const text = String(input).trim();
    const m = text.match(PATTERN);
    if (!m || m[2] === undefined) throw new TypeError(`Invalid URL: ${text}`);
    const at = m[2].lastIndexOf('@');
    this._userinfo = at >= 0 ? m[2].slice(0, at + 1) : '';
    const authority = m[2].slice(at + 1);
    const hostMatch = authority.match(/^(\[[^\]]+\]|[^:]*)(?::(\d*))?$/);
    if (!hostMatch || !hostMatch[1]) throw new TypeError(`Invalid URL: ${text}`);
    this.protocol = m[1].toLowerCase();
    this.hostname = hostMatch[1].toLowerCase();
    const port = hostMatch[2] || '';
    this.port = SPECIAL[this.protocol] === port ? '' : port;
    this.pathname = m[3] || (SPECIAL[this.protocol] ? '/' : '');
    this.searchParams = new ShimURLSearchParams(m[4] || '');
    this._search = m[4] && m[4] !== '?' ? m[4] : '';
    // An empty "?" or "#" stays in href (as Node keeps it), not in search/hash.
    this._rawQuery = m[4] || '';
    this._rawHash = m[5] || '';
    this.hash = m[5] && m[5] !== '#' ? m[5] : '';
  }
  get host() {
    return this.port ? `${this.hostname}:${this.port}` : this.hostname;
  }
  // The user and password before "@", as given (search-core's host rule
  // refuses an address with either).
  get username() {
    const info = this._userinfo.slice(0, -1);
    const colon = info.indexOf(':');
    return colon >= 0 ? info.slice(0, colon) : info;
  }
  get password() {
    const info = this._userinfo.slice(0, -1);
    const colon = info.indexOf(':');
    return colon >= 0 ? info.slice(colon + 1) : '';
  }
  get origin() {
    return `${this.protocol}//${this.host}`;
  }
  get search() {
    return this._search;
  }
  get href() {
    return `${this.protocol}//${this._userinfo}${this.host}${this.pathname}${this._rawQuery}${this._rawHash}`;
  }
  toString() {
    return this.href;
  }
}

/** Adds URL and URLSearchParams to `root` (GJS's globalThis) where they're missing. */
export function installURL(root = globalThis) {
  if (typeof root.URL !== 'function') root.URL = ShimURL;
  if (typeof root.URLSearchParams !== 'function') root.URLSearchParams = ShimURLSearchParams;
}
