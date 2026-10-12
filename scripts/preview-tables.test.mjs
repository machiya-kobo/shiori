// A wide table in a preview fits the screen, the same in the apps
// (PreviewWebView.swift), the web app (app.js) and the search page
// (search.js): smaller text, addresses and code may break anywhere, words
// stay whole, and only a table whose words alone don't fit scrolls
// sideways, inside itself.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8').replace(/\s+/g, '');
const previews = {
  apps: read('Shiori/PreviewWebView.swift'),
  'web app': read('web/app/app.js'),
  'search page': read('patches/shiori/search.js'),
};

for (const [where, css] of Object.entries(previews)) {
  test(`${where}: a wide table fits, words whole`, () => {
    assert.match(css, /table\{border-collapse:collapse;display:block;overflow-x:auto;font-size:\.?0?\.875em;?\}/);
    assert.match(css, /td,th\{border:1pxsolid[^;]+;padding:4px6px;overflow-wrap:break-word;?\}/);
    assert.match(css, /tda,tdcode,tha,thcode\{overflow-wrap:anywhere;?\}/);
    assert.match(css, /@media\(max-width:480px\)\{table\{font-size:0?\.8em;?\}td,th\{padding:3px4px;?\}\}/);
    // Anywhere in every cell let a column shrink to a character wide.
    assert.doesNotMatch(css, /td,th\{[^}]*overflow-wrap:anywhere/);
  });
}
