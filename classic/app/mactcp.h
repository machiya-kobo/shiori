/*
 * mactcp.h: the parts of MacTCP's driver interface Shiori uses, written
 * from the MacTCP Programmer's Guide (Apple, 1989) so that no Apple header
 * is copied into this repository. Only TCP (create, open, send, receive,
 * close, abort, release) and the IP driver's address call.
 *
 * Layouts follow the 68000's (two-byte) alignment, as the driver expects.
 * classic/tests/check-mactcp-layout.sh compares every offset with Apple's
 * header where one is at hand.
 */
#ifndef SHIORI_MACTCP_H
#define SHIORI_MACTCP_H

#include <Types.h>
#include <Files.h>

typedef unsigned long ip_addr;
typedef unsigned short tcp_port;
typedef unsigned char byte;
typedef Ptr StreamPtr;

/* csCodes */
enum {
	ipctlGetAddr = 15,
	TCPCreate = 30,
	TCPPassiveOpen = 31,
	TCPActiveOpen = 32,
	TCPSend = 34,
	TCPNoCopyRcv = 35,
	TCPRcvBfrReturn = 36,
	TCPRcv = 37,
	TCPClose = 38,
	TCPAbort = 39,
	TCPStatus = 40,
	TCPRelease = 42
};

/* results */
enum {
	inProgress = 1,
	ipBadLapErr = -23000,
	ipBadCnfgErr = -23001,
	ipNoCnfgErr = -23002,
	ipLoadErr = -23003,
	ipBadAddr = -23004,
	connectionClosing = -23005,
	invalidLength = -23006,
	connectionExists = -23007,
	connectionDoesntExist = -23008,
	insufficientResources = -23009,
	invalidStreamPtr = -23010,
	streamAlreadyOpen = -23011,
	connectionTerminated = -23012,
	invalidBufPtr = -23013,
	invalidRDS = -23014,
	invalidWDS = -23014,
	openFailed = -23015,
	commandTimeout = -23016,
	duplicateSocket = -23017
};

/* a write data structure: (length, pointer) pairs ended by a zero length */
typedef struct wdsEntry {
	unsigned short length;
	Ptr ptr;
} wdsEntry;

struct ICMPReport;
typedef pascal void (*TCPNotifyProcPtr)(StreamPtr stream, unsigned short eventCode, Ptr userDataPtr,
	unsigned short terminReason, struct ICMPReport *icmpMsg);

typedef struct TCPCreatePB {
	Ptr rcvBuff;
	unsigned long rcvBuffLen;
	TCPNotifyProcPtr notifyProc;
	Ptr userDataPtr;
} TCPCreatePB;

typedef struct TCPOpenPB {
	byte ulpTimeoutValue;
	byte ulpTimeoutAction;
	byte validityFlags;
	byte commandTimeoutValue;
	ip_addr remoteHost;
	tcp_port remotePort;
	ip_addr localHost;
	tcp_port localPort;
	byte tosFlags;
	byte precedence;
	Boolean dontFrag;
	byte timeToLive;
	byte security;
	byte optionCnt;
	byte options[40];
	Ptr userDataPtr;
} TCPOpenPB;

typedef struct TCPSendPB {
	byte ulpTimeoutValue;
	byte ulpTimeoutAction;
	byte validityFlags;
	Boolean pushFlag;
	Boolean urgentFlag;
	byte filler;
	Ptr wdsPtr;
	unsigned long sendFree;
	unsigned short sendLength;
	Ptr userDataPtr;
} TCPSendPB;

typedef struct TCPReceivePB {
	byte commandTimeoutValue;
	Boolean markFlag;
	Boolean urgentFlag;
	byte filler;
	Ptr rcvBuff;
	unsigned short rcvBuffLen;
	Ptr rdsPtr;
	unsigned short rdsLength;
	unsigned short secondTimeStamp;
	Ptr userDataPtr;
} TCPReceivePB;

typedef struct TCPClosePB {
	byte ulpTimeoutValue;
	byte ulpTimeoutAction;
	byte validityFlags;
	byte filler;
	Ptr userDataPtr;
} TCPClosePB;

typedef struct TCPAbortPB {
	Ptr userDataPtr;
} TCPAbortPB;

typedef struct TCPiopb {
	char fill12[12];                    /* qLink, qType, ioTrap, ioCmdAddr */
	ProcPtr ioCompletion;
	volatile short ioResult;
	Ptr ioNamePtr;
	short ioVRefNum;
	short ioCRefNum;
	short csCode;
	StreamPtr tcpStream;
	union {
		TCPCreatePB create;
		TCPOpenPB open;
		TCPSendPB send;
		TCPReceivePB receive;
		TCPClosePB close;
		TCPAbortPB abort;
	} csParam;
} TCPiopb;

/* the IP driver's own address (ipctlGetAddr) */
typedef struct GetAddrParamBlock {
	char fill12[12];
	ProcPtr ioCompletion;
	volatile short ioResult;
	Ptr ioNamePtr;
	short ioVRefNum;
	short ioCRefNum;
	short csCode;
	ip_addr ourAddress;
	long ourNetMask;
} GetAddrParamBlock;

#endif
