// A row in the results list: the title (bold), a badge and the host (or a
// note's folder), and the snippet with its <mark> words in bold.
#pragma once

#include <ListItem.h>
#include <String.h>

#include "../core/Results.h"

class ResultItem : public BListItem {
public:
	explicit ResultItem(const shiori::Result& result);

	void DrawItem(BView* owner, BRect frame, bool complete = false) override;
	void Update(BView* owner, const BFont* font) override;

	const shiori::Result& Data() const { return fResult; }

private:
	shiori::Result fResult;
	std::string fTitle;
	std::vector<std::pair<std::string, bool>> fSnippet;
	float fLineHeight = 14;
	float fAscent = 11;
};

// A section header ("Notes", "Pages"): not a result, drawn small and grey.
class HeaderItem : public BListItem {
public:
	explicit HeaderItem(const char* text);
	void DrawItem(BView* owner, BRect frame, bool complete = false) override;
	void Update(BView* owner, const BFont* font) override;

private:
	BString fText;
};

// The last row while there's more: "Show More…", invoked like a result.
class MoreItem : public BListItem {
public:
	MoreItem();
	void DrawItem(BView* owner, BRect frame, bool complete = false) override;
	void Update(BView* owner, const BFont* font) override;
	void SetLoading(bool loading) { fLoading = loading; }

private:
	bool fLoading = false;
};
