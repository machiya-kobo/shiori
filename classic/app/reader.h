/*
 * reader.h: a result read in its own window (up to three). A note comes
 * from Kura (/api/note: never Hister's copy, never cached), a page from
 * Hister's readable copy (/api/preview). The HTML becomes styled text
 * (core/notetext.c): headings, bold, italic, code, quotes, lists, links.
 * A link to another note in the same Kura opens that note here; any other
 * link shows its address, and Copy Link copies it (there's no browser).
 * Find (⌘F) and Find Again (⌘G) search the text.
 */
#ifndef SHIORI_READER_H
#define SHIORI_READER_H

#include <Events.h>
#include <Windows.h>

#include "../core/config.h"
#include "resultlist.h"

/* Opens row (a page or a note) in a reader window; false when it can't (three are open, or memory). */
Boolean ReaderOpen(const ShioriConfig *config, const ListRow *row);
Boolean IsReaderWindow(WindowPtr w);

void ReaderUpdate(WindowPtr w);
void ReaderActivate(WindowPtr w, Boolean active);
void ReaderClick(WindowPtr w, EventRecord *e);
void ReaderKey(WindowPtr w, EventRecord *e);
void ReaderGrow(WindowPtr w, Point where);
void ReaderZoom(WindowPtr w, Point where, short part);
void ReaderClose(WindowPtr w);
/* Moves every reader's request along; true while any is loading. */
Boolean ReaderPollAll(void);
void ReaderStop(WindowPtr w);
void ReaderFind(WindowPtr w);
void ReaderFindAgain(WindowPtr w);
void ReaderCopyLink(WindowPtr w);
/* Copies the whole text (Edit > Copy). */
void ReaderCopy(WindowPtr w);
Boolean ReaderCanFindAgain(WindowPtr w);
void ReaderCloseAll(void);

#endif
