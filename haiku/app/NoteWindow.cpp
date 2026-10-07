#include "NoteWindow.h"

#include <cmath>
#include <memory>
#include <string>
#include <thread>

#include <Button.h>
#include <Cursor.h>
#include <Font.h>
#include <LayoutBuilder.h>
#include <Messenger.h>
#include <ScrollView.h>
#include <StringView.h>
#include <TextView.h>

#include "../core/NoteText.h"
#include "../core/Query.h"
#include "../core/Results.h"
#include "Http.h"
#include "Shiori.h"

using namespace shiori;

namespace {

const uint32 kMsgNoteLoaded = 'Snld';
const uint32 kMsgOpenInKura = 'Snok';

struct Loaded {
	StyledText text;
	std::string problem;
};

void RunLoad(BMessenger target, Config config, std::string url, std::string path, std::string vault)
{
	auto loaded = std::make_unique<Loaded>();
	// From Hister (Settings: Notes From): its readable copy, by the note's
	// address, and only a note it may show (the default vault's).
	bool fromHister = NotesFromHister(config);
	const char* who = fromHister ? "Hister" : "Kura";
	HttpReply reply;
	if (fromHister && !HisterNoteShown(url))
		reply.status = 404;
	else if (fromHister)
		reply = HttpRequestJSON(config, "GET", HisterPreviewURL(config.server, url), std::string(), true);
	else
		reply = HttpRequestJSON(config, "GET", KuraNoteURL(config.kura, path, vault));
	std::string html;
	if (reply.status == 0)
		loaded->problem = TransportProblem(who, reply.error);
	else if (reply.status == 401 || reply.status == 403)
		loaded->problem = std::string(who) + " wants you signed in: sign in to Hister in Settings.";
	else if (reply.status == 404)
		loaded->problem = std::string(who) + " has no such note any more.";
	else if (reply.status < 200 || reply.status > 299)
		loaded->problem = std::string(who) + " answered " + std::to_string(reply.status) + ".";
	else if (!(fromHister ? ParseHisterPreview(reply.body, html) : ParseKuraNote(reply.body, html)))
		loaded->problem = std::string(who) + " sent something that isn't a note.";
	else
		loaded->text = NoteHTMLToText(html);
	BMessage done(kMsgNoteLoaded);
	done.AddPointer("loaded", loaded.get());
	if (target.SendMessage(&done) == B_OK)
		loaded.release();
}

}  // namespace

// The note's text: read-only, selectable, its links followed on a click.
class NoteTextView : public BTextView {
public:
	NoteTextView()
		:
		BTextView("note")
	{
		MakeEditable(false);
		SetStylable(true);
		SetWordWrap(true);
		SetInsets(12, 10, 12, 10);
	}

	void SetStyled(const StyledText& styled)
	{
		fStyled = styled;
		BFont plain(be_plain_font);
		float size = plain.Size();
		rgb_color text = ui_color(B_DOCUMENT_TEXT_COLOR);
		rgb_color link = ui_color(B_LINK_TEXT_COLOR);
		rgb_color quiet = tint_color(text, B_LIGHTEN_1_TINT);
		text_run_array* runs = AllocRunArray((int32)styled.runs.size());
		for (size_t i = 0; i < styled.runs.size(); i++) {
			const StyledRun& r = styled.runs[i];
			BFont font(r.style & kStyleCode ? be_fixed_font : be_plain_font);
			font.SetSize(size);
			uint16 face = 0;
			if (r.style & (kStyleBold | kStyleHeading | kStyleSubheading))
				face |= B_BOLD_FACE;
			if (r.style & (kStyleItalic | kStyleQuote))
				face |= B_ITALIC_FACE;
			if (face != 0)
				font.SetFace(face);
			if (r.style & kStyleHeading)
				font.SetSize(size * 1.4f);
			else if (r.style & kStyleSubheading)
				font.SetSize(size * 1.15f);
			runs->runs[i].offset = (int32)r.offset;
			runs->runs[i].font = font;
			runs->runs[i].color = r.style & kStyleLink ? link : (r.style & kStyleQuote ? quiet : text);
		}
		SetText(styled.text.c_str(), runs);
		FreeRunArray(runs);
	}

	void MouseDown(BPoint where) override
	{
		fDown = where;
		BTextView::MouseDown(where);
	}

	void MouseUp(BPoint where) override
	{
		BTextView::MouseUp(where);
		// A click (no drag, nothing selected) on a link follows it.
		int32 start, end;
		GetSelection(&start, &end);
		if (start != end || (fabsf(where.x - fDown.x) > 3 || fabsf(where.y - fDown.y) > 3))
			return;
		std::string href = fStyled.LinkAt((size_t)OffsetAt(where));
		if (!href.empty())
			OpenInBrowser(href);
	}

	void MouseMoved(BPoint where, uint32 transit, const BMessage* dragged) override
	{
		BTextView::MouseMoved(where, transit, dragged);
		bool overLink = transit != B_EXITED_VIEW && !fStyled.LinkAt((size_t)OffsetAt(where)).empty();
		if (overLink != fOverLink) {
			fOverLink = overLink;
			BCursor cursor(overLink ? B_CURSOR_ID_FOLLOW_LINK : B_CURSOR_ID_I_BEAM);
			SetViewCursor(&cursor);
		}
	}

private:
	StyledText fStyled;
	BPoint fDown;
	bool fOverLink = false;
};

NoteWindow::NoteWindow(const Result& note)
	:
	BWindow(BRect(140, 120, 700, 640), DecodeEntities(note.title).c_str(), B_DOCUMENT_WINDOW,
		B_AUTO_UPDATE_SIZE_LIMITS | B_ASYNCHRONOUS_CONTROLS | B_CLOSE_ON_ESCAPE),
	fNote(note)
{
	fText = new NoteTextView();
	BScrollView* scroll = new BScrollView("scroll", fText, 0, false, true, B_NO_BORDER);
	std::string place = note.host.empty() ? DecodeEntities(note.title)
		: note.host + " \xE2\x80\xBA " + DecodeEntities(note.title);  // ›
	if (!note.vault.empty())
		place = note.vault + " \xE2\x80\xBA " + place;
	BStringView* where = new BStringView("place", place.c_str());
	where->SetExplicitMaxSize(BSize(B_SIZE_UNLIMITED, B_SIZE_UNSET));
	fStatus = new BStringView("status", "Loading" B_UTF8_ELLIPSIS);
	fStatus->SetExplicitMaxSize(BSize(B_SIZE_UNLIMITED, B_SIZE_UNSET));
	BButton* kura = new BButton("openInKura", "Open in Kura", new BMessage(kMsgOpenInKura));

	BLayoutBuilder::Group<>(this, B_VERTICAL, 0)
		.AddGroup(B_HORIZONTAL, B_USE_SMALL_SPACING)
			.SetInsets(B_USE_WINDOW_SPACING, B_USE_SMALL_SPACING, B_USE_WINDOW_SPACING, B_USE_SMALL_SPACING)
			.Add(where)
			.Add(kura)
		.End()
		.Add(scroll, 1.0)
		.AddGroup(B_HORIZONTAL)
			.SetInsets(B_USE_WINDOW_SPACING, B_USE_SMALL_SPACING, B_USE_WINDOW_SPACING, B_USE_SMALL_SPACING)
			.Add(fStatus)
		.End();
	Load();
}

void NoteWindow::Load()
{
	Config config = CurrentConfig();
	std::thread(RunLoad, BMessenger(this), config, fNote.url, fNote.path, fNote.vault).detach();
}

void NoteWindow::ShowNote(BMessage* message)
{
	Loaded* raw = nullptr;
	if (message->FindPointer("loaded", (void**)&raw) != B_OK || raw == nullptr)
		return;
	std::unique_ptr<Loaded> loaded(raw);
	if (!loaded->problem.empty()) {
		fStatus->SetText(loaded->problem.c_str());
		return;
	}
	fText->SetStyled(loaded->text);
	fStatus->SetText(loaded->text.text.empty() ? "The note is empty." : "");
}

void NoteWindow::MessageReceived(BMessage* message)
{
	switch (message->what) {
		case kMsgNoteLoaded:
			ShowNote(message);
			break;
		case kMsgOpenInKura:
			if (!OpenInBrowser(fNote.url))
				fStatus->SetText("That address can't be opened.");
			break;
		default:
			BWindow::MessageReceived(message);
	}
}
