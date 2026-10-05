// Server addresses and tokens, kept in ~/config/settings/Shiori/config.json (0600),
// and the Hister sign-in (sign-in.json), offered while Hister has users.
#pragma once

#include <Window.h>

class BButton;
class BCheckBox;
class BStringView;
class BTextControl;

class SettingsWindow : public BWindow {
public:
	SettingsWindow();
	void MessageReceived(BMessage* message) override;

private:
	void Store();
	void ShowAccount();

	bool fSignInOffered = false;
	BStringView* fAccount;
	BButton* fAccountButton;
	BCheckBox* fDeskbar;
	BTextControl* fServer;
	BTextControl* fHisterToken;
	BTextControl* fKura;
	BTextControl* fRoomToken;
	BStringView* fStatus;
};
