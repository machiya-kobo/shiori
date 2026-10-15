// Basic Search for web/dev-server.py: renders one /basic request with web/basic.mjs under Node, as the shiori-web
// image's njs does. The request comes as JSON on stdin ({args, cookie, referer, host, port, kura}); the answer
// ({status, headers, body}) goes to stdout. Its searches go back through the dev server on 127.0.0.1:<port>.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import { basic } from '../web/basic.mjs';

const context = {};
vm.runInNewContext(readFileSync(fileURLToPath(new URL('../patches/shiori/search-core.js', import.meta.url)), 'utf8'), context);
const S = context.ShioriSearch;

const req = JSON.parse(readFileSync(0, 'utf8'));
const get = async (path) => {
  const headers = { Accept: 'application/json' };
  if (req.cookie) headers.Cookie = req.cookie;
  const reply = await fetch(`http://127.0.0.1:${req.port}${path}`, { headers, redirect: 'manual' });
  return { status: reply.status, body: await reply.text() };
};
const out = await basic(req, { S, get, site: { kura: !!req.kura, signIn: '', kuraSignIn: '', self: `http://${req.host || `127.0.0.1:${req.port}`}/` } });
process.stdout.write(JSON.stringify(out));
