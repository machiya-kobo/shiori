#include "Http.h"

#include <exception>
#include <memory>

#include <DataIO.h>
#include <ErrorsExt.h>
#include <HttpFields.h>
#include <HttpRequest.h>
#include <HttpResult.h>
#include <HttpSession.h>
#include <Url.h>

#include "Shiori.h"

using namespace BPrivate::Network;

namespace {

BHttpSession& Session()
{
	// One session for the app; its worker threads start with it.
	static BHttpSession session;
	return session;
}

}  // namespace

HttpReply HttpRequestJSON(const shiori::Config& config, const char* method,
	const std::string& url, const std::string& body, bool hister)
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
		shiori::Headers credentials = shiori::CredentialHeaders(config, url);
		for (const auto& header : credentials)
			fields.AddField(header.first, header.second);
		request.SetFields(fields);
		// A credential never follows a redirect (it could carry it to another host).
		request.SetMaxRedirections(credentials.empty() ? 3 : 0);
		request.SetTimeout(15 * 1000000LL);
		request.SetStopOnError(false);
		if (!body.empty()) {
			auto data = std::make_unique<BMallocIO>();
			data->Write(body.data(), body.size());
			data->Seek(0, SEEK_SET);
			request.SetRequestBody(std::move(data), "application/json", body.size());
		}
		BHttpResult result = Session().Execute(std::move(request));
		reply.status = result.Status().code;
		BHttpBody& received = result.Body();
		if (received.text)
			reply.body.assign(received.text->String(), received.text->Length());
	} catch (const BError& error) {
		reply.status = 0;
		reply.error = error.Message();
		BString debug = error.DebugMessage();
		if (debug.Length() > 0)
			reply.error += std::string(" (") + debug.String() + ")";
	} catch (const std::exception& error) {
		reply.status = 0;
		reply.error = error.what();
	}
	return reply;
}
