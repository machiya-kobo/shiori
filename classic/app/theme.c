/* theme.c: see theme.h. */
#include <LowMem.h>
#include <OSUtils.h>
#include <Quickdraw.h>
#include <Windows.h>

#include "theme.h"

/* Shiori's colours on a color screen, grays on a gray one. */
typedef struct Rgb { unsigned short r, g, b; } Rgb;

#define C(hex) { (unsigned short) ((((hex) >> 16) & 0xFF) * 257), (unsigned short) ((((hex) >> 8) & 0xFF) * 257), \
	(unsigned short) (((hex) & 0xFF) * 257) }

/* From the Mac's standard 256-color palette (its 6x6x6 cube), so an 8-bit
   screen shows them exactly: the light theme's hues, each 4.5:1 or better on
   white (Tokyo Night Day's own values fell between the cube's steps, and
   Notes and Code both drew red). */
static const Rgb kColor[ROLE_COUNT] = {
	C(0x000000),            /* text */
	C(0x333366),            /* secondary: 11:1 */
	C(0x0033CC),            /* accent: 8.6:1 */
	C(0x006699),            /* All: 6.2:1 */
	C(0x0033CC),            /* Pages */
	C(0x996600),            /* Notes: 5.2:1 */
	C(0xCC0033),            /* Code: 5.6:1 */
	C(0xCCCCFF),            /* a selected row: titles stay 5.8:1 on it; the rest draws black */
};

/* A 16-color screen has only Apple's standard 4-bit palette: these are its
   own entries, so nothing is snapped to a neighbour (its orange and cyan are
   too light for text on white, so Notes is the palette's brown). */
static const Rgb kColor16[ROLE_COUNT] = {
	C(0x000000),            /* text */
	C(0x404040),            /* secondary: dark gray, 10:1 */
	C(0x0000D4),            /* accent: blue, 9:1 */
	C(0x006411),            /* All: dark green, 7:1 */
	C(0x0000D4),            /* Pages */
	C(0x562C05),            /* Notes: brown, 12:1 */
	C(0xDD0806),            /* Code: red, 5:1 */
	C(0xC0C0C0),            /* a selected row: light gray */
};

/* Grays darker than the contrast needs: emulators (and some monitors' gamma)
   show them lighter (Basilisk II draws #444444 as #656565). */
static const Rgb kGray[ROLE_COUNT] = {
	C(0x000000),
	C(0x444444),            /* secondary: 9.7:1 */
	C(0x000000),
	C(0x333333),            /* the pills: 12.6:1 */
	C(0x333333),
	C(0x333333),
	C(0x333333),
	C(0xCCCCCC),
};

static int gHasColorQD = -1;

static Boolean HasColorQD(void)
{
	SysEnvRec env;

	if (gHasColorQD < 0)
		gHasColorQD = (SysEnvirons(1, &env) == noErr && env.hasColorQD) ? 1 : 0;
	return gHasColorQD == 1;
}

WindowPtr ThemeNewWindow(const Rect *bounds, ConstStr255Param title, short procID)
{
	if (HasColorQD())
		return NewCWindow(NULL, bounds, title, true, procID, (WindowPtr) -1L, true, 0);
	return NewWindow(NULL, bounds, title, true, procID, (WindowPtr) -1L, true, 0);
}

/* The main screen's kind and depth, as it is now. */
static int Screen(short *depth)
{
	GDHandle gd;

	*depth = 1;
	if (!HasColorQD())
		return THEME_MONO;
	gd = GetMainDevice();
	if (gd == NULL)
		return THEME_MONO;
	*depth = (**(**gd).gdPMap).pixelSize;
	if (*depth < 2)
		return THEME_MONO;
	/* gdDevType (bit 0 of gdFlags): set for a color screen, clear for grays */
	return ((**gd).gdFlags & 1) ? THEME_COLOR : THEME_GRAY;
}

int ThemeKind(void)
{
	short depth;
	return Screen(&depth);
}

static const Rgb *Table(void)
{
	short depth;
	int kind = Screen(&depth);

	if (kind == THEME_COLOR)
		return depth <= 4 ? kColor16 : kColor;
	return kind == THEME_GRAY ? kGray : NULL;
}

void ThemeFore(int role)
{
	const Rgb *t = Table();
	RGBColor c;

	if (t == NULL) {
		ForeColor(blackColor);
		return;
	}
	c.red = t[role].r;
	c.green = t[role].g;
	c.blue = t[role].b;
	RGBForeColor(&c);
}

void ThemeBack(int role)
{
	const Rgb *t = Table();
	RGBColor c;

	if (t == NULL || role != ROLE_SELECTED_BG) {
		BackColor(whiteColor);
		if (t != NULL) {
			c.red = c.green = c.blue = 0xFFFF;
			RGBBackColor(&c);
		}
		return;
	}
	c.red = t[role].r;
	c.green = t[role].g;
	c.blue = t[role].b;
	RGBBackColor(&c);
}

void ThemeNormal(void)
{
	if (HasColorQD()) {
		RGBColor black = {0, 0, 0}, white = {0xFFFF, 0xFFFF, 0xFFFF};
		RGBForeColor(&black);
		RGBBackColor(&white);
	} else {
		ForeColor(blackColor);
		BackColor(whiteColor);
	}
}

void ThemeHilite(const Rect *r)
{
	if (ThemeKind() != THEME_MONO) {
		/* HiliteMode is a low-memory global at a fixed address, which GCC takes for an empty array */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Warray-bounds"
		LMSetHiliteMode((Byte) (LMGetHiliteMode() & ~(1 << pHiliteBit)));
#pragma GCC diagnostic pop
	}
	InvertRect(r);
}

int ThemePillRole(int pill)
{
	return pill == 1 ? ROLE_PAGES : pill == 2 ? ROLE_NOTES : pill == 3 ? ROLE_CODE : ROLE_ALL;
}
