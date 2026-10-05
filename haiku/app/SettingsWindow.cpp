#include "SettingsWindow.h"

#include <Application.h>
#include <Button.h>
#include <LayoutBuilder.h>
#include <StringView.h>
#include <TextControl.h>

#include "../core/Config.h"
#include "../core/Query.h"
#include "Shiori.h"

using namespace shiori;

SettingsWindow::SettingsWindow()
	:
	BWindow(BRect(160, 160, 700, 360), "Shiori settings", B_TITLED_WINDOW,
		B_AUTO_UPDATE_SIZE_LIMITS | B_ASYNCHRONOUS_CONTROLS | B_NOT_ZOOMABLE | B_CLOSE_ON_ESCAPE)
{
	Config config = CurrentConfig();
	fServer = new BTextControl("server", "Hister:", config.server.c_str(), NULL);
	fHisterToken = new BTextControl("histerToken", "Hister token:", config.histerToken.c_str(), NULL);
	fKura = new BTextControl("kura", "Kura:", config.kura.c_str(), NULL);
	fRoomToken = new BTextControl("roomToken", "Room token:", config.roomToken.c_str(), NULL);
	fHisterToken->TextView()->HideTyping(true);
	fRoomToken->TextView()->HideTyping(true);
	// HideTyping() drops the text: put it back.
	fHisterToken->SetText(config.histerToken.c_str());
	fRoomToken->SetText(config.roomToken.c_str());

	BString where("Stored in ");
	where << ConfigPath().c_str();
	int mode = ConfigMode(ConfigPath());
	if (mode >= 0 && (mode & 077) != 0)
		where << " (others can read it: Save sets it to 0600)";
	fStatus = new BStringView("status", where.String());
	BStringView* hint = new BStringView("hint",
		"Hister's token goes only to Hister. Kura takes a room token (mht_" B_UTF8_ELLIPSIS ") or nothing.");
	BButton* save = new BButton("save", "Save", new BMessage(kMsgDoStoreSettings));
	BButton* cancel = new BButton("cancel", "Cancel", new BMessage(B_QUIT_REQUESTED));

	BLayoutBuilder::Group<>(this, B_VERTICAL)
		.SetInsets(B_USE_WINDOW_SPACING)
		.AddGrid(B_USE_SMALL_SPACING, B_USE_SMALL_SPACING)
			.AddTextControl(fServer, 0, 0)
			.AddTextControl(fHisterToken, 0, 1)
			.AddTextControl(fKura, 0, 2)
			.AddTextControl(fRoomToken, 0, 3)
		.End()
		.Add(hint)
		.Add(fStatus)
		.AddGroup(B_HORIZONTAL)
			.AddGlue()
			.Add(cancel)
			.Add(save)
		.End();
	fServer->TextView()->SetExplicitMinSize(BSize(320, B_SIZE_UNSET));
	SetDefaultButton(save);
}

void SettingsWindow::Store()
{
	Config config;
	config.server = Trim(fServer->Text());
	config.histerToken = Trim(fHisterToken->Text());
	config.kura = Trim(fKura->Text());
	config.roomToken = Trim(fRoomToken->Text());
	if (!config.server.empty() && OriginOf(config.server).empty()) {
		fStatus->SetText("Hister's address must start with http:// or https://.");
		return;
	}
	if (!config.kura.empty() && OriginOf(config.kura).empty()) {
		fStatus->SetText("Kura's address must start with http:// or https://.");
		return;
	}
	if (!config.histerToken.empty() && CheckedHisterToken(config.histerToken).empty()) {
		fStatus->SetText("That Hister token isn't one (8 to 512 characters, no spaces).");
		return;
	}
	if (!config.roomToken.empty() && CheckedRoomToken(config.roomToken).empty()) {
		fStatus->SetText("A room token starts with mht_ (Hister's own token never goes to Kura).");
		return;
	}
	std::string error;
	if (!SaveConfig(ConfigPath(), config, &error)) {
		fStatus->SetText((std::string("Couldn't save: ") + error).c_str());
		return;
	}
	SetCurrentConfig(config);
	be_app->PostMessage(kMsgConfigChanged);
	Quit();
}

void SettingsWindow::MessageReceived(BMessage* message)
{
	switch (message->what) {
		case kMsgDoStoreSettings:
			Store();
			break;
		default:
			BWindow::MessageReceived(message);
	}
}
