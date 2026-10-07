/*
 * http.h: HTTP/1.0 for the Mac's side of the bridge: the request's text,
 * and the reply's head. Portable C89; the bytes move in app/net.c.
 */
#ifndef SHIORI_HTTP_H
#define SHIORI_HTTP_H

typedef struct HttpBase {
	char host[64];          /* the bridge's address as typed ("192.168.1.5") */
	unsigned short port;
	char path[64];          /* "/" or a prefix ending in "/" */
} HttpBase;

/* "http://host[:port][/path/]" -> base; 0 for anything else (https, userinfo,
   a query, a fragment, a bad port). */
int http_base(const char *url, HttpBase *out);

/* The request text: GET <target> with Host, Connection: close and the
   given "Name: value" lines (NULL-terminated, may be NULL). The target must
   start with "/". Returns its length, or -1 when it doesn't fit out. */
long http_request(char *out, long cap, const HttpBase *base, const char *target, const char *const *headers);

typedef struct HttpReply {
	int status;                 /* 200 */
	long headLen;               /* bytes up to and including the blank line */
	long contentLength;         /* -1 when absent */
	char contentType[48];
	char location[128];
} HttpReply;

/* Parses a reply's head from buf. 1: complete (out filled); 0: more bytes
   needed; -1: not an HTTP reply (or a head longer than 8 KB). */
int http_parse_head(const char *buf, long len, HttpReply *out);

#endif
