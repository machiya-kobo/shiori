// A small JSON reader and writer for Shiori's portable core: enough for
// Hister's and Kura's replies and the bodies Shiori sends. No Be headers,
// so the core builds and tests on Linux too (haiku/Makefile.test).
#pragma once

#include <string>
#include <utility>
#include <vector>

namespace shiori {
namespace json {

struct Value {
	enum Type { Null, Bool, Number, String, Array, Object };

	Type type = Null;
	bool boolean = false;
	double number = 0;
	std::string string;
	std::vector<Value> items;
	std::vector<std::pair<std::string, Value>> members;

	Value() = default;
	static Value MakeString(const std::string& s);
	static Value MakeNumber(double n);
	static Value MakeBool(bool b);
	static Value MakeObject();
	static Value MakeArray();

	bool IsNull() const { return type == Null; }
	bool IsString() const { return type == String; }
	bool IsNumber() const { return type == Number; }
	bool IsArray() const { return type == Array; }
	bool IsObject() const { return type == Object; }

	// A member, or a shared null when there's none (or this isn't an object).
	const Value& operator[](const std::string& key) const;
	// The string, or `fallback` for anything that isn't one.
	std::string Str(const std::string& fallback = "") const;
	// The number, or `fallback`.
	double Num(double fallback = 0) const;

	// Builders (objects keep their members' order).
	Value& Set(const std::string& key, Value value);
	Value& Push(Value value);
};

// Parses `text`; false (with `error` set) on anything that isn't one JSON value.
bool Parse(const std::string& text, Value& out, std::string* error = nullptr);

// A JSON string literal, quotes included.
std::string Quote(const std::string& s);

// Compact JSON, members in order (JSON.stringify's output for the same value).
std::string Write(const Value& value);

}  // namespace json
}  // namespace shiori
