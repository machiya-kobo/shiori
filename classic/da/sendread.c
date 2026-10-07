/* sendread.c: see sendread.h. */
#include <AppleEvents.h>
#include <Files.h>
#include <Memory.h>
#include <Processes.h>
#include <string.h>

#include "sendread.h"

enum { typeAppParameters_ = 'appa', launchNoFileFlags_ = 0x0800 };   /* not in Multiversal */

/* Shiori's process, when it's running. */
static Boolean FindShiori(ProcessSerialNumber *psn)
{
	ProcessInfoRec info;

	psn->highLongOfPSN = 0;
	psn->lowLongOfPSN = kNoProcess;
	while (GetNextProcess(psn) == noErr) {
		memset(&info, 0, sizeof(info));
		info.processInfoLength = sizeof(info);
		if (GetProcessInformation(psn, &info) == noErr && info.processSignature == 'SHIO')
			return true;
	}
	return false;
}

/* Shiori on any mounted volume, by its creator, from the desktop database. */
static Boolean FindApp(FSSpec *spec)
{
	HParamBlockRec vol;
	DTPBRec dt;
	Str255 name;
	short i;

	for (i = 1; ; i++) {
		memset(&vol, 0, sizeof(vol));
		vol.volumeParam.ioVolIndex = i;
		if (PBHGetVInfoSync(&vol) != noErr)
			return false;
		memset(&dt, 0, sizeof(dt));
		dt.ioVRefNum = vol.volumeParam.ioVRefNum;
		if (PBDTGetPath(&dt) != noErr)
			continue;
		dt.ioNamePtr = name;
		dt.ioIndex = 0;
		dt.ioFileCreator = 'SHIO';
		if (PBDTGetAPPLSync(&dt) == noErr && FSMakeFSSpec(vol.volumeParam.ioVRefNum, dt.ioAPPLParID, name, spec) == noErr)
			return true;
	}
}

static OSErr Put(AppleEvent *ae, AEKeyword key, const char *s)
{
	return AEPutParamPtr(ae, key, typeChar, (Ptr) s, (Size) strlen(s));
}

OSErr ShioriSendRead(Boolean note, const char *url, const char *title, const char *place, const char *path)
{
	OSType sig = 'SHIO';
	AEAddressDesc target;
	AppleEvent ae, reply;
	ProcessSerialNumber psn;
	OSErr err;

	err = AECreateDesc(typeApplSignature, (Ptr) &sig, (Size) sizeof(sig), &target);
	if (err != noErr)
		return err;
	err = AECreateAppleEvent('SHIO', 'read', &target, kAutoGenerateReturnID, kAnyTransactionID, &ae);
	AEDisposeDesc(&target);
	if (err != noErr)
		return err;
	err = Put(&ae, keyDirectObject, url);
	if (err == noErr)
		err = Put(&ae, 'kind', note ? "n" : "p");
	if (err == noErr)
		err = Put(&ae, 'titl', title);
	if (err == noErr)
		err = Put(&ae, 'plac', place);
	if (err == noErr && note)
		err = Put(&ae, 'path', path);
	if (err == noErr) {
		if (FindShiori(&psn)) {
			err = AESend(&ae, &reply, kAENoReply, kAENormalPriority, kAEDefaultTimeout, NULL, NULL);
			if (err == noErr)
				SetFrontProcess(&psn);
		} else {
			FSSpec app;
			AEDesc launchDesc;
			LaunchParamBlockRec lp;

			if (!FindApp(&app)) {
				err = fnfErr;
			} else if ((err = AECoerceDesc(&ae, typeAppParameters_, &launchDesc)) == noErr) {
				HLock(launchDesc.dataHandle);
				memset(&lp, 0, sizeof(lp));
				lp.launchBlockID = extendedBlock;
				lp.launchEPBLength = extendedBlockLen;
				lp.launchControlFlags = launchContinue | launchNoFileFlags_;
				lp.launchAppSpec = &app;
				lp.launchAppParameters = (AppParametersPtr) *launchDesc.dataHandle;
				err = LaunchApplication(&lp);
				AEDisposeDesc(&launchDesc);
			}
		}
	}
	AEDisposeDesc(&ae);
	return err;
}

