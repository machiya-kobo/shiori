#include "Json.h"

#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace shiori {
namespace json {

namespace {

const Value kNull;

struct Parser {
	const std::string& s;
	size_t i = 0;
	std::string error;
	int depth = 0;

	explicit Parser(const std::string& text) : s(text) {}

	bool Fail(const char* what)
	{
		if (error.empty()) {
			char buf[96];
			snprintf(buf, sizeof(buf), "%s at offset %zu", what, i);
			error = buf;
		}
		return false;
	}

	void Space()
	{
		while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r'))
			i++;
	}

	bool Literal(const char* word)
	{
		size_t n = 0;
		while (word[n] != '\0') {
			if (i + n >= s.size() || s[i + n] != word[n])
				return Fail("bad literal");
			n++;
		}
		i += n;
		return true;
	}

	static void Utf8(std::string& out, unsigned long cp)
	{
		if (cp < 0x80) {
			out += char(cp);
		} else if (cp < 0x800) {
			out += char(0xC0 | (cp >> 6));
			out += char(0x80 | (cp & 0x3F));
		} else if (cp < 0x10000) {
			out += char(0xE0 | (cp >> 12));
			out += char(0x80 | ((cp >> 6) & 0x3F));
			out += char(0x80 | (cp & 0x3F));
		} else {
			out += char(0xF0 | (cp >> 18));
			out += char(0x80 | ((cp >> 12) & 0x3F));
			out += char(0x80 | ((cp >> 6) & 0x3F));
			out += char(0x80 | (cp & 0x3F));
		}
	}

	bool Hex4(unsigned long& cp)
	{
		if (i + 4 > s.size())
			return Fail("short \\u escape");
		cp = 0;
		for (int k = 0; k < 4; k++) {
			char c = s[i++];
			cp <<= 4;
			if (c >= '0' && c <= '9') cp |= c - '0';
			else if (c >= 'a' && c <= 'f') cp |= c - 'a' + 10;
			else if (c >= 'A' && c <= 'F') cp |= c - 'A' + 10;
			else return Fail("bad \\u escape");
		}
		return true;
	}

	bool StringBody(std::string& out)
	{
		// s[i] == '"'
		i++;
		while (i < s.size()) {
			unsigned char c = s[i++];
			if (c == '"')
				return true;
			if (c < 0x20)
				return Fail("control character in string");
			if (c != '\\') {
				out += char(c);
				continue;
			}
			if (i >= s.size())
				break;
			char e = s[i++];
			switch (e) {
				case '"': out += '"'; break;
				case '\\': out += '\\'; break;
				case '/': out += '/'; break;
				case 'b': out += '\b'; break;
				case 'f': out += '\f'; break;
				case 'n': out += '\n'; break;
				case 'r': out += '\r'; break;
				case 't': out += '\t'; break;
				case 'u': {
					unsigned long cp;
					if (!Hex4(cp))
						return false;
					if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < s.size() && s[i] == '\\'
						&& s[i + 1] == 'u') {
						size_t save = i;
						i += 2;
						unsigned long low;
						if (!Hex4(low))
							return false;
						if (low >= 0xDC00 && low <= 0xDFFF)
							cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
						else
							i = save;
					}
					if (cp >= 0xD800 && cp <= 0xDFFF)
						cp = 0xFFFD;  // a lone surrogate
					Utf8(out, cp);
					break;
				}
				default:
					return Fail("bad escape");
			}
		}
		return Fail("unterminated string");
	}

	bool NumberBody(Value& v)
	{
		size_t start = i;
		if (s[i] == '-')
			i++;
		if (i >= s.size() || !isdigit((unsigned char)s[i]))
			return Fail("bad number");
		while (i < s.size() && (isdigit((unsigned char)s[i]) || s[i] == '.' || s[i] == 'e'
			|| s[i] == 'E' || s[i] == '+' || s[i] == '-'))
			i++;
		std::string text = s.substr(start, i - start);
		char* end = nullptr;
		v.number = strtod(text.c_str(), &end);
		if (end == nullptr || *end != '\0')
			return Fail("bad number");
		v.type = Value::Number;
		return true;
	}

	bool Any(Value& v)
	{
		if (++depth > 64)
			return Fail("nested too deeply");
		Space();
		if (i >= s.size())
			return Fail("unexpected end");
		char c = s[i];
		bool ok;
		if (c == '{') {
			v.type = Value::Object;
			i++;
			Space();
			if (i < s.size() && s[i] == '}') {
				i++;
				ok = true;
			} else {
				ok = false;
				while (true) {
					Space();
					if (i >= s.size() || s[i] != '"') {
						Fail("expected a key");
						break;
					}
					std::string key;
					if (!StringBody(key))
						break;
					Space();
					if (i >= s.size() || s[i] != ':') {
						Fail("expected ':'");
						break;
					}
					i++;
					Value member;
					if (!Any(member))
						break;
					v.members.emplace_back(std::move(key), std::move(member));
					Space();
					if (i < s.size() && s[i] == ',') {
						i++;
						continue;
					}
					if (i < s.size() && s[i] == '}') {
						i++;
						ok = true;
					} else {
						Fail("expected ',' or '}'");
					}
					break;
				}
			}
		} else if (c == '[') {
			v.type = Value::Array;
			i++;
			Space();
			if (i < s.size() && s[i] == ']') {
				i++;
				ok = true;
			} else {
				ok = false;
				while (true) {
					Value item;
					if (!Any(item))
						break;
					v.items.push_back(std::move(item));
					Space();
					if (i < s.size() && s[i] == ',') {
						i++;
						continue;
					}
					if (i < s.size() && s[i] == ']') {
						i++;
						ok = true;
					} else {
						Fail("expected ',' or ']'");
					}
					break;
				}
			}
		} else if (c == '"') {
			v.type = Value::String;
			ok = StringBody(v.string);
		} else if (c == 't') {
			v.type = Value::Bool;
			v.boolean = true;
			ok = Literal("true");
		} else if (c == 'f') {
			v.type = Value::Bool;
			ok = Literal("false");
		} else if (c == 'n') {
			ok = Literal("null");
		} else {
			ok = NumberBody(v);
		}
		depth--;
		return ok;
	}
};

}  // namespace

Value Value::MakeString(const std::string& s)
{
	Value v;
	v.type = String;
	v.string = s;
	return v;
}

Value Value::MakeNumber(double n)
{
	Value v;
	v.type = Number;
	v.number = n;
	return v;
}

Value Value::MakeBool(bool b)
{
	Value v;
	v.type = Bool;
	v.boolean = b;
	return v;
}

Value Value::MakeObject()
{
	Value v;
	v.type = Object;
	return v;
}

Value Value::MakeArray()
{
	Value v;
	v.type = Array;
	return v;
}

const Value& Value::operator[](const std::string& key) const
{
	if (type != Object)
		return kNull;
	for (const auto& m : members) {
		if (m.first == key)
			return m.second;
	}
	return kNull;
}

std::string Value::Str(const std::string& fallback) const
{
	return type == String ? string : fallback;
}

double Value::Num(double fallback) const
{
	return type == Number ? number : fallback;
}

Value& Value::Set(const std::string& key, Value value)
{
	type = Object;
	for (auto& m : members) {
		if (m.first == key) {
			m.second = std::move(value);
			return *this;
		}
	}
	members.emplace_back(key, std::move(value));
	return *this;
}

Value& Value::Push(Value value)
{
	type = Array;
	items.push_back(std::move(value));
	return *this;
}

bool Parse(const std::string& text, Value& out, std::string* error)
{
	Parser p(text);
	out = Value();
	bool ok = p.Any(out);
	if (ok) {
		p.Space();
		if (p.i != text.size())
			ok = p.Fail("trailing characters");
	}
	if (!ok) {
		out = Value();
		if (error != nullptr)
			*error = p.error;
	}
	return ok;
}

std::string Quote(const std::string& s)
{
	std::string out = "\"";
	for (unsigned char c : s) {
		switch (c) {
			case '"': out += "\\\""; break;
			case '\\': out += "\\\\"; break;
			case '\b': out += "\\b"; break;
			case '\f': out += "\\f"; break;
			case '\n': out += "\\n"; break;
			case '\r': out += "\\r"; break;
			case '\t': out += "\\t"; break;
			default:
				if (c < 0x20) {
					char buf[8];
					snprintf(buf, sizeof(buf), "\\u%04x", c);
					out += buf;
				} else {
					out += char(c);
				}
		}
	}
	return out + "\"";
}

std::string Write(const Value& v)
{
	switch (v.type) {
		case Value::Null:
			return "null";
		case Value::Bool:
			return v.boolean ? "true" : "false";
		case Value::Number: {
			if (!std::isfinite(v.number))
				return "null";
			char buf[32];
			if (v.number == std::floor(v.number) && std::fabs(v.number) < 9.007199254740992e15)
				snprintf(buf, sizeof(buf), "%lld", (long long)v.number);
			else
				snprintf(buf, sizeof(buf), "%.17g", v.number);
			return buf;
		}
		case Value::String:
			return Quote(v.string);
		case Value::Array: {
			std::string out = "[";
			for (size_t k = 0; k < v.items.size(); k++) {
				if (k)
					out += ",";
				out += Write(v.items[k]);
			}
			return out + "]";
		}
		case Value::Object: {
			std::string out = "{";
			for (size_t k = 0; k < v.members.size(); k++) {
				if (k)
					out += ",";
				out += Quote(v.members[k].first) + ":" + Write(v.members[k].second);
			}
			return out + "}";
		}
	}
	return "null";
}

}  // namespace json
}  // namespace shiori
