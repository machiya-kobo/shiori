// Sign in to Hister (docs/signing-in.md): name and password, Hister's own
// login, then the sign-in helper's id, kept in sign-in.json (0600).
#pragma once

#include <Messenger.h>
#include <Window.h>

class BButton;
class BStringView;
class BTextControl;

class SignInWindow : public BWindow {
public:
	// `notify` hears kMsgAccountChanged once signed in (the Settings window).
	explicit SignInWindow(BMessenger notify);
	void MessageReceived(BMessage* message) override;

private:
	void SignIn();

	BMessenger fNotify;
	BTextControl* fName;
	BTextControl* fPassword;
	BStringView* fStatus;
	BButton* fSignIn;
};
