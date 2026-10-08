# HisterKit and the shared client logic: traps and rules

Loaded when you work in `Packages/HisterKit`. The same logic lives in JavaScript in `patches/shiori/search-core.js` (twins, same tests). The project-wide rules, layout and build/test commands are in the root `CLAUDE.md`.

## Hister API quirks

- Every request needs `Origin: hister://`. `limit`, `sort` and `highlight`
  only work inside the JSON `query=` parameter. `*` with sort `date` is
  "recent". Snippets are HTML with `<mark>`. A malformed regexp returns zero
  results. Replies can hold raw control characters (decoding retries with
  them blanked). Query strings go through `URLComponents.setQueryItems` (it
  escapes "+").
- **Every Hister query ends in ` -label:vault -metadata.source:vault
  -type:local -metadata.source:code`** (`SearchText.forHister` /
  `S.histerText`, applied inside the clients): notes come from Kura, files
  only on the Files pill (a query with `type:local` keeps them), code only on
  the Code pill. There's no `NOT` and no exclude parameter; a negated field
  works with exact totals.
- The last typed word is searched as a prefix (`prefixLastWord`): Hister and
  Kura match whole words. Hister has no fuzzy search (`word~2` finds "2");
  respellings come from SearXNG's autocomplete (`Respelling.didYouMean` /
  `S.didYouMean`).
- Delete is by query: dry-run first, refuse unless exactly one page matches.
  `api/add` replaces a page's metadata (last writer wins) but keeps its label
  when the add has none.
- `url:` needs the exact stored URL; marks use one search, `url:(a|a/|b…)`;
  URLs with `( ) |` can't go in the alternation.
- Hister matches remembered opens by the exact query text, so search fields
  have autocapitalization and autocorrect off, and opens are recorded under
  the text as sent.
- Signing in (the apps, `HisterAccount`): the app holds a Hister session
  (`Cookie: hister=…`; HisterKit keeps cookies off and sets it) and the
  helper's `mhs_` id for the rooms; offered only while the helper says
  Hister has users. A 401/403 is `signedOut`, never retried; the outbox keeps
  its pages until sign-in. Test a sign-in only against a throwaway Hister
  with users (`HISTER_USERS_URL`).

## Notes, files, code, small web, AI

- **Notes come from Kura or from Hister**: Settings → Notes From,
  `notesSource` (`""` until chosen, `kura`, `hister`), per device, never sent
  to the account. Until chosen, Kura when one is set up, else Hister;
  `S.notesSource` / `NotesSource` and the Haiku and classic cores are twins on
  `scripts/notes-source-cases.json`.
  - From Kura (`/api/search`, `/api/recent`, `/api/note`, `/api/vaults`,
    `feed.xml`): every vault the filter picks, previews from `/api/note`
    (never cached for another vault).
  - From Hister: its `label:vault` documents, **the default vault's alone**
    (`S.histerNoteShown` / `Notes.histerNoteShown`: by address as Kura reads
    it, `/v/<vault>/` never), previews from Hister's `/api/preview`; no vault
    filter, no notes feed. Every other Hister query leaves notes out.
  - A note's chip names its vault (`Notes.vaultChip`); it opens in Obsidian
    (the vault name must match exactly) with its Kura page and Konbini card
    linked. Don't build folder, tag or backlink browsing into Shiori: link to Kura.
- **Save This Note's Links**: a note's outside links come from Kura's
  `external_links`, deduplicated, 200 a run (`SaveLinks` / `S.saveLinkRows`).
  Never a URL Hister holds (looked up before each save and again after
  redirects). http(s): downloaded here, skip rules hold in bulk, Save Anyway
  per link for a 406, `http://` tried as `https://` first, files never saved.
  `gemini://` and `gopher://` go through the small-web gateway's
  `POST /api/save` (202; 429 waited out).
- **Files** (the folders Hister watches, `type:local`): only the Files pill,
  only while Hister has some (`LocalFiles` / `S.filesQuery`, twins), opened
  from Hister's copy (`/api/file?id=<address>`); never recorded as opened,
  labeled or deleted; no AI (`AIContent.localFile`).
- **Code** (code-import's `metadata.source:code`): only the Code pill, while
  Hister has some (`CodeDocs` / `S.codeQuery`, twins). Filters are metadata
  terms, each one lowercase token (Hister can't match `/` in a value):
  `metadata.code_kind:`, `code_state:open`, `code_repo:<owner>__<repo>`,
  `code_private:true` (a string). Never labeled, deleted or folded by site; AI
  on the device only (`AIContent.code`). "code" is a reserved collection name.
- **Small Web** (Gemini and Gopher through the gateway) is searched on submit
  only. The web app's Add Page and share target save through
  `POST /smallweb/api/save` after `api.checkPageURL` refuses any note; the 202
  means queued: say "Saving…", never "Saved". `marks` are code-point offsets.
- **AI** (docs/ai.md): off by default, per device, keys in the Keychain.
  Engine order is fixed: Apple Intelligence, a local server, one cloud engine;
  another engine tries only after "couldn't answer". **A note never goes to a
  cloud engine**, a private vault's note to none (`AIContent.workNote`).
  Anthropic: never send `temperature` or a prefilled turn; JSON through
  `output_config.format`; a refusal is a 200 with `stop_reason: "refusal"`.
  OpenAI wants `max_completion_tokens`, local servers `max_tokens`. Apple
  Intelligence needs iOS/macOS 26 and an availability check before every
  request; its guardrails decline some ordinary pages (retry from the title
  and address); its context is small (read long pages in parts).

## Private vaults and the settings that follow the person

- **A note from a private vault** (address `/v/<vault>/n/…` and any page under
  `/v/<vault>/`; a vault Kura's `/api/vaults` doesn't mark `private: false`;
  `Notes.isPrivateNote` / `S.isPrivateNote`) never goes to Hister, any AI
  engine (on-device included), a cache, an export or a feed. Kura's config is
  the one switch (a shared vault is treated like the default); clients fail
  closed: until Kura answers, every vault but the default is private.
  **Before anything about another vault's note goes to Hister or a model,
  ask Kura afresh** (`isPrivateNoteNow`, 4 s); a path that can't wait (the
  share sheet, the sidebar, the address bar, the right-click menu, Summarize on
  the web) refuses every other vault's note. Read the address as Kura serves
  it: a leading `//` folded, `%XX` decoded once, dot segments resolved; a
  name that still isn't `[a-z0-9-]+`, or an address that can't be parsed, is
  private. The hosted page's `/kura/` passes only Kura's API, never its reader.
- **The settings that follow the person**: signed in, the shared ones (theme,
  appearance, text size, pills) and Shiori's own options (`shiori.*`) go to
  the account at the Hister sign-in helper (`/machiya/api/prefs`). Never an
  address, a sign-in, a token, an AI setting or this device's own (the preview
  pane, Use This Device's Size). Twins: `S.prefsSync` / `PrefsSync` on
  `scripts/prefs-sync-cases.json`; `scripts/prefs.schema.json` is a copy of
  [Machiya's contract](https://github.com/machiya-kobo/machiya/blob/main/docs/contracts/prefs.md)'s schema.
