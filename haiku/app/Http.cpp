#include "Http.h"

#include <exception>
#include <memory>
#include <mutex>

#include <DataIO.h>
#include <ErrorsExt.h>
#include <HttpFields.h>
#include <HttpRequest.h>
#include <HttpResult.h>
#include <HttpSession.h>
#include <NetServicesDefs.h>
#include <OS.h>
#include <Url.h>

#include "Shiori.h"

using namespace BPrivate::Network;

namespace {

// SetTimeout() doesn't cover a server that accepts and then stalls (seen
// with TLS): every request also has a deadline of its own.
const bigtime_t kDeadline = 20 * 1000000LL;

// netservices2's messages hold "\n\t": one line for a status bar.
std::string OneLine(const BError& error)
{
	std::string text = error.Message();
	BString debug = error.DebugMessage();
	debug.ReplaceAll("\n\t", " ");
	debug.ReplaceAll('\n', ' ');
	if (debug.Length() > 0)
		text += std::string(" (") + debug.String() + ")";
	return text;
}

// netservices2 connects on one control thread per session, and
// BSecureSocket::Connect's TLS handshake ignores the timeout: a server that
// accepts and never answers the handshake holds that thread, so every later
// request (Kura's too) waits behind it, and the session's destructor waits
// for it at quit (then crashes once OpenSSL is gone). So the session lives
// on the heap and is never deleted (quit doesn't wait), and a request past
// its deadline retires it: the next request gets a fresh session, the stuck
// one is left to its thread.
std::mutex sSessionLock;
BHttpSession* sSession = nullptr;

BHttpSession* Session()
{
	std::lock_guard<std::mutex> lock(sSessionLock);
	if (sSession == nullptr)
		sSession = new BHttpSession();
	return sSession;
}

void RetireSession(BHttpSession* stuck)
{
	std::lock_guard<std::mutex> lock(sSessionLock);
	// Leaked on purpose: deleting it would wait for the stuck thread.
	if (sSession == stuck)
		sSession = nullptr;
}

}  // namespace

HttpReply HttpRequestJSON(const shiori::Config& config, const char* method,
	const std::string& url, const std::string& body, bool hister, bool credentials,
	const shiori::Headers& extra)
{
	HttpReply reply;
	if (!shiori::IsConfiguredOrigin(config, url)) {
		reply.error = "Not a configured host: " + shiori::OriginOf(url);
		return reply;
	}
	try {
		BUrl target(url.c_str(), true);
		if (!target.IsValid()) {
			reply.error = "Not an address: " + url;
			return reply;
		}
		BHttpRequest request(target);
		request.SetMethod(BHttpMethod(std::string_view(method)));
		BHttpFields fields;
		fields.AddField("Accept", "application/json");
		fields.AddField("User-Agent", "Shiori-Haiku/" SHIORI_VERSION);
		if (hister)
			fields.AddField("Origin", "hister://");
		shiori::Headers carried = credentials ? shiori::CredentialHeaders(config, url) : shiori::Headers();
		for (const auto& header : extra)
			carried.push_back(header);
		for (const auto& header : carried)
			fields.AddField(header.first, header.second);
		request.SetFields(fields);
		// A credential never follows a redirect (it could carry it to another host).
		request.SetMaxRedirections(carried.empty() ? 3 : 0);
		request.SetTimeout(15 * 1000000LL);
		request.SetStopOnError(false);
		if (!body.empty()) {
			auto data = std::make_unique<BMallocIO>();
			data->Write(body.data(), body.size());
			data->Seek(0, SEEK_SET);
			request.SetRequestBody(std::move(data), "application/json", body.size());
		}
		BHttpSession* session = Session();
		BHttpResult result = session->Execute(std::move(request));
		bigtime_t deadline = system_time() + kDeadline;
		while (!result.IsCompleted()) {
			if (system_time() > deadline) {
				session->Cancel(result);
				RetireSession(session);
				reply.error = "no answer in 20 seconds";
				return reply;
			}
			snooze(50000);
		}
		reply.status = result.Status().code;
		for (const auto& field : result.Fields()) {
			if (field.Name() == std::string_view("Set-Cookie"))
				reply.setCookies.emplace_back(field.Value());
		}
		BHttpBody& received = result.Body();
		if (received.text)
			reply.body.assign(received.text->String(), received.text->Length());
	} catch (const BNetworkRequestError& error) {
		reply.status = 0;
		reply.error = OneLine(error);
		// netservices2 says only "Operation not allowed" (B_NOT_ALLOWED) when
		// TLS fails, whether the certificate isn't trusted or the server
		// doesn't speak https; its own words add nothing, and a long line is
		// cut before the advice: name the failure instead.
		if (error.Type() == BNetworkRequestError::NetworkError && error.ErrorCode() == B_NOT_ALLOWED
			&& url.compare(0, 8, "https://") == 0)
			reply.error = "TLS handshake failed";
	} catch (const BError& error) {
		reply.status = 0;
		reply.error = OneLine(error);
	} catch (const std::exception& error) {
		reply.status = 0;
		reply.error = error.what();
	}
	return reply;
}
