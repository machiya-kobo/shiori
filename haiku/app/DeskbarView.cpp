#include "DeskbarView.h"

#include <algorithm>

#include <AppFileInfo.h>
#include <Application.h>
#include <Bitmap.h>
#include <Deskbar.h>
#include <File.h>
#include <IconUtils.h>
#include <MenuItem.h>
#include <Message.h>
#include <Messenger.h>
#include <PopUpMenu.h>
#include <Resources.h>
#include <Roster.h>
#include <Window.h>

#include "Shiori.h"

namespace {

const uint32 kMsgRemoveItem = 'Sdrm';

status_t RemoveThread(void*)
{
	BDeskbar().RemoveItem(SHIORI_DESKBAR_NAME);
	return B_OK;
}

}  // namespace

DeskbarView::DeskbarView(BRect frame)
	:
	BView(frame, SHIORI_DESKBAR_NAME, B_FOLLOW_LEFT | B_FOLLOW_TOP, B_WILL_DRAW)
{
}

DeskbarView::DeskbarView(BMessage* archive)
	:
	BView(archive)
{
}

DeskbarView::~DeskbarView()
{
	delete fIcon;
}

DeskbarView* DeskbarView::Instantiate(BMessage* archive)
{
	if (!validate_instantiation(archive, "DeskbarView"))
		return nullptr;
	return new DeskbarView(archive);
}

status_t DeskbarView::Archive(BMessage* data, bool deep) const
{
	status_t status = BView::Archive(data, deep);
	if (status == B_OK)
		status = data->AddString("add_on", SHIORI_SIGNATURE);
	if (status == B_OK)
		status = data->AddString("class", "DeskbarView");
	return status;
}

void DeskbarView::AttachedToWindow()
{
	BView::AttachedToWindow();
	AdoptParentColors();
	LoadIcon();
}

void DeskbarView::LoadIcon()
{
	// The app's vector icon (Icon.rdef), drawn at the tray's size.
	delete fIcon;
	fIcon = nullptr;
	entry_ref ref;
	if (be_roster->FindApp(SHIORI_SIGNATURE, &ref) != B_OK)
		return;
	BFile file(&ref, B_READ_ONLY);
	BResources resources;
	if (file.InitCheck() != B_OK || resources.SetTo(&file) != B_OK)
		return;
	size_t size = 0;
	const void* data = resources.LoadResource(B_VECTOR_ICON_TYPE, "BEOS:ICON", &size);
	if (data == nullptr)
		return;
	BRect bounds = Bounds();
	float side = std::min(bounds.Width(), bounds.Height());
	BBitmap* icon = new BBitmap(BRect(0, 0, side, side), B_RGBA32);
	if (icon->InitCheck() != B_OK
		|| BIconUtils::GetVectorIcon((const uint8*)data, size, icon) != B_OK) {
		delete icon;
		return;
	}
	fIcon = icon;
}

void DeskbarView::Draw(BRect)
{
	if (fIcon == nullptr)
		return;
	SetDrawingMode(B_OP_ALPHA);
	SetBlendingMode(B_PIXEL_ALPHA, B_ALPHA_OVERLAY);
	BRect bounds = Bounds();
	BRect icon = fIcon->Bounds();
	DrawBitmap(fIcon, BPoint(bounds.left + (bounds.Width() - icon.Width()) / 2,
		bounds.top + (bounds.Height() - icon.Height()) / 2));
	SetDrawingMode(B_OP_COPY);
}

void DeskbarView::MouseDown(BPoint where)
{
	uint32 buttons = 0;
	if (Window() != nullptr && Window()->CurrentMessage() != nullptr)
		Window()->CurrentMessage()->FindInt32("buttons", (int32*)&buttons);
	if ((buttons & B_SECONDARY_MOUSE_BUTTON) == 0) {
		Tell(kMsgQuickSearch);
		return;
	}
	BPopUpMenu* menu = new BPopUpMenu("shiori", false, false);
	menu->SetFont(be_plain_font);
	menu->AddItem(new BMenuItem("Quick Search" B_UTF8_ELLIPSIS, new BMessage(kMsgQuickSearch)));
	menu->AddItem(new BMenuItem("Open Shiori", new BMessage(kMsgShowMain)));
	menu->AddItem(new BMenuItem("Save URL" B_UTF8_ELLIPSIS, new BMessage(kMsgOpenSave)));
	menu->AddItem(new BMenuItem("Settings" B_UTF8_ELLIPSIS, new BMessage(kMsgOpenSettings)));
	menu->AddSeparatorItem();
	menu->AddItem(new BMenuItem("Remove from Deskbar", new BMessage(kMsgRemoveItem)));
	menu->SetTargetForItems(this);
	ConvertToScreen(&where);
	menu->Go(where, true, true, ConvertToScreen(Bounds()), true);
}

void DeskbarView::Tell(uint32 what)
{
	// To the app, launched with the message if it isn't running.
	BMessage message(what);
	if (be_roster->IsRunning(SHIORI_SIGNATURE))
		BMessenger(SHIORI_SIGNATURE).SendMessage(&message);
	else
		be_roster->Launch(SHIORI_SIGNATURE, &message);
}

void DeskbarView::MessageReceived(BMessage* message)
{
	switch (message->what) {
		case kMsgQuickSearch:
		case kMsgShowMain:
		case kMsgOpenSave:
		case kMsgOpenSettings:
			Tell(message->what);
			break;
		case kMsgRemoveItem:
			// Not from Deskbar's own thread: RemoveItem waits on Deskbar.
			resume_thread(spawn_thread(RemoveThread, "shiori deskbar remove", B_NORMAL_PRIORITY, nullptr));
			break;
		default:
			BView::MessageReceived(message);
	}
}

extern "C" _EXPORT BView* instantiate_deskbar_item(float maxWidth, float maxHeight)
{
	(void)maxWidth;
	float side = maxHeight - 1;
	return new DeskbarView(BRect(0, 0, side, side));
}

bool InDeskbar()
{
	return BDeskbar().HasItem(SHIORI_DESKBAR_NAME);
}

status_t AddToDeskbar()
{
	BDeskbar deskbar;
	if (deskbar.HasItem(SHIORI_DESKBAR_NAME))
		return B_OK;
	app_info info;
	status_t status = be_app->GetAppInfo(&info);
	if (status != B_OK)
		return status;
	return deskbar.AddItem(&info.ref);
}

status_t RemoveFromDeskbar()
{
	return BDeskbar().RemoveItem(SHIORI_DESKBAR_NAME);
}
