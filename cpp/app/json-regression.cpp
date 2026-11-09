#include "json.h"
#include <iostream>
#include <limits>

int main() {
    int failed = 0, checks = 0;
    auto check = [&](bool ok, const char* name) {
        ++checks;
        if (!ok) { ++failed; std::cout << "FAIL: " << name << '\n'; }
    };
    check(js::Parse(R"({"name":"\u4e2d\u6587"})").Str("name") == "中文", "Chinese Unicode escapes preserved");
    check(js::Parse(R"("\ud83d\ude00")").text == "\xf0\x9f\x98\x80", "surrogate pair becomes UTF-8");
    check(js::Parse("\xef\xbb\xbf{\"a\":1}").Num("a") == 1, "UTF-8 BOM accepted");
    const char* invalid[] = {"{", "[", "{\"a\":1", "[1,]", "{\"a\":1,}", "{\"a\" 1}",
        "{x:1}", "[1 2]", "{}junk", "truefalse", "01", "+1", "1.", ".1", "1e", "--1", "1e309",
        "\"unterminated", "\"\q\"", "\"\u12xz\"", "\"\ud800\"", "\"\udc00\"", "\"\ud800\u1234\"",
        "\"line\nbreak\"", "\"\xc0\xaf\"", "\"\xed\xa0\x80\""};
    for (const char* input : invalid) check(js::Parse(input).kind == js::Value::Kind::Null, input);
    check(js::Parse(std::string(200, '[') + "0" + std::string(200, ']')).kind == js::Value::Kind::Null, "depth limit rejects excessive nesting");
    std::string controls;
    for (int i = 0; i < 32; ++i) controls.push_back(static_cast<char>(i));
    const auto encoded = js::Serialize(js::Value::MakeString(controls));
    bool noRawControls = true;
    for (unsigned char c : encoded) if (c < 32) noRawControls = false;
    check(noRawControls, "writer escapes every control character");
    check(js::Parse(encoded).text == controls, "all controls roundtrip");
    check(js::Serialize(js::Value::MakeNumber(std::numeric_limits<double>::infinity())) == "null", "infinity serialized safely");
    check(js::Serialize(js::Value::MakeNumber(std::numeric_limits<double>::quiet_NaN())) == "null", "NaN serialized safely");
    const auto config = js::Parse(R"({"theme":"dark","hosts":[{"name":"中文","enabled":true}],"normalX":-123.456789012345,"nothing":null})");
    check(config.IsObject() && config.Arr("hosts") && config.Arr("hosts")->size() == 1, "normal configuration accepted");
    check(js::Parse(js::Serialize(config)).Num("normalX") == config.Num("normalX"), "numeric roundtrip keeps precision");
    check(js::Parse(" \t-2.5e+2\r\n").number == -250, "valid exponent and whitespace");
    std::cout << checks << " checks, " << failed << " failures\n";
    return failed ? 1 : 0;
}
