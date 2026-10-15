// Basic Search in nginx (njs, the QuickJS engine): web/basic.mjs renders, this hands it the request and this host's
// own routes. Each search goes back through nginx on loopback, a full request, so the routes' sign-in (auth_request,
// which nginx never runs for a subrequest) and their cookie rules apply exactly as for the pages. Only the browser's
// Cookie travels with it; nothing is logged or kept. The Dockerfile puts search-core.js beside this as a module.
import S from 'search-core.mjs';
import { basic } from 'basic.mjs';

async function page(r) {
  const port = r.variables.server_port;
  const cookie = r.headersIn.Cookie || '';
  const get = async (path) => {
    const headers = { Accept: 'application/json' };
    if (cookie) headers.Cookie = cookie;
    const reply = await ngx.fetch(`http://127.0.0.1:${port}${path}`, { headers });
    return { status: reply.status, body: await reply.text() };
  };
  try {
    const out = await basic(
      { args: r.variables.args || '', cookie, referer: r.headersIn.Referer || '', host: r.headersIn.Host || '' },
      {
        S,
        get,
        site: {
          kura: r.variables.basic_kura === '1',
          signIn: r.variables.basic_signin || '',
          kuraSignIn: r.variables.basic_kura_signin || '',
          self: r.variables.basic_self || '/',
        },
      },
    );
    // A redirect's text is its address in njs (r.return sets Location from it).
    if (out.status >= 300 && out.status < 400) return r.return(out.status, out.headers.Location);
    for (const [name, value] of Object.entries(out.headers)) r.headersOut[name] = value;
    r.return(out.status, out.body);
  } catch (e) {
    r.error(`basic search: ${e && e.message}`);
    r.headersOut['Content-Type'] = 'text/plain; charset=utf-8';
    r.return(500, 'Basic Search failed.\n');
  }
}

export default { page };
