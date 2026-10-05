#include "ResultItem.h"

#include <ControlLook.h>
#include <Font.h>
#include <InterfaceDefs.h>
#include <String.h>
#include <View.h>

using shiori::Result;

namespace {

// Truncated to `width` with an ellipsis, in `font`.
BString Fit(const BFont& font, const std::string& text, float width)
{
	BString s(text.c_str());
	font.TruncateString(&s, B_TRUNCATE_END, width);
	return s;
}

}  // namespace

ResultItem::ResultItem(const shiori::Result& result)
	:
	fResult(result),
	fTitle(shiori::DecodeEntities(result.title)),
	fSnippet(shiori::SnippetRuns(result.snippet))
{
}

void ResultItem::Update(BView* owner, const BFont* font)
{
	font_height fh;
	font->GetHeight(&fh);
	fLineHeight = ceilf(fh.ascent + fh.descent + fh.leading) + 1;
	fAscent = ceilf(fh.ascent);
	SetWidth(owner->Bounds().Width());
	// Title, host line, two snippet lines, padding.
	SetHeight(fLineHeight * 4 + 8);
}

void ResultItem::DrawItem(BView* owner, BRect frame, bool complete)
{
	rgb_color background = ui_color(IsSelected() ? B_LIST_SELECTED_BACKGROUND_COLOR : B_LIST_BACKGROUND_COLOR);
	rgb_color text = ui_color(IsSelected() ? B_LIST_SELECTED_ITEM_TEXT_COLOR : B_LIST_ITEM_TEXT_COLOR);
	rgb_color dim = tint_color(text, text.IsLight() ? B_DARKEN_2_TINT : B_LIGHTEN_2_TINT);
	rgb_color badge = fResult.kind == Result::Note ? make_color(0x2e, 0x7d, 0x32)
		: fResult.kind == Result::Code ? make_color(0x6a, 0x1b, 0x9a) : make_color(0x15, 0x65, 0xc0);

	owner->SetLowColor(background);
	owner->FillRect(frame, B_SOLID_LOW);

	BFont plain;
	owner->GetFont(&plain);
	BFont bold(plain);
	bold.SetFace(B_BOLD_FACE);
	float x = frame.left + 8;
	float width = frame.Width() - 16;
	float y = frame.top + 4 + fAscent;

	// Title
	owner->SetFont(&bold);
	owner->SetHighColor(text);
	owner->DrawString(Fit(bold, fTitle, width).String(), BPoint(x, y));

	// Badge + host
	y += fLineHeight;
	const char* kind = fResult.kind == Result::Note ? "NOTE" : fResult.kind == Result::Code ? "CODE" : "PAGE";
	BFont small(plain);
	small.SetSize(plain.Size() * 0.8f);
	small.SetFace(B_BOLD_FACE);
	float badgeWidth = small.StringWidth(kind) + 8;
	BRect pill(x, y - fAscent + 1, x + badgeWidth, y + 2);
	owner->SetHighColor(badge);
	owner->FillRoundRect(pill, 3, 3);
	owner->SetFont(&small);
	owner->SetHighColor(255, 255, 255);
	owner->DrawString(kind, BPoint(x + 4, y - 1));
	owner->SetFont(&plain);
	owner->SetHighColor(dim);
	std::string where = fResult.host;
	if (fResult.kind == Result::Note && where.empty())
		where = "(vault root)";
	owner->DrawString(Fit(plain, where, width - badgeWidth - 8).String(), BPoint(x + badgeWidth + 8, y));

	// Snippet: up to two lines, <mark> in bold, wrapped by width.
	y += fLineHeight;
	float cx = x;
	int line = 0;
	owner->SetHighColor(text);
	for (const auto& run : fSnippet) {
		const BFont& f = run.second ? bold : plain;
		owner->SetFont(&f);
		// Word by word, so lines wrap.
		size_t i = 0;
		const std::string& s = run.first;
		while (i < s.size() && line < 2) {
			size_t end = s.find(' ', i);
			end = end == std::string::npos ? s.size() : end + 1;
			std::string word = s.substr(i, end - i);
			float w = f.StringWidth(word.c_str());
			if (cx + w > x + width && cx > x) {
				line++;
				if (line >= 2)
					break;
				cx = x;
				y += fLineHeight;
			}
			if (line == 1 && cx + w > x + width) {
				BString cut = Fit(f, word, x + width - cx);
				owner->DrawString(cut.String(), BPoint(cx, y));
				line = 2;
				break;
			}
			owner->DrawString(word.c_str(), BPoint(cx, y));
			cx += w;
			i = end;
		}
		if (line >= 2)
			break;
	}
	owner->SetFont(&plain);

	// A hairline between rows.
	owner->SetHighColor(tint_color(background, B_DARKEN_1_TINT));
	owner->StrokeLine(BPoint(frame.left, frame.bottom), BPoint(frame.right, frame.bottom));
}

HeaderItem::HeaderItem(const char* text)
	:
	fText(text)
{
	SetEnabled(false);
}

void HeaderItem::Update(BView* owner, const BFont* font)
{
	font_height fh;
	font->GetHeight(&fh);
	SetWidth(owner->Bounds().Width());
	SetHeight(ceilf(fh.ascent + fh.descent) + 8);
}

void HeaderItem::DrawItem(BView* owner, BRect frame, bool complete)
{
	rgb_color background = tint_color(ui_color(B_LIST_BACKGROUND_COLOR), B_DARKEN_1_TINT);
	owner->SetLowColor(background);
	owner->FillRect(frame, B_SOLID_LOW);
	BFont font;
	owner->GetFont(&font);
	BFont bold(font);
	bold.SetFace(B_BOLD_FACE);
	owner->SetFont(&bold);
	font_height fh;
	bold.GetHeight(&fh);
	owner->SetHighColor(tint_color(ui_color(B_LIST_ITEM_TEXT_COLOR), B_LIGHTEN_1_TINT));
	owner->DrawString(fText.String(), BPoint(frame.left + 8, frame.top + 4 + fh.ascent));
	owner->SetFont(&font);
}
