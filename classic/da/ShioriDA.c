/*
 * Shiori Search, the desk accessory: a quick search from the Apple menu, the
 * classic counterpart of the Haiku Deskbar item and Linux's --quick. A field
 * and up to eight rows: your notes from Kura (the default vault only), then
 * your pages from Hister. Return searches; Return on a row (or a double-click)
 * opens it in Shiori's reader on System 7 (SHIO/read, launching Shiori when
 * it isn't running), and copies its link on System 6, which has no Apple
 * events. Copy copies the selected row's link.
 *
 * It reads Hister's and Kura's addresses and the tokens from Shiori
 * Preferences and opens its own MacTCP stream, through the same core and
 * fetch code as the app, so the credential rule is the same. Its state hangs
 * from dCtlStorage; it has no resources of its own (Font/DA Mover renumbers
 * a DA, so strings live in the code).
 *
 * Built as a flat code resource (-Wl,--mac-flat): the DRVR header sits in
 * .rsrcheader, which Elf2Mac places first, and its offsets point at the
 * glue below, which calls the C routines with (param block, DCE).
 */
#include <Devices.h>
#include <Events.h>
#include <Fonts.h>
#include <Gestalt.h>
#include <Memory.h>
#include <OSUtils.h>
#include <Quickdraw.h>
#include <Retro68Runtime.h>
#include <TextEdit.h>
#include <ToolUtils.h>
#include <Traps.h>
#include <Windows.h>
#include <string.h>

#include "../core/config.h"
#include "../core/notetext.h"
#include "../core/query.h"
#include "../core/results.h"
#include "../core/roman.h"
#include "../app/defaults.h"
#include "../app/draw.h"
#include "../app/fetch.h"
#include "../app/net.h"
#include "../app/prefs.h"
#include "../app/theme.h"
#include "sendread.h"

/* dNeedLock | dNeedTime | dCtlEnable, every 6 ticks; events: mouseDown keyDown autoKey update activate */
__asm__(
	"	.section .rsrcheader,\"ax\",@progbits\n"
	"	.globl	da_header\n"
	"da_header:\n"
	"	.short	0x6400\n"
	"	.short	6\n"
	"	.short	0x016A\n"
	"	.short	0\n"
	"	.short	da_open - da_header\n"
	"	.short	da_done - da_header\n"
	"	.short	da_control - da_header\n"
	"	.short	da_done - da_header\n"
	"	.short	da_close - da_header\n"
	"	.byte	14\n"
	"	.byte	0\n"
	"	.ascii	\"Shiori Search\"\n"
	"	.align	2\n"
	/* Open and Close: immediate, a plain rts */
	"da_open:\n"
	"	movem.l	%a0-%a1,-(%sp)\n"
	"	move.l	%a1,-(%sp)\n"
	"	move.l	%a0,-(%sp)\n"
	"	bsr.w	DAOpen\n"
	"	addq.l	#8,%sp\n"
	"	movem.l	(%sp)+,%a0-%a1\n"
	"	rts\n"
	"da_close:\n"
	"	movem.l	%a0-%a1,-(%sp)\n"
	"	move.l	%a1,-(%sp)\n"
	"	move.l	%a0,-(%sp)\n"
	"	bsr.w	DAClose\n"
	"	addq.l	#8,%sp\n"
	"	movem.l	(%sp)+,%a0-%a1\n"
	"	rts\n"
	/* Control: through IODone unless the call was immediate (ioTrap bit 9) */
	"da_control:\n"
	"	movem.l	%a0-%a1,-(%sp)\n"
	"	move.l	%a1,-(%sp)\n"
	"	move.l	%a0,-(%sp)\n"
	"	bsr.w	DAControl\n"
	"	addq.l	#8,%sp\n"
	"	movem.l	(%sp)+,%a0-%a1\n"
	"da_iodone:\n"
	"	move.w	6(%a0),%d1\n"
	"	btst	#9,%d1\n"
	"	bne.s	1f\n"
	"	move.l	0x8FC,-(%sp)\n"
	"1:	rts\n"
	"da_done:\n"
	"	moveq	#0,%d0\n"
	"	bra.s	da_iodone\n"
	"	.text\n");

/* Elf2Mac wants an entry point; the Device Manager uses the header instead
   (the link names it with --undefined=da_header, so -gc-sections keeps it). */
void _start(void)
{
}

/* The desk accessory control calls (Inside Macintosh I-445). */
enum { accEvent_ = 64, accRun_ = 65, accCursor_ = 66, accCut_ = 70, accCopy_ = 71, accPaste_ = 72, accClear_ = 73 };

#define ROWS 8
#define ROW_H 28
#define WIDTH 340
#define MARGIN 8
#define FIELD_H 16
#define STATUS_H 16
#define TYPED_MAX 199
#define MAX_REPLY (64L * 1024L)
#define NOTE_ROWS 3

enum { STAGE_IDLE, STAGE_NOTES, STAGE_PAGES };

typedef struct DARow {
	char kind;              /* ROW_NOTE or ROW_PAGE */
	char title[100];        /* Mac Roman */
	char place[64];         /* Mac Roman: the host, or a note's folder */
	char url[256];          /* as the server sent it */
	char path[160];         /* a note's path in Kura's default vault */
} DARow;

typedef struct DA {
	WindowPtr w;
	TEHandle field;
	Rect fieldBox, listBox, statusBox;
	Prefs prefs;
	Fetch fetch;
	short stage;
	char query[TYPED_MAX * 3 + 1];  /* the words searched, UTF-8 */
	DARow rows[ROWS];
	short count, selected;
	long notes, pages;      /* the totals Kura and Hister gave */
	char problem[100];      /* the first stage's problem, kept for the end */
	char status[100];
	Boolean listFocus, active, haveAE, netOpen;
	unsigned long lastClick;
	short lastRow;
} DA;

static void Cat(char *s, const char *t)
{
	strncat(s, t, 99 - strlen(s));
}

static void CatNum(char *s, long n)
{
	Str255 p;
	char c[16];

	NumToString(n, p);
	memcpy(c, p + 1, p[0]);
	c[p[0]] = '\0';
	Cat(s, c);
}

/* What went wrong, briefly (the app's own messages need sprintf, too big for a DA). */
static void Problem(DA *d, const char *who, char *s)
{
	Fetch *f = &d->fetch;

	s[0] = '\0';
	if (f->state == FETCH_DONE) {
		if (f->head.status == 401) {
			Cat(s, "Set this Mac's room token in Shiori's Preferences.");
		} else {
			Cat(s, who);
			Cat(s, " answered ");
			CatNum(s, f->head.status);
			Cat(s, ".");
		}
	} else if (f->err == fetchBadAddress) {
		Cat(s, "Set the address in Shiori's Preferences.");
	} else if (f->err == fetchTooLong) {
		Cat(s, "That search is too long to send.");
	} else if (f->err == fetchCancelled) {
		Cat(s, "Stopped.");
	} else if (f->err == fetchTimedOut) {
		Cat(s, who);
		Cat(s, " didn't answer in time.");
	} else if (f->err == fetchTooLarge || f->err == fetchBadReply) {
		Cat(s, who);
		Cat(s, "'s answer couldn't be read.");
	} else if (f->err == ipBadAddr) {
		Cat(s, "MacTCP has no address: is this Mac on the network?");
	} else {
		Cat(s, "Can't reach ");
		Cat(s, who);
		Cat(s, " (");
		CatNum(s, f->err);
		Cat(s, ").");
	}
}

/* ---- drawing ---- */

static Rect RowRect(DA *d, short i)
{
	Rect r;
	SetRect(&r, d->listBox.left, (short) (d->listBox.top + i * ROW_H), d->listBox.right,
		(short) (d->listBox.top + (i + 1) * ROW_H));
	return r;
}

static void DrawRow(DA *d, short i)
{
	Rect r = RowRect(d, i);
	DARow *row = &d->rows[i];
	Boolean selected = i == d->selected;
	Boolean lit = selected && d->listFocus && d->active;
	Boolean tinted = lit && ThemeKind() != THEME_MONO;
	short width = (short) (r.right - r.left - 2 * MARGIN);
	char place[80];

	if (tinted)
		ThemeBack(ROLE_SELECTED_BG);
	EraseRect(&r);
	TextFont(kFontIDGeneva);
	TextSize(10);
	TextFace(bold);
	ThemeFore(ROLE_ACCENT);
	MoveTo((short) (r.left + MARGIN), (short) (r.top + 12));
	DrawFitted(row->title[0] ? row->title : row->url, width);
	TextFace(0);
	TextSize(9);
	ThemeFore(tinted ? ROLE_TEXT : row->kind == ROW_NOTE ? ROLE_NOTES : ROLE_SECONDARY);
	place[0] = '\0';
	if (row->kind == ROW_NOTE)
		strcpy(place, row->place[0] ? "Note \245 " : "Note");
	strncat(place, row->place, sizeof(place) - 1 - strlen(place));
	MoveTo((short) (r.left + MARGIN), (short) (r.top + 24));
	DrawFitted(place, width);
	ThemeNormal();
	if (lit && !tinted) {
		InvertRect(&r);
	} else if (selected && !lit) {
		InsetRect(&r, 1, 1);
		FrameRect(&r);
	}
}

static void DrawStatus(DA *d)
{
	Rect r = d->statusBox;

	EraseRect(&r);
	MoveTo(r.left, r.top);
	LineTo(r.right, r.top);
	TextFont(kFontIDGeneva);
	TextSize(9);
	ThemeFore(ROLE_SECONDARY);
	MoveTo((short) (r.left + MARGIN), (short) (r.bottom - 4));
	DrawFitted(d->status, (short) (r.right - r.left - 2 * MARGIN));
	ThemeNormal();
}

static void DrawField(DA *d)
{
	Rect f = d->fieldBox;

	InsetRect(&f, -3, -3);
	PenNormal();
	if (!d->listFocus && d->active)
		PenSize(2, 2);
	EraseRect(&f);
	FrameRect(&f);
	PenNormal();
	TEUpdate(&d->fieldBox, d->field);
}

static void Draw(DA *d)
{
	short i;
	Rect rest;

	EraseRect(&d->w->portRect);
	DrawField(d);
	for (i = 0; i < d->count; i++)
		DrawRow(d, i);
	rest = d->listBox;
	rest.top = (short) (d->listBox.top + d->count * ROW_H);
	EraseRect(&rest);
	DrawStatus(d);
}

static void SetStatus(DA *d, const char *s)
{
	strncpy(d->status, s, sizeof(d->status) - 1);
	d->status[sizeof(d->status) - 1] = '\0';
	DrawStatus(d);
}

static void Focus(DA *d, Boolean list)
{
	short i;

	if (d->listFocus == list)
		return;
	d->listFocus = list;
	if (list) {
		TEDeactivate(d->field);
		if (d->selected < 0 && d->count > 0)
			d->selected = 0;
	} else if (d->active) {
		TEActivate(d->field);
	}
	DrawField(d);
	for (i = 0; i < d->count; i++)
		if (i == d->selected)
			DrawRow(d, i);
}

static void Select(DA *d, short i)
{
	short old = d->selected;

	if (i < 0 || i >= d->count)
		return;
	d->selected = i;
	if (old >= 0 && old < d->count && old != i)
		DrawRow(d, old);
	DrawRow(d, i);
}

/* ---- searching ---- */

static void AddRow(void *ctx, const ShioriRow *r)
{
	DA *d = (DA *) ctx;
	DARow *row;
	char vault[48];

	if (d->count >= ROWS)
		return;
	if (r->kind == ROW_NOTE) {
		/* the default vault only: the address decides (Kura names the default too) */
		shiori_url_vault(r->url, vault, (long) sizeof(vault));
		if (vault[0] != '\0' || r->path[0] == '\0')
			return;
	} else if (r->kind != ROW_PAGE) {
		return;
	}
	row = &d->rows[d->count++];
	memset(row, 0, sizeof(*row));
	row->kind = r->kind;
	strncpy(row->title, r->title, sizeof(row->title) - 1);
	roman_from_utf8(row->title);
	strncpy(row->place, r->host, sizeof(row->place) - 1);
	roman_from_utf8(row->place);
	strncpy(row->url, r->url, sizeof(row->url) - 1);
	strncpy(row->path, r->path, sizeof(row->path) - 1);
}

static void Idle(DA *d, short ticks, DCtlPtr dce)
{
	dce->dCtlDelay = ticks;
}

static Boolean StartStage(DA *d, short stage)
{
	char target[700];
	int ok;
	Boolean kura = stage == STAGE_NOTES;

	if (kura)
		ok = shiori_kura_search_target(d->query, NOTE_ROWS, 0, "", target, (long) sizeof(target));
	else
		ok = shiori_hister_search_target(d->query, PILL_PAGES, ROWS - d->count, "", target, (long) sizeof(target));
	if (!ok)
		return false;
	d->stage = stage;
	FetchStart(&d->fetch, &d->prefs.config, kura ? d->prefs.config.kura : d->prefs.config.hister, target, MAX_REPLY, 0);
	return true;
}

static void ShowEnd(DA *d)
{
	char s[100];

	if (d->count == 0 && d->problem[0]) {
		SetStatus(d, d->problem);
		return;
	}
	if (d->count == 0) {
		SetStatus(d, "Nothing found.");
		return;
	}
	s[0] = '\0';
	if (d->prefs.config.kura[0]) {
		CatNum(s, d->notes);
		Cat(s, d->notes == 1 ? " note \245 " : " notes \245 ");
	}
	CatNum(s, d->pages);
	Cat(s, d->pages == 1 ? " page" : " pages");
	if (d->problem[0])
		Cat(s, " (Kura didn't answer)");
	SetStatus(d, s);
}

/* A stage's reply: its rows, then the next stage. */
static void StageDone(DA *d, DCtlPtr dce)
{
	ShioriPage page;
	const char *body;
	long len;
	short i, before = d->count;
	Boolean kura = d->stage == STAGE_NOTES;

	memset(&page, 0, sizeof(page));
	if (d->fetch.state == FETCH_DONE && d->fetch.head.status == 200) {
		body = FetchBody(&d->fetch, &len);
		if (kura)
			shiori_parse_kura(body, len, &page, AddRow, d);
		else
			shiori_parse_hister(body, len, &page, AddRow, d);
		if (kura)
			d->notes = page.total;
		else
			d->pages = page.total;
	} else if (!d->problem[0]) {
		Problem(d, kura ? "Kura" : "Hister", d->problem);
	}
	FetchReset(&d->fetch);
	SetPort(d->w);
	for (i = before; i < d->count; i++)
		DrawRow(d, i);
	if (kura && d->count < ROWS && StartStage(d, STAGE_PAGES))
		return;
	d->stage = STAGE_IDLE;
	Idle(d, 30, dce);
	ShowEnd(d);
}

static void Search(DA *d, DCtlPtr dce)
{
	char typed[TYPED_MAX + 1];
	CharsHandle text = TEGetText(d->field);
	short n = (**d->field).teLength;

	if (n > TYPED_MAX)
		n = TYPED_MAX;
	memcpy(typed, *text, (size_t) n);
	typed[n] = '\0';
	FetchReset(&d->fetch);
	d->stage = STAGE_IDLE;
	if (!shiori_trim(typed, typed, (long) sizeof(typed)) || !roman_to_utf8(typed, d->query, (long) sizeof(d->query))) {
		SetStatus(d, "Type words, then press Return.");
		return;
	}
	/* MacTCP opens on the first search, not with the window: without an address
	   its open waits a minute, and the whole Mac with it */
	if (!d->netOpen) {
		OSErr err = NetInit();
		if (err != noErr) {
			SetStatus(d, err == ipBadAddr ? "MacTCP has no address: is this Mac on the network?"
				: err <= ipBadLapErr && err >= ipBadAddr ? "MacTCP isn't set up: check its control panel."
				: "MacTCP isn't installed.");
			return;
		}
		d->netOpen = true;
	}
	d->count = 0;
	d->selected = -1;
	d->notes = d->pages = 0;
	d->problem[0] = '\0';
	Focus(d, false);
	Draw(d);
	SetStatus(d, "Searching\311");
	Idle(d, 1, dce);
	/* no Kura: pages only */
	if (!(d->prefs.config.kura[0] && StartStage(d, STAGE_NOTES)) && !StartStage(d, STAGE_PAGES)) {
		Idle(d, 30, dce);
		SetStatus(d, "Type words, then press Return.");
	}
}

static void Stop(DA *d, DCtlPtr dce)
{
	if (d->stage == STAGE_IDLE)
		return;
	FetchReset(&d->fetch);
	d->stage = STAGE_IDLE;
	Idle(d, 30, dce);
	SetStatus(d, "Stopped.");
}

static void Run(DA *d, DCtlPtr dce)
{
	GrafPtr old;

	if (d->stage == STAGE_IDLE)
		return;
	if (FetchPoll(&d->fetch))
		return;
	GetPort(&old);
	StageDone(d, dce);
	SetPort(old);
}

/* ---- opening a row ---- */

static void CopyLink(DA *d)
{
	char roman[256];

	if (d->selected < 0)
		return;
	strncpy(roman, d->rows[d->selected].url, sizeof(roman) - 1);
	roman[sizeof(roman) - 1] = '\0';
	roman_from_utf8(roman);
	ZeroScrap();
	PutScrap((long) strlen(roman), 'TEXT', roman);
	SetStatus(d, "Copied the link.");
}

static void OpenRow(DA *d)
{
	OSErr err;

	if (d->selected < 0 || d->selected >= d->count)
		return;
	if (!d->haveAE) {
		CopyLink(d);
		return;
	}
	{
		const DARow *row = &d->rows[d->selected];
		err = ShioriSendRead(row->kind == ROW_NOTE, row->url, row->title, row->place, row->path);
	}
	if (err == fnfErr)
		SetStatus(d, "Can't find Shiori on this Mac.");
	else if (err != noErr)
		SetStatus(d, "Shiori didn't open it.");
	else
		SetStatus(d, "Opened in Shiori.");
}

/* ---- events ---- */

static void Click(DA *d, EventRecord *e)
{
	Point p = e->where;
	Rect f = d->fieldBox;
	short i;

	GlobalToLocal(&p);
	InsetRect(&f, -3, -3);
	if (PtInRect(p, &f)) {
		Focus(d, false);
		TEClick(p, (e->modifiers & shiftKey) != 0, d->field);
		return;
	}
	if (!PtInRect(p, &d->listBox))
		return;
	i = (short) ((p.v - d->listBox.top) / ROW_H);
	if (i >= d->count)
		return;
	Focus(d, true);
	Select(d, i);
	/* DoubleTime is a low-memory global at a fixed address, which GCC takes for an empty array */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Warray-bounds"
	if (i == d->lastRow && (long) (e->when - d->lastClick) <= LMGetDoubleTime()) {
#pragma GCC diagnostic pop
		d->lastClick = 0;
		OpenRow(d);
		return;
	}
	d->lastRow = i;
	d->lastClick = e->when;
}

static void Key(DA *d, EventRecord *e, DCtlPtr dce)
{
	char c = (char) (e->message & charCodeMask);

	if (e->modifiers & cmdKey) {
		if (c == '.')
			Stop(d, dce);
		return;
	}
	switch (c) {
	case '\r':
	case 3:                                 /* Enter */
		if (d->listFocus && d->selected >= 0)
			OpenRow(d);
		else
			Search(d, dce);
		return;
	case '\t':
		if (d->count > 0)
			Focus(d, !d->listFocus);
		return;
	case 0x1E:                              /* up */
	case 0x1F:                              /* down */
		if (d->count == 0)
			return;
		if (!d->listFocus) {
			Focus(d, true);
			Select(d, 0);
		} else {
			Select(d, (short) (d->selected + (c == 0x1F ? 1 : -1)));
		}
		return;
	case 0x1B:                              /* Escape */
		Stop(d, dce);
		return;
	}
	Focus(d, false);
	if (c != 8 && (**d->field).teLength - ((**d->field).selEnd - (**d->field).selStart) >= TYPED_MAX)
		return;
	TEKey(c, d->field);
}

static void Activate(DA *d, Boolean active)
{
	d->active = active;
	if (active && !d->listFocus)
		TEActivate(d->field);
	else
		TEDeactivate(d->field);
	DrawField(d);
	if (d->selected >= 0)
		DrawRow(d, d->selected);
}

static void CopyField(DA *d)
{
	TEPtr te;
	short n;

	HLock((Handle) d->field);
	te = *d->field;
	n = (short) (te->selEnd - te->selStart);
	if (n > 0) {
		HLock(te->hText);
		ZeroScrap();
		PutScrap(n, 'TEXT', *te->hText + te->selStart);
		HUnlock(te->hText);
	}
	HUnlock((Handle) d->field);
}

static void Paste(DA *d)
{
	Handle h = NewHandle(0);
	long offset, n;
	short room;

	if (h == NULL)
		return;
	n = GetScrap(h, 'TEXT', &offset);
	room = (short) (TYPED_MAX - (**d->field).teLength + ((**d->field).selEnd - (**d->field).selStart));
	if (n > 0) {
		if (n > room)
			n = room;
		TEDelete(d->field);
		HLock(h);
		TEInsert(*h, n, d->field);
		HUnlock(h);
	}
	DisposeHandle(h);
}

static void Edit(DA *d, short code)
{
	if (code == accCopy_ && d->listFocus) {
		CopyLink(d);
		return;
	}
	Focus(d, false);
	switch (code) {
	case accCut_: CopyField(d); TEDelete(d->field); break;
	case accCopy_: CopyField(d); break;
	case accPaste_: Paste(d); break;
	case accClear_: TEDelete(d->field); break;
	}
}

static void TrackCursor(DA *d)
{
	Point p;
	Rect f = d->fieldBox;

	GetMouse(&p);
	InsetRect(&f, -3, -3);
	if (PtInRect(p, &f)) {
		CursHandle ibeam = GetCursor(iBeamCursor);
		if (ibeam != NULL)
			SetCursor(*ibeam);
	} else {
		InitCursor();
	}
}

/* ---- the driver ---- */

short DAOpen(ParmBlkPtr pb, DCtlPtr dce)
{
	Rect r, dest;
	DA *d;
	long response;
	GrafPtr old;
	short height = MARGIN + FIELD_H + 6 + MARGIN + ROWS * ROW_H + STATUS_H;

	RETRO68_RELOCATE();
	if (dce->dCtlWindow != NULL) {          /* already open: bring it forward */
		SelectWindow((WindowPtr) dce->dCtlWindow);
		return noErr;
	}
	d = (DA *) NewPtrClear(sizeof(DA));
	if (d == NULL)
		return memFullErr;
	GetPort(&old);
	SetRect(&r, 40, 50, 40 + WIDTH, (short) (50 + height));
	d->w = ThemeNewWindow(&r, "\pShiori Search", noGrowDocProc);
	if (d->w == NULL) {
		DisposePtr((Ptr) d);
		return memFullErr;
	}
	((WindowPeek) d->w)->windowKind = dce->dCtlRefNum;
	SetPort(d->w);
	TextFont(systemFont);
	TextSize(12);
	SetRect(&d->fieldBox, MARGIN + 3, MARGIN + 3, WIDTH - MARGIN - 3, MARGIN + 3 + FIELD_H);
	dest = d->fieldBox;
	dest.right = 2000;                      /* one line that scrolls sideways */
	d->field = TENew(&dest, &d->fieldBox);
	SetRect(&d->listBox, 0, (short) (d->fieldBox.bottom + 3 + MARGIN), WIDTH, (short) (height - STATUS_H));
	SetRect(&d->statusBox, 0, (short) (height - STATUS_H), WIDTH, height);
	d->selected = d->lastRow = -1;
	d->active = true;

	memset(&d->prefs, 0, sizeof(d->prefs));
	strcpy(d->prefs.config.hister, SHIORI_DEFAULT_HISTER);
	strcpy(d->prefs.config.kura, SHIORI_DEFAULT_KURA);
	shiori_checked_room_token(SHIORI_DEFAULT_TOKEN, d->prefs.config.roomToken, (long) sizeof(d->prefs.config.roomToken));
	if (!PrefsLoad(&d->prefs) && SHIORI_DEFAULT_TOKEN[0] == '\0')
		strcpy(d->status, "Open Shiori first, to set up Hister's address.");
	else
		strcpy(d->status, "Type, then Return: your notes and pages.");
	FetchInit(&d->fetch);
	d->haveAE = NGetTrapAddress(_Gestalt, kToolboxTrapType) != NGetTrapAddress(_Unimplemented, kToolboxTrapType)
		&& Gestalt(gestaltAppleEventsAttr, &response) == noErr && (response & 1);
	TEActivate(d->field);
	dce->dCtlStorage = (Handle) d;
	dce->dCtlWindow = (WindowPtr) d->w;
	dce->dCtlDelay = 30;
	SetPort(old);
	return noErr;
}

short DAClose(ParmBlkPtr pb, DCtlPtr dce)
{
	DA *d = (DA *) dce->dCtlStorage;

	RETRO68_RELOCATE();
	if (d != NULL) {
		FetchReset(&d->fetch);
		if (d->field != NULL)
			TEDispose(d->field);
		DisposeWindow(d->w);
		DisposePtr((Ptr) d);
	}
	dce->dCtlStorage = NULL;
	dce->dCtlWindow = NULL;
	return noErr;
}

short DAControl(ParmBlkPtr pb, DCtlPtr dce)
{
	CntrlParam *cp = (CntrlParam *) pb;
	DA *d = (DA *) dce->dCtlStorage;
	GrafPtr old;
	EventRecord *e;

	RETRO68_RELOCATE();
	if (d == NULL)
		return noErr;
	GetPort(&old);
	SetPort(d->w);
	switch (cp->csCode) {
	case accEvent_:
		memcpy(&e, cp->csParam, sizeof(e));     /* csParam holds the event's address */
		switch (e->what) {
		case updateEvt:
			BeginUpdate(d->w);
			Draw(d);
			EndUpdate(d->w);
			break;
		case activateEvt:
			Activate(d, (e->modifiers & activeFlag) != 0);
			break;
		case mouseDown:
			Click(d, e);
			break;
		case keyDown:
		case autoKey:
			Key(d, e, dce);
			break;
		}
		break;
	case accRun_:
		if (d->active && !d->listFocus)
			TEIdle(d->field);
		Run(d, dce);
		break;
	case accCursor_:
		TrackCursor(d);
		break;
	case accCut_:
	case accCopy_:
	case accPaste_:
	case accClear_:
		Edit(d, cp->csCode);
		break;
	}
	SetPort(old);
	return noErr;
}
