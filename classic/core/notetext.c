/* notetext.c: see notetext.h. Follows haiku/core/NoteText.cpp. */
#include <stdio.h>
#include <string.h>

#include "json.h"
#include "notetext.h"
#include "query.h"
#include "results.h"
#include "roman.h"

#define MAX_FRAMES 32
#define MAX_LISTS 8

typedef struct Frame {
	char tag[12];
	unsigned char style;
	long href;
} Frame;

typedef struct Builder {
	NoteText *t;
	Frame frames[MAX_FRAMES];
	int depth;
	int pre;
	int lists[MAX_LISTS];       /* per open list: 0 for ul, else the next number */
	int listDepth;
} Builder;

static int lower(int c)
{
	return (c >= 'A' && c <= 'Z') ? c + 32 : c;
}

static int is_space(int c)
{
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
}

void note_text_init(NoteText *t, char *text, long textCap, NoteRun *runs, int runCap, char *hrefs, long hrefCap,
	int roman)
{
	memset(t, 0, sizeof(*t));
	t->text = text;
	t->textCap = textCap;
	t->runs = runs;
	t->runCap = runCap;
	t->hrefs = hrefs;
	t->hrefCap = hrefCap;
	t->roman = roman;
	if (textCap > 0)
		text[0] = '\0';
}

static int at_line_start(const NoteText *t)
{
	return t->textLen == 0 || t->text[t->textLen - 1] == '\n';
}

static int ends_with_space(const NoteText *t)
{
	return t->textLen > 0 && t->text[t->textLen - 1] == ' ';
}

static void trim_trailing_space(NoteText *t)
{
	while (t->textLen > 0 && t->text[t->textLen - 1] == ' ')
		t->textLen--;
	t->text[t->textLen] = '\0';
	while (t->runCount > 0 && t->runs[t->runCount - 1].offset > t->textLen)
		t->runCount--;
}

static void current_style(const Builder *b, unsigned char *style, long *href)
{
	int i;

	*style = STYLE_PLAIN;
	*href = -1;
	for (i = 0; i < b->depth; i++) {
		*style |= b->frames[i].style;
		if (b->frames[i].href >= 0)
			*href = b->frames[i].href;
	}
}

/* Appends s (UTF-8, n bytes) in the current style. */
static void emit(Builder *b, const char *s, long n)
{
	NoteText *t = b->t;
	unsigned char style;
	long href, i;

	if (n <= 0)
		return;
	current_style(b, &style, &href);
	if (t->runCount == 0 || t->runs[t->runCount - 1].style != style || t->runs[t->runCount - 1].href != href) {
		/* a run that never got text gives way */
		if (t->runCount > 0 && t->runs[t->runCount - 1].offset == t->textLen)
			t->runCount--;
		if (t->runCount == 0 || t->runs[t->runCount - 1].style != style || t->runs[t->runCount - 1].href != href) {
			if (t->runCount >= t->runCap) {
				t->truncated = 1;
				return;
			}
			t->runs[t->runCount].offset = t->textLen;
			t->runs[t->runCount].style = style;
			t->runs[t->runCount].href = href;
			t->runCount++;
		}
	}
	if (!t->roman) {
		if (t->textLen + n >= t->textCap) {
			t->truncated = 1;
			n = t->textCap - 1 - t->textLen;
			/* never half a character */
			while (n > 0 && ((unsigned char) s[n] & 0xC0) == 0x80)
				n--;
			if (n <= 0)
				return;
		}
		memcpy(t->text + t->textLen, s, (size_t) n);
		t->textLen += n;
		t->text[t->textLen] = '\0';
		return;
	}
	for (i = 0; i < n;) {
		unsigned char c = (unsigned char) s[i];
		unsigned long cp;
		int extra, k;
		if (c < 0x80) {
			cp = c;
			i++;
		} else {
			extra = (c >= 0xF0) ? 3 : (c >= 0xE0) ? 2 : (c >= 0xC0) ? 1 : -1;
			i++;
			if (extra < 0) {
				cp = '?';
			} else {
				cp = c & (0x3F >> extra);
				for (k = 0; k < extra && i < n && ((unsigned char) s[i] & 0xC0) == 0x80; k++)
					cp = (cp << 6) | ((unsigned char) s[i++] & 0x3F);
				if (k < extra)
					cp = '?';
			}
		}
		c = roman_from_cp(cp);
		if (c == 0)
			continue;
		if (t->textLen + 1 >= t->textCap) {
			t->truncated = 1;
			return;
		}
		t->text[t->textLen++] = (char) c;
	}
	t->text[t->textLen] = '\0';
}

static void emits(Builder *b, const char *s)
{
	emit(b, s, (long) strlen(s));
}

/* text between tags: entities decoded, whitespace folded (none at a line's start) unless in <pre> */
static void text(Builder *b, const char *raw, long n)
{
	char buf[512];
	long start = 0;

	while (start < n) {
		long chunk = n - start, k, m = 0;
		char out[512];
		/* decode in chunks that never split an entity: end a chunk after a ';' or at a space */
		if (chunk > (long) sizeof(buf) - 1) {
			chunk = (long) sizeof(buf) - 1;
			for (k = chunk; k > chunk - 16 && k > 0; k--)
				if (raw[start + k - 1] == ';' || raw[start + k - 1] == ' ')
					break;
			if (k > chunk - 16 && k > 0)
				chunk = k;
			while (chunk > 1 && ((unsigned char) raw[start + chunk] & 0xC0) == 0x80)
				chunk--;
		}
		memcpy(buf, raw + start, (size_t) chunk);
		buf[chunk] = '\0';
		start += chunk;
		shiori_decode_entities(buf);
		if (b->pre > 0) {
			emits(b, buf);
			continue;
		}
		for (k = 0; buf[k]; k++) {
			if (!is_space((unsigned char) buf[k])) {
				out[m++] = buf[k];
				continue;
			}
			{
				int lineStart = m == 0 && at_line_start(b->t);
				int afterSpace = m == 0 ? ends_with_space(b->t) : out[m - 1] == ' ';
				if (!lineStart && !afterSpace)
					out[m++] = ' ';
			}
		}
		emit(b, out, m);
	}
}

/* a block boundary: at most one blank line between blocks */
static void block(Builder *b)
{
	NoteText *t = b->t;

	trim_trailing_space(t);
	if (t->textLen == 0)
		return;
	if (t->textLen >= 2 && t->text[t->textLen - 1] == '\n' && t->text[t->textLen - 2] == '\n')
		return;
	emits(b, t->text[t->textLen - 1] == '\n' ? "\n" : "\n\n");
}

static void line(Builder *b)
{
	trim_trailing_space(b->t);
	if (!at_line_start(b->t))
		emits(b, "\n");
}

static void push(Builder *b, const char *tag, unsigned char style, long href)
{
	if (b->depth >= MAX_FRAMES)
		return;
	strncpy(b->frames[b->depth].tag, tag, sizeof(b->frames[0].tag) - 1);
	b->frames[b->depth].tag[sizeof(b->frames[0].tag) - 1] = '\0';
	b->frames[b->depth].style = style;
	b->frames[b->depth].href = href;
	b->depth++;
}

static void pop(Builder *b, const char *tag)
{
	int i;

	for (i = b->depth; i > 0; i--) {
		if (strcmp(b->frames[i - 1].tag, tag) == 0) {
			memmove(&b->frames[i - 1], &b->frames[i], sizeof(Frame) * (size_t) (b->depth - i));
			b->depth--;
			return;
		}
	}
}

static void toggle(Builder *b, int closing, const char *tag, unsigned char style)
{
	if (closing)
		pop(b, tag);
	else
		push(b, tag, style, -1);
}

/* An attribute's value from a tag's inside (`a href="…" class=x`), entities decoded, trimmed. */
static void attribute(const char *inside, long n, const char *name, char *out, long cap)
{
	long nameLen = (long) strlen(name), at, eq, v, end, k;

	out[0] = '\0';
	for (at = 1; at + nameLen <= n; at++) {
		for (k = 0; k < nameLen; k++)
			if (lower((unsigned char) inside[at + k]) != name[k])
				break;
		if (k < nameLen || !is_space((unsigned char) inside[at - 1]))
			continue;
		eq = at + nameLen;
		while (eq < n && is_space((unsigned char) inside[eq]))
			eq++;
		if (eq >= n || inside[eq] != '=')
			continue;
		v = eq + 1;
		while (v < n && is_space((unsigned char) inside[v]))
			v++;
		if (v >= n)
			return;
		if (inside[v] == '"' || inside[v] == '\'') {
			char q = inside[v++];
			for (end = v; end < n && inside[end] != q; end++)
				;
		} else {
			for (end = v; end < n && !is_space((unsigned char) inside[end]); end++)
				;
		}
		if (end - v >= cap)
			return;                          /* too long to be useful: no value at all */
		memcpy(out, inside + v, (size_t) (end - v));
		out[end - v] = '\0';
		shiori_decode_entities(out);
		shiori_trim(out, out, cap);
		return;
	}
}

static long add_href(NoteText *t, const char *href)
{
	long n = (long) strlen(href), at = t->hrefLen;

	if (t->hrefLen + n + 1 > t->hrefCap) {
		t->truncated = 1;
		return -1;
	}
	memcpy(t->hrefs + t->hrefLen, href, (size_t) n + 1);
	t->hrefLen += n + 1;
	return at;
}

void shiori_note_html_to_text(const char *html, long len, NoteText *t)
{
	Builder b;
	long i = 0, lt, gt, k, n;
	int skip = 0;
	char name[12], value[300];
	const char *inside;

	memset(&b, 0, sizeof(b));
	b.t = t;
	while (i < len) {
		for (lt = i; lt < len && html[lt] != '<'; lt++)
			;
		if (skip == 0 && lt > i)
			text(&b, html + i, lt - i);
		if (lt >= len)
			break;
		if (lt + 4 <= len && memcmp(html + lt, "<!--", 4) == 0) {
			for (k = lt + 4; k + 3 <= len && memcmp(html + k, "-->", 3) != 0; k++)
				;
			i = k + 3 <= len ? k + 3 : len;
			continue;
		}
		for (gt = lt; gt < len && html[gt] != '>'; gt++)
			;
		if (gt >= len)
			break;
		inside = html + lt + 1;
		n = gt - lt - 1;
		i = gt + 1;
		{
			int closing = n > 0 && inside[0] == '/';
			long m = 0;
			for (k = closing ? 1 : 0; k < n && m < (long) sizeof(name) - 1
					&& ((inside[k] >= 'a' && inside[k] <= 'z') || (inside[k] >= 'A' && inside[k] <= 'Z')
						|| (inside[k] >= '0' && inside[k] <= '9')); k++)
				name[m++] = (char) lower((unsigned char) inside[k]);
			name[m] = '\0';
			if (strcmp(name, "script") == 0 || strcmp(name, "style") == 0 || strcmp(name, "template") == 0) {
				skip += closing ? -1 : 1;
				if (skip < 0)
					skip = 0;
				continue;
			}
			if (skip > 0)
				continue;
			if (name[0] == 'h' && name[1] >= '1' && name[1] <= '6' && name[2] == '\0') {
				block(&b);
				toggle(&b, closing, name, name[1] <= '2' ? STYLE_HEADING : STYLE_SUBHEADING);
			} else if (!strcmp(name, "p") || !strcmp(name, "div") || !strcmp(name, "section")
					|| !strcmp(name, "article") || !strcmp(name, "table") || !strcmp(name, "figure")
					|| !strcmp(name, "details") || !strcmp(name, "summary")) {
				block(&b);
			} else if (!strcmp(name, "tr") || !strcmp(name, "dt") || !strcmp(name, "dd")) {
				line(&b);
			} else if (!strcmp(name, "br")) {
				trim_trailing_space(t);
				emits(&b, "\n");
			} else if (!strcmp(name, "hr")) {
				block(&b);
				emits(&b, "\xE2\x80\x94\xE2\x80\x94\xE2\x80\x94");
				block(&b);
			} else if (!strcmp(name, "blockquote")) {
				block(&b);
				toggle(&b, closing, name, STYLE_QUOTE);
			} else if (!strcmp(name, "pre")) {
				block(&b);
				toggle(&b, closing, name, STYLE_CODE);
				if (closing && b.pre > 0)
					b.pre--;
				else if (!closing)
					b.pre++;
			} else if (!strcmp(name, "ul") || !strcmp(name, "ol")) {
				if (closing) {
					if (b.listDepth > 0)
						b.listDepth--;
					if (b.listDepth == 0)
						block(&b);
				} else {
					if (b.listDepth == 0)
						block(&b);
					if (b.listDepth < MAX_LISTS)
						b.lists[b.listDepth] = !strcmp(name, "ol") ? 1 : 0;
					b.listDepth++;
				}
			} else if (!strcmp(name, "li")) {
				if (!closing) {
					char mark[48];
					int d = b.listDepth > MAX_LISTS ? MAX_LISTS : b.listDepth, level = d > 1 ? d - 1 : 0, s;
					line(&b);
					for (s = 0; s < level * 4 && s < 32; s++)
						mark[s] = ' ';
					mark[s] = '\0';
					if (d > 0 && b.lists[d - 1] > 0)
						sprintf(mark + s, "%d. ", b.lists[d - 1]++);
					else
						strcpy(mark + s, "\xE2\x80\xA2 ");
					emits(&b, mark);
				}
			} else if (!strcmp(name, "strong") || !strcmp(name, "b")) {
				toggle(&b, closing, name, STYLE_BOLD);
			} else if (!strcmp(name, "em") || !strcmp(name, "i")) {
				toggle(&b, closing, name, STYLE_ITALIC);
			} else if (!strcmp(name, "code") || !strcmp(name, "kbd") || !strcmp(name, "samp")) {
				toggle(&b, closing, name, STYLE_CODE);
			} else if (!strcmp(name, "a")) {
				if (closing) {
					pop(&b, name);
				} else {
					/* only web addresses are links; anything else is plain text */
					attribute(inside, n, "href", value, (long) sizeof(value));
					if (shiori_is_web_url(value))
						push(&b, name, STYLE_LINK, add_href(t, value));
					else
						push(&b, name, STYLE_PLAIN, -1);
				}
			} else if (!strcmp(name, "img") && !closing) {
				attribute(inside, n, "alt", value + 1, (long) sizeof(value) - 2);
				if (value[1]) {
					value[0] = '[';
					strcat(value, "]");
					text(&b, value, (long) strlen(value));
				}
			} else if ((!strcmp(name, "td") || !strcmp(name, "th")) && !closing) {
				text(&b, " ", 1);
			}
		}
	}
	/* trailing blank lines go */
	while (t->textLen > 0 && (t->text[t->textLen - 1] == '\n' || t->text[t->textLen - 1] == ' '))
		t->textLen--;
	if (t->textCap > 0)
		t->text[t->textLen] = '\0';
	while (t->runCount > 1 && t->runs[t->runCount - 1].offset >= t->textLen)
		t->runCount--;
	if (t->runCount == 0 && t->runCap > 0) {
		t->runs[0].offset = 0;
		t->runs[0].style = STYLE_PLAIN;
		t->runs[0].href = -1;
		t->runCount = 1;
	}
}

const char *note_link_at(const NoteText *t, long offset)
{
	long href = -1;
	int i;

	if (offset < 0 || offset >= t->textLen)
		return "";
	for (i = 0; i < t->runCount; i++) {
		if (t->runs[i].offset > offset)
			break;
		href = t->runs[i].href;
	}
	return href >= 0 ? t->hrefs + href : "";
}

int shiori_json_member(const char *buf, long len, const char *key, const char **raw, long *rawLen)
{
	JsonReader r;
	int t;

	json_init(&r, buf, len);
	if (json_next(&r) != JSON_OBJECT)
		return 0;
	while ((t = json_next(&r)) == JSON_KEY) {
		if (json_is(&r, key)) {
			if (json_next(&r) != JSON_STRING)
				return 0;
			*raw = r.tok;
			*rawLen = r.tokLen;
			return 1;
		}
		if (json_skip(&r, JSON_KEY) == JSON_ERROR)
			return 0;
	}
	return 0;
}

static int target(const char *head, const char *name1, const char *value1, const char *name2, const char *value2,
	char *out, long cap)
{
	long n;

	if ((long) strlen(head) + 1 >= cap)
		return 0;
	strcpy(out, head);
	strcat(out, name1);
	n = (long) strlen(out);
	if (!shiori_form_encode(value1, out + n, cap - n))
		return 0;
	if (value2 != NULL && value2[0]) {
		n = (long) strlen(out);
		if (n + (long) strlen(name2) + 1 >= cap)
			return 0;
		strcat(out, name2);
		n = (long) strlen(out);
		if (!shiori_form_encode(value2, out + n, cap - n))
			return 0;
	}
	return 1;
}

int shiori_kura_note_target(const char *path, const char *vault, char *out, long cap)
{
	return target("api/note?", "path=", path, "&vault=", vault, out, cap);
}

int shiori_hister_preview_target(const char *url, char *out, long cap)
{
	return target("api/preview?", "url=", url, NULL, NULL, out, cap);
}

static int hexval(int c)
{
	if (c >= '0' && c <= '9')
		return c - '0';
	c = lower(c);
	if (c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	return -1;
}

/* the note's base: everything before "/n/" or "/v/" in its address */
static long base_length(const char *url)
{
	const char *n = shiori_strstr(url, "/n/"), *v = shiori_strstr(url, "/v/"), *p;

	p = n == NULL ? v : (v == NULL ? n : (n < v ? n : v));
	return p == NULL ? -1 : (long) (p - url);
}

void shiori_url_vault(const char *url, char *out, long cap)
{
	const char *v = shiori_strstr(url, "/v/"), *name, *slash, *c;

	out[0] = '\0';
	if (v == NULL)
		return;
	name = v + 3;
	slash = strchr(name, '/');
	if (slash == NULL || strncmp(slash, "/n/", 3) != 0 || slash == name || slash - name >= cap)
		return;
	for (c = name; c < slash; c++)
		if (!((*c >= 'a' && *c <= 'z') || (*c >= '0' && *c <= '9') || *c == '-'))
			return;
	memcpy(out, name, (size_t) (slash - name));
	out[slash - name] = '\0';
}

int shiori_note_link(const char *href, const char *noteURL, char *path, long pathCap, char *vault, long vaultCap)
{
	long base = base_length(noteURL), n, k;
	const char *rest, *slug, *end;

	path[0] = vault[0] = '\0';
	if (base < 0 || strncmp(href, noteURL, (size_t) base) != 0)
		return 0;
	rest = href + base;
	if (strncmp(rest, "/n/", 3) == 0) {
		slug = rest + 3;
	} else if (strncmp(rest, "/v/", 3) == 0) {
		const char *name = rest + 3, *slash = strchr(name, '/');
		if (slash == NULL || strncmp(slash, "/n/", 3) != 0 || slash == name || slash - name >= vaultCap)
			return 0;
		for (k = 0; name + k < slash; k++) {
			char c = name[k];
			if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-'))
				return 0;
		}
		memcpy(vault, name, (size_t) (slash - name));
		vault[slash - name] = '\0';
		slug = slash + 3;
	} else {
		return 0;
	}
	end = slug + strcspn(slug, "#?");
	if (end == slug)
		return 0;
	/* percent-decoded once, then ".md" */
	for (n = 0, k = 0; slug + k < end; k++) {
		int c = (unsigned char) slug[k];
		if (c == '%' && slug + k + 2 < end + 1 && hexval(slug[k + 1]) >= 0 && hexval(slug[k + 2]) >= 0) {
			c = hexval(slug[k + 1]) * 16 + hexval(slug[k + 2]);
			k += 2;
		}
		if (n + 4 >= pathCap || c == 0) {
			path[0] = vault[0] = '\0';
			return 0;
		}
		path[n++] = (char) c;
	}
	path[n] = '\0';
	/* never out of the vault: no "." or ".." segment, no leading slash */
	if (path[0] == '/' || strcmp(path, "..") == 0 || strcmp(path, ".") == 0 || strncmp(path, "../", 3) == 0
			|| strncmp(path, "./", 2) == 0 || shiori_strstr(path, "/../") != NULL || shiori_strstr(path, "/./") != NULL
			|| (n >= 3 && strcmp(path + n - 3, "/..") == 0) || (n >= 2 && strcmp(path + n - 2, "/.") == 0)) {
		path[0] = vault[0] = '\0';
		return 0;
	}
	strcat(path, ".md");
	return 1;
}
