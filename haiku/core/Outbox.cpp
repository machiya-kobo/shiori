#include "Outbox.h"

#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include "Json.h"

namespace shiori {

SaveOutcome OutcomeOf(int status)
{
	if (status >= 200 && status < 300)
		return SaveOutcome::Sent;
	if (status == 401 || status == 403)
		return SaveOutcome::Hold;
	if (status == 429 || status >= 500 || status == 0)
		return SaveOutcome::Retry;
	return SaveOutcome::Drop;
}

std::string QueuedPageToJSON(const QueuedPage& page)
{
	json::Value p = json::Value::MakeObject();
	p.Set("url", json::Value::MakeString(page.url));
	p.Set("title", json::Value::MakeString(page.title));
	p.Set("label", json::Value::MakeString(page.label));
	p.Set("added", json::Value::MakeNumber((double)page.added));
	json::Value entry = json::Value::MakeObject();
	entry.Set("page", p);
	entry.Set("attempts", json::Value::MakeNumber(page.attempts));
	return json::Write(entry);
}

bool QueuedPageFromJSON(const std::string& text, QueuedPage& page)
{
	json::Value v;
	if (!json::Parse(text, v) || !v.IsObject() || !v["page"].IsObject() || !v["page"]["url"].IsString())
		return false;
	const json::Value& p = v["page"];
	page.url = p["url"].Str();
	if (page.url.empty())
		return false;
	page.title = p["title"].Str();
	page.label = p["label"].Str();
	page.added = (int64_t)p["added"].Num(0);
	page.attempts = (int)v["attempts"].Num(0);
	return true;
}

Outbox::Outbox(const std::string& dir)
	:
	fDir(dir)
{
}

std::vector<std::string> Outbox::Names() const
{
	std::vector<std::string> names;
	DIR* dir = opendir(fDir.c_str());
	if (dir == nullptr)
		return names;
	while (struct dirent* e = readdir(dir)) {
		std::string name = e->d_name;
		if (name.size() > 5 && name.compare(name.size() - 5, 5, ".json") == 0)
			names.push_back(name);
	}
	closedir(dir);
	std::sort(names.begin(), names.end());
	return names;
}

bool Outbox::Read(const std::string& name, QueuedPage& page) const
{
	FILE* f = fopen((fDir + "/" + name).c_str(), "rb");
	if (f == nullptr)
		return false;
	std::string text;
	char buffer[4096];
	size_t n;
	while ((n = fread(buffer, 1, sizeof buffer, f)) > 0)
		text.append(buffer, n);
	fclose(f);
	return QueuedPageFromJSON(text, page);
}

bool Outbox::Write(const std::string& name, const QueuedPage& page, std::string* error) const
{
	if (mkdir(fDir.c_str(), 0700) != 0 && errno != EEXIST) {
		if (error != nullptr)
			*error = std::string("can't make ") + fDir + ": " + strerror(errno);
		return false;
	}
	// The addresses someone saved are theirs: 0600, written then renamed.
	std::string path = fDir + "/" + name;
	std::string temp = path + ".tmp";
	unlink(temp.c_str());
	int fd = open(temp.c_str(), O_WRONLY | O_CREAT | O_EXCL, 0600);
	FILE* f = fd >= 0 ? fdopen(fd, "wb") : nullptr;
	if (f == nullptr) {
		if (error != nullptr)
			*error = strerror(errno);
		if (fd >= 0)
			close(fd);
		return false;
	}
	std::string text = QueuedPageToJSON(page);
	bool ok = fwrite(text.data(), 1, text.size(), f) == text.size();
	ok = fclose(f) == 0 && ok;
	if (ok)
		ok = rename(temp.c_str(), path.c_str()) == 0;
	if (!ok) {
		if (error != nullptr)
			*error = strerror(errno);
		unlink(temp.c_str());
	}
	return ok;
}

void Outbox::Remove(const std::string& name) const
{
	unlink((fDir + "/" + name).c_str());
}

bool Outbox::Enqueue(QueuedPage page, int64_t now, std::string* error)
{
	int64_t first = 0;
	for (const std::string& name : Names()) {
		QueuedPage waiting;
		if (Read(name, waiting) && waiting.url == page.url) {
			if (first == 0 || (waiting.added != 0 && waiting.added < first))
				first = waiting.added;
			Remove(name);
		}
	}
	page.added = first != 0 ? first : (page.added != 0 ? page.added : now);
	page.attempts = 0;
	// Named by time, so the directory's order is the queue's.
	char name[64];
	snprintf(name, sizeof name, "%012lld-%d-%u.json", (long long)now, (int)getpid(), fCounter++);
	return Write(name, page, error);
}

std::vector<QueuedPage> Outbox::Pages() const
{
	std::vector<QueuedPage> pages;
	for (const std::string& name : Names()) {
		QueuedPage page;
		if (Read(name, page))
			pages.push_back(page);
	}
	return pages;
}

DrainResult Outbox::Drain(const std::function<int(const QueuedPage&)>& send, int64_t now)
{
	DrainResult result;
	for (const std::string& name : Names()) {
		QueuedPage page;
		if (!Read(name, page)) {
			Remove(name);  // unreadable: lost either way
			result.dropped++;
			continue;
		}
		if (page.added != 0 && now - page.added > kOutboxMaxAge) {
			Remove(name);
			result.dropped++;
			continue;
		}
		int status = send(page);
		if (status == 0) {
			result.stopped = true;
			return result;
		}
		switch (OutcomeOf(status)) {
			case SaveOutcome::Sent:
				result.sent++;
				Remove(name);
				break;
			case SaveOutcome::Drop:
				result.dropped++;
				Remove(name);
				break;
			case SaveOutcome::Hold:
				result.stopped = true;
				return result;
			case SaveOutcome::Retry:
				page.attempts++;
				if (page.attempts >= kOutboxMaxAttempts) {
					result.dropped++;
					Remove(name);
				} else {
					Write(name, page, nullptr);
				}
				result.stopped = true;
				return result;
		}
	}
	return result;
}

}  // namespace shiori
