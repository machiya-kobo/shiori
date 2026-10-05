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
#include <MenuField.h>
#include <MenuItem.h>
#include <MessageFilter.h>
#include <Messenger.h>
#include <PopUpMenu.h>
#include <ScrollView.h>
#include <StringView.h>
#include <TextControl.h>

#include "../core/Query.h"
#include "../core/Results.h"
#include "Http.h"
#include "NoteWindow.h"
#include "Search.h"
#include "ResultItem.h"
#include "Shiori.h"

using namespace shiori;

namespace {

const Pill kPills[] = {Pill::All, Pill::Pages, Pill::Notes, Pill::Code};
const uint32 kMsgVault = 'Svlt';
const uint32 kMsgFocusQuery = 'Sfcq';

// The keys between the field and the list: ↓ in the field goes to the
// first result, Escape in the list back to the field.
filter_result KeyFilter(BMessage* message, BHandler** target, BMessageFilter* filter)
{
	const char* bytes = nullptr;
	if (message->FindString("bytes", &bytes) != B_OK || bytes == nullptr)
		return B_DISPATCH_MESSAGE;
	BView* view = dynamic_cast<BView*>(*target);
	BWindow* window = dynamic_cast<BWindow*>(filter->Looper());
	if (view == nullptr || window == nullptr)
		return B_DISPATCH_MESSAGE;
	BListView* list = dynamic_cast<BListView*>(window->FindView("results"));
	BTextControl* query = dynamic_cast<BTextControl*>(window->FindView("query"));
	if (list == nullptr || query == nullptr)
		return B_DISPATCH_MESSAGE;
	if (bytes[0] == B_DOWN_ARROW && view == query->TextView()) {
		for (int32 i = 0; i < list->CountItems(); i++) {
			if (list->ItemAt(i)->IsEnabled()) {
				list->MakeFocus(true);
				list->Select(i);
				list->ScrollToSelection();
				return B_SKIP_MESSAGE;
			}
		}
	}
	if (bytes[0] == B_ESCAPE && view == list) {
		list->DeselectAll();
		window->PostMessage(kMsgFocusQuery);
		return B_SKIP_MESSAGE;
	}
	return B_DISPATCH_MESSAGE;
}
const uint32 kMsgVaults = 'Svls';

void RunVaults(BMessenger target, Config config)
{
	BMessage done(kMsgVaults);
	if (!Trim(config.kura).empty()) {
		HttpReply reply = HttpRequestJSON(config, "GET", KuraVaultsURL(config.kura));
		if (reply.status >= 200 && reply.status <= 299) {
			for (const Vault& v : ParseVaults(reply.body)) {
				done.AddString("name", v.name.c_str());
				done.AddString("title", v.title.c_str());
				done.AddBool("default", v.isDefault);
			}
		}
	}
	target.SendMessage(&done);
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
	// The pills and the field by keyboard: ⌘1–⌘4, ⌘L.
	BMenu* search = new BMenu("Search");
	search->AddItem(new BMenuItem("Find" B_UTF8_ELLIPSIS, new BMessage(kMsgFocusQuery), 'L'));
	search->AddSeparatorItem();
	for (int i = 0; i < 4; i++) {
		BMessage* m = new BMessage(kMsgPill);
		m->AddInt32("pill", int32(kPills[i]));
		search->AddItem(new BMenuItem(PillLabel(kPills[i]), m, char('1' + i)));
	}
	search->AddSeparatorItem();
	search->AddItem(new BMenuItem("Quick Search" B_UTF8_ELLIPSIS, new BMessage(kMsgQuickSearch), 'K'));
	search->ItemAt(search->CountItems() - 1)->SetTarget(be_app);
	menuBar->AddItem(search, 1);

	// Return searches (the field's invocation); typing alone never does.
	fQuery = new BTextControl("query", NULL, "", new BMessage(kMsgSearchNow));
	fQuery->SetModificationMessage(new BMessage(kMsgQueryChanged));

	for (int i = 0; i < 4; i++) {
		BMessage* m = new BMessage(kMsgPill);
		m->AddInt32("pill", int32(kPills[i]));
		fPills[i] = new BButton(PillKey(kPills[i]), PillLabel(kPills[i]), m);
		fPills[i]->SetBehavior(BButton::B_TOGGLE_BEHAVIOR);
		fPills[i]->SetFlat(false);
	}
	fVaultMenu = new BPopUpMenu("vaults");
	fVaultField = new BMenuField("vault", NULL, fVaultMenu);

	fList = new BListView("results");
	fList->SetInvocationMessage(new BMessage(kMsgInvokeResult));
	BScrollView* scroll = new BScrollView("scroll", fList, 0, false, true);
	fStatus = new BStringView("status", "Type, then Return, to search Hister and Kura.");
	fStatus->SetExplicitMaxSize(BSize(B_SIZE_UNLIMITED, B_SIZE_UNSET));

	BLayoutBuilder::Group<>(this, B_VERTICAL, 0)
		.Add(menuBar)
		.AddGroup(B_VERTICAL, B_USE_SMALL_SPACING)
			.SetInsets(B_USE_WINDOW_SPACING, B_USE_SMALL_SPACING, B_USE_WINDOW_SPACING, 0)
			.Add(fQuery)
			.AddGroup(B_HORIZONTAL, B_USE_SMALL_SPACING)
				.Add(fPills[0])
				.Add(fPills[1])
				.Add(fPills[2])
				.Add(fPills[3])
				.AddGlue()
				.Add(fVaultField)
			.End()
		.End()
		.AddGroup(B_VERTICAL, 0)
			.SetInsets(B_USE_WINDOW_SPACING, B_USE_SMALL_SPACING, B_USE_WINDOW_SPACING, B_USE_SMALL_SPACING)
			.Add(scroll, 1.0)
			.Add(fStatus)
		.End();

	AddCommonFilter(new BMessageFilter(B_KEY_DOWN, &KeyFilter));
	SetPill(Pill::All);
	fQuery->MakeFocus(true);
	ResizeTo(680, 560);
	LoadVaults();
}

SearchWindow::~SearchWindow()
{
	ClearList();
}

bool SearchWindow::QuitRequested()
{
	be_app->PostMessage(B_QUIT_REQUESTED);
	return true;
}

void SearchWindow::ClearList()
{
	for (int32 i = fList->CountItems() - 1; i >= 0; i--)
		delete fList->RemoveItem(i);
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
	// The vault choice is the Notes pill's, and only with more than one vault.
	bool show = pill == Pill::Notes && fVaults.size() > 1;
	if (fVaultField->IsHidden(fVaultField) == show) {
		if (show)
			fVaultField->Show();
		else
			fVaultField->Hide();
	}
}

void SearchWindow::LoadVaults()
{
	std::thread(RunVaults, BMessenger(this), CurrentConfig()).detach();
}

void SearchWindow::ShowVaults(BMessage* message)
{
	fVaults.clear();
	const char* name;
	for (int32 i = 0; message->FindString("name", i, &name) == B_OK; i++) {
		Vault v;
		v.name = name;
		v.title = message->GetString("title", i, name);
		v.isDefault = message->GetBool("default", i, false);
		fVaults.push_back(v);
	}
	while (BMenuItem* item = fVaultMenu->RemoveItem((int32)0))
		delete item;
	BMessage* all = new BMessage(kMsgVault);
	all->AddString("vault", "all");
	fVaultMenu->AddItem(new BMenuItem("All Vaults", all));
	bool known = fVault == "all";
	for (const Vault& v : fVaults) {
		BMessage* m = new BMessage(kMsgVault);
		m->AddString("vault", v.name.c_str());
		fVaultMenu->AddItem(new BMenuItem(v.title.c_str(), m));
		known = known || v.name == fVault;
	}
	if (!known)
		fVault = "all";
	for (int32 i = 0; BMenuItem* item = fVaultMenu->ItemAt(i); i++) {
		const char* v = nullptr;
		item->Message()->FindString("vault", &v);
		item->SetMarked(v != nullptr && fVault == v);
	}
	SetPill(fPill);
}

void SearchWindow::StartSearch()
{
	int32 generation = ++fGeneration;
	fLoadingMore = false;
	std::string query = fQuery->Text();
	Config config = CurrentConfig();
	if (Trim(config.server).empty() && Trim(config.kura).empty()) {
		ClearList();
		fStatus->SetText("Set up Hister and Kura in Settings (File " B_UTF8_ELLIPSIS ").");
		return;
	}
	if (Trim(query).empty() && fPill != Pill::Notes) {
		ClearList();
		fStatus->SetText("Type, then Return, to search Hister and Kura.");
		return;
	}
	SearchRequest request;
	request.pill = fPill;
	request.query = query;
	request.vault = fVault;
	fShownQuery = query;
	fShownPill = fPill;
	fStatus->SetText("Searching" B_UTF8_ELLIPSIS);
	std::thread(RunSearch, BMessenger(this), generation, request, config).detach();
}

void SearchWindow::LoadMore()
{
	if (fLoadingMore)
		return;
	bool notes = fShownPill == Pill::Notes;
	if ((notes && fKuraNext <= 0) || (!notes && fHisterNext.empty()))
		return;
	fLoadingMore = true;
	if (MoreItem* more = dynamic_cast<MoreItem*>(fList->LastItem())) {
		more->SetLoading(true);
		fList->InvalidateItem(fList->CountItems() - 1);
	}
	SearchRequest request;
	request.pill = fShownPill;
	request.query = fShownQuery;
	request.vault = fVault;
	request.more = true;
	request.histerKey = fHisterNext;
	request.kuraOffset = fKuraNext;
	std::thread(RunSearch, BMessenger(this), fGeneration, request, CurrentConfig()).detach();
}

void SearchWindow::ShowResults(BMessage* message)
{
	SearchOutcome* raw = nullptr;
	if (message->FindPointer("outcome", (void**)&raw) != B_OK || raw == nullptr)
		return;
	std::unique_ptr<SearchOutcome> outcome(raw);
	if (message->GetInt32("generation", -1) != fGeneration)
		return;  // the query moved on

	if (outcome->more) {
		fLoadingMore = false;
		if (dynamic_cast<MoreItem*>(fList->LastItem()) != nullptr)
			delete fList->RemoveItem(fList->CountItems() - 1);
	} else {
		ClearList();
		fHisterNext.clear();
		fKuraNext = 0;
		fPagesTotal = fNotesTotal = fPagesShown = fNotesShown = 0;
	}

	bool sections = !outcome->more && outcome->askedNotes && outcome->askedPages;
	if (sections && !outcome->notes.results.empty())
		fList->AddItem(new HeaderItem("Notes"));
	for (const auto& r : outcome->notes.results)
		fList->AddItem(new ResultItem(r));
	if (sections && !outcome->pages.results.empty())
		fList->AddItem(new HeaderItem("Pages"));
	for (const auto& r : outcome->pages.results)
		fList->AddItem(new ResultItem(r));

	// What's next: Kura by offset (the Notes pill only), Hister by page_key
	// (a full page that names a next one).
	if (outcome->askedNotes && outcome->notesProblem.empty()) {
		fNotesTotal = outcome->notes.total;
		fNotesShown += int(outcome->notes.results.size());
		int next = outcome->kuraOffset + outcome->notes.received;
		fKuraNext = fShownPill == Pill::Notes && outcome->notes.received > 0 && next < outcome->notes.total
			? next : 0;
	}
	if (outcome->askedPages && outcome->pagesProblem.empty()) {
		fPagesTotal = outcome->pages.total;
		fPagesShown += int(outcome->pages.results.size());
		fHisterNext = outcome->pages.received >= kPageSize ? outcome->pages.next : std::string();
	} else if (outcome->askedPages) {
		fHisterNext.clear();
	}
	bool more = fShownPill == Pill::Notes ? fKuraNext > 0 : !fHisterNext.empty();
	if (more)
		fList->AddItem(new MoreItem());

	BString status;
	if (outcome->askedNotes || fNotesShown > 0) {
		if (!outcome->notesProblem.empty())
			status << outcome->notesProblem.c_str();
		else
			status << fNotesTotal << (fNotesTotal == 1 ? " note" : " notes");
	}
	if (outcome->askedPages || fPagesShown > 0) {
		if (status.Length() > 0)
			status << " · ";
		const char* what = fShownPill == Pill::Code ? " code document" : " page";
		if (!outcome->pagesProblem.empty())
			status << outcome->pagesProblem.c_str();
		else
			status << fPagesTotal << what << (fPagesTotal == 1 ? "" : "s");
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
	if (dynamic_cast<MoreItem*>(fList->ItemAt(fList->CurrentSelection())) != nullptr) {
		LoadMore();
		return;
	}
	const Result* r = SelectedResult();
	if (r != nullptr && !OpenInBrowser(r->url))
		fStatus->SetText("That address can't be opened.");
}

void SearchWindow::MessageReceived(BMessage* message)
{
	switch (message->what) {
		case kMsgQueryChanged:
			// Nothing searches while typing; a cleared field resets at once.
			if (Trim(fQuery->Text()).empty())
				StartSearch();
			break;
		case kMsgSearchNow:
			StartSearch();
			break;
		case kMsgFocusQuery:
			fQuery->MakeFocus(true);
			fQuery->TextView()->SelectAll();
			break;
		case kMsgPill:
			SetPill(Pill(message->GetInt32("pill", 0)));
			StartSearch();
			break;
		case kMsgVault:
			fVault = message->GetString("vault", "all");
			if (fPill == Pill::Notes)
				StartSearch();
			break;
		case kMsgVaults:
			ShowVaults(message);
			break;
		case kMsgResults:
			ShowResults(message);
			break;
		case kMsgOpenResult:
			OpenSelected();
			break;
		case kMsgInvokeResult: {
			// A note opens its preview (from Kura); anything else, the browser.
			const Result* r = SelectedResult();
			if (r != nullptr) {
				if (!OpenResult(*r))
					fStatus->SetText("That address can't be opened.");
			} else {
				OpenSelected();  // Show More…
			}
			break;
		}
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
			// A note never goes to Hister.
			if (r != nullptr && r->kind != Result::Note) {
				save.AddString("url", r->url.c_str());
				save.AddString("title", DecodeEntities(r->title).c_str());
			}
			be_app->PostMessage(&save);
			break;
		}
		case kMsgConfigChanged:
			LoadVaults();
			StartSearch();
			break;
		default:
			BWindow::MessageReceived(message);
	}
}
