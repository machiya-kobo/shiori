#include "Config.h"

#include <cerrno>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include "Json.h"
#include "Query.h"

namespace shiori {

namespace {

std::string LowerASCII(std::string s)
{
	for (char& c : s) {
		if (c >= 'A' && c <= 'Z')
			c = char(c - 'A' + 'a');
	}
	return s;
}

bool IsBase64URL(char c)
{
	return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_'
		|| c == '-';
}

}  // namespace

std::string OriginOf(const std::string& raw)
{
	std::string url = Trim(raw);
	std::string lower = LowerASCII(url.substr(0, 8));
	std::string scheme;
	if (lower.compare(0, 8, "https://") == 0)
		scheme = "https";
	else if (lower.compare(0, 7, "http://") == 0)
		scheme = "http";
	else
		return "";
	size_t start = scheme.size() + 3;
	size_t end = url.find_first_of("/?#", start);
	std::string authority = LowerASCII(
		url.substr(start, end == std::string::npos ? std::string::npos : end - start));
	if (authority.empty() || authority.find('@') != std::string::npos)
		return "";
	for (char c : authority) {
		if (c == ' ' || c == '\\' || c == '\t')
			return "";
	}
	size_t colon = authority.rfind(':');
	bool bracket = authority[0] == '[';
	if (colon != std::string::npos && (!bracket || authority.find(']') < colon)) {
		std::string port = authority.substr(colon + 1);
		std::string host = authority.substr(0, colon);
		if (host.empty())
			return "";
		for (char c : port) {
			if (c < '0' || c > '9')
				return "";
		}
		if (port.empty() || (scheme == "https" && port == "443") || (scheme == "http" && port == "80"))
			authority = host;
	}
	return scheme + "://" + authority;
}

std::string CheckedHisterToken(const std::string& raw)
{
	std::string t = Trim(raw);
	if (t.size() < 8 || t.size() > 512)
		return "";
	for (unsigned char c : t) {
		if (c < 0x21 || c > 0x7E)
			return "";
	}
	return t;
}

std::string CheckedRoomToken(const std::string& raw)
{
	std::string t = Trim(raw);
	if (t.size() != 4 + 43 || t.compare(0, 4, "mht_") != 0)
		return "";
	for (size_t i = 4; i < t.size(); i++) {
		if (!IsBase64URL(t[i]))
			return "";
	}
	return t;
}

bool IsConfiguredOrigin(const Config& config, const std::string& url)
{
	std::string origin = OriginOf(url);
	if (origin.empty())
		return false;
	return origin == OriginOf(config.server) || origin == OriginOf(config.kura);
}

Headers CredentialHeaders(const Config& config, const std::string& url)
{
	Headers headers;
	std::string origin = OriginOf(url);
	if (origin.empty())
		return headers;
	std::string hister = OriginOf(config.server);
	std::string kura = OriginOf(config.kura);
	if (!hister.empty() && origin == hister) {
		std::string token = CheckedHisterToken(config.histerToken);
		if (!token.empty())
			headers.emplace_back("X-Access-Token", token);
		return headers;
	}
	// A room sharing Hister's origin gets nothing (search-core's machiyaRooms).
	if (!kura.empty() && origin == kura && kura != hister) {
		std::string token = CheckedRoomToken(config.roomToken);
		if (!token.empty())
			headers.emplace_back("Authorization", "Bearer " + token);
	}
	return headers;
}

std::string ConfigToJSON(const Config& config)
{
	// Pretty enough to edit by hand, keys in a fixed order.
	return std::string("{\n")
		+ "  \"server\": " + json::Quote(Trim(config.server)) + ",\n"
		+ "  \"histerToken\": " + json::Quote(Trim(config.histerToken)) + ",\n"
		+ "  \"kura\": " + json::Quote(Trim(config.kura)) + ",\n"
		+ "  \"roomToken\": " + json::Quote(Trim(config.roomToken)) + "\n"
		+ "}\n";
}

bool ConfigFromJSON(const std::string& text, Config& config)
{
	json::Value v;
	if (!json::Parse(text, v) || !v.IsObject())
		return false;
	config.server = v["server"].Str();
	config.histerToken = v["histerToken"].Str();
	config.kura = v["kura"].Str();
	config.roomToken = v["roomToken"].Str();
	return true;
}

bool LoadConfig(const std::string& path, Config& config, std::string* error)
{
	FILE* f = fopen(path.c_str(), "rb");
	if (f == nullptr) {
		if (error != nullptr)
			*error = strerror(errno);
		return false;
	}
	std::string text;
	char buf[4096];
	size_t n;
	while ((n = fread(buf, 1, sizeof(buf), f)) > 0 && text.size() < 1 << 20)
		text.append(buf, n);
	fclose(f);
	if (!ConfigFromJSON(text, config)) {
		if (error != nullptr)
			*error = "config.json isn't a JSON object";
		return false;
	}
	return true;
}

bool SaveConfig(const std::string& path, const Config& config, std::string* error)
{
	// The directory first (~/config/settings/Shiori), then a 0600 temporary
	// file renamed over the old one: the token is never readable by others,
	// not even for a moment.
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
	int fd = open(temp.c_str(), O_WRONLY | O_CREAT | O_EXCL, 0600);
	if (fd < 0) {
		if (error != nullptr)
			*error = strerror(errno);
		return false;
	}
	fchmod(fd, 0600);
	std::string text = ConfigToJSON(config);
	bool ok = write(fd, text.data(), text.size()) == ssize_t(text.size());
	ok = fsync(fd) == 0 && ok;
	close(fd);
	if (!ok || rename(temp.c_str(), path.c_str()) != 0) {
		if (error != nullptr)
			*error = strerror(errno);
		unlink(temp.c_str());
		return false;
	}
	chmod(path.c_str(), 0600);
	return true;
}

int ConfigMode(const std::string& path)
{
	struct stat st;
	if (stat(path.c_str(), &st) != 0)
		return -1;
	return int(st.st_mode & 0777);
}

}  // namespace shiori
