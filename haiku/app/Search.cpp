#include "Search.h"

#include <memory>
#include <thread>

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
	// Where notes come from (Settings: Notes From): Kura, or Hister, which holds
	// the default vault's notes (ParseHisterNotes keeps those alone).
	bool fromHister = NotesFromHister(config);
	bool hasNotes = fromHister ? hasHister : hasKura;
	outcome->notesFromHister = fromHister;
	bool wantNotes, wantPages;
	if (request.more) {
		wantNotes = pill == Pill::Notes && hasNotes;
		wantPages = pill != Pill::Notes && hasHister;
	} else {
		// No words is the newest, as every Shiori shows an empty field: the
		// recent notes, Hister's newest pages (or code).
		wantNotes = hasNotes && (pill == Pill::Notes || pill == Pill::All);
		wantPages = pill != Pill::Notes && hasHister;
	}

	// Kura and Hister at once (on their own thread each), not one after the
	// other: the slower of the two, not the sum, before the list shows.
	std::thread notesThread;
	SearchOutcome* out = outcome.get();
	auto fetchNotes = [&config, &request, out, pill, trimmed, fromHister]() {
		bool notesPill = pill == Pill::Notes;
		int limit = notesPill ? kPageSize : (trimmed.empty() ? kAllRecentNotes : kAllNotes);
		if (fromHister) {
			// Hister's label:vault, sent with Hister's credentials only (by origin).
			std::string url = HisterSearchURL(config.server, request.query, Pill::Notes, limit,
				notesPill && request.more ? request.histerKey : std::string());
			HttpReply reply = HttpRequestJSON(config, "GET", url, std::string(), true);
			if (reply.status >= 200 && reply.status <= 299)
				out->notes = ParseHisterNotes(reply.body);
			out->notesProblem = Problem("Hister", reply, out->notes, !CredentialHeaders(config, url).empty());
			return;
		}
		std::string url = KuraSearchURL(config.kura, request.query,
			limit, out->kuraOffset, notesPill ? request.vault : std::string());
		HttpReply reply = HttpRequestJSON(config, "GET", url);
		if (reply.status >= 200 && reply.status <= 299)
			out->notes = ParseKura(reply.body);
		out->notesProblem = Problem("Kura", reply, out->notes, !CredentialHeaders(config, url).empty());
	};
	if (wantNotes) {
		outcome->askedNotes = true;
		// Other vaults only on the Notes pill from Kura; All asks for the default vault.
		outcome->kuraOffset = request.more && !fromHister ? request.kuraOffset : 0;
		if (wantPages)
			notesThread = std::thread(fetchNotes);
		else
			fetchNotes();
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
	if (notesThread.joinable())
		notesThread.join();

	BMessage message(kMsgResults);
	message.AddInt32("generation", generation);
	message.AddPointer("outcome", outcome.get());
	if (target.SendMessage(&message) == B_OK)
		outcome.release();
}
