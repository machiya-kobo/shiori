// What a search sends: the twins of search-core.js's query rules
// (patches/shiori/search-core.js, HisterKit's SearchText), with the same
// test vectors (tests/test_core.cpp mirrors scripts/search-core.test.mjs).
// When search-core's rules change, these change in the same series.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace shiori {

// The pills v0.1 has (search-core's PILLS keys).
enum class Pill { All, Pages, Notes, Code };
const char* PillKey(Pill pill);
const char* PillLabel(Pill pill);

// Text helpers (UTF-8 throughout).
std::string Trim(const std::string& s);
std::vector<std::string> SplitWords(const std::string& s);  // JS's split(/\s+/), empties dropped
std::string JoinWords(const std::vector<std::string>& words);

// search-core: the last word as a prefix ("hist" -> "hist*", or with
// `unionForm` Hister's "(hist|hist*)").
std::string PrefixLastWord(const std::string& text, bool unionForm = false);
// search-core: a dangling quote closed.
std::string CloseQuote(const std::string& text);
// search-core: never the notes.
std::string ExcludingNotes(const std::string& text);
// search-core: a Hister search as sent (the last word a prefix, never the
// notes, and never the files or code unless it asks).
std::string HisterText(const std::string& text);
// search-core: the Code pill's query (no filters in v0.1).
std::string CodeQuery(const std::string& typed);
// search-core: the Files tab's query.
std::string FilesQuery(const std::string& typed);
// search-core: the query without Hister-only operators.
std::string WebQuery(const std::string& q);
// search-core: a search as Kura reads it ('' for Kura's recent list).
std::string KuraQuery(const std::string& q);

// encodeURIComponent and URLSearchParams' form encoding (space as "+").
std::string EncodeURIComponent(const std::string& s);
std::string FormEncode(const std::string& s);

// A base URL with exactly one trailing slash.
std::string WithSlash(const std::string& base);

// Hister's JSON search: GET <server>search?query=<{"text","highlight","limit"}>
// (HisterClient.search's request; Accept: application/json is the client's).
// `pageKey`: the last reply's page_key, for the next page. No words: the
// newest pages ("*", sort date).
std::string HisterSearchURL(const std::string& server, const std::string& typed, Pill pill,
	int limit = 30, const std::string& pageKey = std::string());
// search-core's kuraURL: api/search?limit&offset[&vault]&q&sort, or api/recent.
// `vault`: one name or "all" (the Notes pill only); '' asks for the default vault.
std::string KuraSearchURL(const std::string& kura, const std::string& typed, int limit = 20,
	int offset = 0, const std::string& vault = std::string());
// Kura's vault list.
std::string KuraVaultsURL(const std::string& kura);

// A deliberate save (linux/src/page.js newPage + addRequest): the body for
// POST <server>api/add. `version` is the app's, `via` "haiku".
bool IsWebURL(const std::string& url);
std::string AddURL(const std::string& server);
// `added`: unix seconds (a queued page keeps its first time), 0 for none.
std::string NewPageJSON(const std::string& url, const std::string& title,
	const std::string& label, const std::string& version, int64_t added = 0);
// HisterKit's Rejection, in words; '' for anything else.
std::string RejectionReason(int status);

// No answer, in words that say what to do (HisterError(transport:)): a TLS
// or certificate failure is "isn't trusted", anything else "can't be reached".
bool IsCertificateError(const std::string& error);
std::string TransportProblem(const std::string& who, const std::string& error);

}  // namespace shiori
