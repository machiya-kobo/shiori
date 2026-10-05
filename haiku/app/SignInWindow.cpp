#include "SignInWindow.h"

#include <string>
#include <thread>
#include <unistd.h>

#include <Application.h>
#include <Button.h>
#include <LayoutBuilder.h>
#include <StringView.h>
#include <TextControl.h>

#include "../core/Config.h"
#include "../core/Query.h"
#include "../core/SignIn.h"
#include "Http.h"
#include "Shiori.h"

using namespace shiori;

namespace {

std::string Base(const std::string& server)
{
	std::string base = Trim(server);
	if (!base.empty() && base.back() != '/')
		base += '/';
	return base;
}

// Hister's login, then the helper's trade of the session for an id. The
// password stays in this thread and is never kept. Answers kMsgSignedIn with
// "error" empty when signed in (sign-in.json written).
void RunSignIn(BMessenger target, Config config, std::string name, std::string password)
{
	BMessage done(kMsgSignedIn);
	std::string base = Base(config.server);
	// No credential of the config's on either call: Hister's login, then a
	// trade the helper checks by the session alone.
	HttpReply login = HttpRequestJSON(config, "POST", base + "api/login", LoginBody(name, password), true, false);
	password.assign(password.size(), '\0');
	if (login.status == 0) {
		done.AddString("error", TransportProblem("Hister", login.error).c_str());
		target.SendMessage(&done);
		return;
	}
	std::string session = login.status == 200 ? SessionFromSetCookie(login.setCookies) : "";
	if (session.empty()) {
		done.AddString("error", LoginProblem(login.status == 200 ? 500 : login.status).c_str());
		target.SendMessage(&done);
		return;
	}
	char host[256] = "Haiku";
	gethostname(host, sizeof host - 1);
	HttpReply trade = HttpRequestJSON(config, "POST", base + "machiya/api/app-session",
		AppSessionBody(session, std::string("Shiori on ") + host), false, false);
	SignIn signIn;
	if (trade.status != 200 || !SignInFromTrade(trade.body, session, signIn)) {
		// The helper didn't take it: log Hister's session out, so none is left behind.
		Config out = config;
		out.signIn = SignIn();
		out.signIn.session = session;
		HttpRequestJSON(out, "POST", base + "api/logout", std::string(), true);
		done.AddString("error", LoginProblem(trade.status == 401 ? 401 : 500).c_str());
		target.SendMessage(&done);
		return;
	}
	std::string error;
	if (!SaveSignIn(SignInPath(), config.server, signIn, &error))
		done.AddString("error", (std::string("Couldn't keep the sign-in: ") + error).c_str());
	else
		done.AddString("error", "");
	target.SendMessage(&done);
}

}  // namespace

SignInWindow::SignInWindow(BMessenger notify)
	:
	BWindow(BRect(200, 200, 560, 340), "Sign in to Hister", B_TITLED_WINDOW,
		B_AUTO_UPDATE_SIZE_LIMITS | B_ASYNCHRONOUS_CONTROLS | B_NOT_ZOOMABLE | B_NOT_RESIZABLE | B_CLOSE_ON_ESCAPE),
	fNotify(notify)
{
	fName = new BTextControl("name", "Name:", "", NULL);
	fPassword = new BTextControl("password", "Password:", "", NULL);
	fPassword->TextView()->HideTyping(true);
	fStatus = new BStringView("status", "Your Hister user's name and password.");
	fStatus->SetExplicitMaxSize(BSize(B_SIZE_UNLIMITED, B_SIZE_UNSET));
	fSignIn = new BButton("signIn", "Sign In", new BMessage(kMsgDoSignIn));
	BButton* cancel = new BButton("cancel", "Cancel", new BMessage(B_QUIT_REQUESTED));

	BLayoutBuilder::Group<>(this, B_VERTICAL)
		.SetInsets(B_USE_WINDOW_SPACING)
		.AddGrid(B_USE_SMALL_SPACING, B_USE_SMALL_SPACING)
			.AddTextControl(fName, 0, 0)
			.AddTextControl(fPassword, 0, 1)
		.End()
		.Add(fStatus)
		.AddGroup(B_HORIZONTAL)
			.AddGlue()
			.Add(cancel)
			.Add(fSignIn)
		.End();
	fName->TextView()->SetExplicitMinSize(BSize(200, B_SIZE_UNSET));
	SetDefaultButton(fSignIn);
	fName->MakeFocus(true);
}

void SignInWindow::SignIn()
{
	Config config = CurrentConfig();
	if (OriginOf(config.server).empty()) {
		fStatus->SetText("Set Hister's address in Settings first.");
		return;
	}
	std::string name = Trim(fName->Text());
	std::string password = fPassword->Text();
	if (name.empty() || password.empty()) {
		fStatus->SetText("Type your name and password.");
		return;
	}
	fSignIn->SetEnabled(false);
	fStatus->SetText("Signing in" B_UTF8_ELLIPSIS);
	std::thread(RunSignIn, BMessenger(this), config, name, password).detach();
	// The field forgets it at once.
	fPassword->SetText("");
}

void SignInWindow::MessageReceived(BMessage* message)
{
	switch (message->what) {
		case kMsgDoSignIn:
			SignIn();
			break;
		case kMsgSignedIn: {
			BString error = message->GetString("error", "");
			fSignIn->SetEnabled(true);
			if (!error.IsEmpty()) {
				fStatus->SetText(error.String());
				break;
			}
			Config config = CurrentConfig();
			LoadSignIn(SignInPath(), config.server, config.signIn);
			SetCurrentConfig(config);
			be_app->PostMessage(kMsgConfigChanged);
			fNotify.SendMessage(kMsgAccountChanged);
			Quit();
			break;
		}
		default:
			BWindow::MessageReceived(message);
	}
}
