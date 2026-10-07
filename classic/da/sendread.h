/*
 * sendread.h: SHIO/read, "open this result in a reader", from the Shiori
 * Search desk accessory to Shiori (System 7 only: the caller checks for the
 * Apple Event Manager). When Shiori isn't running it's found by its creator
 * in the desktop database and launched with the event as its first. The
 * event's parameters are in app/ae.h. The test tool (tests/aesend.c) sends
 * through it too.
 */
#ifndef SHIORI_SENDREAD_H
#define SHIORI_SENDREAD_H

#include <MacTypes.h>

/* fnfErr when Shiori isn't on any mounted volume. */
OSErr ShioriSendRead(Boolean note, const char *url, const char *title, const char *place, const char *path);

#endif
