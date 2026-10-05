// Quick search (from the Deskbar, or `Shiori --quick`, which a shortcut in
// the Shortcuts preferences can run): a small floating window with a field
// and the top results of All. Return searches; ↓ moves into the results;
// Return there opens one (a note's preview, a page in the browser) and
// closes; Escape closes; Command-Return opens the search in Shiori's window.
#pragma once

#include <Window.h>

class BListView;
class BStringView;
class QuickField;

class QuickWindow : public BWindow {
public:
	QuickWindow();
	~QuickWindow() override;

	void MessageReceived(BMessage* message) override;

private:
	void Search();
	void ClearList();

	QuickField* fQuery;
	BListView* fList;
	BStringView* fStatus;
	int32 fGeneration = 0;
};
