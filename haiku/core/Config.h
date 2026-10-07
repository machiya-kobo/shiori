// Shiori's settings on Haiku: ~/config/settings/Shiori/config.json, mode
// 0600, with Linux's keys (server, histerToken, kura, roomToken, notesSource), and the
// rules for which request carries which credential (linux/src/hister.js,
// linux/src/machiya.js):
// - Hister's token goes only to the configured Hister origin, as X-Access-Token.
// - Signed in, Hister also gets its session as Cookie: hister=…
// - Kura gets the sign-in's id (mhs_…) or else a room token (mht_…) as
//   Authorization: Bearer, or nothing. Never Hister's token or session.
// - Any other host is refused; a request with a credential follows no redirect.
#pragma once

#include <string>
#include <utility>
#include <vector>

#include "SignIn.h"

namespace shiori {

struct Config {
	std::string server;       // Hister, e.g. https://hister.example.ts.net/
	std::string histerToken;  // Hister's access token
	std::string kura;         // Kura, e.g. https://kura.example.ts.net/
	std::string roomToken;    // mht_… (Kura only)
	// Where notes come from: '' until chosen, "kura" or "hister" (NotesSource).
	std::string notesSource;
	// Not in config.json: sign-in.json's (LoadSignIn), for this server.
	SignIn signIn;
};

typedef std::vector<std::pair<std::string, std::string>> Headers;

// search-core's machiyaOrigin: "scheme://host[:port]" lowercased, the
// default port dropped; '' for anything not http(s) or with a user/password.
std::string OriginOf(const std::string& url);

// search-core's histerToken: 8 to 512 printable ASCII characters, else ''.
std::string CheckedHisterToken(const std::string& raw);
// A room token (mht_ and 43 base64url characters), else ''.
std::string CheckedRoomToken(const std::string& raw);

// Whether the app may call `url` at all: its origin is Hister's or Kura's.
bool IsConfiguredOrigin(const Config& config, const std::string& url);
// The credential headers a request to `url` gets (none, or exactly one).
Headers CredentialHeaders(const Config& config, const std::string& url);

// Whether notes come from Hister (the default vault's, Kura's push): chosen,
// or no Kura to ask (NotesSource, scripts/notes-source-cases.json).
bool NotesFromHister(const Config& config);

// config.json's content and back. Unknown keys are dropped.
std::string ConfigToJSON(const Config& config);
bool ConfigFromJSON(const std::string& text, Config& config);

// File I/O (POSIX): Save writes a temporary file 0600, then renames it.
bool LoadConfig(const std::string& path, Config& config, std::string* error = nullptr);
bool SaveConfig(const std::string& path, const Config& config, std::string* error = nullptr);
// The file's permission bits, or -1 when it doesn't exist.
int ConfigMode(const std::string& path);

}  // namespace shiori
