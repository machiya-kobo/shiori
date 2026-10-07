/*
 * The classic core's tests, run on the host (cc) by scripts/classic.test.mjs:
 *   make -C classic/tests test
 */
#include <stdio.h>
#include <string.h>

#include "../core/http.h"
#include "../core/json.h"
#include "../core/query.h"
#include "../core/results.h"
#include "../core/config.h"
#include "../core/roman.h"
#include "../core/notetext.h"
#include "vectors.h"

static int passed, failed;

#define CHECK(cond) do { if (cond) passed++; else { failed++; printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)

/* The token kinds of a whole document, as a compact string ({}[]ksn tfz, E for an error). */
static void kinds(const char *doc, char *out)
{
	JsonReader r;
	int t, n = 0;
	static const char map[] = "{}[]ksntfz";

	json_init(&r, doc, (long) strlen(doc));
	for (;;) {
		t = json_next(&r);
		if (t == JSON_EOF)
			break;
		if (t == JSON_ERROR) {
			out[n++] = 'E';
			break;
		}
		out[n++] = map[t - 1];
		if (n > 60)
			break;
	}
	out[n] = '\0';
}

static void test_json_tokens(void)
{
	char k[80];

	kinds("{}", k); CHECK(strcmp(k, "{}") == 0);
	kinds("[]", k); CHECK(strcmp(k, "[]") == 0);
	kinds(" [ ] ", k); CHECK(strcmp(k, "[]") == 0);
	kinds("{\"a\": [1, \"x\", true, false, null, {}, []]}", k); CHECK(strcmp(k, "{k[nstfz{}[]]}") == 0);
	kinds("{\"a\":1,\"b\":{\"c\":[]}}", k); CHECK(strcmp(k, "{kn k{k[]}}") != 0 && strcmp(k, "{knk{k[]}}") == 0);
	kinds("-12.5e3", k); CHECK(strcmp(k, "n") == 0);
	kinds("\"\\\"q\\\"\"", k); CHECK(strcmp(k, "s") == 0);
	/* errors */
	kinds("{\"a\":1,}", k); CHECK(strchr(k, 'E') != NULL);
	kinds("[1,]", k); CHECK(strchr(k, 'E') != NULL);
	kinds("[1 2]", k); CHECK(strchr(k, 'E') != NULL);
	kinds("{\"a\" 1}", k); CHECK(strchr(k, 'E') != NULL);
	kinds("{1:2}", k); CHECK(strchr(k, 'E') != NULL);
	kinds("[}", k); CHECK(strchr(k, 'E') != NULL);
	kinds("{]", k); CHECK(strchr(k, 'E') != NULL);
	kinds("\"open", k); CHECK(strcmp(k, "E") == 0);
	kinds("\"a\nb\"", k); CHECK(strcmp(k, "E") == 0);
	kinds("tru", k); CHECK(strcmp(k, "E") == 0);
	kinds("{} {}", k); CHECK(strcmp(k, "{}E") == 0);
	kinds("", k); CHECK(strcmp(k, "E") == 0);
	kinds("[[[[[[[[[[[[[[[[[[[[[[[[[1]]]]]]]]]]]]]]]]]]]]]]]]]", k); CHECK(strchr(k, 'E') != NULL);   /* deeper than 24 */
}

static void test_json_strings(void)
{
	JsonReader r;
	char out[64];
	const char *doc = "[\"caf\\u00e9 \\ud83d\\ude00 \\\"q\\\" \\\\ \\/ \\n\", \"Ch\xC5\x8D" "chin\", \"\\ud800x\", \"abcdef\"]";

	json_init(&r, doc, (long) strlen(doc));
	CHECK(json_next(&r) == JSON_ARRAY);
	CHECK(json_next(&r) == JSON_STRING);
	json_string(&r, out, sizeof(out));
	CHECK(strcmp(out, "caf\xC3\xA9 \xF0\x9F\x98\x80 \"q\" \\ / \n") == 0);
	CHECK(json_next(&r) == JSON_STRING);
	json_string(&r, out, sizeof(out));
	CHECK(strcmp(out, "Ch\xC5\x8D" "chin") == 0);
	/* a short buffer cuts at a character boundary */
	CHECK(json_string(&r, out, 4) == 2 && strcmp(out, "Ch") == 0);
	CHECK(json_next(&r) == JSON_STRING);
	json_string(&r, out, sizeof(out));
	CHECK(strcmp(out, "\xEF\xBF\xBDx") == 0);   /* a lone surrogate is U+FFFD */
	CHECK(json_next(&r) == JSON_STRING);
	CHECK(json_string(&r, out, 3) == 2 && strcmp(out, "ab") == 0);
	CHECK(json_next(&r) == JSON_ARRAY_END);
	CHECK(json_next(&r) == JSON_EOF);
}

static void test_json_walk(void)
{
	/* the shape of a Hister reply: find documents[].title, skipping the rest */
	const char *doc = "{\"total\": 45, \"took\": {\"ms\": [1,2]}, \"documents\": ["
		"{\"url\": \"https://a.example/\", \"title\": \"A\", \"metadata\": {\"source\": \"shiori\"}},"
		"{\"title\": \"B\", \"url\": \"https://b.example/\"}], \"page_key\": \"p2\"}";
	JsonReader r;
	int t, rows = 0;
	long total = 0;
	char title[16], key[8] = "";

	json_init(&r, doc, (long) strlen(doc));
	CHECK(json_next(&r) == JSON_OBJECT);
	while ((t = json_next(&r)) == JSON_KEY) {
		if (json_is(&r, "total")) {
			CHECK(json_next(&r) == JSON_NUMBER);
			total = json_long(&r);
		} else if (json_is(&r, "documents")) {
			CHECK(json_next(&r) == JSON_ARRAY);
			while ((t = json_next(&r)) == JSON_OBJECT) {
				while ((t = json_next(&r)) == JSON_KEY) {
					if (json_is(&r, "title")) {
						CHECK(json_next(&r) == JSON_STRING);
						json_string(&r, title, sizeof(title));
						rows++;
					} else {
						t = json_skip(&r, JSON_KEY);
					}
				}
				CHECK(t == JSON_OBJECT_END);
			}
			CHECK(t == JSON_ARRAY_END);
		} else if (json_is(&r, "page_key")) {
			CHECK(json_next(&r) == JSON_STRING);
			json_string(&r, key, sizeof(key));
		} else {
			json_skip(&r, JSON_KEY);
		}
	}
	CHECK(t == JSON_OBJECT_END);
	CHECK(json_next(&r) == JSON_EOF);
	CHECK(total == 45 && rows == 2 && strcmp(title, "B") == 0 && strcmp(key, "p2") == 0);
}

static void test_http_base(void)
{
	HttpBase b;

	CHECK(http_base("http://192.168.1.5:8070/", &b) && strcmp(b.host, "192.168.1.5") == 0 && b.port == 8070
		&& strcmp(b.path, "/") == 0);
	CHECK(http_base("http://bridge.example", &b) && b.port == 80 && strcmp(b.path, "/") == 0);
	CHECK(http_base("http://h.example:81/kura", &b) && strcmp(b.path, "/kura/") == 0);
	CHECK(!http_base("https://h.example/", &b));
	CHECK(!http_base("http://user@h.example/", &b));
	CHECK(!http_base("http://h.example:0/", &b));
	CHECK(!http_base("http://h.example:65536/", &b));
	CHECK(!http_base("http://h.example:80x/", &b));
	CHECK(!http_base("http://h.example/?q", &b));
	CHECK(!http_base("http:///", &b));
	CHECK(!http_base("ftp://h.example/", &b));
}

static void test_http_request(void)
{
	HttpBase b;
	char out[256];
	const char *headers[] = {"Accept: application/json", "Authorization: Bearer mht_x", NULL};
	const char *bad[] = {"X: a\r\nInjected: 1", NULL};
	long n;

	http_base("http://192.168.1.5:8070/", &b);
	n = http_request(out, sizeof(out), &b, "/api/recent?limit=20", headers);
	CHECK(n > 0 && strcmp(out, "GET /api/recent?limit=20 HTTP/1.0\r\nHost: 192.168.1.5:8070\r\nConnection: close\r\n"
		"Accept: application/json\r\nAuthorization: Bearer mht_x\r\n\r\n") == 0);
	CHECK(n == (long) strlen(out));
	http_base("http://h.example/", &b);
	http_request(out, sizeof(out), &b, "/x", NULL);
	CHECK(strcmp(out, "GET /x HTTP/1.0\r\nHost: h.example\r\nConnection: close\r\n\r\n") == 0);
	CHECK(http_request(out, 20, &b, "/x", NULL) == -1);
	CHECK(http_request(out, sizeof(out), &b, "x", NULL) == -1);
	CHECK(http_request(out, sizeof(out), &b, "/x", bad) == -1);
}

static void test_http_head(void)
{
	HttpReply h;
	const char *ok = "HTTP/1.0 200 OK\r\nContent-Type: application/json \r\ncontent-length: 12\r\n\r\n{\"ok\": true}";
	const char *redirect = "HTTP/1.1 302 Found\r\nLocation: https://elsewhere.example/\r\n\r\n";

	CHECK(http_parse_head(ok, (long) strlen(ok), &h) == 1);
	CHECK(h.status == 200 && h.contentLength == 12 && strcmp(h.contentType, "application/json") == 0);
	CHECK(h.headLen == (long) (strstr(ok, "{") - ok));
	CHECK(http_parse_head(ok, 20, &h) == 0);
	CHECK(http_parse_head(redirect, (long) strlen(redirect), &h) == 1 && h.status == 302
		&& strcmp(h.location, "https://elsewhere.example/") == 0 && h.contentLength == -1);
	CHECK(http_parse_head("SSH-2.0-x\r\n\r\n", 13, &h) == -1);
	CHECK(http_parse_head("HTTP/1.0 2x0 OK\r\n\r\n", 19, &h) == -1);
	CHECK(http_parse_head("HTTP/1.0 200 OK\r\nContent-Length: 99999999999\r\n\r\n", 48, &h) == -1);
}

/* search-core.js's own answers (vectors.h), through the C twins */
static void test_vectors(void)
{
	unsigned int i;
	char got[4096], tmp[2048];
	int fails = 0;

	for (i = 0; i < sizeof(kVectors) / sizeof(kVectors[0]); i++) {
		const struct Vec *v = &kVectors[i];
		const char *fn = v->fn;
		got[0] = '\0';
		if (strcmp(fn, "prefixLastWord") == 0) {
			shiori_prefix_last_word(v->in, 0, got, sizeof(got));
		} else if (strcmp(fn, "prefixLastWordUnion") == 0) {
			shiori_prefix_last_word(v->in, 1, got, sizeof(got));
		} else if (strcmp(fn, "histerText") == 0) {
			shiori_hister_text(v->in, got, sizeof(got));
		} else if (strcmp(fn, "codeHisterText") == 0) {
			shiori_code_query(v->in, tmp, sizeof(tmp));
			shiori_hister_text(tmp, got, sizeof(got));
		} else if (strcmp(fn, "filesHisterText") == 0) {
			shiori_files_query(v->in, tmp, sizeof(tmp));
			shiori_hister_text(tmp, got, sizeof(got));
		} else if (strcmp(fn, "webQuery") == 0) {
			shiori_web_query(v->in, got, sizeof(got));
		} else if (strcmp(fn, "kuraQuery") == 0) {
			shiori_kura_query(v->in, got, sizeof(got));
		} else if (strcmp(fn, "kuraURL") == 0) {
			strcpy(got, "https://kura.example/");
			shiori_kura_search_target(v->in, 5, 0, "", got + strlen(got), sizeof(got) - strlen(got));
		} else if (strcmp(fn, "kuraURLVault") == 0) {
			strcpy(got, "https://kura.example/");
			shiori_kura_search_target(v->in, 30, 30, "all", got + strlen(got), sizeof(got) - strlen(got));
		} else if (strcmp(fn, "histerSearchURL") == 0) {
			strcpy(got, "https://h.example/");
			shiori_hister_search_target(v->in, PILL_ALL, 30, "", got + strlen(got), sizeof(got) - strlen(got));
		} else {
			printf("FAIL unknown vector function %s\n", fn);
			failed++;
			continue;
		}
		if (strcmp(got, v->want) == 0) {
			passed++;
		} else {
			failed++;
			if (++fails <= 10)
				printf("FAIL %s(\"%s\")\n   got  \"%s\"\n   want \"%s\"\n", fn, v->in, got, v->want);
		}
	}
}

static void test_query_bounds(void)
{
	char small[8];

	CHECK(shiori_hister_text("raspberry pi", small, sizeof(small)) == 0 && strlen(small) == 7);
	CHECK(shiori_form_encode("a b+c", small, sizeof(small)) == 1 && strcmp(small, "a+b%2Bc") == 0);
	CHECK(shiori_uri_encode("a b(c)", small, sizeof(small)) == 0);
	CHECK(strcmp(shiori_pill_label(PILL_CODE), "Code") == 0);
}

/* -- results -------------------------------------------------------------------------- */

static ShioriRow gRows[8];
static int gRowCount;

static void keep_row(void *ctx, const ShioriRow *row)
{
	(void) ctx;
	if (gRowCount < 8)
		gRows[gRowCount++] = *row;
}

static void test_hister_reply(void)
{
	const char *reply = "{\"total\": 230, \"query\": {\"text\": \"x\"}, \"documents\": ["
		"{\"url\": \"https://www.Example.com:8443/a?b\", \"title\": \"Caf\\u00e9 \\u2014 one\", \"domain\": \"\", "
		"\"text\": \"the <mark>pi</mark> &amp; more\", \"label\": \"tech\", \"added\": 1790000000, "
		"\"metadata\": {\"source\": \"shiori\", \"tags\": [1, 2]}, \"score\": 1.5},"
		"{\"url\": \"javascript:alert(1)\", \"title\": \"bad\"},"
		"{\"url\": \"https://git.example/o/r\", \"title\": \"\", \"domain\": \"git.example\", \"updated\": 7, "
		"\"metadata\": {\"source\": \"code\"}}"
		"], \"page_key\": \"p2\", \"history\": null}";
	ShioriPage page;

	gRowCount = 0;
	CHECK(shiori_parse_hister(reply, (long) strlen(reply), &page, keep_row, NULL) == 1);
	CHECK(page.ok && page.total == 230 && page.received == 3 && strcmp(page.next, "p2") == 0);
	CHECK(gRowCount == 2);
	CHECK(gRows[0].kind == ROW_PAGE && strcmp(gRows[0].title, "Caf\xC3\xA9 \xE2\x80\x94 one") == 0);
	CHECK(strcmp(gRows[0].host, "example.com") == 0);        /* from the url: no www., no port */
	CHECK(strcmp(gRows[0].label, "tech") == 0 && gRows[0].added == 1790000000L && gRows[0].updated == 1790000000L);
	CHECK(gRows[1].kind == ROW_CODE && strcmp(gRows[1].title, "https://git.example/o/r") == 0 && gRows[1].updated == 7);
	/* malformed or the wrong shape */
	CHECK(shiori_parse_hister("[]", 2, &page, keep_row, NULL) == 0 && !page.ok);
	CHECK(shiori_parse_hister("{\"documents\": 5}", 16, &page, keep_row, NULL) == 0);
	CHECK(shiori_parse_hister("{\"total\": 1", 11, &page, keep_row, NULL) == 0);
	CHECK(shiori_parse_hister("{}", 2, &page, keep_row, NULL) == 1 && page.total == 0);
}

static void test_kura_reply(void)
{
	const char *reply = "{\"total\": 2, \"took_ms\": 1, \"results\": ["
		"{\"path\": \"Projects/Shiori Classic.md\", \"vault\": \"personal\", \"title\": \"Shiori Classic\", "
		"\"url\": \"https://kura.example/n/Projects/Shiori%20Classic\", \"summary\": \"A Mac Plus client\", "
		"\"tags\": [\"a\"], \"created\": 1790000000, \"changed\": 1790500000, \"card_url\": null},"
		"{\"path\": \"Inbox/x.md\", \"url\": \"https://kura.example/n/Inbox/x\", \"snippet\": \"a <mark>pi</mark>\"}"
		"]}";
	ShioriPage page;

	gRowCount = 0;
	CHECK(shiori_parse_kura(reply, (long) strlen(reply), &page, keep_row, NULL) == 1 && page.total == 2);
	CHECK(gRowCount == 2 && gRows[0].kind == ROW_NOTE && strcmp(gRows[0].host, "Projects") == 0);
	CHECK(strcmp(gRows[0].snippet, "A Mac Plus client") == 0 && strcmp(gRows[0].label, "vault") == 0);
	CHECK(gRows[0].updated == 1790500000L && strcmp(gRows[0].vault, "personal") == 0);
	CHECK(strcmp(gRows[1].title, "Inbox/x.md") == 0 && strcmp(gRows[1].snippet, "a <mark>pi</mark>") == 0);
}

static void test_vaults(void)
{
	const char *reply = "{\"vaults\": [{\"name\": \"personal\", \"title\": \"Personal\", \"default\": true},"
		"{\"name\": \"work\", \"private\": true}, {\"name\": \"shared\", \"title\": \"Shared\", \"private\": false},"
		"{\"name\": \"Bad Name\"}, {\"name\": \"quiet\"}]}";
	ShioriVault v[8];
	int n = shiori_parse_vaults(reply, (long) strlen(reply), v, 8);

	CHECK(n == 4);
	CHECK(v[0].isDefault && !v[0].isPrivate && strcmp(v[0].title, "Personal") == 0);
	CHECK(v[1].isPrivate && strcmp(v[1].title, "work") == 0);
	CHECK(!v[2].isPrivate && strcmp(v[2].name, "shared") == 0);
	CHECK(v[3].isPrivate);                    /* no "private": fail closed */
	CHECK(shiori_parse_vaults("nope", 4, v, 8) == 0);
}

static void test_snippets(void)
{
	char out[64], s[64];

	shiori_snippet_text("the  <mark>pi</mark>\n&amp; <b>more</b>", out, sizeof(out));
	CHECK(strcmp(out, "the \001pi\002 & more") == 0);
	shiori_snippet_text("<mark>open", out, sizeof(out));
	CHECK(strcmp(out, "\001open\002") == 0);
	shiori_snippet_text("caf\xC3\xA9 caf\xC3\xA9", out, 7);          /* cut inside the second word */
	CHECK(strcmp(out, "caf\xC3\xA9 ") == 0 || strcmp(out, "caf\xC3\xA9 c") == 0);
	shiori_snippet_text("ab\xC3\xA9", out, 4);                     /* the cut would halve é */
	CHECK(strcmp(out, "ab") == 0);
	shiori_snippet_text("ab\xC3\xA9", out, 5);                     /* it fits whole */
	CHECK(strcmp(out, "ab\xC3\xA9") == 0);
	strcpy(s, "&#x41;&#66;&quot;&bogus;&&#8212;&#128512;&nbsp;x");
	shiori_decode_entities(s);
	CHECK(strcmp(s, "AB\"&bogus;&\xE2\x80\x94\xF0\x9F\x98\x80 x") == 0);
}

static void test_hosts(void)
{
	char h[64];

	shiori_host_of("https://user@WWW.Example.COM:8080/x", h, sizeof(h));
	CHECK(strcmp(h, "example.com") == 0);
	shiori_host_of("http://[::1]:80/", h, sizeof(h));
	CHECK(strcmp(h, "[::1]:80") == 0);
	shiori_host_of("ftp://example.com/", h, sizeof(h));
	CHECK(h[0] == '\0');
	CHECK(shiori_is_web_url("HTTPS://a") && !shiori_is_web_url("https:///a") && !shiori_is_web_url("javascript:x"));
}

/* -- credentials ---------------------------------------------------------------------- */

static void test_credentials(void)
{
	char o[96], tok[64], h[128];
	ShioriConfig c;
	const char *good = "mht_KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK";

	shiori_origin_of("HTTP://Example.COM:80/a?b#c", o, sizeof(o));
	CHECK(strcmp(o, "http://example.com") == 0);
	shiori_origin_of("http://127.0.0.1:8401/", o, sizeof(o));
	CHECK(strcmp(o, "http://127.0.0.1:8401") == 0);
	shiori_origin_of("https://h.example:443", o, sizeof(o));
	CHECK(strcmp(o, "https://h.example") == 0);
	shiori_origin_of("ftp://x/", o, sizeof(o));
	CHECK(o[0] == '\0');
	shiori_origin_of("http://user@h.example/", o, sizeof(o));
	CHECK(o[0] == '\0');
	shiori_origin_of("http://h.example:80x/", o, sizeof(o));
	CHECK(o[0] == '\0');

	shiori_checked_room_token("  mht_KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK \n", tok, sizeof(tok));
	CHECK(strcmp(tok, good) == 0);
	shiori_checked_room_token("mht_KKKK", tok, sizeof(tok));
	CHECK(tok[0] == '\0');
	shiori_checked_room_token("mhs_KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK", tok, sizeof(tok));
	CHECK(tok[0] == '\0');
	shiori_checked_room_token("mht_KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK!", tok, sizeof(tok));
	CHECK(tok[0] == '\0');

	memset(&c, 0, sizeof(c));
	strcpy(c.hister, "http://192.168.1.5:8070/");
	strcpy(c.kura, "http://192.168.1.5:8071/");
	strcpy(c.roomToken, good);
	shiori_credential_header(&c, "http://192.168.1.5:8070/search?query=x", h, sizeof(h));
	CHECK(strcmp(h, "Authorization: Bearer mht_KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK") == 0);
	shiori_credential_header(&c, "http://192.168.1.5:8071/api/note?path=a.md", h, sizeof(h));
	CHECK(h[0] != '\0');
	shiori_credential_header(&c, "http://192.168.1.5:8072/", h, sizeof(h));   /* another port */
	CHECK(h[0] == '\0');
	shiori_credential_header(&c, "https://192.168.1.5:8070/", h, sizeof(h));  /* another scheme */
	CHECK(h[0] == '\0');
	shiori_credential_header(&c, "http://evil.example/", h, sizeof(h));
	CHECK(h[0] == '\0' && !shiori_is_configured_origin(&c, "http://evil.example/"));
	strcpy(c.roomToken, "mht_short");
	shiori_credential_header(&c, "http://192.168.1.5:8070/", h, sizeof(h));
	CHECK(h[0] == '\0');
}

/* -- Mac Roman ---------------------------------------------------------------------------- */

static void test_roman(void)
{
	char s[64], u[64];

	strcpy(s, "Caf\xC3\xA9 \xE2\x80\x94 \xE2\x80\x9Cq\xE2\x80\x9D \xE2\x80\xA6");
	CHECK(roman_from_utf8(s) == 12 && strcmp(s, "Caf\x8E \xD1 \xD2q\xD3 \xC9") == 0);
	strcpy(s, "Ch\xC5\x8D" "chin \xE7\x94\xBA \xF0\x9F\x98\x80 \xE2\x82\xAC");
	roman_from_utf8(s);
	CHECK(strcmp(s, "Chochin ? ? \xDB") == 0);
	strcpy(s, "a\001b\002\xFFz\xE2\x80\x8Bx");               /* marks pass, a bad byte is ?, zero width dropped */
	roman_from_utf8(s);
	CHECK(strcmp(s, "a\001b\002?zx") == 0);
	CHECK(roman_to_utf8("Caf\x8E \xD1 \xF0", u, sizeof(u)) && strcmp(u, "Caf\xC3\xA9 \xE2\x80\x94 \xEF\xA3\xBF") == 0);
	CHECK(roman_to_utf8("\x8E\x8E", u, 4) == 0);
	CHECK(roman_from_cp(0x00A4) == 0xDB && roman_from_cp(0x0131) == 0xF5 && roman_from_cp(0x2019) == 0xD5);
}

/* -- the reader's text (haiku/tests/test_core.cpp's TestNoteText, and more) ------------------- */

static char gText[2048], gHrefs[512];
static NoteRun gRuns[64];

static NoteText note(const char *html, int roman)
{
	NoteText t;
	note_text_init(&t, gText, sizeof(gText), gRuns, 64, gHrefs, sizeof(gHrefs), roman);
	shiori_note_html_to_text(html, (long) strlen(html), &t);
	return t;
}

static int run_at(const NoteText *t, const char *find, int style)
{
	const char *at = strstr(t->text, find);
	int i;
	if (at == NULL)
		return 0;
	for (i = 0; i < t->runCount; i++)
		if (t->runs[i].offset == at - t->text && t->runs[i].style == style)
			return 1;
	return 0;
}

static void test_note_text(void)
{
	const char *html =
		"<h1>BeBox</h1>\n<p>Be Inc.&#39;s <strong>dual</strong> machine, see <a href=\"https://example.com/bebox\">the page</a>.</p>"
		"<ul><li>Two <em>PowerPC</em> CPUs</li><li>GeekPort</li></ul>"
		"<p>Run <code>ls -l</code></p><pre>line 1\n  line 2</pre>"
		"<blockquote><p>A quote</p></blockquote><script>alert(1)</script>"
		"<p><a href=\"javascript:alert(1)\">not a link</a> &amp; <img alt=\"a photo\" src=\"x.png\"></p>"
		"<ol><li>one</li><li>two</li></ol>";
	NoteText t = note(html, 0);
	char path[64], vault[16];

	CHECK(strcmp(t.text, "BeBox\n\nBe Inc.'s dual machine, see the page.\n\n\xE2\x80\xA2 Two PowerPC CPUs\n\xE2\x80\xA2 GeekPort\n\n"
		"Run ls -l\n\nline 1\n  line 2\n\nA quote\n\nnot a link & [a photo]\n\n1. one\n2. two") == 0);
	CHECK(t.runCount > 0 && t.runs[0].offset == 0 && t.runs[0].style == STYLE_HEADING);
	CHECK(strcmp(note_link_at(&t, (long) (strstr(t.text, "the page") - t.text) + 2), "https://example.com/bebox") == 0);
	CHECK(strcmp(note_link_at(&t, (long) (strstr(t.text, "dual") - t.text)), "") == 0);
	CHECK(strcmp(note_link_at(&t, (long) (strstr(t.text, "not a link") - t.text)), "") == 0);
	CHECK(run_at(&t, "dual", STYLE_BOLD) && run_at(&t, "ls -l", STYLE_CODE) && run_at(&t, "A quote", STYLE_QUOTE)
		&& run_at(&t, "PowerPC", STYLE_ITALIC));
	CHECK(!t.truncated);
	t = note("", 0);
	CHECK(t.text[0] == '\0' && t.runCount == 1);
	t = note("hello", 0);
	CHECK(strcmp(t.text, "hello") == 0 && t.runCount == 1 && t.runs[0].offset == 0 && t.runs[0].style == 0);

	/* as Mac Roman, offsets stay true */
	t = note("<p>caf\xC3\xA9 <b>na\xC3\xAFve</b></p><ul><li>\xE2\x80\x94</li></ul>", 1);
	CHECK(strcmp(t.text, "caf\x8E na\x95ve\n\n\xA5 \xD1") == 0 && run_at(&t, "na\x95ve", STYLE_BOLD));
	/* a nested list indents; a table's cells are a line each row */
	t = note("<ul><li>a<ul><li>b</li></ul></li></ul><table><tr><td>1</td><td>2</td></tr><tr><td>3</td></tr></table>", 0);
	CHECK(strcmp(t.text, "\xE2\x80\xA2 a\n    \xE2\x80\xA2 b\n\n1 2\n3") == 0);
	/* a small buffer truncates cleanly */
	{
		char small[8];
		NoteRun r[4];
		char h[8];
		NoteText s;
		note_text_init(&s, small, sizeof(small), r, 4, h, sizeof(h), 0);
		shiori_note_html_to_text("<p>caf\xC3\xA9 au lait</p>", 20, &s);
		CHECK(s.truncated && strlen(small) < 8 && strncmp(small, "caf\xC3\xA9", 5) == 0);
	}

	/* requests */
	CHECK(shiori_kura_note_target("Retro/Be Box.md", "", path, sizeof(path)) && strcmp(path, "api/note?path=Retro%2FBe+Box.md") == 0);
	CHECK(shiori_kura_note_target("a.md", "work", path, sizeof(path)) && strcmp(path, "api/note?path=a.md&vault=work") == 0);
	{
		char pv[96];
		CHECK(shiori_hister_preview_target("https://a.example/x?y=1&z", pv, sizeof(pv))
			&& strcmp(pv, "api/preview?url=https%3A%2F%2Fa.example%2Fx%3Fy%3D1%26z") == 0);
	}

	/* the reply's html, undecoded until asked */
	{
		const char *reply = "{\"title\": \"x\", \"html\": \"<p>caf\\u00e9</p>\", \"markdown\": \"x\"}";
		const char *raw;
		long rawLen;
		char html2[32];
		CHECK(shiori_json_member(reply, (long) strlen(reply), "html", &raw, &rawLen));
		CHECK(json_decode(raw, rawLen, html2, sizeof(html2)) == 12 && strcmp(html2, "<p>caf\xC3\xA9</p>") == 0);
		CHECK(!shiori_json_member("{\"error\": \"not found\"}", 22, "html", &raw, &rawLen));
	}

	/* the vault is the address's */
	shiori_url_vault("https://kura.example/n/Projects/x", vault, sizeof(vault));
	CHECK(vault[0] == '\0');
	shiori_url_vault("https://kura.example/v/work/n/x", vault, sizeof(vault));
	CHECK(strcmp(vault, "work") == 0);
	shiori_url_vault("https://kura.example/v/Work/n/x", vault, sizeof(vault));
	CHECK(vault[0] == '\0');
	shiori_url_vault("https://kura.example/v/work/t/x", vault, sizeof(vault));
	CHECK(vault[0] == '\0');

	/* wikilinks open notes: same base, the slug decoded, ".md" */
	CHECK(shiori_note_link("https://kura.example/n/Projects/Be%20Box#Specs", "https://kura.example/n/Retro/x",
		path, sizeof(path), vault, sizeof(vault)) && strcmp(path, "Projects/Be Box.md") == 0 && vault[0] == '\0');
	CHECK(shiori_note_link("https://kura.example/v/work/n/a", "https://kura.example/v/work/n/b",
		path, sizeof(path), vault, sizeof(vault)) && strcmp(path, "a.md") == 0 && strcmp(vault, "work") == 0);
	CHECK(!shiori_note_link("https://other.example/n/a", "https://kura.example/n/b", path, sizeof(path), vault, sizeof(vault)));
	CHECK(!shiori_note_link("https://kura.example/t/tag", "https://kura.example/n/b", path, sizeof(path), vault, sizeof(vault)));
	CHECK(!shiori_note_link("https://kura.example/n/%2E%2E/x", "https://kura.example/n/b", path, sizeof(path), vault, sizeof(vault)));
	CHECK(!shiori_note_link("https://kura.example/n/a/%2E%2E", "https://kura.example/n/b", path, sizeof(path), vault, sizeof(vault)));
	CHECK(!shiori_note_link("https://kura.example/n/a/./b", "https://kura.example/n/b", path, sizeof(path), vault, sizeof(vault)));
	CHECK(!shiori_note_link("https://kura.example/v/Bad/n/a", "https://kura.example/n/b", path, sizeof(path), vault, sizeof(vault)));
}

int main(void)
{
	test_note_text();
	test_vectors();
	test_hister_reply();
	test_kura_reply();
	test_vaults();
	test_snippets();
	test_hosts();
	test_credentials();
	test_roman();
	test_query_bounds();
	test_json_tokens();
	test_json_strings();
	test_json_walk();
	test_http_base();
	test_http_request();
	test_http_head();
	printf("%d passed, %d failed\n", passed, failed);
	return failed ? 1 : 0;
}
