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
#include "../core/NoteText.h"
#include "../core/Outbox.h"
#include "../core/Query.h"
#include "../core/Results.h"
#include "../core/SignIn.h"

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
		else if (fn == "kuraURLVault") got = KuraSearchURL("https://kura.example/", in, 30, 30, "all");
		else if (fn == "histerSearchURL") got = HisterSearchURL("https://h.example", in, Pill::Pages);
		else got = "(unknown function)";
		Check(fn + "(" + in + ")", got, v.want);
	}
	// Idempotent, as search-core's tests check.
	Check("histerText twice", HisterText(HisterText("x")), HisterText("x"));
	Check("kuraURL recent", KuraSearchURL("https://kura.example", "", 20), "https://kura.example/api/recent?limit=20&offset=0");
	Check("Hister's next page", HisterSearchURL("https://h.example/", "beos", Pill::Pages, 30, "k2"),
		"https://h.example/search?query=" + FormEncode("{\"text\":\"" + HisterText("beos") + "\",\"highlight\":\"HTML\",\"limit\":30,\"page_key\":\"k2\"}"));
	Check("vaults URL", KuraVaultsURL("https://kura.example"), "https://kura.example/api/vaults");
	ResultPage hp = ParseHister("{\"total\":3,\"page_key\":\"k2\",\"documents\":[{\"url\":\"javascript:x\"},{\"url\":\"https://a.example/\"}]}");
	Check("Hister's page_key and count", hp.next + " " + std::to_string(hp.received) + " " + std::to_string(hp.results.size()), "k2 2 1");
	ResultPage kp = ParseKura("{\"total\":9,\"results\":[{\"url\":\"https://k.example/n/a\"},{\"url\":\"file:///x\"}]}");
	Check("Kura's count, dropped rows included", std::to_string(kp.received) + " " + std::to_string(kp.results.size()), "2 1");
	std::vector<Vault> vaults = ParseVaults("{\"vaults\":[{\"name\":\"personal\",\"title\":\"Personal\",\"default\":true},"
		"{\"name\":\"work\",\"title\":\"Work\",\"private\":true},{\"name\":\"Bad Name\"},{\"name\":\"bare\"}]}");
	Check("vaults parsed", vaults.size() == 3 ? vaults[0].title + "/" + (vaults[0].isDefault ? "d" : "-") + " " + vaults[1].name + " " + vaults[2].title : "count " + std::to_string(vaults.size()),
		"Personal/d work bare");
	Check("not a vault list", std::to_string(ParseVaults("[]").size()), "0");
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

// Signing in to Hister: as Linux does it (scripts/linux.test.mjs' sign-in cases).
static void TestSignIn()
{
	const std::string session = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-abcde";
	const std::string sid = "mhs_" + std::string(43, 'Z');
	Check("a session", CheckedHisterSession("  " + session + " "), session);
	Check("not a session", CheckedHisterSession("short"), "");
	Check("an id", CheckedSessionID(sid), sid);
	Check("not an id (mht_)", CheckedSessionID("mht_" + std::string(43, 'Z')), "");

	// The record: only for its own server's origin.
	SignIn in;
	in.session = session;
	in.sid = sid;
	in.username = "alex";
	std::string text = SignInToJSON("https://hister.example/", in);
	SignIn back;
	CheckTrue("record round trip", SignInFromJSON(text, "https://HISTER.example:443/", back) && back.sid == sid && back.username == "alex");
	CheckTrue("another server's record is refused", !SignInFromJSON(text, "https://other.example/", back));
	CheckTrue("a broken id is refused", !SignInFromJSON("{\"server\":\"https://hister.example\",\"session\":\"" + session + "\",\"sid\":\"mhs_x\"}", "https://hister.example/", back));

	// Hister's Set-Cookie: the session, not one that clears it.
	Check("session from Set-Cookie", SessionFromSetCookie({"other=1", "hister=" + session + "; Path=/; HttpOnly"}), session);
	Check("a cleared cookie isn't a session", SessionFromSetCookie({"hister=" + session + "; Max-Age=0"}), "");
	Check("no cookie", SessionFromSetCookie({}), "");

	// The bodies, as JSON.stringify writes them.
	Check("login body", LoginBody("alex", "p\"w"), "{\"username\":\"alex\",\"password\":\"p\\\"w\"}");
	Check("trade body", AppSessionBody(session, "Shiori on haiku"), "{\"hister\":\"" + session + "\",\"label\":\"Shiori on haiku\"}");
	SignIn traded;
	CheckTrue("the helper's answer", SignInFromTrade("{\"sid\":\"" + sid + "\",\"username\":\"alex\"}", session, traded) && traded.IsSet());
	CheckTrue("a helper answer without an id", !SignInFromTrade("{\"username\":\"alex\"}", session, traded));
	CheckTrue("offered while Hister has users", SignInAvailable(200, "{\"ok\":true,\"hister\":\"ok\"}"));
	CheckTrue("not offered otherwise", !SignInAvailable(200, "{\"ok\":false}") && !SignInAvailable(503, ""));
	Check("401 in words", LoginProblem(401), "Hister didn't recognise that name and password.");

	// Signed in: Hister gets its session (and the token), the rooms the id, never the session.
	Config c;
	c.server = "https://hister.example/";
	c.kura = "https://kura.example/";
	c.histerToken = "ABCDEFGHJKLMNPQRSTUVWXYZ23";
	c.roomToken = "mht_" + std::string(43, 'r');
	c.signIn = in;
	Headers h = CredentialHeaders(c, "https://hister.example/search");
	Check("Hister signed in: token and session", std::to_string(h.size()), "2");
	Check("Hister's cookie", h.size() == 2 ? h[1].first + ": " + h[1].second : "", "Cookie: hister=" + session);
	h = CredentialHeaders(c, "https://kura.example/api/search");
	Check("Kura signed in: the id, over the room token", h.size() == 1 ? h[0].second : "", "Bearer " + sid);
	c.signIn = SignIn();
	h = CredentialHeaders(c, "https://kura.example/api/search");
	Check("Kura not signed in: the room token", h.size() == 1 ? h[0].second : "", "Bearer mht_" + std::string(43, 'r'));

	// The file: 0600, and removed on sign-out.
	char dir[] = "/tmp/shiori-signin-XXXXXX";
	if (mkdtemp(dir) == nullptr)
		return;
	std::string path = std::string(dir) + "/Shiori/sign-in.json";
	CheckTrue("saved", SaveSignIn(path, "https://hister.example/", in));
	struct stat st;
	Check("sign-in.json is 0600", stat(path.c_str(), &st) == 0 ? std::to_string(st.st_mode & 0777) : "missing", std::to_string(0600));
	SignIn loaded;
	CheckTrue("loaded back", LoadSignIn(path, "https://hister.example/", loaded) && loaded.session == session);
	CheckTrue("removed", RemoveSignIn(path) && !LoadSignIn(path, "https://hister.example/", loaded));
	CheckTrue("removing again is fine", RemoveSignIn(path));
	rmdir((std::string(dir) + "/Shiori").c_str());
	rmdir(dir);
}

// The outbox: the iOS rules (linux.test.mjs' outbox cases), with 401/403 held.
static void TestTransport()
{
	CheckTrue("a certificate error", IsCertificateError("SSL error: certificate verify failed"));
	CheckTrue("a TLS handshake", IsCertificateError("TLS handshake failure"));
	CheckTrue("not one", !IsCertificateError("Connection refused") && !IsCertificateError(""));
	Check("untrusted in words", TransportProblem("Hister", "certificate verify failed"),
		"Couldn't make a secure connection to Hister (certificate verify failed): its certificate may not be trusted here (trust it on this computer), or it doesn't answer https.");
	CheckTrue("netservices2's TLS failure, as Http.cpp marks it",
		IsCertificateError("secure connection failed: Network error during operation ([BSocket::Connect()] Network error during operation Underlying System Error: -2147483633 (Operation not allowed))"));
	CheckTrue("the same error on http isn't one",
		!IsCertificateError("Network error during operation ([BSocket::Connect()] Network error during operation Underlying System Error: -2147483633 (Operation not allowed))"));
	Check("unreachable in words", TransportProblem("Kura", "Connection refused"),
		"Kura can't be reached (Connection refused): check your network or VPN, then try again.");
}

static void TestOutbox()
{
	Check("NewPageJSON with added", NewPageJSON("https://a.example/", "A", "", "1.0", 1790000000),
		"{\"url\":\"https://a.example/\",\"title\":\"A\",\"added\":1790000000,\"metadata\":{\"source\":\"shiori\",\"client\":\"shiori\",\"client_version\":\"1.0\",\"via\":\"haiku\",\"ignore_skip_rules\":true}}");
	CheckTrue("2xx sent", OutcomeOf(201) == SaveOutcome::Sent);
	CheckTrue("406/413/422/404 dropped", OutcomeOf(406) == SaveOutcome::Drop && OutcomeOf(413) == SaveOutcome::Drop
		&& OutcomeOf(422) == SaveOutcome::Drop && OutcomeOf(404) == SaveOutcome::Drop);
	CheckTrue("429/5xx retried", OutcomeOf(429) == SaveOutcome::Retry && OutcomeOf(502) == SaveOutcome::Retry);
	CheckTrue("401/403 held", OutcomeOf(401) == SaveOutcome::Hold && OutcomeOf(403) == SaveOutcome::Hold);

	char dir[] = "/tmp/shiori-outbox-XXXXXX";
	if (mkdtemp(dir) == nullptr)
		return;
	std::string path = std::string(dir) + "/outbox";
	Outbox box(path);
	QueuedPage a;
	a.url = "https://a.example/";
	a.title = "A";
	QueuedPage b;
	b.url = "https://b.example/";
	CheckTrue("queued", box.Enqueue(a, 1000) && box.Enqueue(b, 1001));
	struct stat st;
	Check("outbox dir 0700", stat(path.c_str(), &st) == 0 ? std::to_string(st.st_mode & 0777) : "missing", std::to_string(0700));
	a.title = "A, again";
	box.Enqueue(a, 2000);
	std::vector<QueuedPage> pages = box.Pages();
	Check("one per URL", std::to_string(pages.size()), "2");
	Check("oldest first", pages.size() == 2 ? pages[0].url : "", "https://b.example/");
	Check("a newer save keeps the first time", pages.size() == 2 ? std::to_string(pages[1].added) + " " + pages[1].title : "",
		"1000 A, again");

	// Unreachable: nothing counted, all kept.
	DrainResult r = box.Drain([](const QueuedPage&) { return 0; }, 3000);
	CheckTrue("unreachable stops", r.stopped && r.sent == 0 && box.Count() == 2);
	// Signed out: kept, no try counted.
	r = box.Drain([](const QueuedPage&) { return 403; }, 3000);
	CheckTrue("403 holds", r.stopped && box.Count() == 2 && box.Pages()[0].attempts == 0);
	// 5xx: counted; the fifth drops it.
	for (int i = 0; i < 4; i++)
		box.Drain([](const QueuedPage&) { return 503; }, 3000);
	Check("four tries counted", std::to_string(box.Pages()[0].attempts), "4");
	r = box.Drain([](const QueuedPage&) { return 503; }, 3000);
	CheckTrue("the fifth drops it", r.dropped == 1 && box.Count() == 1);
	// A refusal drops it; a success sends the rest.
	box.Enqueue(b, 3001);
	std::vector<std::string> seen;
	r = box.Drain([&seen](const QueuedPage& p) {
		seen.push_back(p.url);
		return p.url == "https://a.example/" ? 422 : 201;
	}, 3002);
	CheckTrue("refused dropped, the rest sent", !r.stopped && r.dropped == 1 && r.sent == 1 && box.Count() == 0);
	Check("drain order", seen.size() == 2 ? seen[0] + " " + seen[1] : "", "https://a.example/ https://b.example/");
	// Fourteen days: dropped unsent.
	box.Enqueue(a, 1000);
	bool called = false;
	r = box.Drain([&called](const QueuedPage&) { called = true; return 201; }, 1000 + kOutboxMaxAge + 1);
	CheckTrue("too old: dropped unsent", !called && r.dropped == 1 && box.Count() == 0);
	// An unreadable file is dropped.
	FILE* junk = fopen((path + "/000000000001-x.json").c_str(), "w");
	if (junk != nullptr) {
		fputs("not json", junk);
		fclose(junk);
	}
	r = box.Drain([](const QueuedPage&) { return 201; }, 5000);
	CheckTrue("unreadable dropped", r.dropped == 1 && box.Count() == 0);
	rmdir(path.c_str());
	rmdir(dir);
}

// A note's preview: Kura's sanitized HTML as styled text.
static std::string Styles(const StyledText& t)
{
	// "offset:style[:href]" per run, for comparing.
	std::string out;
	for (const StyledRun& r : t.runs)
		out += std::to_string(r.offset) + ":" + std::to_string(r.style) + (r.href.empty() ? "" : ":" + r.href) + " ";
	return out;
}

static void TestNoteText()
{
	StyledText t = NoteHTMLToText(
		"<h1>BeBox</h1>\n<p>Be Inc.&#39;s <strong>dual</strong> machine, see <a href=\"https://example.com/bebox\">the page</a>.</p>"
		"<ul><li>Two <em>PowerPC</em> CPUs</li><li>GeekPort</li></ul>"
		"<p>Run <code>ls -l</code></p><pre>line 1\n  line 2</pre>"
		"<blockquote><p>A quote</p></blockquote><script>alert(1)</script>"
		"<p><a href=\"javascript:alert(1)\">not a link</a> &amp; <img alt=\"a photo\" src=\"x.png\"></p>"
		"<ol><li>one</li><li>two</li></ol>");
	Check("note text", t.text,
		"BeBox\n\nBe Inc.'s dual machine, see the page.\n\n\xE2\x80\xA2 Two PowerPC CPUs\n\xE2\x80\xA2 GeekPort\n\n"
		"Run ls -l\n\nline 1\n  line 2\n\nA quote\n\nnot a link & [a photo]\n\n1. one\n2. two");
	size_t bold = t.text.find("dual");
	size_t link = t.text.find("the page");
	CheckTrue("heading styled", !t.runs.empty() && t.runs[0].offset == 0 && t.runs[0].style == kStyleHeading);
	Check("the link's address", t.LinkAt(link + 2), "https://example.com/bebox");
	Check("no link beside it", t.LinkAt(bold), "");
	Check("a javascript: link is text", t.LinkAt(t.text.find("not a link")), "");
	bool boldRun = false, codeRun = false, quoteRun = false, italicRun = false;
	for (const StyledRun& r : t.runs) {
		boldRun = boldRun || (r.offset == bold && r.style == kStyleBold);
		codeRun = codeRun || (r.offset == t.text.find("ls -l") && r.style == kStyleCode);
		quoteRun = quoteRun || (r.offset == t.text.find("A quote") && r.style == kStyleQuote);
		italicRun = italicRun || (r.offset == t.text.find("PowerPC") && r.style == kStyleItalic);
	}
	CheckTrue("bold run " + Styles(t), boldRun);
	CheckTrue("code run", codeRun);
	CheckTrue("quote run", quoteRun);
	CheckTrue("italic run", italicRun);
	Check("empty note", NoteHTMLToText("").text, "");
	Check("plain text only", Styles(NoteHTMLToText("hello")), "0:0 ");
	Check("note URL", KuraNoteURL("https://kura.example", "Retro/Be Box.md", ""),
		"https://kura.example/api/note?path=Retro%2FBe+Box.md");
	Check("note URL with vault", KuraNoteURL("https://kura.example/", "a.md", "work"),
		"https://kura.example/api/note?path=a.md&vault=work");
	std::string html;
	CheckTrue("note reply", ParseKuraNote("{\"title\":\"x\",\"html\":\"<p>x</p>\"}", html) && html == "<p>x</p>");
	CheckTrue("not a note reply", !ParseKuraNote("{\"error\":\"not found\"}", html));
}

int main()
{
	TestVectors();
	TestJson();
	TestResults();
	TestSave();
	TestCredentials();
	TestConfigFile();
	TestSignIn();
	TestOutbox();
	TestNoteText();
	TestTransport();
	printf("%d passed, %d failed\n", gPassed, gFailed);
	return gFailed ? 1 : 0;
}
