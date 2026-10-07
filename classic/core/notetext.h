/*
 * notetext.h: a note's or page's readable HTML (Kura's /api/note "html", a
 * sanitized allow-list; Hister's /api/preview "content") as styled text for
 * the reader: headings, bold, italic, code, quotes, lists, tables as lines,
 * images as their alt text, links. A C port of haiku/core/NoteText, with the
 * Mac's needs: the text can come out as Mac Roman (so run offsets stay
 * true), and Kura's wikilinks resolve to a note to open.
 * Portable C89, no allocation: the caller gives every buffer.
 */
#ifndef SHIORI_NOTETEXT_H
#define SHIORI_NOTETEXT_H

enum {
	STYLE_PLAIN = 0,
	STYLE_BOLD = 1,
	STYLE_ITALIC = 2,
	STYLE_CODE = 4,
	STYLE_HEADING = 8,      /* h1-h2 */
	STYLE_SUBHEADING = 16,  /* h3-h6 */
	STYLE_QUOTE = 32,
	STYLE_LINK = 64
};

typedef struct NoteRun {
	long offset;            /* into text */
	unsigned char style;
	long href;              /* into hrefs (a NUL-ended address), or -1 */
} NoteRun;

typedef struct NoteText {
	char *text;             /* the caller's: text, NUL-ended */
	long textCap, textLen;
	NoteRun *runs;
	int runCap, runCount;
	char *hrefs;            /* link addresses, each NUL-ended (UTF-8) */
	long hrefCap, hrefLen;
	int roman;              /* 1: the text as Mac Roman; 0: UTF-8 */
	int truncated;          /* something didn't fit */
} NoteText;

void note_text_init(NoteText *t, char *text, long textCap, NoteRun *runs, int runCap, char *hrefs, long hrefCap,
	int roman);
/* Converts html (len bytes) into t. Only http(s) addresses become links. */
void shiori_note_html_to_text(const char *html, long len, NoteText *t);
/* The link at a text offset ("" for none). */
const char *note_link_at(const NoteText *t, long offset);

/* A top-level string member of a JSON object: its raw token (undecoded, no
   quotes), for json_decode into a buffer the caller sizes. 0 when absent. */
int shiori_json_member(const char *buf, long len, const char *key, const char **raw, long *rawLen);

/* Kura's note, relative to the Kura base: api/note?path=…[&vault=…]. */
int shiori_kura_note_target(const char *path, const char *vault, char *out, long cap);
/* Hister's readable copy, relative to the Hister base: api/preview?url=…. */
int shiori_hister_preview_target(const char *url, char *out, long cap);

/* Which vault a note's address names: <base>/v/<vault>/n/… gives the vault,
   anything else (the default vault's /n/…) "". As search-core's noteVault: the
   address decides, never a reply's vault field (Kura names the default too). */
void shiori_url_vault(const char *url, char *out, long cap);

/* Whether href is a wikilink to another note on the same Kura as noteURL
   (the note being read): <base>/n/<slug> or <base>/v/<vault>/n/<slug>, a
   #fragment dropped. Then path is the slug percent-decoded plus ".md", and
   vault the name ("" for the default vault). */
int shiori_note_link(const char *href, const char *noteURL, char *path, long pathCap, char *vault, long vaultCap);

#endif
