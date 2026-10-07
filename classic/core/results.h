/*
 * results.h: Hister's and Kura's replies as rows (haiku/core/Results,
 * HisterKit's DocumentWire, search-core's kuraDocuments), read with the
 * pull parser one row at a time, so a Mac Plus never holds a parsed tree.
 * Strings are UTF-8, cut to fit at a character boundary. Portable C89.
 */
#ifndef SHIORI_RESULTS_H
#define SHIORI_RESULTS_H

enum { ROW_PAGE = 'p', ROW_NOTE = 'n', ROW_CODE = 'c' };

typedef struct ShioriRow {
	char kind;              /* ROW_PAGE, ROW_NOTE or ROW_CODE */
	char url[256];
	char title[160];
	char host[64];          /* the page's host; a note's folder */
	char snippet[400];      /* HTML whose only markup is <mark> */
	char label[32];
	char path[160];         /* a note's path in its vault */
	char vault[48];         /* a note's vault ("" for Kura's default) */
	long added, updated;    /* unix seconds */
} ShioriRow;

typedef struct ShioriPage {
	int ok;                 /* the reply was a JSON object of the right shape */
	long total;
	char next[96];          /* Hister's page_key for the next page ("" at the end) */
	int received;           /* rows in the reply, ones dropped as non-web included */
} ShioriPage;

typedef void (*ShioriRowFn)(void *ctx, const ShioriRow *row);

/* Hister's /search: {total, documents: [{url, title, domain, label, text, added, updated, metadata}], page_key}.
   Only http(s) addresses become rows (a stored javascript: or file: link never opens). */
int shiori_parse_hister(const char *buf, long len, ShioriPage *page, ShioriRowFn fn, void *ctx);
/* Kura's /api/search or /api/recent: {total, results: [{url, path, vault, title, folder, snippet, summary, created, changed}]} */
int shiori_parse_kura(const char *buf, long len, ShioriPage *page, ShioriRowFn fn, void *ctx);

typedef struct ShioriVault {
	char name[48];          /* [a-z0-9-]+, as Kura allows */
	char title[64];
	int isDefault;
	int isPrivate;          /* Kura's "private" (true unless it says false: fail closed) */
} ShioriVault;

/* Kura's /api/vaults: {vaults: [{name, title, default, private}]}; how many were written. */
int shiori_parse_vaults(const char *buf, long len, ShioriVault *out, int max);

/* The host of an http(s) URL, lowercased, without "www." or the port; "" otherwise. */
void shiori_host_of(const char *url, char *out, long cap);
int shiori_is_web_url(const char *url);

/* Entities (&amp; &lt; &gt; &quot; &apos; &#..; &#x..; &nbsp;) decoded, in place. */
void shiori_decode_entities(char *s);

/* A snippet's HTML as text: entities decoded, tags dropped, whitespace folded,
   and <mark>…</mark> as SNIPPET_MARK_ON … SNIPPET_MARK_OFF bytes. */
#define SNIPPET_MARK_ON '\001'
#define SNIPPET_MARK_OFF '\002'
void shiori_snippet_text(const char *html, char *out, long cap);

#endif
