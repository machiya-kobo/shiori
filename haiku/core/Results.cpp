#include "Results.h"

#include <cstdlib>
#include <cstring>
#include <algorithm>

#include "Json.h"
#include "Query.h"

namespace shiori {

namespace {

void AppendUtf8(std::string& out, unsigned long cp)
{
	if (cp == 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF))
		cp = 0xFFFD;
	if (cp < 0x80) {
		out += char(cp);
	} else if (cp < 0x800) {
		out += char(0xC0 | (cp >> 6));
		out += char(0x80 | (cp & 0x3F));
	} else if (cp < 0x10000) {
		out += char(0xE0 | (cp >> 12));
		out += char(0x80 | ((cp >> 6) & 0x3F));
		out += char(0x80 | (cp & 0x3F));
	} else {
		out += char(0xF0 | (cp >> 18));
		out += char(0x80 | ((cp >> 12) & 0x3F));
		out += char(0x80 | ((cp >> 6) & 0x3F));
		out += char(0x80 | (cp & 0x3F));
	}
}

std::string LowerASCII(std::string s)
{
	for (char& c : s) {
		if (c >= 'A' && c <= 'Z')
			c = char(c - 'A' + 'a');
	}
	return s;
}

std::string FolderOf(const std::string& path)
{
	size_t slash = path.rfind('/');
	return slash == std::string::npos ? std::string() : path.substr(0, slash);
}

}  // namespace

std::string HostOf(const std::string& url)
{
	if (!IsWebURL(url))
		return "";
	size_t start = url.find("://") + 3;
	size_t end = url.find_first_of("/?#", start);
	std::string authority = url.substr(start, end == std::string::npos ? std::string::npos : end - start);
	size_t at = authority.rfind('@');
	if (at != std::string::npos)
		authority = authority.substr(at + 1);
	if (!authority.empty() && authority[0] != '[') {
		size_t colon = authority.find(':');
		if (colon != std::string::npos)
			authority = authority.substr(0, colon);
	}
	authority = LowerASCII(authority);
	if (authority.compare(0, 4, "www.") == 0)
		authority = authority.substr(4);
	return authority;
}

ResultPage ParseHister(const std::string& body)
{
	ResultPage page;
	json::Value v;
	if (!json::Parse(body, v, &page.error) || !v.IsObject()) {
		if (page.error.empty())
			page.error = "not a JSON object";
		return page;
	}
	page.ok = true;
	page.total = int(v["total"].Num(0));
	for (const auto& d : v["documents"].items) {
		std::string url = d["url"].Str();
		// Only web addresses become rows: a stored javascript: or file: link never opens (SHIO-1).
		if (!IsWebURL(url))
			continue;
		Result r;
		r.url = url;
		r.title = d["title"].Str();
		if (r.title.empty())
			r.title = url;
		r.host = d["domain"].Str();
		if (r.host.empty())
			r.host = HostOf(url);
		r.snippet = d["text"].Str();
		r.label = d["label"].Str();
		r.added = d["added"].Num(0);
		r.updated = d["updated"].Num(r.added);
		r.kind = d["metadata"]["source"].Str() == "code" ? Result::Code : Result::Page;
		page.results.push_back(std::move(r));
	}
	page.received = int(v["documents"].items.size());
	page.next = v["page_key"].Str();
	return page;
}

namespace {

bool StartsWithLower(const std::string& s, const char* prefix)
{
	size_t n = std::strlen(prefix);
	return s.size() >= n && LowerASCII(s.substr(0, n)) == prefix;
}

bool SingleDot(const std::string& s)
{
	return s == "." || LowerASCII(s) == "%2e";
}

bool DoubleDot(const std::string& s)
{
	std::string l = LowerASCII(s);
	return l == ".." || l == ".%2e" || l == "%2e." || l == "%2e%2e";
}

int HexValue(char c)
{
	if (c >= '0' && c <= '9')
		return c - '0';
	if (c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	if (c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	return -1;
}

}  // namespace

std::string KuraPath(const std::string& url, bool* ok)
{
	*ok = false;
	size_t start;
	if (StartsWithLower(url, "https://"))
		start = 8;
	else if (StartsWithLower(url, "http://"))
		start = 7;
	else
		return "";
	size_t p = url.find_first_of("/\\?#", start);
	if (p == std::string::npos)
		p = url.size();
	size_t end = url.find_first_of("?#", p);
	if (end == std::string::npos)
		end = url.size();
	// The URL standard's path: separators / and \, dot segments resolved.
	std::vector<std::string> segs;
	if (p < end && (url[p] == '/' || url[p] == '\\'))
		p++;
	for (;;) {
		size_t q = p;
		while (q < end && url[q] != '/' && url[q] != '\\')
			q++;
		std::string seg = url.substr(p, q - p);
		bool last = q >= end;
		if (DoubleDot(seg)) {
			if (!segs.empty())
				segs.pop_back();
			if (last)
				segs.push_back("");
		} else if (SingleDot(seg)) {
			if (last)
				segs.push_back("");
		} else {
			segs.push_back(seg);
		}
		if (last)
			break;
		p = q + 1;
	}
	std::string one;
	for (const auto& seg : segs)
		one += "/" + seg;
	if (one.empty())
		one = "/";
	// ASCII escapes decoded once, as Kura does.
	std::string decoded;
	for (size_t i = 0; i < one.size(); i++) {
		int hi = one[i] == '%' && i + 2 < one.size() + 0 ? HexValue(one[i + 1]) : -1;
		int lo = hi >= 0 ? HexValue(one[i + 2]) : -1;
		if (hi >= 0 && hi <= 7 && lo >= 0) {
			decoded += char(hi * 16 + lo);
			i += 2;
		} else {
			decoded += one[i];
		}
	}
	// Leading slashes folded, then . and .. resolved again.
	size_t i = decoded.find_first_not_of('/');
	std::string rest = i == std::string::npos ? "" : decoded.substr(i);
	std::vector<std::string> out;
	size_t from = 0;
	for (;;) {
		size_t slash = rest.find('/', from);
		std::string seg = rest.substr(from, slash == std::string::npos ? std::string::npos : slash - from);
		if (seg == "..") {
			if (!out.empty())
				out.pop_back();
		} else if (seg != ".") {
			out.push_back(seg);
		}
		if (slash == std::string::npos)
			break;
		from = slash + 1;
	}
	std::string path;
	for (const auto& seg : out)
		path += "/" + seg;
	*ok = true;
	return path.empty() ? "/" : path;
}

std::string NoteVault(const std::string& url)
{
	bool ok;
	std::string path = KuraPath(url, &ok);
	if (!ok || path.compare(0, 3, "/v/") != 0)
		return "";
	size_t slash = path.find('/', 3);
	if (slash == std::string::npos || slash == 3)
		return "";
	return path.substr(3, slash - 3);
}

bool HisterNoteShown(const std::string& url)
{
	bool ok;
	KuraPath(url, &ok);
	return ok && NoteVault(url).empty();
}

ResultPage ParseHisterNotes(const std::string& body)
{
	ResultPage page;
	json::Value v;
	if (!json::Parse(body, v, &page.error) || !v.IsObject()) {
		if (page.error.empty())
			page.error = "not a JSON object";
		return page;
	}
	page.ok = true;
	const json::Value& docs = v["documents"];
	int all = int(docs.items.size()), dropped = 0;
	for (const auto& d : docs.items) {
		std::string url = d["url"].Str();
		if (!HisterNoteShown(url)) {
			dropped++;  // another vault's, or not an address
			continue;
		}
		Result r;
		r.kind = Result::Note;
		r.url = url;
		r.title = d["title"].Str();
		if (r.title.empty())
			r.title = url;
		r.path = d["metadata"]["vault_path"].Str();
		r.host = FolderOf(r.path);
		r.snippet = d["text"].Str();
		r.label = "vault";
		r.added = d["added"].Num(0);
		r.updated = d["updated"].Num(r.added);
		page.results.push_back(std::move(r));
	}
	page.total = std::max(0, int(v["total"].Num(double(all))) - dropped);
	page.received = all;
	page.next = v["page_key"].Str();
	return page;
}

ResultPage ParseKura(const std::string& body)
{
	ResultPage page;
	json::Value v;
	if (!json::Parse(body, v, &page.error) || !v.IsObject()) {
		if (page.error.empty())
			page.error = "not a JSON object";
		return page;
	}
	page.ok = true;
	const json::Value& results = v["results"];
	page.total = int(v["total"].Num(double(results.items.size())));
	for (const auto& n : results.items) {
		std::string url = n["url"].Str();
		if (!IsWebURL(url))
			continue;
		Result r;
		r.kind = Result::Note;
		r.url = url;
		r.path = n["path"].Str();
		r.vault = n["vault"].Str();
		r.title = n["title"].Str(r.path.empty() ? url : r.path);
		if (r.title.empty())
			r.title = r.path.empty() ? url : r.path;
		r.host = n["folder"].Str(FolderOf(r.path));
		r.snippet = n["snippet"].Str(n["summary"].Str());
		if (r.snippet.empty())
			r.snippet = n["summary"].Str();
		r.label = "vault";
		r.added = n["created"].Num(0);
		r.updated = n["changed"].Num(r.added);
		page.results.push_back(std::move(r));
	}
	page.received = int(results.items.size());
	return page;
}

std::vector<Vault> ParseVaults(const std::string& body)
{
	std::vector<Vault> vaults;
	json::Value v;
	if (!json::Parse(body, v) || !v.IsObject())
		return vaults;
	for (const auto& item : v["vaults"].items) {
		Vault vault;
		vault.name = item["name"].Str();
		bool sound = !vault.name.empty() && vault.name.size() <= 64;
		for (char c : vault.name) {
			if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-'))
				sound = false;
		}
		if (!sound)
			continue;
		vault.title = item["title"].Str(vault.name);
		if (vault.title.empty())
			vault.title = vault.name;
		vault.isDefault = item["default"].type == json::Value::Bool && item["default"].boolean;
		vaults.push_back(vault);
	}
	return vaults;
}

std::string DecodeEntities(const std::string& s)
{
	std::string out;
	for (size_t i = 0; i < s.size(); i++) {
		if (s[i] != '&') {
			out += s[i];
			continue;
		}
		size_t semi = s.find(';', i);
		if (semi == std::string::npos || semi - i > 10) {
			out += s[i];
			continue;
		}
		std::string name = s.substr(i + 1, semi - i - 1);
		std::string rep;
		if (name.size() > 1 && name[0] == '#') {
			bool hex = name[1] == 'x' || name[1] == 'X';
			const char* digits = name.c_str() + (hex ? 2 : 1);
			char* end = nullptr;
			unsigned long cp = strtoul(digits, &end, hex ? 16 : 10);
			if (end != nullptr && *end == '\0' && *digits != '\0')
				AppendUtf8(rep, cp);
		} else {
			std::string n = LowerASCII(name);
			if (n == "amp") rep = "&";
			else if (n == "lt") rep = "<";
			else if (n == "gt") rep = ">";
			else if (n == "quot") rep = "\"";
			else if (n == "apos") rep = "'";
			else if (n == "nbsp") rep = " ";
		}
		if (rep.empty()) {
			out += s[i];
			continue;
		}
		out += rep;
		i = semi;
	}
	return out;
}

std::vector<std::pair<std::string, bool>> SnippetRuns(const std::string& html)
{
	std::vector<std::pair<std::string, bool>> runs;
	bool marked = false;
	std::string current;
	auto flush = [&]() {
		if (current.empty())
			return;
		std::string text = DecodeEntities(current);
		// Fold whitespace (newlines included) to single spaces.
		std::string folded;
		bool space = false;
		for (char c : text) {
			if (c == ' ' || c == '\n' || c == '\t' || c == '\r') {
				space = true;
				continue;
			}
			if (space && (!folded.empty() || !runs.empty()))
				folded += ' ';
			space = false;
			folded += c;
		}
		if (space)
			folded += ' ';
		if (!folded.empty())
			runs.emplace_back(folded, marked);
		current.clear();
	};
	for (size_t i = 0; i < html.size(); i++) {
		if (html[i] == '<') {
			size_t close = html.find('>', i);
			if (close == std::string::npos)
				break;
			std::string tag = LowerASCII(html.substr(i + 1, close - i - 1));
			if (tag == "mark" || tag.compare(0, 5, "mark ") == 0) {
				flush();
				marked = true;
			} else if (tag == "/mark") {
				flush();
				marked = false;
			}
			i = close;
			continue;
		}
		current += html[i];
	}
	flush();
	return runs;
}

std::string SnippetText(const std::string& html)
{
	std::string out;
	for (const auto& run : SnippetRuns(html))
		out += run.first;
	return out;
}

}  // namespace shiori
