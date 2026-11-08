// Minimal JSON for the app's own config format (objects, arrays, strings,
// numbers, bools, null). No dependencies; tolerant reader, deterministic writer.
#pragma once
#include <string>
#include <vector>
#include <map>
#include <memory>
#include <cstdio>
#include <cmath>
#include <cwchar>

namespace js {

struct Value;
using Object = std::map<std::string, Value>;
using Array = std::vector<Value>;

struct Value {
    enum class Kind { Null, Bool, Number, String, Array, Object } kind = Kind::Null;
    bool boolean = false;
    double number = 0;
    std::string text;
    std::shared_ptr<Array> items;
    std::shared_ptr<Object> fields;

    static Value MakeObject() { Value v; v.kind = Kind::Object; v.fields = std::make_shared<Object>(); return v; }
    static Value MakeArray() { Value v; v.kind = Kind::Array; v.items = std::make_shared<Array>(); return v; }
    static Value MakeString(const std::string& s) { Value v; v.kind = Kind::String; v.text = s; return v; }
    static Value MakeNumber(double n) { Value v; v.kind = Kind::Number; v.number = n; return v; }
    static Value MakeBool(bool b) { Value v; v.kind = Kind::Bool; v.boolean = b; return v; }

    bool IsObject() const { return kind == Kind::Object && fields; }
    bool IsArray() const { return kind == Kind::Array && items; }
    bool IsString() const { return kind == Kind::String; }
    bool IsNumber() const { return kind == Kind::Number; }
    bool IsBool() const { return kind == Kind::Bool; }

    const Value* Get(const std::string& key) const {
        if (!IsObject()) return nullptr;
        auto it = fields->find(key);
        return it == fields->end() ? nullptr : &it->second;
    }
    // Convenience readers with defaults.
    std::string Str(const std::string& key, const std::string& fallback = "") const {
        const Value* v = Get(key);
        return (v && v->IsString()) ? v->text : fallback;
    }
    double Num(const std::string& key, double fallback = 0) const {
        const Value* v = Get(key);
        return (v && v->IsNumber()) ? v->number : fallback;
    }
    bool Bool(const std::string& key, bool fallback = false) const {
        const Value* v = Get(key);
        return (v && v->IsBool()) ? v->boolean : fallback;
    }
    const Array* Arr(const std::string& key) const {
        const Value* v = Get(key);
        return (v && v->IsArray()) ? v->items.get() : nullptr;
    }
    void Set(const std::string& key, Value v) {
        if (!IsObject()) { *this = MakeObject(); }
        (*fields)[key] = std::move(v);
    }
    Value& operator[](const std::string& key) {
        if (!IsObject()) { *this = MakeObject(); }
        return (*fields)[key];
    }
};

namespace detail {
struct Reader {
    const std::string& s;
    size_t i = 0;
    explicit Reader(const std::string& text) : s(text) {}
    void Skip() {
        while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n')) ++i;
    }
    bool Literal(const char* word) {
        size_t n = std::char_traits<char>::length(word);
        if (s.compare(i, n, word) != 0) return false;
        i += n;
        return true;
    }
    std::string ParseString() {
        std::string out;
        if (i >= s.size() || s[i] != '"') return out;
        ++i;
        while (i < s.size() && s[i] != '"') {
            char c = s[i++];
            if (c != '\\') { out.push_back(c); continue; }
            if (i >= s.size()) break;
            char esc = s[i++];
            switch (esc) {
            case 'n': out.push_back('\n'); break;
            case 't': out.push_back('\t'); break;
            case 'r': out.push_back('\r'); break;
            case 'b': out.push_back('\b'); break;
            case 'f': out.push_back('\f'); break;
            case 'u': {
                // Enough for our own files: keep ASCII, replace the rest with '?'.
                if (i + 4 <= s.size()) {
                    unsigned code = (unsigned)std::strtoul(s.substr(i, 4).c_str(), nullptr, 16);
                    i += 4;
                    out.push_back(code < 0x80 ? (char)code : '?');
                }
                break;
            }
            default: out.push_back(esc);
            }
        }
        if (i < s.size() && s[i] == '"') ++i;
        return out;
    }
    Value Parse() {
        Skip();
        if (i >= s.size()) return Value();
        char c = s[i];
        if (c == '{') {
            ++i;
            Value object = Value::MakeObject();
            Skip();
            if (i < s.size() && s[i] == '}') { ++i; return object; }
            while (i < s.size()) {
                Skip();
                std::string key = ParseString();
                Skip();
                if (i < s.size() && s[i] == ':') ++i;
                (*object.fields)[key] = Parse();
                Skip();
                if (i < s.size() && s[i] == ',') { ++i; continue; }
                if (i < s.size() && s[i] == '}') { ++i; break; }
                break;
            }
            return object;
        }
        if (c == '[') {
            ++i;
            Value array = Value::MakeArray();
            Skip();
            if (i < s.size() && s[i] == ']') { ++i; return array; }
            while (i < s.size()) {
                array.items->push_back(Parse());
                Skip();
                if (i < s.size() && s[i] == ',') { ++i; continue; }
                if (i < s.size() && s[i] == ']') { ++i; break; }
                break;
            }
            return array;
        }
        if (c == '"') return Value::MakeString(ParseString());
        if (Literal("true")) return Value::MakeBool(true);
        if (Literal("false")) return Value::MakeBool(false);
        if (Literal("null")) return Value();
        // number
        size_t start = i;
        while (i < s.size() && (std::isdigit((unsigned char)s[i]) || s[i] == '-' || s[i] == '+' || s[i] == '.' || s[i] == 'e' || s[i] == 'E')) ++i;
        return Value::MakeNumber(std::strtod(s.substr(start, i - start).c_str(), nullptr));
    }
};

inline void Escape(const std::string& in, std::string& out) {
    out.push_back('"');
    for (char c : in) {
        switch (c) {
        case '"': out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default: out.push_back(c);
        }
    }
    out.push_back('"');
}

inline void Write(const Value& v, std::string& out, int indent, int depth) {
    auto pad = [&](int d) { out.append(size_t(d) * 2, ' '); };
    switch (v.kind) {
    case Value::Kind::Null: out += "null"; break;
    case Value::Kind::Bool: out += v.boolean ? "true" : "false"; break;
    case Value::Kind::Number: {
        char buffer[32];
        double n = v.number;
        if (std::floor(n) == n && std::fabs(n) < 1e15) std::snprintf(buffer, sizeof(buffer), "%.0f", n);
        else std::snprintf(buffer, sizeof(buffer), "%.6g", n);
        out += buffer;
        break;
    }
    case Value::Kind::String: Escape(v.text, out); break;
    case Value::Kind::Array: {
        const auto& items = *v.items;
        if (items.empty()) { out += "[]"; break; }
        bool scalar = true;
        for (const auto& item : items) if (item.kind == Value::Kind::Object || item.kind == Value::Kind::Array) { scalar = false; break; }
        out += '[';
        for (size_t i = 0; i < items.size(); ++i) {
            if (i) out += ',';
            if (indent > 0) { out += '\n'; pad(depth + 1); }
            else if (!scalar) out += ' ';
            Write(items[i], out, indent, depth + 1);
        }
        if (indent > 0) { out += '\n'; pad(depth); }
        out += ']';
        break;
    }
    case Value::Kind::Object: {
        const auto& fields = *v.fields;
        if (fields.empty()) { out += "{}"; break; }
        out += '{';
        bool first = true;
        for (const auto& [key, value] : fields) {
            if (!first) out += ',';
            first = false;
            if (indent > 0) { out += '\n'; pad(depth + 1); } else out += ' ';
            Escape(key, out);
            out += indent > 0 ? ": " : ":";
            Write(value, out, indent, depth + 1);
        }
        if (indent > 0) { out += '\n'; pad(depth); }
        out += '}';
        break;
    }
    }
}
} // namespace detail

inline Value Parse(const std::string& text) { return detail::Reader(text).Parse(); }
inline std::string Serialize(const Value& value, bool pretty = true) {
    std::string out;
    detail::Write(value, out, pretty ? 2 : 0, 0);
    return out;
}

} // namespace js
