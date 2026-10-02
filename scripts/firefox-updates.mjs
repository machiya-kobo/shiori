#!/usr/bin/env node
// Firefox's update manifest for a signed release (docs/firefox-plan.md,
// phase 5). Firefox fetches it from the add-on's update_url
// (releases/latest/download/updates.json) and installs the version it
// names when it's newer. The ID, version and floor come from the built
// manifest, so they can't disagree with the build; the hash is the signed
// file's, so Firefox installs only that file.
// Usage: firefox-updates.mjs <built manifest.json> <signed .xpi> <its download URL> <output>

import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export function updatesManifest(manifest, xpi, link) {
  const gecko = (manifest.browser_specific_settings || {}).gecko || {};
  if (!gecko.id) throw new Error('the manifest has no add-on ID');
  if (!manifest.version) throw new Error('the manifest has no version');
  if (!/^https:\/\//.test(link)) throw new Error('the update link must be https');
  const update = {
    version: manifest.version,
    update_link: link,
    update_hash: 'sha256:' + createHash('sha256').update(xpi).digest('hex'),
  };
  if (gecko.strict_min_version) {
    update.applications = { gecko: { strict_min_version: gecko.strict_min_version } };
  }
  return { addons: { [gecko.id]: { updates: [update] } } };
}

function main(argv) {
  const [, , manifestPath, xpiPath, link, outPath] = argv;
  if (!manifestPath || !xpiPath || !link || !outPath) {
    console.error('usage: firefox-updates.mjs <manifest.json> <signed.xpi> <download URL> <output>');
    process.exit(2);
  }
  const updates = updatesManifest(JSON.parse(readFileSync(manifestPath, 'utf8')), readFileSync(xpiPath), link);
  writeFileSync(outPath, JSON.stringify(updates, null, 2) + '\n');
  console.error(`wrote ${outPath}`);
}

if (fileURLToPath(import.meta.url) === process.argv[1]) {
  main(process.argv);
}
