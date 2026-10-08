#!/usr/bin/env python3
"""Configures the shiori-web image when it starts: validates the settings in the
environment, stamps them into a copy of the built pages, and writes nginx's
config. Standard library only; nothing it writes leaves OUT.

    configure.py [--dist DIR] [--out DIR] [--scripts DIR] [--resolver ADDR]

The pages are built once, with their settings left as `__SHIORI_…__`
placeholders (scripts/stamp-env.py lists them). Here the same placeholders are
filled from this run's settings, so one image serves every deployment and no
page or route holds a setting it wasn't given. The settings are in
web/README.md ("In a container").

Required: SHIORI_HISTER_URL and SHIORI_SEARXNG_URL. Everything else is
optional, and an unset service is off: its routes answer 404 and the pages
leave its feature out.
"""
import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import ssl
import subprocess
import sys
import urllib.error
import urllib.request

REQUIRED = ("SHIORI_HISTER_URL", "SHIORI_SEARXNG_URL")
# Upstream services the host proxies to: setting -> the route they own.
OPTIONAL = {
    "SHIORI_KURA_URL": "Kura (notes)",
    "SHIORI_KONBINI_URL": "Konbini (cards)",
    "SHIORI_SMALLWEB_URL": "the small-web gateway",
    "SHIORI_FEED_URL": "shiori-feed (Subscribe)",
    "SHIORI_AI_URL": "shiori-ai (Summarize, AI Answer)",
}
UPSTREAM_RE = re.compile(r"^(https?)://([A-Za-z0-9._-]+|\[[0-9A-Fa-f:]+\])(?::([0-9]{1,5}))?/?$")
PUBLIC_RE = re.compile(r"^https?://[^\s'\"\\<>`{}|^\x00-\x1f\x7f]+$")
HOST_RE = re.compile(r"^[A-Za-z0-9._-]+(?::[0-9]{1,5})?$")
COOKIE_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
ROOM_ORIGIN_RE = re.compile(r"^https?://[A-Za-z0-9._-]+(:[0-9]{1,5})?$")
VERSION_RE = re.compile(r"^[A-Za-z0-9._+-]{1,64}$")
# The most of an upstream's answer the start-up probe reads: SearXNG's JSON for one search is often past 64 KiB.
PROBE_MAX = 2 << 20


class ConfigError(Exception):
    pass


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def upstream(env, name):
    """{base, scheme, host, hostport} for an upstream setting, or None when unset."""
    value = env.get(name, "").strip()
    if not value:
        return None
    m = UPSTREAM_RE.match(value)
    if not m:
        raise ConfigError(f"{name}: {value!r} is not an http(s)://host[:port] address (no path)")
    scheme, host, port = m.groups()
    if port is not None and not 0 < int(port) < 65536:
        raise ConfigError(f"{name}: the port {port} is out of range")
    hostport = host + (f":{port}" if port else "")
    return {"base": f"{scheme}://{hostport}", "scheme": scheme, "host": host, "hostport": hostport}


def public(env, name):
    """An address for people's browsers (links, the Rooms menu), or ''."""
    value = env.get(name, "").strip()
    if value and not PUBLIC_RE.match(value):
        raise ConfigError(f"{name}: {value!r} is not an http(s):// address")
    return value


def settings(env):
    """Everything this run needs, from the environment; ConfigError says what's wrong."""
    missing = [n for n in REQUIRED if not env.get(n, "").strip()]
    if missing:
        raise ConfigError(
            "shiori-web needs " + " and ".join(missing) + ".\n"
            "  SHIORI_HISTER_URL   where Hister is, from this container (for example http://hister:4433)\n"
            "  SHIORI_SEARXNG_URL  where SearXNG is (for example http://searxng:8080)\n"
            "Everything else is optional: see web/README.md, \"In a container\".")
    s = {"hister": upstream(env, "SHIORI_HISTER_URL"), "searxng": upstream(env, "SHIORI_SEARXNG_URL")}
    for name in OPTIONAL:
        s[name] = upstream(env, name)
    if env.get("SHIORI_HISTER_HOST", "").strip():
        host = env["SHIORI_HISTER_HOST"].strip()
        if not HOST_RE.match(host):
            raise ConfigError(f"SHIORI_HISTER_HOST: {host!r} is not a host name")
        s["hister"]["hostport"] = host
    # Sign-in: Machiya's helper (hister-login) when set, else Hister's own.
    login = upstream(env, "SHIORI_LOGIN_URL")
    s["login"] = login
    if login:
        auth = upstream(env, "SHIORI_LOGIN_AUTH_URL")
        if not auth:
            auth = {**login, "hostport": login["host"] + ":8081"}
            auth["base"] = f"{login['scheme']}://{auth['hostport']}"
        s["login_auth"] = auth
    s["signin"] = "hister-login" if login else "hister"
    cookie = env.get("SHIORI_ROOM_COOKIE", "__Host-machiya_sso_shiori").strip()
    if not COOKIE_RE.match(cookie):
        raise ConfigError(f"SHIORI_ROOM_COOKIE: {cookie!r} is not a cookie name")
    s["room_cookie"] = cookie
    s["tls_verify"] = env.get("SHIORI_UPSTREAM_TLS_VERIFY", "1").strip() != "0"
    # The two sites.
    for key, var, default_port, default_url in (("search", "SHIORI_SEARCH_PAGE_URL", "8080", "http://localhost:8080/"),
                                               ("app", "SHIORI_APP_URL", "8081", "http://localhost:8081/")):
        port = env.get(f"SHIORI_{key.upper()}_PORT", default_port).strip()
        if not port.isdigit() or not 1024 <= int(port) < 65536:
            raise ConfigError(f"SHIORI_{key.upper()}_PORT: {port!r} is not a port from 1024 up (the image runs without root)")
        url = env.get(var, "").strip() or default_url
        if not re.match(r"^https?://[A-Za-z0-9._-]+(:[0-9]{1,5})?/?$", url):
            raise ConfigError(f"{var}: {url!r} is not this site's http(s):// address (no path)")
        s[key] = {"port": int(port), "url": url.rstrip("/") + "/", "origin": url.rstrip("/")}
    if s["search"]["port"] == s["app"]["port"]:
        raise ConfigError("SHIORI_SEARCH_PORT and SHIORI_APP_PORT are the same")
    # Addresses people click: default to the upstream's own, which works when it is one a browser can reach.
    s["public"] = {
        "kura": public(env, "SHIORI_KURA_PUBLIC_URL") or (s["SHIORI_KURA_URL"] and env["SHIORI_KURA_URL"].strip()) or "",
        "konbini": public(env, "SHIORI_KONBINI_PUBLIC_URL") or (s["SHIORI_KONBINI_URL"] and env["SHIORI_KONBINI_URL"].strip()) or "",
        "kura_explicit": public(env, "SHIORI_KURA_PUBLIC_URL"),
        "konbini_explicit": public(env, "SHIORI_KONBINI_PUBLIC_URL"),
        "hister": public(env, "SHIORI_HISTER_PUBLIC_URL"),
        "searxng": public(env, "SHIORI_SEARXNG_PUBLIC_URL"),
    }
    s["rooms"] = env.get("SHIORI_ROOMS", "").strip()
    s["source"] = public(env, "SHIORI_SOURCE_URL")
    s["status"] = public(env, "SHIORI_STATUS_URL")
    s["vault"] = env.get("SHIORI_OBSIDIAN_VAULT", "").strip()
    s["frontends"] = env.get("SHIORI_FRONTENDS", "").strip()
    # The Hister release status.json names, when it isn't the one the image was built against.
    s["hister_version"] = env.get("SHIORI_HISTER_VERSION", "").strip()
    if s["hister_version"] and not VERSION_RE.match(s["hister_version"]):
        raise ConfigError(f"SHIORI_HISTER_VERSION: {s['hister_version']!r} is not a version (for example v0.20.0)")
    return s


def stamped(s):
    """The values for the pages' `__SHIORI_…__` placeholders (scripts/stamp-env.py)."""
    values = {
        "SHIORI_KURA_URL": s["public"]["kura"],
        "SHIORI_KONBINI_URL": s["public"]["konbini"],
        "SHIORI_SMALLWEB_URL": s["SHIORI_SMALLWEB_URL"] and s["SHIORI_SMALLWEB_URL"]["base"] or "",
        "SHIORI_OBSIDIAN_VAULT": s["vault"],
        "SHIORI_SOURCE_URL": s["source"],
        "SHIORI_FRONTENDS": s["frontends"],
        "SHIORI_AI": "1" if s["SHIORI_AI_URL"] else "",
        "SHIORI_FEED": "" if s["SHIORI_FEED_URL"] else "off",
        "SHIORI_SIGNIN": "hister" if s["signin"] == "hister" else "",
    }
    return {k: v for k, v in values.items() if v}


# --- nginx -----------------------------------------------------------------------------------------------------------

def tls(up, verify):
    if up["scheme"] != "https":
        return ""
    lines = f"    proxy_ssl_server_name on;\n    proxy_ssl_name {up['host']};\n"
    if verify:
        lines += ("    proxy_ssl_verify on;\n    proxy_ssl_verify_depth 3;\n"
                  "    proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;\n")
    return lines


def proxy(var, up, verify, host=None, cookie='""', extra="", hide_set_cookie=False, rewrite=""):
    """The directives shared by every proxied location (the upstream is a variable, so nginx resolves it per request
    and an upstream that is down never stops nginx from starting)."""
    # `set` first: a `rewrite … break` ends the rewrite directives, so a later `set` would never run.
    out = f"    set ${var} {up['base']};\n" + (f"    {rewrite}\n" if rewrite else "") + f"    proxy_pass ${var};\n"
    out += f"    proxy_set_header Host {host or up['hostport']};\n"
    out += f"    proxy_set_header Cookie {cookie};\n"
    if hide_set_cookie:
        out += "    proxy_hide_header Set-Cookie;\n"
    return out + tls(up, verify) + extra


def routes(s):
    """The routes both sites share, as production's shiori-routes.inc has them (web/README.md)."""
    verify = s["tls_verify"]
    login = s["signin"] == "hister-login"
    h = s["hister"]
    out = []
    add = out.append
    add('''types {
    text/html                 html;
    text/css                  css;
    text/javascript           js mjs;
    application/xml           xml;
    image/png                 png;
    application/json          json;
    text/markdown             md;
}
''')
    # The sign-in.
    if login:
        add(f'''# Hister's users, through Machiya's sign-in helper: every Hister-bound route asks it for Hister's session on
# nginx's OWN hop. The browser holds only this host's room cookie; Hister's session replaces the whole Cookie header
# and Hister's Set-Cookie is dropped, so neither reaches the browser. 200 = signed in, 401 = the page goes to the
# helper's sign-in, anything else = "sign-in unavailable".
location = /_machiya_auth {{
    internal;
    set $helper {s["login_auth"]["base"]};
    proxy_pass $helper/v1/nginx;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header X-Machiya-Session $machiya_room_sid;
    proxy_set_header X-Machiya-Room $site_origin;
{tls(s["login_auth"], verify)}}}
location ~ ^/machiya/(start|callback|signed-out|signout|api/prefs)$ {{
    set $helper_pub {s["login"]["base"]};
    proxy_pass $helper_pub;
    proxy_set_header Host $host;
{tls(s["login"], verify)}}}
location /machiya/static/ {{
    set $helper_pub {s["login"]["base"]};
    proxy_pass $helper_pub;
    proxy_set_header Host $host;
{tls(s["login"], verify)}}}
location /machiya/ {{
    return 404;
}}
''')
    else:
        add(f'''# Hister's own sign-in: with users on, Hister's `/auth` page (proxied below) signs the person in and its session
# cookie works on this origin. Only that one cookie ever goes to Hister; the feed and AI routes ask Hister's
# /api/profile whether the cookie is good (200 signed in or open, 401/403 not). With no users, Hister is open and so is
# this host.
location = /_hister_auth {{
    internal;
    set $hister {h["base"]};
    proxy_pass $hister/api/profile;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header Host {h["hostport"]};
    proxy_set_header Cookie $hister_cookie_own;
{tls(h, verify)}}}
location /machiya/ {{
    return 404;
}}
''')
    auth = "auth_request /_machiya_auth;" if login else "auth_request /_hister_auth;"
    # The built pages.
    add('''location = /healthz {
    default_type text/plain;
    add_header Cache-Control "no-store" always;
    return 200 "ok\\n";
}
location = / {
    try_files /index.html =404;
    add_header Cache-Control "no-cache" always;
    add_header Content-Security-Policy $shiori_csp always;
}
location = /index.html {
    add_header Cache-Control "no-cache" always;
    add_header Content-Security-Policy $shiori_csp always;
}
location = /_shiori/config.json {
    add_header Cache-Control "no-cache" always;
    add_header Content-Security-Policy $shiori_csp always;
}
location /_shiori/ {
    try_files $uri =404;
    add_header Cache-Control $shiori_cache always;
    add_header Content-Security-Policy $shiori_csp always;
}
''')
    # SearXNG (required).
    add("# SearXNG, /searx stripped.\nlocation /searx/ {\n"
        + proxy("searx", s["searxng"], verify, rewrite="rewrite ^/searx/(.*)$ /$1 break;") + "}\n")
    # The rooms: the cookie each one reads.
    if login:
        kura_cookie = '"__Host-machiya_sso_kura=$machiya_room_sid"'
        konbini_cookie = '"__Host-machiya_sso_konbini=$machiya_room_sid"'
    else:
        kura_cookie = konbini_cookie = "$machiya_session_cookie"
    if s["SHIORI_KONBINI_URL"]:
        add("# Konbini, /konbini stripped.\nlocation /konbini/ {\n"
            + proxy("konbini", s["SHIORI_KONBINI_URL"], verify, cookie=konbini_cookie, rewrite="rewrite ^/konbini/(.*)$ /$1 break;") + "}\n")
    else:
        add("location /konbini/ {\n    return 404;\n}\n")
    if s["SHIORI_KURA_URL"]:
        add("# Kura: only its JSON API and feed, never its reader pages (they would read as ordinary pages under /kura/).\n"
            "location ~ ^/kura/(api/(search|recent|note|vaults|prefs)|feed\\.xml)$ {\n"
            + proxy("kura", s["SHIORI_KURA_URL"], verify, cookie=kura_cookie, rewrite="rewrite ^/kura/(.*)$ /$1 break;") + "}\n")
    add("location /kura/ {\n    return 404;\n}\n")
    if s["SHIORI_SMALLWEB_URL"]:
        add("# The small-web gateway: its API only.\nlocation /smallweb/api/ {\n"
            + proxy("smallweb", s["SHIORI_SMALLWEB_URL"], verify, extra="    proxy_read_timeout 60s;\n", rewrite="rewrite ^/smallweb/(.*)$ /$1 break;") + "}\n")
    add("location /smallweb/ {\n    return 404;\n}\n")
    # shiori-ai, shiori-feed: signed in, and a clean answer when they're off (never Hister's UI, which answers any path 200).
    if s["SHIORI_AI_URL"]:
        ai = s["SHIORI_AI_URL"]
        add("# shiori-ai: Host = this site (its Origin check); Origin itself passes through untouched.\n"
            "location = /shiori/ai/status {\n    limit_except GET { deny all; }\n"
            + proxy("ai", ai, verify, host="$host") + "}\n"
            "location = /shiori/ai/healthz {\n" + proxy("ai", ai, verify, host="$host") + "}\n"
            "location /shiori/ai/ {\n    " + auth + "\n" + proxy("ai", ai, verify, host="$host")
            + "    error_page 502 503 504 = @shiori_ai_down;\n}\n"
            "location @shiori_ai_down {\n    default_type application/json;\n    add_header Cache-Control \"no-store\" always;\n"
            "    return 503 '{\"error\":\"unavailable\",\"message\":\"The summary service is not running.\"}';\n}\n")
    else:
        add("location /shiori/ai/ {\n    default_type application/json;\n    return 404 '{\"error\":\"not_found\",\"message\":\"No summary service is set up.\"}';\n}\n")
    if s["SHIORI_FEED_URL"]:
        feed = s["SHIORI_FEED_URL"]
        add("# shiori-feed.\nlocation = /shiori/healthz {\n" + proxy("feed", feed, verify) + "}\n"
            "location /shiori/ {\n    " + auth + "\n" + proxy("feed", feed, verify) + "}\n")
    else:
        add("location /shiori/ {\n    default_type application/json;\n    return 404 '{\"error\":\"not_found\",\"message\":\"No feed service is set up.\"}';\n}\n")
    # Hister: everything else.
    if login:
        add('''# Everything else is Hister, signed in by the helper.
location / {
    auth_request /_machiya_auth;
    auth_request_set $hister_cookie $upstream_http_x_hister_cookie;
''' + proxy("hister", h, verify, cookie="$hister_cookie", hide_set_cookie=True,
            extra="    proxy_set_header Connection $http_connection;\n    proxy_set_header Upgrade $http_upgrade;\n") + "}\n")
    else:
        add('''# Everything else is Hister, with its own session cookie (and nothing else of the browser's).
location / {
''' + proxy("hister", h, verify, cookie="$hister_cookie_own",
            extra="    proxy_set_header Connection $http_connection;\n    proxy_set_header Upgrade $http_upgrade;\n") + "}\n")
    return "\n".join(out)


MAPS = '''# Generated by shiori-web's configure.py when the container starts; edits are lost.
resolver {resolver} valid=30s ipv6=off;

map "" $shiori_csp {{
    default "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'";
}}
# A built asset asked for with its build version (?v=) never changes: a year, immutable. The page, the service worker
# and the manifest always revalidate.
map $request_uri $shiori_cache {{
    default                 "no-cache";
    "~^/_shiori/[^?]*\\?(?:[^#]*&)?v="   "public, max-age=31536000, immutable";
    ~^/_shiori/             "max-age=300";
}}
# The access log has no query string: searches stay out of logs.
map $request_uri $logpath {{
    ~^(?<p>[^?]*) $p;
    default       "-";
}}
log_format nosearch '$remote_addr [$time_local] "$request_method $logpath" $status $body_bytes_sent';
{signin_maps}
proxy_http_version 1.1;
proxy_read_timeout 120s;
proxy_buffering off;
client_max_body_size 40m;
'''

LOGIN_MAPS = '''
# This host's room session: only a well-formed mhr_ id is picked from the browser's cookies.
map $http_cookie $machiya_room_sid {{
    "~(?:^|;\\s*){cookie}=(?<v>mhr_[A-Za-z0-9_-]{{43}})" $v;
    default "";
}}
'''

OWN_MAPS = '''
# Hister's own session cookie, and the rooms' session cookie: the only cookies that go to anything.
map $http_cookie $hister_cookie_own {
    "~(?:^|;\\s*)hister=(?<v>[A-Za-z0-9_=.%+-]{8,256})" "hister=$v";
    default "";
}
map $http_cookie $machiya_session_cookie {
    "~(?:^|;\\s*)machiya_session=(?<v>[A-Za-z0-9_=.%+-]{8,512})" "machiya_session=$v";
    default "";
}
'''


def sites(s, resolver, root):
    maps = MAPS.format(resolver=resolver, signin_maps=(
        LOGIN_MAPS.format(cookie=s["room_cookie"]) if s["signin"] == "hister-login" else OWN_MAPS))
    body = routes(s)
    out = [maps]
    for key in ("search", "app"):
        site = s[key]
        extra = ""
        if key == "search":
            extra = '''    location = /_shiori/opensearch.xml {
        default_type application/opensearchdescription+xml;
        types { }
        add_header Cache-Control "max-age=300" always;
    }
'''
        else:
            extra = '''    location = /sw.js {
        default_type text/javascript;
        types { }
        add_header Cache-Control "no-cache" always;
        add_header Content-Security-Policy $shiori_csp always;
        add_header Service-Worker-Allowed "/" always;
    }
    location = /manifest.webmanifest {
        default_type application/manifest+json;
        types { }
        add_header Cache-Control "no-cache" always;
    }
'''
        indented = "\n".join(("    " + line if line.strip() else line) for line in body.splitlines())
        out.append(f"""server {{
    access_log /dev/stdout nosearch;
    listen {site['port']};
    server_name _;
    set $site_origin {site['origin']};
    root {root}/{key};
{extra}{indented}
}}
""")
    return "\n".join(out)


# --- the pages ---------------------------------------------------------------------------------------------------------

def stamp_pages(s, dist, out, scripts):
    stamp_env = load("stamp_env", os.path.join(scripts, "stamp-env.py"))
    values_env = stamped(s)
    values = stamp_env.values_from(values_env)
    www = os.path.join(out, "www")
    shutil.rmtree(www, ignore_errors=True)
    shutil.copytree(dist, www)
    rooms_env = {k: v for k, v in {
        "SHIORI_ROOMS": s["rooms"],
        "SHIORI_KURA_URL": s["public"]["kura_explicit"],
        "SHIORI_KONBINI_URL": s["public"]["konbini_explicit"],
        "SHIORI_SERVER_URL": s["public"]["hister"],
        "SHIORI_SEARXNG_URL": s["public"]["searxng"],
    }.items() if v}
    files = {"search": ["index.html", "_shiori/web-shim.js", "_shiori/search.js", "_shiori/search-core.js"],
             "app": ["index.html", "_shiori/app.js", "_shiori/search-core.js"]}
    digest = hashlib.sha256(json.dumps([values, rooms_env, s["status"]], sort_keys=True).encode()).hexdigest()[:8]
    for key, names in files.items():
        for name in names:
            path = os.path.join(www, key, name)
            with open(path, encoding="utf-8") as f:
                text = f.read()
            try:
                text = stamp_env.stamp(text, values)
            except ValueError as e:
                raise ConfigError(str(e))
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
            if name.endswith(("search.js", "app.js")):
                run = subprocess.run([sys.executable, os.path.join(scripts, "rooms-stamp.py"), path],
                                     env={**os.environ, **{k: "" for k in ("SHIORI_ROOMS", "SHIORI_KURA_URL", "SHIORI_KONBINI_URL",
                                                                            "SHIORI_SERVER_URL", "SHIORI_SEARXNG_URL")}, **rooms_env},
                                     capture_output=True, text=True)
                if run.returncode:
                    raise ConfigError(run.stderr.strip() or "rooms-stamp failed")
        index = os.path.join(www, key, "index.html")
        run = subprocess.run([sys.executable, os.path.join(scripts, "status-link.py"), index, s["status"]], capture_output=True, text=True)
        if run.returncode:
            raise ConfigError(run.stderr.strip())
        # The build's version in every address, then this run's settings with it: a browser that holds an older copy
        # (assets are cached for a year) never runs a page with settings that aren't this run's.
        with open(index, encoding="utf-8") as f:
            m = re.search(r"\?v=([A-Za-z0-9._]+)", f.read())
        if m:
            old = m.group(1)
            new = f"{old}-{digest}"
            for dirpath, _, filenames in os.walk(os.path.join(www, key)):
                for fn in filenames:
                    if not fn.endswith((".html", ".js", ".css")):
                        continue
                    p = os.path.join(dirpath, fn)
                    with open(p, encoding="utf-8") as f:
                        text = f.read()
                    changed = text.replace(f"v={old}", f"v={new}").replace(f"shiori-app-{old}", f"shiori-app-{new}")
                    if changed != text:
                        with open(p, "w", encoding="utf-8") as f:
                            f.write(changed)
        # The search page's OpenSearch description names the page's own address.
        osx = os.path.join(www, key, "_shiori", "opensearch.xml")
        if os.path.exists(osx):
            with open(osx, encoding="utf-8") as f:
                text = f.read()
            with open(osx, "w", encoding="utf-8") as f:
                f.write(text.replace("http://shiori-web.invalid/", s["search"]["url"]))
        with open(os.path.join(www, key, "_shiori", "config.json"), "w", encoding="utf-8") as f:
            json.dump(report(s), f, indent=2)
            f.write("\n")
        # status.json (scripts/status-json.py): the Hister release this run names, when one is set.
        status = os.path.join(www, key, "_shiori", "status.json")
        if s["hister_version"] and os.path.exists(status):
            with open(status, encoding="utf-8") as f:
                doc = json.load(f)
            doc["hister"] = s["hister_version"]
            with open(status, "w", encoding="utf-8") as f:
                json.dump(doc, f)
                f.write("\n")


def report(s):
    """What this run serves, for /_shiori/config.json and the start-up line: modes and which services are on, plus the
    addresses the pages link. No upstream address that isn't already in the page, no secret."""
    return {
        "signin": s["signin"],
        "services": {"hister": True, "searxng": True,
                     **{name.removeprefix("SHIORI_").removesuffix("_URL").lower(): bool(s[name]) for name in OPTIONAL}},
        "sites": {"search": s["search"]["url"], "app": s["app"]["url"]},
        "links": {k: v for k, v in {"kura": s["public"]["kura"], "konbini": s["public"]["konbini"],
                                    "source": s["source"], "status": s["status"]}.items() if v},
    }


def resolver_from(path="/etc/resolv.conf"):
    try:
        with open(path) as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 2 and parts[0] == "nameserver" and ":" not in parts[1]:
                    return parts[1]
    except OSError:
        pass
    return "127.0.0.11"


def startup_line(s):
    on = [label for name, label in OPTIONAL.items() if s[name]]
    off = [label for name, label in OPTIONAL.items() if not s[name]]
    signin = ("Machiya's sign-in helper" if s["signin"] == "hister-login"
              else "Hister's own (the pages open while Hister has no users)")
    return "\n".join([
        f"shiori-web: search page :{s['search']['port']}, web app :{s['app']['port']}",
        f"  Hister {s['hister']['base']}, SearXNG {s['searxng']['base']}",
        f"  on:  {', '.join(on) or 'nothing else'}",
        f"  off: {', '.join(off) or 'nothing'}",
        f"  sign-in: {signin}",
    ])


def fetch(up, path, verify, timeout=4):
    """(status, content type, body) of a GET to an upstream, the body cut at PROBE_MAX + 1 bytes; status None when
    nothing answered."""
    ctx = None
    if up["scheme"] == "https":
        ctx = ssl.create_default_context()
        if not verify:
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(up["base"] + path, headers={"Accept": "application/json", "User-Agent": "shiori-web"})
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            return r.status, r.headers.get_content_type(), r.read(PROBE_MAX + 1)
    except urllib.error.HTTPError as e:
        return e.code, "", b""
    except (OSError, ValueError):
        return None, "", b""


def json_answer(ctype, body):
    """Whether an answer is JSON: parsed whole when it fits in PROBE_MAX, else known by its content type."""
    if len(body) > PROBE_MAX:
        return ctype == "application/json"
    try:
        json.loads(body.decode("utf-8", "replace"))
        return True
    except ValueError:
        return False


def probe(s):
    """Says plainly what's wrong with Hister or SearXNG, once, at start. Never stops the start: they may still be
    coming up, and the pages say the same thing (and recover) when they're asked."""
    lines = []
    status, _, _ = fetch(s["hister"], "/", s["tls_verify"])
    if status is None:
        lines.append(f"  ! Hister isn't answering at {s['hister']['base']} yet: check SHIORI_HISTER_URL, and that Hister is running.")
    status, ctype, body = fetch(s["searxng"], "/search?q=shiori&format=json", s["tls_verify"])
    if status is None:
        lines.append(f"  ! SearXNG isn't answering at {s['searxng']['base']} yet: check SHIORI_SEARXNG_URL, and that SearXNG is running.")
    elif status == 403:
        lines.append("  ! SearXNG doesn't allow JSON results: add `json` to `search: formats:` in its settings.yml "
                     "(formats: [html, json]) and restart it.")
    elif status >= 400:
        lines.append(f"  ! SearXNG answered {status} to a JSON search: check its settings.")
    elif not json_answer(ctype, body):
        lines.append("  ! SearXNG's answer to a JSON search wasn't JSON: check `formats` in its settings.yml.")
    return lines or ["  Hister and SearXNG answer."]


def main():
    ap = argparse.ArgumentParser()
    here = os.path.dirname(os.path.abspath(__file__))
    ap.add_argument("--dist", default="/opt/shiori/dist")
    ap.add_argument("--out", default="/tmp/shiori")
    ap.add_argument("--scripts", default="/opt/shiori/scripts")
    ap.add_argument("--resolver", default="")
    ap.add_argument("--check", action="store_true", help="validate the settings and print the start-up line only")
    ap.add_argument("--no-probe", action="store_true", help="don't ask Hister and SearXNG whether they answer")
    args = ap.parse_args()
    try:
        s = settings(os.environ)
        if not args.check:
            os.makedirs(args.out, exist_ok=True)
            stamp_pages(s, args.dist, args.out, args.scripts)
            with open(os.path.join(args.out, "sites.conf"), "w", encoding="utf-8") as f:
                f.write(sites(s, args.resolver or resolver_from(), os.path.join(args.out, "www")))
    except ConfigError as e:
        sys.stderr.write(f"shiori-web: {e}\n")
        return 2
    print(startup_line(s), flush=True)
    if not args.no_probe:
        print("\n".join(probe(s)), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
