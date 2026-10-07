/*
 * net.c: MacTCP, asynchronously. Each driver call is issued with
 * PBControlAsync and then polled: the yield callback runs between polls
 * (WaitNextEvent in the app), and a call past its deadline or cancelled is
 * aborted. One connection at a time.
 */
#include <Devices.h>
#include <Memory.h>
#include <OSUtils.h>
#include <Events.h>
#include <string.h>

#include "net.h"

#define RCV_BUF_LEN 8192L   /* MacTCP's receive buffer for the stream (4K at least) */

static short gIPP = 0;      /* the .IPP driver's refnum, once opened */

OSErr NetInit(void)
{
	ParamBlockRec pb;
	OSErr err;

	if (gIPP != 0)
		return noErr;
	memset(&pb, 0, sizeof(pb));
	pb.ioParam.ioNamePtr = (StringPtr) "\p.IPP";
	pb.ioParam.ioPermssn = fsCurPerm;
	err = PBOpenSync(&pb);
	if (err == noErr)
		gIPP = pb.ioParam.ioRefNum;
	return err;
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

/* Starts the call in c->pb and waits for it, yielding; aborts on timeout or cancel. */
static OSErr Wait(NetConn *c)
{
	OSErr err;

	c->pb.ioResult = inProgress;
	err = PBControlAsync((ParmBlkPtr) &c->pb);
	if (err != noErr)
		return err;
	while (c->pb.ioResult == inProgress) {
		if (c->yield != NULL && c->yield(c->yieldCtx))
			c->cancelled = true;
		if (c->cancelled || TickCount() > c->deadline) {
			TCPiopb abort;

			memset(&abort, 0, sizeof(abort));
			abort.ioCRefNum = gIPP;
			abort.csCode = TCPAbort;
			abort.tcpStream = c->stream;
			PBControlSync((ParmBlkPtr) &abort);   /* completes the pending call */
			while (c->pb.ioResult == inProgress)
				;
			return c->cancelled ? userCanceledErr : commandTimeout;
		}
	}
	return c->pb.ioResult;
}

static void Prepare(NetConn *c, short csCode, short timeoutSecs)
{
	memset(&c->pb, 0, sizeof(c->pb));
	c->pb.ioCRefNum = gIPP;
	c->pb.csCode = csCode;
	c->pb.tcpStream = c->stream;
	c->deadline = TickCount() + (unsigned long) timeoutSecs * 60;
}

OSErr NetOpen(NetConn *c, ip_addr host, tcp_port port, short timeoutSecs, NetYield yield, void *ctx)
{
	OSErr err;

	memset(c, 0, sizeof(*c));
	c->yield = yield;
	c->yieldCtx = ctx;
	if ((err = NetInit()) != noErr)
		return err;
	c->rcvBufLen = RCV_BUF_LEN;
	c->rcvBuf = NewPtr(c->rcvBufLen);
	if (c->rcvBuf == NULL)
		return memFullErr;

	Prepare(c, TCPCreate, 5);
	c->pb.csParam.create.rcvBuff = c->rcvBuf;
	c->pb.csParam.create.rcvBuffLen = c->rcvBufLen;
	err = PBControlSync((ParmBlkPtr) &c->pb);
	if (err != noErr) {
		DisposePtr(c->rcvBuf);
		c->rcvBuf = NULL;
		return err;
	}
	c->stream = c->pb.tcpStream;

	Prepare(c, TCPActiveOpen, timeoutSecs);
	c->pb.csParam.open.ulpTimeoutValue = (byte) timeoutSecs;
	c->pb.csParam.open.ulpTimeoutAction = 1;          /* abort when it passes */
	c->pb.csParam.open.validityFlags = 0xC0;          /* both of the above are set */
	c->pb.csParam.open.commandTimeoutValue = (byte) timeoutSecs;
	c->pb.csParam.open.remoteHost = host;
	c->pb.csParam.open.remotePort = port;
	return Wait(c);
}

OSErr NetSend(NetConn *c, const char *data, unsigned short len)
{
	wdsEntry wds[2];

	wds[0].length = len;
	wds[0].ptr = (Ptr) data;
	wds[1].length = 0;
	wds[1].ptr = NULL;
	Prepare(c, TCPSend, 20);
	c->pb.csParam.send.ulpTimeoutValue = 20;
	c->pb.csParam.send.ulpTimeoutAction = 1;
	c->pb.csParam.send.validityFlags = 0xC0;
	c->pb.csParam.send.pushFlag = true;
	c->pb.csParam.send.wdsPtr = (Ptr) wds;
	return Wait(c);
}

OSErr NetRecv(NetConn *c, char *buf, unsigned short *len, short timeoutSecs)
{
	OSErr err;

	Prepare(c, TCPRcv, timeoutSecs + 2);
	c->pb.csParam.receive.commandTimeoutValue = (byte) timeoutSecs;
	c->pb.csParam.receive.rcvBuff = buf;
	c->pb.csParam.receive.rcvBuffLen = *len;
	err = Wait(c);
	*len = (err == noErr) ? c->pb.csParam.receive.rcvBuffLen : 0;
	return err;
}

void NetClose(NetConn *c)
{
	if (c->stream != NULL) {
		Prepare(c, TCPClose, 3);
		c->pb.csParam.close.ulpTimeoutValue = 3;
		c->pb.csParam.close.ulpTimeoutAction = 1;
		c->pb.csParam.close.validityFlags = 0xC0;
		if (!c->cancelled)
			(void) Wait(c);
		Prepare(c, TCPAbort, 2);
		(void) PBControlSync((ParmBlkPtr) &c->pb);
		Prepare(c, TCPRelease, 2);
		(void) PBControlSync((ParmBlkPtr) &c->pb);
		c->stream = NULL;
	}
	if (c->rcvBuf != NULL) {
		DisposePtr(c->rcvBuf);
		c->rcvBuf = NULL;
	}
}
