/* http.c: see http.h. */
#include <string.h>

#include "http.h"

#define MAX_HEAD 8192L

static int lower(int c)
{
	return (c >= 'A' && c <= 'Z') ? c + 32 : c;
}

int http_base(const char *url, HttpBase *out)
{
	const char *p, *hostEnd, *pathStart;
	long port = 80, n;

	memset(out, 0, sizeof(*out));
	if (strncmp(url, "http://", 7) != 0)
		return 0;
	p = url + 7;
	hostEnd = p;
	while (*hostEnd && *hostEnd != ':' && *hostEnd != '/') {
		char c = *hostEnd;
		if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '-'))
			return 0;
		hostEnd++;
	}
	n = hostEnd - p;
	if (n == 0 || n >= (long) sizeof(out->host))
		return 0;
	memcpy(out->host, p, (size_t) n);
	pathStart = hostEnd;
	if (*hostEnd == ':') {
		const char *d = hostEnd + 1;
		port = 0;
		if (*d < '0' || *d > '9')
			return 0;
		while (*d >= '0' && *d <= '9') {
			port = port * 10 + (*d - '0');
			if (port > 65535)
				return 0;
			d++;
		}
		if (port == 0 || (*d && *d != '/'))
			return 0;
		pathStart = d;
	}
	out->port = (unsigned short) port;
	if (*pathStart == '\0') {
		strcpy(out->path, "/");
		return 1;
	}
	n = (long) strlen(pathStart);
	if (n >= (long) sizeof(out->path) - 1 || strpbrk(pathStart, "?#@ ") != NULL)
		return 0;
	strcpy(out->path, pathStart);
	if (out->path[n - 1] != '/')
		strcat(out->path, "/");
	return 1;
}

static int add(char *out, long cap, long *n, const char *s)
{
	long len = (long) strlen(s);
	if (*n + len >= cap)
		return 0;
	memcpy(out + *n, s, (size_t) len);
	*n += len;
	out[*n] = '\0';
	return 1;
}

long http_request(char *out, long cap, const HttpBase *base, const char *target, const char *const *headers)
{
	long n = 0;
	char port[8];
	int i;
	unsigned short v;

	if (cap <= 0 || target[0] != '/')
		return -1;
	out[0] = '\0';
	i = 7;
	port[i] = '\0';
	v = base->port;
	do {
		port[--i] = (char) ('0' + v % 10);
		v /= 10;
	} while (v && i > 1);
	port[--i] = ':';
	if (!add(out, cap, &n, "GET ") || !add(out, cap, &n, target) || !add(out, cap, &n, " HTTP/1.0\r\nHost: ")
			|| !add(out, cap, &n, base->host) || (base->port != 80 && !add(out, cap, &n, port + i))
			|| !add(out, cap, &n, "\r\nConnection: close\r\n"))
		return -1;
	for (i = 0; headers != NULL && headers[i] != NULL; i++) {
		if (strpbrk(headers[i], "\r\n") != NULL)
			return -1;
		if (!add(out, cap, &n, headers[i]) || !add(out, cap, &n, "\r\n"))
			return -1;
	}
	if (!add(out, cap, &n, "\r\n"))
		return -1;
	return n;
}

/* Whether the header line [p, end) is "name:"; then *value points after the colon and spaces. */
static int header_is(const char *p, const char *end, const char *name, const char **value)
{
	long n = (long) strlen(name);
	long i;

	if (end - p <= n || p[n] != ':')
		return 0;
	for (i = 0; i < n; i++)
		if (lower((unsigned char) p[i]) != name[i])
			return 0;
	p += n + 1;
	while (p < end && (*p == ' ' || *p == '\t'))
		p++;
	*value = p;
	return 1;
}

static void copy_value(char *out, long cap, const char *p, const char *end)
{
	long n = end - p;
	while (n > 0 && (p[n - 1] == ' ' || p[n - 1] == '\t'))
		n--;
	if (n >= cap)
		n = cap - 1;
	memcpy(out, p, (size_t) n);
	out[n] = '\0';
}

int http_parse_head(const char *buf, long len, HttpReply *out)
{
	const char *p, *end, *line, *eol, *v;
	long i;

	memset(out, 0, sizeof(*out));
	out->contentLength = -1;
	/* find the blank line */
	end = NULL;
	for (i = 0; i + 3 < len && i < MAX_HEAD; i++) {
		if (buf[i] == '\r' && buf[i + 1] == '\n' && buf[i + 2] == '\r' && buf[i + 3] == '\n') {
			end = buf + i + 2;
			out->headLen = i + 4;
			break;
		}
	}
	if (end == NULL)
		return (len >= MAX_HEAD) ? -1 : (len >= 5 && memcmp(buf, "HTTP/", 5) != 0 ? -1 : 0);
	if (out->headLen < 12 || memcmp(buf, "HTTP/1.", 7) != 0 || buf[8] != ' ')
		return -1;
	for (i = 9; i < 12; i++)
		if (buf[i] < '0' || buf[i] > '9')
			return -1;
	out->status = (buf[9] - '0') * 100 + (buf[10] - '0') * 10 + (buf[11] - '0');
	p = buf;
	while (p < end && *p != '\n')
		p++;
	line = p + 1;
	while (line < end) {
		eol = line;
		while (eol < end && *eol != '\r')
			eol++;
		if (header_is(line, eol, "content-length", &v)) {
			long cl = 0;
			if (v >= eol)
				return -1;
			while (v < eol && *v >= '0' && *v <= '9') {
				if (cl > 99999999L)
					return -1;
				cl = cl * 10 + (*v++ - '0');
			}
			out->contentLength = cl;
		} else if (header_is(line, eol, "content-type", &v)) {
			copy_value(out->contentType, (long) sizeof(out->contentType), v, eol);
		} else if (header_is(line, eol, "location", &v)) {
			copy_value(out->location, (long) sizeof(out->location), v, eol);
		}
		line = eol + 2;
	}
	return 1;
}
