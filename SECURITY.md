# Security

## Reporting a vulnerability

Please report security problems privately, not in a public issue: use
GitHub's private vulnerability reporting (this repository's Security tab,
then Report a vulnerability), with what you found, how to reproduce it, and
what it affects. You'll get an answer within a week, and a fix or a plan
before anything is disclosed.

## What's in scope

- **The apps** (iPhone, iPad, Mac), their share extensions and the Safari
  extension: anything that sends a page, a note or a setting somewhere the
  user didn't configure, or lets a web page act through the extension.
- **The previews:** pages are shown with scripts off and a strict content
  policy; a way around that is in scope.
- **The search page and web app:** cross-site requests reaching Hister
  through the host (it accepts same-origin writes only), script injection
  from results, titles or snippets.
- **Saving:** a way to make Shiori overwrite a page Hister already holds,
  or to save without the user asking.
- **Notes:** a note from a vault other than the default reaching Hister,
  an AI engine, a cache or an export.
- **AI:** keys leaving the device, or page text reaching an engine the user
  didn't switch on.
- **Signing in to Machiya:** the token (docs/signing-in.md) reaching any
  host but the configured rooms (Hister, SearXNG, a redirect, a lookalike),
  a web page or content script getting it, or it being stored somewhere
  other than the Keychain or Linux's config.
- **Shiori for Linux:** requests to hosts the configuration doesn't name.

Hister, SearXNG, Kura and the other servers Shiori talks to are separate
projects: report their problems to them.

## Supported versions

Fixes go into the latest release on the main branch.
