/* ae.c: see ae.h. */
#include <AppleEvents.h>
#include <Gestalt.h>
#include <Traps.h>
#include <string.h>

#include "ae.h"

static void (*gQuit)(void);
static void (*gSearch)(const char *macRoman);
static Boolean gHaveAE;

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
	DescType type;
	Size size = 0;
	OSErr err;

	(void) reply; (void) refcon;
	err = AEGetParamPtr((AERecord *) e, keyDirectObject, typeChar, &type, text, (Size) sizeof(text) - 1, &size);
	if (err != noErr)
		return err;
	if (size > (Size) sizeof(text) - 1)
		size = (Size) sizeof(text) - 1;
	text[size] = '\0';
	if (gSearch != NULL)
		gSearch(text);
	return noErr;
}

void AppleEventsInit(void (*quit)(void), void (*search)(const char *macRoman))
{
	long response;

	gQuit = quit;
	gSearch = search;
	if (NGetTrapAddress(_Gestalt, kToolboxTrapType) == NGetTrapAddress(_Unimplemented, kToolboxTrapType)
			|| Gestalt(gestaltAppleEventsAttr, &response) != noErr || !(response & 1))
		return;
	gHaveAE = true;
	AEInstallEventHandler(kCoreEventClass, kAEOpenApplication, NewAEEventHandlerUPP(OpenApp), 0, false);
	AEInstallEventHandler(kCoreEventClass, kAEOpenDocuments, NewAEEventHandlerUPP(NoDocuments), 0, false);
	AEInstallEventHandler(kCoreEventClass, kAEPrintDocuments, NewAEEventHandlerUPP(NoDocuments), 0, false);
	AEInstallEventHandler(kCoreEventClass, kAEQuitApplication, NewAEEventHandlerUPP(Quit), 0, false);
	AEInstallEventHandler('SHIO', 'srch', NewAEEventHandlerUPP(Search), 0, false);
}

void AppleEventsHandle(EventRecord *e)
{
	if (gHaveAE)
		AEProcessAppleEvent(e);
}
