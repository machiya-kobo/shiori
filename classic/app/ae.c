/* ae.c: see ae.h. */
#include <AppleEvents.h>
#include <Gestalt.h>
#include <Traps.h>
#include <string.h>

#include "../core/notetext.h"
#include "ae.h"

enum { errAEParamMissed = -1715 };      /* not in Multiversal */

static void (*gQuit)(void);
static void (*gSearch)(const char *macRoman);
static void (*gRead)(const ListRow *row);
static Boolean gHaveAE;

/* A text parameter into out (cap bytes, NUL-terminated); false when it's missing. */
static Boolean TextParam(const AppleEvent *e, AEKeyword key, char *out, long cap)
{
	DescType type;
	Size size = 0;

	out[0] = '\0';
	if (AEGetParamPtr((AERecord *) e, key, typeChar, &type, out, (Size) cap - 1, &size) != noErr)
		return false;
	if (size > (Size) cap - 1)
		size = (Size) cap - 1;
	out[size] = '\0';
	return true;
}

static pascal OSErr OpenApp(const AppleEvent *e, AppleEvent *reply, long refcon)
{
	(void) e; (void) reply; (void) refcon;
	return noErr;
}

static pascal OSErr NoDocuments(const AppleEvent *e, AppleEvent *reply, long refcon)
{
	(void) e; (void) reply; (void) refcon;
	return errAEEventNotHandled;
}

static pascal OSErr Quit(const AppleEvent *e, AppleEvent *reply, long refcon)
{
	(void) e; (void) reply; (void) refcon;
	if (gQuit != NULL)
		gQuit();
	return noErr;
}

/* SHIO/srch: the direct object is the text to search for. */
static pascal OSErr Search(const AppleEvent *e, AppleEvent *reply, long refcon)
{
	char text[256];

	(void) reply; (void) refcon;
	if (!TextParam(e, keyDirectObject, text, (long) sizeof(text)))
		return errAEParamMissed;
	if (gSearch != NULL)
		gSearch(text);
	return noErr;
}

/* SHIO/read: a result from the desk accessory, opened in a reader. */
static pascal OSErr Read(const AppleEvent *e, AppleEvent *reply, long refcon)
{
	ListRow row;
	char kind[4], vault[48];

	(void) reply; (void) refcon;
	memset(&row, 0, sizeof(row));
	if (!TextParam(e, keyDirectObject, row.url, (long) sizeof(row.url)) || !TextParam(e, 'kind', kind, (long) sizeof(kind)))
		return errAEParamMissed;
	(void) TextParam(e, 'titl', row.title, (long) sizeof(row.title));
	(void) TextParam(e, 'plac', row.place, (long) sizeof(row.place));
	if (kind[0] == 'n') {
		row.kind = LROW_NOTE;
		if (!TextParam(e, 'path', row.path, (long) sizeof(row.path)) || row.path[0] == '\0')
			return errAEParamMissed;
		shiori_url_vault(row.url, vault, (long) sizeof(vault));
		if (vault[0] != '\0')
			return errAEEventNotHandled;    /* another vault: never through an Apple event */
	} else {
		row.kind = LROW_PAGE;
	}
	if (gRead != NULL)
		gRead(&row);
	return noErr;
}

void AppleEventsInit(void (*quit)(void), void (*search)(const char *macRoman), void (*read)(const ListRow *row))
{
	long response;

	gQuit = quit;
	gSearch = search;
	gRead = read;
	if (NGetTrapAddress(_Gestalt, kToolboxTrapType) == NGetTrapAddress(_Unimplemented, kToolboxTrapType)
			|| Gestalt(gestaltAppleEventsAttr, &response) != noErr || !(response & 1))
		return;
	gHaveAE = true;
	AEInstallEventHandler(kCoreEventClass, kAEOpenApplication, NewAEEventHandlerUPP(OpenApp), 0, false);
	AEInstallEventHandler(kCoreEventClass, kAEOpenDocuments, NewAEEventHandlerUPP(NoDocuments), 0, false);
	AEInstallEventHandler(kCoreEventClass, kAEPrintDocuments, NewAEEventHandlerUPP(NoDocuments), 0, false);
	AEInstallEventHandler(kCoreEventClass, kAEQuitApplication, NewAEEventHandlerUPP(Quit), 0, false);
	AEInstallEventHandler('SHIO', 'srch', NewAEEventHandlerUPP(Search), 0, false);
	AEInstallEventHandler('SHIO', 'read', NewAEEventHandlerUPP(Read), 0, false);
}

void AppleEventsHandle(EventRecord *e)
{
	if (gHaveAE)
		AEProcessAppleEvent(e);
}
