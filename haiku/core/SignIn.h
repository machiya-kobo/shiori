// Signing in to Hister (docs/signing-in.md, as Linux does it: linux/src/hister.js):
// Hister's own login (POST /api/login) sets a session cookie, which the sign-in
// helper on Hister's host trades for an id (POST /machiya/api/app-session).
// Both are kept in ~/config/settings/Shiori/sign-in.json (0600), tied to the
// server's origin: the session goes only to that server as `Cookie: hister=…`,
// the id only to the rooms as `Authorization: Bearer mhs_…`. Sign-out ends both
// through the helper (POST /machiya/signout). Portable: no Be headers.
#pragma once

#include <string>
#include <vector>

namespace shiori {

struct SignIn {
	std::string session;   // Hister's session: 43 base64url characters
	std::string sid;       // the helper's id: mhs_ and 43 base64url characters
	std::string username;  // who, for the window (at most 64 characters)

	bool IsSet() const { return !session.empty() && !sid.empty(); }
};

// A Hister session value, checked; '' for anything else.
std::string CheckedHisterSession(const std::string& raw);
// The helper's id (mhs_…), checked; '' for anything else.
std::string CheckedSessionID(const std::string& raw);

// sign-in.json's content for `server`: false unless it's for that server's
// origin and both values are sound.
bool SignInFromJSON(const std::string& text, const std::string& server, SignIn& out);
std::string SignInToJSON(const std::string& server, const SignIn& signIn);

// Hister's session from its Set-Cookie values (one that clears it skipped), else ''.
std::string SessionFromSetCookie(const std::vector<std::string>& values);

// The bodies: Hister's login, and the helper's trade (label: who's asking, at most 80).
std::string LoginBody(const std::string& username, const std::string& password);
std::string AppSessionBody(const std::string& session, const std::string& label);

// The helper's answer to the trade: {sid, username}; false unless the id is sound.
bool SignInFromTrade(const std::string& body, const std::string& session, SignIn& out);

// Sign-in is offered only when the helper's /machiya/healthz says Hister has users.
bool SignInAvailable(int status, const std::string& body);

// The login's answer in words, for the window.
std::string LoginProblem(int status);

// File I/O (POSIX), as SaveConfig: 0600, written then renamed.
bool LoadSignIn(const std::string& path, const std::string& server, SignIn& out);
bool SaveSignIn(const std::string& path, const std::string& server, const SignIn& signIn, std::string* error = nullptr);
bool RemoveSignIn(const std::string& path);

}  // namespace shiori
