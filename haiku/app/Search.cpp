#include "Search.h"

#include <memory>

#include "Http.h"
#include "Shiori.h"

using namespace shiori;

// `sentCredential`: whether the request carried any (a token, the sign-in).
static std::string Problem(const char* who, const HttpReply& reply, const ResultPage& page, bool sentCredential)
{
	if (reply.status == 0)
		return TransportProblem(who, reply.error);
	if ((reply.status == 401 || reply.status == 403) && !sentCredential)
		return std::string(who) + " wants you signed in: sign in to Hister in Settings.";
	if (reply.status == 401 || reply.status == 403) {
		// Hister answers 403 without a valid token or session; Kura 401 without a credential.
		return std::string(who) + " refused this device's credential (" + std::to_string(reply.status)
			+ "): sign in or check Settings.";
	}
	if (reply.status < 200 || reply.status > 299)
		return std::string(who) + " answered " + std::to_string(reply.status) + ".";
	if (!page.ok)
		return std::string(who) + " sent something that isn't JSON (" + page.error + ").";
	return "";
}

void RunSearch(BMessenger target, int32 generation, SearchRequest request, Config config)
{
	auto outcome = std::make_unique<SearchOutcome>();
	outcome->more = request.more;
	std::string trimmed = Trim(request.query);
	Pill pill = request.pill;
	bool hasKura = !Trim(config.kura).empty();
	bool hasHister = !Trim(config.server).empty();
	bool wantNotes, wantPages;
	if (request.more) {
		wantNotes = pill == Pill::Notes && hasKura;
		wantPages = pill != Pill::Notes && hasHister;
	} else {
		// All's notes need words; the Notes pill without any lists the recent ones.
		wantNotes = hasKura && (pill == Pill::Notes || (pill == Pill::All && !trimmed.empty()));
		wantPages = pill != Pill::Notes && hasHister && !trimmed.empty();
	}

	if (wantNotes) {
		outcome->askedNotes = true;
		// Other vaults only on the Notes pill; All asks for the default vault.
		bool notesPill = pill == Pill::Notes;
		outcome->kuraOffset = request.more ? request.kuraOffset : 0;
		std::string url = KuraSearchURL(config.kura, request.query,
			notesPill ? kPageSize : kAllNotes, outcome->kuraOffset, notesPill ? request.vault : std::string());
		HttpReply reply = HttpRequestJSON(config, "GET", url);
		if (reply.status >= 200 && reply.status <= 299)
			outcome->notes = ParseKura(reply.body);
		outcome->notesProblem = Problem("Kura", reply, outcome->notes, !CredentialHeaders(config, url).empty());
	}
	if (wantPages) {
		outcome->askedPages = true;
		std::string url = HisterSearchURL(config.server, request.query, pill == Pill::Code ? Pill::Code : Pill::Pages,
			kPageSize, request.more ? request.histerKey : std::string());
		HttpReply reply = HttpRequestJSON(config, "GET", url, std::string(), true);
		if (reply.status >= 200 && reply.status <= 299)
			outcome->pages = ParseHister(reply.body);
		outcome->pagesProblem = Problem("Hister", reply, outcome->pages, !CredentialHeaders(config, url).empty());
	}

	BMessage message(kMsgResults);
	message.AddInt32("generation", generation);
	message.AddPointer("outcome", outcome.get());
	if (target.SendMessage(&message) == B_OK)
		outcome.release();
}
