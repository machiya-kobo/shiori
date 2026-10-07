// A search, run on its own thread (Hister's pages and the notes for a pill,
// from Kura or, as Settings says, from Hister; or the next page of one), its
// outcome posted back as kMsgResults with a "generation" and an "outcome" (a
// SearchOutcome* the receiver owns). Shared by the search window and the
// quick search.
#pragma once

#include <string>

#include <Messenger.h>

#include "../core/Config.h"
#include "../core/Query.h"
#include "../core/Results.h"

const int kPageSize = 30;
const int kAllNotes = 3;   // All shows Kura's top notes, then Hister's pages
const int kAllRecentNotes = 10;   // All with no words: the newest notes, then the newest pages

struct SearchRequest {
	shiori::Pill pill = shiori::Pill::All;
	std::string query;
	std::string vault;       // the Notes pill's
	bool more = false;
	std::string histerKey;   // more: Hister's page_key (the notes' too, when they come from Hister)
	int kuraOffset = 0;      // more: Kura's offset
};

struct SearchOutcome {
	bool more = false;
	bool askedNotes = false, askedPages = false;
	bool notesFromHister = false;   // the notes came from Hister (paged by page_key, not offset)
	int kuraOffset = 0;
	shiori::ResultPage notes, pages;
	std::string notesProblem, pagesProblem;
};

void RunSearch(BMessenger target, int32 generation, SearchRequest request, shiori::Config config);
