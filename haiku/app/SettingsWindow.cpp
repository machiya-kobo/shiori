#include "SettingsWindow.h"

#include <cstring>
#include <string>
#include <thread>

#include <Application.h>
#include <Button.h>
#include <CheckBox.h>
#include <LayoutBuilder.h>
#include <MenuField.h>
#include <MenuItem.h>
#include <PopUpMenu.h>
#include <StringView.h>
#include <TextControl.h>

#include "../core/Config.h"
#include "../core/Query.h"
#include "../core/SignIn.h"
#include "DeskbarView.h"
#include "Http.h"
#include "Shiori.h"
#include "SignInWindow.h"

using namespace shiori;

namespace {

const uint32 kMsgAvailability = 'Savl';
const uint32 kMsgNotesFrom = 'Snfr';

std::string Base(const std::string& server)
{
	std::string base = Trim(server);
	if (!base.empty() && base.back() != '/')
		base += '/';
	return base;
}

// Sign-in is offered only while the helper says Hister has users.
void CheckAvailability(BMessenger target, Config config)
{
	BMessage done(kMsgAvailability);
	bool offered = false;
	if (!OriginOf(config.server).empty()) {
		HttpReply reply = HttpRequestJSON(config, "GET", Base(config.server) + "machiya/healthz",
			std::string(), false, false);
		offered = SignInAvailable(reply.status, reply.body);
	}
	done.AddBool("offered", offered);
	target.SendMessage(&done);
}

// The helper ends the session everywhere (Hister's too); the file goes either way.
void RunSignOut(BMessenger target, Config config)
{
	if (config.signIn.IsSet()) {
		Headers bearer;
		bearer.emplace_back("Authorization", "Bearer " + config.signIn.sid);
		HttpRequestJSON(config, "POST", Base(config.server) + "machiya/signout", std::string(),
			false, false, bearer);
	}
	RemoveSignIn(SignInPath());
	target.SendMessage(kMsgSignedOut);
}

// Show() and Hide() nest (a count, not a flag): only change what differs.
void SetVisible(BView* view, bool visible)
{
	if (view->IsHidden(view) == visible) {
		if (visible)
			view->Show();
		else
			view->Hide();
	}
}

}  // namespace

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
	// Notes From: Kura, or Hister (the default vault's notes, as Kura pushes
	// them). It shows the source in use: Kura when one is set up, until the
	// person picks.
	BPopUpMenu* notesMenu = new BPopUpMenu("notesFrom");
	bool fromHister = NotesFromHister(config);
	const char* const kSources[] = {"kura", "hister"};
	const char* const kLabels[] = {"Kura", "Hister"};
	for (int i = 0; i < 2; i++) {
		BMessage* pick = new BMessage(kMsgNotesFrom);
		pick->AddString("source", kSources[i]);
		BMenuItem* item = new BMenuItem(kLabels[i], pick);
		item->SetMarked((i == 1) == fromHister);
		notesMenu->AddItem(item);
	}
	fNotesFrom = new BMenuField("notesFrom", "Notes from:", notesMenu);
	BStringView* notesHint = new BStringView("notesHint",
		"From Hister: your default vault's notes only.");
	BStringView* hint = new BStringView("hint",
		"Hister's token goes only to Hister. Kura takes the sign-in or a room token (mht_" B_UTF8_ELLIPSIS "), never Hister's.");
	fAccount = new BStringView("account", "");
	fAccount->SetExplicitMaxSize(BSize(B_SIZE_UNLIMITED, B_SIZE_UNSET));
	fAccountButton = new BButton("accountButton", "Sign In" B_UTF8_ELLIPSIS, new BMessage(kMsgOpenSignIn));
	fDeskbar = new BCheckBox("deskbar", "Show in Deskbar", new BMessage(kMsgDeskbarToggle));
	fDeskbar->SetValue(InDeskbar() ? B_CONTROL_ON : B_CONTROL_OFF);
	BButton* save = new BButton("save", "Save", new BMessage(kMsgDoStoreSettings));
	BButton* cancel = new BButton("cancel", "Cancel", new BMessage(B_QUIT_REQUESTED));

	BLayoutBuilder::Group<>(this, B_VERTICAL)
		.SetInsets(B_USE_WINDOW_SPACING)
		.AddGrid(B_USE_SMALL_SPACING, B_USE_SMALL_SPACING)
			.AddTextControl(fServer, 0, 0)
			.AddTextControl(fHisterToken, 0, 1)
			.AddTextControl(fKura, 0, 2)
			.AddTextControl(fRoomToken, 0, 3)
			.AddMenuField(fNotesFrom, 0, 4)
		.End()
		.Add(notesHint)
		.Add(hint)
		.AddGroup(B_HORIZONTAL)
			.Add(fAccount)
			.AddGlue()
			.Add(fAccountButton)
		.End()
		.Add(fDeskbar)
		.Add(fStatus)
		.AddGroup(B_HORIZONTAL)
			.AddGlue()
			.Add(cancel)
			.Add(save)
		.End();
	fServer->TextView()->SetExplicitMinSize(BSize(320, B_SIZE_UNSET));
	SetDefaultButton(save);
	ShowAccount();
	std::thread(CheckAvailability, BMessenger(this), config).detach();
}

void SettingsWindow::ShowAccount()
{
	Config config = CurrentConfig();
	if (config.signIn.IsSet()) {
		std::string who = "Signed in to Hister";
		if (!config.signIn.username.empty())
			who += " as " + config.signIn.username;
		fAccount->SetText(who.c_str());
		fAccountButton->SetLabel("Sign Out");
		fAccountButton->SetMessage(new BMessage(kMsgSignOut));
		SetVisible(fAccount, true);
		SetVisible(fAccountButton, true);
		return;
	}
	fAccount->SetText("Hister has users: sign in to search as yours.");
	fAccountButton->SetLabel("Sign In" B_UTF8_ELLIPSIS);
	fAccountButton->SetMessage(new BMessage(kMsgOpenSignIn));
	// Hidden until the helper says Hister has users (it's inert otherwise).
	SetVisible(fAccount, fSignInOffered);
	SetVisible(fAccountButton, fSignInOffered);
}

void SettingsWindow::Store()
{
	Config config;
	config.server = Trim(fServer->Text());
	config.histerToken = Trim(fHisterToken->Text());
	config.kura = Trim(fKura->Text());
	config.roomToken = Trim(fRoomToken->Text());
	// Saved as a choice only once picked here; until then it follows Kura's address.
	config.notesSource = CurrentConfig().notesSource;
	if (fNotesChosen) {
		BMenuItem* marked = fNotesFrom->Menu()->FindMarked();
		const char* source = nullptr;
		if (marked != nullptr && marked->Message() != nullptr
			&& marked->Message()->FindString("source", &source) == B_OK && source != nullptr)
			config.notesSource = source;
	}
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
	// The sign-in belongs to its server: a new address leaves it behind.
	LoadSignIn(SignInPath(), config.server, config.signIn);
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
		case kMsgDeskbarToggle: {
			// At once, not on Save: it's the Deskbar's, not config.json's.
			status_t status = fDeskbar->Value() == B_CONTROL_ON ? AddToDeskbar() : RemoveFromDeskbar();
			if (status != B_OK && status != B_NAME_NOT_FOUND) {
				fStatus->SetText((std::string("The Deskbar said: ") + strerror(status)).c_str());
				fDeskbar->SetValue(InDeskbar() ? B_CONTROL_ON : B_CONTROL_OFF);
			}
			break;
		}
		case kMsgNotesFrom:
			fNotesChosen = true;
			break;
		case kMsgAvailability:
			fSignInOffered = message->GetBool("offered", false);
			ShowAccount();
			break;
		case kMsgOpenSignIn: {
			SignInWindow* window = new SignInWindow(BMessenger(this));
			window->Show();
			break;
		}
		case kMsgAccountChanged:
			ShowAccount();
			break;
		case kMsgSignOut:
			fAccountButton->SetEnabled(false);
			fAccount->SetText("Signing out" B_UTF8_ELLIPSIS);
			std::thread(RunSignOut, BMessenger(this), CurrentConfig()).detach();
			break;
		case kMsgSignedOut: {
			Config config = CurrentConfig();
			config.signIn = SignIn();
			SetCurrentConfig(config);
			be_app->PostMessage(kMsgConfigChanged);
			fAccountButton->SetEnabled(true);
			ShowAccount();
			break;
		}
		default:
			BWindow::MessageReceived(message);
	}
}
