/*
 * query.h: what a search sends. The twins of search-core.js's query rules
 * (patches/shiori/search-core.js; HisterKit's SearchText; haiku/core/Query),
 * checked against vectors generated from search-core itself
 * (haiku/tests/gen-vectors.mjs --c > classic/tests/vectors.h). When
 * search-core's rules change, these change in the same series.
 *
 * Portable C89, no allocation: every function writes a NUL-terminated
 * UTF-8 result into out (cap bytes) and returns 1, or 0 when it didn't fit
 * (out then holds as much as fitted). Inputs are UTF-8, at most
 * SHIORI_MAX_TEXT bytes.
 */
#ifndef SHIORI_QUERY_H
#define SHIORI_QUERY_H

#define SHIORI_MAX_TEXT 512

enum { PILL_ALL, PILL_PAGES, PILL_NOTES, PILL_CODE };

const char *shiori_pill_label(int pill);

int shiori_trim(const char *text, char *out, long cap);
/* the last word as a prefix: "hist" -> "hist*", or with unionForm "(hist|hist*)" */
int shiori_prefix_last_word(const char *text, int unionForm, char *out, long cap);
/* a Hister search as sent: the last word a prefix, never the notes, files or code unless asked */
int shiori_hister_text(const char *text, char *out, long cap);
int shiori_code_query(const char *typed, char *out, long cap);
int shiori_files_query(const char *typed, char *out, long cap);
/* the query without Hister-only operators */
int shiori_web_query(const char *q, char *out, long cap);
/* a search as Kura reads it ('' for Kura's recent list) */
int shiori_kura_query(const char *q, char *out, long cap);

/* URLSearchParams' form encoding (space as "+") and encodeURIComponent */
int shiori_form_encode(const char *s, char *out, long cap);
int shiori_uri_encode(const char *s, char *out, long cap);

/* Hister's search, relative to the Hister base: search?query=<JSON>. No words:
   the newest ("*" sorted by date); PILL_NOTES asks Hister for notes (label:vault). pageKey: the last reply's page_key, raw as
   ShioriPage.next keeps it (JSON escapes intact: Hister's holds \u0000), or "". */
/* Where notes come from (scripts/notes-source-cases.json): "hister" when chosen, else
   "kura" when one is set up, else "hister". choice: the setting ("" until chosen). */
const char *shiori_notes_source(const char *choice, int kuraConfigured);
/* Hister's query for notes: the words (the last a prefix), "*" for the newest, and label:vault. */
int shiori_hister_notes_text(const char *text, char *out, long cap);
int shiori_hister_search_target(const char *typed, int pill, int limit, const char *pageKey, char *out, long cap);
/* Kura's, relative to the Kura base: api/search?… or api/recent?…; vault "" (the
   default vault), a name, or "all" */
int shiori_kura_search_target(const char *typed, int limit, long offset, const char *vault, char *out, long cap);

#endif
