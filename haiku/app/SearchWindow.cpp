#include "SearchWindow.h"

#include <memory>
#include <thread>

#include <Application.h>
#include <Button.h>
#include <Clipboard.h>
#include <LayoutBuilder.h>
#include <ListView.h>
#include <Menu.h>
#include <MenuBar.h>
#include <MenuItem.h>
#include <MessageRunner.h>
#include <Messenger.h>
#include <PopUpMenu.h>
#include <ScrollView.h>
#include <StringView.h>
#include <TextControl.h>

#include "../core/Query.h"
#include "../core/Results.h"
#include "Http.h"
#include "ResultItem.h"
#include "Shiori.h"

using namespace shiori;

namespace {

const Pill kPills[] = {Pill::All, Pill::Pages, Pill::Notes, Pill::Code};

struct Outcome {
	bool askedNotes = false, askedPages = false;
	ResultPage notes, pages;
	std::string notesProblem, pagesProblem;
};

std::string Problem(const char* who, const HttpReply& reply, const ResultPage& page)
{
	if (reply.status == 0)
		return std::string(who) + " can't be reached: " + reply.error;
	if (reply.status == 401 || reply.status == 403) {
		// Hister answers 403 without a valid token; Kura 401 without a credential.
		return std::string(who) + " refused this device's credential (" + std::to_string(reply.status)
			+ "): check Settings.";
	}
	if (reply.status < 200 || reply.status > 299)
		return std::string(who) + " answered " + std::to_string(reply.status) + ".";
	if (!page.ok)
		return std::string(who) + " sent something that isn't JSON (" + page.error + ").";
	return "";
}

void RunSearch(BMessenger target, int32 generation, Pill pill, std::string query, Config config)
{
	auto outcome = std::make_unique<Outcome>();
	std::string trimmed = Trim(query);
	bool wantNotes = (pill == Pill::All || pill == Pill::Notes) && !Trim(config.kura).empty();
	bool wantPages = (pill != Pill::Notes) && !Trim(config.server).empty() && !trimmed.empty();
	if (pill == Pill::All && trimmed.empty())
		wantNotes = false;

	if (wantNotes) {
		outcome->askedNotes = true;
		int limit = pill == Pill::All ? 3 : 30;
		HttpReply reply = HttpRequestJSON(config, "GET", KuraSearchURL(config.kura, query, limit));
		if (reply.status >= 200 && reply.status <= 299)
			outcome->notes = ParseKura(reply.body);
		outcome->notesProblem = Problem("Kura", reply, outcome->notes);
	}
	if (wantPages) {
		outcome->askedPages = true;
		HttpReply reply = HttpRequestJSON(config, "GET",
			HisterSearchURL(config.server, query, pill == Pill::Code ? Pill::Code : Pill::Pages, 30),
			std::string(), true);
		if (reply.status >= 200 && reply.status <= 299)
			outcome->pages = ParseHister(reply.body);
		outcome->pagesProblem = Problem("Hister", reply, outcome->pages);
	}

	BMessage message(kMsgResults);
	message.AddInt32("generation", generation);
	message.AddPointer("outcome", outcome.get());
	if (target.SendMessage(&message) == B_OK)
		outcome.release();
}

}  // namespace

SearchWindow::SearchWindow()
	:
	BWindow(BRect(80, 80, 760, 640), "Shiori", B_TITLED_WINDOW,
		B_AUTO_UPDATE_SIZE_LIMITS | B_ASYNCHRONOUS_CONTROLS | B_QUIT_ON_WINDOW_CLOSE)
{
	BMenuBar* menuBar = new BMenuBar("menu");
	BMenu* file = new BMenu("File");
	file->AddItem(new BMenuItem("Save URL" B_UTF8_ELLIPSIS, new BMessage(kMsgOpenSave), 'S'));
	file->AddItem(new BMenuItem("Settings" B_UTF8_ELLIPSIS, new BMessage(kMsgOpenSettings), ','));
	file->AddSeparatorItem();
	file->AddItem(new BMenuItem("Quit", new BMessage(B_QUIT_REQUESTED), 'Q'));
	file->SetTargetForItems(be_app);
	menuBar->AddItem(file);
	BMenu* result = new BMenu("Result");
	result->AddItem(new BMenuItem("Open in browser", new BMessage(kMsgOpenResult), 'O'));
	result->AddItem(new BMenuItem("Copy link", new BMessage(kMsgCopyLink), 'C', B_SHIFT_KEY));
	result->AddItem(new BMenuItem("Save to Hister" B_UTF8_ELLIPSIS, new BMessage(kMsgSaveResult)));
	menuBar->AddItem(result);

	fQuery = new BTextControl("query", NULL, "", new BMessage(kMsgSearchNow));
	fQuery->SetModificationMessage(new BMessage(kMsgQueryChanged));

	BGroupLayout* pills;
	for (int i = 0; i < 4; i++) {
		BMessage* m = new BMessage(kMsgPill);
		m->AddInt32("pill", int32(kPills[i]));
		fPills[i] = new BButton(PillKey(kPills[i]), PillLabel(kPills[i]), m);
		fPills[i]->SetBehavior(BButton::B_TOGGLE_BEHAVIOR);
		fPills[i]->SetFlat(false);
	}

	fList = new BListView("results");
	fList->SetInvocationMessage(new BMessage(kMsgOpenResult));
	BScrollView* scroll = new BScrollView("scroll", fList, 0, false, true);
	fStatus = new BStringView("status", "Type to search Hister and Kura.");
	fStatus->SetExplicitMaxSize(BSize(B_SIZE_UNLIMITED, B_SIZE_UNSET));

	BLayoutBuilder::Group<>(this, B_VERTICAL, 0)
		.Add(menuBar)
		.AddGroup(B_VERTICAL, B_USE_SMALL_SPACING)
			.SetInsets(B_USE_WINDOW_SPACING, B_USE_SMALL_SPACING, B_USE_WINDOW_SPACING, 0)
			.Add(fQuery)
			.AddGroup(B_HORIZONTAL, B_USE_SMALL_SPACING)
				.GetLayout(&pills)
				.Add(fPills[0])
				.Add(fPills[1])
				.Add(fPills[2])
				.Add(fPills[3])
				.AddGlue()
			.End()
		.End()
		.AddGroup(B_VERTICAL, 0)
			.SetInsets(B_USE_WINDOW_SPACING, B_USE_SMALL_SPACING, B_USE_WINDOW_SPACING, B_USE_SMALL_SPACING)
			.Add(scroll, 1.0)
			.Add(fStatus)
		.End();

	SetPill(Pill::All);
	fQuery->MakeFocus(true);
	ResizeTo(680, 560);
}

SearchWindow::~SearchWindow()
{
	delete fDebounce;
	for (int32 i = fList->CountItems() - 1; i >= 0; i--)
		delete fList->RemoveItem(i);
}

bool SearchWindow::QuitRequested()
{
	be_app->PostMessage(B_QUIT_REQUESTED);
	return true;
}

void SearchWindow::SetQuery(const char* text)
{
	fQuery->SetText(text);
	StartSearch();
}

void SearchWindow::SetPill(Pill pill)
{
	fPill = pill;
	for (int i = 0; i < 4; i++)
		fPills[i]->SetValue(kPills[i] == pill ? B_CONTROL_ON : B_CONTROL_OFF);
}

void SearchWindow::StartSearch()
{
	delete fDebounce;
	fDebounce = nullptr;
	int32 generation = ++fGeneration;
	std::string query = fQuery->Text();
	fLastSearch = fQuery->Text();
	fLastSearch << "\n" << PillKey(fPill);
	Config config = CurrentConfig();
	if (Trim(config.server).empty() && Trim(config.kura).empty()) {
		fStatus->SetText("Set up Hister and Kura in Settings (File " B_UTF8_ELLIPSIS ").");
		return;
	}
	if (Trim(query).empty() && fPill != Pill::Notes) {
		for (int32 i = fList->CountItems() - 1; i >= 0; i--)
			delete fList->RemoveItem(i);
		fStatus->SetText("Type to search Hister and Kura.");
		return;
	}
	fStatus->SetText("Searching" B_UTF8_ELLIPSIS);
	std::thread(RunSearch, BMessenger(this), generation, fPill, query, config).detach();
}

void SearchWindow::ShowResults(BMessage* message)
{
	Outcome* raw = nullptr;
	if (message->FindPointer("outcome", (void**)&raw) != B_OK || raw == nullptr)
		return;
	std::unique_ptr<Outcome> outcome(raw);
	if (message->GetInt32("generation", -1) != fGeneration)
		return;  // the query moved on

	for (int32 i = fList->CountItems() - 1; i >= 0; i--)
		delete fList->RemoveItem(i);
	bool sections = outcome->askedNotes && outcome->askedPages;
	if (sections && !outcome->notes.results.empty())
		fList->AddItem(new HeaderItem("Notes"));
	for (const auto& r : outcome->notes.results)
		fList->AddItem(new ResultItem(r));
	if (sections && !outcome->pages.results.empty())
		fList->AddItem(new HeaderItem("Pages"));
	for (const auto& r : outcome->pages.results)
		fList->AddItem(new ResultItem(r));

	BString status;
	if (outcome->askedNotes) {
		if (!outcome->notesProblem.empty())
			status << outcome->notesProblem.c_str();
		else
			status << outcome->notes.total << (outcome->notes.total == 1 ? " note" : " notes");
	}
	if (outcome->askedPages) {
		if (status.Length() > 0)
			status << " · ";
		const char* what = fPill == Pill::Code ? " code document" : " page";
		if (!outcome->pagesProblem.empty())
			status << outcome->pagesProblem.c_str();
		else
			status << outcome->pages.total << what << (outcome->pages.total == 1 ? "" : "s");
	}
	if (status.Length() == 0)
		status = "Nothing to search: check Settings.";
	fStatus->SetText(status.String());
}

const Result* SearchWindow::SelectedResult() const
{
	ResultItem* item = dynamic_cast<ResultItem*>(fList->ItemAt(fList->CurrentSelection()));
	return item != nullptr ? &item->Data() : nullptr;
}

void SearchWindow::OpenSelected()
{
	const Result* r = SelectedResult();
	if (r != nullptr && !OpenInBrowser(r->url))
		fStatus->SetText("That address can't be opened.");
}

void SearchWindow::MessageReceived(BMessage* message)
{
	switch (message->what) {
		case kMsgQueryChanged: {
			// SetText() also reports a change: no second search for the same words.
			BString now(fQuery->Text());
			now << "\n" << PillKey(fPill);
			if (now == fLastSearch)
				break;
			delete fDebounce;
			BMessage go(kMsgSearchNow);
			fDebounce = new BMessageRunner(BMessenger(this), &go, 350000, 1);
			break;
		}
		case kMsgSearchNow:
			StartSearch();
			break;
		case kMsgPill:
			SetPill(Pill(message->GetInt32("pill", 0)));
			StartSearch();
			break;
		case kMsgResults:
			ShowResults(message);
			break;
		case kMsgOpenResult:
			OpenSelected();
			break;
		case kMsgCopyLink: {
			const Result* r = SelectedResult();
			if (r != nullptr && be_clipboard->Lock()) {
				be_clipboard->Clear();
				BMessage* clip = be_clipboard->Data();
				clip->AddData("text/plain", B_MIME_TYPE, r->url.c_str(), r->url.size());
				be_clipboard->Commit();
				be_clipboard->Unlock();
				fStatus->SetText("Link copied.");
			}
			break;
		}
		case kMsgSaveResult: {
			const Result* r = SelectedResult();
			BMessage save(kMsgOpenSave);
			if (r != nullptr && r->kind != Result::Note) {
				save.AddString("url", r->url.c_str());
				save.AddString("title", DecodeEntities(r->title).c_str());
			}
			be_app->PostMessage(&save);
			break;
		}
		case kMsgConfigChanged:
			StartSearch();
			break;
		default:
			BWindow::MessageReceived(message);
	}
}
