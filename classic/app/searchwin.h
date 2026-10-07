/*
 * searchwin.h: Shiori's window, laid out as the Haiku app's: the search
 * field (Return searches; typing never does), the four pills (All, Pages,
 * Notes, Code; ⌘1-⌘4), the result list and a status line.
 *   All:   Kura's top notes, then your pages from Hister
 *   Pages: Hister, 10 a page (Show More follows its page_key)
 *   Notes: Kura, 10 a page (by offset), the chosen vault ("" for the default)
 *   Code:  Hister's code pages
 * No words: the newest pages and notes. One request at a time; a new
 * search stops the one under way; ⌘-. stops it.
 */
#ifndef SHIORI_SEARCHWIN_H
#define SHIORI_SEARCHWIN_H

#include <Events.h>
#include <Windows.h>

#include "prefs.h"

/* The window keeps prefs (a pointer): Notes' vault is saved there. */
void SearchWindowOpen(Prefs *prefs);
/* After Preferences changed the bridge or the token. */
void SearchWindowConfigChanged(void);
Boolean IsSearchWindow(WindowPtr w);

/* Events the app passes on when the window is in front (or for it). */
void SearchWindowUpdate(void);
void SearchWindowActivate(Boolean active);
void SearchWindowClick(EventRecord *e);
void SearchWindowKey(EventRecord *e);
void SearchWindowGrow(Point where);
void SearchWindowZoom(Point where, short part);
void SearchWindowIdle(void);
/* Moves the network along; true while a search is under way (the loop then doesn't sleep). */
Boolean SearchWindowPoll(void);
void SearchWindowCursor(Point where);

/* Searches for text (Mac Roman), as the Shiori Search desk accessory asks. */
void SearchWindowSearchFor(const char *macRoman);
/* A Balloon Help tip for the point (global) and its area, or NULL. */
const char *SearchWindowBalloon(Point where, Rect *hot);

/* Commands (menus). */
void SearchWindowPill(int pill);
void SearchWindowFind(void);
void SearchWindowShowMore(void);
void SearchWindowStop(void);
void SearchWindowCopyLink(void);
void SearchWindowOpenSelected(void);
/* Edit menu items in the field: 0 Undo, 2 Cut, 3 Copy, 4 Paste, 5 Clear, 6 Select All. */
void SearchWindowEdit(short item);
/* What the menus should offer now. */
Boolean SearchWindowHasSelection(void);
Boolean SearchWindowHasMore(void);
Boolean SearchWindowBusy(void);

#endif
