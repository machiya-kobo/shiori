// Pages waiting for Hister, as the iOS app's Outbox (HisterKit Saving.swift)
// and the Safari extension's queue keep them (docs/linux.md): one
// JSON entry per page, oldest first, one entry per URL (a newer save
// replaces it and keeps the first time). Pure: the store is passed in, a
// directory of files in GJS, a Map in the tests.
//
// store: { list(): Promise<string[]> (names), read(name): Promise<string|null>,
//          write(name, text): Promise<void>, remove(name): Promise<void> }

export const MAX_ATTEMPTS = 5;
/** A page nobody could send for this long is dropped unsent. */
export const MAX_AGE_SECONDS = 14 * 24 * 60 * 60;

const nowSeconds = () => Math.floor(Date.now() / 1000);

async function entries(store) {
  const names = (await store.list()).filter((n) => n.endsWith('.json')).sort();
  const out = [];
  for (const name of names) {
    let entry = null;
    try {
      entry = JSON.parse((await store.read(name)) || 'null');
    } catch (_) {}
    out.push({ name, entry: entry && entry.page && typeof entry.page.url === 'string' ? entry : null });
  }
  return out;
}

/** Queues a page, stamping its time if it has none; a page already waiting is replaced, keeping its first time. */
export async function enqueue(store, page, { now = nowSeconds(), id = Math.random().toString(36).slice(2, 10) } = {}) {
  const queued = { ...page };
  for (const { name, entry } of await entries(store)) {
    if (entry && entry.page.url === page.url) {
      if (queued.added == null) queued.added = entry.page.added;
      await store.remove(name);
    }
  }
  if (queued.added == null) queued.added = now;
  const name = `${String(now).padStart(12, '0')}-${id}.json`;
  await store.write(name, JSON.stringify({ page: queued, attempts: 0 }));
  return name;
}

/** How many wait, and since when (unix seconds, or null). */
export async function status(store) {
  const all = (await entries(store)).filter((e) => e.entry);
  return { count: all.length, oldest: all.length ? all[0].entry.page.added ?? null : null };
}

/**
 * What one reply means for a queued page: 'sent'; 'drop' (Hister refused it
 * for good: 406 skip rule, 413, 422 sensitive, or any other 4xx but 429);
 * 'retry' (429 or 5xx: counted, and the drain stops).
 */
export function outcome(httpStatus) {
  if (httpStatus >= 200 && httpStatus < 300) return 'sent';
  if (httpStatus === 429 || httpStatus >= 500) return 'retry';
  return 'drop';
}

/**
 * Sends oldest first with `send(page)`, which resolves to the HTTP status
 * or rejects when Hister can't be reached. Stops at the first unreachable
 * or unwell reply; the rest waits for the next drain.
 * Resolves to { sent, dropped, stopped }.
 */
export async function drain(store, send, { now = nowSeconds() } = {}) {
  let sent = 0;
  let dropped = 0;
  for (const { name, entry } of await entries(store)) {
    if (!entry) {
      await store.remove(name); // unreadable: lost either way
      dropped++;
      continue;
    }
    if (entry.page.added != null && now - entry.page.added > MAX_AGE_SECONDS) {
      await store.remove(name);
      dropped++;
      continue;
    }
    let result;
    try {
      result = outcome(await send(entry.page));
    } catch (_) {
      return { sent, dropped, stopped: true };
    }
    if (result === 'sent') {
      sent++;
      await store.remove(name);
    } else if (result === 'drop') {
      dropped++;
      await store.remove(name);
    } else {
      entry.attempts = (entry.attempts || 0) + 1;
      if (entry.attempts >= MAX_ATTEMPTS) {
        dropped++;
        await store.remove(name);
      } else {
        await store.write(name, JSON.stringify(entry));
      }
      return { sent, dropped, stopped: true };
    }
  }
  return { sent, dropped, stopped: false };
}
