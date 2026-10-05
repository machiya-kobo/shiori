// Save a web address to Hister (POST /api/add, Origin: hister://).
#pragma once

#include <Window.h>

class BButton;
class BStringView;
class BTextControl;

class SaveWindow : public BWindow {
public:
	SaveWindow(const char* url, const char* title, const char* label);

	void MessageReceived(BMessage* message) override;

private:
	void Save();
	void TakeURL(const char* url);

	BTextControl* fURL;
	BTextControl* fTitle;
	BTextControl* fLabel;
	BStringView* fStatus;
	BButton* fSave;
};

// A web address on the clipboard (text/plain), or ''.
BString ClipboardURL();
