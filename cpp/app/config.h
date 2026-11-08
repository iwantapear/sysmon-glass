// Settings model + JSON persistence, mirroring the PowerShell implementation's
// sysmon.json (same keys, same defaults, atomic write, shared position).
#pragma once
#include "json.h"
#include <windows.h>
#include <shlobj.h>
#include <string>
#include <vector>
#include <map>
#include <algorithm>
#include <cstdio>

namespace cfg {

struct Slot { int row = 0, column = 0; };

struct HostConfig {
    std::string id = "dgx";
    std::string name = "DGX Spark";
    std::string sshHost = "dgx";
    std::string user;
    int port = 22;
    std::string probe = "~/.sysmon.sh";
    bool enabled = true;
};

struct Settings {
    // appearance
    std::string theme = "dark";
    std::string material = "glass";
    std::string language = "zh-CN";
    // behaviour
    int interval = 2000;            // ms
    std::string layerMode = "normal";   // top | normal | bottom
    std::string preset = "2k";          // auto | 1080p | 2k | 4k
    bool insightsRail = true;
    bool customLayout = false;
    bool freePlacement = false;
    // placement (shared across modes; only size is per-mode)
    double normalX = -1e9, normalY = -1e9, desktopX = -1e9, desktopY = -1e9;
    double desktopScale = 1.0;
    double normalWidthDip = 0, normalHeightDip = 0;
    // cards
    std::vector<std::string> cardOrder;
    std::map<std::string, Slot> cardSlots;
    std::map<std::string, std::string> cardShapes;
    std::vector<std::string> enabledCards;
    // hosts
    std::vector<HostConfig> hosts;
    std::string activeHostId = "dgx";

    bool HasPosition(bool desktop) const { return desktop ? (desktopX > -1e8) : (normalX > -1e8); }
};

inline std::string ConfigPath() {
    const char* override = std::getenv("SYSMON_CONFIG_HOME");
    if (override && *override) return std::string(override) + "\\sysmon.json";
    char buffer[MAX_PATH] = {};
    if (SUCCEEDED(SHGetFolderPathA(nullptr, CSIDL_APPDATA, nullptr, 0, buffer)))
        return std::string(buffer) + "\\SysMon.Glass\\sysmon.json";
    return "sysmon.json";
}

inline void EnsureParent(const std::string& path) {
    size_t cut = path.find_last_of("\\/");
    if (cut == std::string::npos) return;
    std::string dir = path.substr(0, cut);
    for (size_t i = 3; i < dir.size(); ++i) {
        if (dir[i] == '\\' || dir[i] == '/') CreateDirectoryA(dir.substr(0, i).c_str(), nullptr);
    }
    CreateDirectoryA(dir.c_str(), nullptr);
}

inline std::vector<std::string> DefaultCardOrder() {
    return { "cpu", "gpuT", "cpuRpm", "caseRpm", "pumpRpm", "vrm", "dgxGpuT", "dgxCpu",
             "dgxFan", "dgxNvme", "dgxMem", "dgxLoad", "netDown", "netUp", "diskPct" };
}
inline std::vector<HostConfig> DefaultHosts() {
    HostConfig host;
    return { host };
}

inline Settings Defaults() {
    Settings s;
    s.cardOrder = DefaultCardOrder();
    s.hosts = DefaultHosts();
    return s;
}

inline Settings Load() {
    Settings s = Defaults();
    std::string path = ConfigPath();
    FILE* file = std::fopen(path.c_str(), "rb");
    if (!file) return s;
    std::string text;
    char buffer[4096];
    while (size_t read = std::fread(buffer, 1, sizeof(buffer), file)) text.append(buffer, read);
    std::fclose(file);
    if (text.empty()) return s;

    js::Value root = js::Parse(text);
    if (!root.IsObject()) return s;

    s.theme = root.Str("theme", s.theme);
    s.material = root.Str("material", s.material);
    s.language = root.Str("language", s.language);
    s.interval = (int)root.Num("interval", s.interval);
    s.layerMode = root.Str("layerMode", s.layerMode);
    s.preset = root.Str("preset", s.preset);
    s.insightsRail = root.Bool("insightsRail", s.insightsRail);
    s.customLayout = root.Bool("customLayout", s.customLayout);
    s.freePlacement = root.Bool("freePlacement", s.freePlacement);
    s.normalX = root.Num("normalX", s.normalX);
    s.normalY = root.Num("normalY", s.normalY);
    s.desktopX = root.Num("desktopX", s.desktopX);
    s.desktopY = root.Num("desktopY", s.desktopY);
    s.desktopScale = root.Num("desktopScale", s.desktopScale);
    s.normalWidthDip = root.Num("normalWidthDip", s.normalWidthDip);
    s.normalHeightDip = root.Num("normalHeightDip", s.normalHeightDip);

    if (auto* order = root.Arr("cardOrder")) {
        s.cardOrder.clear();
        for (const auto& item : *order) if (item.IsString()) s.cardOrder.push_back(item.text);
    }
    if (auto* slots = root.Get("cardSlots"); slots && slots->IsObject()) {
        for (const auto& [key, value] : *slots->fields) {
            if (!value.IsObject()) continue;
            Slot slot;
            slot.row = (int)value.Num("row", 0);
            slot.column = (int)value.Num("column", 0);
            s.cardSlots[key] = slot;
        }
    }
    if (auto* shapes = root.Get("cardShapes"); shapes && shapes->IsObject()) {
        for (const auto& [key, value] : *shapes->fields) {
            if (value.IsString()) s.cardShapes[key] = value.text;
        }
    }
    if (auto* enabled = root.Arr("enabledCards")) {
        s.enabledCards.clear();
        for (const auto& item : *enabled) if (item.IsString()) s.enabledCards.push_back(item.text);
    }
    if (auto* hosts = root.Arr("hosts")) {
        s.hosts.clear();
        for (const auto& item : *hosts) {
            if (!item.IsObject()) continue;
            HostConfig host;
            host.id = item.Str("id", host.id);
            host.name = item.Str("name", host.name);
            host.sshHost = item.Str("sshHost", host.sshHost);
            host.user = item.Str("user", "");
            host.port = (int)item.Num("port", 22);
            host.probe = item.Str("probe", host.probe);
            host.enabled = item.Bool("enabled", true);
            s.hosts.push_back(host);
        }
    }
    if (s.hosts.empty()) s.hosts = DefaultHosts();
    s.activeHostId = root.Str("activeHostId", s.hosts.front().id);

    // Same normalisation the PowerShell build applies.
    if (s.interval != 1000 && s.interval != 2000 && s.interval != 3000 && s.interval != 5000) s.interval = 2000;
    if (s.layerMode != "top" && s.layerMode != "normal" && s.layerMode != "bottom") s.layerMode = "normal";
    if (s.preset != "auto" && s.preset != "1080p" && s.preset != "2k" && s.preset != "4k") s.preset = "2k";
    if (s.desktopScale < 0.2) s.desktopScale = 1.0;
    if (s.cardOrder.empty()) s.cardOrder = DefaultCardOrder();
    return s;
}

inline bool Save(const Settings& s) {
    js::Value root = js::Value::MakeObject();
    root.Set("theme", js::Value::MakeString(s.theme));
    root.Set("material", js::Value::MakeString(s.material));
    root.Set("language", js::Value::MakeString(s.language));
    root.Set("interval", js::Value::MakeNumber(s.interval));
    root.Set("layerMode", js::Value::MakeString(s.layerMode));
    // desktopMode mirrors layerMode so older builds read the same state.
    root.Set("desktopMode", js::Value::MakeBool(s.layerMode == "bottom"));
    root.Set("preset", js::Value::MakeString(s.preset));
    root.Set("insightsRail", js::Value::MakeBool(s.insightsRail));
    root.Set("customLayout", js::Value::MakeBool(s.customLayout));
    root.Set("freePlacement", js::Value::MakeBool(s.freePlacement));
    if (s.normalX > -1e8) { root.Set("normalX", js::Value::MakeNumber(s.normalX)); root.Set("normalY", js::Value::MakeNumber(s.normalY)); }
    if (s.desktopX > -1e8) { root.Set("desktopX", js::Value::MakeNumber(s.desktopX)); root.Set("desktopY", js::Value::MakeNumber(s.desktopY)); }
    root.Set("desktopScale", js::Value::MakeNumber(s.desktopScale));
    if (s.normalWidthDip > 0) { root.Set("normalWidthDip", js::Value::MakeNumber(s.normalWidthDip)); root.Set("normalHeightDip", js::Value::MakeNumber(s.normalHeightDip)); }

    js::Value order = js::Value::MakeArray();
    for (const auto& key : s.cardOrder) order.items->push_back(js::Value::MakeString(key));
    root.Set("cardOrder", order);

    js::Value slots = js::Value::MakeObject();
    for (const auto& [key, slot] : s.cardSlots) {
        js::Value entry = js::Value::MakeObject();
        entry.Set("row", js::Value::MakeNumber(slot.row));
        entry.Set("column", js::Value::MakeNumber(slot.column));
        slots.Set(key, entry);
    }
    root.Set("cardSlots", slots);

    js::Value shapes = js::Value::MakeObject();
    for (const auto& [key, value] : s.cardShapes) shapes.Set(key, js::Value::MakeString(value));
    root.Set("cardShapes", shapes);

    if (!s.enabledCards.empty()) {
        js::Value enabled = js::Value::MakeArray();
        for (const auto& key : s.enabledCards) enabled.items->push_back(js::Value::MakeString(key));
        root.Set("enabledCards", enabled);
    }

    js::Value hosts = js::Value::MakeArray();
    for (const auto& host : s.hosts) {
        js::Value item = js::Value::MakeObject();
        item.Set("id", js::Value::MakeString(host.id));
        item.Set("name", js::Value::MakeString(host.name));
        item.Set("sshHost", js::Value::MakeString(host.sshHost));
        item.Set("user", js::Value::MakeString(host.user));
        item.Set("port", js::Value::MakeNumber(host.port));
        item.Set("probe", js::Value::MakeString(host.probe));
        item.Set("enabled", js::Value::MakeBool(host.enabled));
        hosts.items->push_back(item);
    }
    root.Set("hosts", hosts);
    root.Set("activeHostId", js::Value::MakeString(s.activeHostId));

    std::string path = ConfigPath();
    EnsureParent(path);
    std::string temp = path + ".tmp";
    FILE* file = std::fopen(temp.c_str(), "wb");
    if (!file) return false;
    std::string text = js::Serialize(root, true);
    std::fwrite(text.data(), 1, text.size(), file);
    std::fclose(file);
    return MoveFileExA(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING) != 0;
}

} // namespace cfg
