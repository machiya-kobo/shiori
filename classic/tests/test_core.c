/*
 * The classic core's tests, run on the host (cc) by scripts/classic.test.mjs:
 *   make -C classic/tests test
 */
#include <stdio.h>
#include <string.h>

#include "../core/http.h"
#include "../core/json.h"

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

int main(void)
{
	test_json_tokens();
	test_json_strings();
	test_json_walk();
	test_http_base();
	test_http_request();
	test_http_head();
	printf("%d passed, %d failed\n", passed, failed);
	return failed ? 1 : 0;
}
