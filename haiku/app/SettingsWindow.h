// Server addresses and tokens, kept in ~/config/settings/Shiori/config.json (0600).
#pragma once

#include <Window.h>

class BStringView;
class BTextControl;

class SettingsWindow : public BWindow {
public:
	SettingsWindow();
	void MessageReceived(BMessage* message) override;

private:
	void Store();

	BTextControl* fServer;
	BTextControl* fHisterToken;
	BTextControl* fKura;
	BTextControl* fRoomToken;
	BStringView* fStatus;
};
