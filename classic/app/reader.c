/* reader.c: see reader.h. */
#include <Dialogs.h>
#include <Fonts.h>
#include <Memory.h>
#include <TextEdit.h>
#include <ToolUtils.h>
#include <stdio.h>
#include <string.h>

#include "../core/json.h"
#include "../core/notetext.h"
#include "../core/roman.h"
#include "draw.h"
#include "fetch.h"
#include "reader.h"

#define MAX_READERS 3
#define MAX_REPLY (192L * 1024L)
#define HEAD_H 34                       /* title and place */
#define STATUS_H 15
#define MARGIN 10
#define MAX_RUNS 3000
#define HREF_CAP (16L * 1024L)
#define FIND_DIALOG 129

enum { kReturnKey = 0x0D, kEnterKey = 0x03, kUp = 0x1E, kDown = 0x1F, kHome = 0x01, kEnd = 0x04,
	kPageUp = 0x0B, kPageDown = 0x0C, kSpace = 0x20 };

typedef struct TextLine {
	long start, end;        /* into the text */
	short height, ascent;
	short indent;
} TextLine;

typedef struct Reader {
	WindowPtr win;
	Fetch fetch;            /* stays put: the reader is a non-relocatable block */
	Boolean loading;
	char kind;              /* LROW_NOTE or LROW_PAGE */
	char title[100];        /* Mac Roman */
	char place[64];
	char url[256];          /* the note's or page's own address (UTF-8) */
	Handle text;            /* Mac Roman */
	long textLen;
	Handle runs;            /* NoteRun[runCount] */
	int runCount;
	Handle hrefs;
	Handle lines;           /* TextLine[lineCount] */
	long lineCount;
	long top;               /* the first line shown */
	ControlHandle bar;
	Rect textRect;
	char status[200];
	char link[256];         /* the last link clicked (UTF-8), for Copy Link */
	long foundStart, foundEnd;
	Boolean active;
} Reader;

static Reader *gReaders[MAX_READERS];
static ShioriConfig gConfig;
static char gFind[64];                  /* the last Find's text (Mac Roman) */
static Reader *gTracking;
static short gTextSize = 12;

static Reader *Find(WindowPtr w)
{
	int i;
	for (i = 0; i < MAX_READERS; i++)
		if (gReaders[i] != NULL && gReaders[i]->win == w)
			return gReaders[i];
	return NULL;
}

Boolean IsReaderWindow(WindowPtr w)
{
	return w != NULL && Find(w) != NULL;
}

/* -- styles ---------------------------------------------------------------------------------- */

static void UseStyle(unsigned char style)
{
	Style face = 0;

	if (style & STYLE_CODE) {
		TextFont(kFontIDMonaco);
		TextSize(gTextSize >= 14 ? 12 : 9);
	} else {
		TextFont(kFontIDGeneva);
		TextSize((short) ((style & STYLE_HEADING) ? gTextSize + 2 : gTextSize));
	}
	if (style & (STYLE_BOLD | STYLE_HEADING | STYLE_SUBHEADING))
		face |= bold;
	if (style & (STYLE_ITALIC | STYLE_QUOTE))
		face |= italic;
	if (style & STYLE_LINK)
		face |= underline;
	TextFace(face);
}

static NoteRun *Runs(Reader *r)
{
	return (NoteRun *) *r->runs;
}

/* The run holding text offset at, from a starting guess. */
static int RunAt(Reader *r, long at, int from)
{
	int i = from < 0 ? 0 : from;
	NoteRun *runs = Runs(r);

	while (i + 1 < r->runCount && runs[i + 1].offset <= at)
		i++;
	while (i > 0 && runs[i].offset > at)
		i--;
	return i;
}

/* Width of text [start, end) in its runs' styles. */
static short SpanWidth(Reader *r, long start, long end, int *runHint)
{
	long w = 0, at = start;
	int i = RunAt(r, start, *runHint);
	NoteRun *runs;
	char *text = *r->text;

	while (at < end) {
		long stop = end;
		runs = Runs(r);
		if (i + 1 < r->runCount && runs[i + 1].offset < stop)
			stop = runs[i + 1].offset;
		UseStyle(runs[i].style);
		w += TextWidth(text, (short) at, (short) (stop - at));
		at = stop;
		if (at < end)
			i++;
	}
	*runHint = i;
	return (short) (w > 32000 ? 32000 : w);
}

/* -- layout ----------------------------------------------------------------------------------- */

static Boolean AddLine(Reader *r, long start, long end, short indent)
{
	TextLine line;
	int i;
	short asc = 0, desc = 0;
	FontInfo fi;
	NoteRun *runs;

	if (GetHandleSize(r->lines) < (r->lineCount + 1) * (long) sizeof(TextLine)) {
		SetHandleSize(r->lines, (r->lineCount + 64) * (long) sizeof(TextLine));
		if (MemError() != noErr)
			return false;
	}
	/* the line's height: the tallest style on it */
	i = RunAt(r, start, 0);
	do {
		runs = Runs(r);
		UseStyle(runs[i].style);
		GetFontInfo(&fi);
		if (fi.ascent > asc)
			asc = fi.ascent;
		if (fi.descent + fi.leading > desc)
			desc = (short) (fi.descent + fi.leading);
		i++;
	} while (i < r->runCount && Runs(r)[i].offset < end);
	if (start == end) {                 /* an empty line: half a body line */
		UseStyle(0);
		GetFontInfo(&fi);
		asc = (short) (fi.ascent / 2 + 1);
		desc = (short) (fi.descent);
	}
	line.start = start;
	line.end = end;
	line.ascent = asc;
	line.height = (short) (asc + desc + 1);
	line.indent = indent;
	((TextLine *) *r->lines)[r->lineCount++] = line;
	return true;
}

/* Wraps the text to the window's width: words where they fit, a long word cut. */
static void Layout(Reader *r)
{
	short width = (short) (r->textRect.right - r->textRect.left - 2 * MARGIN);
	long at = 0, len = r->textLen;
	int hint = 0;
	char *text;

	r->lineCount = 0;
	if (r->text == NULL)
		return;
	HLock(r->text);
	text = *r->text;
	while (at <= len) {
		long para = at, paraEnd = at;
		short indent;
		while (paraEnd < len && text[paraEnd] != '\n')
			paraEnd++;
		indent = (short) ((Runs(r)[RunAt(r, para, hint)].style & STYLE_QUOTE) ? 14 : 0);
		if (paraEnd == para) {
			if (!AddLine(r, para, para, 0))
				break;
		}
		while (para < paraEnd) {
			long lineEnd = para, lastBreak = -1, k;
			/* the longest run of words from para that fits */
			for (k = para; k <= paraEnd; k++) {
				if (k == paraEnd || text[k] == ' ') {
					if (SpanWidth(r, para, k, &hint) <= width - indent)
						lastBreak = k;
					else
						break;
				}
			}
			if (lastBreak > para) {
				lineEnd = lastBreak;
			} else {
				/* one word wider than the line: as many characters as fit */
				lineEnd = para + 1;
				while (lineEnd < paraEnd && SpanWidth(r, para, lineEnd + 1, &hint) <= width - indent)
					lineEnd++;
			}
			if (!AddLine(r, para, lineEnd, indent))
				break;
			para = lineEnd;
			while (para < paraEnd && text[para] == ' ')
				para++;
		}
		at = paraEnd + 1;
	}
	HUnlock(r->text);
}

/* -- drawing ----------------------------------------------------------------------------------- */

static short VisibleLines(Reader *r, long from)
{
	short h = 0, n = 0, view = (short) (r->textRect.bottom - r->textRect.top);
	TextLine *lines = (TextLine *) *r->lines;

	while (from + n < r->lineCount && h + lines[from + n].height <= view) {
		h += lines[from + n].height;
		n++;
	}
	return n;
}

static void DrawLine(Reader *r, long index, short y)
{
	TextLine line = ((TextLine *) *r->lines)[index];
	long at = line.start;
	int i = RunAt(r, at, 0);
	short x = (short) (r->textRect.left + MARGIN + line.indent);
	char *text = *r->text;

	MoveTo(x, (short) (y + line.ascent));
	while (at < line.end) {
		long stop = line.end;
		NoteRun run = Runs(r)[i];
		if (i + 1 < r->runCount && Runs(r)[i + 1].offset < stop)
			stop = Runs(r)[i + 1].offset;
		UseStyle(run.style);
		DrawText(text, (short) at, (short) (stop - at));
		at = stop;
		i++;
	}
	if ((Runs(r)[RunAt(r, line.start, 0)].style & STYLE_QUOTE) && line.indent > 0) {
		/* a quote's bar */
		PenNormal();
		MoveTo((short) (r->textRect.left + MARGIN + 3), y);
		LineTo((short) (r->textRect.left + MARGIN + 3), (short) (y + line.height - 1));
	}
	/* a Find match on this line */
	if (r->foundEnd > r->foundStart && r->foundStart < line.end && r->foundEnd > line.start) {
		long s = r->foundStart > line.start ? r->foundStart : line.start;
		long e = r->foundEnd < line.end ? r->foundEnd : line.end;
		int hint = 0;
		Rect hit;
		short left = (short) (x + (s > line.start ? SpanWidth(r, line.start, s, &hint) : 0));
		short right = (short) (left + SpanWidth(r, s, e, &hint));
		SetRect(&hit, left, y, right, (short) (y + line.height));
		InvertRect(&hit);
	}
	TextFace(0);
}

static void DrawText_(Reader *r)
{
	RgnHandle clip = NewRgn();
	short y = r->textRect.top;
	long i;
	Rect rest;

	GetClip(clip);
	ClipRect(&r->textRect);
	EraseRect(&r->textRect);
	if (r->text != NULL) {
		HLock(r->text);
		for (i = r->top; i < r->lineCount && y < r->textRect.bottom; i++) {
			DrawLine(r, i, y);
			y += ((TextLine *) *r->lines)[i].height;
		}
		HUnlock(r->text);
	} else {
		TextFont(kFontIDGeneva);
		TextSize(12);
		MoveTo((short) (r->textRect.left + MARGIN), (short) (r->textRect.top + 20));
		DrawC(r->loading ? "Loading\311" : "");
	}
	(void) rest;
	SetClip(clip);
	DisposeRgn(clip);
}

static void DrawHead(Reader *r)
{
	Rect head = r->win->portRect;
	short width = (short) (head.right - head.left - 2 * MARGIN);

	head.bottom = HEAD_H;
	EraseRect(&head);
	TextFont(kFontIDGeneva);
	TextSize(12);
	TextFace(bold);
	MoveTo(MARGIN, 15);
	DrawFitted(r->title, width);
	TextFace(0);
	TextSize(9);
	MoveTo(MARGIN, 28);
	DrawFitted(r->place, width);
	MoveTo(0, (short) (HEAD_H - 1));
	LineTo(r->win->portRect.right, (short) (HEAD_H - 1));
}

static void DrawStatus(Reader *r)
{
	Rect s = r->win->portRect;

	s.top = (short) (s.bottom - STATUS_H + 1);
	s.right = (short) (s.right - 15);
	EraseRect(&s);
	TextFont(kFontIDGeneva);
	TextSize(9);
	TextFace(0);
	MoveTo(MARGIN, (short) (s.bottom - 4));
	DrawFitted(r->status, (short) (s.right - s.left - 2 * MARGIN));
	MoveTo(0, (short) (s.top - 1));
	LineTo((short) (r->win->portRect.right - 15), (short) (s.top - 1));
}

static void SetStatus(Reader *r, const char *s)
{
	GrafPtr old;

	strncpy(r->status, s, sizeof(r->status) - 1);
	r->status[sizeof(r->status) - 1] = '\0';
	GetPort(&old);
	SetPort(r->win);
	DrawStatus(r);
	SetPort(old);
}

static void DrawGrow(Reader *r)
{
	RgnHandle old = NewRgn();
	Rect box = r->win->portRect;

	GetClip(old);
	box.left = (short) (box.right - 15);
	box.top = (short) (box.bottom - 15);
	ClipRect(&box);
	DrawGrowIcon(r->win);
	SetClip(old);
	DisposeRgn(old);
}

static void SyncBar(Reader *r)
{
	long max = r->lineCount - VisibleLines(r, r->lineCount > 0 ? r->lineCount - 1 : 0);
	/* the last screenful: count back from the end */
	{
		short h = 0, view = (short) (r->textRect.bottom - r->textRect.top);
		long i = r->lineCount;
		while (i > 0 && h + ((TextLine *) *r->lines)[i - 1].height <= view) {
			h += ((TextLine *) *r->lines)[i - 1].height;
			i--;
		}
		max = i;
	}
	if (max < 0)
		max = 0;
	if (max > 32000)
		max = 32000;
	if (r->top > max)
		r->top = max;
	SetControlMaximum(r->bar, (short) max);
	SetControlValue(r->bar, (short) r->top);
	HiliteControl(r->bar, (r->active && max > 0) ? 0 : 255);
}

static void Relayout(Reader *r)
{
	Rect port = r->win->portRect, bar;

	SetRect(&r->textRect, 0, HEAD_H, (short) (port.right - 15), (short) (port.bottom - STATUS_H));
	SetRect(&bar, (short) (port.right - 15), (short) (HEAD_H - 1), (short) (port.right + 1), (short) (port.bottom - 14));
	HideControl(r->bar);
	MoveControl(r->bar, bar.left, bar.top);
	SizeControl(r->bar, (short) (bar.right - bar.left), (short) (bar.bottom - bar.top));
	ShowControl(r->bar);
	Layout(r);
	SyncBar(r);
}

void ReaderUpdate(WindowPtr w)
{
	Reader *r = Find(w);
	GrafPtr old;

	if (r == NULL)
		return;
	GetPort(&old);
	SetPort(w);
	BeginUpdate(w);
	DrawHead(r);
	DrawText_(r);
	DrawStatus(r);
	DrawControls(w);
	DrawGrow(r);
	EndUpdate(w);
	SetPort(old);
}

static void ScrollTo(Reader *r, long top)
{
	if (top < 0)
		top = 0;
	r->top = top;
	SyncBar(r);
	SetPort(r->win);
	DrawText_(r);
}

/* -- loading ----------------------------------------------------------------------------------- */

static void Loaded(Reader *r)
{
	long len, rawLen = 0, htmlLen;
	const char *body, *raw = NULL;
	Handle html = NULL;
	NoteText t;

	r->loading = false;
	if (r->fetch.state != FETCH_DONE || r->fetch.head.status != 200) {
		char problem[160];
		FetchProblem(&r->fetch, r->kind == LROW_NOTE ? "Kura" : "Hister", problem, (long) sizeof(problem));
		FetchReset(&r->fetch);
		SetStatus(r, problem);
		InvalRect(&r->textRect);
		return;
	}
	body = FetchBody(&r->fetch, &len);
	if (!shiori_json_member(body, len, r->kind == LROW_NOTE ? "html" : "content", &raw, &rawLen)) {
		FetchReset(&r->fetch);
		SetStatus(r, r->kind == LROW_NOTE ? "Kura's answer had no note." : "Hister has no readable copy of this page.");
		InvalRect(&r->textRect);
		return;
	}
	/* the title (and a note's folder) as the reply has them */
	{
		const char *field;
		long fieldLen;
		char buf[200];
		if (shiori_json_member(body, len, "title", &field, &fieldLen) && fieldLen > 0) {
			json_decode(field, fieldLen, buf, (long) sizeof(buf));
			roman_from_utf8(buf);
			if (buf[0]) {
				unsigned char wt[64];
				size_t n = strlen(buf) > 63 ? 63 : strlen(buf);
				strncpy(r->title, buf, sizeof(r->title) - 1);
				wt[0] = (unsigned char) n;
				memcpy(wt + 1, buf, n);
				SetWTitle(r->win, wt);
			}
		}
		if (r->kind == LROW_NOTE && shiori_json_member(body, len, "path", &field, &fieldLen) && fieldLen > 0) {
			char *slash;
			json_decode(field, fieldLen, buf, (long) sizeof(buf));
			slash = strrchr(buf, '/');
			if (slash != NULL) {
				*slash = '\0';
				roman_from_utf8(buf);
				strncpy(r->place, buf, sizeof(r->place) - 1);
			}
		}
		{
			Rect head = r->win->portRect;
			head.bottom = HEAD_H;
			InvalRect(&head);
		}
	}
	/* the HTML on its own, then the reply goes, before the text is made */
	html = NewHandle(rawLen + 1);
	if (html == NULL) {
		FetchReset(&r->fetch);
		SetStatus(r, "Not enough memory to read this.");
		return;
	}
	HLock(html);
	body = FetchBody(&r->fetch, &len);
	shiori_json_member(body, len, r->kind == LROW_NOTE ? "html" : "content", &raw, &rawLen);
	htmlLen = json_decode(raw, rawLen, *html, rawLen + 1);
	FetchReset(&r->fetch);

	r->text = NewHandle(htmlLen + 2048);
	r->runs = NewHandle((long) MAX_RUNS * (long) sizeof(NoteRun));
	r->hrefs = NewHandle(HREF_CAP);
	if (r->text == NULL || r->runs == NULL || r->hrefs == NULL) {
		DisposeHandle(html);
		SetStatus(r, "Not enough memory to read this.");
		return;
	}
	HLock(r->text);
	HLock(r->runs);
	HLock(r->hrefs);
	note_text_init(&t, *r->text, htmlLen + 2048, (NoteRun *) *r->runs, MAX_RUNS, *r->hrefs, HREF_CAP, 1);
	shiori_note_html_to_text(*html, htmlLen, &t);
	HUnlock(r->text);
	HUnlock(r->runs);
	HUnlock(r->hrefs);
	DisposeHandle(html);
	r->textLen = t.textLen;
	r->runCount = t.runCount;
	SetHandleSize(r->text, r->textLen + 1);
	SetHandleSize(r->runs, (long) r->runCount * (long) sizeof(NoteRun));
	SetHandleSize(r->hrefs, t.hrefLen > 0 ? t.hrefLen : 1);
	SetPort(r->win);
	Relayout(r);
	InvalRect(&r->textRect);
	SetStatus(r, t.truncated ? "Shown in part: too long for this Mac." : "");
}

Boolean ReaderPollAll(void)
{
	int i;
	Boolean busy = false;

	for (i = 0; i < MAX_READERS; i++) {
		Reader *r = gReaders[i];
		if (r == NULL || !r->loading)
			continue;
		if (FetchPoll(&r->fetch)) {
			busy = true;
			continue;
		}
		{
			GrafPtr old;
			GetPort(&old);
			SetPort(r->win);
			Loaded(r);
			SetPort(old);
		}
	}
	return busy;
}

static Boolean Start(Reader *r, const char *path, const char *vault, const char *url)
{
	char target[700];
	int ok;

	if (r->kind == LROW_NOTE)
		ok = shiori_kura_note_target(path, vault, target, (long) sizeof(target));
	else
		ok = shiori_hister_preview_target(url, target, (long) sizeof(target));
	if (!ok)
		return false;
	FetchStart(&r->fetch, &gConfig, r->kind == LROW_NOTE ? gConfig.kura : gConfig.hister, target, MAX_REPLY, 0);
	r->loading = r->fetch.state != FETCH_FAILED;
	if (!r->loading) {
		char problem[160];
		FetchProblem(&r->fetch, r->kind == LROW_NOTE ? "Kura" : "Hister", problem, (long) sizeof(problem));
		strcpy(r->status, problem);
	} else {
		strcpy(r->status, "Loading\311");
	}
	return true;
}

Boolean ReaderOpen(const ShioriConfig *config, const ListRow *row)
{
	int slot;
	Reader *r;
	Rect bounds;
	unsigned char title[64];
	size_t n;

	gConfig = *config;
	for (slot = 0; slot < MAX_READERS && gReaders[slot] != NULL; slot++)
		;
	if (slot == MAX_READERS)
		return false;
	r = (Reader *) NewPtrClear(sizeof(Reader));
	if (r == NULL)
		return false;
	r->kind = row->kind == LROW_NOTE ? LROW_NOTE : LROW_PAGE;
	strcpy(r->title, row->title);
	strcpy(r->place, row->place);
	strncpy(r->url, row->url, sizeof(r->url) - 1);
	r->lines = NewHandle(0);
	SetRect(&bounds, (short) (16 + slot * 14), (short) (48 + slot * 14),
		(short) (qd.screenBits.bounds.right - 20 + slot * 4), (short) (qd.screenBits.bounds.bottom - 12));
	if (bounds.right > qd.screenBits.bounds.right - 4)
		bounds.right = (short) (qd.screenBits.bounds.right - 4);
	n = strlen(row->title);
	if (n > 63)
		n = 63;
	title[0] = (unsigned char) n;
	memcpy(title + 1, row->title, n);
	r->win = NewWindow(NULL, &bounds, title, true, 8 /* documentProc + zoom box */, (WindowPtr) -1L, true, 0);
	if (r->win == NULL || r->lines == NULL) {
		if (r->win)
			DisposeWindow(r->win);
		DisposePtr((Ptr) r);
		return false;
	}
	SetPort(r->win);
	r->bar = NewControl(r->win, &bounds, "\p", true, 0, 0, 0, scrollBarProc, 0);
	r->active = true;
	gReaders[slot] = r;
	Relayout(r);
	if (!Start(r, row->path, row->vault, row->url))
		strcpy(r->status, "Can't ask for this.");
	return true;
}

static void Dispose(Reader *r)
{
	int i;

	FetchReset(&r->fetch);
	if (r->text)
		DisposeHandle(r->text);
	if (r->runs)
		DisposeHandle(r->runs);
	if (r->hrefs)
		DisposeHandle(r->hrefs);
	if (r->lines)
		DisposeHandle(r->lines);
	DisposeWindow(r->win);
	for (i = 0; i < MAX_READERS; i++)
		if (gReaders[i] == r)
			gReaders[i] = NULL;
	DisposePtr((Ptr) r);
}

void ReaderClose(WindowPtr w)
{
	Reader *r = Find(w);
	if (r != NULL)
		Dispose(r);
}

void ReaderCloseAll(void)
{
	int i;
	for (i = 0; i < MAX_READERS; i++)
		if (gReaders[i] != NULL)
			Dispose(gReaders[i]);
}

void ReaderStop(WindowPtr w)
{
	Reader *r = Find(w);
	if (r != NULL && r->loading)
		FetchCancel(&r->fetch);
}

void ReaderActivate(WindowPtr w, Boolean active)
{
	Reader *r = Find(w);

	if (r == NULL)
		return;
	r->active = active;
	SetPort(w);
	SyncBar(r);
	DrawGrow(r);
}

/* -- clicks and keys ------------------------------------------------------------------------------ */

static pascal void TrackBar(ControlHandle bar, short part)
{
	Reader *r = gTracking;
	long step = 0, page;

	if (r == NULL || part == 0)
		return;
	page = VisibleLines(r, r->top) - 1;
	if (page < 1)
		page = 1;
	switch (part) {
	case inUpButton: step = -1; break;
	case inDownButton: step = 1; break;
	case inPageUp: step = -page; break;
	case inPageDown: step = page; break;
	}
	(void) bar;
	ScrollTo(r, r->top + step);
}

/* The text offset under a point, or -1. */
static long OffsetAt(Reader *r, Point p)
{
	short y = r->textRect.top, x;
	long i, at;
	int hint = 0;
	TextLine line;

	for (i = r->top; i < r->lineCount; i++) {
		line = ((TextLine *) *r->lines)[i];
		if (p.v < y + line.height)
			break;
		y += line.height;
	}
	if (i >= r->lineCount)
		return -1;
	x = (short) (r->textRect.left + MARGIN + line.indent);
	if (p.h < x)
		return -1;
	for (at = line.start; at < line.end; at++)
		if (x + SpanWidth(r, line.start, at + 1, &hint) > p.h)
			return at;
	return -1;
}

void ReaderClick(WindowPtr w, EventRecord *e)
{
	Reader *r = Find(w);
	Point p = e->where;
	ControlHandle hit;
	short part;

	if (r == NULL)
		return;
	SetPort(w);
	GlobalToLocal(&p);
	part = FindControl(p, w, &hit);
	if (hit == r->bar && part != 0) {
		if (part == inThumb) {
			TrackControl(hit, p, NULL);
			ScrollTo(r, GetControlValue(hit));
		} else {
			gTracking = r;
			TrackControl(hit, p, NewControlActionUPP(TrackBar));
			gTracking = NULL;
		}
		return;
	}
	if (PtInRect(p, &r->textRect) && r->text != NULL) {
		long at;
		const char *href;
		NoteText t;
		HLock(r->text);
		at = OffsetAt(r, p);
		HUnlock(r->text);
		if (at < 0)
			return;
		/* the links' table, as notetext made it */
		memset(&t, 0, sizeof(t));
		HLock(r->runs);
		HLock(r->hrefs);
		t.runs = (NoteRun *) *r->runs;
		t.runCount = r->runCount;
		t.hrefs = *r->hrefs;
		t.textLen = r->textLen;
		href = note_link_at(&t, at);
		if (*href) {
			char path[200], vault[48], s[200];
			strncpy(r->link, href, sizeof(r->link) - 1);
			r->link[sizeof(r->link) - 1] = '\0';
			HUnlock(r->runs);
			HUnlock(r->hrefs);
			if (r->kind == LROW_NOTE && shiori_note_link(r->link, r->url, path, (long) sizeof(path), vault,
					(long) sizeof(vault))) {
				ListRow row;
				memset(&row, 0, sizeof(row));
				row.kind = LROW_NOTE;
				{
					/* the title until the note says: its name, without .md */
					char *slash = strrchr(path, '/');
					strncpy(row.title, slash ? slash + 1 : path, sizeof(row.title) - 1);
					if (strlen(row.title) > 3)
						row.title[strlen(row.title) - 3] = '\0';
					roman_from_utf8(row.title);
				}
				strcpy(row.place, "Notes");
				strncpy(row.url, r->link, sizeof(row.url) - 1);
				strcpy(row.path, path);
				strcpy(row.vault, vault);
				if (!ReaderOpen(&gConfig, &row))
					SetStatus(r, "Three readers are open: close one first.");
				return;
			}
			sprintf(s, "Link: %.150s (Copy Link copies it)", r->link);
			roman_from_utf8(s);
			SetStatus(r, s);
			return;
		}
		HUnlock(r->runs);
		HUnlock(r->hrefs);
	}
}

void ReaderKey(WindowPtr w, EventRecord *e)
{
	Reader *r = Find(w);
	char c = (char) (e->message & charCodeMask);
	long page;

	if (r == NULL)
		return;
	page = VisibleLines(r, r->top) - 1;
	if (page < 1)
		page = 1;
	switch (c) {
	case kUp: ScrollTo(r, r->top - 1); break;
	case kDown: ScrollTo(r, r->top + 1); break;
	case kPageUp: ScrollTo(r, r->top - page); break;
	case kPageDown: case kSpace: ScrollTo(r, r->top + page); break;
	case kHome: ScrollTo(r, 0); break;
	case kEnd: ScrollTo(r, r->lineCount); break;
	}
}

void ReaderGrow(WindowPtr w, Point where)
{
	Reader *r = Find(w);
	Rect limits;
	long size;

	if (r == NULL)
		return;
	SetRect(&limits, 240, 120, qd.screenBits.bounds.right, qd.screenBits.bounds.bottom);
	size = GrowWindow(w, where, &limits);
	if (size == 0)
		return;
	SetPort(w);
	SizeWindow(w, LoWord(size), HiWord(size), true);
	Relayout(r);
	InvalRect(&w->portRect);
}

void ReaderZoom(WindowPtr w, Point where, short part)
{
	Reader *r = Find(w);

	if (r == NULL)
		return;
	SetPort(w);
	if (!TrackBox(w, where, part))
		return;
	EraseRect(&w->portRect);
	ZoomWindow(w, part, true);
	Relayout(r);
	InvalRect(&w->portRect);
}

/* -- Find --------------------------------------------------------------------------------------------- */

static int Fold(int c)
{
	c &= 0xFF;
	if (c >= 'A' && c <= 'Z')
		return c + 32;
	switch (c) {                        /* Mac Roman's accented capitals */
	case 0x80: return 0x8A; case 0x81: return 0x8C; case 0x82: return 0x8D; case 0x83: return 0x8E;
	case 0x84: return 0x96; case 0x85: return 0x9A; case 0x86: return 0x9F;
	}
	return c;
}

static Boolean FindFrom(Reader *r, long from)
{
	long n = (long) strlen(gFind), i, k;
	char *text;

	if (n == 0 || r->text == NULL)
		return false;
	HLock(r->text);
	text = *r->text;
	for (i = from; i + n <= r->textLen; i++) {
		for (k = 0; k < n && Fold(text[i + k]) == Fold(gFind[k]); k++)
			;
		if (k == n)
			break;
	}
	HUnlock(r->text);
	if (i + n > r->textLen)
		return false;
	r->foundStart = i;
	r->foundEnd = i + n;
	/* show its line */
	for (k = 0; k < r->lineCount && ((TextLine *) *r->lines)[k].end <= i; k++)
		;
	if (k < r->top || k >= r->top + VisibleLines(r, r->top))
		r->top = k > 2 ? k - 2 : 0;
	ScrollTo(r, r->top);
	return true;
}

void ReaderFind(WindowPtr w)
{
	Reader *r = Find(w);
	DialogPtr d;
	short item = 0, type;
	Handle h;
	Rect box;
	unsigned char text[256];

	if (r == NULL)
		return;
	d = GetNewDialog(FIND_DIALOG, NULL, (WindowPtr) -1L);
	if (d == NULL)
		return;
	GetDialogItem(d, 4, &type, &h, &box);
	text[0] = (unsigned char) strlen(gFind);
	memcpy(text + 1, gFind, text[0]);
	SetDialogItemText(h, text);
	SelectDialogItemText(d, 4, 0, 32767);
	while (item != 1 && item != 2)
		ModalDialog(NULL, &item);
	if (item == 1) {
		GetDialogItemText(h, text);
		if (text[0] > sizeof(gFind) - 1)
			text[0] = sizeof(gFind) - 1;
		memcpy(gFind, text + 1, text[0]);
		gFind[text[0]] = '\0';
	}
	DisposeDialog(d);
	SetPort(w);
	if (item == 1 && gFind[0]) {
		if (!FindFrom(r, 0))
			SetStatus(r, "Not found.");
		else
			SetStatus(r, "");
	}
}

void ReaderFindAgain(WindowPtr w)
{
	Reader *r = Find(w);

	if (r == NULL || !gFind[0])
		return;
	SetPort(w);
	if (!FindFrom(r, r->foundEnd > 0 ? r->foundStart + 1 : 0))
		SetStatus(r, "No more.");
}

Boolean ReaderCanFindAgain(WindowPtr w)
{
	return Find(w) != NULL && gFind[0] != '\0';
}

void ReaderCopyLink(WindowPtr w)
{
	Reader *r = Find(w);
	char roman[256];

	if (r == NULL)
		return;
	strncpy(roman, r->link[0] ? r->link : r->url, sizeof(roman) - 1);
	roman[sizeof(roman) - 1] = '\0';
	roman_from_utf8(roman);
	ZeroScrap();
	PutScrap((long) strlen(roman), 'TEXT', roman);
	SetStatus(r, r->link[0] ? "Copied the link." : "Copied this page's address.");
}

void ReaderCopy(WindowPtr w)
{
	Reader *r = Find(w);

	if (r == NULL || r->text == NULL)
		return;
	ZeroScrap();
	HLock(r->text);
	PutScrap(r->textLen < 32000 ? r->textLen : 32000, 'TEXT', *r->text);
	HUnlock(r->text);
	SetStatus(r, r->textLen < 32000 ? "Copied the text." : "Copied the first 32,000 characters.");
}

void ReaderSetTextSize(short size)
{
	int i;

	gTextSize = size;
	for (i = 0; i < MAX_READERS; i++) {
		Reader *r = gReaders[i];
		if (r == NULL)
			continue;
		SetPort(r->win);
		Relayout(r);
		InvalRect(&r->win->portRect);
	}
}
