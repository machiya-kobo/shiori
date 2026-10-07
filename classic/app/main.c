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
#include <string.h>

#include "../core/config.h"
#include "net.h"
#include "reader.h"
#include "searchwin.h"

/* The bridge and the Mac's room token until Preferences has them. Builds take
   them from classic/local.env (gitignored); these neutral defaults reach nothing. */
#ifndef SHIORI_DEFAULT_HISTER
#define SHIORI_DEFAULT_HISTER "http://192.0.2.1:8070/"
#endif
#ifndef SHIORI_DEFAULT_KURA
#define SHIORI_DEFAULT_KURA "http://192.0.2.1:8071/"
#endif
#ifndef SHIORI_DEFAULT_TOKEN
#define SHIORI_DEFAULT_TOKEN ""
#endif

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
	Enable(file, kPrefsItem, false);              /* phase 5 */
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

static Boolean GetEvent(EventRecord *e, long sleep)
{
	if (gHasWNE)
		return WaitNextEvent(everyEvent, e, sleep, NULL);
	SystemTask();
	return GetNextEvent(everyEvent, e);
}

static void Setup(ShioriConfig *config)
{
	InitGraf(&qd.thePort);
	InitFonts();
	FlushEvents(everyEvent, 0);
	InitWindows();
	InitMenus();
	TEInit();
	InitDialogs(NULL);
	InitCursor();
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
	(void) NetInit();
}

int main(void)
{
	EventRecord e;
	ShioriConfig config;

	Setup(&config);
	SearchWindowOpen(&config);
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
		SearchWindowPoll();
		gReadersBusy = ReaderPollAll();
	}
	ReaderCloseAll();
	return 0;
}
