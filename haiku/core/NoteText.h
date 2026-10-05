// A note's preview (Kura's /api/note: {html, …}, sanitized HTML) as styled
// text for a BTextView: headings, bold, italic, code, quotes, lists and links,
// every other tag dropped and its text kept. Notes come only from Kura, and
// a preview is never cached. Portable: no Be headers.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace shiori {

enum TextStyle : uint32_t {
	kStylePlain = 0,
	kStyleBold = 1,
	kStyleItalic = 2,
	kStyleCode = 4,
	kStyleHeading = 8,    // h1–h2
	kStyleSubheading = 16, // h3–h6
	kStyleQuote = 32,
	kStyleLink = 64,
};

struct StyledRun {
	size_t offset = 0;     // into StyledText::text (bytes)
	uint32_t style = kStylePlain;
	std::string href;      // a link's address (http(s) only; others aren't links)
};

struct StyledText {
	std::string text;
	std::vector<StyledRun> runs;  // in order, the first at 0

	// The link at a byte offset, or ''.
	std::string LinkAt(size_t offset) const;
};

StyledText NoteHTMLToText(const std::string& html);

// GET <kura>api/note?path=…[&vault=…] (no vault: Kura's default one).
std::string KuraNoteURL(const std::string& kura, const std::string& path, const std::string& vault);
// The reply's html; false for anything else.
bool ParseKuraNote(const std::string& body, std::string& html);

}  // namespace shiori
