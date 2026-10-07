/*
 * balloons.r: the 'hmnu' resource type for Balloon Help (Inside Macintosh:
 * More Macintosh Toolbox, chapter 3). Retro68 ships no Balloons.r.
 *
 * The layout, as System 7.6.1's own Note Pad has it: version, options,
 * procID, variant, the count of components after the missing-items one,
 * then the missing-items component, the menu title's and each item's. Every
 * component starts with its size in bytes (the size word included) and its
 * type. Only fixed-size components here, so no Rez labels are needed: a skip
 * (size 4, type 256) and a message from 'STR#' resources (size 20, type 3:
 * resource ID and index for the enabled, dimmed, checked and other states;
 * 0, 0 for none).
 */
#ifndef SHIORI_BALLOONS_R
#define SHIORI_BALLOONS_R

#define HelpMgrVersion      2
#define hmDefaultOptions    0

type 'hmnu'
{
	integer;                          /* version */
	longint;                          /* options */
	integer;                          /* procID */
	integer;                          /* variant */
	integer = $$CountOf(MenuArray);
	switch {                          /* items with no entry (appended ones) */
		case HMSkipItem:
			key longint = 0x00040100;
		case HMStringResItem:
			key longint = 0x00140003;
			integer; integer; integer; integer;
			integer; integer; integer; integer;
	};
	array MenuArray {                 /* the title, then each item */
		switch {
			case HMSkipItem:
				key longint = 0x00040100;
			case HMStringResItem:
				key longint = 0x00140003;
				integer; integer; integer; integer;
				integer; integer; integer; integer;
		};
	};
};

#endif
