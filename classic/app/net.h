/*
 * net.h: one TCP connection at a time over MacTCP, every call asynchronous
 * and polled, so the app keeps taking events (and ⌘-. cancels) while a
 * Mac Plus waits on the network.
 */
#ifndef SHIORI_NET_H
#define SHIORI_NET_H

#include "mactcp.h"

/* Called while a call is in progress: return true to cancel it. The app
   passes one that runs WaitNextEvent and watches for ⌘-. */
typedef Boolean (*NetYield)(void *ctx);

typedef struct NetConn {
	TCPiopb pb;
	StreamPtr stream;
	Ptr rcvBuf;
	long rcvBufLen;
	unsigned long deadline;     /* TickCount() past which the call is abandoned */
	NetYield yield;
	void *yieldCtx;
	Boolean cancelled;
} NetConn;

/* Opens the IP driver once. noErr, or MacTCP's error (not installed, no address). */
OSErr NetInit(void);

/* "192.168.1.5" -> its address; false for anything else (no DNS yet). */
Boolean NetParseIP(const char *text, ip_addr *out);

/* Connects; timeoutSecs bounds the whole connect. */
OSErr NetOpen(NetConn *c, ip_addr host, tcp_port port, short timeoutSecs, NetYield yield, void *ctx);
/* Sends all of [data, data+len). */
OSErr NetSend(NetConn *c, const char *data, unsigned short len);
/* Receives up to *len bytes into buf; *len is what came. connectionClosing
   (or connectionTerminated) when the other side has finished. */
OSErr NetRecv(NetConn *c, char *buf, unsigned short *len, short timeoutSecs);
/* Closes (gracefully when it can), and releases the stream. Always safe. */
void NetClose(NetConn *c);

#endif
