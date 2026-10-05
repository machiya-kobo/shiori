// Shiori in the Deskbar: the icon; a click opens the quick search, the
// secondary button a menu (Quick Search, Open Shiori, Save URL, Settings,
// Remove from Deskbar). It lives in Deskbar's process, loaded from the app's
// own binary (instantiate_deskbar_item), so it does no networking: every
// action is a message to the app, which it launches when it isn't running.
#pragma once

#include <View.h>

class BBitmap;

#define SHIORI_DESKBAR_NAME "Shiori"

class _EXPORT DeskbarView : public BView {
public:
	explicit DeskbarView(BRect frame);
	explicit DeskbarView(BMessage* archive);
	~DeskbarView() override;

	static DeskbarView* Instantiate(BMessage* archive);
	status_t Archive(BMessage* data, bool deep = true) const override;

	void AttachedToWindow() override;
	void Draw(BRect updateRect) override;
	void MouseDown(BPoint where) override;
	void MessageReceived(BMessage* message) override;

private:
	void LoadIcon();
	void Tell(uint32 what);

	BBitmap* fIcon = nullptr;
};

// Deskbar's entry point when it loads the app as its item (BDeskbar::AddItem(entry_ref*)).
extern "C" _EXPORT BView* instantiate_deskbar_item(float maxWidth, float maxHeight);

// From the app: whether Shiori is in the Deskbar, and putting it there or taking it out.
bool InDeskbar();
status_t AddToDeskbar();
status_t RemoveFromDeskbar();
