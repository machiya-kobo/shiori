/*
 * Shiori for Classic Macintosh: the application. The event loop, the menus
 * and desk accessories; the search window (searchwin.c) does the rest.
 * The network moves along from the loop (no sleep while a search is under
 * way), so the window always answers and ⌘-. stops a search.
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
#include <Gestalt.h>
#include <string.h>

#include "../core/config.h"
#include "ae.h"
#include "defaults.h"
#include "net.h"
#include "prefs.h"
#include "reader.h"
#include "searchwin.h"

enum { kAppleMenu = 128, kFileMenu = 129, kEditMenu = 130, kSearchMenu = 131 };
enum { kAboutItem = 1 };
enum { kOpenItem = 1, kCloseItem = 2, kPrefsItem = 4, kQuitItem = 6 };
enum { kUndoItem = 1, kCutItem = 3, kCopyItem = 4, kPasteItem = 5, kClearItem = 6, kSelectAllItem = 7, kCopyLinkItem = 9 };
enum { kFindItem = 1, kFindAgainItem = 2, kAllItem = 4, kPagesItem = 5, kNotesItem = 6, kCodeItem = 7, kMoreItem = 9,
	kStopItem = 10 };
enum { kAboutAlert = 128 };
/* osEvt's suspend/resume (Inside Macintosh VI; not in Multiversal) */
enum { kSuspendResumeMessage = 1, kResumeFlag = 1 };

static Boolean gQuit;
static Boolean gHasWNE;
static Boolean gInBackground;
static Boolean gReadersBusy;
static Boolean gHaveHelp;               /* System 7's Help Manager: window balloons */
static Prefs gPrefs;

static void Enable(MenuHandle m, short item, Boolean on)
{
	if (on)
		EnableItem(m, item);
	else
		DisableItem(m, item);
}

/* What the menus offer depends on the front window and the window's state. */
static void AdjustMenus(void)
{
	WindowPtr front = FrontWindow();
	Boolean ours = IsSearchWindow(front);
	Boolean reader = IsReaderWindow(front);
	Boolean da = front != NULL && ((WindowPeek) front)->windowKind < 0;
	MenuHandle file = GetMenuHandle(kFileMenu), edit = GetMenuHandle(kEditMenu), search = GetMenuHandle(kSearchMenu);
	short i;

	Enable(file, kOpenItem, ours && SearchWindowHasSelection());
	Enable(file, kCloseItem, da || reader);
	Enable(file, kPrefsItem, !da);
	Enable(edit, kUndoItem, da);
	for (i = kCutItem; i <= kSelectAllItem; i++)
		Enable(edit, i, ours || da);
	Enable(edit, kCopyItem, ours || da || reader);
	Enable(edit, kCopyLinkItem, (ours && SearchWindowHasSelection()) || reader);
	for (i = kFindItem; i <= kStopItem; i++)
		Enable(search, i, ours);
	Enable(search, kFindItem, ours || reader);
	Enable(search, kFindAgainItem, reader && ReaderCanFindAgain(front));
	Enable(search, kMoreItem, ours && SearchWindowHasMore());
	Enable(search, kStopItem, ours && SearchWindowBusy());
}

static void DoMenu(long choice)
{
	short menu = HiWord(choice), item = LoWord(choice);

	HiliteMenu(0);                      /* before any dialog or alert the item opens */
	switch (menu) {
	case kAppleMenu:
		if (item == kAboutItem) {
			Alert(kAboutAlert, NULL);
		} else {
			Str255 name;
			GetMenuItemText(GetMenuHandle(kAppleMenu), item, name);
			OpenDeskAcc(name);
		}
		break;
	case kFileMenu:
		if (item == kOpenItem) {
			SearchWindowOpenSelected();
		} else if (item == kCloseItem) {
			WindowPtr front = FrontWindow();
			if (IsReaderWindow(front))
				ReaderClose(front);
			else if (front != NULL && ((WindowPeek) front)->windowKind < 0)
				CloseDeskAcc(((WindowPeek) front)->windowKind);
		} else if (item == kPrefsItem) {
			if (PrefsDialog(&gPrefs)) {
				SearchWindowConfigChanged();
				ReaderSetTextSize(gPrefs.textSize);
			}
		} else if (item == kQuitItem) {
			gQuit = true;
		}
		break;
	case kEditMenu:
		if (SystemEdit((short) (item - 1)))
			break;
		if (IsReaderWindow(FrontWindow())) {
			if (item == kCopyLinkItem)
				ReaderCopyLink(FrontWindow());
			else if (item == kCopyItem)
				ReaderCopy(FrontWindow());
		} else if (item == kCopyLinkItem) {
			SearchWindowCopyLink();
		} else {
			SearchWindowEdit((short) (item - 1));
		}
		break;
	case kSearchMenu:
		if (IsReaderWindow(FrontWindow())) {
			if (item == kFindItem)
				ReaderFind(FrontWindow());
			else if (item == kFindAgainItem)
				ReaderFindAgain(FrontWindow());
			break;
		}
		switch (item) {
		case kFindItem: SearchWindowFind(); break;
		case kAllItem: case kPagesItem: case kNotesItem: case kCodeItem:
			SearchWindowPill(item - kAllItem);
			break;
		case kMoreItem: SearchWindowShowMore(); break;
		case kStopItem: SearchWindowStop(); break;
		}
		break;
	}
	HiliteMenu(0);
}

static void DoMouseDown(EventRecord *e)
{
	WindowPtr w;
	short part = FindWindow(e->where, &w);

	switch (part) {
	case inMenuBar:
		AdjustMenus();
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
	case inGrow:
		if (IsSearchWindow(w))
			SearchWindowGrow(e->where);
		else if (IsReaderWindow(w))
			ReaderGrow(w, e->where);
		break;
	case inZoomIn:
	case inZoomOut:
		if (IsSearchWindow(w))
			SearchWindowZoom(e->where, part);
		else if (IsReaderWindow(w))
			ReaderZoom(w, e->where, part);
		break;
	case inGoAway:
		if (TrackGoAway(w, e->where)) {
			if (IsReaderWindow(w))
				ReaderClose(w);
			else
				gQuit = true;           /* the search window: closing it quits, as the Haiku app's does */
		}
		break;
	case inContent:
		if (w != FrontWindow())
			SelectWindow(w);
		else if (IsSearchWindow(w))
			SearchWindowClick(e);
		else if (IsReaderWindow(w))
			ReaderClick(w, e);
		break;
	}
}

static void DoKey(EventRecord *e)
{
	char c = (char) (e->message & charCodeMask);

	if (e->modifiers & cmdKey) {
		if (c == '.') {
			if (IsReaderWindow(FrontWindow()))
				ReaderStop(FrontWindow());
			else
				SearchWindowStop();
			return;
		}
		AdjustMenus();
		DoMenu(MenuKey(c));
		return;
	}
	if (IsSearchWindow(FrontWindow()))
		SearchWindowKey(e);
	else if (IsReaderWindow(FrontWindow()))
		ReaderKey(FrontWindow(), e);
}

/* A row the Shiori Search desk accessory asks to read (SHIO/read). */
static void ReadRow(const ListRow *row)
{
	if (!ReaderOpen(&gPrefs.config, row))
		SysBeep(10);
}

static void QuitApp(void)
{
	gQuit = true;
}

/* Balloons for the window's parts while Show Balloons is on (System 7). */
static void Balloons(Point where)
{
	static const char *shown;
	Rect hot;
	const char *tip;
	HMMessageRecord msg;
	size_t n;

	if (!gHaveHelp || !HMGetBalloons())
		return;
	tip = SearchWindowBalloon(where, &hot);
	if (tip == shown && (tip == NULL || HMIsBalloon()))
		return;
	shown = tip;
	if (tip == NULL)
		return;
	memset(&msg, 0, sizeof(msg));
	msg.hmmHelpType = 1;                /* khmmString */
	n = strlen(tip) > 255 ? 255 : strlen(tip);
	msg.u.hmmString[0] = (unsigned char) n;
	memcpy(msg.u.hmmString + 1, tip, n);
	LocalToGlobal((Point *) &hot.top);
	LocalToGlobal((Point *) &hot.bottom);
	(void) HMShowBalloon(&msg, where, &hot, NULL, 0, 0, 0);
}

static Boolean GetEvent(EventRecord *e, long sleep)
{
	if (gHasWNE)
		return WaitNextEvent(everyEvent, e, sleep, NULL);
	SystemTask();
	return GetNextEvent(everyEvent, e);
}

static void Setup(Prefs *prefs)
{
	ShioriConfig *config = &prefs->config;

	InitGraf(&qd.thePort);
	InitFonts();
	FlushEvents(everyEvent, 0);
	InitWindows();
	InitMenus();
	TEInit();
	InitDialogs(NULL);
	InitCursor();
	/* a 32 KB stack, not the Mac Plus's 8 KB: a search's request and a reply's
	   parse each want a few kilobytes of it (before MaxApplZone grows the heap up to it) */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Warray-bounds"   /* low-memory globals at fixed addresses */
	{
		Ptr limit = (Ptr) ((long) LMGetCurStackBase() - 32L * 1024L);
		if (limit < LMGetApplLimit())
			SetApplLimit(limit);
	}
#pragma GCC diagnostic pop
	MaxApplZone();
	MoreMasters();
	MoreMasters();
	gHasWNE = NGetTrapAddress(_WaitNextEvent, kToolboxTrapType) != NGetTrapAddress(_Unimplemented, kToolboxTrapType);

	SetMenuBar(GetNewMBar(128));
	AppendResMenu(GetMenuHandle(kAppleMenu), 'DRVR');
	DrawMenuBar();

	memset(config, 0, sizeof(*config));
	strcpy(config->hister, SHIORI_DEFAULT_HISTER);
	strcpy(config->kura, SHIORI_DEFAULT_KURA);
	shiori_checked_room_token(SHIORI_DEFAULT_TOKEN, config->roomToken, (long) sizeof(config->roomToken));
	prefs->textSize = 12;
	prefs->vault[0] = '\0';
	PrefsLoad(prefs);
	(void) NetInit();
	{
		long response;
		gHaveHelp = NGetTrapAddress(_Gestalt, kToolboxTrapType) != NGetTrapAddress(_Unimplemented, kToolboxTrapType)
			&& Gestalt(gestaltHelpMgrAttr, &response) == noErr && (response & 1);
	}
	AppleEventsInit(QuitApp, SearchWindowSearchFor, ReadRow);
}

int main(void)
{
	EventRecord e;

	Setup(&gPrefs);
	ReaderSetTextSize(gPrefs.textSize);
	SearchWindowOpen(&gPrefs);
	/* the first run (the placeholder address), or through the bridge with no room token: Preferences first */
	if (strstr(gPrefs.config.hister, "192.0.2.") != NULL || (!gPrefs.config.direct && !gPrefs.config.roomToken[0])) {
		if (PrefsDialog(&gPrefs))
			SearchWindowConfigChanged();
	}
	while (!gQuit) {
		Boolean busy = SearchWindowBusy() || gReadersBusy;
		if (GetEvent(&e, busy ? 0 : (gInBackground ? 30 : 10))) {
			switch (e.what) {
			case mouseDown:
				DoMouseDown(&e);
				break;
			case keyDown:
			case autoKey:
				DoKey(&e);
				break;
			case updateEvt:
				if (IsSearchWindow((WindowPtr) e.message))
					SearchWindowUpdate();
				else if (IsReaderWindow((WindowPtr) e.message))
					ReaderUpdate((WindowPtr) e.message);
				break;
			case activateEvt:
				if (IsSearchWindow((WindowPtr) e.message))
					SearchWindowActivate((e.modifiers & activeFlag) != 0);
				else if (IsReaderWindow((WindowPtr) e.message))
					ReaderActivate((WindowPtr) e.message, (e.modifiers & activeFlag) != 0);
				break;
			case kHighLevelEvent:
				AppleEventsHandle(&e);
				break;
			case osEvt:
				if (((e.message >> 24) & 0xFF) == kSuspendResumeMessage) {
					gInBackground = (e.message & kResumeFlag) == 0;
					if (IsSearchWindow(FrontWindow()))
						SearchWindowActivate(!gInBackground);
					else if (IsReaderWindow(FrontWindow()))
						ReaderActivate(FrontWindow(), !gInBackground);
				}
				break;
			}
		} else if (!gInBackground) {
			SearchWindowIdle();
		}
		SearchWindowCursor(e.where);
		Balloons(e.where);
		SearchWindowPoll();
		gReadersBusy = ReaderPollAll();
	}
	ReaderCloseAll();
	return 0;
}
