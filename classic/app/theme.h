/*
 * theme.h: colour only where the screen has it. On a Mac Plus, and at one
 * bit, everything is black on white. On a gray screen, secondary text and
 * the pills are dark grays. On a color screen the pills wear Shiori's
 * colours (All cyan, Pages blue, Notes orange, Code red), titles and links
 * the accent: the light theme's hues, taken from the screen's own palette
 * (the 256-color cube, or the 16-color one) so nothing is snapped to a
 * neighbour, every one at least 4.5:1 on white. The screen is read at every
 * draw, so a depth changed in Monitors while Shiori runs just works.
 */
#ifndef SHIORI_THEME_H
#define SHIORI_THEME_H

#include <Quickdraw.h>
#include <Windows.h>

enum { THEME_MONO, THEME_GRAY, THEME_COLOR };

enum {
	ROLE_TEXT,
	ROLE_SECONDARY,         /* the place line, the status line */
	ROLE_ACCENT,            /* result titles, links */
	ROLE_ALL,               /* the pills, by their pill */
	ROLE_PAGES,
	ROLE_NOTES,
	ROLE_CODE,
	ROLE_SELECTED_BG,       /* a selected row's background (gray and color only) */
	ROLE_COUNT
};

/* A document window: a color port where Color QuickDraw is (an old-style
   port maps every colour to QuickDraw's eight), a plain one on a Mac Plus. */
WindowPtr ThemeNewWindow(const Rect *bounds, ConstStr255Param title, short procID);
/* The main screen as it is now. */
int ThemeKind(void);
/* Sets the pen's colour for role (black on a 1-bit screen). */
void ThemeFore(int role);
/* Sets the background colour (white, or a selected row's). */
void ThemeBack(int role);
/* Black text on white again. */
void ThemeNormal(void);
/* Highlights r: the user's highlight color where there's color (Color
   QuickDraw's hilite mode), an invert on a Mac Plus. Call it again to undo. */
void ThemeHilite(const Rect *r);
/* The role of pill i (0 All ... 3 Code). */
int ThemePillRole(int pill);

#endif
