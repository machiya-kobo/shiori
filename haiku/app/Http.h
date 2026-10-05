// HTTP for Shiori on Haiku, through the Network Kit's netservices2
// (private API, linked statically). Blocking: call it from a worker thread.
// Only the configured origins (Hister, Kura); each request gets exactly the
// credential CredentialHeaders() allows, and one with a credential follows
// no redirect. Hister gets Origin: hister://.
#pragma once

#include <string>
#include <vector>

#include "../core/Config.h"

struct HttpReply {
	int status = 0;          // 0 when no answer came
	std::string body;
	std::string error;       // why there's no answer
	std::vector<std::string> setCookies;  // the reply's Set-Cookie values (the sign-in reads Hister's)
};

// `credentials` false: none of the config's (Hister's login and the helper's
// trade send none). `extra`: headers of the caller's own (Sign Out's Bearer
// mhs_). With any credential, no redirect is followed.
HttpReply HttpRequestJSON(const shiori::Config& config, const char* method,
	const std::string& url, const std::string& body = std::string(), bool hister = false,
	bool credentials = true, const shiori::Headers& extra = shiori::Headers());
