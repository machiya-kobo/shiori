// The search window: query field, pills, the Notes pill's vault, results,
// status line. A search runs on Return or a pill, never while typing;
// clearing the field resets at once. "Show More…" pages on.
#pragma once

#include <string>
#include <vector>

#include <String.h>
#include <Window.h>

#include "../core/Query.h"
#include "../core/Results.h"

class BButton;
class BListView;
class BMenuField;
class BPopUpMenu;
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
	void LoadMore();
	void ShowResults(BMessage* message);
	void ClearList();
	void OpenSelected();
	const shiori::Result* SelectedResult() const;
	void SetPill(shiori::Pill pill);
	void LoadVaults();
	void ShowVaults(BMessage* message);

	BTextControl* fQuery;
	BButton* fPills[4];
	BMenuField* fVaultField;
	BPopUpMenu* fVaultMenu;
	BListView* fList;
	BStringView* fStatus;
	shiori::Pill fPill = shiori::Pill::All;
	int32 fGeneration = 0;
	bool fLoadingMore = false;

	// The search on screen, for its next page.
	std::string fShownQuery;
	shiori::Pill fShownPill = shiori::Pill::All;
	std::string fHisterNext;   // Hister's page_key, '' at the end
	int fKuraNext = 0;         // Kura's next offset, 0 at the end
	int fPagesTotal = 0, fNotesTotal = 0, fPagesShown = 0, fNotesShown = 0;

	// The Notes pill's vault: "all" or one name (Kura's /api/vaults).
	std::string fVault = "all";
	std::vector<shiori::Vault> fVaults;
};
