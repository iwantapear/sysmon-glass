// SysMon Glass — native Windows build (Win32 + Direct2D/DirectWrite).
// Behaviour and visuals mirror the PowerShell/WPF implementation: same palettes,
// materials, cards, layout rules, desktop-underlay masking and interactions.
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#ifndef WINVER
#define WINVER 0x0A00
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <windowsx.h>
#include <shellapi.h>
#include <d2d1.h>
#include <dwrite.h>
#include <dwmapi.h>
#include <uiautomation.h>
#include <string>
#include <vector>
#include <map>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <memory>

#include "json.h"
#include "theme.h"
#include "config.h"
#include "metrics.h"

#pragma comment(lib, "d2d1.lib")
#pragma comment(lib, "dwrite.lib")
#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")
#pragma comment(lib, "uiautomationcore.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "gdi32.lib")

// ---------------------------------------------------------------- card model
struct CardDef {
    const char* key;
    const char* labelZh;
    const char* labelTw;
    const char* labelEn;
    const char* unit;
    uint32_t color;
    const char* bar;      // optional secondary key driving the progress bar
    char side;            // L | R | S
    bool temperature;
};

static const CardDef kCards[] = {
    { "cpu",     "本机 · CPU 温度", "本機 · CPU 溫度", "Local · CPU temp", "°C",     0xFF68B5FFu, nullptr,   'L', true },
    { "gpuT",    "本机 · GPU 温度", "本機 · GPU 溫度", "Local · GPU temp", "°C",     0xFFC79EFFu, nullptr,   'L', true },
    { "cpuRpm",  "本机 · CPU 风扇", "本機 · CPU 風扇", "Local · CPU fan",  "RPM",    0xFF83BBFFu, "cpuDuty", 'L', false },
    { "caseRpm", "本机 · 机箱风扇", "本機 · 機箱風扇", "Local · case fan", "RPM",    0xFFA6A5FFu, "caseDuty",'L', false },
    { "pumpRpm", "本机 · 水泵",     "本機 · 水泵",     "Local · pump",     "RPM",    0xFF74DAEBu, "pumpDuty",'L', false },
    { "vrm",     "本机 · VRM 温度", "本機 · VRM 溫度", "Local · VRM temp", "°C",     0xFFFFBB90u, nullptr,   'L', true },
    { "dgxGpuT", "DGX · GPU 温度",  "DGX · GPU 溫度",  "DGX · GPU temp",   "°C",     0xFF74EBE0u, nullptr,   'R', true },
    { "dgxCpu",  "DGX · CPU 温度",  "DGX · CPU 溫度",  "DGX · CPU temp",   "°C",     0xFF8CB9FFu, nullptr,   'R', true },
    { "dgxFan",  "DGX · 风扇",      "DGX · 風扇",      "DGX · fan",        "RPM",    0xFFA8D8FFu, nullptr,   'R', false },
    { "dgxNvme", "DGX · NVMe 温度", "DGX · NVMe 溫度", "DGX · NVMe temp",  "°C",     0xFFCBAAFFu, nullptr,   'R', true },
    { "dgxMem",  "DGX · 内存",      "DGX · 記憶體",    "DGX · memory",     "GB",     0xFF8FE9CEu, "dgxMemPct",'R', false },
    { "dgxLoad", "DGX · 负载",      "DGX · 負載",      "DGX · load",       "",       0xFFFFCC97u, nullptr,   'R', false },
    { "netDown", "本机 · 网络速率 · 下载", "本機 · 網路速率 · 下載", "Local · network down", "KiB/s", 0xFF74DAEBu, nullptr, 'S', false },
    { "netUp",   "本机 · 网络速率 · 上传", "本機 · 網路速率 · 上傳", "Local · network up",   "KiB/s", 0xFF9BE5B8u, nullptr, 'S', false },
    { "diskPct", "本机 · 磁盘空间 · 已用", "本機 · 磁碟空間 · 已用", "Local · disk used",    "%",     0xFFFFCC97u, "diskPct", 'S', false }
};
static const CardDef kOptionalCards[] = {
    { "cpuPwr",     "CPU 功耗", "CPU 功耗", "CPU power", "W", 0xFFFFB36Bu, nullptr, 'L', false },
    { "gpuUtil",    "GPU 使用率", "GPU 使用率", "GPU usage", "%", 0xFF74D9FFu, "gpuUtil", 'L', false },
    { "gpuMem",     "GPU 显存", "GPU 記憶體", "GPU memory", "GB", 0xFF9BE5B8u, nullptr, 'L', false },
    { "gpuClock",   "GPU 频率", "GPU 頻率", "GPU clock", "MHz", 0xFFC9A6FFu, nullptr, 'L', false },
    { "pch",        "PCH 温度", "PCH 溫度", "PCH temperature", "°C", 0xFFFFC27Du, nullptr, 'L', true },
    { "dgxGpuPwr",  "DGX GPU 功耗", "DGX GPU 功耗", "DGX GPU power", "W", 0xFF66D8D0u, nullptr, 'R', false },
    { "dgxGpuUtil", "DGX GPU 使用率", "DGX GPU 使用率", "DGX GPU usage", "%", 0xFF74EBE0u, "dgxGpuUtil", 'R', false },
    { "dgxMemPct",  "DGX 内存使用率", "DGX 記憶體使用率", "DGX memory usage", "%", 0xFF8FE9CEu, "dgxMemPct", 'R', false }
};
static const int kCardCount = int(sizeof(kCards) / sizeof(kCards[0]));
static const int kOptionalCount = int(sizeof(kOptionalCards) / sizeof(kOptionalCards[0]));

static const CardDef* FindCard(const std::string& key) {
    for (int i = 0; i < kCardCount; ++i) if (key == kCards[i].key) return &kCards[i];
    for (int i = 0; i < kOptionalCount; ++i) if (key == kOptionalCards[i].key) return &kOptionalCards[i];
    return nullptr;
}

static std::vector<std::string> DefaultCardKeys() {
    std::vector<std::string> keys;
    for (int i = 0; i < kCardCount; ++i) keys.push_back(kCards[i].key);
    return keys;
}


// ---------------------------------------------------------------- localisation
static std::string g_language = "zh-CN";
// Returns by value: a .c_str() on a temporary would dangle.
static std::wstring Tr(const CardDef& card) {
    if (g_language == "en") return metrics::Utf8ToWide(card.labelEn);
    if (g_language == "zh-TW") return metrics::Utf8ToWide(card.labelTw);
    return metrics::Utf8ToWide(card.labelZh);
}
static std::wstring T(const std::wstring& zh, const std::wstring& tw, const std::wstring& en) {
    if (g_language == "en") return en;
    if (g_language == "zh-TW") return tw;
    return zh;
}

// ---------------------------------------------------------------- app state
static HINSTANCE g_instance = nullptr;
static HWND g_hwnd = nullptr;
static ID2D1Factory* g_d2d = nullptr;
static IDWriteFactory* g_dwrite = nullptr;
static ID2D1HwndRenderTarget* g_target = nullptr;
static IDWriteTextFormat* g_fmtTitle = nullptr;
static IDWriteTextFormat* g_fmtValue = nullptr;
static IDWriteTextFormat* g_fmtUnit = nullptr;
static IDWriteTextFormat* g_fmtSmall = nullptr;
static IDWriteTextFormat* g_fmtStats = nullptr;
static IDWriteTextFormat* g_fmtDetail = nullptr;
static IDWriteTextFormat* g_fmtHeader = nullptr;
static IDWriteTextFormat* g_fmtEyebrow = nullptr;
static IDWriteTextFormat* g_fmtButton = nullptr;

static cfg::Settings g_settings;
static std::vector<theme::Palette> g_palettes;
static theme::Material g_material{ 0.62f, 0.45f, "glass" };
static metrics::Collector g_collector;
static metrics::Snapshot g_snapshot;
static std::map<std::string, std::vector<double>> g_history;
static bool g_editMode = false;
static bool g_panelAdjusting = false;
static bool g_showRail = true;
static int g_hoverControl = 0;          // 0 none, 1 theme, 2 hide, 3 done, 4 scale-, 5 scale+, 6 mode, 7 layer
static RECT g_themeRect{}, g_hideRect{}, g_doneRect{}, g_scaleUpRect{}, g_scaleDownRect{}, g_modeRect{}, g_layerRect{};
static NOTIFYICONDATAW g_tray{};
static HMENU g_trayMenu = nullptr;
static bool g_dragging = false;
static POINT g_dragOrigin{};
static RECT g_dragWindow{};
static int g_dragCard = -1;
static POINT g_dragCardOffset{};
static bool g_exitRequested = false;
static UINT g_timerId = 0;
static float g_scale = 1.0f;            // DIP->physical factor for the panel
static std::wstring g_statusText;
static bool g_regionDirty = true;
static std::string g_trackedKey = "cpu";
struct InsightAlert { std::string key; double value; int level; SYSTEMTIME at; };
static std::vector<InsightAlert> g_alerts;
static std::map<std::string, int> g_alertLevels;

// ---------------------------------------------------------------- helpers
static uint32_t WithAlpha(uint32_t color, float factor) {
    float alpha = float((color >> 24) & 0xFF) * factor;
    if (alpha < 0) alpha = 0;
    if (alpha > 255) alpha = 255;
    return (color & 0x00FFFFFFu) | (uint32_t(alpha) << 24);
}
static D2D1_COLOR_F ToColorF(uint32_t argb) {
    return D2D1::ColorF(argb & 0x00FFFFFFu, float((argb >> 24) & 0xFF) / 255.0f);
}

static bool IsDesktopMode() { return g_settings.layerMode == "bottom"; }

static const theme::Palette& Pal() { return theme::Get(g_palettes, g_settings.theme); }

// ---------------------------------------------------------------- layout
struct Placement { const CardDef* card; int row, column, span; float x = 0, y = 0, w = 0, h = 0; };
// Section headers exactly as Dashboard.xaml labels them.
static const wchar_t* kLocalEyebrowZh = L"LOCAL MACHINE";
static const wchar_t* kLocalTitleZh = L"本机 · i9-13900KF + RTX 4070";
static const wchar_t* kLocalTitleEn = L"Local · i9-13900KF + RTX 4070";
static const wchar_t* kRemoteEyebrowZh = L"REMOTE COMPUTE";
static const wchar_t* kRemoteTitleZh = L"DGX Spark · GB10";
static float g_sectionTop = 0.0f;
static std::vector<Placement> g_placements;

static int PanelBaseHeight(bool desktop) { return (desktop ? 700 : 900) + 200; }

static void ComputeGeometry(RECT work, double requestedWidth, POINT position, bool desktop,
                            int& outWidth, int& outHeight, POINT& outPosition) {
    double baseHeight = PanelBaseHeight(desktop);
    const UINT dpi = g_hwnd ? GetDpiForWindow(g_hwnd) : 96;
    const double pixelsPerDip = dpi > 0 ? (double)dpi / 96.0 : 1.0;
    double factor = 1.0;
    if (requestedWidth > 10) factor = requestedWidth / 1600.0;
    else if (g_settings.preset == "auto") {
        factor = std::min(2.0, std::min((work.right - work.left) * 0.94 / 1600.0, (work.bottom - work.top) * 0.92 / baseHeight));
    } else if (g_settings.preset == "1080p") factor = 1.0;
    else if (g_settings.preset == "2k") factor = 1.4;
    else factor = 2.0;

    double width = 1600 * factor;
    // normalWidthDip/normalHeightDip are device-independent pixels, exactly as
    // the WPF layout stores them. desktopScale is already a physical ratio.
    double height = (!desktop && g_settings.normalHeightDip > 10)
        ? g_settings.normalHeightDip * pixelsPerDip
        : baseHeight * factor;
    double fit = std::min(1.0, std::min((work.right - work.left - 20) / width, (work.bottom - work.top - 20) / height));
    width = std::max(1.0, std::floor(width * fit));
    height = std::max(1.0, std::floor(height * fit));
    int padding = desktop ? 8 : 0;
    int x = (int)std::min(std::max((double)position.x, (double)work.left + padding), work.right - width - padding);
    int y = (int)std::min(std::max((double)position.y, (double)work.top + padding), work.bottom - height - padding);
    outWidth = (int)width;
    outHeight = (int)height;
    outPosition = POINT{ x, y };
}

static RECT WorkAreaAt(POINT point) {
    HMONITOR monitor = MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (monitor && GetMonitorInfoW(monitor, &info)) return info.rcWork;
    RECT fallback{};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &fallback, 0);
    return fallback;
}

static void ApplyPlacement(bool useCurrentPosition) {
    bool desktop = IsDesktopMode();
    RECT window{};
    GetWindowRect(g_hwnd, &window);
    POINT position{ window.left, window.top };
    if (!useCurrentPosition && g_settings.HasPosition(desktop)) {
        position = POINT{ (LONG)(desktop ? g_settings.desktopX : g_settings.normalX),
                          (LONG)(desktop ? g_settings.desktopY : g_settings.normalY) };
    }
    double width = desktop ? (g_settings.desktopScale * 1600.0)
                           : g_settings.normalWidthDip * (g_hwnd ? (double)GetDpiForWindow(g_hwnd) / 96.0 : 1.0);
    const POINT monitorPoint{ position.x + 40, position.y + 40 };
    const RECT work = WorkAreaAt(monitorPoint);
    int widthPx = 0, heightPx = 0;
    POINT topLeft{};
    ComputeGeometry(work, width, position, desktop, widthPx, heightPx, topLeft);
    // One place decides both dimensions and scale: the logical 1600-wide canvas
    // maps exactly onto the client area, including fractional-DPI displays.
    g_scale = float(widthPx) / 1600.0f;
    SetWindowPos(g_hwnd, nullptr, topLeft.x, topLeft.y, widthPx, heightPx, SWP_NOZORDER | SWP_NOACTIVATE);
    g_regionDirty = true;
}

// Layout constants live in the 1600-wide logical space (the same reference the WPF
// Viewbox uses), so proportions never drift with the window size.
static const float kLogicalWidth = 1600.0f;
static const float kCardWidth = 376.0f;
static const float kCellHeight = 200.0f;
static const float kContentLeft = 48.0f;
static const float kHeaderHeight = 94.0f;
static const float kFooterHeight = 46.0f;
static float g_scrollOffset = 0.0f;

static float ContentViewTop() { return IsDesktopMode() ? 0.0f : kHeaderHeight + 16.0f; }
static float LogicalHeight() {
    const float scale = g_scale > 0 ? g_scale : 1.0f;
    return (g_target ? g_target->GetSize().height : 900.0f) / scale;
}
static float ContentViewHeight() {
    return LogicalHeight() - ContentViewTop() - (IsDesktopMode() ? 0.0f : kFooterHeight);
}

// Places cards the way Dashboard.xaml does: two sections side by side (each two
// card columns wide, 28 px gutter) with their own eyebrow + title, and the system
// cards in a row underneath. Geometry is absolute in the 1600-wide logical space.
static void BuildPlacements(int /*columns*/) {
    g_placements.clear();
    std::vector<std::string> order = g_settings.cardOrder;
    for (const auto& key : DefaultCardKeys()) {
        if (std::find(order.begin(), order.end(), key) == order.end()) order.push_back(key);
    }
    if (!g_settings.enabledCards.empty()) {
        order.erase(std::remove_if(order.begin(), order.end(), [&](const std::string& key) {
            return std::find(g_settings.enabledCards.begin(), g_settings.enabledCards.end(), key) == g_settings.enabledCards.end();
        }), order.end());
    }
    const bool desktop = IsDesktopMode();
    const float gutter = 28.0f;
    const float halfWidth = (1504.0f - gutter) / 2.0f;      // 1504 = 1600 - 2*48
    const float columnWidth = halfWidth / 2.0f;
    const float headerBand = desktop ? 0.0f : 53.0f;        // LocalSection title row
    const float top = ContentViewTop();
    g_sectionTop = top;

    // Desktop mode keeps the free slot grid (cardSlots) — that is what dragging edits.
    if (desktop && !g_settings.cardSlots.empty()) {
        for (const auto& key : order) {
            const CardDef* card = FindCard(key);
            if (!card) continue;
            auto it = g_settings.cardSlots.find(key);
            if (it == g_settings.cardSlots.end()) continue;
            const int span = (g_settings.cardShapes.count(card->key) && g_settings.cardShapes[card->key] == "long") ? 2 : 1;
            Placement placement{ card, it->second.row, it->second.column, span };
            placement.x = 48.0f + it->second.column * 376.0f;
            placement.y = it->second.row * 200.0f;
            placement.w = span * 376.0f - 16.0f;
            placement.h = 200.0f - 16.0f;
            g_placements.push_back(placement);
        }
        return;
    }

    int leftRow = 0, leftCol = 0, rightRow = 0, rightCol = 0, sysRow = 0, sysCount = 0;
    float leftBottom = 0, rightBottom = 0;
    for (const auto& key : order) {
        const CardDef* card = FindCard(key);
        if (!card) continue;
        int span = (g_settings.cardShapes.count(card->key) && g_settings.cardShapes[card->key] == "long") ? 2 : 1;
        span = std::min(span, 2);
        Placement placement{ card, 0, 0, span };
        placement.w = span * columnWidth - 16.0f;
        placement.h = 200.0f - 16.0f;
        if (card->side == 'L') {
            if (leftCol + span > 2) { leftCol = 0; ++leftRow; }
            placement.row = leftRow;
            placement.column = leftCol;
            placement.x = 48.0f + leftCol * columnWidth;
            placement.y = top + headerBand + leftRow * 200.0f;
            leftCol += span;
            leftBottom = std::max(leftBottom, placement.y + 200.0f);
        } else if (card->side == 'R') {
            if (rightCol + span > 2) { rightCol = 0; ++rightRow; }
            placement.row = rightRow;
            placement.column = rightCol;
            placement.x = 48.0f + halfWidth + gutter + rightCol * columnWidth;
            placement.y = top + headerBand + rightRow * 200.0f;
            rightCol += span;
            rightBottom = std::max(rightBottom, placement.y + 200.0f);
        } else {
            if (sysCount + 1 > 4) { sysCount = 0; ++sysRow; }
            placement.row = sysRow;
            placement.column = sysCount;
            placement.x = 48.0f + sysCount * 376.0f;
            placement.y = std::max(leftBottom, rightBottom) + 16.0f + sysRow * 200.0f;
            ++sysCount;
        }
        g_placements.push_back(placement);
    }
}

// ---------------------------------------------------------------- text helpers
static void DrawText(ID2D1RenderTarget* target, const std::wstring& text, IDWriteTextFormat* format,
                     D2D1_RECT_F box, ID2D1Brush* brush) {
    target->DrawTextW(text.c_str(), (UINT32)text.size(), format, box, brush);
}

static float MeasureTextWidth(const std::wstring& text, IDWriteTextFormat* format) {
    if (!g_dwrite || !format) return 0;
    IDWriteTextLayout* layout = nullptr;
    const HRESULT hr = g_dwrite->CreateTextLayout(text.c_str(), (UINT32)text.size(), format, 1000, 1000, &layout);
    if (FAILED(hr) || !layout) return 0;
    DWRITE_TEXT_METRICS metrics{};
    layout->GetMetrics(&metrics);
    layout->Release();
    return metrics.width;
}

static std::wstring FormatNumber(double value, bool temperature) {
    wchar_t buffer[64];
    if (std::fabs(value) < 10) std::swprintf(buffer, 64, L"%.1f", value);
    else std::swprintf(buffer, 64, L"%.0f", value);
    (void)temperature;
    return buffer;
}

static std::wstring FormatValueForCard(const CardDef& card) {
    auto it = g_snapshot.values.find(card.key);
    if (it == g_snapshot.values.end()) return T(L"—", L"—", L"—");
    const double value = it->second;
    switch (card.side) {
    case 'S':
        if (std::string(card.key) == "netDown" || std::string(card.key) == "netUp") {
            // Formats KiB/s the way Format-ByteValue does (B/KiB/MiB).
            double perSecond = value * 1024.0;
            wchar_t buffer[64];
            if (perSecond >= 1048576) std::swprintf(buffer, 64, L"%.1f", perSecond / 1048576);
            else if (perSecond >= 1024) std::swprintf(buffer, 64, L"%.1f", perSecond / 1024);
            else std::swprintf(buffer, 64, L"%.0f", perSecond);
            return buffer;
        }
        return FormatNumber(value, false);
    default:
        return FormatNumber(value, card.temperature);
    }
}

static std::wstring FormatUnitForCard(const CardDef& card) {
    if (std::string(card.key) == "netDown" || std::string(card.key) == "netUp") {
        auto it = g_snapshot.values.find(card.key);
        double perSecond = it == g_snapshot.values.end() ? 0 : it->second * 1024.0;
        if (perSecond >= 1048576) return L"MiB/s";
        if (perSecond >= 1024) return L"KiB/s";
        return L"B/s";
    }
    return metrics::Utf8ToWide(card.unit);
}

static std::wstring CardDetail(const CardDef& card) {
    const std::string key = card.key;
    auto value = [&](const char* name) -> std::wstring {
        auto it = g_snapshot.values.find(name);
        if (it == g_snapshot.values.end()) return L"—";
        return FormatNumber(it->second, false);
    };
    if (key == "cpu") return T(L"功耗 ", L"功耗 ", L"Power ") + value("cpuPwr") + L" W";
    if (key == "gpuT") return T(L"功耗 ", L"功耗 ", L"Power ") + value("gpuPwr") + L" W · " + T(L"使用率 ", L"使用率 ", L"usage ") + value("gpuUtil") + L"%";
    if (key == "cpuRpm") return T(L"占空比 ", L"佔空比 ", L"Duty ") + value("cpuDuty") + L"%";
    if (key == "caseRpm") return T(L"占空比 ", L"佔空比 ", L"Duty ") + value("caseDuty") + L"%";
    if (key == "pumpRpm") return T(L"占空比 ", L"佔空比 ", L"Duty ") + value("pumpDuty") + L"%";
    if (key == "vrm") return L"PCH " + value("pch") + L" °C";
    if (key == "dgxGpuT") return T(L"功耗 ", L"功耗 ", L"Power ") + value("dgxGpuPwr") + L" W · " + T(L"使用率 ", L"使用率 ", L"usage ") + value("dgxGpuUtil") + L"%";
    if (key == "dgxCpu") return T(L"ACPI 最高温区", L"ACPI 最高溫區", L"ACPI thermal zone");
    if (key == "dgxFan") return L"acpi_fan";
    if (key == "dgxNvme") return T(L"本地盘", L"本機磁碟", L"local drive");
    if (key == "dgxMem") return T(L"共 ", L"共 ", L"of ") + value("dgxMemTot") + L" GB";
    if (key == "dgxLoad") return T(L"已运行 ", L"已執行 ", L"up ") + value("dgxUp") + T(L" 小时", L" 小時", L" h");
    if (key == "netDown") return T(L"上传 ", L"上傳 ", L"up ") + value("netUp");
    if (key == "netUp") return T(L"下载 ", L"下載 ", L"down ") + value("netDown");
    if (key == "diskPct") {
        const std::wstring summary = value("diskUsed") + L" / " + value("diskTotal") + L" GB";
        return g_snapshot.diskDetail.empty() ? summary : summary + L" · " + g_snapshot.diskDetail;
    }
    return {};
}

// ---------------------------------------------------------------- painting
static void DrawAmbient(ID2D1RenderTarget* target, D2D1_SIZE_F size, const theme::Palette& palette) {
    // Two soft radial glows, matching AmbientTop / AmbientBottom in Dashboard.xaml.
    const D2D1_GRADIENT_STOP topStops[2] = { { 0.0f, ToColorF(WithAlpha(palette.glowTop, 1.0f)) }, { 1.0f, ToColorF(WithAlpha(palette.glowTop, 0.0f)) } };
    const D2D1_GRADIENT_STOP bottomStops[2] = { { 0.0f, ToColorF(WithAlpha(palette.glowBottom, 1.0f)) }, { 1.0f, ToColorF(WithAlpha(palette.glowBottom, 0.0f)) } };
    ID2D1GradientStopCollection* collection = nullptr;
    if (SUCCEEDED(target->CreateGradientStopCollection(topStops, 2, &collection)) && collection) {
        ID2D1RadialGradientBrush* brush = nullptr;
        D2D1_RADIAL_GRADIENT_BRUSH_PROPERTIES props{
            D2D1::Point2F(size.width * 0.82f, size.height * 0.05f),
            D2D1::Point2F(size.width * 0.82f, size.height * 0.05f),
            size.width * 0.42f, size.height * 0.42f };
        if (SUCCEEDED(target->CreateRadialGradientBrush(props, collection, &brush)) && brush) {
            target->FillEllipse(D2D1::Ellipse(props.center, size.width * 0.42f, size.height * 0.30f), brush);
            brush->Release();
        }
        collection->Release();
    }
    collection = nullptr;
    if (SUCCEEDED(target->CreateGradientStopCollection(bottomStops, 2, &collection)) && collection) {
        ID2D1RadialGradientBrush* brush = nullptr;
        D2D1_RADIAL_GRADIENT_BRUSH_PROPERTIES props{
            D2D1::Point2F(size.width * 0.10f, size.height * 0.95f),
            D2D1::Point2F(size.width * 0.10f, size.height * 0.95f),
            size.width * 0.40f, size.height * 0.40f };
        if (SUCCEEDED(target->CreateRadialGradientBrush(props, collection, &brush)) && brush) {
            target->FillEllipse(D2D1::Ellipse(props.center, size.width * 0.40f, size.height * 0.26f), brush);
            brush->Release();
        }
        collection->Release();
    }
}

static void DrawCard(ID2D1RenderTarget* target, const Placement& placement, D2D1_RECT_F rect, const theme::Palette& palette) {
    const CardDef& card = *placement.card;
    const float radius = 20.0f;
    const D2D1_ROUNDED_RECT rounded = D2D1::RoundedRect(rect, radius, radius);

    // Card surface: the palette gradient with the material's alpha multiplier.
    const D2D1_GRADIENT_STOP stops[3] = {
        { 0.0f,    ToColorF(WithAlpha(palette.card[0], g_material.scale)) },
        { 0.55f,   ToColorF(WithAlpha(palette.card[1], g_material.scale)) },
        { 1.0f,    ToColorF(WithAlpha(palette.card[2], g_material.scale)) } };
    ID2D1GradientStopCollection* collection = nullptr;
    ID2D1LinearGradientBrush* fill = nullptr;
    if (SUCCEEDED(target->CreateGradientStopCollection(stops, 3, &collection)) && collection &&
        SUCCEEDED(target->CreateLinearGradientBrush(
            D2D1::LinearGradientBrushProperties(D2D1::Point2F(rect.left, rect.top),
                                               D2D1::Point2F(rect.left + (rect.right - rect.left) * 0.8f, rect.bottom)),
            collection, &fill)) && fill) {
        target->FillRoundedRectangle(rounded, fill);
        fill->Release();
    }
    if (collection) collection->Release();

    // Rim: the palette's rim gradient, approximated with its mid stop.
    ID2D1SolidColorBrush* rim = nullptr;
    if (SUCCEEDED(target->CreateSolidColorBrush(ToColorF(palette.rim[1]), &rim)) && rim) {
        target->DrawRoundedRectangle(rounded, rim, 1.2f);
        rim->Release();
    }

    // Top gloss band.
    ID2D1SolidColorBrush* gloss = nullptr;
    if (SUCCEEDED(target->CreateSolidColorBrush(ToColorF(WithAlpha(palette.gloss, g_material.gloss / 0.45f)), &gloss)) && gloss) {
        target->FillRoundedRectangle(
            D2D1::RoundedRect(D2D1::RectF(rect.left + 1, rect.top + 1, rect.right - 1, rect.top + 58), radius, radius), gloss);
        gloss->Release();
    }

    ID2D1SolidColorBrush* accent = nullptr;
    ID2D1SolidColorBrush* textBrush = nullptr;
    ID2D1SolidColorBrush* secondary = nullptr;
    target->CreateSolidColorBrush(ToColorF(card.color), &accent);
    target->CreateSolidColorBrush(ToColorF(palette.text), &textBrush);
    target->CreateSolidColorBrush(ToColorF(palette.secondary), &secondary);
    if (!accent || !textBrush || !secondary) {
        if (accent) accent->Release();
        if (textBrush) textBrush->Release();
        if (secondary) secondary->Release();
        return;
    }

    // Accent dot + title.
    target->FillEllipse(D2D1::Ellipse(D2D1::Point2F(rect.left + 24, rect.top + 26), 4.0f, 4.0f), accent);
    DrawText(target, Tr(card), g_fmtTitle, D2D1::RectF(rect.left + 36, rect.top + 14, rect.right - 20, rect.top + 40), accent);

    // Value + unit.
    const std::wstring value = FormatValueForCard(card);
    DrawText(target, value, g_fmtValue, D2D1::RectF(rect.left + 22, rect.top + 46, rect.right - 150, rect.top + 108), textBrush);
    // Place the unit after the measured value width, not at a fixed fraction of
    // the value box (which overlapped long values such as 2,066).
    const float measured = MeasureTextWidth(value, g_fmtValue);
    // Draw the unit directly after the measured number and let it use the rest
    // of the card. A second clamp against the stats lane hid °C and RPM.
    const float unitLeft = rect.left + 22 + measured + 10.0f;
    DrawText(target, FormatUnitForCard(card), g_fmtUnit,
             D2D1::RectF(unitLeft, rect.top + 78, rect.right - 18.0f, rect.top + 108), secondary);

    // Rolling max/min/mean on the right.
    auto history = g_history.find(card.key);
    if (history != g_history.end() && !history->second.empty()) {
        double max = history->second[0], min = history->second[0], sum = 0;
        for (double sample : history->second) { max = std::max(max, sample); min = std::min(min, sample); sum += sample; }
        const double mean = sum / double(history->second.size());
        const std::wstring stats = T(L"最大 ", L"最大 ", L"max ") + FormatNumber(max, false) + L"\n" +
                                   T(L"最小 ", L"最小 ", L"min ") + FormatNumber(min, false) + L"\n" +
                                   T(L"均值 ", L"均值 ", L"avg ") + FormatNumber(mean, false);
        DrawText(target, stats, g_fmtStats, D2D1::RectF(rect.right - 132, rect.top + 52, rect.right - 18, rect.top + 108), secondary);

        // Sparkline over the last samples.
        if (history->second.size() >= 3 && CardDetail(card).size() <= 42) {
            const float sparkLeft = rect.right - 150, sparkWidth = 128.0f, sparkTop = rect.top + 128, sparkHeight = 26.0f;
            double high = max, low = min;
            if (high - low < 2) high = low + 2;
            std::vector<D2D1_POINT_2F> points;
            const auto& samples = history->second;
            for (size_t i = 0; i < samples.size(); ++i) {
                float x = sparkLeft + sparkWidth * float(i) / float(samples.size() - 1);
                float y = sparkTop + 2 + (sparkHeight - 4) - (sparkHeight - 4) * float((samples[i] - low) / (high - low));
                points.push_back(D2D1::Point2F(x, y));
            }
            for (size_t i = 1; i < points.size(); ++i) target->DrawLine(points[i - 1], points[i], accent, 2.0f);
        }
    }

    // Long details wrap and take the full width; the sparkline yields to them
    // instead of truncating drive or sensor information.
    const std::wstring detail = CardDetail(card);
    const float detailRight = detail.size() > 42 ? rect.right - 22.0f : rect.right - 164.0f;
    DrawText(target, detail, g_fmtDetail ? g_fmtDetail : g_fmtSmall,
             D2D1::RectF(rect.left + 22, rect.bottom - 46, detailRight, rect.bottom - 8), secondary);
    accent->Release();
    textBrush->Release();
    secondary->Release();
}

static void DrawHeader(ID2D1RenderTarget* target, D2D1_SIZE_F size, const theme::Palette& palette) {
    ID2D1SolidColorBrush* local = nullptr;
    ID2D1SolidColorBrush* text = nullptr;
    ID2D1SolidColorBrush* secondary = nullptr;
    target->CreateSolidColorBrush(ToColorF(palette.local), &local);
    target->CreateSolidColorBrush(ToColorF(palette.text), &text);
    target->CreateSolidColorBrush(ToColorF(palette.secondary), &secondary);
    if (local && text) {
        DrawText(target, T(L"系统 / 实时监控", L"系統 / 即時監控", L"SYSTEM / LIVE MONITOR"),
                 g_fmtEyebrow, D2D1::RectF(48, 18, 640, 38), local);
        DrawText(target, T(L"系统状态", L"系統狀態", L"System status"),
                 g_fmtHeader, D2D1::RectF(46, 36, 640, 82), text);
    }
    if (secondary) {
        std::wstring status = g_statusText.empty() ? T(L"启动中", L"啟動中", L"starting") : g_statusText;
        DrawText(target, status, g_fmtSmall, D2D1::RectF(48, size.height - 42, size.width - 48, size.height - 16), secondary);
    }
    // Status pill and header buttons mirror StatusBorder / ThemeButton / HideButton.
    ID2D1SolidColorBrush* pill = nullptr;
    ID2D1SolidColorBrush* pillRim = nullptr;
    ID2D1SolidColorBrush* dot = nullptr;
    target->CreateSolidColorBrush(ToColorF(palette.pillBg), &pill);
    target->CreateSolidColorBrush(ToColorF(palette.pillBorder), &pillRim);
    target->CreateSolidColorBrush(ToColorF(g_snapshot.remoteFresh ? 0xFF6EE7ACu : 0xFFFF727Cu), &dot);
    const float right = size.width;
    const D2D1_RECT_F statusRect = D2D1::RectF(right - 566, 20, right - 256, 58);
    if (pill) target->FillRoundedRectangle(D2D1::RoundedRect(statusRect, 18, 18), pill);
    if (pillRim) target->DrawRoundedRectangle(D2D1::RoundedRect(statusRect, 18, 18), pillRim, 1.0f);
    if (dot) target->FillEllipse(D2D1::Ellipse(D2D1::Point2F(statusRect.left + 18, statusRect.top + 19), 4, 4), dot);
    const std::wstring status = g_statusText.empty() ? T(L"启动中", L"啟動中", L"starting") : g_statusText;
    DrawText(target, status, g_fmtSmall,
             D2D1::RectF(statusRect.left + 32, statusRect.top + 8, statusRect.right - 10, statusRect.bottom - 4), text ? text : secondary);

    g_themeRect = RECT{ (LONG)(right - 240), 20, (LONG)(right - 144), 58 };
    g_hideRect = RECT{ (LONG)(right - 128), 20, (LONG)(right - 32), 58 };
    auto headerButton = [&](RECT rect, const std::wstring& label) {
        const D2D1_RECT_F box = D2D1::RectF((float)rect.left, (float)rect.top, (float)rect.right, (float)rect.bottom);
        if (pill) target->FillRoundedRectangle(D2D1::RoundedRect(box, 11, 11), pill);
        if (pillRim) target->DrawRoundedRectangle(D2D1::RoundedRect(box, 11, 11), pillRim, 1.0f);
        DrawText(target, label, g_fmtButton, D2D1::RectF(box.left + 10, box.top + 7, box.right - 8, box.bottom - 3), text ? text : secondary);
    };
    headerButton(g_themeRect, T(L"主题", L"主題", L"Theme"));
    headerButton(g_hideRect, T(L"隐藏", L"隱藏", L"Hide"));

    if (pill) pill->Release();
    if (pillRim) pillRim->Release();
    if (dot) dot->Release();
    if (local) local->Release();
    if (text) text->Release();
    if (secondary) secondary->Release();
}

#include "insights.h"

#include "toolbar.h"

static void Render() {
    if (!g_target || !g_hwnd) return;
    const theme::Palette& palette = Pal();
    g_target->BeginDraw();
    g_target->SetTransform(D2D1::Matrix3x2F::Identity());
    // Desktop mode is transparent so the wallpaper shows through the gaps.
    g_target->Clear(IsDesktopMode() ? D2D1::ColorF(0, 0.0f) : D2D1::ColorF(0, 0.0f));
    g_target->SetTransform(D2D1::Matrix3x2F::Scale(g_scale, g_scale));
    if (!IsDesktopMode()) {
        const D2D1_GRADIENT_STOP stops[3] = {
            { 0.0f, ToColorF(palette.bg[0]) },
            { 0.52f, ToColorF(palette.bg[1]) },
            { 1.0f, ToColorF(palette.bg[2]) }
        };
        ID2D1GradientStopCollection* collection = nullptr;
        ID2D1LinearGradientBrush* background = nullptr;
        if (SUCCEEDED(g_target->CreateGradientStopCollection(stops, 3, &collection)) && collection &&
            SUCCEEDED(g_target->CreateLinearGradientBrush(
                D2D1::LinearGradientBrushProperties(D2D1::Point2F(0, 0), D2D1::Point2F(kLogicalWidth, LogicalHeight())),
                collection, &background)) && background) {
            g_target->FillRectangle(D2D1::RectF(0, 0, kLogicalWidth, LogicalHeight()), background);
            background->Release();
        }
        if (collection) collection->Release();
    }

    const D2D1_SIZE_F size = D2D1::SizeF(kLogicalWidth, LogicalHeight());
    if (!IsDesktopMode()) {
        DrawAmbient(g_target, size, palette);
        DrawHeader(g_target, size, palette);
    }

    BuildPlacements(4);
    const float viewTop = ContentViewTop();
    const float viewBottom = viewTop + ContentViewHeight();

    if (!IsDesktopMode()) {
        // Section headers mirror LocalSectionHeader / RemoteSectionHeader.
        ID2D1SolidColorBrush* localBrush = nullptr;
        ID2D1SolidColorBrush* remoteBrush = nullptr;
        ID2D1SolidColorBrush* titleBrush = nullptr;
        g_target->CreateSolidColorBrush(ToColorF(palette.local), &localBrush);
        g_target->CreateSolidColorBrush(ToColorF(palette.remote), &remoteBrush);
        g_target->CreateSolidColorBrush(ToColorF(palette.secondary), &titleBrush);
        const float gutter = 28.0f;
        const float halfWidth = (1504.0f - gutter) / 2.0f;
        const float headingTop = viewTop - g_scrollOffset;
        if (localBrush && titleBrush) {
            DrawText(g_target, kLocalEyebrowZh, g_fmtEyebrow,
                     D2D1::RectF(48, headingTop, 48 + halfWidth, headingTop + 20), localBrush);
            DrawText(g_target, (g_language == "en" ? kLocalTitleEn : kLocalTitleZh), g_fmtSmall,
                     D2D1::RectF(46, headingTop + 18, 48 + halfWidth, headingTop + 46), titleBrush);
        }
        if (remoteBrush && titleBrush) {
            const float remoteLeft = 48 + halfWidth + gutter;
            DrawText(g_target, kRemoteEyebrowZh, g_fmtEyebrow,
                     D2D1::RectF(remoteLeft, headingTop, remoteLeft + halfWidth, headingTop + 20), remoteBrush);
            DrawText(g_target, kRemoteTitleZh, g_fmtSmall,
                     D2D1::RectF(remoteLeft - 2, headingTop + 18, remoteLeft + halfWidth, headingTop + 46), titleBrush);
        }
        if (localBrush) localBrush->Release();
        if (remoteBrush) remoteBrush->Release();
        if (titleBrush) titleBrush->Release();
    }

    for (const auto& placement : g_placements) {
        const float top = placement.y - g_scrollOffset;
        if (top + placement.h < viewTop - 4 || top > viewBottom) continue;   // cull off-screen rows
        DrawCard(g_target, placement, D2D1::RectF(placement.x, top, placement.x + placement.w, top + placement.h), palette);
    }

    DrawEditToolbar(g_target, palette);

    if (IsDesktopMode()) DrawInsightsRail(g_target, palette);

    if (!IsDesktopMode()) {
        ID2D1SolidColorBrush* muted = nullptr;
        if (SUCCEEDED(g_target->CreateSolidColorBrush(ToColorF(palette.muted), &muted)) && muted) {
            DrawText(g_target,
                     T(L"双击托盘图标 显示 / 隐藏　·　右键打开设置", L"按兩下系統匣圖示 顯示 / 隱藏　·　按右鍵開啟設定",
                       L"Double-click the tray icon to show/hide · right-click for settings"),
                     g_fmtSmall, D2D1::RectF(kContentLeft, size.height - 40, kLogicalWidth - kContentLeft, size.height - 12), muted);
            muted->Release();
        }
    }

    g_target->EndDraw();
    g_regionDirty = true;
}

// ---------------------------------------------------------------- desktop mask
static std::vector<RECT> DesktopIconRects() {
    std::vector<RECT> rects;
    IUIAutomation* automation = nullptr;
    if (FAILED(CoCreateInstance(__uuidof(CUIAutomation), nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&automation))) || !automation)
        return rects;
    IUIAutomationElement* root = nullptr;
    if (SUCCEEDED(automation->GetRootElement(&root)) && root) {
        VARIANT type; VariantInit(&type); type.vt = VT_I4; type.lVal = UIA_ListControlTypeId;
        IUIAutomationCondition* condition = nullptr;
        if (SUCCEEDED(automation->CreatePropertyCondition(UIA_ControlTypePropertyId, type, &condition)) && condition) {
            IUIAutomationElementArray* lists = nullptr;
            if (SUCCEEDED(root->FindAll(TreeScope_Descendants, condition, &lists)) && lists) {
                int count = 0; lists->get_Length(&count);
                for (int i = 0; i < count; ++i) {
                    IUIAutomationElement* list = nullptr;
                    if (FAILED(lists->GetElement(i, &list)) || !list) continue;
                    IUIAutomationElementArray* items = nullptr;
                    if (SUCCEEDED(list->FindAll(TreeScope_Children, nullptr, &items)) && items) {
                        int itemCount = 0; items->get_Length(&itemCount);
                        for (int j = 0; j < itemCount && j < 512; ++j) {
                            IUIAutomationElement* item = nullptr;
                            if (FAILED(items->GetElement(j, &item)) || !item) continue;
                            RECT bounds{};
                            if (SUCCEEDED(item->get_CurrentBoundingRectangle(&bounds)) &&
                                bounds.right > bounds.left && bounds.bottom > bounds.top) rects.push_back(bounds);
                            item->Release();
                        }
                        items->Release();
                    }
                    list->Release();
                }
                lists->Release();
            }
            condition->Release();
        }
        root->Release();
    }
    automation->Release();
    return rects;
}

static void ApplyRegion() {
    RECT window{};
    GetWindowRect(g_hwnd, &window);
    HRGN region = CreateRectRgn(0, 0, 0, 0);
    BuildPlacements(4);
    const int width = window.right - window.left, height = window.bottom - window.top;
    const float scale = g_scale > 0 ? g_scale : 1.0f;
    for (const auto& placement : g_placements) {
        int left = (int)(placement.x * scale);
        int top = (int)((placement.y - g_scrollOffset) * scale);
        int right = (int)((placement.x + placement.w) * scale);
        int bottom = (int)((placement.y - g_scrollOffset + placement.h) * scale);
        if (right <= left || bottom <= top) continue;
        if (bottom < 0 || top > height) continue;
        HRGN piece = CreateRectRgn(left, std::max(0, top), right, std::min(height, bottom));
        CombineRgn(region, region, piece, RGN_OR);
        DeleteObject(piece);
    }
    if (!IsDesktopMode()) {
        // In normal mode the whole window is interactive.
        HRGN whole = CreateRectRgn(0, 0, width, height);
        CombineRgn(region, region, whole, RGN_OR);
        DeleteObject(whole);
    } else {
        if (g_settings.insightsRail) {
            // The rail is interactive like a card and must remain in the region.
            const int left = (int)(1192 * scale);
            const int top = (int)(12 * scale);
            const int right = (int)((1192 + 300) * scale);
            const int bottom = (int)((ContentViewHeight() - 12) * scale);
            HRGN rail = CreateRectRgn(left, top, right, bottom);
            CombineRgn(region, region, rail, RGN_OR);
            DeleteObject(rail);
        }
        for (const auto& icon : DesktopIconRects()) {
            HRGN hole = CreateRectRgn(icon.left - window.left, icon.top - window.top,
                                      icon.right - window.left, icon.bottom - window.top);
            CombineRgn(region, region, hole, RGN_DIFF);
            DeleteObject(hole);
        }
    }
    SetWindowRgn(g_hwnd, region, TRUE);
}

// ---------------------------------------------------------------- text formats
static void CreateFormats(const wchar_t* family) {
    auto make = [&](float size, DWRITE_FONT_WEIGHT weight, IDWriteTextFormat** out) {
        g_dwrite->CreateTextFormat(family, nullptr, weight, DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
                                   size, L"zh-CN", out);
        if (*out) {
            (*out)->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_NEAR);
            (*out)->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
        }
    };
    // Match the WPF card typography: title/unit/subline sizes are not scaled
    // down independently of the window's logical scale.
    make(15.0f, DWRITE_FONT_WEIGHT_BOLD, &g_fmtTitle);
    make(44.0f, DWRITE_FONT_WEIGHT_SEMI_BOLD, &g_fmtValue);
    make(15.0f, DWRITE_FONT_WEIGHT_NORMAL, &g_fmtUnit);
    make(14.0f, DWRITE_FONT_WEIGHT_NORMAL, &g_fmtSmall);
    make(11.0f, DWRITE_FONT_WEIGHT_NORMAL, &g_fmtStats);
    make(12.0f, DWRITE_FONT_WEIGHT_NORMAL, &g_fmtDetail);
    if (g_fmtDetail) g_fmtDetail->SetWordWrapping(DWRITE_WORD_WRAPPING_WRAP);
    make(30.0f, DWRITE_FONT_WEIGHT_SEMI_BOLD, &g_fmtHeader);
    make(12.0f, DWRITE_FONT_WEIGHT_SEMI_BOLD, &g_fmtEyebrow);
    make(13.0f, DWRITE_FONT_WEIGHT_NORMAL, &g_fmtButton);
}

// ---------------------------------------------------------------- tick
static void UpdateMetrics() {
    g_snapshot = g_collector.Collect();
    UpdateInsightsAlerts();
    for (const auto& [key, value] : g_snapshot.values) {
        auto& samples = g_history[key];
        samples.push_back(value);
        if (samples.size() > 60) samples.erase(samples.begin());
    }
    wchar_t buffer[128];
    if (g_snapshot.remoteAgeSec >= 0 && g_snapshot.remoteFresh) {
        std::swprintf(buffer, 128, T(L"DGX 在线 · %.0f 秒前", L"DGX 線上 · %.0f 秒前", L"DGX online · %.0f s ago").c_str(), g_snapshot.remoteAgeSec);
    } else if (!g_snapshot.remoteError.empty()) {
        const std::wstring message = T(L"DGX 连接失败 · ", L"DGX 連線失敗 · ", L"DGX connection failed · ") + g_snapshot.remoteError.substr(0, 90);
        std::swprintf(buffer, 128, L"%s", message.c_str());
    } else {
        std::swprintf(buffer, 128, L"%s", T(L"DGX 离线", L"DGX 離線", L"DGX offline").c_str());
    }
    g_statusText = buffer;
    InvalidateRect(g_hwnd, nullptr, FALSE);
}

// ---------------------------------------------------------------- window
static void ToggleTray(bool show) {
    if (show) {
        ZeroMemory(&g_tray, sizeof(g_tray));
        g_tray.cbSize = sizeof(g_tray);
        g_tray.hWnd = g_hwnd;
        g_tray.uID = 1;
        g_tray.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
        g_tray.uCallbackMessage = WM_APP + 1;
        g_tray.hIcon = LoadIconW(g_instance, L"APPICON");
        if (!g_tray.hIcon) g_tray.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
        wcscpy_s(g_tray.szTip, L"SysMon Glass");
        Shell_NotifyIconW(NIM_ADD, &g_tray);
    } else {
        Shell_NotifyIconW(NIM_DELETE, &g_tray);
    }
}

static void ShowPanel(bool visible) {
    ShowWindow(g_hwnd, visible ? SW_SHOWNOACTIVATE : SW_HIDE);
    if (visible) {
        ApplyPlacement(false);
        if (!IsDesktopMode()) {
            // A new normal-mode window must not start behind the active terminal.
            SetWindowPos(g_hwnd, g_settings.layerMode == "top" ? HWND_TOPMOST : HWND_TOP,
                         0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
            SetForegroundWindow(g_hwnd);
        }
        InvalidateRect(g_hwnd, nullptr, FALSE);
    }
}

static void UpdateBackdrop() {
    if (!g_hwnd) return;
    // Blur only the normal window backdrop. Bottom mode must remain transparent
    // so the desktop wallpaper and icons show through the card gaps.
    DWM_BLURBEHIND blur{};
    blur.dwFlags = DWM_BB_ENABLE | DWM_BB_BLURREGION;
    blur.fEnable = IsDesktopMode() ? FALSE : TRUE;
    blur.hRgnBlur = CreateRectRgn(0, 0, 32767, 32767);
    DwmEnableBlurBehindWindow(g_hwnd, &blur);
    if (blur.hRgnBlur) DeleteObject(blur.hRgnBlur);
}

static void SetLayerMode(const std::string& mode, bool persist) {
    g_settings.layerMode = mode;
    // Shared position: a layer switch keeps the panel where it is.
    RECT window{};
    GetWindowRect(g_hwnd, &window);
    g_settings.normalX = window.left; g_settings.normalY = window.top;
    g_settings.desktopX = window.left; g_settings.desktopY = window.top;

    LONG_PTR ex = GetWindowLongPtrW(g_hwnd, GWL_EXSTYLE);
    if (mode == "bottom") ex |= WS_EX_NOACTIVATE; else ex &= ~WS_EX_NOACTIVATE;
    SetWindowLongPtrW(g_hwnd, GWL_EXSTYLE, ex);
    SetWindowPos(g_hwnd, mode == "top" ? HWND_TOPMOST : (mode == "bottom" ? HWND_BOTTOM : HWND_NOTOPMOST),
                 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    UpdateBackdrop();
    ApplyPlacement(false);
    if (persist) cfg::Save(g_settings);
    g_regionDirty = true;
}

static void StepScale(double delta) {
    if (IsDesktopMode()) {
        const double current = g_settings.desktopScale > 0.001 ? g_settings.desktopScale : (g_scale > 0.001 ? g_scale : 1.0);
        g_settings.desktopScale = std::min(2.0, std::max(0.4, current + delta));
    } else {
        double width = g_settings.normalWidthDip > 0 ? g_settings.normalWidthDip : 1600.0;
        width = std::min(3840.0, std::max(800.0, width * (1.0 + delta)));
        g_settings.normalWidthDip = width;
        g_settings.normalHeightDip = width * PanelBaseHeight(false) / 1600.0;
    }
    ApplyPlacement(true);
    cfg::Save(g_settings);
}

static std::wstring NativeExePath() {
    wchar_t path[MAX_PATH] = {};
    GetModuleFileNameW(nullptr, path, MAX_PATH);
    return L"\"" + std::wstring(path) + L"\"";
}
static bool IsAutoStartEnabled() {
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, KEY_READ, &key) != ERROR_SUCCESS) return false;
    wchar_t value[MAX_PATH * 2] = {};
    DWORD size = sizeof(value), type = 0;
    const bool present = RegQueryValueExW(key, L"SysMon.Glass", nullptr, &type, (LPBYTE)value, &size) == ERROR_SUCCESS;
    RegCloseKey(key);
    return present;
}
static void SetAutoStart(bool enabled) {
    HKEY key = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS) return;
    if (enabled) {
        const std::wstring command = NativeExePath();
        RegSetValueExW(key, L"SysMon.Glass", 0, REG_SZ, (const BYTE*)command.c_str(), DWORD((command.size() + 1) * sizeof(wchar_t)));
    } else {
        RegDeleteValueW(key, L"SysMon.Glass");
    }
    RegCloseKey(key);
}

static void ShowDetail(int index) {
    if (index < 0 || index >= (int)g_placements.size()) return;
    const CardDef& card = *g_placements[index].card;
    g_trackedKey = card.key;
    std::wstring message = Tr(card);
    message += L"\n";
    message += FormatValueForCard(card) + L" " + FormatUnitForCard(card);
    message += L"\n";
    message += CardDetail(card);
    MessageBoxW(g_hwnd, message.c_str(), T(L"卡片详情", L"卡片詳情", L"Card detail").c_str(), MB_OK | MB_ICONINFORMATION);
}

#include "manager.h"
#include "remote.h"

static void ShowContextMenu(int x, int y) {
    HMENU menu = CreatePopupMenu();
    AppendMenuW(menu, MF_STRING | ((g_editMode || g_panelAdjusting) ? MF_CHECKED : 0), 100,
                (g_editMode || g_panelAdjusting) ? T(L"完成编辑", L"完成編輯", L"Done").c_str() : T(L"编辑布局", L"編輯佈局", L"Edit layout").c_str());
    HMENU scales = CreatePopupMenu();
    AppendMenuW(scales, MF_STRING | (g_settings.preset == "auto" ? MF_CHECKED : 0), 700, T(L"自动适配", L"自動適配", L"Auto fit").c_str());
    AppendMenuW(scales, MF_STRING | (g_settings.preset == "1080p" ? MF_CHECKED : 0), 701, L"1080p");
    AppendMenuW(scales, MF_STRING | (g_settings.preset == "2k" ? MF_CHECKED : 0), 702, L"2K");
    AppendMenuW(scales, MF_STRING | (g_settings.preset == "4k" ? MF_CHECKED : 0), 703, L"4K");
    AppendMenuW(scales, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(scales, MF_STRING, 704, T(L"缩小 5%", L"縮小 5%", L"Smaller 5%").c_str());
    AppendMenuW(scales, MF_STRING, 705, T(L"放大 5%", L"放大 5%", L"Larger 5%").c_str());
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)scales, T(L"缩放 / 预设", L"縮放 / 預設", L"Scale / preset").c_str());
    HMENU themes = CreatePopupMenu();
    int id = 200;
    for (const auto& name : theme::Order()) {
        AppendMenuW(themes, MF_STRING | (g_settings.theme == name ? MF_CHECKED : 0), id, metrics::Utf8ToWide(name).c_str());
        ++id;
    }
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)themes, T(L"主题", L"主題", L"Theme").c_str());
    HMENU materials = CreatePopupMenu();
    AppendMenuW(materials, MF_STRING | (g_settings.material == "glass" ? MF_CHECKED : 0), 300, L"glass");
    AppendMenuW(materials, MF_STRING | (g_settings.material == "frosted" ? MF_CHECKED : 0), 301, L"frosted");
    AppendMenuW(materials, MF_STRING | (g_settings.material == "solid" ? MF_CHECKED : 0), 302, L"solid");
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)materials, T(L"材质", L"材質", L"Material").c_str());
    HMENU languages = CreatePopupMenu();
    AppendMenuW(languages, MF_STRING | (g_language == "zh-CN" ? MF_CHECKED : 0), 1000, L"简体中文");
    AppendMenuW(languages, MF_STRING | (g_language == "zh-TW" ? MF_CHECKED : 0), 1001, L"繁體中文");
    AppendMenuW(languages, MF_STRING | (g_language == "en" ? MF_CHECKED : 0), 1002, L"English");
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)languages, T(L"界面语言", L"介面語言", L"Language").c_str());
    HMENU rates = CreatePopupMenu();
    AppendMenuW(rates, MF_STRING | (g_settings.interval == 1000 ? MF_CHECKED : 0), 1010, L"1s");
    AppendMenuW(rates, MF_STRING | (g_settings.interval == 2000 ? MF_CHECKED : 0), 1011, L"2s");
    AppendMenuW(rates, MF_STRING | (g_settings.interval == 3000 ? MF_CHECKED : 0), 1012, L"3s");
    AppendMenuW(rates, MF_STRING | (g_settings.interval == 5000 ? MF_CHECKED : 0), 1013, L"5s");
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)rates, T(L"刷新频率", L"刷新頻率", L"Refresh rate").c_str());
    AppendMenuW(menu, MF_STRING | (IsAutoStartEnabled() ? MF_CHECKED : 0), 1020, T(L"登录时启动", L"登入時啟動", L"Start at login").c_str());
    HMENU layers = CreatePopupMenu();
    AppendMenuW(layers, MF_STRING | (g_settings.layerMode == "top" ? MF_CHECKED : 0), 400, T(L"置顶", L"置頂", L"Top").c_str());
    AppendMenuW(layers, MF_STRING | (g_settings.layerMode == "normal" ? MF_CHECKED : 0), 401, T(L"普通", L"普通", L"Normal").c_str());
    AppendMenuW(layers, MF_STRING | (g_settings.layerMode == "bottom" ? MF_CHECKED : 0), 402, T(L"置底（底层模式）", L"置底（底層模式）", L"Bottom").c_str());
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)layers, T(L"窗口图层", L"視窗圖層", L"Window layer").c_str());
    AppendMenuW(menu, MF_STRING | (g_settings.insightsRail ? MF_CHECKED : 0), 500, T(L"洞察栏", L"洞察欄", L"Insights rail").c_str());
    AppendMenuW(menu, MF_STRING, 800, T(L"卡片管理…", L"卡片管理…", L"Card manager…").c_str());
    AppendMenuW(menu, MF_STRING, 900, T(L"远程主机…", L"遠端主機…", L"Remote hosts…").c_str());
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, 600, T(L"隐藏", L"隱藏", L"Hide").c_str());
    AppendMenuW(menu, MF_STRING, 601, T(L"退出", L"結束", L"Quit").c_str());

    int command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, x, y, 0, g_hwnd, nullptr);
    DestroyMenu(menu);
    switch (command) {
    case 100:
        if (g_editMode || g_panelAdjusting) { g_editMode = false; g_panelAdjusting = false; }
        else if (IsDesktopMode()) g_panelAdjusting = true;
        else g_editMode = true;
        break;
    case 700: g_settings.preset = "auto"; g_settings.desktopScale = 0; ApplyPlacement(false); cfg::Save(g_settings); break;
    case 701: g_settings.preset = "1080p"; ApplyPlacement(false); cfg::Save(g_settings); break;
    case 702: g_settings.preset = "2k"; ApplyPlacement(false); cfg::Save(g_settings); break;
    case 703: g_settings.preset = "4k"; ApplyPlacement(false); cfg::Save(g_settings); break;
    case 704: StepScale(-0.05); break;
    case 705: StepScale(0.05); break;
    case 800: ShowCardManager(g_hwnd); break;
    case 900: ShowRemoteEditor(g_hwnd); break;
    case 1000: case 1001: case 1002:
        g_language = command == 1000 ? "zh-CN" : (command == 1001 ? "zh-TW" : "en");
        g_settings.language = g_language;
        cfg::Save(g_settings);
        break;
    case 1010: case 1011: case 1012: case 1013: {
        g_settings.interval = command == 1010 ? 1000 : (command == 1011 ? 2000 : (command == 1012 ? 3000 : 5000));
        if (g_timerId) KillTimer(g_hwnd, g_timerId);
        g_timerId = SetTimer(g_hwnd, 1, UINT(g_settings.interval), nullptr);
        cfg::Save(g_settings);
        break;
    }
    case 1020: SetAutoStart(!IsAutoStartEnabled()); break;
    case 200: case 201: case 202: case 203: case 204: case 205: case 206: case 207: case 208: case 209: case 210: {
        auto order = theme::Order();
        g_settings.theme = order[size_t(command - 200)];
        cfg::Save(g_settings);
        break;
    }
    case 300: g_settings.material = "glass"; cfg::Save(g_settings); break;
    case 301: g_settings.material = "frosted"; cfg::Save(g_settings); break;
    case 302: g_settings.material = "solid"; cfg::Save(g_settings); break;
    case 400: SetLayerMode("top", true); break;
    case 401: SetLayerMode("normal", true); break;
    case 402: SetLayerMode("bottom", true); break;
    case 500: g_settings.insightsRail = !g_settings.insightsRail; cfg::Save(g_settings); break;
    case 600: ShowPanel(false); break;
    case 601: g_exitRequested = true; PostMessageW(g_hwnd, WM_CLOSE, 0, 0); break;
    default: break;
    }
    g_material = theme::GetMaterial(g_settings.material);
    InvalidateRect(g_hwnd, nullptr, FALSE);
}

// Hit-testing for header buttons; rectangles are computed in Render().
static void LayoutButtons(D2D1_SIZE_F size) {
    const int buttonWidth = 96, buttonHeight = 34, gap = 8;
    int right = (int)size.width - 24;
    g_hideRect = RECT{ right - buttonWidth, 24, right, 24 + buttonHeight };
    right -= buttonWidth + gap;
    g_themeRect = RECT{ right - buttonWidth, 24, right, 24 + buttonHeight };
}

static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_CREATE:
        g_hwnd = hwnd;
        return 0;

    case WM_NCHITTEST: {
        // Normal mode: the 8px rim drags the panel (shipping behaviour of the WPF build).
        if (IsDesktopMode()) return HTCLIENT;
        POINT point{ GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) };
        RECT window{}; GetWindowRect(hwnd, &window);
        int cx = point.x - window.left, cy = point.y - window.top;
        int width = window.right - window.left, height = window.bottom - window.top;
        bool grip = cx >= width - 64 && cy >= height - 64;
        if (!grip && (cx < 8 || cx >= width - 8 || cy < 8 || cy >= height - 8)) return HTCAPTION;
        return HTCLIENT;
    }

    case WM_NCLBUTTONDBLCLK:
        return 0;   // never maximise this borderless panel

    case WM_SIZE:
        if (g_target) { g_target->Resize(D2D1::SizeU(LOWORD(lParam), HIWORD(lParam))); }
        g_regionDirty = true;
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;

    case WM_LBUTTONDOWN: {
        int x = GET_X_LPARAM(lParam), y = GET_Y_LPARAM(lParam);
        RECT window{}; GetWindowRect(hwnd, &window);
        int width = window.right - window.left, height = window.bottom - window.top;
        // Resize grip (bottom-right 24px), same affordance as the WPF build.
        if (!IsDesktopMode() && x >= width - 32 && y >= height - 32) {
            SendMessageW(hwnd, WM_SYSCOMMAND, SC_SIZE | 8, 0);   // SC_SIZE + bottom-right
            return 0;
        }
        // Toolbar buttons use the same logical coordinates as DrawEditToolbar.
        if (g_editMode || g_panelAdjusting) {
            const float scale = g_scale > 0 ? g_scale : 1.0f;
            POINT logical{ (LONG)(x / scale), (LONG)(y / scale) };
            if (PtInRect(&g_doneRect, logical)) {
                g_editMode = false; g_panelAdjusting = false;
                cfg::Save(g_settings);
                InvalidateRect(hwnd, nullptr, FALSE);
                return 0;
            }
            if (PtInRect(&g_scaleDownRect, logical)) { StepScale(-0.05); return 0; }
            if (PtInRect(&g_scaleUpRect, logical)) { StepScale(0.05); return 0; }
            if (PtInRect(&g_modeRect, logical)) {
                if (g_editMode) { g_editMode = false; g_panelAdjusting = true; }
                else { g_panelAdjusting = false; g_editMode = true; }
                InvalidateRect(hwnd, nullptr, FALSE);
                return 0;
            }
            if (PtInRect(&g_layerRect, logical)) {
                SetLayerMode(g_settings.layerMode == "top" ? "normal" : (g_settings.layerMode == "normal" ? "bottom" : "top"), true);
                InvalidateRect(hwnd, nullptr, FALSE);
                return 0;
            }
        }
        // Header buttons.
        const float headerScale = g_scale > 0 ? g_scale : 1.0f;
        POINT client{ (LONG)(x / headerScale), (LONG)(y / headerScale) };
        if (!IsDesktopMode()) {
            if (PtInRect(&g_hideRect, client)) { ShowPanel(false); return 0; }
            if (PtInRect(&g_themeRect, client)) {
                auto order = theme::Order();
                size_t index = 0;
                for (size_t i = 0; i < order.size(); ++i) if (order[i] == g_settings.theme) { index = i; break; }
                g_settings.theme = order[(index + 1) % order.size()];
                cfg::Save(g_settings);
                InvalidateRect(hwnd, nullptr, FALSE);
                return 0;
            }
        }
        // Panel adjustment mode: dragging any card or blank area moves the panel.
        if (IsDesktopMode() && g_panelAdjusting) {
            g_dragging = true;
            g_dragOrigin = POINT{ x, y };
            GetWindowRect(hwnd, &g_dragWindow);
            SetCapture(hwnd);
            return 0;
        }
        // Card click → detail. Hit test in the same logical space Render() uses.
        const float hitScale = g_scale > 0 ? g_scale : 1.0f;
        const float logicalX = x / hitScale, logicalY = y / hitScale;
        for (size_t i = 0; i < g_placements.size(); ++i) {
            const auto& placement = g_placements[i];
            float left = placement.x;
            float top = placement.y - g_scrollOffset;
            float cardWidth = placement.w;
            float cardHeight = placement.h;
            if (logicalX >= left && logicalX <= left + cardWidth && logicalY >= top && logicalY <= top + cardHeight) {
                if (g_editMode) {
                    g_dragCard = int(i);
                    g_dragCardOffset = POINT{ x - (int)left, y - (int)top };
                    SetCapture(hwnd);
                } else {
                    ShowDetail(int(i));
                }
                return 0;
            }
        }
        // Blank chrome: drag the panel (normal mode), like the margins in WPF.
        if (!IsDesktopMode()) {
            g_dragging = true;
            g_dragOrigin = POINT{ x, y };
            GetWindowRect(hwnd, &window);
            g_dragWindow = window;
            SetCapture(hwnd);
        }
        return 0;
    }

    case WM_MOUSEMOVE: {
        if (g_dragCard >= 0 && g_placements.size() > size_t(g_dragCard)) {
            const auto& placement = g_placements[size_t(g_dragCard)];
            D2D1_SIZE_F size = g_target->GetSize();
            const float cellWidth = size.width / 4.0f;
            const float cellHeight = cellWidth * 200.0f / 376.0f;
            int column = std::max(0, std::min(3, int((GET_X_LPARAM(lParam) - g_dragCardOffset.x) / cellWidth)));
            int row = std::max(0, int((GET_Y_LPARAM(lParam) - g_dragCardOffset.y - (IsDesktopMode() ? 0 : 96)) / cellHeight));
            // Move the dragged card to the front of its slot group (visual only until release).
            g_settings.cardSlots[placement.card->key] = cfg::Slot{ row, column };
            InvalidateRect(hwnd, nullptr, FALSE);
            return 0;
        }
        if (g_dragging) {
            POINT cursor{ GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) };
            ClientToScreen(hwnd, &cursor);
            SetWindowPos(hwnd, nullptr,
                         g_dragWindow.left + (cursor.x - g_dragWindow.left) - g_dragOrigin.x,
                         g_dragWindow.top + (cursor.y - g_dragWindow.top) - g_dragOrigin.y,
                         0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
            return 0;
        }
        return 0;
    }

    case WM_LBUTTONUP: {
        if (g_dragCard >= 0) {
            // Commit: persist slot order, then re-pack from slots.
            g_settings.customLayout = true;
            cfg::Save(g_settings);
            g_dragCard = -1;
            ReleaseCapture();
            InvalidateRect(hwnd, nullptr, FALSE);
            return 0;
        }
        if (g_dragging) {
            g_dragging = false;
            ReleaseCapture();
            RECT window{}; GetWindowRect(hwnd, &window);
            g_settings.normalX = window.left; g_settings.normalY = window.top;
            g_settings.desktopX = window.left; g_settings.desktopY = window.top;
            cfg::Save(g_settings);
            return 0;
        }
        return 0;
    }

    case WM_RBUTTONUP: {
        POINT point{ GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) };
        ClientToScreen(hwnd, &point);
        ShowContextMenu(point.x, point.y);
        return 0;
    }

    case WM_KEYDOWN:
        if (wParam == VK_ESCAPE) { g_editMode = false; g_panelAdjusting = false; InvalidateRect(hwnd, nullptr, FALSE); }
        return 0;

    case WM_TIMER:
        if (wParam == g_timerId) { UpdateMetrics(); return 0; }
        return 0;

    case WM_APP + 1:   // tray callback
        if (LOWORD(lParam) == WM_LBUTTONDBLCLK) {
            ShowPanel(!IsWindowVisible(hwnd));
        } else if (LOWORD(lParam) == WM_RBUTTONUP) {
            POINT point{}; GetCursorPos(&point);
            HMENU menu = CreatePopupMenu();
            AppendMenuW(menu, MF_STRING, 1, T(L"显示 / 隐藏", L"顯示 / 隱藏", L"Show / hide").c_str());
            AppendMenuW(menu, MF_STRING, 2, T(L"退出", L"結束", L"Quit").c_str());
            int command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, point.x, point.y, 0, hwnd, nullptr);
            DestroyMenu(menu);
            if (command == 1) ShowPanel(!IsWindowVisible(hwnd));
            if (command == 2) PostMessageW(hwnd, WM_CLOSE, 0, 0);
        }
        return 0;

    case WM_MOUSEWHEEL: {
        if (IsDesktopMode()) return 0;
        BuildPlacements(4);
        int lastRow = 0;
        for (const auto& placement : g_placements) lastRow = std::max(lastRow, placement.row);
        const float contentHeight = (lastRow + 1) * kCellHeight + 16.0f;
        const float maxScroll = std::max(0.0f, contentHeight - ContentViewHeight());
        g_scrollOffset -= GET_WHEEL_DELTA_WPARAM(wParam) / 120.0f * 90.0f;
        g_scrollOffset = std::max(0.0f, std::min(maxScroll, g_scrollOffset));
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
    }

    case WM_DPICHANGED: {
        RECT* suggested = (RECT*)lParam;
        // Windows' suggested rectangle may shrink the panel on a DPI transition.
        // Keep the user's physical size and let ApplyPlacement recompute the scale.
        SetWindowPos(hwnd, nullptr, suggested->left, suggested->top, 0, 0,
                     SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
        ApplyPlacement(true);
        return 0;
    }

    case WM_ERASEBKGND:
        return 1;

    case WM_PAINT: {
        PAINTSTRUCT ps{};
        BeginPaint(hwnd, &ps);
        if (!g_target && g_d2d) {
            RECT client{}; GetClientRect(hwnd, &client);
            g_d2d->CreateHwndRenderTarget(
                D2D1::RenderTargetProperties(D2D1_RENDER_TARGET_TYPE_DEFAULT,
                    D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED)),
                D2D1::HwndRenderTargetProperties(hwnd, D2D1::SizeU(client.right, client.bottom)),
                &g_target);
            if (g_target) g_target->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_CLEARTYPE);
        }
        Render();
        if (IsDesktopMode()) ApplyRegion();
        EndPaint(hwnd, &ps);
        return 0;
    }

    case WM_CLOSE:
        if (!g_exitRequested) { ShowPanel(false); return 0; }
        DestroyWindow(hwnd);
        return 0;

    case WM_DESTROY:
        ToggleTray(false);
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

int WINAPI WinMain(HINSTANCE instance, HINSTANCE, LPSTR, int) {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    g_instance = instance;

    D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, &g_d2d);
    DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), (IUnknown**)&g_dwrite);
    CreateFormats(L"Microsoft YaHei UI");

    g_settings = cfg::Load();
    g_language = g_settings.language.empty() ? "zh-CN" : g_settings.language;
    g_material = theme::GetMaterial(g_settings.material);
    g_palettes = theme::BuildAll();
    g_showRail = g_settings.insightsRail;

    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = WndProc;
    wc.hInstance = instance;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = L"SysMonGlassNative";
    wc.hbrBackground = nullptr;
    wc.hIcon = LoadIconW(instance, L"APPICON");
    wc.hIconSm = wc.hIcon;
    RegisterClassExW(&wc);

    RECT work{};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    POINT start{ (work.right - work.left - 1200) / 2, (work.bottom - work.top - 700) / 2 };
    g_hwnd = CreateWindowExW(WS_EX_TOOLWINDOW, wc.lpszClassName, L"系统状态 · Glass", WS_POPUP,
                             start.x, start.y, 1200, 700, nullptr, nullptr, instance, nullptr);
    if (!g_hwnd) return 1;

    {
        char startup[MAX_PATH] = {};
        GetTempPathA(MAX_PATH, startup);
        std::string file = std::string(startup) + "sysmon-ssh.log";
        if (FILE* fp = std::fopen(file.c_str(), "ab")) {
            std::fprintf(fp, "startup hosts=%zu active=%s enabled=%d lang=%s config=%s\n",
                         g_settings.hosts.size(),
                         g_settings.activeHostId.c_str(),
                         g_settings.hosts.empty() ? -1 : (g_settings.hosts.front().enabled ? 1 : 0),
                         g_settings.language.c_str(),
                         cfg::ConfigPath().c_str());
            std::fclose(fp);
        }
    }
    for (const auto& host : g_settings.hosts) {
        if (host.id == g_settings.activeHostId) { g_collector.StartRemote(host); break; }
    }
    UpdateMetrics();
    ApplyPlacement(false);
    SetLayerMode(g_settings.layerMode, false);
    g_timerId = SetTimer(g_hwnd, 1, UINT(g_settings.interval), nullptr);
    ToggleTray(true);
    ShowPanel(true);

    MSG message;
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }

    if (g_timerId) KillTimer(g_hwnd, g_timerId);
    g_collector.StopRemote();
    if (g_target) g_target->Release();
    for (IDWriteTextFormat* format : { g_fmtTitle, g_fmtValue, g_fmtUnit, g_fmtSmall, g_fmtStats, g_fmtDetail, g_fmtHeader, g_fmtEyebrow, g_fmtButton })
        if (format) format->Release();
    if (g_dwrite) g_dwrite->Release();
    if (g_d2d) g_d2d->Release();
    CoUninitialize();
    return 0;
}
