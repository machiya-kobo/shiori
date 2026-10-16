/*
 * net_talkip.c: net.h for Shiori Lite, on talkip (MacIP over LocalTalk, no MacTCP) through its
 * MacTCP-style shim. talkip's calls finish before they return, so a "begin" keeps the result for
 * NetPoll; a receive waits in NetPoll, which asks _TCPStatus (it runs the stack) and takes what
 * has come. Connecting blocks inside talkip, at most its 30 seconds, while it runs the stack.
 */
#include <Memory.h>
#include <string.h>

#include <talkip.h>

#include "net.h"

/* talkip's shim (tcpshim.c): the NCSA-style wrapper calls, which talkip.h doesn't declare. */
OSErr _TCPInit(void);
OSErr _TCPCreate(TCPiopb *pb, StreamPtr *stream, Ptr rcvBufPtr, long rcvBufLen, TCPNotifyUPP aNotifyProc,
	Ptr userDataPtr, TCPIOCompletionUPP ioCompletion, Boolean async);
OSErr _TCPActiveOpen(TCPiopb *pb, StreamPtr stream, ip_addr remoteIP, tcp_port remotePort, ip_addr *localIP,
	tcp_port *localPort, Ptr userData, TCPIOCompletionUPP ioCompletion, Boolean async);
OSErr _TCPSend(TCPiopb *pb, StreamPtr stream, wdsEntry *wdsPtr, Ptr userData, TCPIOCompletionUPP ioCompletion,
	Boolean async);
OSErr _TCPRcv(TCPiopb *pb, StreamPtr stream, Ptr rcvBufPtr, unsigned short *rcvBufLen, Ptr userData,
	TCPIOCompletionUPP ioCompletion, Boolean async);
OSErr _TCPAbort(TCPiopb *pb, StreamPtr stream, Ptr userData, TCPIOCompletionUPP ioCompletion, Boolean async);
OSErr _TCPStatus(TCPiopb *pb, StreamPtr stream, struct TCPStatusPB *status, Ptr userData,
	TCPIOCompletionUPP ioCompletion, Boolean async);
OSErr _TCPRelease(TCPiopb *pb, StreamPtr stream, Ptr userData, TCPIOCompletionUPP ioCompletion, Boolean async);

static Boolean gStarted = false;

OSErr NetInit(void)
{
	OSErr err;

	if (gStarted)
		return noErr;
	err = _TCPInit();
	if (err == noErr)
		gStarted = true;
	return err;
}

void NetIdle(void)
{
	talkip_idle();
}

Boolean NetHasAddress(void)
{
	return talkip_local_ip() != 0;
}

Boolean NetParseIP(const char *s, ip_addr *out)
{
	unsigned long addr = 0;
	int part, digits;
	long v;

	for (part = 0; part < 4; part++) {
		v = 0;
		digits = 0;
		while (*s >= '0' && *s <= '9') {
			v = v * 10 + (*s - '0');
			if (++digits > 3 || v > 255)
				return false;
			s++;
		}
		if (digits == 0)
			return false;
		addr = (addr << 8) | (unsigned long) v;
		if (part < 3) {
			if (*s != '.')
				return false;
			s++;
		}
	}
	if (*s != '\0')
		return false;
	*out = addr;
	return true;
}

static OSErr Finished(NetConn *c, OSErr err)
{
	c->result = err;
	c->busy = true;             /* NetPoll hands the result over */
	return noErr;
}

OSErr NetCreate(NetConn *c, long bufLen)
{
	OSErr err;

	memset(c, 0, sizeof(*c));
	if ((err = NetInit()) != noErr)
		return err;
	c->rcvBufLen = bufLen;
	c->rcvBuf = NewPtr(bufLen);
	if (c->rcvBuf == NULL)
		return memFullErr;
	err = _TCPCreate(&c->pb, &c->stream, c->rcvBuf, bufLen, NULL, NULL, NULL, false);
	if (err != noErr) {
		DisposePtr(c->rcvBuf);
		c->rcvBuf = NULL;
		c->stream = 0;
	}
	return err;
}

OSErr NetBeginOpen(NetConn *c, ip_addr host, tcp_port port, short timeoutSecs)
{
	(void) timeoutSecs;         /* talkip's own: 20 s for an address, then 30 s to connect */
	return Finished(c, _TCPActiveOpen(&c->pb, c->stream, host, port, NULL, NULL, NULL, NULL, false));
}

OSErr NetBeginSend(NetConn *c, const char *data, unsigned short len)
{
	c->wds[0].length = len;
	c->wds[0].ptr = (Ptr) data;
	c->wds[1].length = 0;
	c->wds[1].ptr = NULL;
	return Finished(c, _TCPSend(&c->pb, c->stream, c->wds, NULL, NULL, false));
}

OSErr NetBeginRecv(NetConn *c, char *buf, unsigned short len, short timeoutSecs)
{
	(void) timeoutSecs;         /* fetch.c keeps the deadline */
	c->rcvInto = buf;
	c->rcvWant = len;
	c->rcvGot = 0;
	c->receiving = true;
	c->busy = true;
	return noErr;
}

/* A waiting receive: inProgress until data has come or the connection has ended. */
static OSErr Receive(NetConn *c)
{
	struct TCPStatusPB st;
	TCPiopb pb;
	unsigned short n;
	OSErr err;

	memset(&st, 0, sizeof(st));
	err = _TCPStatus(&pb, c->stream, &st, NULL, NULL, false);
	if (err == connectionDoesntExist)
		return connectionTerminated;    /* closed, nothing left unread */
	if (err != noErr)
		return err;
	if (st.amtUnreadData > 0) {
		n = c->rcvWant;
		err = _TCPRcv(&pb, c->stream, (Ptr) c->rcvInto, &n, NULL, NULL, false);
		if (err == noErr)
			c->rcvGot = n;
		return err;
	}
	if (st.connectionState == ConnectionStateCloseWait || st.connectionState == ConnectionStateClosed)
		return connectionClosing;       /* the reply is all in */
	return inProgress;
}

OSErr NetPoll(NetConn *c)
{
	OSErr err;

	if (!c->busy)
		return noErr;
	if (c->receiving) {
		err = Receive(c);
		if (err == inProgress)
			return inProgress;
		c->receiving = false;
		c->busy = false;
		return err;
	}
	c->busy = false;
	return c->result;
}

Boolean NetReady(const NetConn *c)
{
	/* always worth asking: NetPoll runs the stack, so fetch.c's pass keeps it moving for its few ticks */
	return true;
}

unsigned short NetReceived(const NetConn *c)
{
	return c->rcvGot;
}

void NetAbort(NetConn *c)
{
	TCPiopb pb;

	if (c->stream == 0)
		return;
	(void) _TCPAbort(&pb, c->stream, NULL, NULL, false);
	c->receiving = false;
	c->busy = false;
}

void NetRelease(NetConn *c)
{
	TCPiopb pb;

	if (c->stream != 0) {
		NetAbort(c);
		(void) _TCPRelease(&pb, c->stream, NULL, NULL, false);
		c->stream = 0;
	}
	if (c->rcvBuf != NULL) {
		DisposePtr(c->rcvBuf);
		c->rcvBuf = NULL;
	}
}
