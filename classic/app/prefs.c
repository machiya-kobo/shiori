/* prefs.c: see prefs.h. */
#include <Dialogs.h>
#include <Files.h>
#include <Gestalt.h>
#include <OSUtils.h>
#include <Traps.h>
#include <ToolUtils.h>
#include <stdio.h>
#include <string.h>

#include "../core/http.h"
#include "net.h"
#include "prefs.h"

#define PREFS_DIALOG 130
#define TOKEN_DIALOG 131
#define BAD_ALERT 132

enum {
	iOK = 1, iCancel = 2, iBridge = 4, iDirect = 5, iHister = 7, iKura = 9, iTokenState = 11, iChangeToken = 12,
	iHisterTokenLabel = 13, iHisterTokenState = 14, iChangeHisterToken = 15,
	iSmall = 17, iMedium = 18, iLarge = 19, iOutline = 21
};

static const unsigned char kName[] = "\pShiori Preferences";


/* Folder Manager values (Inside Macintosh VI) Multiversal lacks */
enum { kShioriOnSystemDisk = -32768, kShioriCreateFolder = 1, kShioriFindFolderPresent = 0 };

static Boolean TrapAvailable(short trap, TrapType type)
{
	return NGetTrapAddress(trap, type) != NGetTrapAddress(_Unimplemented, kToolboxTrapType);
}

/* The folder: System 7's Preferences folder, else the System Folder. */
static OSErr PrefsFolder(short *vRefNum, long *dirID)
{
	long response;
	SysEnvRec env;

	if (TrapAvailable(_Gestalt, kToolboxTrapType) && Gestalt(gestaltFindFolderAttr, &response) == noErr
			&& (response & (1L << kShioriFindFolderPresent)))
		return FindFolder(kShioriOnSystemDisk, kPreferencesFolderType, kShioriCreateFolder, vRefNum, dirID);
	if (SysEnvirons(1, &env) != noErr)
		return fnfErr;
	*vRefNum = env.sysVRefNum;           /* a working directory: the System Folder */
	*dirID = 0;
	return noErr;
}

/* The File Manager calls, with every parameter block zeroed first: Retro68's
   glue (HOpen, FSWrite…) leaves fields such as ioCompletion and ioVersNum as
   stack garbage, and on a Mac Plus FSWrite then died with an address error. */
static OSErr PrefOpen(short vRef, long dirID, short perm, short *ref)
{
	HParamBlockRec pb;
	OSErr err;

	memset(&pb, 0, sizeof(pb));
	pb.ioParam.ioNamePtr = (StringPtr) kName;
	pb.ioParam.ioVRefNum = vRef;
	pb.ioParam.ioPermssn = (SInt8) perm;
	pb.fileParam.ioDirID = dirID;
	err = PBHOpenSync(&pb);
	*ref = pb.ioParam.ioRefNum;
	return err;
}

static OSErr PrefCreate(short vRef, long dirID)
{
	HParamBlockRec pb;
	OSErr err;

	memset(&pb, 0, sizeof(pb));
	pb.fileParam.ioNamePtr = (StringPtr) kName;
	pb.fileParam.ioVRefNum = vRef;
	pb.fileParam.ioDirID = dirID;
	if ((err = PBHCreateSync(&pb)) != noErr)
		return err;
	memset(&pb, 0, sizeof(pb));
	pb.fileParam.ioNamePtr = (StringPtr) kName;
	pb.fileParam.ioVRefNum = vRef;
	pb.fileParam.ioDirID = dirID;
	if ((err = PBHGetFInfoSync(&pb)) != noErr)
		return err;
	pb.fileParam.ioFlFndrInfo.fdType = 'pref';
	pb.fileParam.ioFlFndrInfo.fdCreator = 'SHIO';
	pb.fileParam.ioDirID = dirID;
	return PBHSetFInfoSync(&pb);
}

static OSErr PrefReadWrite(short ref, long *count, void *buf, Boolean write)
{
	ParamBlockRec pb;
	OSErr err;

	memset(&pb, 0, sizeof(pb));
	pb.ioParam.ioRefNum = ref;
	pb.ioParam.ioBuffer = buf;
	pb.ioParam.ioReqCount = *count;
	pb.ioParam.ioPosMode = fsFromStart;
	pb.ioParam.ioPosOffset = 0;
	err = write ? PBWriteSync((ParmBlkPtr) &pb) : PBReadSync((ParmBlkPtr) &pb);
	*count = pb.ioParam.ioActCount;
	return err;
}

static OSErr PrefSetLength(short ref, long length)
{
	ParamBlockRec pb;

	memset(&pb, 0, sizeof(pb));
	pb.ioParam.ioRefNum = ref;
	pb.ioParam.ioMisc = (Ptr) length;
	return PBSetEOFSync((ParmBlkPtr) &pb);
}

static void PrefClose(short ref, short vRef)
{
	ParamBlockRec pb;

	memset(&pb, 0, sizeof(pb));
	pb.ioParam.ioRefNum = ref;
	(void) PBCloseSync((ParmBlkPtr) &pb);
	memset(&pb, 0, sizeof(pb));
	pb.ioParam.ioVRefNum = vRef;
	(void) PBFlushVolSync((ParmBlkPtr) &pb);
}

static void Set(char *dst, long cap, const char *value)
{
	strncpy(dst, value, (size_t) cap - 1);
	dst[cap - 1] = '\0';
}

Boolean PrefsLoad(Prefs *p)
{
	short vRef, ref;
	long dirID, len;
	long words[256];                     /* word-aligned, as PrefsSave's */
	char *buf = (char *) words, *line, *next;

	if (PrefsFolder(&vRef, &dirID) != noErr || PrefOpen(vRef, dirID, fsRdPerm, &ref) != noErr)
		return false;
	len = (long) sizeof(words) - 1;
	if (PrefReadWrite(ref, &len, buf, false) != noErr && len <= 0)
		len = 0;
	PrefClose(ref, vRef);
	buf[len] = '\0';
	for (line = buf; line != NULL && *line; line = next) {
		char *eq;
		next = strchr(line, '\r');
		if (next != NULL)
			*next++ = '\0';
		eq = strchr(line, '=');
		if (eq == NULL)
			continue;
		*eq = '\0';
		if (strcmp(line, "hister") == 0)
			Set(p->config.hister, (long) sizeof(p->config.hister), eq + 1);
		else if (strcmp(line, "kura") == 0)
			Set(p->config.kura, (long) sizeof(p->config.kura), eq + 1);
		else if (strcmp(line, "token") == 0)
			shiori_checked_room_token(eq + 1, p->config.roomToken, (long) sizeof(p->config.roomToken));
		else if (strcmp(line, "histerToken") == 0)
			shiori_checked_hister_token(eq + 1, p->config.histerToken, (long) sizeof(p->config.histerToken));
		else if (strcmp(line, "mode") == 0)
			p->config.direct = strcmp(eq + 1, "direct") == 0;
		else if (strcmp(line, "textSize") == 0) {
			int size = 0;
			const char *c;
			for (c = eq + 1; *c >= '0' && *c <= '9' && size < 100; c++)
				size = size * 10 + (*c - '0');      /* no strtol: errno brings 1 KB into the DA */
			if (size == 10 || size == 12 || size == 14)
				p->textSize = (short) size;
		} else if (strcmp(line, "vault") == 0)
			Set(p->vault, (long) sizeof(p->vault), eq + 1);
	}
	return true;
}

Boolean PrefsSave(const Prefs *p)
{
	short vRef, ref;
	long dirID, len;
	long words[256];                     /* the buffer word-aligned: a 68000 faults on a word at an odd address */
	char *buf = (char *) words;
	OSErr err;

	if (PrefsFolder(&vRef, &dirID) != noErr)
		return false;
	sprintf(buf, "mode=%s\rhister=%s\rkura=%s\rtoken=%s\rhisterToken=%s\rtextSize=%d\rvault=%s\r",
		p->config.direct ? "direct" : "bridge", p->config.hister, p->config.kura, p->config.roomToken,
		p->config.histerToken, p->textSize, p->vault);
	err = PrefOpen(vRef, dirID, fsRdWrPerm, &ref);
	if (err == fnfErr) {
		if (PrefCreate(vRef, dirID) != noErr)
			return false;
		err = PrefOpen(vRef, dirID, fsRdWrPerm, &ref);
	}
	if (err != noErr)
		return false;
	len = (long) strlen(buf);
	err = PrefReadWrite(ref, &len, buf, true);
	if (err == noErr)
		err = PrefSetLength(ref, len);
	PrefClose(ref, vRef);
	return err == noErr;
}

/* -- the dialogs ------------------------------------------------------------------------------- */

static void ItemText(DialogPtr d, short item, char *out, long cap)
{
	short type;
	Handle h;
	Rect r;
	Str255 s;

	GetDialogItem(d, item, &type, &h, &r);
	GetDialogItemText(h, s);
	if (s[0] > cap - 1)
		s[0] = (unsigned char) (cap - 1);
	memcpy(out, s + 1, s[0]);
	out[s[0]] = '\0';
}

static void SetItemText(DialogPtr d, short item, const char *text)
{
	short type;
	Handle h;
	Rect r;
	Str255 s;
	size_t n = strlen(text) > 255 ? 255 : strlen(text);

	GetDialogItem(d, item, &type, &h, &r);
	s[0] = (unsigned char) n;
	memcpy(s + 1, text, n);
	SetDialogItemText(h, s);
}

static void SetRadio(DialogPtr d, short item, Boolean on)
{
	short type;
	Handle h;
	Rect r;

	GetDialogItem(d, item, &type, &h, &r);
	SetControlValue((ControlHandle) h, on ? 1 : 0);
}

/* The heavy outline around the default button (System 6 dialogs don't draw one). */
static pascal void DrawOutline(DialogPtr d, short item)
{
	short type;
	Handle h;
	Rect r;

	(void) item;
	GetDialogItem(d, iOK, &type, &h, &r);
	PenSize(3, 3);
	InsetRect(&r, -4, -4);
	FrameRoundRect(&r, 16, 16);
	PenNormal();
}

static void TokenState(const char *token, char *out)
{
	if (token[0])
		sprintf(out, "Set (\311%s)", token + strlen(token) - 4);
	else
		strcpy(out, "Not set");
}

static Boolean BridgeAddressOK(const char *url)
{
	HttpBase b;
	ip_addr ip;
	return http_base(url, &b) && NetParseIP(b.host, &ip);
}

/* A token: typed or pasted once, never shown again. hister: Hister's own token, else the room token. */
static Boolean AskToken(char *token, long cap, Boolean hister)
{
	DialogPtr d;
	short item = 0;
	char typed[200], checked[128];

	ParamText(hister ? "\pHister's access token (its app.access_token, or your user's):"
		: "\pThis Mac's room token (mht_\311):", "\p", "\p", "\p");
	d = GetNewDialog(TOKEN_DIALOG, NULL, (WindowPtr) -1L);
	if (d == NULL)
		return false;
	for (;;) {
		item = 0;
		while (item != iOK && item != iCancel)
			ModalDialog(NULL, &item);
		if (item == iCancel)
			break;
		ItemText(d, 4, typed, (long) sizeof(typed));
		if (hister)
			shiori_checked_hister_token(typed, checked, (long) sizeof(checked));
		else
			shiori_checked_room_token(typed, checked, (long) sizeof(checked));
		if ((checked[0] || typed[0] == '\0') && (long) strlen(checked) < cap) {
			strcpy(token, checked);
			break;
		}
		if (hister)
			ParamText("\pThat isn't a Hister token: it's 8 to 127 letters, digits or symbols, with no spaces.",
				"\p", "\p", "\p");
		else
			ParamText("\pThat isn't a room token: it's mht_ and 43 more letters, digits, - or _, from Hister's "
				"sign-in helper (Sessions).", "\p", "\p", "\p");
		StopAlert(BAD_ALERT, NULL);
	}
	DisposeDialog(d);
	return item == iOK;
}

/* The mode's radio buttons, and the Hister token's row only where it's used. */
static void ShowMode(DialogPtr d, Boolean direct)
{
	short type;
	Handle h;
	Rect r;

	SetRadio(d, iBridge, !direct);
	SetRadio(d, iDirect, direct);
	GetDialogItem(d, iChangeHisterToken, &type, &h, &r);
	HiliteControl((ControlHandle) h, direct ? 0 : 255);
}

Boolean PrefsDialog(Prefs *p)
{
	DialogPtr d = GetNewDialog(PREFS_DIALOG, NULL, (WindowPtr) -1L);
	Prefs edit = *p;
	short item = 0, type;
	Handle h;
	Rect r;
	char state[64];
	Boolean saved = false;

	if (d == NULL)
		return false;
	GetDialogItem(d, iOutline, &type, &h, &r);
	SetDialogItem(d, iOutline, type, (Handle) NewUserItemUPP(DrawOutline), &r);
	SetItemText(d, iHister, edit.config.hister);
	SetItemText(d, iKura, edit.config.kura);
	TokenState(edit.config.roomToken, state);
	SetItemText(d, iTokenState, state);
	TokenState(edit.config.histerToken, state);
	SetItemText(d, iHisterTokenState, state);
	ShowMode(d, edit.config.direct);
	SetRadio(d, iSmall, edit.textSize == 10);
	SetRadio(d, iMedium, edit.textSize == 12);
	SetRadio(d, iLarge, edit.textSize == 14);
	SelectDialogItemText(d, iHister, 0, 32767);
	for (;;) {
		ModalDialog(NULL, &item);
		if (item == iCancel)
			break;
		if (item == iChangeToken) {
			if (AskToken(edit.config.roomToken, (long) sizeof(edit.config.roomToken), false)) {
				TokenState(edit.config.roomToken, state);
				SetItemText(d, iTokenState, state);
			}
			SetPort(d);
			continue;
		}
		if (item == iChangeHisterToken) {
			if (AskToken(edit.config.histerToken, (long) sizeof(edit.config.histerToken), true)) {
				TokenState(edit.config.histerToken, state);
				SetItemText(d, iHisterTokenState, state);
			}
			SetPort(d);
			continue;
		}
		if (item == iBridge || item == iDirect) {
			edit.config.direct = item == iDirect;
			ShowMode(d, edit.config.direct);
			continue;
		}
		if (item >= iSmall && item <= iLarge) {
			edit.textSize = item == iSmall ? 10 : item == iMedium ? 12 : 14;
			SetRadio(d, iSmall, item == iSmall);
			SetRadio(d, iMedium, item == iMedium);
			SetRadio(d, iLarge, item == iLarge);
			continue;
		}
		if (item == iOK) {
			ItemText(d, iHister, edit.config.hister, (long) sizeof(edit.config.hister));
			ItemText(d, iKura, edit.config.kura, (long) sizeof(edit.config.kura));
			if (!BridgeAddressOK(edit.config.hister) || (edit.config.kura[0] && !BridgeAddressOK(edit.config.kura))) {
				ParamText("\pAddresses look like http://192.168.1.5:8070/ (an IP address and a port; Shiori here "
					"looks up no names). Kura's may be empty.", "\p", "\p", "\p");
				StopAlert(BAD_ALERT, NULL);
				SetPort(d);
				continue;
			}
			*p = edit;
			saved = PrefsSave(p);
			if (!saved) {
				ParamText("\pThe preferences couldn't be saved: is the startup disk locked or full?", "\p", "\p", "\p");
				StopAlert(BAD_ALERT, NULL);
			}
			break;
		}
	}
	DisposeDialog(d);
	return item == iOK;
}
