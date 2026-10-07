/*
 * ae.h: System 7's Apple events. The required four (open the application,
 * open and print documents, which Shiori has none of, and quit), and
 * Shiori's own two, which the Shiori Search desk accessory sends:
 *   SHIO/srch  search for the direct object (text);
 *   SHIO/read  open a result in a reader: the direct object is its address,
 *              'kind' "n" (a note) or "p" (a page), 'titl' and 'plac' its
 *              title and place (Mac Roman), 'path' a note's path (UTF-8).
 * A note is read only from Kura's default vault: the address decides, and
 * one naming another vault is refused (the desk accessory searches only the
 * default, and any program can send an Apple event). Nothing on System 6.
 */
#ifndef SHIORI_AE_H
#define SHIORI_AE_H

#include <Events.h>

#include "resultlist.h"

/* Installs the handlers when the Apple Event Manager is there. */
void AppleEventsInit(void (*quit)(void), void (*search)(const char *macRoman), void (*read)(const ListRow *row));
/* A kHighLevelEvent from the loop. */
void AppleEventsHandle(EventRecord *e);

#endif
