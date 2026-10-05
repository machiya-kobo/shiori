// The search window: query field, pills, results, status line.
#pragma once

#include <String.h>
#include <Window.h>

#include "../core/Query.h"
#include "../core/Results.h"

class BButton;
class BListView;
class BMessageRunner;
class BStringView;
class BTextControl;

class SearchWindow : public BWindow {
public:
	SearchWindow();
	~SearchWindow() override;

	void MessageReceived(BMessage* message) override;
	bool QuitRequested() override;

	void SetQuery(const char* text);

private:
	void StartSearch();
	void ShowResults(BMessage* message);
	void OpenSelected();
	const shiori::Result* SelectedResult() const;
	void SetPill(shiori::Pill pill);

	BTextControl* fQuery;
	BButton* fPills[4];
	BListView* fList;
	BStringView* fStatus;
	BMessageRunner* fDebounce = nullptr;
	shiori::Pill fPill = shiori::Pill::All;
	int32 fGeneration = 0;
	BString fLastSearch;  // query and pill of the search last started
};
