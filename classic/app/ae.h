/*
 * ae.h: System 7's Apple events. The required four (open the application,
 * open and print documents, which Shiori has none of, and quit), and
 * Shiori's own SHIO/srch, "search for this" (its direct object, text), which
 * the Shiori Search desk accessory sends. Nothing on System 6.
 */
#ifndef SHIORI_AE_H
#define SHIORI_AE_H

#include <Events.h>

/* Installs the handlers when the Apple Event Manager is there. */
void AppleEventsInit(void (*quit)(void), void (*search)(const char *macRoman));
/* A kHighLevelEvent from the loop. */
void AppleEventsHandle(EventRecord *e);

#endif
