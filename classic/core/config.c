/* config.c: see config.h. */
#include <string.h>

#include "config.h"
#include "query.h"

static int lower(int c)
{
	return (c >= 'A' && c <= 'Z') ? c + 32 : c;
}

void shiori_origin_of(const char *raw, char *out, long cap)
{
	char url[256], auth[160], *colon, *p;
	const char *scheme, *start, *end;
	long n;
	int https;

	out[0] = '\0';
	if (!shiori_trim(raw, url, (long) sizeof(url))) {
		/* longer than the buffer (a request with a long query): only the scheme and the
		   host decide, and they come first */
		while (*raw == ' ' || *raw == '\t' || *raw == '\r' || *raw == '\n')
			raw++;
		if (strlen(raw) < sizeof(url))
			return;
		memcpy(url, raw, sizeof(url) - 1);
		url[sizeof(url) - 1] = '\0';
	}
	for (n = 0; n < 8 && url[n]; n++)
		auth[n] = (char) lower((unsigned char) url[n]);
	auth[n] = '\0';
	if (strncmp(auth, "https://", 8) == 0)
		https = 1;
	else if (strncmp(auth, "http://", 7) == 0)
		https = 0;
	else
		return;
	scheme = https ? "https" : "http";
	start = url + (https ? 8 : 7);
	end = start + strcspn(start, "/?#");
	n = end - start;
	if (n == 0 || n >= (long) sizeof(auth))
		return;
	for (p = auth; start < end; start++)
		*p++ = (char) lower((unsigned char) *start);
	*p = '\0';
	if (strchr(auth, '@') != NULL || strpbrk(auth, " \\\t") != NULL)
		return;
	colon = strrchr(auth, ':');
	if (colon != NULL && (auth[0] != '[' || strchr(auth, ']') < colon)) {
		char *d;
		if (colon == auth)
			return;
		for (d = colon + 1; *d; d++)
			if (*d < '0' || *d > '9')
				return;
		if (colon[1] == '\0' || (https && strcmp(colon + 1, "443") == 0) || (!https && strcmp(colon + 1, "80") == 0))
			*colon = '\0';
	}
	if ((long) (strlen(scheme) + 3 + strlen(auth)) >= cap)
		return;
	strcpy(out, scheme);
	strcat(out, "://");
	strcat(out, auth);
}

void shiori_checked_room_token(const char *raw, char *out, long cap)
{
	char t[64];
	const char *c;

	out[0] = '\0';
	if (!shiori_trim(raw, t, (long) sizeof(t)) || strlen(t) != 47 || strncmp(t, "mht_", 4) != 0 || cap < 48)
		return;
	for (c = t + 4; *c; c++)
		if (!((*c >= 'A' && *c <= 'Z') || (*c >= 'a' && *c <= 'z') || (*c >= '0' && *c <= '9') || *c == '_' || *c == '-'))
			return;
	strcpy(out, t);
}

int shiori_notes_from_hister(const ShioriConfig *c)
{
	return strcmp(shiori_notes_source(c->notesSource, c->kura[0] != '\0'), "hister") == 0;
}

int shiori_is_configured_origin(const ShioriConfig *c, const char *url)
{
	char want[160], h[160], k[160];

	shiori_origin_of(url, want, (long) sizeof(want));
	if (want[0] == '\0')
		return 0;
	shiori_origin_of(c->hister, h, (long) sizeof(h));
	shiori_origin_of(c->kura, k, (long) sizeof(k));
	return (h[0] && strcmp(want, h) == 0) || (k[0] && strcmp(want, k) == 0);
}

void shiori_checked_hister_token(const char *raw, char *out, long cap)
{
	char t[160];
	const char *c;
	size_t n;

	out[0] = '\0';
	if (!shiori_trim(raw, t, (long) sizeof(t)))
		return;
	n = strlen(t);
	if (n < 8 || n > 127 || (long) n >= cap)
		return;
	for (c = t; *c; c++)
		if ((unsigned char) *c < 0x21 || (unsigned char) *c > 0x7E)
			return;
	strcpy(out, t);
}

void shiori_credential_header(const ShioriConfig *c, const char *url, char *out, long cap)
{
	char want[160], h[160], k[160], token[128];
	const char *name;

	out[0] = '\0';
	shiori_origin_of(url, want, (long) sizeof(want));
	if (want[0] == '\0')
		return;
	shiori_origin_of(c->hister, h, (long) sizeof(h));
	shiori_origin_of(c->kura, k, (long) sizeof(k));
	if (h[0] && strcmp(want, h) == 0) {
		if (c->direct) {
			shiori_checked_hister_token(c->histerToken, token, (long) sizeof(token));
			name = "X-Access-Token: ";
		} else {
			shiori_checked_room_token(c->roomToken, token, (long) sizeof(token));
			name = "Authorization: Bearer ";
		}
	} else if (k[0] && strcmp(want, k) == 0) {
		shiori_checked_room_token(c->roomToken, token, (long) sizeof(token));
		name = "Authorization: Bearer ";
	} else {
		return;
	}
	if (token[0] == '\0' || cap < (long) (strlen(name) + strlen(token) + 1))
		return;
	strcpy(out, name);
	strcat(out, token);
}
