// Pages waiting for Hister, by the iOS outbox's rules (HisterKit's Saving,
// linux/src/outbox.js): one JSON file per page in a 0700 directory
// (~/config/settings/Shiori/outbox), oldest first, one per URL (a newer save
// replaces it and keeps the first time). Unreachable, 429 and 5xx queue a
// save; 406/413/422 and other 4xx drop it; 5xx/429 get five tries; a page
// waiting 14 days is dropped unsent. A 401/403 (signed out, or no token yet)
// keeps it, no try counted, until the next drain. No credential is stored:
// the drain sends with the settings of the moment. Portable: no Be headers.
#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

namespace shiori {

struct QueuedPage {
	std::string url;
	std::string title;
	std::string label;
	int64_t added = 0;   // unix seconds, when first saved
	int attempts = 0;
};

enum class SaveOutcome {
	Sent,    // 2xx
	Drop,    // Hister refused it for good
	Retry,   // 429, 5xx: counted, the drain stops
	Hold,    // 401, 403: kept, not counted, the drain stops
};

SaveOutcome OutcomeOf(int status);

const int kOutboxMaxAttempts = 5;
const int64_t kOutboxMaxAge = 14 * 24 * 60 * 60;

std::string QueuedPageToJSON(const QueuedPage& page);
bool QueuedPageFromJSON(const std::string& text, QueuedPage& page);

struct DrainResult {
	int sent = 0;
	int dropped = 0;
	bool stopped = false;   // something is still waiting for the next drain
};

class Outbox {
public:
	explicit Outbox(const std::string& dir);

	// Queues a page (stamped `now` unless it already waits: then the first time is kept).
	bool Enqueue(QueuedPage page, int64_t now, std::string* error = nullptr);
	// The waiting pages, oldest first (unreadable files are left out).
	std::vector<QueuedPage> Pages() const;
	int Count() const { return (int)Pages().size(); }

	// Sends oldest first; `send` answers the HTTP status, or 0 when Hister
	// can't be reached (which stops the drain, nothing counted).
	DrainResult Drain(const std::function<int(const QueuedPage&)>& send, int64_t now);

private:
	std::vector<std::string> Names() const;
	bool Write(const std::string& name, const QueuedPage& page, std::string* error) const;
	bool Read(const std::string& name, QueuedPage& page) const;
	void Remove(const std::string& name) const;

	std::string fDir;
	unsigned fCounter = 0;
};

}  // namespace shiori
