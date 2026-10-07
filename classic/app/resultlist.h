/*
 * resultlist.h: the search window's list. Rows (section headers, results,
 * Show More) live in one relocatable handle, as Mac Roman for drawing, with
 * the link kept as sent. Drawn by hand in 1-bit QuickDraw: a bold title,
 * the place line (the host, or a note's folder) with a Note or Code tag,
 * and one line of snippet with the matched words bold. A vertical scroll
 * bar; click, double-click, ↑/↓, Page Up/Down, Home/End.
 */
#ifndef SHIORI_RESULTLIST_H
#define SHIORI_RESULTLIST_H

#include <Quickdraw.h>
#include <Windows.h>

enum { LROW_PAGE = 'p', LROW_NOTE = 'n', LROW_CODE = 'c', LROW_HEADER = 'h', LROW_MORE = 'm' };

typedef struct ListRow {
	char kind;
	char title[100];        /* Mac Roman; a header's text */
	char place[64];         /* Mac Roman: the host, or a note's folder */
	char snippet[160];      /* Mac Roman, with SNIPPET_MARK_ON/OFF bytes */
	char url[256];          /* as the server sent it (UTF-8) */
	char path[160];         /* a note's path in its vault (UTF-8) */
	char vault[48];         /* a note's vault ("" for the default) */
} ListRow;

typedef struct ResultList {
	WindowPtr window;
	Rect frame;             /* the list's area, scroll bar excluded */
	ControlHandle bar;
	Handle rows;            /* ListRow[count] */
	short count, cap;
	short selected;         /* -1: none */
	short top;              /* scroll offset in pixels */
	Boolean focused;        /* the keyboard is in the list */
	Boolean active;         /* the window is in front */
} ResultList;

void ListInit(ResultList *l, WindowPtr w, const Rect *frame, short cap);
void ListSetFrame(ResultList *l, const Rect *frame);
void ListClear(ResultList *l);
/* A new row at the end (zeroed), or NULL when the list is full or memory is.
   The pointer is good until the next call that can move memory. */
ListRow *ListAppend(ResultList *l, char kind);
/* Removes the last row (a Show More that's being replaced). */
void ListDropLast(ResultList *l);
/* A copy of row i; false when there is none. */
Boolean ListGet(const ResultList *l, short i, ListRow *out);
short ListCount(const ResultList *l);
short ListSelected(const ResultList *l);
/* After rows changed: the scroll bar's range, and a redraw. */
void ListChanged(ResultList *l);
void ListDraw(ResultList *l);
void ListActivate(ResultList *l, Boolean active);
void ListFocus(ResultList *l, Boolean focused);
/* A click in the list (or its bar): true when it was a double-click on a row. */
Boolean ListClick(ResultList *l, Point where, Boolean doubleClick);
/* ↑ ↓, Page Up/Down, Home/End: true when it was one of those keys. */
Boolean ListKey(ResultList *l, char key);
/* Selects the first result (not a header); false when there's none. */
Boolean ListSelectFirst(ResultList *l);

#endif
