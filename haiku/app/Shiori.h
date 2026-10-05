// Shiori for Haiku: shared bits of the Be API side.
#pragma once

#include <string>

#include <String.h>

#include "../core/Config.h"

#define SHIORI_SIGNATURE "application/x-vnd.machiya-kobo.shiori"
#define SHIORI_VERSION "0.1.0-proto"

enum {
	// App
	kMsgOpenSettings = 'Sset',
	kMsgOpenSave = 'Ssav',
	kMsgConfigChanged = 'Scfg',
	kMsgWindowClosed = 'Swcl',

	// Search window
	kMsgQueryChanged = 'Sqch',
	kMsgSearchNow = 'Sqgo',
	kMsgPill = 'Spil',
	kMsgResults = 'Sres',
	kMsgOpenResult = 'Sopn',
	kMsgCopyLink = 'Scpy',
	kMsgSaveResult = 'Ssvr',

	// Save and Settings windows
	kMsgDoSave = 'Sdsv',
	kMsgSaved = 'Ssvd',
	kMsgDoStoreSettings = 'Sdst',
	kMsgCancel = 'Scnc',

	// Signing in to Hister
	kMsgOpenSignIn = 'Ssin',
	kMsgDoSignIn = 'Sdsi',
	kMsgSignedIn = 'Ssid',
	kMsgSignOut = 'Ssou',
	kMsgSignedOut = 'Ssod',
	kMsgAccountChanged = 'Sacc',
};

// ~/config/settings/Shiori/config.json
std::string ConfigPath();
// ~/config/settings/Shiori/sign-in.json (the Hister sign-in: session and id, 0600)
std::string SignInPath();

// The app's current settings (a copy; the app owns them).
shiori::Config CurrentConfig();
void SetCurrentConfig(const shiori::Config& config);

// Opens a web address in the preferred browser (WebPositive); only http(s).
bool OpenInBrowser(const std::string& url);
