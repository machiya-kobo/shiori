/*
 * json.h: a pull parser for JSON replies, small enough for a Mac Plus.
 * It never allocates: tokens point into the caller's buffer, and strings
 * are decoded (escapes, \u, surrogate pairs) into a caller's buffer as
 * UTF-8 only when asked for. Portable C89; no Toolbox headers.
 */
#ifndef SHIORI_JSON_H
#define SHIORI_JSON_H

enum {
	JSON_ERROR = -1,
	JSON_EOF = 0,
	JSON_OBJECT,       /* { */
	JSON_OBJECT_END,   /* } */
	JSON_ARRAY,        /* [ */
	JSON_ARRAY_END,    /* ] */
	JSON_KEY,          /* a member's name (the token's raw text) */
	JSON_STRING,
	JSON_NUMBER,
	JSON_TRUE,
	JSON_FALSE,
	JSON_NULL
};

#define JSON_MAX_DEPTH 24

typedef struct JsonReader {
	const char *p, *end;
	const char *tok;            /* the last string, key or number: raw, without quotes */
	long tokLen;
	int depth;
	char stack[JSON_MAX_DEPTH]; /* '{' or '[' per open container */
	int wantKey;                /* inside an object, a key comes next */
	int afterValue;             /* a ',' or the container's end comes next */
	int done;                   /* the top-level value is complete */
	int justOpened;             /* an array just opened: ']' may close it */
	int objectOpened;           /* an object just opened: '}' may close it */
} JsonReader;

void json_init(JsonReader *r, const char *buf, long len);
/* The next token, JSON_EOF after the one top-level value, JSON_ERROR on bad input. */
int json_next(JsonReader *r);
/* After an OBJECT or ARRAY token: skips to its end. After a KEY: skips the
   member's value. Returns the last token read (JSON_ERROR on bad input). */
int json_skip(JsonReader *r, int token);
/* The last KEY or STRING decoded into out (UTF-8, NUL-terminated, cut at a
   character boundary to fit cap); returns its length. */
long json_string(const JsonReader *r, char *out, long cap);
/* Whether the last KEY is exactly k (keys are compared undecoded). */
int json_is(const JsonReader *r, const char *k);
/* The last NUMBER as a long (fraction and exponent dropped; 0 if not a number). */
long json_long(const JsonReader *r);

#endif
