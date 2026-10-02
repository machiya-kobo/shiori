# AI in Shiori

Optional AI, **off by default**, bring your own: you pick which engines may
run, on-device first and the cloud last. Four jobs:

1. **Summaries**: Summarize in the apps (iPhone, iPad, Mac), and on the
   hosted search page and web app through a server endpoint.
2. **Label suggestions**: Edit Label opens with the AI's first and second
   choices, applied only on a tap.
3. **Label New Pages**: classify unlabelled pages, automatically when the
   engine is sure, as a suggestion otherwise.
4. **Keep Collections Current**: put labels no collection names into the
   one they belong in, and propose new collections (always asked).

Plus an **AI Answer** for a web search, on request only.

Everything is set on **Settings → AI**. API keys live in the Keychain, never
in settings files. AI settings are per device, and a web page can never
turn AI on (they're not in `SharedSettings.apply`'s whitelist).

## Engines

- **Apple Intelligence** (Foundation Models), iOS/macOS 26 and later,
  gated by `canImport`, `#available` and `availability == .available`. The
  app's floor stays 18.6/15; older systems just don't list it. Context is
  4,096 tokens, so long pages are read in parts and summarized from their
  notes. Its guardrails decline some ordinary pages; a declined page is
  retried from its title, site and address alone.
- **A local server** (any OpenAI-compatible server: Ollama, LM Studio).
- **One cloud engine**: Anthropic (Messages API) or OpenAI (chat
  completions), raw HTTPS, no SDK. Default models: Claude Sonnet 5.5
  (`claude-sonnet-5-5`) and GPT-6 Luna (`gpt-6-luna`); Test Connection
  lists the provider's models and offers the closest when the chosen one
  isn't there.

**The order is fixed:** Apple Intelligence, the local server, then the
cloud engine. Another engine tries only after "couldn't answer" (no
network, 408/429/5xx, a refused key, unavailable, declined). A 400 or an
unreadable reply is shown, not routed around. A result that fell through
says so ("Summarized by Claude").

## Code

- `Packages/ShioriAI`: `AnthropicClient`, `OpenAICompatibleClient`,
  `EngineChain`, `AIReachability`, `ConnectionTest`, the prompts and
  schemas, `LabelClassifier`, `CollectionPlanner`, `Summarizer`,
  `SearchAnswerer`. No FoundationModels import, so it builds and tests
  anywhere. `ShioriAIOnDevice` holds the Apple Intelligence engine, shared
  by the app and the test tool.
- `Shiori/AI/`: `AIKeychain`, `AISettingsPage`, `AutoLabeller`,
  `CollectionKeeper`, `LabelHints`. Only the app links ShioriAI; the
  extensions never do.
- Keys: one Keychain item per provider (service `<app id>.ai`). On iOS
  they're `AfterFirstUnlockThisDeviceOnly`; on the Mac they use the login
  keychain (the data-protection one needs an application-identifier
  entitlement a free team's Mac build lacks).

## Summaries

- The input is the preview's readable HTML as plain text, converted off
  the main actor. The page's language is named in the prompt.
- The style is short: one sentence of at most 25 words, then two to four
  points of at most 12 words each. A hard `tidy` keeps the on-device model
  to that.
- Cached per page (url + Hister's `updated`) in the app's Caches, 300 at
  most, never in Hister (its metadata is last-writer-wins).
- **On the web** the hosted pages can use a companion service on the
  Hister host (`/shiori/ai/*`, same origin only). It is not part of this
  repository; without it the pages simply don't offer Summarize or AI
  Answer. Its contract, for anyone who builds one: `GET /shiori/ai/status`
  → `{enabled, answer, engine, model, remaining}`; `POST
  /shiori/ai/summarize {url, refresh}` → `{summary, engine, model,
  partial, cached, updated}` (web pages only, never notes); `POST
  /shiori/ai/answer {q, refresh}` → `{answer, sources: [{n, title, url}],
  engine, model, cached}`, answered from the web results' snippets. Errors
  are JSON `{error, message}`: 400 `bad_request`, 403 `forbidden` or
  `note`, 404 `not_indexed` or `not_found`, 422 `empty` or `no_results`,
  429 `cap` (with Retry-After), 502 `engine` or `declined`, 503
  `unavailable`, 504 `searx` (`web/dev-server.py`'s `AI_STUB=1` mimics
  them).

## Labels

- The answer is constrained to the label list (a JSON-schema enum on every
  engine; `DynamicGenerationSchema` on Apple Intelligence, 26.4 and later).
- `LabelHints` gives the model two example titles per label, the labels on
  the user's other pages from the same site, and the user's labelled pages
  most like this one (`NeighbourQuery`), plus their recent corrections.
- **Label New Pages** (off by default, meant for one device): the newest
  unlabelled pages, 25 a run, a daily cap of 200 cloud requests. A label is
  applied when Anthropic is sure, or when Anthropic and Apple Intelligence
  agree; everything else waits in Suggested Labels with the reason. Every
  applied label is logged with Undo, and a label undone twice is held for
  review. The page's label is re-read before writing.
- **Never Suggested** lists labels the AI never applies or suggests (the
  build's `SHIORI_AI_NEVER_SUGGEST` by default). `vault` and the build's
  `SHIORI_AI_NOT_TOPICS` are never offered.

## Collections

Collections are Hister's aliases: `@media: label:(film|music)`.
Shiori edits them only through Keep Collections Current, and only:

- `@`-keywords (only those are collections); a plain alias is the user's
  own query;
- values that are purely `label:a` or `label:(a|b|…)`;
- never a name an alias already has (with or without "@"), never `notes`
  or `pages`, never the build's `SHIORI_RESERVED_COLLECTIONS`.

A label is placed automatically on the same terms as a page's label;
otherwise it's asked. New collections are always asked. Every change goes
through Hister's `api/add_alias` / `api/delete_alias`, logged with the
previous value for Undo.

## The AI Answer

On request only (nothing is asked until the section is opened): the server
runs the search on SearXNG and answers from the top results' snippets,
citing them as [n]. The apps do the same on the device's engines with the
results already on screen. On Apple Intelligence it answers in two
sentences, no points: its direct answers were right, its extra points were
where it went wrong.

## Safety and privacy

- One master switch, off; each engine off until configured; each feature
  has its own switch. Turning AI off stops the labeller at once.
- **A note never goes to a cloud engine**, and a note from a private
  vault (any but the default, unless Kura marks it shared) never goes to
  any engine, on-device included. Kura is asked afresh before each use of
  another vault's note; no answer means private.
  `EngineChain.eligible(for:)` enforces both by the content's kind, so no
  caller has to remember.
- Skip-listed and sensitive pages never reach Hister, so never reach the AI.
- Page text is quoted data in the user turn, never instructions, and the
  output is constrained to a schema.
- Logs name counts and engines, never page text or keys.

## Measuring

`swift run -c release shiori-ai-eval --server <Hister URL>` in
`Packages/ShioriAI` scores the classifier against your own labelled
pages (read-only; it prints counts and the misses' titles). Options:
`--engine anthropic|openai` (key in `ANTHROPIC_API_KEY` / `OPENAI_API_KEY`,
or the login keychain, service `shiori-ai-eval`), `--no-hints`,
`--agreement`, `--gates`, `--unlabelled N` (a dry run of Label New Pages),
`--collections`, `--url <page>`, and `--searx URL --answer "…"`.

How well each engine does depends on your own pages and labels, and on the
engine: run `shiori-ai-eval` against your library to see. It reports, per
engine, how often the first choice is right, how often the right label is
in the top two, and how often a "high" answer is right. Only an engine
whose "high" answers you've measured as reliable should apply labels on
its own.

Shiori trusts only Anthropic to apply labels on its own.
