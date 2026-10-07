/* draw.c: see draw.h. */
#include <Fonts.h>
#include <string.h>

#include "../core/results.h"
#include "draw.h"

#define ELLIPSIS ((char) 0xC9)

void DrawC(const char *s)
{
	DrawText((Ptr) s, 0, (short) strlen(s));
}

short FitLength(const char *s, short len, short maxWidth, Boolean *cut)
{
	short lo, hi, mid, ell = CharWidth(ELLIPSIS);

	*cut = false;
	if (TextWidth((Ptr) s, 0, len) <= maxWidth)
		return len;
	*cut = true;
	/* the longest prefix that fits with the ellipsis */
	lo = 0;
	hi = len;
	while (lo < hi) {
		mid = (short) ((lo + hi + 1) / 2);
		if (TextWidth((Ptr) s, 0, mid) + ell <= maxWidth)
			lo = mid;
		else
			hi = (short) (mid - 1);
	}
	while (lo > 0 && s[lo - 1] == ' ')
		lo--;
	return lo;
}

void DrawFitted(const char *s, short maxWidth)
{
	Boolean cut;
	short n = FitLength(s, (short) strlen(s), maxWidth, &cut);

	DrawText((Ptr) s, 0, n);
	if (cut)
		DrawChar(ELLIPSIS);
}

void DrawSnippet(const char *s, short maxWidth)
{
	short used = 0, ell;
	Style face = 0;
	const char *p = s;

	TextFace(0);
	ell = CharWidth(ELLIPSIS);
	while (*p) {
		const char *run = p;
		short n, w;
		Boolean cut;
		if (*p == SNIPPET_MARK_ON) {
			face = bold;
			TextFace(face);
			p++;
			continue;
		}
		if (*p == SNIPPET_MARK_OFF) {
			face = 0;
			TextFace(face);
			p++;
			continue;
		}
		while (*p && *p != SNIPPET_MARK_ON && *p != SNIPPET_MARK_OFF)
			p++;
		n = (short) (p - run);
		w = TextWidth((Ptr) run, 0, n);
		if (used + w <= maxWidth - (*p ? ell : 0) || (!*p && used + w <= maxWidth)) {
			DrawText((Ptr) run, 0, n);
			used += w;
			continue;
		}
		n = FitLength(run, n, (short) (maxWidth - used), &cut);
		DrawText((Ptr) run, 0, n);
		DrawChar(ELLIPSIS);
		break;
	}
	TextFace(0);
}
