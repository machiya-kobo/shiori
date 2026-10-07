/* net.c: see net.h. */
#include <Devices.h>
#include <Memory.h>
#include <string.h>

#include "net.h"

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

static void Prepare(NetConn *c, short csCode)
{
	memset(&c->pb, 0, sizeof(c->pb));
	c->pb.ioCRefNum = gIPP;
	c->pb.csCode = csCode;
	c->pb.tcpStream = c->stream;
}

static OSErr Start(NetConn *c)
{
	OSErr err;

	c->pb.ioResult = inProgress;
	err = PBControlAsync((ParmBlkPtr) &c->pb);
	c->busy = err == noErr;
	return err;
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
	Prepare(c, TCPCreate);
	c->pb.csParam.create.rcvBuff = c->rcvBuf;
	c->pb.csParam.create.rcvBuffLen = (unsigned long) bufLen;
	err = PBControlSync((ParmBlkPtr) &c->pb);
	if (err != noErr) {
		DisposePtr(c->rcvBuf);
		c->rcvBuf = NULL;
		return err;
	}
	c->stream = c->pb.tcpStream;
	return noErr;
}

OSErr NetBeginOpen(NetConn *c, ip_addr host, tcp_port port, short timeoutSecs)
{
	Prepare(c, TCPActiveOpen);
	c->pb.csParam.open.ulpTimeoutValue = (byte) timeoutSecs;
	c->pb.csParam.open.ulpTimeoutAction = 1;          /* abort when it passes */
	c->pb.csParam.open.validityFlags = 0xC0;          /* both of the above are set */
	c->pb.csParam.open.commandTimeoutValue = (byte) timeoutSecs;
	c->pb.csParam.open.remoteHost = host;
	c->pb.csParam.open.remotePort = port;
	return Start(c);
}

OSErr NetBeginSend(NetConn *c, const char *data, unsigned short len)
{
	c->wds[0].length = len;
	c->wds[0].ptr = (Ptr) data;
	c->wds[1].length = 0;
	c->wds[1].ptr = NULL;
	Prepare(c, TCPSend);
	c->pb.csParam.send.ulpTimeoutValue = 30;
	c->pb.csParam.send.ulpTimeoutAction = 1;
	c->pb.csParam.send.validityFlags = 0xC0;
	c->pb.csParam.send.pushFlag = true;
	c->pb.csParam.send.wdsPtr = (Ptr) c->wds;
	return Start(c);
}

OSErr NetBeginRecv(NetConn *c, char *buf, unsigned short len, short timeoutSecs)
{
	Prepare(c, TCPRcv);
	c->pb.csParam.receive.commandTimeoutValue = (byte) timeoutSecs;
	c->pb.csParam.receive.rcvBuff = buf;
	c->pb.csParam.receive.rcvBuffLen = len;
	return Start(c);
}

OSErr NetPoll(NetConn *c)
{
	if (!c->busy)
		return noErr;
	if (c->pb.ioResult == inProgress)
		return inProgress;
	c->busy = false;
	return c->pb.ioResult;
}

Boolean NetReady(const NetConn *c)
{
	return !c->busy || c->pb.ioResult != inProgress;
}

unsigned short NetReceived(const NetConn *c)
{
	return c->pb.csParam.receive.rcvBuffLen;
}

void NetAbort(NetConn *c)
{
	TCPiopb abort;

	if (c->stream == NULL)
		return;
	memset(&abort, 0, sizeof(abort));
	abort.ioCRefNum = gIPP;
	abort.csCode = TCPAbort;
	abort.tcpStream = c->stream;
	(void) PBControlSync((ParmBlkPtr) &abort);       /* completes the operation in flight */
	while (c->busy && c->pb.ioResult == inProgress)
		;
	c->busy = false;
}

void NetRelease(NetConn *c)
{
	TCPiopb rel;

	if (c->stream != NULL) {
		NetAbort(c);
		memset(&rel, 0, sizeof(rel));
		rel.ioCRefNum = gIPP;
		rel.csCode = TCPRelease;
		rel.tcpStream = c->stream;
		(void) PBControlSync((ParmBlkPtr) &rel);
		c->stream = NULL;
	}
	if (c->rcvBuf != NULL) {
		DisposePtr(c->rcvBuf);
		c->rcvBuf = NULL;
	}
}
