// Backgrounds (docs/backgrounds.md): a scene drawn behind the page (bg.js, from annai), the rain over it, or your
// own picture or video, with the page's surfaces as glass over it. Shared by the search page (and Safari's page) and
// the web app, which each put its rows in their own Settings sheet.
//
// These are this browser's own: localStorage (shioriBackground: {scene, rain}) and IndexedDB (shiori-background,
// your picture or video as {type, buf}), never the account, Safari's app settings or any server. Off draws nothing:
// no canvas, no timers, and bg.js isn't even loaded until a scene is picked.
//
// In the sheet a change previews at once and only Save keeps it (begin, change, save, cancel), the house's rule.
(function () {
  'use strict';
  const KEY = 'shioriBackground';
  // [id, name, group]: bg.js's scenes (its annaiBg.scenes, the same list; scripts/backgrounds.test.mjs holds them
  // together and to their previews in assets/backgrounds/).
  const SCENES = [
    ['city', 'Tokyo', 'Japan'], ['alley', 'Tokyo Alley', 'Japan'], ['osaka', 'Osaka', 'Japan'],
    ['seoul', 'Seoul', 'Asia'], ['hk', 'Hong Kong', 'Asia'], ['sh', 'Shanghai', 'Asia'], ['tp', 'Taipei', 'Asia'],
    ['sg', 'Singapore', 'Asia'], ['bkk', 'Bangkok', 'Asia'],
    ['sf', 'San Francisco', 'Americas'], ['la', 'Los Angeles', 'Americas'], ['chicago', 'Chicago', 'Americas'],
    ['lv', 'Las Vegas', 'Americas'],
    ['br', 'Los Angeles, 2019', 'Films and Games'], ['akira', 'Neo-Tokyo', 'Films and Games'],
    ['stray', 'Walled City (with a Cat)', 'Films and Games'],
  ];
  const IDS = SCENES.map(([id]) => id);
  const OFF = 'off';
  const CUSTOM = 'custom';
  // Your picture or video: a picture is scaled to 2400 px (JPEG); a GIF or a video is kept as it is, so it moves.
  const MAX_VIDEO = 100 * 1024 * 1024;
  const MAX_GIF = 20 * 1024 * 1024;

  // Where this script came from: bg.js and the previews sit beside it (the hosted pages' /_shiori/, Safari's
  // extension root), with the same build stamp (?v=).
  const self = document.currentScript && document.currentScript.src ? new URL(document.currentScript.src, location.href) : null;
  const base = self ? new URL('.', self).href : '';
  const stamp = self ? self.search : '';
  const preview = (id) => `${base}backgrounds/bg-${id}.jpg${stamp}`;

  const valid = (s) => (s === OFF || s === CUSTOM || IDS.includes(s) ? s : OFF);
  function read() {
    try {
      const v = JSON.parse(localStorage.getItem(KEY) || 'null') || {};
      return { scene: valid(v.scene), rain: v.rain === true };
    } catch (_) {
      return { scene: OFF, rain: false };
    }
  }
  function write(v) {
    try {
      if (v.scene === OFF && !v.rain) localStorage.removeItem(KEY);
      else localStorage.setItem(KEY, JSON.stringify({ scene: v.scene, rain: !!v.rain }));
    } catch (_) {}
  }

  // ---- your picture or video, in IndexedDB as {type, buf} (bytes: older Safari kept Blobs unreliably) -------------
  const store = {
    open() {
      return new Promise((ok, no) => {
        const q = indexedDB.open('shiori-background', 1);
        q.onupgradeneeded = () => q.result.createObjectStore('files');
        q.onsuccess = () => ok(q.result);
        q.onerror = () => no(q.error);
      });
    },
    async get() {
      try {
        const db = await this.open();
        return await new Promise((ok) => {
          const q = db.transaction('files').objectStore('files').get('bg');
          q.onsuccess = () => ok(q.result && q.result.buf ? q.result : null);
          q.onerror = () => ok(null);
        });
      } catch (_) {
        return null;
      }
    },
    async put(rec) {
      const db = await this.open();
      await new Promise((ok, no) => {
        const tx = db.transaction('files', 'readwrite');
        tx.objectStore('files').put(rec, 'bg');
        tx.oncomplete = () => ok();
        tx.onerror = tx.onabort = () => no(tx.error);
      });
    },
    async del() {
      try {
        const db = await this.open();
        await new Promise((ok) => {
          const tx = db.transaction('files', 'readwrite');
          tx.objectStore('files').delete('bg');
          tx.oncomplete = tx.onerror = tx.onabort = () => ok();
        });
      } catch (_) {}
    },
  };

  let kept = read();
  // The sheet's preview of your video (a blob: address), dropped when the sheet closes.
  let thumbURL = null;
  const dropThumb = () => {
    if (thumbURL) URL.revokeObjectURL(thumbURL);
    thumbURL = null;
  };
  let now = { ...kept };
  // While the Settings sheet is open: what was kept, and your picture or video if one was picked (null: removed).
  let draft = null;
  // The stored picture or video: undefined until asked, then null or {type, buf}.
  let stored;
  let words = () => [];
  const reduced = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
  // Apple's browsers (a Mac, iPhone or iPad; an iPad says MacIntel) keep the frosted glass whatever moves behind it.
  // Elsewhere (Firefox and Chrome on Linux and Windows) the blur over a moving background cost more than a core.
  const APPLE = /Mac|iPhone|iPad|iPod/.test((typeof navigator === 'object' && navigator.platform) || '');
  const media = () => (draft && draft.media !== undefined ? draft.media : stored);

  // ---- showing it ---------------------------------------------------------------------------------------------
  let engine = null; // bg.js, loaded once a scene is first shown
  function loadEngine() {
    if (window.annaiBg) return Promise.resolve(window.annaiBg);
    engine ||= new Promise((ok, no) => {
      const s = document.createElement('script');
      s.src = `${base}bg.js${stamp}`;
      s.onload = () => (window.annaiBg ? ok(window.annaiBg) : no(new Error('bg.js')));
      s.onerror = () => {
        engine = null;
        no(new Error('bg.js'));
      };
      document.head.append(s);
    });
    return engine;
  }

  let shown = ''; // what's on screen: a scene's id, custom:<n> for a picture or video, '' for nothing
  let mediaN = 0; // which picture or video (a new pick is a new one)
  let token = 0; // the newest apply wins over a slower one still loading
  let mediaURL = null;

  function clearMedia() {
    document.querySelectorAll('body > .bgimg, body > .bgvid').forEach((e) => e.remove());
    if (mediaURL) URL.revokeObjectURL(mediaURL);
    mediaURL = null;
  }

  async function apply() {
    const t = ++token;
    const root = document.documentElement;
    let scene = now.scene;
    if (scene === CUSTOM && stored === undefined && !(draft && draft.media !== undefined)) stored = await store.get();
    if (t !== token) return;
    if (scene === CUSTOM && !media()) scene = OFF;
    const want = scene === OFF ? '' : scene === CUSTOM ? `custom:${mediaN}` : scene;
    if (want !== shown) {
      if (window.annaiBg) window.annaiBg.stop();
      clearMedia();
      shown = '';
      if (scene !== OFF && scene !== CUSTOM) {
        let bg;
        try {
          bg = await loadEngine();
        } catch (_) {
          return; // the file didn't load: the page stays as it is
        }
        if (t !== token) return;
        bg.start(scene, ['Shiori', ...words()]);
      } else if (scene === CUSTOM) {
        await showMedia(media(), t);
        if (t !== token) return;
      }
      shown = want;
    }
    const on = shown !== '';
    root.classList.toggle('has-bg', on);
    // Moving: a scene, the rain or a video, redrawn many times a second. Off Apple (bg-lite) the glass then dims
    // without a backdrop filter (backgrounds.css): the browser would blur the moving layers again for every frame,
    // the most of what a background costs (Firefox on Linux, without a GPU, used more than a whole core for it).
    const video = scene === CUSTOM && !!media() && media().type.startsWith('video/');
    root.classList.toggle('bg-moving', on && !reduced() && (scene !== CUSTOM || video || !!now.rain));
    root.classList.toggle('bg-lite', on && !APPLE);
    if (!on) setWatching(false);
    if (window.annaiBg) window.annaiBg.rain(on && !!now.rain);
    corner();
  }

  async function showMedia(rec, t) {
    if (!rec) return;
    if (rec.type.startsWith('video/')) {
      mediaURL = URL.createObjectURL(new Blob([rec.buf], { type: rec.type }));
      const v = document.createElement('video');
      v.className = 'bgvid';
      v.muted = true;
      v.loop = true;
      v.playsInline = true;
      v.setAttribute('muted', '');
      v.setAttribute('playsinline', '');
      v.setAttribute('aria-hidden', 'true');
      v.preload = 'auto';
      v.src = mediaURL;
      document.body.prepend(v);
      // Reduced motion: the first frame stays.
      if (!reduced() && !document.hidden) v.play().catch(() => {});
      return;
    }
    // A picture as a data: address: the hosted pages' CSP takes data: images, not blob:.
    const url = await dataURL(rec);
    if (t !== token || !url) return;
    const d = document.createElement('div');
    d.className = 'bgimg';
    d.setAttribute('aria-hidden', 'true');
    d.style.backgroundImage = `url("${url}")`;
    document.body.prepend(d);
  }
  function dataURL(rec) {
    return new Promise((ok) => {
      const r = new FileReader();
      r.onload = () => ok(typeof r.result === 'string' && r.result.startsWith('data:image/') ? r.result : null);
      r.onerror = () => ok(null);
      r.readAsDataURL(new Blob([rec.buf], { type: rec.type }));
    });
  }
  // A looping video costs battery: it plays only while the page shows.
  document.addEventListener('visibilitychange', () => {
    const v = document.querySelector('body > .bgvid');
    if (!v) return;
    if (document.hidden) v.pause();
    else if (!reduced()) v.play().catch(() => {});
  });

  // ---- the corner: Rain and Watch, lower right, while a background shows -----------------------------------------
  const RAIN_ICON = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 15a5 5 0 1 1 1.6-9.7A6 6 0 0 1 20 9a4 4 0 0 1-2 7.5H7z"/><path d="M8 19l-1 2M12 19l-1 2M16 19l-1 2"/></svg>';
  const EYE_ICON = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg>';
  const watching = () => document.documentElement.classList.contains('bg-watching');
  function setWatching(on) {
    document.documentElement.classList.toggle('bg-watching', !!on);
    const eye = document.querySelector('#bgctl .bg-watch');
    if (eye) eye.setAttribute('aria-pressed', String(!!on));
  }
  function corner() {
    let box = document.getElementById('bgctl');
    const on = document.documentElement.classList.contains('has-bg');
    document.documentElement.classList.toggle('has-bgctl', on);
    if (!on) {
      if (box) box.remove();
      return;
    }
    if (!box) {
      box = document.createElement('div');
      box.id = 'bgctl';
      box.className = 'bgctl';
      box.setAttribute('role', 'group');
      box.setAttribute('aria-label', 'Background');
      const button = (cls, label, icon, onclick) => {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = cls;
        b.setAttribute('aria-label', label);
        b.title = label;
        b.innerHTML = icon;
        b.addEventListener('click', (event) => {
          event.stopPropagation();
          onclick();
        });
        return b;
      };
      // Rain from here is kept at once, as annai's corner (the sheet isn't open: it covers this).
      box.append(
        button('bg-rain', 'Rain', RAIN_ICON, () => change({ rain: !now.rain })),
        button('bg-watch', 'Watch', EYE_ICON, () => setWatching(!watching())),
      );
      document.body.append(box);
    }
    box.querySelector('.bg-rain').setAttribute('aria-pressed', String(!!now.rain));
    box.querySelector('.bg-watch').setAttribute('aria-pressed', String(watching()));
  }
  // Watching: a tap anywhere but the corner, or Escape, brings the page back (and does nothing else).
  document.addEventListener('click', (event) => {
    if (!watching() || (event.target.closest && event.target.closest('#bgctl'))) return;
    event.preventDefault();
    event.stopPropagation();
    setWatching(false);
  }, true);
  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape' || !watching()) return;
    event.preventDefault();
    event.stopPropagation();
    setWatching(false);
  }, true);

  // ---- settings -----------------------------------------------------------------------------------------------
  /** A change: previewed while the sheet is open (kept on Save), else kept at once. */
  function change(values) {
    now = { ...now, ...values };
    if (!draft) {
      kept = { ...now };
      write(kept);
    }
    return apply();
  }
  /** The sheet opened: what's kept now is what Cancel goes back to. */
  function begin() {
    draft = { before: { ...kept } };
    now = { ...kept };
  }
  /** Save: the scene, the rain and your picture or video, kept in this browser. */
  async function save() {
    const d = draft;
    if (!d) return;
    draft = null;
    dropThumb();
    if (d.media !== undefined) {
      try {
        if (d.media) await store.put(d.media);
        else await store.del();
        stored = d.media;
      } catch (_) {
        // Too big for this browser's storage: it shows for now, and isn't kept.
        stored = null;
        if (now.scene === CUSTOM) now.scene = OFF;
      }
    }
    kept = { ...now };
    write(kept);
    await apply();
  }
  /** Cancel (or any close but Save): as it was when the sheet opened. */
  function cancel() {
    const d = draft;
    if (!d) return;
    draft = null;
    dropThumb();
    now = { ...d.before };
    if (d.media !== undefined) mediaN++; // the picked one goes; the stored one comes back
    return apply();
  }

  async function picked(file, note) {
    const type = (file.type || '').toLowerCase();
    const say = (text) => {
      note.textContent = text;
      note.hidden = !text;
    };
    say('');
    let rec = null;
    if (type.startsWith('video/')) {
      if (file.size > MAX_VIDEO) return say(`That video is ${Math.round(file.size / 1048576)} MB; the most is ${MAX_VIDEO / 1048576} MB.`);
      if (!(await playable(file))) return say('This browser can’t play that video. Try MP4 (H.264) or WebM.');
      rec = { type, buf: await file.arrayBuffer() };
    } else if (type === 'image/gif') {
      if (file.size > MAX_GIF) return say(`That GIF is ${Math.round(file.size / 1048576)} MB; the most is ${MAX_GIF / 1048576} MB.`);
      rec = { type, buf: await file.arrayBuffer() };
    } else if (type.startsWith('image/')) {
      rec = await scaled(file);
      if (!rec) return say('This browser can’t read that picture.');
    } else {
      return say('Choose a picture, a GIF or a video.');
    }
    if (!draft) begin();
    draft.media = rec;
    mediaN++;
    return true;
  }
  function playable(file) {
    return new Promise((ok) => {
      const v = document.createElement('video');
      const url = URL.createObjectURL(file);
      let done = false;
      const end = (yes) => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        URL.revokeObjectURL(url);
        v.removeAttribute('src');
        ok(yes);
      };
      const timer = setTimeout(() => end(false), 8000);
      v.muted = true;
      v.preload = 'metadata';
      v.onloadedmetadata = () => end(v.videoWidth > 0);
      v.onerror = () => end(false);
      v.src = url;
    });
  }
  // Read as a data: address, not blob:: the hosted pages' CSP takes data: images only.
  async function scaled(file) {
    const url = await dataURL({ type: file.type, buf: await file.arrayBuffer() });
    if (!url) return null;
    return new Promise((ok) => {
      const im = new Image();
      im.onload = () => {
        const k = Math.min(1, 2400 / Math.max(im.width, im.height));
        const cv = document.createElement('canvas');
        cv.width = Math.max(1, Math.round(im.width * k));
        cv.height = Math.max(1, Math.round(im.height * k));
        cv.getContext('2d').drawImage(im, 0, 0, cv.width, cv.height);
        cv.toBlob(async (b) => ok(b ? { type: 'image/jpeg', buf: await b.arrayBuffer() } : null), 'image/jpeg', 0.85);
      };
      im.onerror = () => ok(null);
      im.src = url;
    });
  }

  function thumb(scene) {
    const box = document.createElement('div');
    box.className = 'bg-thumb';
    box.setAttribute('aria-hidden', 'true');
    dropThumb();
    if (scene === CUSTOM) {
      const rec = media();
      if (rec && rec.type.startsWith('video/')) {
        thumbURL = URL.createObjectURL(new Blob([rec.buf], { type: rec.type }));
        const v = document.createElement('video');
        v.muted = true;
        v.loop = true;
        v.playsInline = true;
        v.setAttribute('playsinline', '');
        v.src = thumbURL;
        box.append(v);
        if (!reduced()) v.play().catch(() => {});
      } else if (rec) {
        void dataURL(rec).then((url) => url && (box.style.backgroundImage = `url("${url}")`));
      }
    } else {
      box.style.backgroundImage = `url("${preview(scene)}")`;
    }
    return box;
  }

  /**
   * The Settings rows, in the page's own markup: `row(label, control, id)` makes one (the page's class and layout),
   * `redraw()` draws the sheet again (a row shows or hides), and `buttonClass` is the page's plain button.
   */
  function rows({ row, redraw, buttonClass = '' }) {
    // The stored picture: asked once, then the rows know whether there's one to remove.
    if (stored === undefined) void store.get().then((rec) => {
      stored = rec;
      if (rec) redraw();
    });
    const out = [];
    const sel = document.createElement('select');
    sel.id = 'setting-background';
    const option = (value, text) => {
      const o = document.createElement('option');
      o.value = value;
      o.textContent = text;
      return o;
    };
    sel.append(option(OFF, 'Off'));
    for (const group of [...new Set(SCENES.map(([, , g]) => g))]) {
      const g = document.createElement('optgroup');
      g.label = group;
      for (const [id, name, gg] of SCENES) if (gg === group) g.append(option(id, name));
      sel.append(g);
    }
    const yours = document.createElement('optgroup');
    yours.label = 'Yours';
    yours.append(option(CUSTOM, 'Your Picture or Video'));
    sel.append(yours);
    const scene = now.scene === CUSTOM && !media() ? OFF : now.scene;
    sel.value = scene;
    const file = document.createElement('input');
    file.type = 'file';
    file.accept = 'image/*,video/*';
    file.hidden = true;
    file.id = 'setting-background-file';
    const note = document.createElement('p');
    note.className = 'bg-note';
    note.setAttribute('role', 'status');
    note.hidden = true;
    const again = (id) => {
      redraw();
      document.getElementById(id)?.focus();
    };
    sel.addEventListener('change', () => {
      // Your Picture or Video with none yet: pick one first (the list stays as it was until you do).
      if (sel.value === CUSTOM && !media()) {
        sel.value = scene;
        file.click();
        return;
      }
      void change({ scene: sel.value }).then(() => again('setting-background'));
    });
    file.addEventListener('change', async () => {
      const f = file.files && file.files[0];
      file.value = '';
      if (!f) return;
      if ((await picked(f, note)) === true) {
        await change({ scene: CUSTOM });
        again('setting-background-pick');
      }
    });
    out.push(row('Background', sel, 'setting-background'));
    if (scene !== OFF) {
      out.push(row('Preview', thumb(scene), null, 'bg-preview-row'));
      const rain = document.createElement('input');
      rain.type = 'checkbox';
      rain.id = 'setting-background-rain';
      rain.className = 'switch';
      rain.setAttribute('role', 'switch');
      rain.checked = !!now.rain;
      rain.addEventListener('change', () => void change({ rain: rain.checked }));
      out.push(row('Rain', rain, 'setting-background-rain'));
    }
    const pick = document.createElement('button');
    pick.type = 'button';
    pick.id = 'setting-background-pick';
    if (buttonClass) pick.className = buttonClass;
    pick.textContent = media() ? 'Choose Another…' : 'Choose…';
    pick.addEventListener('click', () => file.click());
    const actions = document.createElement('span');
    actions.className = 'bg-actions';
    actions.append(pick);
    if (media()) {
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.id = 'setting-background-remove';
      remove.className = `${buttonClass} danger`.trim();
      remove.textContent = 'Remove';
      remove.addEventListener('click', () => {
        if (!draft) begin();
        draft.media = null;
        mediaN++;
        void change(now.scene === CUSTOM ? { scene: OFF } : {}).then(() => again('setting-background-pick'));
      });
      actions.append(remove);
    }
    actions.append(file);
    out.push(row('Your Picture or Video', actions, 'setting-background-pick'));
    out.push(note);
    return out;
  }

  /** Starts the page's background: `words()` names the signs (the page's visible pills). */
  function init(opts = {}) {
    if (typeof opts.words === 'function') words = opts.words;
    if (kept.scene !== OFF) void apply();
  }

  window.ShioriBackgrounds = {
    SCENES, OFF, CUSTOM, KEY,
    init, apply, change, begin, save, cancel, rows,
    state: () => ({ ...now }),
    kept: () => ({ ...kept }),
    get editing() { return !!draft; },
    get watching() { return watching(); },
    setWatching,
  };
})();
