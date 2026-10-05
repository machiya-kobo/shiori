// The headless test of Shiori for Haiku's portable core: query building
// (against search-core.js's own answers, tests/vectors.inc), reply
// parsing, the save body, the credential rules and the config file.
// Runs on Linux and Haiku: make -f Makefile.test test
#include <cstdio>
#include <cstdlib>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

#include "../core/Config.h"
#include "../core/Json.h"
#include "../core/Query.h"
#include "../core/Results.h"

using namespace shiori;

#include "vectors.inc"

static int gFailed = 0;
static int gPassed = 0;

static void Check(const std::string& name, const std::string& got, const std::string& want)
{
	if (got == want) {
		gPassed++;
		return;
	}
	gFailed++;
	printf("FAIL %s\n  got:  %s\n  want: %s\n", name.c_str(), got.c_str(), want.c_str());
}

static void CheckTrue(const std::string& name, bool ok)
{
	Check(name, ok ? "true" : "false", "true");
}

static void TestVectors()
{
	for (const Vec& v : kVectors) {
		std::string fn = v.fn, in = v.in, got;
		if (fn == "prefixLastWord") got = PrefixLastWord(in);
		else if (fn == "prefixLastWordUnion") got = PrefixLastWord(in, true);
		else if (fn == "histerText") got = HisterText(in);
		else if (fn == "codeHisterText") got = HisterText(CodeQuery(in));
		else if (fn == "filesHisterText") got = HisterText(FilesQuery(in));
		else if (fn == "webQuery") got = WebQuery(in);
		else if (fn == "kuraQuery") got = KuraQuery(in);
		else if (fn == "kuraURL") got = KuraSearchURL("https://kura.example/", in, 5);
		else if (fn == "histerSearchURL") got = HisterSearchURL("https://h.example", in, Pill::Pages);
		else got = "(unknown function)";
		Check(fn + "(" + in + ")", got, v.want);
	}
	// Idempotent, as search-core's tests check.
	Check("histerText twice", HisterText(HisterText("x")), HisterText("x"));
	Check("kuraURL recent", KuraSearchURL("https://kura.example", "", 20), "https://kura.example/api/recent?limit=20&offset=0");
	Check("code pill URL contains the term",
		HisterSearchURL("https://h.example/", "tag page", Pill::Code).find("metadata.source%3Acode+tag") != std::string::npos ? "yes" : "no", "yes");
}

static void TestJson()
{
	json::Value v;
	std::string err;
	CheckTrue("parse object", json::Parse("{\"a\":[1,2.5,\"x\\u00e9\\ud83d\\ude00\"],\"b\":{\"c\":null},\"d\":true}", v, &err));
	Check("array number", std::to_string(int(v["a"].items[0].Num())), "1");
	Check("unicode escape", v["a"].items[2].Str(), "x\xC3\xA9\xF0\x9F\x98\x80");
	Check("missing member", v["zz"]["y"].Str("none"), "none");
	CheckTrue("bad JSON rejected", !json::Parse("{\"a\":}", v, &err));
	CheckTrue("trailing junk rejected", !json::Parse("{} x", v, &err));
	std::string deep(100, '[');
	CheckTrue("deep nesting rejected", !json::Parse(deep, v, &err));
	Check("quote", json::Quote("a\"b\\c\n\x01"), "\"a\\\"b\\\\c\\n\\u0001\"");
}

static void TestResults()
{
	ResultPage hister = ParseHister(
		"{\"total\":3,\"documents\":["
		"{\"url\":\"https://www.Example.com:8443/a\",\"title\":\"A &amp; B\",\"text\":\"the <mark>pi</mark> &lt;5&gt;\",\"label\":\"tech\"},"
		"{\"url\":\"javascript:alert(1)\",\"title\":\"bad\"},"
		"{\"url\":\"https://git.example/x\",\"title\":\"\",\"domain\":\"git.example\",\"metadata\":{\"source\":\"code\"}}]}");
	CheckTrue("hister ok", hister.ok);
	Check("hister total", std::to_string(hister.total), "3");
	Check("hister rows (javascript: dropped)", std::to_string(hister.results.size()), "2");
	Check("hister host", hister.results[0].host, "example.com");
	Check("hister title kept raw", hister.results[0].title, "A &amp; B");
	Check("hister empty title", hister.results[1].title, "https://git.example/x");
	CheckTrue("hister code kind", hister.results[1].kind == Result::Code);
	Check("snippet text", SnippetText(hister.results[0].snippet), "the pi <5>");
	auto runs = SnippetRuns("a <mark>b</mark> c");
	Check("snippet runs", std::to_string(runs.size()) + (runs[1].second ? "m" : "-") + runs[1].first, "3mb");

	ResultPage kura = ParseKura(
		"{\"total\":25,\"took_ms\":3,\"results\":[{\"path\":\"Projects/Garden Plan.md\",\"title\":\"Garden Plan\","
		"\"url\":\"https://kura.example/n/Projects/Garden%20Plan\",\"snippet\":\"<mark>Garden</mark> Plan\",\"folder\":\"Projects\","
		"\"created\":1790380800,\"changed\":1790553600,\"tags\":[\"type/idea\"]},{\"path\":\"x.md\",\"url\":\"file:///x\"}]}");
	CheckTrue("kura ok", kura.ok);
	Check("kura total", std::to_string(kura.total), "25");
	Check("kura rows", std::to_string(kura.results.size()), "1");
	Check("kura folder", kura.results[0].host, "Projects");
	CheckTrue("kura note kind", kura.results[0].kind == Result::Note);
	CheckTrue("kura junk", !ParseKura("<html>").ok);
	Check("entities", DecodeEntities("&#x41;&#66;&quot;&bogus;&"), "AB\"&bogus;&");
}

static void TestSave()
{
	Check("newPage", NewPageJSON("https://a.example/", "A", "", "0.1.0"),
		"{\"url\":\"https://a.example/\",\"title\":\"A\",\"metadata\":{\"source\":\"shiori\",\"client\":\"shiori\","
		"\"client_version\":\"0.1.0\",\"via\":\"haiku\",\"ignore_skip_rules\":true}}");
	Check("newPage label", NewPageJSON("https://a.example/", "", "books", "0").find("\"label\":\"books\"") != std::string::npos ? "yes" : "no", "yes");
	Check("add URL", AddURL("https://h.example"), "https://h.example/api/add");
	CheckTrue("web URL", IsWebURL("HTTPS://a.example"));
	CheckTrue("not javascript", !IsWebURL("javascript:alert(1)"));
	CheckTrue("not bare scheme", !IsWebURL("https:///x"));
	CheckTrue("not file", !IsWebURL("file:///etc/passwd"));
	Check("rejection 422", RejectionReason(422), "Hister refused it as sensitive (it looks like it holds a secret).");
}

static void TestCredentials()
{
	const std::string room = "mht_" + std::string(43, 'A');
	Config c;
	c.server = "https://hister.example/";
	c.histerToken = "ABCDEFGHJKLMNPQRSTUVWXYZ23";
	c.kura = "https://kura.example";
	c.roomToken = room;

	Headers h = CredentialHeaders(c, "https://hister.example/search?q=1");
	Check("hister gets its token", h.size() == 1 ? h[0].first + ": " + h[0].second : "none", "X-Access-Token: ABCDEFGHJKLMNPQRSTUVWXYZ23");
	h = CredentialHeaders(c, "https://kura.example/api/search");
	Check("kura gets the room token", h.size() == 1 ? h[0].first + ": " + h[0].second : "none", "Authorization: Bearer " + room);
	for (const auto& kv : h)
		CheckTrue("never Hister's token to Kura", kv.second.find(c.histerToken) == std::string::npos);
	Check("elsewhere gets nothing", std::to_string(CredentialHeaders(c, "https://evil.example/").size()), "0");
	Check("user@ gets nothing", std::to_string(CredentialHeaders(c, "https://x@hister.example/").size()), "0");
	Check("http vs https differ", std::to_string(CredentialHeaders(c, "http://hister.example/").size()), "0");
	Check("default port folds", std::to_string(CredentialHeaders(c, "https://hister.example:443/a").size()), "1");

	Config wrong = c;
	wrong.roomToken = c.histerToken;  // Hister's token pasted into the room field
	Check("non-mht room token refused", std::to_string(CredentialHeaders(wrong, "https://kura.example/").size()), "0");
	wrong.roomToken = "mch_abcdefghijkl";
	Check("mch_ not sent", std::to_string(CredentialHeaders(wrong, "https://kura.example/").size()), "0");
	Config same = c;
	same.kura = "https://hister.example/kura/";
	h = CredentialHeaders(same, "https://hister.example/kura/api/search");
	Check("room on Hister's origin: Hister's rule only", h.size() == 1 ? h[0].first : "none", "X-Access-Token");

	CheckTrue("configured hister", IsConfiguredOrigin(c, "https://hister.example/api/add"));
	CheckTrue("configured kura", IsConfiguredOrigin(c, "https://KURA.example:443/api/recent"));
	CheckTrue("unconfigured", !IsConfiguredOrigin(c, "https://other.example/"));
	Check("origin", OriginOf("HTTP://Example.COM:80/a?b#c"), "http://example.com");
	Check("origin port", OriginOf("http://127.0.0.1:8401/"), "http://127.0.0.1:8401");
	Check("origin bad", OriginOf("ftp://x/"), "");
	Check("short hister token", CheckedHisterToken("short"), "");
	Check("spaced hister token", CheckedHisterToken("abc defghij"), "");
}

static void TestConfigFile()
{
	char dir[] = "/tmp/shiori-test-XXXXXX";
	if (mkdtemp(dir) == nullptr) {
		Check("mkdtemp", "failed", "ok");
		return;
	}
	std::string path = std::string(dir) + "/Shiori/config.json";
	Config c;
	c.server = "http://127.0.0.1:8401/";
	c.histerToken = "tok\"en-with-quote";
	c.kura = "http://127.0.0.1:8402/";
	c.roomToken = "mht_x";
	std::string err;
	CheckTrue("save", SaveConfig(path, c, &err));
	Check("mode 0600", std::to_string(ConfigMode(path)), std::to_string(0600));
	struct stat st;
	stat((std::string(dir) + "/Shiori").c_str(), &st);
	Check("dir 0700", std::to_string(st.st_mode & 0777), std::to_string(0700));
	chmod(path.c_str(), 0644);
	CheckTrue("save again", SaveConfig(path, c, &err));
	Check("mode back to 0600", std::to_string(ConfigMode(path)), std::to_string(0600));
	Config back;
	CheckTrue("load", LoadConfig(path, back, &err));
	Check("round trip", back.histerToken + "|" + back.server + "|" + back.kura + "|" + back.roomToken,
		c.histerToken + "|" + c.server + "|" + c.kura + "|" + c.roomToken);
	Check("missing file mode", std::to_string(ConfigMode(std::string(dir) + "/none")), "-1");
	unlink(path.c_str());
	rmdir((std::string(dir) + "/Shiori").c_str());
	rmdir(dir);
}

int main()
{
	TestVectors();
	TestJson();
	TestResults();
	TestSave();
	TestCredentials();
	TestConfigFile();
	printf("%d passed, %d failed\n", gPassed, gFailed);
	return gFailed ? 1 : 0;
}
