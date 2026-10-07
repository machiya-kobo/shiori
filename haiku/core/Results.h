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
	std::string vault;    // a note's vault ('' for Kura's default)
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

// search-core's kuraPath: an http(s) address's path as Kura reads it (the URL
// standard's dot segments, with \ and %2e; ASCII escapes decoded once; leading
// slashes folded; dot segments again). ok false when it isn't http(s).
std::string KuraPath(const std::string& url, bool* ok);
// search-core's noteVault: the vault an address is under (/v/<name>/), or ''.
std::string NoteVault(const std::string& url);
// search-core's histerNoteShown: one of Hister's notes a client may show, the
// default vault's alone (another vault, shared or private, never).
bool HisterNoteShown(const std::string& url);
// search-core's histerNoteDocuments: Hister's reply to a notes search as notes,
// the default vault's alone, their path from Kura's metadata.vault_path and
// their folder as host; total less what was dropped.
ResultPage ParseHisterNotes(const std::string& body);

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
