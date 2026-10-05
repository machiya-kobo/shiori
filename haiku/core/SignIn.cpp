#include "SignIn.h"

#include <cerrno>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include "Config.h"
#include "Json.h"

namespace shiori {

static bool IsBase64URL(char c)
{
	return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-';
}

static std::string Trimmed(const std::string& s)
{
	size_t a = s.find_first_not_of(" \t\r\n");
	if (a == std::string::npos)
		return "";
	size_t b = s.find_last_not_of(" \t\r\n");
	return s.substr(a, b - a + 1);
}

static bool Is43(const std::string& s, size_t from)
{
	if (s.size() != from + 43)
		return false;
	for (size_t i = from; i < s.size(); i++) {
		if (!IsBase64URL(s[i]))
			return false;
	}
	return true;
}

std::string CheckedHisterSession(const std::string& raw)
{
	std::string s = Trimmed(raw);
	return Is43(s, 0) ? s : "";
}

std::string CheckedSessionID(const std::string& raw)
{
	std::string s = Trimmed(raw);
	return s.compare(0, 4, "mhs_") == 0 && Is43(s, 4) ? s : "";
}

bool SignInFromJSON(const std::string& text, const std::string& server, SignIn& out)
{
	json::Value v;
	if (!json::Parse(text, v) || !v.IsObject())
		return false;
	std::string origin = OriginOf(server);
	if (origin.empty() || OriginOf(v["server"].Str()) != origin)
		return false;
	SignIn s;
	s.session = CheckedHisterSession(v["session"].Str());
	s.sid = CheckedSessionID(v["sid"].Str());
	s.username = v["username"].Str().substr(0, 64);
	if (!s.IsSet())
		return false;
	out = s;
	return true;
}

std::string SignInToJSON(const std::string& server, const SignIn& signIn)
{
	return std::string("{\n")
		+ "  \"server\": " + json::Quote(OriginOf(server)) + ",\n"
		+ "  \"session\": " + json::Quote(signIn.session) + ",\n"
		+ "  \"sid\": " + json::Quote(signIn.sid) + ",\n"
		+ "  \"username\": " + json::Quote(signIn.username) + "\n"
		+ "}\n";
}

std::string SessionFromSetCookie(const std::vector<std::string>& values)
{
	for (const std::string& value : values) {
		size_t semi = value.find(';');
		std::string pair = value.substr(0, semi);
		size_t eq = pair.find('=');
		if (eq == std::string::npos || Trimmed(pair.substr(0, eq)) != "hister")
			continue;
		// One that clears the cookie (Max-Age=0) isn't a session.
		bool clears = false;
		std::string attrs = semi == std::string::npos ? "" : value.substr(semi);
		for (size_t i = 0; i < attrs.size(); i++)
			attrs[i] = (char)tolower((unsigned char)attrs[i]);
		size_t at = attrs.find("max-age");
		if (at != std::string::npos) {
			size_t e = attrs.find('=', at);
			if (e != std::string::npos && Trimmed(attrs.substr(e + 1, attrs.find(';', e) - e - 1)) == "0")
				clears = true;
		}
		if (clears)
			continue;
		std::string session = CheckedHisterSession(pair.substr(eq + 1));
		if (!session.empty())
			return session;
	}
	return "";
}

std::string LoginBody(const std::string& username, const std::string& password)
{
	json::Value body = json::Value::MakeObject();
	body.Set("username", json::Value::MakeString(username));
	body.Set("password", json::Value::MakeString(password));
	return json::Write(body);
}

std::string AppSessionBody(const std::string& session, const std::string& label)
{
	json::Value body = json::Value::MakeObject();
	body.Set("hister", json::Value::MakeString(session));
	body.Set("label", json::Value::MakeString(label.substr(0, 80)));
	return json::Write(body);
}

bool SignInFromTrade(const std::string& body, const std::string& session, SignIn& out)
{
	json::Value v;
	if (!json::Parse(body, v) || !v.IsObject())
		return false;
	SignIn s;
	s.session = CheckedHisterSession(session);
	s.sid = CheckedSessionID(v["sid"].Str());
	s.username = v["username"].Str().substr(0, 64);
	if (!s.IsSet())
		return false;
	out = s;
	return true;
}

bool SignInAvailable(int status, const std::string& body)
{
	if (status != 200)
		return false;
	json::Value v;
	if (!json::Parse(body, v) || !v.IsObject())
		return false;
	return v["ok"].type == json::Value::Bool && v["ok"].boolean && v["hister"].Str() == "ok";
}

std::string LoginProblem(int status)
{
	if (status == 401)
		return "Hister didn't recognise that name and password.";
	if (status == 403)
		return "This Hister signs in only through its sign-in provider: sign in from the web app instead.";
	return "Sign-in is unavailable right now: Hister or its sign-in helper isn't answering.";
}

bool LoadSignIn(const std::string& path, const std::string& server, SignIn& out)
{
	FILE* f = fopen(path.c_str(), "rb");
	if (f == nullptr)
		return false;
	std::string text;
	char buffer[4096];
	size_t n;
	while ((n = fread(buffer, 1, sizeof buffer, f)) > 0)
		text.append(buffer, n);
	fclose(f);
	return SignInFromJSON(text, server, out);
}

bool SaveSignIn(const std::string& path, const std::string& server, const SignIn& signIn, std::string* error)
{
	size_t slash = path.rfind('/');
	if (slash != std::string::npos && slash > 0) {
		std::string dir = path.substr(0, slash);
		if (mkdir(dir.c_str(), 0700) != 0 && errno != EEXIST) {
			if (error != nullptr)
				*error = std::string("can't make ") + dir + ": " + strerror(errno);
			return false;
		}
	}
	std::string temp = path + ".tmp";
	unlink(temp.c_str());
	FILE* f = nullptr;
	int fd = open(temp.c_str(), O_WRONLY | O_CREAT | O_EXCL, 0600);
	if (fd >= 0)
		f = fdopen(fd, "wb");
	if (f == nullptr) {
		if (error != nullptr)
			*error = strerror(errno);
		if (fd >= 0)
			close(fd);
		return false;
	}
	std::string text = SignInToJSON(server, signIn);
	bool ok = fwrite(text.data(), 1, text.size(), f) == text.size();
	ok = fclose(f) == 0 && ok;
	if (ok)
		ok = rename(temp.c_str(), path.c_str()) == 0;
	if (!ok) {
		if (error != nullptr)
			*error = strerror(errno);
		unlink(temp.c_str());
	}
	return ok;
}

bool RemoveSignIn(const std::string& path)
{
	return unlink(path.c_str()) == 0 || errno == ENOENT;
}

}  // namespace shiori
