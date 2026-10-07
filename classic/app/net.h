/*
 * net.h: MacTCP's TCP stream, driven without blocking. Each call starts the
 * driver's operation asynchronously and returns; net_poll says when it has
 * finished. The app's fetch (fetch.c) runs the state machine from its event
 * loop, so the window keeps taking events while a Mac Plus waits.
 */
#ifndef SHIORI_NET_H
#define SHIORI_NET_H

#include "mactcp.h"

typedef struct NetConn {
	TCPiopb pb;             /* the operation in flight (one at a time) */
	StreamPtr stream;
	Ptr rcvBuf;             /* MacTCP's own receive buffer for the stream */
	long rcvBufLen;
	wdsEntry wds[2];        /* the send's write data structure */
	Boolean busy;           /* an operation was started and hasn't finished */
} NetConn;

/* Opens the IP driver once. noErr, or MacTCP's error (not installed, no address). */
OSErr NetInit(void);

/* "192.168.1.5" -> its address; false for anything else (no DNS: the bridge is an address). */
Boolean NetParseIP(const char *text, ip_addr *out);

/* Creates the stream (synchronous, quick) with a receive buffer of bufLen bytes. */
OSErr NetCreate(NetConn *c, long bufLen);
/* Starts connecting; the driver gives up after timeoutSecs. */
OSErr NetBeginOpen(NetConn *c, ip_addr host, tcp_port port, short timeoutSecs);
/* Starts sending [data, data+len); data must stay put until it finishes. */
OSErr NetBeginSend(NetConn *c, const char *data, unsigned short len);
/* Starts receiving up to len bytes into buf (which must stay put, locked). */
OSErr NetBeginRecv(NetConn *c, char *buf, unsigned short len, short timeoutSecs);
/* inProgress while the operation runs; then its result (noErr, connectionClosing…). */
OSErr NetPoll(NetConn *c);
/* Whether the operation has finished (without taking its result: NetPoll does). */
Boolean NetReady(const NetConn *c);
/* Bytes the finished receive delivered. */
unsigned short NetReceived(const NetConn *c);
/* Ends the connection at once (completes any operation in flight). */
void NetAbort(NetConn *c);
/* Aborts if needed and releases the stream and its buffer. Always safe. */
void NetRelease(NetConn *c);

#endif
