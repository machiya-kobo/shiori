#include "NoteText.h"

#include <cctype>

#include "Json.h"
#include "Query.h"
#include "Results.h"

namespace shiori {

namespace {

std::string Lower(std::string s)
{
	for (char& c : s)
		c = (char)tolower((unsigned char)c);
	return s;
}

// An attribute's value from a tag's inside (`a href="…" class=x`), entities decoded.
std::string Attribute(const std::string& tag, const std::string& name)
{
	std::string lower = Lower(tag);
	size_t at = 0;
	while ((at = lower.find(name, at)) != std::string::npos) {
		bool start = at > 0 && isspace((unsigned char)lower[at - 1]);
		size_t eq = at + name.size();
		while (eq < lower.size() && isspace((unsigned char)lower[eq]))
			eq++;
		if (!start || eq >= lower.size() || lower[eq] != '=') {
			at += name.size();
			continue;
		}
		size_t v = eq + 1;
		while (v < tag.size() && isspace((unsigned char)tag[v]))
			v++;
		if (v >= tag.size())
			return "";
		char quote = tag[v];
		size_t end;
		if (quote == '"' || quote == '\'') {
			end = tag.find(quote, v + 1);
			return DecodeEntities(tag.substr(v + 1, end == std::string::npos ? std::string::npos : end - v - 1));
		}
		end = v;
		while (end < tag.size() && !isspace((unsigned char)tag[end]) && tag[end] != '>')
			end++;
		return DecodeEntities(tag.substr(v, end - v));
	}
	return "";
}

class Builder {
public:
	StyledText out;

	void Text(const std::string& raw)
	{
		std::string text = DecodeEntities(raw);
		if (fPre > 0) {
			Emit(text);
			return;
		}
		// Whitespace folds to one space, none at a line's start.
		std::string folded;
		for (char c : text) {
			if (!isspace((unsigned char)c)) {
				folded += c;
				continue;
			}
			bool lineStart = folded.empty() && AtLineStart();
			bool afterSpace = folded.empty() ? EndsWithSpace() : folded.back() == ' ';
			if (!lineStart && !afterSpace)
				folded += ' ';
		}
		Emit(folded);
	}

	// A block boundary: at most one blank line between blocks.
	void Block()
	{
		TrimTrailingSpace();
		if (out.text.empty())
			return;
		if (out.text.size() >= 2 && out.text.compare(out.text.size() - 2, 2, "\n\n") == 0)
			return;
		Emit(out.text.back() == '\n' ? "\n" : "\n\n");
	}

	// A line break (<br>): always.
	void Break()
	{
		TrimTrailingSpace();
		Emit("\n");
	}

	// A new line, unless one has just begun (a list item, a table row).
	void Line()
	{
		TrimTrailingSpace();
		if (!AtLineStart())
			Emit("\n");
	}

	// A tag's style, ended by its closing tag (the innermost of that name).
	void Push(const std::string& tag, uint32_t style, const std::string& href = "")
	{
		fStack.push_back({tag, style, href});
	}

	void Pop(const std::string& tag)
	{
		for (size_t i = fStack.size(); i > 0; i--) {
			if (fStack[i - 1].tag == tag) {
				fStack.erase(fStack.begin() + (i - 1));
				return;
			}
		}
	}

	// Opens or closes a tag's style.
	void Toggle(bool closing, const std::string& tag, uint32_t style)
	{
		if (closing)
			Pop(tag);
		else
			Push(tag, style);
	}

	void Emit(const std::string& s)
	{
		if (s.empty())
			return;
		uint32_t style = kStylePlain;
		std::string href;
		for (const auto& f : fStack) {
			style |= f.style;
			if (!f.href.empty())
				href = f.href;
		}
		auto same = [&](const StyledRun& run) { return run.style == style && run.href == href; };
		if (out.runs.empty() || !same(out.runs.back())) {
			// A run that never got text gives way.
			if (!out.runs.empty() && out.runs.back().offset == out.text.size())
				out.runs.pop_back();
			if (out.runs.empty() || !same(out.runs.back())) {
				StyledRun run;
				run.offset = out.text.size();
				run.style = style;
				run.href = href;
				out.runs.push_back(run);
			}
		}
		out.text += s;
	}

	int fPre = 0;
	std::vector<int> fLists;  // per open list: 0 for ul, else the next number

private:
	struct Frame {
		std::string tag;
		uint32_t style;
		std::string href;
	};

	bool AtLineStart() const { return out.text.empty() || out.text.back() == '\n'; }
	bool EndsWithSpace() const { return !out.text.empty() && out.text.back() == ' '; }

	void TrimTrailingSpace()
	{
		while (!out.text.empty() && out.text.back() == ' ')
			out.text.pop_back();
		while (!out.runs.empty() && out.runs.back().offset > out.text.size())
			out.runs.pop_back();
	}

	std::vector<Frame> fStack;
};

}  // namespace

std::string StyledText::LinkAt(size_t offset) const
{
	std::string href;
	for (const StyledRun& run : runs) {
		if (run.offset > offset)
			break;
		href = run.href;
	}
	return offset < text.size() ? href : "";
}

StyledText NoteHTMLToText(const std::string& html)
{
	Builder b;
	int skip = 0;  // inside <script>, <style>, <template>
	size_t i = 0;
	while (i < html.size()) {
		size_t lt = html.find('<', i);
		if (lt == std::string::npos)
			lt = html.size();
		if (skip == 0 && lt > i)
			b.Text(html.substr(i, lt - i));
		if (lt >= html.size())
			break;
		// A comment.
		if (html.compare(lt, 4, "<!--") == 0) {
			size_t end = html.find("-->", lt + 4);
			i = end == std::string::npos ? html.size() : end + 3;
			continue;
		}
		size_t gt = html.find('>', lt);
		if (gt == std::string::npos)
			break;
		std::string inside = html.substr(lt + 1, gt - lt - 1);
		i = gt + 1;
		bool closing = !inside.empty() && inside[0] == '/';
		std::string name;
		for (size_t k = closing ? 1 : 0; k < inside.size() && (isalnum((unsigned char)inside[k])); k++)
			name += (char)tolower((unsigned char)inside[k]);
		if (name == "script" || name == "style" || name == "template") {
			skip += closing ? -1 : 1;
			if (skip < 0)
				skip = 0;
			continue;
		}
		if (skip > 0)
			continue;

		bool heading = name.size() == 2 && name[0] == 'h' && name[1] >= '1' && name[1] <= '6';
		uint32_t headingStyle = heading && name[1] <= '2' ? kStyleHeading : kStyleSubheading;
		if (heading) {
			b.Block();
			b.Toggle(closing, name, headingStyle);
		} else if (name == "p" || name == "div" || name == "section" || name == "article" || name == "table"
			|| name == "figure" || name == "details" || name == "summary") {
			b.Block();
		} else if (name == "tr" || name == "dt" || name == "dd") {
			b.Line();
		} else if (name == "br") {
			b.Break();
		} else if (name == "hr") {
			b.Block();
			b.Emit("\xE2\x80\x94\xE2\x80\x94\xE2\x80\x94");  // ———
			b.Block();
		} else if (name == "blockquote") {
			b.Block();
			b.Toggle(closing, name, kStyleQuote);
		} else if (name == "pre") {
			b.Block();
			b.Toggle(closing, name, kStyleCode);
			if (closing && b.fPre > 0)
				b.fPre--;
			else if (!closing)
				b.fPre++;
		} else if (name == "ul" || name == "ol") {
			if (closing) {
				if (!b.fLists.empty())
					b.fLists.pop_back();
				if (b.fLists.empty())
					b.Block();
			} else {
				if (b.fLists.empty())
					b.Block();
				b.fLists.push_back(name == "ol" ? 1 : 0);
			}
		} else if (name == "li") {
			if (!closing) {
				b.Line();
				std::string indent((b.fLists.size() > 1 ? b.fLists.size() - 1 : 0) * 4, ' ');
				std::string mark = "\xE2\x80\xA2 ";  // •
				if (!b.fLists.empty() && b.fLists.back() > 0)
					mark = std::to_string(b.fLists.back()++) + ". ";
				b.Emit(indent + mark);
			}
		} else if (name == "strong" || name == "b") {
			b.Toggle(closing, name, kStyleBold);
		} else if (name == "em" || name == "i") {
			b.Toggle(closing, name, kStyleItalic);
		} else if (name == "code" || name == "kbd" || name == "samp") {
			b.Toggle(closing, name, kStyleCode);
		} else if (name == "a") {
			if (closing) {
				b.Pop(name);
			} else {
				// Only web addresses are links (SHIO-1); anything else is plain text.
				std::string href = Trim(Attribute(inside, "href"));
				bool web = IsWebURL(href);
				b.Push(name, web ? kStyleLink : kStylePlain, web ? href : "");
			}
		} else if (name == "img" && !closing) {
			std::string alt = Trim(Attribute(inside, "alt"));
			if (!alt.empty())
				b.Text("[" + alt + "]");
		} else if (name == "td" || name == "th") {
			if (!closing)
				b.Text(" ");
		}
	}
	// Trailing blank lines go.
	while (!b.out.text.empty() && (b.out.text.back() == '\n' || b.out.text.back() == ' '))
		b.out.text.pop_back();
	while (!b.out.runs.empty() && b.out.runs.back().offset >= b.out.text.size() && b.out.runs.size() > 1)
		b.out.runs.pop_back();
	if (b.out.runs.empty())
		b.out.runs.push_back(StyledRun());
	return b.out;
}

std::string KuraNoteURL(const std::string& kura, const std::string& path, const std::string& vault)
{
	std::string url = WithSlash(kura) + "api/note?path=" + FormEncode(path);
	if (!vault.empty())
		url += "&vault=" + FormEncode(vault);
	return url;
}

bool ParseKuraNote(const std::string& body, std::string& html)
{
	json::Value v;
	if (!json::Parse(body, v) || !v.IsObject() || !v["html"].IsString())
		return false;
	html = v["html"].Str();
	return true;
}

std::string HisterPreviewURL(const std::string& hister, const std::string& url)
{
	return WithSlash(hister) + "api/preview?url=" + FormEncode(url);
}

bool ParseHisterPreview(const std::string& body, std::string& html)
{
	json::Value v;
	if (!json::Parse(body, v) || !v.IsObject() || !v["content"].IsString())
		return false;
	html = v["content"].Str();
	return true;
}

}  // namespace shiori
