/* searchwin.c: see searchwin.h. */
#include <Fonts.h>
#include <Memory.h>
#include <TextEdit.h>
#include <ToolUtils.h>
#include <stdio.h>
#include <string.h>

#include "../core/notetext.h"
#include "../core/query.h"
#include "../core/results.h"
#include "../core/roman.h"
#include "draw.h"
#include "fetch.h"
#include "reader.h"
#include "resultlist.h"
#include "searchwin.h"

#define MARGIN 8
#define FIELD_TOP 6
#define FIELD_H 18
#define PILLS_TOP 30
#define PILL_H 18
#define LIST_TOP 54
#define STATUS_H 15
#define PAGE_ROWS 10            /* a page of results (the list shows about 8 on a Mac Plus) */
#define ALL_NOTES 5             /* All's top notes */
#define MAX_ROWS 120
#define MAX_REPLY (256L * 1024L)
#define MAX_TYPED 200

enum { kReturn = 0x0D, kEnter = 0x03, kTab = 0x09, kDownArrow = 0x1F, kUpArrow = 0x1E, kBackspace = 0x08 };

/* What the request under way is for. */
enum { STAGE_NONE, STAGE_ALL_NOTES, STAGE_ALL_PAGES, STAGE_PAGES, STAGE_NOTES, STAGE_CODE };

static WindowPtr gWin;
static ShioriConfig gConfig;
static TEHandle gField;
static ResultList gList;
static Rect gFieldRect, gPillRects[4], gStatusRect;
static int gPill = PILL_ALL;
static char gStatus[200];
static Fetch gFetch;
static int gStage = STAGE_NONE;
static char gQuery[SHIORI_MAX_TEXT + 1];        /* the search under way or shown (UTF-8) */
static char gVault[48];                         /* Notes' vault: "" the default */
static Boolean gFocusList;
static Boolean gActive = true;
static long gTotalPages, gTotalNotes;
static int gMoreStage = STAGE_NONE;             /* what Show More asks for, or STAGE_NONE */
static char gMoreKey[96];                       /* Hister's page_key */
static long gMoreOffset;                        /* Kura's next offset */
static Boolean gAppending;                      /* the request is Show More's */
static long gTag;
static char gProblem[160];                      /* the first error of a two-part search */

static const char *const kPillLabels[4] = {"All", "Pages", "Notes", "Code"};

/* TextEdit's private scrap and the desk scrap (Inside Macintosh I-389: the glue
   routines TEFromScrap and TEToScrap, which Multiversal doesn't have). */
/* Multiversal's low-memory accessors dereference fixed addresses, which GCC takes for out of bounds. */
#pragma GCC diagnostic ignored "-Warray-bounds"
static void TEScrapFromDesk(void)
{
	long offset, len;
	Handle h = LMGetTEScrpHandle();

	len = GetScrap(h, 'TEXT', &offset);
	if (len >= 0 && len < 32767)
		LMSetTEScrpLength((short) len);
}

static void TEScrapToDesk(void)
{
	Handle h = LMGetTEScrpHandle();

	ZeroScrap();
	HLock(h);
	PutScrap(LMGetTEScrpLength(), 'TEXT', *h);
	HUnlock(h);
}

/* -- layout and drawing ----------------------------------------------------------------- */

static void Layout(void)
{
	Rect port = gWin->portRect, list;
	short x = MARGIN, i;

	SetRect(&gFieldRect, MARGIN, FIELD_TOP, (short) (port.right - MARGIN), (short) (FIELD_TOP + FIELD_H));
	if (gField != NULL) {
		Rect view = gFieldRect;
		InsetRect(&view, 3, 2);
		(**gField).viewRect = view;
		(**gField).destRect = view;
		(**gField).destRect.right = (short) (view.left + 2000);   /* one line: never wraps */
		TECalText(gField);
	}
	TextFont(systemFont);
	TextSize(12);
	for (i = 0; i < 4; i++) {
		short w = (short) (TextWidth((Ptr) kPillLabels[i], 0, (short) strlen(kPillLabels[i])) + 20);
		SetRect(&gPillRects[i], x, PILLS_TOP, (short) (x + w), (short) (PILLS_TOP + PILL_H));
		x = (short) (x + w + 6);
	}
	SetRect(&gStatusRect, 0, (short) (port.bottom - STATUS_H + 1), (short) (port.right - 15), port.bottom);
	SetRect(&list, 0, LIST_TOP, (short) (port.right - 15), (short) (port.bottom - STATUS_H));
	if (gList.window != NULL)
		ListSetFrame(&gList, &list);
	else
		ListInit(&gList, gWin, &list, MAX_ROWS);
}

static void DrawPills(void)
{
	short i;

	TextFont(systemFont);
	TextSize(12);
	for (i = 0; i < 4; i++) {
		Rect r = gPillRects[i];
		short w = TextWidth((Ptr) kPillLabels[i], 0, (short) strlen(kPillLabels[i]));
		EraseRoundRect(&r, PILL_H, PILL_H);
		if (i == gPill) {
			PaintRoundRect(&r, PILL_H, PILL_H);
			TextMode(srcBic);
		} else {
			FrameRoundRect(&r, PILL_H, PILL_H);
		}
		MoveTo((short) (r.left + (r.right - r.left - w) / 2), (short) (r.bottom - 5));
		DrawC(kPillLabels[i]);
		TextMode(srcOr);
		if (!gActive && i != gPill) {
			/* inactive: the pills are dimmed, as a window's controls are */
			PenPat(&qd.gray);
			PenMode(patBic);
			PaintRoundRect(&r, PILL_H, PILL_H);
			PenNormal();
			FrameRoundRect(&r, PILL_H, PILL_H);
		}
	}
}

static void DrawStatus(void)
{
	Rect r = gStatusRect;

	EraseRect(&r);
	TextFont(kFontIDGeneva);
	TextSize(9);
	MoveTo(MARGIN, (short) (r.bottom - 4));
	DrawFitted(gStatus, (short) (r.right - r.left - 2 * MARGIN));
}

static void SetStatus(const char *s)
{
	GrafPtr old;

	strncpy(gStatus, s, sizeof(gStatus) - 1);
	gStatus[sizeof(gStatus) - 1] = '\0';
	GetPort(&old);
	SetPort(gWin);
	DrawStatus();
	SetPort(old);
}

/* The grow box alone: DrawGrowIcon also draws the scroll bar's column the
   window's whole height, through the field and pills. */
static void DrawGrow(void)
{
	RgnHandle old = NewRgn();
	Rect box = gWin->portRect;

	GetClip(old);
	box.left = (short) (box.right - 15);
	box.top = (short) (box.bottom - 15);
	ClipRect(&box);
	DrawGrowIcon(gWin);
	SetClip(old);
	DisposeRgn(old);
	MoveTo(0, (short) (gStatusRect.top - 1));
	LineTo((short) (gWin->portRect.right - 15), (short) (gStatusRect.top - 1));
}

static void DrawAll(void)
{
	Rect r = gFieldRect;

	FrameRect(&r);
	TextFont(systemFont);
	TextSize(12);
	TEUpdate(&gWin->portRect, gField);
	DrawPills();
	MoveTo(0, (short) (LIST_TOP - 1));
	LineTo(gWin->portRect.right, (short) (LIST_TOP - 1));
	ListDraw(&gList);
	DrawStatus();
	DrawGrow();
}

/* -- focus ---------------------------------------------------------------------------------- */

static void Focus(Boolean list)
{
	if (list == gFocusList)
		return;
	gFocusList = list;
	if (list)
		TEDeactivate(gField);
	else if (gActive)
		TEActivate(gField);
	ListFocus(&gList, list);
}

/* -- searching ---------------------------------------------------------------------------- */

static void AddMore(int stage)
{
	ListRow *row = ListAppend(&gList, LROW_MORE);
	if (row != NULL) {
		strcpy(row->title, "Show More\311");
		gMoreStage = stage;
	}
}

static int gSection;                            /* the stage whose rows are coming in */
static Boolean gHeaderDone;

static void AddRow(void *ctx, const ShioriRow *r)
{
	ListRow *row;
	char snippet[sizeof(r->snippet)];

	(void) ctx;
	if (!gHeaderDone && (gSection == STAGE_ALL_NOTES || gSection == STAGE_ALL_PAGES)) {
		row = ListAppend(&gList, LROW_HEADER);
		if (row != NULL)
			strcpy(row->title, gSection == STAGE_ALL_NOTES ? "Notes" : "Pages");
	}
	gHeaderDone = true;
	row = ListAppend(&gList, r->kind == ROW_NOTE ? LROW_NOTE : r->kind == ROW_CODE ? LROW_CODE : LROW_PAGE);
	if (row == NULL)
		return;
	strncpy(row->title, r->title, sizeof(row->title) - 1);
	roman_from_utf8(row->title);
	if (r->kind == ROW_NOTE)
		strncpy(row->place, r->host[0] ? r->host : "Notes", sizeof(row->place) - 1);
	else
		strncpy(row->place, r->host, sizeof(row->place) - 1);
	roman_from_utf8(row->place);
	shiori_snippet_text(r->snippet, snippet, (long) sizeof(snippet));
	roman_from_utf8(snippet);
	strncpy(row->snippet, snippet, sizeof(row->snippet) - 1);
	strncpy(row->url, r->url, sizeof(row->url) - 1);
	strncpy(row->path, r->path, sizeof(row->path) - 1);
	/* the vault is the address's: Kura names the default vault in its replies too */
	shiori_url_vault(r->url, row->vault, (long) sizeof(row->vault));
}

static void ShowTotals(void)
{
	char s[120];

	if (gProblem[0]) {
		SetStatus(gProblem);
		return;
	}
	switch (gPill) {
	case PILL_ALL:
		sprintf(s, "%ld page%s \245 %ld note%s", gTotalPages, gTotalPages == 1 ? "" : "s", gTotalNotes,
			gTotalNotes == 1 ? "" : "s");
		break;
	case PILL_PAGES: sprintf(s, "%ld page%s", gTotalPages, gTotalPages == 1 ? "" : "s"); break;
	case PILL_NOTES: sprintf(s, "%ld note%s", gTotalNotes, gTotalNotes == 1 ? "" : "s"); break;
	default: sprintf(s, "%ld code page%s", gTotalPages, gTotalPages == 1 ? "" : "s"); break;
	}
	if (ListCount(&gList) == 0)
		strcpy(s, gQuery[0] ? "Nothing found." : "Nothing here yet.");
	SetStatus(s);
}

static void Request(int stage)
{
	char target[1100];
	const char *base;
	int ok;

	gStage = stage;
	switch (stage) {
	case STAGE_ALL_NOTES:
		ok = shiori_kura_search_target(gQuery, ALL_NOTES, 0, "", target, (long) sizeof(target));
		base = gConfig.kura;
		break;
	case STAGE_NOTES:
		ok = shiori_kura_search_target(gQuery, PAGE_ROWS, gAppending ? gMoreOffset : 0, gVault, target,
			(long) sizeof(target));
		base = gConfig.kura;
		break;
	case STAGE_CODE:
		ok = shiori_hister_search_target(gQuery, PILL_CODE, PAGE_ROWS, gAppending ? gMoreKey : "", target,
			(long) sizeof(target));
		base = gConfig.hister;
		break;
	default:
		ok = shiori_hister_search_target(gQuery, PILL_PAGES, PAGE_ROWS, gAppending ? gMoreKey : "", target,
			(long) sizeof(target));
		base = gConfig.hister;
		break;
	}
	if (!ok) {
		gStage = STAGE_NONE;
		SetStatus("That search is too long.");
		return;
	}
	FetchStart(&gFetch, &gConfig, base, target, MAX_REPLY, ++gTag);
	SetStatus("Searching\311");
}

/* A reply came (or failed): rows in, then the next stage or the end. */
static void Answered(void)
{
	int stage = gStage;
	Boolean kura = stage == STAGE_ALL_NOTES || stage == STAGE_NOTES;
	ShioriPage page;
	long len;
	const char *body;

	gStage = STAGE_NONE;
	memset(&page, 0, sizeof(page));
	if (gFetch.state == FETCH_DONE && gFetch.head.status == 200) {
		body = FetchBody(&gFetch, &len);
		gSection = stage;
		gHeaderDone = gAppending;
		if (kura)
			shiori_parse_kura(body, len, &page, AddRow, NULL);
		else
			shiori_parse_hister(body, len, &page, AddRow, NULL);
		if (!page.ok && !gProblem[0])
			sprintf(gProblem, "%s's answer couldn't be read.", kura ? "Kura" : "Hister");
		if (kura) {
			gTotalNotes = page.total;
			gMoreOffset = (gAppending ? gMoreOffset : 0) + page.received;
		} else {
			gTotalPages = page.total;
			strcpy(gMoreKey, page.next);
		}
	} else if (!gProblem[0]) {
		FetchProblem(&gFetch, kura ? "Kura" : "Hister", gProblem, (long) sizeof(gProblem));
	}
	FetchReset(&gFetch);
	gMoreStage = STAGE_NONE;
	switch (stage) {
	case STAGE_ALL_NOTES:
		Request(STAGE_ALL_PAGES);
		ListChanged(&gList);
		return;
	case STAGE_ALL_PAGES:
	case STAGE_PAGES:
	case STAGE_CODE:
		if (page.ok && page.next[0])
			AddMore(stage == STAGE_ALL_PAGES ? STAGE_PAGES : stage);
		break;
	case STAGE_NOTES:
		if (page.ok && gMoreOffset < page.total && page.received > 0)
			AddMore(STAGE_NOTES);
		break;
	}
	gAppending = false;
	ListChanged(&gList);
	ShowTotals();
}

static void Search(void)
{
	char typed[MAX_TYPED + 1], trimmed[SHIORI_MAX_TEXT + 1];
	CharsHandle text = TEGetText(gField);
	short n = (**gField).teLength;

	if (n > MAX_TYPED)
		n = MAX_TYPED;
	memcpy(typed, *text, (size_t) n);
	typed[n] = '\0';
	if (!roman_to_utf8(typed, gQuery, (long) sizeof(gQuery)))
		gQuery[0] = '\0';
	shiori_trim(gQuery, trimmed, (long) sizeof(trimmed));
	strcpy(gQuery, trimmed);
	FetchReset(&gFetch);
	ListClear(&gList);
	ListChanged(&gList);
	gTotalPages = gTotalNotes = 0;
	gMoreStage = STAGE_NONE;
	gAppending = false;
	gProblem[0] = '\0';
	switch (gPill) {
	case PILL_ALL: Request(STAGE_ALL_NOTES); break;
	case PILL_PAGES: Request(STAGE_PAGES); break;
	case PILL_NOTES: Request(STAGE_NOTES); break;
	default: Request(STAGE_CODE); break;
	}
}

/* -- the window -------------------------------------------------------------------------- */

void SearchWindowOpen(const ShioriConfig *config)
{
	Rect r, view;

	gConfig = *config;
	SetRect(&r, 4, 42, 508, 338);
	gWin = NewWindow(NULL, &r, "\pShiori", true, 8 /* documentProc + zoom box */, (WindowPtr) -1L, true, 0);
	SetPort(gWin);
	TextFont(systemFont);
	TextSize(12);
	view = r;
	gField = NULL;
	Layout();
	view = gFieldRect;
	InsetRect(&view, 3, 2);
	gField = TENew(&view, &view);
	(**gField).crOnly = -1;
	Layout();
	TEActivate(gField);
	SetStatus("Type, then Return, to search Hister and Kura.");
	if (!config->roomToken[0])
		SetStatus("No room token yet: Preferences\311");
	FetchInit(&gFetch);
}

Boolean IsSearchWindow(WindowPtr w)
{
	return w != NULL && w == gWin;
}

void SearchWindowUpdate(void)
{
	GrafPtr old;

	GetPort(&old);
	SetPort(gWin);
	BeginUpdate(gWin);
	EraseRect(&gWin->portRect);
	DrawAll();
	EndUpdate(gWin);
	SetPort(old);
}

void SearchWindowActivate(Boolean active)
{
	SetPort(gWin);
	gActive = active;
	if (active && !gFocusList)
		TEActivate(gField);
	else
		TEDeactivate(gField);
	ListActivate(&gList, active);
	DrawGrow();
	InvalRect(&gWin->portRect);
}

void SearchWindowClick(EventRecord *e)
{
	Point p = e->where;
	short i;
	static unsigned long lastClick;
	Boolean dbl;

	SetPort(gWin);
	GlobalToLocal(&p);
	dbl = (long) (e->when - lastClick) <= LMGetDoubleTime();
	lastClick = e->when;
	if (PtInRect(p, &gFieldRect)) {
		Focus(false);
		TEClick(p, (e->modifiers & shiftKey) != 0, gField);
		return;
	}
	for (i = 0; i < 4; i++) {
		if (PtInRect(p, &gPillRects[i])) {
			SearchWindowPill(i);
			return;
		}
	}
	{
		Rect listAndBar = gList.frame;
		listAndBar.right += 15;
		if (PtInRect(p, &listAndBar)) {
			Boolean open = ListClick(&gList, p, dbl);
			if (PtInRect(p, &gList.frame)) {
				ListRow row;
				Focus(true);
				if (ListGet(&gList, ListSelected(&gList), &row) && row.kind == LROW_MORE)
					SearchWindowShowMore();
				else if (open)
					SearchWindowOpenSelected();
			}
		}
	}
}

void SearchWindowKey(EventRecord *e)
{
	char c = (char) (e->message & charCodeMask);
	ListRow row;

	SetPort(gWin);
	if (!gFocusList) {
		if (c == kReturn || c == kEnter) {
			Search();
		} else if (c == kDownArrow || c == kTab) {
			if (ListSelectFirst(&gList) || c == kTab)
				Focus(true);
		} else if (c == kUpArrow) {
			/* one line: nothing above */
		} else if (c == kBackspace || (**gField).teLength < MAX_TYPED || (**gField).selStart != (**gField).selEnd) {
			TEKey(c, gField);
		} else {
			SysBeep(1);
		}
		return;
	}
	if (ListKey(&gList, c))
		return;
	if (c == kReturn || c == kEnter) {
		if (ListGet(&gList, ListSelected(&gList), &row) && row.kind == LROW_MORE)
			SearchWindowShowMore();
		else
			SearchWindowOpenSelected();
	} else if (c == kTab) {
		Focus(false);
	} else if ((unsigned char) c >= 0x20) {
		/* typing goes to the field */
		Focus(false);
		TESetSelect(0, 32767, gField);
		TEKey(c, gField);
	}
}

void SearchWindowGrow(Point where)
{
	Rect limits;
	long size;

	SetRect(&limits, 320, 180, qd.screenBits.bounds.right, qd.screenBits.bounds.bottom);
	size = GrowWindow(gWin, where, &limits);
	if (size == 0)
		return;
	SetPort(gWin);
	SizeWindow(gWin, LoWord(size), HiWord(size), true);
	Layout();
	InvalRect(&gWin->portRect);
}

void SearchWindowZoom(Point where, short part)
{
	SetPort(gWin);
	if (!TrackBox(gWin, where, part))
		return;
	EraseRect(&gWin->portRect);
	ZoomWindow(gWin, part, true);
	Layout();
	InvalRect(&gWin->portRect);
}

void SearchWindowIdle(void)
{
	if (gActive && !gFocusList)
		TEIdle(gField);
}

Boolean SearchWindowPoll(void)
{
	if (gStage == STAGE_NONE)
		return false;
	if (FetchPoll(&gFetch))
		return true;
	{
		GrafPtr old;
		GetPort(&old);
		SetPort(gWin);
		Answered();
		SetPort(old);
	}
	return gStage != STAGE_NONE;
}

void SearchWindowCursor(Point where)
{
	Point p = where;

	if (FrontWindow() != gWin) {
		InitCursor();
		return;
	}
	SetPort(gWin);
	GlobalToLocal(&p);
	if (PtInRect(p, &gFieldRect))
		SetCursor(*GetCursor(iBeamCursor));
	else
		InitCursor();
}

/* -- commands ------------------------------------------------------------------------------ */

void SearchWindowPill(int pill)
{
	GrafPtr old;

	if (pill < 0 || pill > 3)
		return;
	GetPort(&old);
	SetPort(gWin);
	gPill = pill;
	DrawPills();
	SetPort(old);
	Search();
}

void SearchWindowFind(void)
{
	SetPort(gWin);
	Focus(false);
	TESetSelect(0, 32767, gField);
}

void SearchWindowShowMore(void)
{
	if (gMoreStage == STAGE_NONE || gStage != STAGE_NONE)
		return;
	SetPort(gWin);
	ListDropLast(&gList);              /* the Show More row */
	gAppending = true;
	gProblem[0] = '\0';
	Request(gMoreStage);
	ListChanged(&gList);
}

void SearchWindowStop(void)
{
	if (gStage == STAGE_NONE) {
		if (gFocusList)
			Focus(false);
		return;
	}
	FetchCancel(&gFetch);
}

void SearchWindowCopyLink(void)
{
	ListRow row;
	char roman[256];

	if (!ListGet(&gList, ListSelected(&gList), &row) || row.url[0] == '\0')
		return;
	strncpy(roman, row.url, sizeof(roman) - 1);
	roman[sizeof(roman) - 1] = '\0';
	roman_from_utf8(roman);
	ZeroScrap();
	PutScrap((long) strlen(roman), 'TEXT', roman);
	SetStatus("Copied the link.");
}

void SearchWindowOpenSelected(void)
{
	ListRow row;

	if (!ListGet(&gList, ListSelected(&gList), &row) || row.url[0] == '\0')
		return;
	if (!ReaderOpen(&gConfig, &row))
		SetStatus("Three readers are open: close one first.");
}

void SearchWindowEdit(short item)
{
	SetPort(gWin);
	switch (item) {
	case 2: TECut(gField); TEScrapToDesk(); break;
	case 3:
		if (gFocusList) {
			SearchWindowCopyLink();
		} else {
			TECopy(gField);
			TEScrapToDesk();
		}
		break;
	case 4: TEScrapFromDesk(); TEPaste(gField); break;
	case 5: TEDelete(gField); break;
	case 6: Focus(false); TESetSelect(0, 32767, gField); break;
	}
}

Boolean SearchWindowHasSelection(void)
{
	ListRow row;
	return ListGet(&gList, ListSelected(&gList), &row) && row.url[0] != '\0';
}

Boolean SearchWindowHasMore(void)
{
	return gMoreStage != STAGE_NONE && gStage == STAGE_NONE;
}

Boolean SearchWindowBusy(void)
{
	return gStage != STAGE_NONE;
}
