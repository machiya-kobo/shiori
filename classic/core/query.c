/* query.c: see query.h. A line-for-line port of haiku/core/Query.cpp. */
#include <string.h>

#include "query.h"

/* -- a bounded string builder -------------------------------------------------------------- */

typedef struct Buf {
	char *s;
	long cap, len;
	int ok;
} Buf;

static void b_init(Buf *b, char *s, long cap)
{
	b->s = s;
	b->cap = cap;
	b->len = 0;
	b->ok = cap > 0;
	if (cap > 0)
		s[0] = '\0';
}

static void b_addn(Buf *b, const char *p, long n)
{
	if (!b->ok)
		return;
	if (b->len + n >= b->cap) {
		n = b->cap - 1 - b->len;
		b->ok = 0;
	}
	if (n > 0) {
		memmove(b->s + b->len, p, (size_t) n);   /* p may lie inside s (an in-place trim) */
		b->len += n;
	}
	b->s[b->len] = '\0';
}

static void b_add(Buf *b, const char *p)
{
	b_addn(b, p, (long) strlen(p));
}

/* n in decimal at the end of b (no printf: the desk accessory can't afford it). */
static void b_add_num(Buf *b, long n)
{
	char digits[12];
	int i = (int) sizeof(digits) - 1;
	unsigned long u = n < 0 ? (unsigned long) -n : (unsigned long) n;

	digits[i] = '\0';
	do {
		digits[--i] = (char) ('0' + u % 10);
		u /= 10;
	} while (u != 0 && i > 1);
	if (n < 0)
		digits[--i] = '-';
	b_add(b, digits + i);
}

static int b_set(char *out, long cap, const char *p, long n)
{
	Buf b;
	b_init(&b, out, cap);
	b_addn(&b, p, n);
	return b.ok;
}

/* -- code points ----------------------------------------------------------------------------- */

/* One UTF-8 code point at s[*i], advancing *i; U+FFFD for a bad byte. */
static unsigned long next_cp(const char *s, long len, long *i)
{
	unsigned char c = (unsigned char) s[(*i)++];
	int extra, k;
	unsigned long cp;

	if (c < 0x80)
		return c;
	extra = (c >= 0xF0) ? 3 : (c >= 0xE0) ? 2 : (c >= 0xC0) ? 1 : -1;
	if (extra < 0)
		return 0xFFFDUL;
	cp = c & (0x3F >> extra);
	for (k = 0; k < extra; k++) {
		if (*i >= len || ((unsigned char) s[*i] & 0xC0) != 0x80)
			return 0xFFFDUL;
		cp = (cp << 6) | ((unsigned char) s[(*i)++] & 0x3F);
	}
	return cp;
}

/* JavaScript's \s */
static int is_space(unsigned long cp)
{
	return cp == ' ' || (cp >= 0x09 && cp <= 0x0D) || cp == 0xA0 || cp == 0x1680
		|| (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028 || cp == 0x2029 || cp == 0x202F
		|| cp == 0x205F || cp == 0x3000 || cp == 0xFEFF;
}

/* \p{N}, near enough */
static int is_number(unsigned long cp)
{
	return (cp >= '0' && cp <= '9') || (cp >= 0xFF10 && cp <= 0xFF19);
}

/* \p{L}, near enough without ICU (as haiku/core/Query.cpp) */
static int is_letter(unsigned long cp)
{
	if (cp < 0x80)
		return (cp >= 'a' && cp <= 'z') || (cp >= 'A' && cp <= 'Z');
	if (is_space(cp) || is_number(cp))
		return 0;
	if (cp <= 0xBF)
		return cp == 0xAA || cp == 0xB5 || cp == 0xBA;
	if (cp == 0xD7 || cp == 0xF7)
		return 0;
	if (cp >= 0x2000 && cp <= 0x2BFF)
		return 0;
	if (cp >= 0x3000 && cp <= 0x3004)
		return 0;
	if (cp >= 0x3008 && cp <= 0x3020)
		return 0;
	if ((cp >= 0xFE30 && cp <= 0xFE4F) || (cp >= 0xFF00 && cp <= 0xFF0F) || (cp >= 0xFF1A && cp <= 0xFF20)
			|| (cp >= 0xFF3B && cp <= 0xFF40) || (cp >= 0xFF5B && cp <= 0xFF65))
		return 0;
	if (cp >= 0x1F000UL && cp <= 0x1FAFFUL)
		return 0;
	if (cp == 0xFFFD)
		return 0;
	return 1;
}

/* -- words --------------------------------------------------------------------------------- */

/* The next word of s from *i (JS's split(/\s+/), empties dropped): its start and length; 0 at the end. */
static int next_word(const char *s, long len, long *i, long *start, long *n)
{
	long at;
	unsigned long cp;

	while (*i < len) {
		at = *i;
		cp = next_cp(s, len, i);
		if (!is_space(cp)) {
			*i = at;
			break;
		}
	}
	if (*i >= len)
		return 0;
	*start = *i;
	while (*i < len) {
		at = *i;
		cp = next_cp(s, len, i);
		if (is_space(cp)) {
			*i = at;
			break;
		}
	}
	*n = *i - *start;
	return 1;
}

static int has_word(const char *s, const char *w)
{
	long len = (long) strlen(s), i = 0, start, n, wn = (long) strlen(w);

	while (next_word(s, len, &i, &start, &n))
		if (n == wn && memcmp(s + start, w, (size_t) wn) == 0)
			return 1;
	return 0;
}

static int quote_count(const char *s)
{
	int q = 0;
	for (; *s; s++)
		if (*s == '"')
			q++;
	return q;
}

static int lower(int c)
{
	return (c >= 'A' && c <= 'Z') ? c + 32 : c;
}

static int starts_with_ci(const char *s, long n, const char *prefix)
{
	long k = (long) strlen(prefix), j;
	if (n < k)
		return 0;
	for (j = 0; j < k; j++)
		if (lower((unsigned char) s[j]) != prefix[j])
			return 0;
	return 1;
}

/* search-core's HISTER_ONLY: /^(-?(label|added|updated|url|domain|type|language|metadata\.[\w.]+):|@\S+$)/i */
static int is_hister_only(const char *w, long n)
{
	static const char *const fields[] = {"label:", "added:", "updated:", "url:", "domain:", "type:", "language:"};
	unsigned int f;
	long k, start;

	if (n >= 2 && w[0] == '@')
		return 1;
	if (n > 0 && w[0] == '-') {
		w++;
		n--;
	}
	for (f = 0; f < sizeof(fields) / sizeof(fields[0]); f++)
		if (starts_with_ci(w, n, fields[f]))
			return 1;
	if (starts_with_ci(w, n, "metadata.")) {
		start = k = 9;
		while (k < n) {
			int c = lower((unsigned char) w[k]);
			int word = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '.';
			if (c == ':' && k > start)
				return 1;
			if (!word)
				return 0;
			k++;
		}
	}
	return 0;
}

/* -- the rules ------------------------------------------------------------------------------- */

static const char kNotesExclusion[] = "-label:vault -metadata.source:vault";

const char *shiori_pill_label(int pill)
{
	switch (pill) {
	case PILL_PAGES: return "Pages";
	case PILL_NOTES: return "Notes";
	case PILL_CODE: return "Code";
	}
	return "All";
}

int shiori_trim(const char *s, char *out, long cap)
{
	long len = (long) strlen(s), i = 0, at, first = -1, last = 0;
	unsigned long cp;

	while (i < len) {
		at = i;
		cp = next_cp(s, len, &i);
		if (!is_space(cp)) {
			if (first < 0)
				first = at;
			last = i;
		}
	}
	if (first < 0)
		first = last = 0;
	/* out may be s itself: move the bytes before anything is written */
	len = last - first;
	if (len >= cap) {
		len = cap - 1;
		if (len < 0)
			return 0;
		memmove(out, s + first, (size_t) len);
		out[len] = '\0';
		return 0;
	}
	memmove(out, s + first, (size_t) len);
	out[len] = '\0';
	return 1;
}

int shiori_prefix_last_word(const char *t, int unionForm, char *out, long cap)
{
	long len = (long) strlen(t), i = 0, start = 0, at = 0, cps = 0;
	unsigned long cp = 0, last = 0;
	int letter = 0;
	Buf b;

	if (len == 0)
		return b_set(out, cap, t, len);
	while (i < len) {
		last = next_cp(t, len, &i);
		if (is_space(last))
			start = i;
	}
	if (is_space(last) || quote_count(t) % 2)
		return b_set(out, cap, t, len);
	/* the last word: everything after the last space; at least two code
	   points, letters and numbers only, one letter at least */
	i = start;
	while (i < len) {
		at = i;
		cp = next_cp(t, len, &i);
		cps++;
		if (is_letter(cp))
			letter = 1;
		else if (!is_number(cp))
			return b_set(out, cap, t, len);
	}
	(void) at;
	if (cps < 2 || !letter)
		return b_set(out, cap, t, len);
	b_init(&b, out, cap);
	if (unionForm) {
		b_addn(&b, t, start);
		b_add(&b, "(");
		b_add(&b, t + start);
		b_add(&b, "|");
		b_add(&b, t + start);
		b_add(&b, "*)");
	} else {
		b_add(&b, t);
		b_add(&b, "*");
	}
	return b.ok;
}

int shiori_hister_text(const char *text, char *out, long cap)
{
	char a[SHIORI_MAX_TEXT + 8], c[2 * SHIORI_MAX_TEXT + 16];
	Buf b;

	if (!shiori_trim(text, a, (long) sizeof(a) - 1))
		return b_set(out, cap, "", 0) && 0;
	if (quote_count(a) % 2)
		strcat(a, "\"");
	if (!shiori_prefix_last_word(a, 1, c, (long) sizeof(c)))
		return b_set(out, cap, "", 0) && 0;
	/* never the notes (ExcludingNotes over the trimmed text) */
	if (!shiori_trim(c, c, (long) sizeof(c)))
		return 0;
	b_init(&b, out, cap);
	b_add(&b, c);
	if (!(has_word(c, "-label:vault") && has_word(c, "-metadata.source:vault"))) {
		if (c[0])
			b_add(&b, " ");
		b_add(&b, kNotesExclusion);
	}
	if (!has_word(out, "type:local") && !has_word(out, "-type:local"))
		b_add(&b, " -type:local");
	if (!has_word(out, "metadata.source:code") && !has_word(out, "-metadata.source:code"))
		b_add(&b, " -metadata.source:code");
	return b.ok;
}

static int term_query(const char *term, const char *typed, char *out, long cap)
{
	char t[SHIORI_MAX_TEXT + 1];
	Buf b;

	if (!shiori_trim(typed, t, (long) sizeof(t)))
		return 0;
	b_init(&b, out, cap);
	b_add(&b, term);
	b_add(&b, " ");
	b_add(&b, t[0] ? t : "*");
	return b.ok;
}

int shiori_code_query(const char *typed, char *out, long cap)
{
	return term_query("metadata.source:code", typed, out, cap);
}

int shiori_files_query(const char *typed, char *out, long cap)
{
	return term_query("type:local", typed, out, cap);
}

int shiori_web_query(const char *q, char *out, long cap)
{
	long len = (long) strlen(q), i = 0, start, n;
	Buf b;

	b_init(&b, out, cap);
	while (next_word(q, len, &i, &start, &n)) {
		if (is_hister_only(q + start, n))
			continue;
		if (b.len > 0)
			b_add(&b, " ");
		b_addn(&b, q + start, n);
	}
	return b.ok;
}

int shiori_kura_query(const char *q, char *out, long cap)
{
	char w[SHIORI_MAX_TEXT + 1];

	if (!shiori_web_query(q, w, (long) sizeof(w)))
		return 0;
	if (strcmp(w, "*") == 0)
		return b_set(out, cap, "", 0);
	return shiori_prefix_last_word(w, 0, out, cap);
}

static int encode(const char *s, char *out, long cap, int form)
{
	static const char hex[] = "0123456789ABCDEF";
	Buf b;
	char e[4];

	b_init(&b, out, cap);
	for (; *s; s++) {
		unsigned char c = (unsigned char) *s;
		int safe = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
			|| c == '*' || c == '-' || c == '.' || c == '_'
			|| (!form && (c == '!' || c == '~' || c == '\'' || c == '(' || c == ')'));
		if (form && c == ' ') {
			b_add(&b, "+");
		} else if (safe) {
			b_addn(&b, (const char *) &c, 1);
		} else {
			e[0] = '%';
			e[1] = hex[c >> 4];
			e[2] = hex[c & 15];
			b_addn(&b, e, 3);
		}
	}
	return b.ok;
}

int shiori_form_encode(const char *s, char *out, long cap)
{
	return encode(s, out, cap, 1);
}

int shiori_uri_encode(const char *s, char *out, long cap)
{
	return encode(s, out, cap, 0);
}

/* JSON.stringify's string */
static void json_string_to(Buf *b, const char *s)
{
	static const char hex[] = "0123456789abcdef";
	char e[7];

	b_add(b, "\"");
	for (; *s; s++) {
		unsigned char c = (unsigned char) *s;
		switch (c) {
		case '"': b_add(b, "\\\""); break;
		case '\\': b_add(b, "\\\\"); break;
		case '\b': b_add(b, "\\b"); break;
		case '\f': b_add(b, "\\f"); break;
		case '\n': b_add(b, "\\n"); break;
		case '\r': b_add(b, "\\r"); break;
		case '\t': b_add(b, "\\t"); break;
		default:
			if (c < 0x20) {
				strcpy(e, "\\u00");
				e[4] = hex[c >> 4];
				e[5] = hex[c & 15];
				e[6] = '\0';
				b_add(b, e);
			} else {
				b_addn(b, (const char *) &c, 1);
			}
		}
	}
	b_add(b, "\"");
}

int shiori_hister_search_target(const char *typed, int pill, int limit, const char *pageKey, char *out, long cap)
{
	char t[SHIORI_MAX_TEXT + 1], words[SHIORI_MAX_TEXT + 32], text[2 * SHIORI_MAX_TEXT + 96];
	char json[2 * SHIORI_MAX_TEXT + 256];
	int newest;
	Buf j, b;

	if (!shiori_trim(typed, t, (long) sizeof(t)))
		return 0;
	newest = t[0] == '\0';
	if (pill == PILL_CODE) {
		if (!shiori_code_query(newest ? "*" : typed, words, (long) sizeof(words)))
			return 0;
	} else if (!b_set(words, (long) sizeof(words), newest ? "*" : typed, (long) strlen(newest ? "*" : typed))) {
		return 0;
	}
	if (!shiori_hister_text(words, text, (long) sizeof(text)))
		return 0;
	b_init(&j, json, (long) sizeof(json));
	b_add(&j, "{\"text\":");
	json_string_to(&j, text);
	b_add(&j, ",\"highlight\":\"HTML\",\"limit\":");
	b_add_num(&j, limit);
	if (newest)
		b_add(&j, ",\"sort\":\"date\"");
	if (pageKey != NULL && pageKey[0]) {
		b_add(&j, ",\"page_key\":");
		json_string_to(&j, pageKey);
	}
	b_add(&j, "}");
	if (!j.ok)
		return 0;
	b_init(&b, out, cap);
	b_add(&b, "search?query=");
	if (!b.ok)
		return 0;
	return shiori_form_encode(json, out + b.len, cap - b.len);
}

int shiori_kura_search_target(const char *typed, int limit, long offset, const char *vault, char *out, long cap)
{
	char text[SHIORI_MAX_TEXT + 8];
	Buf b;
	long n;

	if (!shiori_kura_query(typed, text, (long) sizeof(text)))
		return 0;
	b_init(&b, out, cap);
	b_add(&b, text[0] ? "api/search?" : "api/recent?");
	b_add(&b, "limit=");
	b_add_num(&b, limit);
	b_add(&b, "&offset=");
	b_add_num(&b, offset);
	if (vault != NULL && vault[0]) {
		b_add(&b, "&vault=");
		if (!b.ok || !shiori_form_encode(vault, out + b.len, cap - b.len))
			return 0;
		b.len += (long) strlen(out + b.len);
	}
	if (text[0]) {
		b_add(&b, "&q=");
		if (!b.ok)
			return 0;
		n = b.len;
		if (!shiori_form_encode(text, out + n, cap - n))
			return 0;
		b.len = n + (long) strlen(out + n);
		b_add(&b, "&sort=relevance");
	}
	return b.ok;
}
