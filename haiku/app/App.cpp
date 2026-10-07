// Shiori for Haiku: the application. It drains the outbox at start, after a
// settings change or a save that reached Hister, and every five minutes
// while pages wait.
//
//   Shiori                      the search window
//   Shiori --query <words>      the search window, searching
//   Shiori --save <url> [label] the Save window, filled in
//   Shiori --quick              the quick search (bind it in Shortcuts)
//   Shiori --deskbar            puts Shiori in the Deskbar (--no-deskbar takes it out)
#include <atomic>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <mutex>
#include <string>
#include <thread>

#include <Alert.h>
#include <Application.h>
#include <FindDirectory.h>
#include <MessageRunner.h>
#include <Path.h>
#include <Url.h>

#include "../core/Config.h"
#include "../core/Outbox.h"
#include "../core/Query.h"
#include "Http.h"
#include "../core/Results.h"
#include "DeskbarView.h"
#include "NoteWindow.h"
#include "QuickWindow.h"
#include "SaveWindow.h"
#include "SearchWindow.h"
#include "SettingsWindow.h"
#include "Shiori.h"

namespace {

std::mutex gConfigLock;
shiori::Config gConfig;
// The outbox's files are touched by save threads and the drain: one at a time.
std::mutex gOutboxLock;

}  // namespace

std::string ConfigPath()
{
	BPath path;
	if (find_directory(B_USER_SETTINGS_DIRECTORY, &path) != B_OK)
		path.SetTo("/boot/home/config/settings");
	path.Append("Shiori/config.json");
	return path.Path();
}

std::string SignInPath()
{
	BPath path;
	if (find_directory(B_USER_SETTINGS_DIRECTORY, &path) != B_OK)
		path.SetTo("/boot/home/config/settings");
	path.Append("Shiori/sign-in.json");
	return path.Path();
}

std::string OutboxPath()
{
	BPath path;
	if (find_directory(B_USER_SETTINGS_DIRECTORY, &path) != B_OK)
		path.SetTo("/boot/home/config/settings");
	path.Append("Shiori/outbox");
	return path.Path();
}

bool QueueSave(const std::string& url, const std::string& title, const std::string& label,
	std::string* error)
{
	shiori::QueuedPage page;
	page.url = url;
	page.title = title;
	page.label = label;
	std::lock_guard<std::mutex> lock(gOutboxLock);
	return shiori::Outbox(OutboxPath()).Enqueue(page, (int64_t)time(nullptr), error);
}

int WaitingCount()
{
	std::lock_guard<std::mutex> lock(gOutboxLock);
	return shiori::Outbox(OutboxPath()).Count();
}

namespace {

// Sends what waits, oldest first, with the settings of the moment (the
// outbox keeps no credential).
void RunDrain(BMessenger app)
{
	shiori::DrainResult result;
	int left = 0;
	{
		std::lock_guard<std::mutex> lock(gOutboxLock);
		shiori::Outbox box(OutboxPath());
		shiori::Config config = CurrentConfig();
		if (!shiori::OriginOf(config.server).empty() && box.Count() > 0) {
			result = box.Drain([&config](const shiori::QueuedPage& page) {
				return HttpRequestJSON(config, "POST", shiori::AddURL(config.server),
					shiori::NewPageJSON(page.url, page.title, page.label, SHIORI_VERSION, page.added), true).status;
			}, (int64_t)time(nullptr));
		}
		left = box.Count();
	}
	BMessage done(kMsgDrained);
	done.AddInt32("sent", result.sent);
	done.AddInt32("dropped", result.dropped);
	done.AddInt32("left", left);
	app.SendMessage(&done);
}

}  // namespace

shiori::Config CurrentConfig()
{
	std::lock_guard<std::mutex> lock(gConfigLock);
	return gConfig;
}

void SetCurrentConfig(const shiori::Config& config)
{
	std::lock_guard<std::mutex> lock(gConfigLock);
	gConfig = config;
}

bool OpenInBrowser(const std::string& url)
{
	// Only web addresses: never javascript:, file: or anything a page stored (SHIO-1).
	if (!shiori::IsWebURL(url))
		return false;
	BUrl target(url.c_str(), true);
	return target.IsValid() && target.OpenWithPreferredApplication(false) == B_OK;
}

bool OpenResult(const shiori::Result& result)
{
	// A note opens its preview: from Kura (by its path), or from Hister's
	// readable copy when notes come from Hister (by its address).
	shiori::Config config = CurrentConfig();
	bool fromHister = shiori::NotesFromHister(config);
	if (result.kind == shiori::Result::Note
		&& (fromHister ? !shiori::Trim(config.server).empty()
			: !result.path.empty() && !shiori::Trim(config.kura).empty())) {
		NoteWindow* window = new NoteWindow(result);
		window->Show();
		return true;
	}
	return OpenInBrowser(result.url);
}

class ShioriApp : public BApplication {
public:
	ShioriApp()
		:
		BApplication(SHIORI_SIGNATURE)
	{
		shiori::Config config;
		shiori::LoadConfig(ConfigPath(), config);
		// The Hister sign-in, if there's one for this server.
		shiori::LoadSignIn(SignInPath(), config.server, config.signIn);
		SetCurrentConfig(config);
	}

	void ReadyToRun() override
	{
		fSearch = new SearchWindow();
		fSearch->Show();
		// The first search: `--query`'s words, else the newest (an empty field
		// shows Kura's recent notes and Hister's newest pages).
		if (fSearch->Lock()) {
			fSearch->SetQuery(fPendingQuery.String());
			fSearch->Unlock();
		}
		shiori::Config config = CurrentConfig();
		if (shiori::Trim(config.server).empty() && shiori::Trim(config.kura).empty())
			OpenSettings();
		// What waits goes now, then every five minutes while something does.
		PostMessage(kMsgDrain);
		// Launched by the Deskbar item for a quick search: the main window
		// just took activation, so the quick search takes it back.
		if (fQuick.IsValid())
			PostMessage(kMsgQuickSearch);
		BMessage tick(kMsgDrain);
		fDrainTimer = new BMessageRunner(BMessenger(this), &tick, 5 * 60 * 1000000LL);
	}

	bool QuitRequested() override
	{
		delete fDrainTimer;
		fDrainTimer = nullptr;
		return BApplication::QuitRequested();
	}

	void ArgvReceived(int32 argc, char** argv) override
	{
		for (int32 i = 1; i < argc; i++) {
			BString arg(argv[i]);
			if (arg == "--save" && i + 1 < argc) {
				BMessage save(kMsgOpenSave);
				save.AddString("url", argv[++i]);
				if (i + 1 < argc && argv[i + 1][0] != '-')
					save.AddString("label", argv[++i]);
				PostMessage(&save);
			} else if (arg == "--quick") {
				PostMessage(kMsgQuickSearch);
			} else if (arg == "--deskbar" || arg == "--no-deskbar") {
				status_t status = arg == "--deskbar" ? AddToDeskbar() : RemoveFromDeskbar();
				if (status != B_OK && status != B_NAME_NOT_FOUND)
					fprintf(stderr, "Shiori: the Deskbar said %s\n", strerror(status));
			} else if (arg == "--query" && i + 1 < argc) {
				// Before ReadyToRun the window doesn't exist yet: it searches once shown.
				if (fSearch != nullptr && fSearch->Lock()) {
					fSearch->SetQuery(argv[++i]);
					fSearch->Unlock();
				} else {
					fPendingQuery = argv[++i];
				}
			}
		}
	}

	void MessageReceived(BMessage* message) override
	{
		switch (message->what) {
			case kMsgOpenSettings:
				OpenSettings();
				break;
			case kMsgOpenSave: {
				BString url = message->GetString("url", "");
				if (url.IsEmpty())
					url = ClipboardURL();
				SaveWindow* window = new SaveWindow(url.String(), message->GetString("title", ""),
					message->GetString("label", ""));
				window->Show();
				break;
			}
			case kMsgConfigChanged:
				if (fSearch != nullptr)
					BMessenger(fSearch).SendMessage(kMsgConfigChanged);
				// New settings or a sign-in: what waits may go now.
				PostMessage(kMsgDrain);
				break;
			case kMsgQuickSearch: {
				// One quick search at a time: bring it forward if it's open.
				if (fQuick.IsValid() && fQuick.LockTarget()) {
					BLooper* looper = nullptr;
					BWindow* window = dynamic_cast<BWindow*>(fQuick.Target(&looper));
					if (window != nullptr) {
						window->Activate();
						window->Unlock();
						break;
					}
					if (looper != nullptr)
						looper->Unlock();
				}
				QuickWindow* quick = new QuickWindow();
				fQuick = BMessenger(quick);
				quick->Show();
				break;
			}
			case kMsgShowMain:
				if (fSearch != nullptr)
					fSearch->Activate();
				break;
			case kMsgShowQuery:
				if (fSearch != nullptr && fSearch->Lock()) {
					fSearch->SetQuery(message->GetString("query", ""));
					fSearch->Activate();
					fSearch->Unlock();
				}
				break;
			case kMsgDrain:
				if (!fDraining) {
					fDraining = true;
					std::thread(RunDrain, BMessenger(this)).detach();
				}
				break;
			case kMsgDrained:
				fDraining = false;
				break;
			default:
				BApplication::MessageReceived(message);
		}
	}

	void AboutRequested() override
	{
		BAlert* about = new BAlert("About", "Shiori for Haiku " SHIORI_VERSION "\n\n"
			"Search Hister and Kura (Machiya).", "OK");
		about->Go(NULL);
	}

private:
	void OpenSettings()
	{
		SettingsWindow* window = new SettingsWindow();
		window->Show();
	}

	SearchWindow* fSearch = nullptr;
	BMessenger fQuick;
	BString fPendingQuery;
	BMessageRunner* fDrainTimer = nullptr;
	bool fDraining = false;
};

int main()
{
	ShioriApp app;
	app.Run();
	return 0;
}
