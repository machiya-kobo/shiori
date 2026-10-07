/* fetch.c: see fetch.h. */
#include <Events.h>
#include <OSUtils.h>
#include <stdio.h>
#include <string.h>

#include "fetch.h"

#define RCV_BUF_LEN 16384L      /* MacTCP's buffer for the stream: room for a window's worth */
#define CHUNK 8192L             /* one receive's most */
#define CONNECT_SECS 15
#define SEND_SECS 20
#define IDLE_SECS 20            /* the longest gap between pieces of the reply */
#define DRAIN_TICKS 4           /* a pass keeps receiving while data comes, this long at most */

static void Fail(Fetch *f, OSErr err)
{
	if (f->locked) {
		HUnlock(f->body);
		f->locked = false;
	}
	NetRelease(&f->conn);
	f->err = err;
	f->state = FETCH_FAILED;
	f->finished = TickCount();
}

void FetchInit(Fetch *f)
{
	memset(f, 0, sizeof(*f));
}

void FetchReset(Fetch *f)
{
	if (f->state == FETCH_CONNECTING || f->state == FETCH_SENDING || f->state == FETCH_RECEIVING)
		NetAbort(&f->conn);
	if (f->locked)
		HUnlock(f->body);
	NetRelease(&f->conn);
	if (f->body != NULL)
		DisposeHandle(f->body);
	FetchInit(f);
}

void FetchStart(Fetch *f, const ShioriConfig *config, const char *base, const char *target, long cap, long tag)
{
	HttpBase b;
	ip_addr ip;
	char url[512], credential[96];
	const char *headers[4];
	int n = 0;
	long len;
	OSErr err;

	FetchReset(f);
	f->tag = tag;
	f->cap = cap;
	f->started = TickCount();
	/* only the configured bridge, by address (no DNS), and only plain http */
	if (!http_base(base, &b) || !NetParseIP(b.host, &ip) || strlen(base) + strlen(target) >= sizeof(url)) {
		Fail(f, fetchBadAddress);
		return;
	}
	strcpy(url, base);
	strcat(url, target);
	if (!shiori_is_configured_origin(config, url)) {
		Fail(f, fetchBadAddress);
		return;
	}
	shiori_credential_header(config, url, credential, (long) sizeof(credential));
	headers[n++] = "Accept: application/json";
	headers[n++] = "Origin: hister://";
	if (credential[0])
		headers[n++] = credential;
	headers[n] = NULL;
	{
		char path[600];
		strcpy(path, b.path);
		strcat(path, target);
		len = http_request(f->req, (long) sizeof(f->req), &b, path, headers);
	}
	if (len < 0) {
		Fail(f, fetchBadAddress);
		return;
	}
	f->reqLen = (unsigned short) len;
	f->body = NewHandle(CHUNK);
	if (f->body == NULL) {
		Fail(f, memFullErr);
		return;
	}
	if ((err = NetCreate(&f->conn, RCV_BUF_LEN)) != noErr || (err = NetBeginOpen(&f->conn, ip, b.port, CONNECT_SECS)) != noErr) {
		Fail(f, err);
		return;
	}
	f->state = FETCH_CONNECTING;
	f->stageDeadline = TickCount() + (CONNECT_SECS + 2) * 60UL;
}

static Boolean StartReceive(Fetch *f)
{
	OSErr err;

	if (f->have + CHUNK > GetHandleSize(f->body)) {
		if (f->have >= f->cap + 1) {
			Fail(f, fetchTooLarge);
			return false;
		}
		SetHandleSize(f->body, f->have + CHUNK);
		if (MemError() != noErr) {
			Fail(f, memFullErr);
			return false;
		}
	}
	HLock(f->body);
	f->locked = true;
	err = NetBeginRecv(&f->conn, *f->body + f->have, (unsigned short) CHUNK, IDLE_SECS);
	if (err != noErr) {
		Fail(f, err);
		return false;
	}
	f->stageDeadline = TickCount() + (IDLE_SECS + 2) * 60UL;
	return true;
}

static void Finish(Fetch *f)
{
	int got;

	if (f->locked) {
		HUnlock(f->body);
		f->locked = false;
	}
	NetRelease(&f->conn);
	f->finished = TickCount();
	SetHandleSize(f->body, f->have > 0 ? f->have : 1);
	HLock(f->body);
	got = http_parse_head(*f->body, f->have, &f->head);
	HUnlock(f->body);
	if (got != 1) {
		f->err = fetchBadReply;
		f->state = FETCH_FAILED;
		return;
	}
	if (f->head.status >= 300 && f->head.status < 400) {
		f->err = fetchRedirected;
		f->state = FETCH_FAILED;
		return;
	}
	if (f->head.contentLength >= 0 && f->have - f->head.headLen < f->head.contentLength) {
		f->err = fetchBadReply;           /* cut short */
		f->state = FETCH_FAILED;
		return;
	}
	f->state = FETCH_DONE;
}

static Boolean Step(Fetch *f);

/* One pass from the event loop: several steps while the network keeps
   answering at once (a pass per receive left the Mac idle between segments). */
Boolean FetchPoll(Fetch *f)
{
	unsigned long until = TickCount() + DRAIN_TICKS;
	Boolean more;

	do {
		more = Step(f);
	} while (more && NetReady(&f->conn) && TickCount() < until);
	return more;
}

static Boolean Step(Fetch *f)
{
	OSErr err;

	if (f->state != FETCH_CONNECTING && f->state != FETCH_SENDING && f->state != FETCH_RECEIVING)
		return false;
	err = NetPoll(&f->conn);
	if (err == inProgress) {
		if (TickCount() > f->stageDeadline)
			Fail(f, fetchTimedOut);
		return f->state != FETCH_FAILED;
	}
	switch (f->state) {
	case FETCH_CONNECTING:
		if (err != noErr) {
			Fail(f, err);
			return false;
		}
		f->connected = TickCount();
		/* the request lives in f, which doesn't move while the send runs */
		if ((err = NetBeginSend(&f->conn, f->req, f->reqLen)) != noErr) {
			Fail(f, err);
			return false;
		}
		f->state = FETCH_SENDING;
		f->stageDeadline = TickCount() + (SEND_SECS + 2) * 60UL;
		return true;
	case FETCH_SENDING:
		if (err != noErr) {
			Fail(f, err);
			return false;
		}
		f->state = FETCH_RECEIVING;
		return StartReceive(f);
	case FETCH_RECEIVING:
		if (f->locked) {
			HUnlock(f->body);
			f->locked = false;
		}
		if (err == noErr) {
			f->have += NetReceived(&f->conn);
			f->receives++;
			if (f->have > f->cap) {
				Fail(f, fetchTooLarge);
				return false;
			}
			return StartReceive(f);
		}
		if (err == connectionClosing || err == connectionTerminated) {
			Finish(f);
			return false;
		}
		Fail(f, err);
		return false;
	}
	return false;
}

void FetchCancel(Fetch *f)
{
	if (f->state == FETCH_CONNECTING || f->state == FETCH_SENDING || f->state == FETCH_RECEIVING) {
		NetAbort(&f->conn);
		Fail(f, fetchCancelled);
	}
}

const char *FetchBody(Fetch *f, long *len)
{
	if (f->state != FETCH_DONE || f->body == NULL) {
		*len = 0;
		return "";
	}
	HLock(f->body);
	f->locked = false;          /* the caller reads it now; FetchReset frees it */
	*len = f->have - f->head.headLen;
	return *f->body + f->head.headLen;
}

void FetchProblem(const Fetch *f, const char *who, char *out, long cap)
{
	char msg[160];
	int status = f->state == FETCH_DONE ? f->head.status : 0;

	if (f->state == FETCH_DONE) {
		if (status == 401)
			sprintf(msg, "%s wants this Mac's room token: Preferences\311", who);
		else if (status == 403)
			sprintf(msg, "%s refused this Mac (403): check the bridge and the room token.", who);
		else if (status == 413)
			sprintf(msg, "Too large for this Mac.");
		else if (status == 502 || status == 504)
			sprintf(msg, "The bridge can't reach %s (%d).", who, status);
		else if (status == 503)
			sprintf(msg, "%s is busy or sign-in is down (503): try again.", who);
		else
			sprintf(msg, "%s answered %d.", who, status);
	} else {
		switch (f->err) {
		case fetchBadAddress: sprintf(msg, "The bridge's address must be http://<IP address>:<port>/ (Preferences\311)."); break;
		case fetchTooLarge: sprintf(msg, "%s's answer was too large for this Mac.", who); break;
		case fetchBadReply: sprintf(msg, "%s's answer was cut short or unreadable.", who); break;
		case fetchRedirected: sprintf(msg, "%s redirected: Shiori never follows a redirect.", who); break;
		case fetchTimedOut: sprintf(msg, "%s didn't answer in time.", who); break;
		case fetchCancelled: sprintf(msg, "Stopped."); break;
		case memFullErr: sprintf(msg, "Not enough memory for %s's answer.", who); break;
		case openFailed: case connectionTerminated: case commandTimeout:
			sprintf(msg, "Can't reach the bridge (%d): is it on, and this Mac on the network?", f->err); break;
		default:
			if (f->err == ipBadAddr)
				sprintf(msg, "MacTCP has no address (%d): is this Mac on the network?", f->err);
			else if (f->err <= ipBadLapErr && f->err >= ipLoadErr)
				sprintf(msg, "MacTCP isn't set up (%d): check the MacTCP control panel.", f->err);
			else
				sprintf(msg, "Can't reach %s (%d).", who, f->err);
		}
	}
	strncpy(out, msg, (size_t) cap - 1);
	out[cap - 1] = '\0';
}
