/*
 * Shiori for Classic Macintosh: phase 0's probe. One window that, on
 * File → Run Probe (⌘R), asks the bridge for a search from Hister and one
 * from Kura, and reports what it took on this Mac: connect, transfer,
 * parse, bytes and rows. The real search window replaces it in phase 3.
 */
#include <Quickdraw.h>
#include <Fonts.h>
#include <Windows.h>
#include <Menus.h>
#include <TextEdit.h>
#include <Dialogs.h>
#include <Events.h>
#include <OSUtils.h>
#include <ToolUtils.h>
#include <Memory.h>
#include <Devices.h>
#include <Traps.h>
#include <string.h>
#include <stdio.h>

#include "../core/http.h"
#include "../core/json.h"
#include "net.h"

/* The bridge and the Mac's room token for the probe. Builds take them from
   classic/local.env (gitignored); these neutral defaults reach nothing. */
#ifndef SHIORI_PROBE_HISTER
#define SHIORI_PROBE_HISTER "http://192.0.2.1:8070/"
#endif
#ifndef SHIORI_PROBE_KURA
#define SHIORI_PROBE_KURA "http://192.0.2.1:8071/"
#endif
#ifndef SHIORI_PROBE_TOKEN
#define SHIORI_PROBE_TOKEN ""
#endif
#ifndef SHIORI_VERSION
#define SHIORI_VERSION "0.0.0-dev"
#endif

enum { kAppleMenu = 128, kFileMenu = 129, kEditMenu = 130 };
enum { kAboutItem = 1 };
enum { kRunItem = 1, kQuitItem = 3 };
enum { kAboutAlert = 128 };

#define MAX_LINES 24
#define MAX_REPLY (512L * 1024L)

static WindowPtr gWindow;
static char gLines[MAX_LINES][96];
static int gLineCount;
static Boolean gQuit;
static Boolean gHasWNE;

static void Redraw(void);

static void AddLine(const char *text)
{
	if (gLineCount == MAX_LINES) {
		memmove(gLines[0], gLines[1], sizeof(gLines[0]) * (MAX_LINES - 1));
		gLineCount--;
	}
	strncpy(gLines[gLineCount], text, sizeof(gLines[0]) - 1);
	gLines[gLineCount][sizeof(gLines[0]) - 1] = '\0';
	gLineCount++;
	Redraw();
}

static void Redraw(void)
{
	GrafPtr old;
	int i;
	Rect r;

	GetPort(&old);
	SetPort(gWindow);
	r = gWindow->portRect;
	EraseRect(&r);
	TextFont(kFontIDGeneva);
	TextSize(9);
	for (i = 0; i < gLineCount; i++) {
		unsigned char pstr[96];
		size_t n = strlen(gLines[i]);
		pstr[0] = (unsigned char) n;
		memcpy(pstr + 1, gLines[i], n);
		MoveTo(8, 16 + i * 12);
		DrawString(pstr);
	}
	SetPort(old);
}

static void DoUpdate(WindowPtr w)
{
	BeginUpdate(w);
	if (w == gWindow)
		Redraw();
	EndUpdate(w);
}

static Boolean GetEvent(EventRecord *e, long sleep)
{
	if (gHasWNE)
		return WaitNextEvent(everyEvent, e, sleep, NULL);
	SystemTask();
	return GetNextEvent(everyEvent, e);
}

/* While the network waits: updates are drawn, ⌘-. cancels. */
static Boolean Yield(void *ctx)
{
	EventRecord e;
	(void) ctx;

	if (GetEvent(&e, 1)) {
		if (e.what == updateEvt)
			DoUpdate((WindowPtr) e.message);
		else if (e.what == keyDown && (e.modifiers & cmdKey) && (e.message & charCodeMask) == '.')
			return true;
	}
	return false;
}

static long Seconds10(unsigned long ticks)   /* tenths of a second */
{
	return (long) ((ticks * 10 + 30) / 60);
}

/* GET base+target into a new handle; returns the HTTP status (or a negative error). */
static int Fetch(const char *baseURL, const char *target, Handle *body, long *bodyOffset,
	unsigned long *connectTicks, unsigned long *transferTicks)
{
	HttpBase base;
	HttpReply head;
	NetConn c;
	ip_addr ip;
	char req[1024];
	char auth[128];
	const char *headers[4];
	long n, have = 0;
	unsigned long t0, t1;
	OSErr err;
	int got = 0;

	*body = NULL;
	if (!http_base(baseURL, &base) || !NetParseIP(base.host, &ip))
		return -1;
	headers[0] = "Accept: application/json";
	headers[1] = "Origin: hister://";
	headers[2] = NULL;
	if (SHIORI_PROBE_TOKEN[0]) {
		sprintf(auth, "Authorization: Bearer %s", SHIORI_PROBE_TOKEN);
		headers[2] = auth;
		headers[3] = NULL;
	}
	n = http_request(req, sizeof(req), &base, target, headers);
	if (n < 0)
		return -2;

	t0 = TickCount();
	err = NetOpen(&c, ip, base.port, 15, Yield, NULL);
	t1 = TickCount();
	*connectTicks = t1 - t0;
	if (err != noErr) {
		NetClose(&c);
		return err;
	}
	err = NetSend(&c, req, (unsigned short) n);
	*body = NewHandle(4096);
	while (err == noErr && *body != NULL) {
		unsigned short len = 4096;
		if (GetHandleSize(*body) < have + 4096) {
			SetHandleSize(*body, have + 16384);
			if (MemError() != noErr) {
				err = memFullErr;
				break;
			}
		}
		HLock(*body);
		err = NetRecv(&c, **body + have, &len, 20);
		HUnlock(*body);
		have += len;
		if (have > MAX_REPLY) {
			err = memFullErr;
			break;
		}
	}
	*transferTicks = TickCount() - t1;
	NetClose(&c);
	if (err != connectionClosing && err != connectionTerminated && err != noErr)
		return err;
	if (*body == NULL)
		return memFullErr;
	SetHandleSize(*body, have);
	HLock(*body);
	got = http_parse_head(**body, have, &head);
	HUnlock(*body);
	if (got != 1)
		return -3;
	*bodyOffset = head.headLen;
	return head.status;
}

/* Walks a reply for its rows (Hister's "documents", Kura's "results"), decoding each title. */
static int CountRows(const char *buf, long len, const char *listKey)
{
	JsonReader r;
	int t, rows = 0;
	char title[256];

	json_init(&r, buf, len);
	if (json_next(&r) != JSON_OBJECT)
		return -1;
	while ((t = json_next(&r)) == JSON_KEY) {
		if (!json_is(&r, listKey)) {
			if (json_skip(&r, JSON_KEY) == JSON_ERROR)
				return -1;
			continue;
		}
		if (json_next(&r) != JSON_ARRAY)
			return -1;
		while ((t = json_next(&r)) == JSON_OBJECT) {
			while ((t = json_next(&r)) == JSON_KEY) {
				if (json_is(&r, "title")) {
					if (json_next(&r) != JSON_STRING)
						return -1;
					json_string(&r, title, sizeof(title));
					rows++;
				} else if (json_skip(&r, JSON_KEY) == JSON_ERROR) {
					return -1;
				}
			}
			if (t != JSON_OBJECT_END)
				return -1;
		}
		if (t != JSON_ARRAY_END)
			return -1;
	}
	return t == JSON_OBJECT_END ? rows : -1;
}

static void Probe(const char *name, const char *base, const char *target, const char *listKey)
{
	Handle body;
	long offset = 0;
	unsigned long connect = 0, transfer = 0, t0, parse;
	int status, rows;
	char line[96];

	sprintf(line, "%s: asking\311", name);
	AddLine(line);
	status = Fetch(base, target, &body, &offset, &connect, &transfer);
	if (status != 200) {
		sprintf(line, "%s: failed (%d) after %ld.%ld s", name, status, Seconds10(connect + transfer) / 10,
			Seconds10(connect + transfer) % 10);
		AddLine(line);
		if (body)
			DisposeHandle(body);
		return;
	}
	HLock(body);
	t0 = TickCount();
	rows = CountRows(*body + offset, GetHandleSize(body) - offset, listKey);
	parse = TickCount() - t0;
	sprintf(line, "%s: %ld bytes, %d rows. Connect %ld.%ld s, transfer %ld.%ld s, parse %ld.%ld s", name,
		GetHandleSize(body) - offset, rows, Seconds10(connect) / 10, Seconds10(connect) % 10,
		Seconds10(transfer) / 10, Seconds10(transfer) % 10, Seconds10(parse) / 10, Seconds10(parse) % 10);
	AddLine(line);
	DisposeHandle(body);
}

static void RunProbe(void)
{
	char line[96];
	OSErr err = NetInit();

	if (err != noErr) {
		sprintf(line, "MacTCP isn't available (%d).", err);
		AddLine(line);
		return;
	}
	SetCursor(*GetCursor(watchCursor));
	/* Hister's query JSON for "heavy", 20 rows, newest first, highlighted: %-escaped */
	Probe("Hister", SHIORI_PROBE_HISTER,
		"/search?query=%7B%22text%22%3A%22heavy+-label%3Avault+-metadata.source%3Avault+-type%3Alocal"
		"+-metadata.source%3Acode%22%2C%22highlight%22%3A%22HTML%22%2C%22limit%22%3A20%7D", "documents");
	Probe("Kura", SHIORI_PROBE_KURA, "/api/search?q=many&limit=20&offset=0", "results");
	InitCursor();
	sprintf(line, "Free memory: %ld K", FreeMem() / 1024);
	AddLine(line);
}

static void DoMenu(long choice)
{
	short menu = HiWord(choice), item = LoWord(choice);

	if (menu == kAppleMenu) {
		if (item == kAboutItem) {
			Alert(kAboutAlert, NULL);
		} else {
			Str255 name;
			GetMenuItemText(GetMenuHandle(kAppleMenu), item, name);
			OpenDeskAcc(name);
		}
	} else if (menu == kFileMenu) {
		if (item == kRunItem)
			RunProbe();
		else if (item == kQuitItem)
			gQuit = true;
	} else if (menu == kEditMenu) {
		SystemEdit(item - 1);
	}
	HiliteMenu(0);
}

static void DoMouseDown(EventRecord *e)
{
	WindowPtr w;
	short part = FindWindow(e->where, &w);

	switch (part) {
	case inMenuBar:
		DoMenu(MenuSelect(e->where));
		break;
	case inSysWindow:
		SystemClick(e, w);
		break;
	case inDrag: {
		Rect bounds = qd.screenBits.bounds;
		InsetRect(&bounds, 4, 4);
		DragWindow(w, e->where, &bounds);
		break;
	}
	case inGoAway:
		if (TrackGoAway(w, e->where))
			gQuit = true;
		break;
	case inContent:
		if (w != FrontWindow())
			SelectWindow(w);
		break;
	}
}

static void Setup(void)
{
	Rect r;
	char line[96];
	Handle bar;

	InitGraf(&qd.thePort);
	InitFonts();
	FlushEvents(everyEvent, 0);
	InitWindows();
	InitMenus();
	TEInit();
	InitDialogs(NULL);
	InitCursor();
	MaxApplZone();
	gHasWNE = NGetTrapAddress(_WaitNextEvent, kToolboxTrapType) != NGetTrapAddress(_Unimplemented, kToolboxTrapType);

	bar = GetNewMBar(128);
	SetMenuBar(bar);
	AppendResMenu(GetMenuHandle(kAppleMenu), 'DRVR');
	DrawMenuBar();

	SetRect(&r, 8, 44, 504, 334);
	gWindow = NewWindow(NULL, &r, "\pShiori Probe", true, documentProc, (WindowPtr) -1L, true, 0);
	sprintf(line, "Shiori %s probe. File > Run Probe (Cmd-R); Cmd-. cancels.", SHIORI_VERSION);
	AddLine(line);
	AddLine("Hister: " SHIORI_PROBE_HISTER "   Kura: " SHIORI_PROBE_KURA);
}

int main(void)
{
	EventRecord e;

	Setup();
	while (!gQuit) {
		if (!GetEvent(&e, 30))
			continue;
		switch (e.what) {
		case mouseDown:
			DoMouseDown(&e);
			break;
		case keyDown:
		case autoKey:
			if (e.modifiers & cmdKey)
				DoMenu(MenuKey((char) (e.message & charCodeMask)));
			break;
		case updateEvt:
			DoUpdate((WindowPtr) e.message);
			break;
		}
	}
	return 0;
}
