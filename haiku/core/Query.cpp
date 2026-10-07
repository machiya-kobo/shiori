#include "Query.h"

#include <cctype>

#include <cstdio>
#include <cstring>

#include "Json.h"

namespace shiori {

namespace {

// One UTF-8 code point at s[i], advancing i; U+FFFD for a bad byte.
unsigned long NextCodePoint(const std::string& s, size_t& i)
{
	unsigned char c = s[i++];
	if (c < 0x80)
		return c;
	int extra = (c >= 0xF0) ? 3 : (c >= 0xE0) ? 2 : (c >= 0xC0) ? 1 : -1;
	if (extra < 0)
		return 0xFFFD;
	unsigned long cp = c & (0x3F >> extra);
	for (int k = 0; k < extra; k++) {
		if (i >= s.size() || (s[i] & 0xC0) != 0x80)
			return 0xFFFD;
		cp = (cp << 6) | (s[i++] & 0x3F);
	}
	return cp;
}

std::vector<unsigned long> CodePoints(const std::string& s)
{
	std::vector<unsigned long> out;
	for (size_t i = 0; i < s.size();)
		out.push_back(NextCodePoint(s, i));
	return out;
}

// JavaScript's \s.
bool IsSpace(unsigned long cp)
{
	return cp == ' ' || (cp >= 0x09 && cp <= 0x0D) || cp == 0xA0 || cp == 0x1680
		|| (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028 || cp == 0x2029 || cp == 0x202F
		|| cp == 0x205F || cp == 0x3000 || cp == 0xFEFF;
}

// \p{N}, near enough: ASCII and full-width digits.
bool IsNumberCP(unsigned long cp)
{
	return (cp >= '0' && cp <= '9') || (cp >= 0xFF10 && cp <= 0xFF19);
}

// \p{L}, near enough without ICU: ASCII letters, and anything past ASCII
// that isn't a space, digit, punctuation or symbol block. (Haiku has ICU;
// the portable core doesn't use it. Close enough for "is this a word".)
bool IsLetterCP(unsigned long cp)
{
	if (cp < 0x80)
		return (cp >= 'a' && cp <= 'z') || (cp >= 'A' && cp <= 'Z');
	if (IsSpace(cp) || IsNumberCP(cp))
		return false;
	if (cp <= 0xBF)
		return cp == 0xAA || cp == 0xB5 || cp == 0xBA;
	if (cp == 0xD7 || cp == 0xF7)
		return false;
	if (cp >= 0x2000 && cp <= 0x2BFF)  // punctuation, symbols, arrows, math, boxes
		return false;
	if (cp >= 0x3000 && cp <= 0x3004)  // CJK spaces and punctuation
		return false;
	if (cp >= 0x3008 && cp <= 0x3020)
		return false;
	if ((cp >= 0xFE30 && cp <= 0xFE4F) || (cp >= 0xFF00 && cp <= 0xFF0F)
		|| (cp >= 0xFF1A && cp <= 0xFF20) || (cp >= 0xFF3B && cp <= 0xFF40)
		|| (cp >= 0xFF5B && cp <= 0xFF65))
		return false;
	if (cp >= 0x1F000 && cp <= 0x1FAFF)  // emoji and pictographs
		return false;
	if (cp == 0xFFFD)
		return false;
	return true;
}

bool StartsWith(const std::string& s, const std::string& prefix)
{
	return s.compare(0, prefix.size(), prefix) == 0;
}

std::string Lower(std::string s)
{
	for (char& c : s) {
		if (c >= 'A' && c <= 'Z')
			c = char(c - 'A' + 'a');
	}
	return s;
}

bool Contains(const std::vector<std::string>& words, const std::string& w)
{
	for (const auto& x : words) {
		if (x == w)
			return true;
	}
	return false;
}

const char* const kNotesExclusion = "-label:vault -metadata.source:vault";
const char* const kFilesTerm = "type:local";
const char* const kFilesExclusion = "-type:local";
const char* const kCodeTerm = "metadata.source:code";
const char* const kCodeExclusion = "-metadata.source:code";

// search-core's HISTER_ONLY:
// /^(-?(label|added|updated|url|domain|type|language|metadata\.[\w.]+):|@\S+$)/i
bool IsHisterOnly(const std::string& token)
{
	if (token.size() >= 2 && token[0] == '@')
		return true;
	std::string t = Lower(token);
	if (!t.empty() && t[0] == '-')
		t.erase(0, 1);
	static const char* const kFields[]
		= {"label:", "added:", "updated:", "url:", "domain:", "type:", "language:"};
	for (const char* f : kFields) {
		if (StartsWith(t, f))
			return true;
	}
	if (StartsWith(t, "metadata.")) {
		size_t k = 9;
		size_t start = k;
		while (k < t.size()) {
			char c = t[k];
			bool word = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '.';
			if (c == ':' && k > start)
				return true;
			if (!word)
				return false;
			k++;
		}
	}
	return false;
}

}  // namespace

const char* PillKey(Pill pill)
{
	switch (pill) {
		case Pill::All: return "all";
		case Pill::Pages: return "pages";
		case Pill::Notes: return "notes";
		case Pill::Code: return "code";
	}
	return "all";
}

const char* PillLabel(Pill pill)
{
	switch (pill) {
		case Pill::All: return "All";
		case Pill::Pages: return "Pages";
		case Pill::Notes: return "Notes";
		case Pill::Code: return "Code";
	}
	return "All";
}

std::string Trim(const std::string& s)
{
	// Byte offsets of the first and last non-space code points.
	size_t i = 0, first = std::string::npos, last = 0;
	while (i < s.size()) {
		size_t at = i;
		unsigned long cp = NextCodePoint(s, i);
		if (!IsSpace(cp)) {
			if (first == std::string::npos)
				first = at;
			last = i;
		}
	}
	return first == std::string::npos ? std::string() : s.substr(first, last - first);
}

std::vector<std::string> SplitWords(const std::string& s)
{
	std::vector<std::string> words;
	std::string current;
	for (size_t i = 0; i < s.size();) {
		size_t at = i;
		unsigned long cp = NextCodePoint(s, i);
		if (IsSpace(cp)) {
			if (!current.empty())
				words.push_back(current);
			current.clear();
		} else {
			current.append(s, at, i - at);
		}
	}
	if (!current.empty())
		words.push_back(current);
	return words;
}

std::string JoinWords(const std::vector<std::string>& words)
{
	std::string out;
	for (const auto& w : words) {
		if (!out.empty())
			out += ' ';
		out += w;
	}
	return out;
}

std::string PrefixLastWord(const std::string& text, bool unionForm)
{
	const std::string& t = text;
	if (t.empty())
		return t;
	std::vector<unsigned long> cps = CodePoints(t);
	if (IsSpace(cps.back()))
		return t;
	size_t quotes = 0;
	for (char c : t) {
		if (c == '"')
			quotes++;
	}
	if (quotes % 2)
		return t;
	// The last word: everything after the last space.
	size_t start = 0;
	for (size_t i = 0; i < t.size();) {
		unsigned long cp = NextCodePoint(t, i);
		if (IsSpace(cp))
			start = i;
	}
	std::string word = t.substr(start);
	std::vector<unsigned long> wcps = CodePoints(word);
	if (wcps.size() < 2)
		return t;
	bool letter = false;
	for (unsigned long cp : wcps) {
		if (IsLetterCP(cp))
			letter = true;
		else if (!IsNumberCP(cp))
			return t;
	}
	if (!letter)
		return t;
	if (unionForm)
		return t.substr(0, start) + "(" + word + "|" + word + "*)";
	return t + "*";
}

std::string CloseQuote(const std::string& text)
{
	size_t quotes = 0;
	for (char c : text) {
		if (c == '"')
			quotes++;
	}
	return quotes % 2 ? text + "\"" : text;
}

std::string ExcludingNotes(const std::string& text)
{
	std::string t = Trim(text);
	std::vector<std::string> words = SplitWords(t);
	if (Contains(words, "-label:vault") && Contains(words, "-metadata.source:vault"))
		return t;
	return t.empty() ? std::string(kNotesExclusion) : t + " " + kNotesExclusion;
}

std::string HisterText(const std::string& text)
{
	std::string sent = ExcludingNotes(PrefixLastWord(CloseQuote(Trim(text)), true));
	std::vector<std::string> words = SplitWords(sent);
	if (!Contains(words, kFilesTerm) && !Contains(words, kFilesExclusion))
		sent += std::string(" ") + kFilesExclusion;
	if (!Contains(words, kCodeTerm) && !Contains(words, kCodeExclusion))
		sent += std::string(" ") + kCodeExclusion;
	return sent;
}

std::string CodeQuery(const std::string& typed)
{
	std::string words = Trim(typed);
	return std::string(kCodeTerm) + " " + (words.empty() ? "*" : words);
}

std::string FilesQuery(const std::string& typed)
{
	std::string words = Trim(typed);
	return std::string(kFilesTerm) + " " + (words.empty() ? "*" : words);
}

std::string WebQuery(const std::string& q)
{
	std::vector<std::string> kept;
	for (const auto& w : SplitWords(q)) {
		if (!IsHisterOnly(w))
			kept.push_back(w);
	}
	return JoinWords(kept);
}

std::string KuraQuery(const std::string& q)
{
	std::string words = WebQuery(q);
	return words == "*" ? std::string() : PrefixLastWord(words);
}

std::string EncodeURIComponent(const std::string& s)
{
	static const char* const kSafe = "-_.!~*'()";
	std::string out;
	for (unsigned char c : s) {
		if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
			|| (c != 0 && strchr(kSafe, c) != nullptr)) {
			out += char(c);
		} else {
			char buf[4];
			snprintf(buf, sizeof(buf), "%%%02X", c);
			out += buf;
		}
	}
	return out;
}

std::string FormEncode(const std::string& s)
{
	std::string out;
	for (unsigned char c : s) {
		if (c == ' ') {
			out += '+';
		} else if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
			|| c == '*' || c == '-' || c == '.' || c == '_') {
			out += char(c);
		} else {
			char buf[4];
			snprintf(buf, sizeof(buf), "%%%02X", c);
			out += buf;
		}
	}
	return out;
}

std::string WithSlash(const std::string& base)
{
	std::string b = Trim(base);
	if (b.empty() || b.back() != '/')
		b += '/';
	return b;
}

std::string NotesSource(const std::string& choice, bool kuraConfigured)
{
	if (choice == "hister")
		return "hister";
	return kuraConfigured ? "kura" : "hister";
}

std::string HisterNotesText(const std::string& text)
{
	std::string t = Trim(text);
	std::string words = t.empty() || t == "*" ? "*" : PrefixLastWord(CloseQuote(t), true);
	return words + " label:vault";
}

std::string HisterSearchURL(const std::string& server, const std::string& typed, Pill pill,
	int limit, const std::string& pageKey)
{
	// No words: the newest ("*" sorted by date, Hister's "recent"), as every
	// Shiori shows when the field is empty.
	bool newest = Trim(typed).empty();
	std::string words = newest ? "*" : typed;
	// Notes from Hister (no Kura, or the person's choice): label:vault.
	std::string text = pill == Pill::Notes ? HisterNotesText(words)
		: pill == Pill::Code ? HisterText(CodeQuery(words)) : HisterText(words);
	json::Value query = json::Value::MakeObject();
	query.Set("text", json::Value::MakeString(text));
	query.Set("highlight", json::Value::MakeString("HTML"));
	query.Set("limit", json::Value::MakeNumber(limit));
	if (newest)
		query.Set("sort", json::Value::MakeString("date"));
	if (!pageKey.empty())
		query.Set("page_key", json::Value::MakeString(pageKey));
	return WithSlash(server) + "search?query=" + FormEncode(json::Write(query));
}

std::string KuraSearchURL(const std::string& kura, const std::string& typed, int limit,
	int offset, const std::string& vault)
{
	std::string text = KuraQuery(typed);
	std::string params = "limit=" + std::to_string(limit) + "&offset=" + std::to_string(offset);
	if (!vault.empty())
		params += "&vault=" + FormEncode(vault);
	if (text.empty())
		return WithSlash(kura) + "api/recent?" + params;
	return WithSlash(kura) + "api/search?" + params + "&q=" + FormEncode(text) + "&sort=relevance";
}

std::string KuraVaultsURL(const std::string& kura)
{
	return WithSlash(kura) + "api/vaults";
}

bool IsWebURL(const std::string& url)
{
	// linux/src/page.js: /^https?:\/\/[^/\s]/i
	std::string lower = Lower(url.substr(0, 8));
	size_t n = StartsWith(lower, "https://") ? 8 : StartsWith(lower, "http://") ? 7 : 0;
	if (n == 0 || url.size() <= n)
		return false;
	char c = url[n];
	return c != '/' && c != ' ' && c != '\t' && c != '\n' && c != '\r' && c != '\f' && c != '\v';
}

std::string AddURL(const std::string& server)
{
	return WithSlash(server) + "api/add";
}

std::string NewPageJSON(const std::string& url, const std::string& title,
	const std::string& label, const std::string& version, int64_t added)
{
	json::Value page = json::Value::MakeObject();
	page.Set("url", json::Value::MakeString(url));
	page.Set("title", json::Value::MakeString(title));
	if (!label.empty())
		page.Set("label", json::Value::MakeString(label));
	// An integer of unix seconds (a string is a 400).
	if (added > 0)
		page.Set("added", json::Value::MakeNumber((double)added));
	json::Value meta = json::Value::MakeObject();
	meta.Set("source", json::Value::MakeString("shiori"));
	meta.Set("client", json::Value::MakeString("shiori"));
	meta.Set("client_version", json::Value::MakeString(version));
	meta.Set("via", json::Value::MakeString("haiku"));
	meta.Set("ignore_skip_rules", json::Value::MakeBool(true));
	page.Set("metadata", meta);
	return json::Write(page);
}

bool IsCertificateError(const std::string& error)
{
	std::string lower;
	for (char c : error)
		lower += (char)tolower((unsigned char)c);
	for (const char* word : {"certificate", "ssl", "tls", "handshake", "x509", "verify failed", "secure connection"}) {
		if (lower.find(word) != std::string::npos)
			return true;
	}
	return false;
}

std::string TransportProblem(const std::string& who, const std::string& error)
{
	std::string detail = error.empty() ? "" : " (" + error + ")";
	if (IsCertificateError(error))
		return "Couldn't make a secure connection to " + who + detail
			+ ": its certificate may not be trusted here (trust it on this computer), or it doesn't answer https.";
	return who + " can't be reached" + detail + ": check your network or VPN, then try again.";
}

std::string RejectionReason(int status)
{
	switch (status) {
		case 406: return "Hister skips this site.";
		case 413: return "The page is too large for Hister.";
		case 422: return "Hister refused it as sensitive (it looks like it holds a secret).";
	}
	return "";
}

}  // namespace shiori
