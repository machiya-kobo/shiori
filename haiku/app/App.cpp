// Shiori for Haiku: the application.
//
//   Shiori                      the search window
//   Shiori --query <words>      the search window, searching
//   Shiori --save <url> [label] the Save window, filled in
#include <mutex>
#include <string>

#include <Alert.h>
#include <Application.h>
#include <FindDirectory.h>
#include <Path.h>
#include <Url.h>

#include "../core/Config.h"
#include "../core/Query.h"
#include "SaveWindow.h"
#include "SearchWindow.h"
#include "SettingsWindow.h"
#include "Shiori.h"

namespace {

std::mutex gConfigLock;
shiori::Config gConfig;

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
		if (!fPendingQuery.IsEmpty()) {
			fSearch->Lock();
			fSearch->SetQuery(fPendingQuery.String());
			fSearch->Unlock();
		}
		shiori::Config config = CurrentConfig();
		if (shiori::Trim(config.server).empty() && shiori::Trim(config.kura).empty())
			OpenSettings();
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
	BString fPendingQuery;
};

int main()
{
	ShioriApp app;
	app.Run();
	return 0;
}
