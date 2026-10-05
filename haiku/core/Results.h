// Hister's and Kura's replies as rows (HisterKit's DocumentWire,
// search-core's kuraDocuments), and their snippets as text runs.
#pragma once

#include <string>
#include <utility>
#include <vector>

namespace shiori {

struct Result {
	enum Kind { Page, Note, Code };
	Kind kind = Page;
	std::string url;
	std::string title;
	std::string host;     // the page's host; a note's folder
	std::string snippet;  // HTML whose only markup is <mark>
	std::string label;
	std::string path;     // a note's path in the vault
	double added = 0;
	double updated = 0;
};

struct ResultPage {
	bool ok = false;
	std::string error;
	int total = 0;
	std::vector<Result> results;
	// Paging: Hister's page_key for the next page ('' at the end); for Kura,
	// how many came (rows dropped as non-web included), the next offset's step.
	std::string next;
	int received = 0;
};

// One of Kura's vaults (/api/vaults: {vaults: [{name, title, default, private}]}).
struct Vault {
	std::string name;
	std::string title;
	bool isDefault = false;
};

// The host of an http(s) URL, lowercased, without "www." or the port; ''.
std::string HostOf(const std::string& url);

// Hister's /search JSON: {total, documents: [{url, title, domain, label, text, metadata}]}.
ResultPage ParseHister(const std::string& body);
// Kura's /api/search or /api/recent: {total, results: [note]} (only http(s) urls kept).
ResultPage ParseKura(const std::string& body);
// Kura's /api/vaults, names checked as Kura allows them ([a-z0-9-]+); [] for anything else.
std::vector<Vault> ParseVaults(const std::string& body);

// A snippet as runs of plain text, `true` where it was inside <mark>:
// entities decoded, every other tag dropped, whitespace folded.
std::vector<std::pair<std::string, bool>> SnippetRuns(const std::string& html);
std::string SnippetText(const std::string& html);

// Entities (&amp; &lt; &gt; &quot; &#39; &#x..; &nbsp;) decoded.
std::string DecodeEntities(const std::string& s);

}  // namespace shiori
