#include "SaveWindow.h"

#include <string>
#include <thread>

#include <Application.h>
#include <Button.h>
#include <Clipboard.h>
#include <LayoutBuilder.h>
#include <Messenger.h>
#include <StringView.h>
#include <TextControl.h>

#include "../core/Outbox.h"
#include "../core/Query.h"
#include "Http.h"
#include "Shiori.h"

using namespace shiori;

BString ClipboardURL()
{
	BString url;
	if (be_clipboard->Lock()) {
		BMessage* clip = be_clipboard->Data();
		const char* data = nullptr;
		ssize_t size = 0;
		if (clip != nullptr
			&& clip->FindData("text/plain", B_MIME_TYPE, (const void**)&data, &size) == B_OK) {
			std::string text = Trim(std::string(data, size));
			if (IsWebURL(text) && text.find_first_of(" \n\t") == std::string::npos)
				url = text.c_str();
		}
		be_clipboard->Unlock();
	}
	return url;
}

namespace {

void RunSave(BMessenger target, Config config, std::string url, std::string title, std::string label)
{
	HttpReply reply = HttpRequestJSON(config, "POST", AddURL(config.server),
		NewPageJSON(url, title, label, SHIORI_VERSION), true);
	BMessage done(kMsgSaved);
	done.AddInt32("status", reply.status);
	done.AddString("error", reply.error.c_str());
	// Unreachable, unwell (429, 5xx) or not signed in (401, 403): it waits in
	// the outbox. A refusal (406, 413, 422) is said, not kept.
	SaveOutcome outcome = OutcomeOf(reply.status);
	if (outcome == SaveOutcome::Retry || outcome == SaveOutcome::Hold) {
		std::string error;
		done.AddBool("queued", QueueSave(url, title, label, &error));
		done.AddString("queueError", error.c_str());
	} else if (outcome == SaveOutcome::Sent) {
		// Hister answers again: send what waited.
		be_app->PostMessage(kMsgDrain);
	}
	target.SendMessage(&done);
}

}  // namespace

SaveWindow::SaveWindow(const char* url, const char* title, const char* label)
	:
	BWindow(BRect(140, 140, 640, 300), "Save to Hister", B_TITLED_WINDOW,
		B_AUTO_UPDATE_SIZE_LIMITS | B_ASYNCHRONOUS_CONTROLS | B_NOT_ZOOMABLE | B_CLOSE_ON_ESCAPE)
{
	fURL = new BTextControl("url", "URL:", url, NULL);
	fTitle = new BTextControl("title", "Title:", title, NULL);
	fLabel = new BTextControl("label", "Label:", label, NULL);
	fStatus = new BStringView("status", "Drop a link here, or paste one.");
	fSave = new BButton("save", "Save", new BMessage(kMsgDoSave));
	BButton* cancel = new BButton("cancel", "Cancel", new BMessage(B_QUIT_REQUESTED));

	BLayoutBuilder::Group<>(this, B_VERTICAL)
		.SetInsets(B_USE_WINDOW_SPACING)
		.AddGrid(B_USE_SMALL_SPACING, B_USE_SMALL_SPACING)
			.AddTextControl(fURL, 0, 0)
			.AddTextControl(fTitle, 0, 1)
			.AddTextControl(fLabel, 0, 2)
		.End()
		.Add(fStatus)
		.AddGroup(B_HORIZONTAL)
			.AddGlue()
			.Add(cancel)
			.Add(fSave)
		.End();
	fURL->TextView()->SetExplicitMinSize(BSize(360, B_SIZE_UNSET));
	SetDefaultButton(fSave);
	fURL->MakeFocus(true);
}

void SaveWindow::TakeURL(const char* url)
{
	std::string text = Trim(url);
	if (!IsWebURL(text)) {
		fStatus->SetText("That isn't a web address.");
		return;
	}
	fURL->SetText(text.c_str());
	fStatus->SetText("");
}

void SaveWindow::Save()
{
	std::string url = Trim(fURL->Text());
	if (!IsWebURL(url)) {
		fStatus->SetText("Only http and https addresses can be saved.");
		return;
	}
	Config config = CurrentConfig();
	if (Trim(config.server).empty()) {
		fStatus->SetText("Set up Hister in Settings first.");
		return;
	}
	fSave->SetEnabled(false);
	fStatus->SetText("Saving" B_UTF8_ELLIPSIS);
	std::thread(RunSave, BMessenger(this), config, url, std::string(fTitle->Text()),
		Trim(fLabel->Text())).detach();
}

void SaveWindow::MessageReceived(BMessage* message)
{
	// A link dropped on the window (WebPositive's links and address bar, Tracker's bookmarks).
	if (message->WasDropped()) {
		const char* text = nullptr;
		ssize_t size = 0;
		BString url;
		if (message->FindString("be:url", &url) == B_OK) {
			TakeURL(url.String());
			return;
		}
		if (message->FindData("text/plain", B_MIME_TYPE, (const void**)&text, &size) == B_OK) {
			TakeURL(std::string(text, size).c_str());
			return;
		}
	}
	switch (message->what) {
		case kMsgDoSave:
			Save();
			break;
		case kMsgSaved: {
			int32 status = message->GetInt32("status", 0);
			fSave->SetEnabled(true);
			if (status >= 200 && status <= 299) {
				fStatus->SetText("Saved to Hister.");
				break;
			}
			std::string reason = RejectionReason(status);
			bool queued = message->GetBool("queued", false);
			if (queued && (status == 401 || status == 403))
				reason = "Kept for later: Hister wants you signed in (or a token) in Settings.";
			else if (queued)
				reason = "Kept for later: Hister can't take it now. It goes when Hister is back.";
			else if (message->HasString("queueError"))
				reason = std::string("Hister can't take it now, and it couldn't be kept: ")
					+ message->GetString("queueError", "");
			else if (reason.empty())
				reason = "Hister answered " + std::to_string(status) + ".";
			fStatus->SetText(reason.c_str());
			break;
		}
		default:
			BWindow::MessageReceived(message);
	}
}
