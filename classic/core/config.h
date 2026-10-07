/*
 * config.h: Shiori for Classic Macintosh's settings and the credential rule,
 * in one of two ways of reaching Hister (each request gets one credential at
 * most, never anywhere but the two addresses, never across a redirect):
 *   through mac-bridge  the room token (mht_…), as Authorization: Bearer, to
 *                       the bridge's two ports; the bridge holds Hister's own
 *                       token. Hister's token is never sent.
 *   directly to Hister  (a Hister served over plain HTTP) Hister's own access
 *                       token, as X-Access-Token, to Hister's address only
 *                       (haiku/core/Config's rule); the room token, as
 *                       Bearer, to Kura's address only. Kura is optional.
 * Origins compare as search-core's machiyaOrigin does (haiku/core/Config's OriginOf).
 */
#ifndef SHIORI_CONFIG_H
#define SHIORI_CONFIG_H

typedef struct ShioriConfig {
	char hister[96];        /* Hister's address: the bridge's port, or Hister itself */
	char kura[96];          /* Kura's address ("" for none: no notes) */
	char roomToken[48];     /* mht_ and 43 base64url characters */
	char histerToken[128];  /* Hister's own access token (direct only) */
	char direct;            /* 1: directly to Hister; 0: through mac-bridge */
} ShioriConfig;

/* "scheme://host[:port]" lowercased, the default port dropped; "" for anything
   not http(s) or with a user/password. */
void shiori_origin_of(const char *url, char *out, long cap);
/* A room token: mht_ and 43 base64url characters, trimmed; else "". */
void shiori_checked_room_token(const char *raw, char *out, long cap);
/* Hister's access token: 8 to 127 printable ASCII characters, trimmed; else ""
   (haiku/core/Config's CheckedHisterToken, with a Mac's smaller cap). */
void shiori_checked_hister_token(const char *raw, char *out, long cap);
/* Whether the app may call url at all: its origin is one of the two bridge addresses. */
int shiori_is_configured_origin(const ShioriConfig *c, const char *url);
/* The one credential header a request to url gets, or "": "Authorization: Bearer mht_…"
   or (direct, at Hister) "X-Access-Token: …". */
void shiori_credential_header(const ShioriConfig *c, const char *url, char *out, long cap);

#endif
