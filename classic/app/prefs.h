/*
 * prefs.h: "Shiori Preferences": the bridge's two addresses, the Mac's room
 * token, the reader's text size and Notes' vault. Kept on this Mac only (no
 * account syncs a Classic Mac's settings), in the Preferences folder on
 * System 7 and the System Folder on System 6, as plain "key=value" lines.
 * Keep the file out of shared folders: the token is in it (System 6 has no
 * Keychain). The token is never shown: Preferences says whether it's set.
 */
#ifndef SHIORI_PREFS_H
#define SHIORI_PREFS_H

#include <MacTypes.h>

#include "../core/config.h"

typedef struct Prefs {
	ShioriConfig config;
	short textSize;         /* the reader's body text: 10, 12 or 14 */
	char vault[48];         /* Notes' vault: "" the default */
} Prefs;

/* Reads the file over the defaults already in p; false when there's none yet. */
Boolean PrefsLoad(Prefs *p);
Boolean PrefsSave(const Prefs *p);
/* The Preferences dialog; true when something changed (and was saved). */
Boolean PrefsDialog(Prefs *p);

#endif
