/* json.c: see json.h. */
#include <string.h>

#include "json.h"

void json_init(JsonReader *r, const char *buf, long len)
{
	memset(r, 0, sizeof(*r));
	r->p = buf;
	r->end = buf + len;
}

static void space(JsonReader *r)
{
	while (r->p < r->end && (*r->p == ' ' || *r->p == '\t' || *r->p == '\n' || *r->p == '\r'))
		r->p++;
}

/* Scans a string's body (r->p just after the opening quote); sets tok. */
static int scan_string(JsonReader *r)
{
	const char *start = r->p;

	while (r->p < r->end) {
		unsigned char c = (unsigned char) *r->p;
		if (c == '"') {
			r->tok = start;
			r->tokLen = r->p - start;
			r->p++;
			return 1;
		}
		if (c < 0x20)
			return 0;
		if (c == '\\') {
			r->p++;
			if (r->p >= r->end)
				return 0;
		}
		r->p++;
	}
	return 0;
}

static int scan_number(JsonReader *r)
{
	const char *start = r->p;

	if (r->p < r->end && *r->p == '-')
		r->p++;
	if (r->p >= r->end || *r->p < '0' || *r->p > '9')
		return 0;
	while (r->p < r->end && ((*r->p >= '0' && *r->p <= '9') || *r->p == '.' || *r->p == 'e' || *r->p == 'E'
			|| *r->p == '+' || *r->p == '-'))
		r->p++;
	r->tok = start;
	r->tokLen = r->p - start;
	return 1;
}

static int word(JsonReader *r, const char *w, int token)
{
	long n = (long) strlen(w);

	if (r->end - r->p < n || memcmp(r->p, w, (size_t) n) != 0)
		return JSON_ERROR;
	r->p += n;
	return token;
}

/* A value just finished: the container now wants ',' or its end. */
static int value_done(JsonReader *r, int token)
{
	if (r->depth == 0)
		r->done = 1;
	else
		r->afterValue = 1;
	return token;
}

int json_next(JsonReader *r)
{
	char c;

	space(r);
	if (r->done)
		return r->p == r->end ? JSON_EOF : JSON_ERROR;
	if (r->p >= r->end)
		return JSON_ERROR;
	c = *r->p;

	if (r->afterValue) {
		char open = r->stack[r->depth - 1];
		if (c == ',') {
			r->p++;
			r->afterValue = 0;
			r->wantKey = (open == '{');
			space(r);
			if (r->p >= r->end)
				return JSON_ERROR;
			c = *r->p;
			if (c == '}' || c == ']')
				return JSON_ERROR;            /* a trailing comma */
		} else if ((c == '}' && open == '{') || (c == ']' && open == '[')) {
			r->p++;
			r->depth--;
			return value_done(r, c == '}' ? JSON_OBJECT_END : JSON_ARRAY_END);
		} else {
			return JSON_ERROR;
		}
	}

	if (r->justOpened) {
		r->justOpened = 0;
		if (c == ']') {                          /* [] */
			r->p++;
			r->depth--;
			return value_done(r, JSON_ARRAY_END);
		}
	}

	if (r->wantKey) {
		if (c == '}' && r->objectOpened) {      /* {} */
			r->objectOpened = 0;
			r->p++;
			r->depth--;
			r->wantKey = 0;
			return value_done(r, JSON_OBJECT_END);
		}
		r->objectOpened = 0;
		if (c != '"')
			return JSON_ERROR;
		r->p++;
		if (!scan_string(r))
			return JSON_ERROR;
		space(r);
		if (r->p >= r->end || *r->p != ':')
			return JSON_ERROR;
		r->p++;
		r->wantKey = 0;
		return JSON_KEY;
	}

	switch (c) {
	case '{':
	case '[':
		if (r->depth >= JSON_MAX_DEPTH)
			return JSON_ERROR;
		r->stack[r->depth++] = c;
		r->p++;
		if (c == '{') {
			r->wantKey = 1;
			r->objectOpened = 1;
			return JSON_OBJECT;
		}
		r->justOpened = 1;
		return JSON_ARRAY;
	case '"':
		r->p++;
		if (!scan_string(r))
			return JSON_ERROR;
		return value_done(r, JSON_STRING);
	case 't':
		return word(r, "true", JSON_TRUE) == JSON_ERROR ? JSON_ERROR : value_done(r, JSON_TRUE);
	case 'f':
		return word(r, "false", JSON_FALSE) == JSON_ERROR ? JSON_ERROR : value_done(r, JSON_FALSE);
	case 'n':
		return word(r, "null", JSON_NULL) == JSON_ERROR ? JSON_ERROR : value_done(r, JSON_NULL);
	default:
		if (!scan_number(r))
			return JSON_ERROR;
		return value_done(r, JSON_NUMBER);
	}
}

int json_skip(JsonReader *r, int token)
{
	int depth;
	int t;

	if (token == JSON_KEY) {
		t = json_next(r);
		if (t != JSON_OBJECT && t != JSON_ARRAY)
			return t;
		token = t;
	}
	if (token != JSON_OBJECT && token != JSON_ARRAY)
		return token;
	depth = 1;
	while (depth > 0) {
		t = json_next(r);
		if (t == JSON_ERROR || t == JSON_EOF)
			return JSON_ERROR;
		if (t == JSON_OBJECT || t == JSON_ARRAY)
			depth++;
		else if (t == JSON_OBJECT_END || t == JSON_ARRAY_END)
			depth--;
	}
	return t;
}

int json_is(const JsonReader *r, const char *k)
{
	long n = (long) strlen(k);
	return r->tokLen == n && memcmp(r->tok, k, (size_t) n) == 0;
}

long json_long(const JsonReader *r)
{
	const char *p = r->tok, *end = r->tok + r->tokLen;
	long v = 0;
	int neg = 0;

	if (p < end && *p == '-') {
		neg = 1;
		p++;
	}
	while (p < end && *p >= '0' && *p <= '9') {
		if (v < 214748364L)
			v = v * 10 + (*p - '0');
		p++;
	}
	return neg ? -v : v;
}

static int hex4(const char *p, unsigned long *out)
{
	int i;
	unsigned long v = 0;

	for (i = 0; i < 4; i++) {
		char c = p[i];
		v <<= 4;
		if (c >= '0' && c <= '9')
			v |= (unsigned long) (c - '0');
		else if (c >= 'a' && c <= 'f')
			v |= (unsigned long) (c - 'a' + 10);
		else if (c >= 'A' && c <= 'F')
			v |= (unsigned long) (c - 'A' + 10);
		else
			return 0;
	}
	*out = v;
	return 1;
}

/* Appends code point cp as UTF-8 if it fits (with the NUL); else returns 0. */
static int put_utf8(char *out, long cap, long *n, unsigned long cp)
{
	char b[4];
	int len, i;

	if (cp < 0x80) {
		b[0] = (char) cp;
		len = 1;
	} else if (cp < 0x800) {
		b[0] = (char) (0xC0 | (cp >> 6));
		b[1] = (char) (0x80 | (cp & 0x3F));
		len = 2;
	} else if (cp < 0x10000) {
		b[0] = (char) (0xE0 | (cp >> 12));
		b[1] = (char) (0x80 | ((cp >> 6) & 0x3F));
		b[2] = (char) (0x80 | (cp & 0x3F));
		len = 3;
	} else {
		b[0] = (char) (0xF0 | (cp >> 18));
		b[1] = (char) (0x80 | ((cp >> 12) & 0x3F));
		b[2] = (char) (0x80 | ((cp >> 6) & 0x3F));
		b[3] = (char) (0x80 | (cp & 0x3F));
		len = 4;
	}
	if (*n + len >= cap)
		return 0;
	for (i = 0; i < len; i++)
		out[(*n)++] = b[i];
	return 1;
}

long json_string(const JsonReader *r, char *out, long cap)
{
	return json_decode(r->tok, r->tokLen, out, cap);
}

long json_decode(const char *raw, long rawLen, char *out, long cap)
{
	const char *p = raw, *end = raw + rawLen;
	long n = 0;

	if (cap <= 0)
		return 0;
	while (p < end) {
		unsigned char c = (unsigned char) *p;
		if (c != '\\') {
			/* copy one UTF-8 character whole, or stop */
			int len = c < 0x80 ? 1 : (c >> 5) == 6 ? 2 : (c >> 4) == 14 ? 3 : (c >> 3) == 30 ? 4 : 1;
			int i;
			if (p + len > end || n + len >= cap)
				break;
			for (i = 0; i < len; i++)
				out[n++] = p[i];
			p += len;
			continue;
		}
		p++;
		if (p >= end)
			break;
		c = (unsigned char) *p++;
		switch (c) {
		case 'n': c = '\n'; break;
		case 't': c = '\t'; break;
		case 'r': c = '\r'; break;
		case 'b': c = '\b'; break;
		case 'f': c = '\f'; break;
		case 'u': {
			unsigned long cp, lo;
			if (end - p < 4 || !hex4(p, &cp))
				goto done;
			p += 4;
			if (cp >= 0xD800 && cp <= 0xDBFF) {
				if (end - p >= 6 && p[0] == '\\' && p[1] == 'u' && hex4(p + 2, &lo) && lo >= 0xDC00 && lo <= 0xDFFF) {
					cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
					p += 6;
				} else {
					cp = 0xFFFD;
				}
			} else if (cp >= 0xDC00 && cp <= 0xDFFF) {
				cp = 0xFFFD;
			}
			if (!put_utf8(out, cap, &n, cp))
				goto done;
			continue;
		}
		default: break;          /* \" \\ \/ */
		}
		if (n + 1 >= cap)
			break;
		out[n++] = (char) c;
	}
done:
	out[n] = '\0';
	return n;
}
