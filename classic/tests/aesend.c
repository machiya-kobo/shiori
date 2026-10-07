/*
 * aesend.c: a test tool for System 7, never shipped. It sends Shiori three
 * SHIO/read events through the desk accessory's own code (da/sendread.c),
 * launching Shiori when it isn't running, then quits:
 *   a page               Shiori opens a reader for it;
 *   a default-vault note  a reader too;
 *   another vault's note  refused: no reader (app/ae.c).
 * With no network the readers say why they couldn't load; the windows and
 * their titles are what's checked (docs/TESTING.md). Its own window shows
 * each send's result (0, or the OSErr) until a click.
 */
#include <Dialogs.h>
#include <Fonts.h>
#include <Memory.h>
#include <Quickdraw.h>
#include <Events.h>
#include <OSUtils.h>
#include <ToolUtils.h>
#include <Windows.h>
#include <string.h>

#include "../da/sendread.h"

int main(void)
{
	InitGraf(&qd.thePort);
	InitFonts();
	InitWindows();
	InitMenus();
	TEInit();
	InitDialogs(NULL);
	InitCursor();
	OSErr err[3];
	WindowPtr w;
	Rect r;
	Str255 num;
	EventRecord e;
	int i;
	static const char *const what[3] = {"page: ", "default note: ", "other vault: "};

	err[0] = ShioriSendRead(false, "https://example.com/aesend/page", "AE test: a page", "example.com", "");
	err[1] = ShioriSendRead(true, "http://192.0.2.1:8071/n/aesend-note", "AE test: a default note", "Tests",
		"aesend-note.md");
	err[2] = ShioriSendRead(true, "http://192.0.2.1:8071/v/work/n/secret", "AE test: another vault", "Work",
		"secret.md");
	SetRect(&r, 40, 400, 300, 470);
	w = NewWindow(NULL, &r, "\pAE Send", true, noGrowDocProc, (WindowPtr) -1L, false, 0);
	SetPort(w);
	TextFont(kFontIDGeneva);
	TextSize(10);
	for (i = 0; i < 3; i++) {
		MoveTo(10, (short) (18 + i * 16));
		DrawText((Ptr) what[i], 0, (short) strlen(what[i]));
		NumToString(err[i], num);
		DrawString(num);
	}
	while (!(GetNextEvent(mDownMask, &e) && e.what == mouseDown))
		SystemTask();
	return 0;
}
