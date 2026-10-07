/* resultlist.c: see resultlist.h. */
#include <Fonts.h>
#include <Memory.h>
#include <Events.h>
#include <string.h>

#include "draw.h"
#include "resultlist.h"
#include "theme.h"

#define HEADER_H 18
#define RESULT_H 44
#define MORE_H 22
#define INSET 8

/* key codes beside the letters */
enum { kUp = 0x1E, kDown = 0x1F, kHome = 0x01, kEnd = 0x04, kPageUp = 0x0B, kPageDown = 0x0C };

static ResultList *gTracking;   /* the list whose bar is being tracked */

static short RowHeight(char kind)
{
	return kind == LROW_HEADER ? HEADER_H : kind == LROW_MORE ? MORE_H : RESULT_H;
}

static ListRow *Rows(const ResultList *l)
{
	return (ListRow *) *l->rows;
}

static short RowTop(const ResultList *l, short i)
{
	short y = 0, k;
	for (k = 0; k < i; k++)
		y += RowHeight(Rows(l)[k].kind);
	return y;
}

static short TotalHeight(const ResultList *l)
{
	return RowTop(l, l->count);
}

static short ViewHeight(const ResultList *l)
{
	return (short) (l->frame.bottom - l->frame.top);
}

static void BarRect(const ResultList *l, Rect *r)
{
	SetRect(r, l->frame.right - 1, l->frame.top - 1, l->frame.right + 15, l->frame.bottom + 1);
}

void ListInit(ResultList *l, WindowPtr w, const Rect *frame, short cap)
{
	Rect r;

	memset(l, 0, sizeof(*l));
	l->window = w;
	l->frame = *frame;
	l->cap = cap;
	l->selected = -1;
	l->rows = NewHandle(0);
	BarRect(l, &r);
	l->bar = NewControl(w, &r, "\p", true, 0, 0, 0, scrollBarProc, 0);
}

void ListSetFrame(ResultList *l, const Rect *frame)
{
	Rect r;

	l->frame = *frame;
	BarRect(l, &r);
	HideControl(l->bar);
	MoveControl(l->bar, r.left, r.top);
	SizeControl(l->bar, (short) (r.right - r.left), (short) (r.bottom - r.top));
	ShowControl(l->bar);
	ListChanged(l);
}

void ListClear(ResultList *l)
{
	SetHandleSize(l->rows, 0);
	l->count = 0;
	l->selected = -1;
	l->top = 0;
}

ListRow *ListAppend(ResultList *l, char kind)
{
	ListRow *row;

	if (l->count >= l->cap)
		return NULL;
	SetHandleSize(l->rows, (long) (l->count + 1) * (long) sizeof(ListRow));
	if (MemError() != noErr)
		return NULL;
	row = Rows(l) + l->count;
	memset(row, 0, sizeof(*row));
	row->kind = kind;
	l->count++;
	return row;
}

void ListDropLast(ResultList *l)
{
	if (l->count == 0)
		return;
	l->count--;
	if (l->selected >= l->count)
		l->selected = (short) (l->count - 1);
	SetHandleSize(l->rows, (long) l->count * (long) sizeof(ListRow));
}

Boolean ListGet(const ResultList *l, short i, ListRow *out)
{
	if (i < 0 || i >= l->count)
		return false;
	*out = Rows(l)[i];
	return true;
}

short ListCount(const ResultList *l)
{
	return l->count;
}

short ListSelected(const ResultList *l)
{
	return l->selected;
}

static void Clamp(ResultList *l)
{
	short max = (short) (TotalHeight(l) - ViewHeight(l));
	if (max < 0)
		max = 0;
	if (l->top > max)
		l->top = max;
	if (l->top < 0)
		l->top = 0;
	SetControlMaximum(l->bar, max);
	SetControlValue(l->bar, l->top);
	HiliteControl(l->bar, (l->active && max > 0) ? 0 : 255);
}

void ListChanged(ResultList *l)
{
	GrafPtr old;

	Clamp(l);
	GetPort(&old);
	SetPort(l->window);
	InvalRect(&l->frame);
	SetPort(old);
}

static void DrawRow(const ResultList *l, const ListRow *row, short index, short y)
{
	Rect r;
	short width = (short) (l->frame.right - l->frame.left - 2 * INSET);
	short x = (short) (l->frame.left + INSET);
	Boolean selected = index == l->selected;
	Boolean tinted = selected && l->focused && l->active && ThemeKind() != THEME_MONO;

	SetRect(&r, l->frame.left, y, l->frame.right, (short) (y + RowHeight(row->kind)));
	if (tinted)
		ThemeBack(ROLE_SELECTED_BG);    /* inverting coloured text makes its complement: tint instead */
	EraseRect(&r);
	switch (row->kind) {
	case LROW_HEADER:
		TextFont(kFontIDGeneva);
		TextSize(9);
		TextFace(bold);
		ThemeFore(ROLE_SECONDARY);
		MoveTo(x, (short) (y + 13));
		DrawC(row->title);
		TextFace(0);
		MoveTo(x, (short) (y + HEADER_H - 2));
		PenPat(&qd.gray);
		LineTo((short) (l->frame.right - INSET), (short) (y + HEADER_H - 2));
		PenNormal();
		ThemeNormal();
		return;
	case LROW_MORE:
		TextFont(kFontIDGeneva);
		TextSize(10);
		ThemeFore(ROLE_ACCENT);
		MoveTo((short) (x + (width - TextWidth((Ptr) row->title, 0, (short) strlen(row->title))) / 2), (short) (y + 15));
		DrawC(row->title);
		ThemeNormal();
		break;
	default: {
		const char *tag = row->kind == LROW_NOTE ? "Note" : row->kind == LROW_CODE ? "Code" : NULL;
		short tagWidth = 0;
		TextFont(kFontIDGeneva);
		TextSize(9);
		if (tag != NULL) {
			Rect t;
			ThemeFore(tinted ? ROLE_TEXT : row->kind == LROW_NOTE ? ROLE_NOTES : ROLE_CODE);
			tagWidth = (short) (TextWidth((Ptr) tag, 0, (short) strlen(tag)) + 8);
			SetRect(&t, (short) (x + width - tagWidth), (short) (y + 4), (short) (x + width), (short) (y + 16));
			FrameRoundRect(&t, 6, 6);
			MoveTo((short) (t.left + 4), (short) (t.bottom - 3));
			DrawC(tag);
			tagWidth += 6;
		}
		TextSize(12);
		TextFace(bold);
		ThemeFore(ROLE_ACCENT);
		MoveTo(x, (short) (y + 14));
		DrawFitted(row->title, (short) (width - tagWidth));
		TextFace(0);
		TextSize(9);
		ThemeFore(tinted ? ROLE_TEXT : ROLE_SECONDARY);
		MoveTo(x, (short) (y + 26));
		DrawFitted(row->place, width);
		ThemeFore(ROLE_TEXT);
		MoveTo(x, (short) (y + 38));
		DrawSnippet(row->snippet, width);
		break;
	}
	}
	ThemeNormal();
	if (selected) {
		if (l->focused && l->active) {
			if (!tinted)
				InvertRect(&r);
		} else {
			InsetRect(&r, 1, 1);
			ThemeFore(ROLE_ACCENT);
			FrameRect(&r);
			ThemeNormal();
		}
	}
}

void ListDraw(ResultList *l)
{
	RgnHandle oldClip = NewRgn();
	short i, y;
	Rect r;

	GetClip(oldClip);
	ClipRect(&l->frame);
	y = (short) (l->frame.top - l->top);
	for (i = 0; i < l->count && y < l->frame.bottom; i++) {
		short h = RowHeight(Rows(l)[i].kind);
		if (y + h > l->frame.top) {
			ListRow row = Rows(l)[i];
			DrawRow(l, &row, i, y);
		}
		y += h;
	}
	if (y < l->frame.bottom) {
		SetRect(&r, l->frame.left, y, l->frame.right, l->frame.bottom);
		EraseRect(&r);
	}
	SetClip(oldClip);
	DisposeRgn(oldClip);
	Draw1Control(l->bar);
}

static void ScrollTo(ResultList *l, short top)
{
	short old = l->top, dy;
	RgnHandle update;

	l->top = top;
	Clamp(l);
	dy = (short) (old - l->top);
	if (dy == 0)
		return;
	if (dy > ViewHeight(l) || -dy > ViewHeight(l)) {
		ListDraw(l);
		return;
	}
	update = NewRgn();
	ScrollRect(&l->frame, 0, dy, update);
	{
		RgnHandle oldClip = NewRgn();
		GetClip(oldClip);
		SetClip(update);
		ListDraw(l);
		SetClip(oldClip);
		DisposeRgn(oldClip);
	}
	DisposeRgn(update);
}

static void Reveal(ResultList *l, short i)
{
	short y = RowTop(l, i), h = RowHeight(Rows(l)[i].kind);

	if (y < l->top)
		ScrollTo(l, y);
	else if (y + h > l->top + ViewHeight(l))
		ScrollTo(l, (short) (y + h - ViewHeight(l)));
}

static void Select(ResultList *l, short i)
{
	short old = l->selected;
	GrafPtr port;
	Rect r;

	if (i == old)
		return;
	l->selected = i;
	GetPort(&port);
	SetPort(l->window);
	if (old >= 0 && old < l->count) {
		short y = (short) (l->frame.top - l->top + RowTop(l, old));
		SetRect(&r, l->frame.left, y, l->frame.right, (short) (y + RowHeight(Rows(l)[old].kind)));
		InvalRect(&r);
	}
	if (i >= 0) {
		Reveal(l, i);
		{
			short y = (short) (l->frame.top - l->top + RowTop(l, i));
			SetRect(&r, l->frame.left, y, l->frame.right, (short) (y + RowHeight(Rows(l)[i].kind)));
			InvalRect(&r);
		}
	}
	SetPort(port);
}

static Boolean Selectable(const ResultList *l, short i)
{
	return i >= 0 && i < l->count && Rows(l)[i].kind != LROW_HEADER;
}

Boolean ListSelectFirst(ResultList *l)
{
	short i;
	for (i = 0; i < l->count; i++)
		if (Selectable(l, i)) {
			Select(l, i);
			return true;
		}
	return false;
}

static pascal void TrackBar(ControlHandle bar, short part)
{
	ResultList *l = gTracking;
	short step = 0, page;

	if (l == NULL || part == 0)
		return;
	page = (short) (ViewHeight(l) - RESULT_H / 2);
	switch (part) {
	case inUpButton: step = -RESULT_H / 2; break;
	case inDownButton: step = RESULT_H / 2; break;
	case inPageUp: step = (short) -page; break;
	case inPageDown: step = page; break;
	}
	(void) bar;
	ScrollTo(l, (short) (l->top + step));
}

Boolean ListClick(ResultList *l, Point where, Boolean doubleClick)
{
	ControlHandle hit;
	short part = FindControl(where, l->window, &hit);
	short i, y;

	if (hit == l->bar && part != 0) {
		if (part == inThumb) {
			TrackControl(hit, where, NULL);
			ScrollTo(l, GetControlValue(hit));
		} else {
			gTracking = l;
			TrackControl(hit, where, NewControlActionUPP(TrackBar));
			gTracking = NULL;
		}
		return false;
	}
	if (!PtInRect(where, &l->frame))
		return false;
	y = (short) (where.v - l->frame.top + l->top);
	for (i = 0; i < l->count; i++) {
		short h = RowHeight(Rows(l)[i].kind);
		if (y < h)
			break;
		y -= h;
	}
	if (!Selectable(l, i))
		return false;
	doubleClick = doubleClick && i == l->selected;
	Select(l, i);
	return doubleClick;
}

Boolean ListKey(ResultList *l, char key)
{
	short i = l->selected;

	switch (key) {
	case kUp:
		for (i = (short) (i - 1); i >= 0 && !Selectable(l, i); i--)
			;
		if (i >= 0)
			Select(l, i);
		return true;
	case kDown:
		for (i = (short) (i + 1); i < l->count && !Selectable(l, i); i++)
			;
		if (i < l->count)
			Select(l, i);
		return true;
	case kHome:
		ScrollTo(l, 0);
		return true;
	case kEnd:
		ScrollTo(l, TotalHeight(l));
		return true;
	case kPageUp:
		ScrollTo(l, (short) (l->top - ViewHeight(l)));
		return true;
	case kPageDown:
		ScrollTo(l, (short) (l->top + ViewHeight(l)));
		return true;
	}
	return false;
}

void ListActivate(ResultList *l, Boolean active)
{
	l->active = active;
	Clamp(l);
	ListChanged(l);
}

void ListFocus(ResultList *l, Boolean focused)
{
	l->focused = focused;
	ListChanged(l);
}
