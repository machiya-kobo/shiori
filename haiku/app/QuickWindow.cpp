#include "QuickWindow.h"

#include <memory>
#include <thread>

#include <Application.h>
#include <LayoutBuilder.h>
#include <ListView.h>
#include <MessageFilter.h>
#include <Screen.h>
#include <ScrollView.h>
#include <StringView.h>
#include <TextControl.h>

#include "../core/Query.h"
#include "ResultItem.h"
#include "Search.h"
#include "Shiori.h"

using namespace shiori;

namespace {

const uint32 kMsgQuickGo = 'Sqqg';
const uint32 kMsgQuickInvoke = 'Sqqi';
const uint32 kMsgQuickDown = 'Sqqd';
const uint32 kMsgQuickInShiori = 'Sqqs';

}  // namespace

// The field: ↓ hands the keyboard to the results.
class QuickField : public BTextControl {
public:
	QuickField()
		:
		BTextControl("query", NULL, "", new BMessage(kMsgQuickGo))
	{
	}

	void AttachedToWindow() override
	{
		BTextControl::AttachedToWindow();
		// The text view gets the keys: watch them there.
		TextView()->AddFilter(new BMessageFilter(B_KEY_DOWN, &KeyFilter));
	}

private:
	static filter_result KeyFilter(BMessage* message, BHandler** target, BMessageFilter*)
	{
		const char* bytes = nullptr;
		if (message->FindString("bytes", &bytes) != B_OK || bytes == nullptr)
			return B_DISPATCH_MESSAGE;
		BView* view = dynamic_cast<BView*>(*target);
		BWindow* window = view != nullptr ? view->Window() : nullptr;
		if (window == nullptr)
			return B_DISPATCH_MESSAGE;
		if (bytes[0] == B_DOWN_ARROW) {
			window->PostMessage(kMsgQuickDown);
			return B_SKIP_MESSAGE;
		}
		return B_DISPATCH_MESSAGE;
	}
};

QuickWindow::QuickWindow()
	:
	BWindow(BRect(0, 0, 520, 360), "Quick Search", B_FLOATING_WINDOW_LOOK, B_FLOATING_ALL_WINDOW_FEEL,
		B_AUTO_UPDATE_SIZE_LIMITS | B_ASYNCHRONOUS_CONTROLS | B_NOT_ZOOMABLE | B_NOT_MINIMIZABLE
			| B_CLOSE_ON_ESCAPE)
{
	fQuery = new QuickField();
	fList = new BListView("results");
	fList->SetInvocationMessage(new BMessage(kMsgQuickInvoke));
	BScrollView* scroll = new BScrollView("scroll", fList, 0, false, true);
	fStatus = new BStringView("status", "Return searches. Command-Return opens the search in Shiori.");
	fStatus->SetExplicitMaxSize(BSize(B_SIZE_UNLIMITED, B_SIZE_UNSET));

	BLayoutBuilder::Group<>(this, B_VERTICAL, B_USE_SMALL_SPACING)
		.SetInsets(B_USE_SMALL_SPACING)
		.Add(fQuery)
		.Add(scroll, 1.0)
		.Add(fStatus);
	AddShortcut(B_ENTER, B_COMMAND_KEY, new BMessage(kMsgQuickInShiori));

	// Near the top of the screen, centred, as a launcher sits.
	BRect screen = BScreen(this).Frame();
	MoveTo(screen.left + (screen.Width() - Frame().Width()) / 2, screen.top + screen.Height() / 5);
	fQuery->MakeFocus(true);
}

QuickWindow::~QuickWindow()
{
	ClearList();
}

void QuickWindow::ClearList()
{
	for (int32 i = fList->CountItems() - 1; i >= 0; i--)
		delete fList->RemoveItem(i);
}

void QuickWindow::Search()
{
	int32 generation = ++fGeneration;
	std::string query = Trim(fQuery->Text());
	if (query.empty()) {
		ClearList();
		return;
	}
	SearchRequest request;
	request.pill = Pill::All;
	request.query = fQuery->Text();
	fStatus->SetText("Searching" B_UTF8_ELLIPSIS);
	std::thread(RunSearch, BMessenger(this), generation, request, CurrentConfig()).detach();
}

void QuickWindow::MessageReceived(BMessage* message)
{
	switch (message->what) {
		case kMsgQuickGo:
			Search();
			break;
		case kMsgResults: {
			SearchOutcome* raw = nullptr;
			if (message->FindPointer("outcome", (void**)&raw) != B_OK || raw == nullptr)
				break;
			std::unique_ptr<SearchOutcome> outcome(raw);
			if (message->GetInt32("generation", -1) != fGeneration)
				break;
			ClearList();
			for (const auto& r : outcome->notes.results)
				fList->AddItem(new ResultItem(r));
			for (const auto& r : outcome->pages.results)
				fList->AddItem(new ResultItem(r));
			std::string problem = !outcome->pagesProblem.empty() ? outcome->pagesProblem : outcome->notesProblem;
			if (!problem.empty())
				fStatus->SetText(problem.c_str());
			else if (fList->IsEmpty())
				fStatus->SetText("Nothing found.");
			else
				fStatus->SetText("\xE2\x86\x93 to choose, Return to open, Command-Return for Shiori's window.");
			break;
		}
		case kMsgQuickDown:
			if (!fList->IsEmpty()) {
				fList->MakeFocus(true);
				fList->Select(0);
			}
			break;
		case kMsgQuickInvoke: {
			ResultItem* item = dynamic_cast<ResultItem*>(fList->ItemAt(fList->CurrentSelection()));
			if (item != nullptr && OpenResult(item->Data()))
				PostMessage(B_QUIT_REQUESTED);
			break;
		}
		case kMsgQuickInShiori: {
			BMessage show(kMsgShowQuery);
			show.AddString("query", fQuery->Text());
			be_app->PostMessage(&show);
			PostMessage(B_QUIT_REQUESTED);
			break;
		}
		default:
			BWindow::MessageReceived(message);
	}
}
