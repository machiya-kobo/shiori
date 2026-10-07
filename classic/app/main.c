/*
 * Shiori for Classic Macintosh: the probe (phases 0 and 2). One window that
 * runs requests through the bridge and reports what they took on this Mac:
 * File > Run Probe (⌘R) a Hister and a Kura search; File > Error Probes (⌘E)
 * the ways a request can fail. The network runs from the event loop, so
 * the window keeps drawing and ⌘-. stops a request. The search window
 * replaces this in phase 3.
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
#include <Traps.h>
#include <string.h>
#include <stdio.h>

#include "../core/config.h"
#include "../core/results.h"
#include "fetch.h"

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
enum { kRunItem = 1, kErrorsItem = 2, kQuitItem = 4 };
enum { kAboutAlert = 128 };

#define MAX_LINES 24
#define MAX_REPLY (256L * 1024L)

typedef struct Step {
	const char *name;
	int kura;               /* 0: Hister's address, 1: Kura's, 2: a bad address */
	const char *target;
	int tokenless;          /* send no room token */
	long cap;               /* the largest reply kept (0: MAX_REPLY) */
} Step;

#define HEAVY "search?query=%7B%22text%22%3A%22heavy+-label%3Avault+-metadata.source%3Avault+-type%3Alocal" \
	"+-metadata.source%3Acode%22%2C%22highlight%22%3A%22HTML%22%2C%22limit%22%3A20%7D"

static const Step kSearchSteps[] = {
	{"Hister", 0, HEAVY, 0, 0},
	{"Kura", 1, "api/search?limit=20&offset=0&q=many&sort=relevance", 0, 0},
};

/* Slow first, so ⌘-. a few seconds in stops it. */
static const Step kErrorSteps[] = {
	{"Slow (Cmd-. stops it)", 1, "api/search?limit=5&offset=0&q=slow", 0, 0},
	{"No token", 0, "search?query=%7B%22text%22%3A%22x%22%7D", 1, 0},
	{"Redirect", 1, "api/search?limit=5&offset=0&q=redirect", 0, 0},
	{"Over the Mac's cap (8 KB here)", 0, HEAVY, 0, 8192},
	{"Over the bridge's cap", 1, "api/search?limit=5&offset=0&q=huge", 0, 0},
	{"Not an address", 2, "api/recent", 0, 0},
};

static WindowPtr gWindow;
static char gLines[MAX_LINES][160];
static int gLineCount;
static Boolean gQuit;
static Boolean gHasWNE;
static ShioriConfig gConfig;
static Fetch gFetch;
static const Step *gSteps;
static int gStepCount, gStep;
static int gRows;

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
		unsigned char pstr[160];
		size_t n = strlen(gLines[i]);
		pstr[0] = (unsigned char) n;
		memcpy(pstr + 1, gLines[i], n);
		MoveTo(8, 14 + i * 12);
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

static void Tenths(char *out, unsigned long ticks)
{
	unsigned long t = (ticks * 10 + 30) / 60;
	sprintf(out, "%lu.%lu s", t / 10, t % 10);
}

static void CountRow(void *ctx, const ShioriRow *row)
{
	(void) ctx;
	(void) row;
	gRows++;
}

static void StartStep(void)
{
	const Step *s;
	ShioriConfig config = gConfig;
	char line[100];

	if (gStep >= gStepCount) {
		sprintf(line, "Done. Free memory: %ld K", FreeMem() / 1024);
		AddLine(line);
		InitCursor();
		gSteps = NULL;
		return;
	}
	s = &gSteps[gStep];
	if (s->tokenless)
		config.roomToken[0] = '\0';
	sprintf(line, "%s: asking\311", s->name);
	AddLine(line);
	FetchStart(&gFetch, &config, s->kura == 2 ? "http://bridge.example:8071/" : s->kura ? config.kura : config.hister,
		s->target, s->cap ? s->cap : MAX_REPLY, gStep);
}

static void StepDone(void)
{
	const Step *s = &gSteps[gStep];
	char line[240], connect[16], transfer[16], parse[16], problem[160];
	unsigned long t0;
	long len;
	const char *body;
	ShioriPage page;

	if (gFetch.state == FETCH_DONE && gFetch.head.status == 200) {
		body = FetchBody(&gFetch, &len);
		gRows = 0;
		t0 = TickCount();
		if (s->kura)
			shiori_parse_kura(body, len, &page, CountRow, NULL);
		else
			shiori_parse_hister(body, len, &page, CountRow, NULL);
		Tenths(parse, TickCount() - t0);
		Tenths(connect, gFetch.connected - gFetch.started);
		Tenths(transfer, gFetch.finished - gFetch.connected);
		sprintf(line, "%s: %ld bytes, %d rows%s. Connect %s, transfer %s (%ld reads), parse %s", s->name, len,
			gRows, page.ok ? "" : " (unreadable)", connect, transfer, gFetch.receives, parse);
	} else {
		FetchProblem(&gFetch, s->kura ? "Kura" : "Hister", problem, (long) sizeof(problem));
		Tenths(transfer, (gFetch.finished ? gFetch.finished : TickCount()) - gFetch.started);
		sprintf(line, "%s: %s (%s)", s->name, problem, transfer);
	}
	AddLine(line);
	FetchReset(&gFetch);
	gStep++;
	StartStep();
}

static void RunSteps(const Step *steps, int count)
{
	OSErr err = NetInit();
	char line[100];

	if (gSteps != NULL)
		return;
	if (err != noErr) {
		sprintf(line, "MacTCP isn't available (%d).", err);
		AddLine(line);
		return;
	}
	SetCursor(*GetCursor(watchCursor));
	gSteps = steps;
	gStepCount = count;
	gStep = 0;
	StartStep();
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
			RunSteps(kSearchSteps, (int) (sizeof(kSearchSteps) / sizeof(kSearchSteps[0])));
		else if (item == kErrorsItem)
			RunSteps(kErrorSteps, (int) (sizeof(kErrorSteps) / sizeof(kErrorSteps[0])));
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

static Boolean GetEvent(EventRecord *e, long sleep)
{
	if (gHasWNE)
		return WaitNextEvent(everyEvent, e, sleep, NULL);
	SystemTask();
	return GetNextEvent(everyEvent, e);
}

static void Setup(void)
{
	Rect r;
	char line[100];

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

	SetMenuBar(GetNewMBar(128));
	AppendResMenu(GetMenuHandle(kAppleMenu), 'DRVR');
	DrawMenuBar();

	memset(&gConfig, 0, sizeof(gConfig));
	strcpy(gConfig.hister, SHIORI_PROBE_HISTER);
	strcpy(gConfig.kura, SHIORI_PROBE_KURA);
	strcpy(gConfig.roomToken, SHIORI_PROBE_TOKEN);
	FetchInit(&gFetch);

	SetRect(&r, 8, 44, 504, 334);
	gWindow = NewWindow(NULL, &r, "\pShiori Probe", true, documentProc, (WindowPtr) -1L, true, 0);
	sprintf(line, "Shiori %s probe. Cmd-R: searches. Cmd-E: error probes. Cmd-. stops.", SHIORI_VERSION);
	AddLine(line);
	AddLine("Hister " SHIORI_PROBE_HISTER "   Kura " SHIORI_PROBE_KURA);
}

int main(void)
{
	EventRecord e;

	Setup();
	while (!gQuit) {
		Boolean busy = gSteps != NULL;
		if (GetEvent(&e, busy ? 0 : 30)) {
			switch (e.what) {
			case mouseDown:
				DoMouseDown(&e);
				break;
			case keyDown:
			case autoKey:
				if ((e.modifiers & cmdKey) && (e.message & charCodeMask) == '.')
					FetchCancel(&gFetch);
				else if (e.modifiers & cmdKey)
					DoMenu(MenuKey((char) (e.message & charCodeMask)));
				break;
			case updateEvt:
				DoUpdate((WindowPtr) e.message);
				break;
			}
		}
		if (gSteps != NULL && !FetchPoll(&gFetch))
			StepDone();
	}
	FetchReset(&gFetch);
	return 0;
}
