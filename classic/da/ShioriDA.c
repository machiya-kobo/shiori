/*
 * Shiori Search, the desk accessory (phase 0 spike): proof that Retro68 can
 * build a working DRVR. It opens a small window, draws, follows activate
 * and update events, and closes. The quick search itself comes in phase 7.
 *
 * Built as a flat code resource (-Wl,--mac-flat): the DRVR header sits in
 * .rsrcheader, which Elf2Mac places first, and its offsets point at the
 * glue below, which calls the C routines with (param block, DCE).
 */
#include <Devices.h>
#include <Events.h>
#include <Quickdraw.h>
#include <Fonts.h>
#include <Windows.h>
#include <Memory.h>
#include <OSUtils.h>
#include <Retro68Runtime.h>
#include <string.h>

/* dNeedLock | dNeedTime | dCtlEnable; events: mouseDown keyDown autoKey update activate */
__asm__(
	"	.section .rsrcheader,\"ax\",@progbits\n"
	"	.globl	da_header\n"
	"da_header:\n"
	"	.short	0x6400\n"
	"	.short	60\n"
	"	.short	0x016A\n"
	"	.short	0\n"
	"	.short	da_open - da_header\n"
	"	.short	da_done - da_header\n"
	"	.short	da_control - da_header\n"
	"	.short	da_done - da_header\n"
	"	.short	da_close - da_header\n"
	"	.byte	14\n"
	"	.byte	0\n"
	"	.ascii	\"Shiori Search\"\n"
	"	.align	2\n"
	/* Open and Close: immediate, a plain rts */
	"da_open:\n"
	"	movem.l	%a0-%a1,-(%sp)\n"
	"	move.l	%a1,-(%sp)\n"
	"	move.l	%a0,-(%sp)\n"
	"	bsr.w	DAOpen\n"
	"	addq.l	#8,%sp\n"
	"	movem.l	(%sp)+,%a0-%a1\n"
	"	rts\n"
	"da_close:\n"
	"	movem.l	%a0-%a1,-(%sp)\n"
	"	move.l	%a1,-(%sp)\n"
	"	move.l	%a0,-(%sp)\n"
	"	bsr.w	DAClose\n"
	"	addq.l	#8,%sp\n"
	"	movem.l	(%sp)+,%a0-%a1\n"
	"	rts\n"
	/* Control: through IODone unless the call was immediate (ioTrap bit 9) */
	"da_control:\n"
	"	movem.l	%a0-%a1,-(%sp)\n"
	"	move.l	%a1,-(%sp)\n"
	"	move.l	%a0,-(%sp)\n"
	"	bsr.w	DAControl\n"
	"	addq.l	#8,%sp\n"
	"	movem.l	(%sp)+,%a0-%a1\n"
	"da_iodone:\n"
	"	move.w	6(%a0),%d1\n"
	"	btst	#9,%d1\n"
	"	bne.s	1f\n"
	"	move.l	0x8FC,-(%sp)\n"
	"1:	rts\n"
	"da_done:\n"
	"	moveq	#0,%d0\n"
	"	bra.s	da_iodone\n"
	"	.text\n");

/* Elf2Mac wants an entry point; the Device Manager uses the header instead. */
void _start(void)
{
}

static void Draw(WindowPtr w)
{
	GrafPtr old;

	GetPort(&old);
	SetPort(w);
	EraseRect(&w->portRect);
	TextFont(kFontIDGeneva);
	TextSize(9);
	MoveTo(10, 20);
	DrawString("\pShiori Search: the desk accessory spike.");
	MoveTo(10, 36);
	DrawString("\pThe quick search arrives in phase 7.");
	SetPort(old);
}

short DAOpen(ParmBlkPtr pb, DCtlPtr dce)
{
	Rect r;
	WindowPtr w;

	RETRO68_RELOCATE();
	if (dce->dCtlWindow != NULL) {          /* already open: bring it forward */
		SelectWindow((WindowPtr) dce->dCtlWindow);
		return noErr;
	}
	SetRect(&r, 60, 80, 330, 140);
	w = NewWindow(NULL, &r, "\pShiori Search", true, noGrowDocProc, (WindowPtr) -1L, true, 0);
	if (w == NULL)
		return memFullErr;
	((WindowPeek) w)->windowKind = dce->dCtlRefNum;
	dce->dCtlWindow = (WindowPtr) w;
	return noErr;
}

short DAClose(ParmBlkPtr pb, DCtlPtr dce)
{
	if (dce->dCtlWindow != NULL) {
		DisposeWindow((WindowPtr) dce->dCtlWindow);
		dce->dCtlWindow = NULL;
	}
	return noErr;
}

short DAControl(ParmBlkPtr pb, DCtlPtr dce)
{
	CntrlParam *cp = (CntrlParam *) pb;
	WindowPtr w = (WindowPtr) dce->dCtlWindow;

	if (cp->csCode == accEvent && w != NULL) {
		EventRecord *e;
		memcpy(&e, cp->csParam, sizeof(e));     /* csParam holds the event's address */
		if (e->what == updateEvt && (WindowPtr) e->message == w) {
			BeginUpdate(w);
			Draw(w);
			EndUpdate(w);
		}
	}
	return noErr;
}
