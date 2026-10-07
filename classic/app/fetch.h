/*
 * fetch.h: one HTTP/1.0 GET to the bridge at a time, as a state machine the
 * event loop drives (FetchPoll on every pass). It sends the one credential
 * the core's rule allows for that address, refuses redirects, caps the
 * reply, and gives up at each stage's deadline; ⌘-. calls FetchCancel.
 */
#ifndef SHIORI_FETCH_H
#define SHIORI_FETCH_H

#include <Memory.h>

#include "../core/config.h"
#include "../core/http.h"
#include "net.h"

enum {
	FETCH_IDLE,             /* nothing asked, or the answer was taken */
	FETCH_CONNECTING,
	FETCH_SENDING,
	FETCH_RECEIVING,
	FETCH_DONE,             /* a reply came: status, head, body */
	FETCH_FAILED            /* see err and FetchProblem */
};

/* Errors of our own, beside MacTCP's (all negative, outside its range). */
enum {
	fetchBadAddress = -30001,   /* the bridge's address isn't http://<IP address>:<port>/ */
	fetchTooLarge = -30002,     /* the reply passed the cap */
	fetchBadReply = -30003,     /* not an HTTP reply */
	fetchRedirected = -30004,   /* a 3xx: never followed */
	fetchTimedOut = -30005,     /* a stage's deadline passed */
	fetchCancelled = -30006
};

typedef struct Fetch {
	int state;
	OSErr err;
	long tag;               /* the caller's: which request this is (a generation) */
	NetConn conn;
	char req[1024];
	unsigned short reqLen;
	Handle body;            /* the whole reply as it came, head included */
	long have, cap;
	HttpReply head;         /* once DONE: status, content type… */
	unsigned long started, stageDeadline, connected, finished;
	long receives;          /* how many receives the reply took (for tuning) */
	Boolean locked;
} Fetch;

void FetchInit(Fetch *f);
/* Starts GET base+target (target relative: "search?…"). cap: the largest reply kept.
   Anything unsafe (an address that isn't the bridge's) fails at once. */
void FetchStart(Fetch *f, const ShioriConfig *config, const char *base, const char *target, long cap, long tag);
/* Advances the state machine; true while it's still under way. */
Boolean FetchPoll(Fetch *f);
void FetchCancel(Fetch *f);
/* The reply's body (after the head) and its length; the handle stays the fetch's. */
const char *FetchBody(Fetch *f, long *len);
/* Frees the reply and the stream; back to FETCH_IDLE. */
void FetchReset(Fetch *f);
/* What went wrong, in words that say what to do. who: "Hister" or "Kura". */
void FetchProblem(const Fetch *f, const char *who, char *out, long cap);

#endif
