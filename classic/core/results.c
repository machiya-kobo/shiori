/* results.c: see results.h. Follows haiku/core/Results.cpp. */
#include <stdlib.h>
#include <string.h>

#include "json.h"
#include "results.h"

const char *shiori_strstr(const char *s, const char *needle)
{
	size_t n = strlen(needle);

	for (; *s; s++)
		if (*s == *needle && strncmp(s, needle, n) == 0)
			return s;
	return n == 0 ? s : NULL;
}

#define COPY(field, r) json_string(r, field, (long) sizeof(field))

static int lower(int c)
{
	return (c >= 'A' && c <= 'Z') ? c + 32 : c;
}

int shiori_is_web_url(const char *url)
{
	/* linux/src/page.js: /^https?:\/\/[^/\s]/i */
	int n;
	char c;

	if (lower((unsigned char) url[0]) != 'h' || lower((unsigned char) url[1]) != 't'
			|| lower((unsigned char) url[2]) != 't' || lower((unsigned char) url[3]) != 'p')
		return 0;
	if (lower((unsigned char) url[4]) == 's')
		n = 5;
	else
		n = 4;
	if (strncmp(url + n, "://", 3) != 0)
		return 0;
	c = url[n + 3];
	return c != '\0' && c != '/' && c != ' ' && c != '\t' && c != '\n' && c != '\r' && c != '\f' && c != '\v';
}

void shiori_host_of(const char *url, char *out, long cap)
{
	const char *start, *end, *at, *p;
	long n;

	out[0] = '\0';
	if (cap <= 0 || !shiori_is_web_url(url))
		return;
	start = shiori_strstr(url, "://") + 3;
	end = start + strcspn(start, "/?#");
	at = NULL;
	for (p = start; p < end; p++)
		if (*p == '@')
			at = p;
	if (at != NULL)
		start = at + 1;
	if (*start != '[') {
		for (p = start; p < end; p++)
			if (*p == ':') {
				end = p;
				break;
			}
	}
	n = end - start;
	if (n >= 4 && lower((unsigned char) start[0]) == 'w' && lower((unsigned char) start[1]) == 'w'
			&& lower((unsigned char) start[2]) == 'w' && start[3] == '.') {
		start += 4;
		n -= 4;
	}
	if (n >= cap)
		n = cap - 1;
	for (p = start; p < start + n; p++)
		*out++ = (char) lower((unsigned char) *p);
	*out = '\0';
}

static void put_utf8(char **o, unsigned long cp)
{
	char *p = *o;

	if (cp == 0 || cp > 0x10FFFFUL || (cp >= 0xD800 && cp <= 0xDFFF))
		cp = 0xFFFD;
	if (cp < 0x80) {
		*p++ = (char) cp;
	} else if (cp < 0x800) {
		*p++ = (char) (0xC0 | (cp >> 6));
		*p++ = (char) (0x80 | (cp & 0x3F));
	} else if (cp < 0x10000UL) {
		*p++ = (char) (0xE0 | (cp >> 12));
		*p++ = (char) (0x80 | ((cp >> 6) & 0x3F));
		*p++ = (char) (0x80 | (cp & 0x3F));
	} else {
		*p++ = (char) (0xF0 | (cp >> 18));
		*p++ = (char) (0x80 | ((cp >> 12) & 0x3F));
		*p++ = (char) (0x80 | ((cp >> 6) & 0x3F));
		*p++ = (char) (0x80 | (cp & 0x3F));
	}
	*o = p;
}

/* Decoding never grows a string: every entity is at least as long as its UTF-8. */
void shiori_decode_entities(char *s)
{
	char *in = s, *out = s, *semi, name[12];
	long n, k;

	while (*in) {
		if (*in != '&' || (semi = strchr(in, ';')) == NULL || semi - in > 10) {
			*out++ = *in++;
			continue;
		}
		n = semi - in - 1;
		memcpy(name, in + 1, (size_t) n);
		name[n] = '\0';
		if (n > 1 && name[0] == '#') {
			int hex = name[1] == 'x' || name[1] == 'X';
			char *digits = name + (hex ? 2 : 1), *end;
			unsigned long cp = strtoul(digits, &end, hex ? 16 : 10);
			/* "&#1;" is 4 bytes, so even U+10000 (4 bytes) fits; &#x10FFFF; likewise */
			if (*digits != '\0' && *end == '\0' && cp <= 0x10FFFFUL && semi + 1 - in >= 4) {
				char tmp[4], *t = tmp;
				put_utf8(&t, cp);
				if (t - tmp <= semi + 1 - in) {
					memcpy(out, tmp, (size_t) (t - tmp));
					out += t - tmp;
					in = semi + 1;
					continue;
				}
			}
		} else {
			for (k = 0; k < n; k++)
				name[k] = (char) lower((unsigned char) name[k]);
			if (strcmp(name, "amp") == 0) { *out++ = '&'; in = semi + 1; continue; }
			if (strcmp(name, "lt") == 0) { *out++ = '<'; in = semi + 1; continue; }
			if (strcmp(name, "gt") == 0) { *out++ = '>'; in = semi + 1; continue; }
			if (strcmp(name, "quot") == 0) { *out++ = '"'; in = semi + 1; continue; }
			if (strcmp(name, "apos") == 0) { *out++ = '\''; in = semi + 1; continue; }
			if (strcmp(name, "nbsp") == 0) { *out++ = ' '; in = semi + 1; continue; }
		}
		*out++ = *in++;
	}
	*out = '\0';
}

void shiori_snippet_text(const char *html, char *out, long cap)
{
	long n = 0;
	int marked = 0, space = 0;
	const char *p = html, *close;
	char tag[8];
	long t;

	if (cap <= 0)
		return;
	/* first pass: tags out, mark bytes in, whitespace folded */
	while (*p && n < cap - 1) {
		if (*p == '<') {
			close = strchr(p, '>');
			if (close == NULL)
				break;
			for (t = 0; t < (long) sizeof(tag) - 1 && p + 1 + t < close; t++)
				tag[t] = (char) lower((unsigned char) p[1 + t]);
			tag[t] = '\0';
			if ((strcmp(tag, "mark") == 0 || strncmp(tag, "mark ", 5) == 0) && !marked) {
				marked = 1;
				if (space && n > 0 && n < cap - 1)
					out[n++] = ' ';
				space = 0;
				if (n < cap - 1)
					out[n++] = SNIPPET_MARK_ON;
			} else if (strcmp(tag, "/mark") == 0 && marked) {
				marked = 0;
				if (n < cap - 1)
					out[n++] = SNIPPET_MARK_OFF;
			}
			p = close + 1;
			continue;
		}
		if (*p == ' ' || *p == '\n' || *p == '\t' || *p == '\r') {
			space = 1;
			p++;
			continue;
		}
		if (space && n > 0 && n < cap - 1)
			out[n++] = ' ';
		space = 0;
		if (n < cap - 1)
			out[n++] = *p;
		p++;
	}
	/* a cut never leaves a half character (or an open mark) */
	if (*p != '\0' && n == cap - 1) {
		long end = n;
		while (end > 0 && ((unsigned char) out[end - 1] & 0xC0) == 0x80)
			end--;
		if (end > 0 && ((unsigned char) out[end - 1] & 0xC0) == 0xC0) {
			unsigned char lead = (unsigned char) out[end - 1];
			long need = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : 2;
			if (n - (end - 1) < need)
				n = end - 1;
		}
		if (marked && n >= cap - 1)
			n--;
	}
	if (marked && n > 0 && n < cap - 1)
		out[n++] = SNIPPET_MARK_OFF;
	out[n] = '\0';
	shiori_decode_entities(out);
}

/* -- replies ------------------------------------------------------------------------------- */

static long number_or_zero(JsonReader *r, int t)
{
	return t == JSON_NUMBER ? json_long(r) : 0;
}

/* Reads one document object (after its JSON_OBJECT); 1 when it closed cleanly. */
static int read_hister_doc(JsonReader *r, ShioriRow *row)
{
	int t, haveUpdated = 0;

	memset(row, 0, sizeof(*row));
	row->kind = ROW_PAGE;
	while ((t = json_next(r)) == JSON_KEY) {
		if (json_is(r, "metadata")) {
			if ((t = json_next(r)) == JSON_OBJECT) {
				while ((t = json_next(r)) == JSON_KEY) {
					if (json_is(r, "source")) {
						if ((t = json_next(r)) == JSON_STRING) {
							char source[16];
							json_string(r, source, (long) sizeof(source));
							if (strcmp(source, "code") == 0)
								row->kind = ROW_CODE;
						} else if (t == JSON_OBJECT || t == JSON_ARRAY) {
							if (json_skip(r, t) == JSON_ERROR)
								return 0;
						}
					} else if (json_skip(r, JSON_KEY) == JSON_ERROR) {
						return 0;
					}
				}
				if (t != JSON_OBJECT_END)
					return 0;
			} else if (t == JSON_ARRAY) {
				if (json_skip(r, t) == JSON_ERROR)
					return 0;
			}
			continue;
		}
		if (json_is(r, "url") || json_is(r, "title") || json_is(r, "domain") || json_is(r, "text")
				|| json_is(r, "label")) {
			char key[8];
			memcpy(key, r->tok, (size_t) (r->tokLen < 7 ? r->tokLen : 7));
			key[r->tokLen < 7 ? r->tokLen : 7] = '\0';
			t = json_next(r);
			if (t == JSON_OBJECT || t == JSON_ARRAY) {
				if (json_skip(r, t) == JSON_ERROR)
					return 0;
				continue;
			}
			if (t != JSON_STRING)
				continue;
			if (strcmp(key, "url") == 0) COPY(row->url, r);
			else if (strcmp(key, "title") == 0) COPY(row->title, r);
			else if (strcmp(key, "domain") == 0) COPY(row->host, r);
			else if (strcmp(key, "text") == 0) COPY(row->snippet, r);
			else COPY(row->label, r);
			continue;
		}
		if (json_is(r, "added") || json_is(r, "updated")) {
			int added = json_is(r, "added");
			t = json_next(r);
			if (t == JSON_OBJECT || t == JSON_ARRAY) {
				if (json_skip(r, t) == JSON_ERROR)
					return 0;
				continue;
			}
			if (added) {
				row->added = number_or_zero(r, t);
			} else {
				row->updated = number_or_zero(r, t);
				haveUpdated = t == JSON_NUMBER;
			}
			continue;
		}
		if (json_skip(r, JSON_KEY) == JSON_ERROR)
			return 0;
	}
	if (t != JSON_OBJECT_END)
		return 0;
	if (!haveUpdated)
		row->updated = row->added;
	if (row->title[0] == '\0')
		strncpy(row->title, row->url, sizeof(row->title) - 1);
	if (row->host[0] == '\0')
		shiori_host_of(row->url, row->host, (long) sizeof(row->host));
	return 1;
}

static void folder_of(const char *path, char *out, long cap)
{
	const char *slash = strrchr(path, '/');
	long n = slash ? slash - path : 0;

	if (n >= cap)
		n = cap - 1;
	memcpy(out, path, (size_t) n);
	out[n] = '\0';
}

static int read_kura_note(JsonReader *r, ShioriRow *row)
{
	int t, haveTitle = 0, haveFolder = 0, haveSnippet = 0, haveChanged = 0;
	char summary[sizeof(row->snippet)];

	memset(row, 0, sizeof(*row));
	summary[0] = '\0';
	row->kind = ROW_NOTE;
	strcpy(row->label, "vault");
	while ((t = json_next(r)) == JSON_KEY) {
		static const char *const keys[] = {"url", "path", "vault", "title", "folder", "snippet", "summary",
			"created", "changed"};
		unsigned int k;
		for (k = 0; k < sizeof(keys) / sizeof(keys[0]); k++)
			if (json_is(r, keys[k]))
				break;
		if (k == sizeof(keys) / sizeof(keys[0])) {
			if (json_skip(r, JSON_KEY) == JSON_ERROR)
				return 0;
			continue;
		}
		t = json_next(r);
		if (t == JSON_OBJECT || t == JSON_ARRAY) {
			if (json_skip(r, t) == JSON_ERROR)
				return 0;
			continue;
		}
		switch (k) {
		case 0: if (t == JSON_STRING) COPY(row->url, r); break;
		case 1: if (t == JSON_STRING) COPY(row->path, r); break;
		case 2: if (t == JSON_STRING) COPY(row->vault, r); break;
		case 3: if (t == JSON_STRING) { COPY(row->title, r); haveTitle = 1; } break;
		case 4: if (t == JSON_STRING) { COPY(row->host, r); haveFolder = 1; } break;
		case 5: if (t == JSON_STRING) { COPY(row->snippet, r); haveSnippet = row->snippet[0] != '\0'; } break;
		case 6: if (t == JSON_STRING) json_string(r, summary, (long) sizeof(summary)); break;
		case 7: row->added = number_or_zero(r, t); break;
		case 8: row->updated = number_or_zero(r, t); haveChanged = t == JSON_NUMBER; break;
		}
	}
	if (t != JSON_OBJECT_END)
		return 0;
	if (!haveTitle || row->title[0] == '\0')
		strncpy(row->title, row->path[0] ? row->path : row->url, sizeof(row->title) - 1);
	if (!haveFolder)
		folder_of(row->path, row->host, (long) sizeof(row->host));
	if (!haveSnippet)
		strcpy(row->snippet, summary);
	if (!haveChanged)
		row->updated = row->added;
	return 1;
}

static int parse_reply(const char *buf, long len, ShioriPage *page, ShioriRowFn fn, void *ctx, int kura)
{
	JsonReader r;
	ShioriRow row;
	int t, sawList = 0, haveTotal = 0;

	memset(page, 0, sizeof(*page));
	json_init(&r, buf, len);
	if (json_next(&r) != JSON_OBJECT)
		return 0;
	while ((t = json_next(&r)) == JSON_KEY) {
		if (json_is(&r, kura ? "results" : "documents")) {
			t = json_next(&r);
			if (t == JSON_NULL)
				continue;
			if (t != JSON_ARRAY)
				return 0;
			sawList = 1;
			while ((t = json_next(&r)) != JSON_ARRAY_END) {
				if (t == JSON_OBJECT) {
					if (!(kura ? read_kura_note(&r, &row) : read_hister_doc(&r, &row)))
						return 0;
					page->received++;
					if (shiori_is_web_url(row.url) && fn != NULL)
						fn(ctx, &row);
				} else if (t == JSON_ARRAY) {
					if (json_skip(&r, t) == JSON_ERROR)
						return 0;
				} else if (t == JSON_ERROR || t == JSON_EOF) {
					return 0;
				}
			}
		} else if (json_is(&r, "total")) {
			t = json_next(&r);
			if (t == JSON_NUMBER) {
				page->total = json_long(&r);
				haveTotal = 1;
			} else if (t == JSON_OBJECT || t == JSON_ARRAY) {
				if (json_skip(&r, t) == JSON_ERROR)
					return 0;
			}
		} else if (!kura && json_is(&r, "page_key")) {
			t = json_next(&r);
			if (t == JSON_STRING)
				json_string(&r, page->next, (long) sizeof(page->next));
			else if (t == JSON_OBJECT || t == JSON_ARRAY)
				if (json_skip(&r, t) == JSON_ERROR)
					return 0;
		} else if (json_skip(&r, JSON_KEY) == JSON_ERROR) {
			return 0;
		}
	}
	if (t != JSON_OBJECT_END || json_next(&r) != JSON_EOF)
		return 0;
	(void) sawList;
	if (!haveTotal)
		page->total = page->received;
	page->ok = 1;
	return 1;
}

int shiori_parse_hister(const char *buf, long len, ShioriPage *page, ShioriRowFn fn, void *ctx)
{
	return parse_reply(buf, len, page, fn, ctx, 0);
}

int shiori_parse_kura(const char *buf, long len, ShioriPage *page, ShioriRowFn fn, void *ctx)
{
	return parse_reply(buf, len, page, fn, ctx, 1);
}

int shiori_parse_vaults(const char *buf, long len, ShioriVault *out, int max)
{
	JsonReader r;
	int t, count = 0;
	ShioriVault v;

	json_init(&r, buf, len);
	if (json_next(&r) != JSON_OBJECT)
		return 0;
	while ((t = json_next(&r)) == JSON_KEY) {
		if (!json_is(&r, "vaults")) {
			if (json_skip(&r, JSON_KEY) == JSON_ERROR)
				return count;
			continue;
		}
		if (json_next(&r) != JSON_ARRAY)
			return count;
		while ((t = json_next(&r)) == JSON_OBJECT) {
			int haveTitle = 0, sound = 1;
			const char *c;
			memset(&v, 0, sizeof(v));
			v.isPrivate = 1;                  /* fail closed: private unless Kura says false */
			while ((t = json_next(&r)) == JSON_KEY) {
				int key = json_is(&r, "name") ? 1 : json_is(&r, "title") ? 2 : json_is(&r, "default") ? 3
					: json_is(&r, "private") ? 4 : 0;
				t = json_next(&r);
				if (t == JSON_OBJECT || t == JSON_ARRAY) {
					if (json_skip(&r, t) == JSON_ERROR)
						return count;
					continue;
				}
				if (key == 1 && t == JSON_STRING) {
					if (r.tokLen >= (long) sizeof(v.name))
						sound = 0;
					COPY(v.name, &r);
				} else if (key == 2 && t == JSON_STRING) {
					COPY(v.title, &r);
					haveTitle = v.title[0] != '\0';
				} else if (key == 3) {
					v.isDefault = t == JSON_TRUE;
				} else if (key == 4) {
					v.isPrivate = t != JSON_FALSE;
				}
			}
			if (t != JSON_OBJECT_END)
				return count;
			if (v.name[0] == '\0')
				sound = 0;
			for (c = v.name; *c; c++)
				if (!((*c >= 'a' && *c <= 'z') || (*c >= '0' && *c <= '9') || *c == '-'))
					sound = 0;
			if (!sound)
				continue;
			if (!haveTitle)
				strcpy(v.title, v.name);
			if (v.isDefault)
				v.isPrivate = 0;              /* the default vault is never private */
			if (count < max)
				out[count++] = v;
		}
		return count;
	}
	return count;
}
