/*
 * config.h: Shiori for Classic Macintosh's settings and the one credential
 * rule. The Mac holds a room token (mht_…) and sends it, as
 * Authorization: Bearer, only to the two bridge addresses it was given
 * (Hister's and Kura's ports): never anywhere else, never across a redirect.
 * The bridge checks it and holds Hister's own token. Origins compare as
 * search-core's machiyaOrigin does (haiku/core/Config's OriginOf).
 */
#ifndef SHIORI_CONFIG_H
#define SHIORI_CONFIG_H

typedef struct ShioriConfig {
	char hister[96];        /* the bridge's Hister address, http://host:8070/ */
	char kura[96];          /* the bridge's Kura address, http://host:8071/ */
	char roomToken[48];     /* mht_ and 43 base64url characters */
} ShioriConfig;

/* "scheme://host[:port]" lowercased, the default port dropped; "" for anything
   not http(s) or with a user/password. */
void shiori_origin_of(const char *url, char *out, long cap);
/* A room token: mht_ and 43 base64url characters, trimmed; else "". */
void shiori_checked_room_token(const char *raw, char *out, long cap);
/* Whether the app may call url at all: its origin is one of the two bridge addresses. */
int shiori_is_configured_origin(const ShioriConfig *c, const char *url);
/* The one credential header a request to url gets ("Authorization: Bearer mht_…"), or "". */
void shiori_credential_header(const ShioriConfig *c, const char *url, char *out, long cap);

#endif
