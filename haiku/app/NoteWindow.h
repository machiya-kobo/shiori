// A note's preview, from Kura's /api/note (never Hister's copy, never
// cached): the note as styled text, its links opening in the browser, and
// Open in Kura.
#pragma once

#include <Window.h>

#include "../core/NoteText.h"
#include "../core/Results.h"

class BStringView;
class NoteTextView;

class NoteWindow : public BWindow {
public:
	explicit NoteWindow(const shiori::Result& note);
	void MessageReceived(BMessage* message) override;

private:
	void Load();
	void ShowNote(BMessage* message);

	shiori::Result fNote;
	NoteTextView* fText;
	BStringView* fStatus;
};
