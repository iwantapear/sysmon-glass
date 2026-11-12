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
#include <string_view>
#include <vector>
#include <map>
#include <algorithm>
#include <cmath>
#include <cctype>
#include <cstdio>
#include <memory>
#include <tuple>

#include "json.h"
#include "theme.h"
#include "config.h"
#include "layout.h"
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
    { "netDown", "本机 · 网络速率 · 下载", "本機 · 網路速率 · 下載", "Local · network down", "",      0xFF74DAEBu, nullptr, 'S', false },
    { "netUp",   "本机 · 网络速率 · 上传", "本機 · 網路速率 · 上傳", "Local · network up",   "",      0xFF9BE5B8u, nullptr, 'S', false },
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
static IDWriteTextFormat* g_fmtCardSub = nullptr;
static IDWriteTextFormat* g_fmtHeader = nullptr;
static IDWriteTextFormat* g_fmtEyebrow = nullptr;
static IDWriteTextFormat* g_fmtButton = nullptr;
static IDWriteTextFormat* g_fmtIcon = nullptr;

static cfg::Settings g_settings;
static std::vector<theme::Palette> g_palettes;
static theme::Material g_material{ 0.62f, 0.45f, "glass" };
static metrics::Collector g_collector;
static metrics::Snapshot g_snapshot;
static std::map<std::string, std::vector<double>> g_history;
static bool g_editMode = false;
static bool g_panelAdjusting = false;
static RECT g_themeRect{}, g_hideRect{}, g_doneRect{}, g_scaleUpRect{}, g_scaleDownRect{}, g_modeRect{}, g_layerRect{};
static NOTIFYICONDATAW g_tray{};
static bool g_dragging = false;
static bool g_resizing = false;
static bool g_resizeChanged = false;
static POINT g_dragOrigin{};
static RECT g_dragWindow{};
static std::string g_dragCard;
static POINT g_dragStart{};
static POINT g_dragCardOffset{};
static cfg::Slot g_dragTarget{};
static bool g_cardMoved = false;
static bool g_exitRequested = false;
static UINT g_timerId = 0;
static float g_scale = 1.0f;            // DIP->physical factor for the panel
static std::wstring g_statusText;
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

static std::vector<Placement> g_placements;

static int PanelBaseHeight(bool desktop) { return desktop || g_editMode ? 900 : 1040; }

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
    const double dpiScale = GetDpiForWindow(g_hwnd) / 96.0;
    const double width = desktop ? g_settings.desktopScale * 1600.0 * dpiScale
                                 : g_settings.normalWidthDip * dpiScale;
    const POINT monitorPoint{ position.x + 40, position.y + 40 };
    const RECT work = WorkAreaAt(monitorPoint);
    int widthPx = 0, heightPx = 0;
    POINT topLeft{};
    ComputeGeometry(work, width, position, desktop, widthPx, heightPx, topLeft);
    // One place decides both dimensions and scale: the logical 1600-wide canvas
    // maps exactly onto the client area, including fractional-DPI displays.
    g_scale = float(widthPx) / 1600.0f;
    SetWindowPos(g_hwnd, nullptr, topLeft.x, topLeft.y, widthPx, heightPx, SWP_NOZORDER | SWP_NOACTIVATE);
}

// Layout constants live in the 1600-wide logical space (the same reference the WPF
// Viewbox uses), so proportions never drift with the window size.
static const float kLogicalWidth = 1600.0f;
static const float kCardWidth = 376.0f;
static const float kCellHeight = 200.0f;
static constexpr float kContentLeft = 48.0f;
static const float kHeaderHeight = 94.0f;
static const float kFooterHeight = 46.0f;
static float g_scrollOffset = 0.0f;

static bool ShowsChrome() { return !IsDesktopMode() && !g_editMode; }
static float ContentViewTop() { return (ShowsChrome() ? kHeaderHeight : 0.0f) + 20.0f; }
static float LogicalHeight() {
    const float scale = g_scale > 0 ? g_scale : 1.0f;
    return (g_target ? g_target->GetSize().height : 900.0f) / scale;
}
static float ContentViewHeight() {
    return std::max(0.0f, LogicalHeight() - ContentViewTop() - 20.0f - (ShowsChrome() ? kFooterHeight : 0.0f));
}

// The WPF canvas uses the same four-column slots in all window modes.
static int CardSpan(const std::string& key) {
    auto shape = g_settings.cardShapes.find(key);
    return shape != g_settings.cardShapes.end() && shape->second == "long" ? 2 : 1;
}

static std::vector<layout::Card> ActiveCards() {
    std::vector<layout::Card> cards;
    const auto enabled = g_settings.enabledCards.empty() ? DefaultCardKeys() : g_settings.enabledCards;
    auto add = [&](const std::string& key) {
        if (!FindCard(key) || std::ranges::find(enabled, key) == enabled.end() ||
            std::ranges::any_of(cards, [&](const auto& card) { return card.key == key; })) return;
        cards.push_back({key, CardSpan(key)});
    };
    for (const auto& key : g_settings.cardOrder) add(key);
    for (const auto& key : enabled) add(key);
    return cards;
}

static D2D1_RECT_F ResizeGripBounds() {
    if (IsDesktopMode() && !g_panelAdjusting) return {};
    return D2D1::RectF(kLogicalWidth - 36, LogicalHeight() - 32, kLogicalWidth - 6, LogicalHeight() - 2);
}

static void BuildPlacements() {
    g_placements.clear();
    const auto cards = ActiveCards();
    const auto slots = layout::Pack(cards, g_settings.cardSlots);
    for (const auto& card : cards) {
        const auto [row, column] = slots.at(card.key);
        g_placements.push_back({FindCard(card.key), row, column, card.span,
            kContentLeft + column * kCardWidth, ContentViewTop() + row * kCellHeight,
            card.span * kCardWidth - 18.0f, kCellHeight - 16.0f});
    }
}

static float MaximumScroll() {
    float contentBottom = ContentViewTop();
    for (const auto& card : g_placements)
        contentBottom = std::max(contentBottom, card.y + card.h + 16.0f);
    if (g_editMode) {
        const float extraRow = g_settings.freePlacement
            ? ContentViewTop() + layout::kRows * kCellHeight : contentBottom + kCellHeight;
        contentBottom = std::max(contentBottom, extraRow);
    }
    return std::max(0.0f, contentBottom - ContentViewTop() - ContentViewHeight());
}

static D2D1_RECT_F InsightsBounds() {
    constexpr float left = kContentLeft + 1504.0f - 312.0f;
    if (!IsDesktopMode() || !g_settings.insightsRail || ContentViewHeight() <= 24.0f)
        return {};
    for (const auto& card : g_placements) {
        if (card.x + card.span * kCardWidth > left - 8.0f) return {};
    }
    const float top = ContentViewTop();
    return D2D1::RectF(left, top, left + 300.0f, top + ContentViewHeight() - 8.0f);
}

// ---------------------------------------------------------------- text helpers
static void DrawText(ID2D1RenderTarget* target, const std::wstring& text, IDWriteTextFormat* format,
                     D2D1_RECT_F box, ID2D1Brush* brush) {
    if (format && box.right > box.left && box.bottom > box.top)
        target->DrawTextW(text.c_str(), (UINT32)text.size(), format, box, brush, D2D1_DRAW_TEXT_OPTIONS_CLIP);
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

struct CardReading {
    std::wstring value;
    std::wstring unit;

    std::wstring Text() const {
        return unit.empty() ? value : value + L" " + unit;
    }
};

static bool IsNetworkCard(const CardDef& card) {
    const std::string_view key = card.key;
    return key == "netDown" || key == "netUp";
}

static CardReading FormatNetworkRate(double kibPerSecond) {
    if (!std::isfinite(kibPerSecond) || kibPerSecond < 0) return {L"—", L""};

    // The collector reports KiB/s. Convert to bytes before choosing decimal units.
    double rate = kibPerSecond * 1024.0;
    constexpr const wchar_t* units[] = {L"B/s", L"KB/s", L"MB/s", L"GB/s"};
    size_t unit = 0;
    while (rate >= 1000.0 && unit + 1 < std::size(units)) {
        rate /= 1000.0;
        ++unit;
    }
    wchar_t value[64]{};
    std::swprintf(value, std::size(value), unit == 0 ? L"%.0f" : L"%.1f", rate);
    return {value, units[unit]};
}

static CardReading ReadCard(const CardDef& card) {
    const auto it = g_snapshot.values.find(card.key);
    if (IsNetworkCard(card))
        return it == g_snapshot.values.end() ? CardReading{L"—", L""} : FormatNetworkRate(it->second);

    return {it == g_snapshot.values.end() ? L"—" : FormatNumber(it->second, card.temperature),
            metrics::Utf8ToWide(card.unit)};
}

static std::wstring FormatCardSample(const CardDef& card, double sample) {
    return IsNetworkCard(card) ? FormatNetworkRate(sample).Text() : FormatNumber(sample, false);
}

static void DrawReading(ID2D1RenderTarget* target, const CardReading& reading,
                        float left, float top, float right, ID2D1Brush* numberBrush, ID2D1Brush* unitBrush) {
    constexpr float gap = 8;
    const float valueWidth = std::ceil(MeasureTextWidth(reading.value, g_fmtValue)) + 2;
    const float unitWidth = std::ceil(MeasureTextWidth(reading.unit, g_fmtUnit)) + 2;
    const float width = valueWidth + (reading.unit.empty() ? 0 : gap + unitWidth);
    const float scale = std::clamp((right - left) / width, 0.0f, 1.0f);
    D2D1_MATRIX_3X2_F transform{};
    target->GetTransform(&transform);
    target->SetTransform(D2D1::Matrix3x2F::Scale(scale, 1.0f, D2D1::Point2F(left, top)) * transform);
    DrawText(target, reading.value, g_fmtValue, D2D1::RectF(left, top + 49, left + valueWidth, top + 110), numberBrush);
    if (!reading.unit.empty()) {
        const float unitLeft = left + valueWidth + gap;
        DrawText(target, reading.unit, g_fmtUnit,
                 D2D1::RectF(unitLeft, top + 78, unitLeft + unitWidth, top + 108), unitBrush);
    }
    target->SetTransform(transform);
}

static std::wstring CardDetail(const CardDef& card) {
    const std::string key = card.key;
    if (card.side == 'R' && !g_snapshot.remoteFresh) return T(L"数据离线", L"資料離線", L"No live data");
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
    if (key == "netDown") return T(L"上传 ", L"上傳 ", L"up ") + ReadCard(*FindCard("netUp")).Text();
    if (key == "netUp") return T(L"下载 ", L"下載 ", L"down ") + ReadCard(*FindCard("netDown")).Text();
    if (key == "diskPct") {
        const std::wstring summary = value("diskUsed") + L" / " + value("diskTotal") + L" GB";
        return g_snapshot.diskDetail.empty() ? summary : summary + L" · " + g_snapshot.diskDetail;
    }
    return {};
}

// ---------------------------------------------------------------- painting
static void DrawGlow(ID2D1RenderTarget* target, D2D1_ELLIPSE area, uint32_t color, float innerStop = 0.0f) {
    const D2D1_GRADIENT_STOP stops[] = {
        {innerStop, ToColorF(color)}, {1.0f, ToColorF(color & 0x00FFFFFFu)}};
    ID2D1GradientStopCollection* colors = nullptr;
    if (FAILED(target->CreateGradientStopCollection(stops, 2, &colors))) return;
    ID2D1RadialGradientBrush* brush = nullptr;
    const auto props = D2D1::RadialGradientBrushProperties(area.point, D2D1::Point2F(), area.radiusX, area.radiusY);
    if (SUCCEEDED(target->CreateRadialGradientBrush(props, colors, &brush))) {
        target->FillEllipse(area, brush);
        brush->Release();
    }
    colors->Release();
}

static void DrawAmbient(ID2D1RenderTarget* target, D2D1_SIZE_F size, const theme::Palette& palette) {
    DrawGlow(target, D2D1::Ellipse(D2D1::Point2F(size.width - 410, 130), 450, 250), palette.glowTop);
    DrawGlow(target, D2D1::Ellipse(D2D1::Point2F(365, size.height - 90), 425, 190), palette.glowBottom);
}

static void DrawCard(ID2D1RenderTarget* target, const Placement& placement, D2D1_RECT_F rect, const theme::Palette& palette) {
    const CardDef& card = *placement.card;
    const float radius = 20.0f;
    const D2D1_ROUNDED_RECT rounded = D2D1::RoundedRect(rect, radius, radius);

    if (!IsDesktopMode()) {
        const auto halo = D2D1::Ellipse(D2D1::Point2F((rect.left + rect.right) / 2, (rect.top + rect.bottom) / 2 + 4),
                                       (rect.right - rect.left) / 2 + 18, (rect.bottom - rect.top) / 2 + 17);
        DrawGlow(target, halo, WithAlpha(palette.shadow | 0xFF000000u, palette.shadowOpacity), 0.55f);
    }

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

    auto paintGradient = [&](const D2D1_GRADIENT_STOP* stops, UINT count, D2D1_RECT_F bounds, bool outline) {
        ID2D1GradientStopCollection* colors = nullptr;
        if (FAILED(target->CreateGradientStopCollection(stops, count, &colors))) return;
        ID2D1LinearGradientBrush* brush = nullptr;
        if (SUCCEEDED(target->CreateLinearGradientBrush(D2D1::LinearGradientBrushProperties(
                D2D1::Point2F(bounds.left, bounds.top), D2D1::Point2F(bounds.right, bounds.bottom)), colors, &brush))) {
            const auto shape = D2D1::RoundedRect(bounds, radius, radius);
            if (outline) target->DrawRoundedRectangle(shape, brush, 1.2f);
            else target->FillRoundedRectangle(shape, brush);
            brush->Release();
        }
        colors->Release();
    };
    const D2D1_GRADIENT_STOP rim[] = {
        {0.0f, ToColorF(palette.rim[0])}, {0.5f, ToColorF(palette.rim[1])}, {1.0f, ToColorF(palette.rim[2])}};
    const D2D1_GRADIENT_STOP gloss[] = {
        {0.0f, ToColorF(WithAlpha(palette.gloss, g_material.gloss / 0.45f))},
        {1.0f, ToColorF(palette.gloss & 0x00FFFFFF)}};
    paintGradient(gloss, 2, D2D1::RectF(rect.left + 1, rect.top + 1, rect.right - 1, rect.top + 58), false);
    paintGradient(rim, 3, rect, true);

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
    target->FillEllipse(D2D1::Ellipse(D2D1::Point2F(rect.left + 28, rect.top + 27), 4.0f, 4.0f), accent);
    DrawText(target, Tr(card), g_fmtTitle, D2D1::RectF(rect.left + 42, rect.top + 17, rect.right - 24, rect.top + 44), textBrush);

    const CardReading reading = ReadCard(card);
    const std::string key = card.key;
    const auto history = g_history.find(card.key);
    const bool hasHistory = history != g_history.end() && !history->second.empty() &&
                            (card.side != 'R' || g_snapshot.remoteFresh);
    double max = 0, min = 0;
    float statsLeft = rect.right - 18;
    std::wstring stats;
    if (hasHistory) {
        max = min = history->second.front();
        double sum = 0;
        for (double sample : history->second) {
            max = std::max(max, sample);
            min = std::min(min, sample);
            sum += sample;
        }
        const double mean = sum / history->second.size();
        stats = T(L"最大 ", L"最大 ", L"max ") + FormatCardSample(card, max) + L"\n" +
                T(L"最小 ", L"最小 ", L"min ") + FormatCardSample(card, min) + L"\n" +
                T(L"均值 ", L"均值 ", L"avg ") + FormatCardSample(card, mean);
        statsLeft -= std::ceil(MeasureTextWidth(stats, g_fmtStats)) + 2;
    }

    const auto temperature = g_snapshot.values.find(card.key);
    if (card.temperature && temperature != g_snapshot.values.end()) {
        if (temperature->second >= 80) textBrush->SetColor(ToColorF(palette.bad));
        else if (temperature->second >= 65) textBrush->SetColor(ToColorF(palette.warn));
    }
    DrawReading(target, reading, rect.left + 24, rect.top, statsLeft - 10, textBrush, secondary);
    textBrush->SetColor(ToColorF(palette.text));

    const auto barValue = card.bar ? g_snapshot.values.find(card.bar) : g_snapshot.values.end();
    const bool hasBar = barValue != g_snapshot.values.end() && g_snapshot.values.contains(key);
    if (hasBar) {
        const float left = rect.left + 24, right = rect.right - 24, top = rect.top + 127;
        secondary->SetColor(ToColorF(palette.track));
        target->FillRectangle(D2D1::RectF(left, top, right, top + 4), secondary);
        secondary->SetColor(ToColorF(palette.secondary));
        const float amount = float(std::clamp(barValue->second, 0.0, 100.0) / 100.0);
        target->FillRectangle(D2D1::RectF(left, top, left + (right - left) * amount, top + 4), accent);
    }

    if (hasHistory) {
        DrawText(target, stats, g_fmtStats,
                 D2D1::RectF(statsLeft, rect.top + 52, rect.right - 18, rect.top + 108), secondary);

        // Sparkline over the last samples.
        if (history->second.size() >= 3 && !hasBar && g_snapshot.values.contains(key)) {
            const float sparkLeft = rect.right - 194, sparkWidth = 170.0f, sparkTop = rect.top + 116, sparkHeight = 26.0f;
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

    DrawText(target, CardDetail(card), g_fmtCardSub,
             D2D1::RectF(rect.left + 24, rect.bottom - 39, rect.right - 24, rect.bottom - 13), secondary);
    if (g_editMode) {
        const auto button = D2D1::RectF(rect.right - 46, rect.top + 8, rect.right - 10, rect.top + 36);
        target->DrawRoundedRectangle(D2D1::RoundedRect(button, 8, 8), secondary);
        DrawText(target, L"↔", g_fmtButton,
                 D2D1::RectF(button.left + 10, button.top + 4, button.right, button.bottom), textBrush);
    }
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
        DrawText(target, T(L"实时监控", L"即時監控", L"SYSTEM / LIVE MONITOR"),
                 g_fmtEyebrow, D2D1::RectF(48, 18, 640, 38), local);
        DrawText(target, T(L"系统状态", L"系統狀態", L"System status"),
                 g_fmtHeader, D2D1::RectF(46, 36, 640, 82), text);
    }
    // Status pill and header buttons mirror StatusBorder / ThemeButton / HideButton.
    ID2D1SolidColorBrush* pill = nullptr;
    ID2D1SolidColorBrush* pillRim = nullptr;
    ID2D1SolidColorBrush* dot = nullptr;
    target->CreateSolidColorBrush(ToColorF(palette.pillBg), &pill);
    target->CreateSolidColorBrush(ToColorF(palette.pillBorder), &pillRim);
    target->CreateSolidColorBrush(ToColorF(g_snapshot.remoteFresh ? 0xFF6EE7ACu : 0xFFFF727Cu), &dot);
    const float right = size.width;
    const std::wstring status = g_statusText.empty() ? T(L"启动中", L"啟動中", L"starting") : g_statusText;
    const float statusRight = right - 158;
    const float statusWidth = std::clamp(MeasureTextWidth(status, g_fmtSmall) + 48.0f, 100.0f, 550.0f);
    const D2D1_RECT_F statusRect = D2D1::RectF(statusRight - statusWidth, 29, statusRight, 65);
    if (pill) target->FillRoundedRectangle(D2D1::RoundedRect(statusRect, 18, 18), pill);
    if (pillRim) target->DrawRoundedRectangle(D2D1::RoundedRect(statusRect, 18, 18), pillRim, 1.0f);
    if (dot) target->FillEllipse(D2D1::Ellipse(D2D1::Point2F(statusRect.left + 18, statusRect.top + 19), 4, 4), dot);
    DrawText(target, status, g_fmtSmall,
             D2D1::RectF(statusRect.left + 32, statusRect.top + 8, statusRect.right - 10, statusRect.bottom - 4), text ? text : secondary);

    g_themeRect = RECT{ (LONG)(right - 146), 28, (LONG)(right - 108), 66 };
    g_hideRect = RECT{ (LONG)(right - 86), 28, (LONG)(right - 48), 66 };
    auto headerButton = [&](RECT rect, const std::wstring& label) {
        const D2D1_RECT_F box = D2D1::RectF((float)rect.left, (float)rect.top, (float)rect.right, (float)rect.bottom);
        if (pill) target->FillRoundedRectangle(D2D1::RoundedRect(box, 11, 11), pill);
        if (pillRim) target->DrawRoundedRectangle(D2D1::RoundedRect(box, 11, 11), pillRim, 1.0f);
        DrawText(target, label, g_fmtIcon, D2D1::RectF(box.left + 11, box.top + 9, box.right, box.bottom), text ? text : secondary);
    };
    headerButton(g_themeRect, L"\uE708");
    headerButton(g_hideRect, L"\uE921");

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
        if (ShowsChrome()) DrawHeader(g_target, size, palette);
    }

    BuildPlacements();
    g_scrollOffset = std::min(g_scrollOffset, MaximumScroll());
    const float viewTop = ContentViewTop();
    const float viewBottom = viewTop + ContentViewHeight();

    g_target->PushAxisAlignedClip(D2D1::RectF(0, viewTop, kLogicalWidth, viewBottom), D2D1_ANTIALIAS_MODE_ALIASED);


    for (const auto& placement : g_placements) {
        const float top = placement.y - g_scrollOffset;
        if (g_cardMoved && g_dragCard == placement.card->key) continue;
        if (top + placement.h <= viewTop || top >= viewBottom) continue;
        DrawCard(g_target, placement, D2D1::RectF(placement.x, top, placement.x + placement.w, top + placement.h), palette);
    }
    if (g_cardMoved) {
        const auto it = std::ranges::find_if(g_placements, [](const auto& p) { return g_dragCard == p.card->key; });
        if (it != g_placements.end()) {
            const float x = kContentLeft + g_dragTarget.column * kCardWidth;
            const float y = viewTop + g_dragTarget.row * kCellHeight - g_scrollOffset;
            DrawCard(g_target, *it, D2D1::RectF(x, y, x + it->w, y + it->h), palette);
        }
    }
    if (IsDesktopMode()) DrawInsightsRail(g_target, palette);
    g_target->PopAxisAlignedClip();

    DrawEditToolbar(g_target, palette);
    const auto grip = ResizeGripBounds();
    ID2D1SolidColorBrush* gripBrush = nullptr;
    if (grip.right > grip.left && SUCCEEDED(g_target->CreateSolidColorBrush(ToColorF(palette.buttonBg), &gripBrush))) {
        g_target->FillRoundedRectangle(D2D1::RoundedRect(grip, 9, 9), gripBrush);
        gripBrush->SetColor(ToColorF(palette.secondary));
        DrawText(g_target, L"↘", g_fmtSmall,
            D2D1::RectF(grip.left + 8, grip.top + 3, grip.right, grip.bottom), gripBrush);
        gripBrush->Release();
    }

    if (ShowsChrome()) {
        ID2D1SolidColorBrush* muted = nullptr;
        if (SUCCEEDED(g_target->CreateSolidColorBrush(ToColorF(palette.muted), &muted)) && muted) {
            DrawText(g_target,
                     T(L"双击托盘图标 显示 / 隐藏　·　右键打开设置", L"按兩下系統匣圖示 顯示 / 隱藏　·　按右鍵開啟設定",
                       L"Double-click the tray icon to show/hide · right-click for settings"),
                     g_fmtSmall, D2D1::RectF(kContentLeft, size.height - 40, kLogicalWidth - kContentLeft, size.height - 12), muted);
            muted->Release();
        }
    }

    if (g_target->EndDraw() == D2DERR_RECREATE_TARGET) {
        g_target->Release();
        g_target = nullptr;
        InvalidateRect(g_hwnd, nullptr, FALSE);
    }
}

// ---------------------------------------------------------------- desktop mask
static const std::vector<RECT>& DesktopIconRects() {
    static std::vector<RECT> cached;
    static ULONGLONG refreshAfter = 0;
    const ULONGLONG now = GetTickCount64();
    if (now < refreshAfter) return cached;
    refreshAfter = now + 3000;

    HWND icons = nullptr;
    EnumWindows([](HWND window, LPARAM state) -> BOOL {
        HWND view = FindWindowExW(window, nullptr, L"SHELLDLL_DefView", nullptr);
        HWND list = view ? FindWindowExW(view, nullptr, L"SysListView32", nullptr) : nullptr;
        if (!list) return TRUE;
        *reinterpret_cast<HWND*>(state) = list;
        return FALSE;
    }, reinterpret_cast<LPARAM>(&icons));
    if (!icons) return cached;
    if (!IsWindowVisible(icons)) {
        cached.clear();
        return cached;
    }

    IUIAutomation* automation = nullptr;
    if (FAILED(CoCreateInstance(__uuidof(CUIAutomation), nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&automation))))
        return cached;
    IUIAutomationElement* list = nullptr;
    if (SUCCEEDED(automation->ElementFromHandle(icons, &list)) && list) {
        IUIAutomationCondition* any = nullptr;
        IUIAutomationElementArray* items = nullptr;
        if (SUCCEEDED(automation->CreateTrueCondition(&any)) &&
            SUCCEEDED(list->FindAll(TreeScope_Children, any, &items)) && items) {
            int count = 0;
            if (SUCCEEDED(items->get_Length(&count))) {
                std::vector<RECT> bounds;
                for (int i = 0; i < count && i < 512; ++i) {
                    IUIAutomationElement* item = nullptr;
                    if (FAILED(items->GetElement(i, &item)) || !item) continue;
                    RECT rect{};
                    if (SUCCEEDED(item->get_CurrentBoundingRectangle(&rect)) &&
                        rect.right > rect.left && rect.bottom > rect.top) bounds.push_back(rect);
                    item->Release();
                }
                cached = std::move(bounds);
            }
            items->Release();
        }
        if (any) any->Release();
        list->Release();
    }
    automation->Release();
    return cached;
}

static void ApplyRegion() {
    RECT window{};
    GetWindowRect(g_hwnd, &window);
    HRGN region = CreateRectRgn(0, 0, 0, 0);
    BuildPlacements();
    const int width = window.right - window.left, height = window.bottom - window.top;
    const float scale = g_scale > 0 ? g_scale : 1.0f;
    const int viewTop = int(ContentViewTop() * scale);
    const int viewBottom = std::min(height, int((ContentViewTop() + ContentViewHeight()) * scale));
    for (const auto& placement : g_placements) {
        int left = (int)(placement.x * scale);
        int top = (int)((placement.y - g_scrollOffset) * scale);
        int right = (int)((placement.x + placement.w) * scale);
        int bottom = (int)((placement.y - g_scrollOffset + placement.h) * scale);
        if (right <= left || bottom <= top) continue;
        if (bottom <= viewTop || top >= viewBottom) continue;
        HRGN piece = CreateRoundRectRgn(left, std::max(viewTop, top), right + 1, std::min(viewBottom, bottom) + 1,
                                       int(40 * scale), int(40 * scale));
        CombineRgn(region, region, piece, RGN_OR);
        DeleteObject(piece);
    }
    if (!IsDesktopMode() || g_editMode || g_panelAdjusting) {
        // A full region keeps capture and previews working across empty slots.
        HRGN whole = CreateRectRgn(0, 0, width, height);
        CombineRgn(region, region, whole, RGN_OR);
        DeleteObject(whole);
    } else {
        auto add = [&](D2D1_RECT_F bounds) {
            if (bounds.right <= bounds.left || bounds.bottom <= bounds.top) return;
            HRGN part = CreateRectRgn(int(bounds.left * scale), int(bounds.top * scale),
                                      int(bounds.right * scale), int(bounds.bottom * scale));
            CombineRgn(region, region, part, RGN_OR);
            DeleteObject(part);
        };
        add(InsightsBounds());
        add(ResizeGripBounds());
        for (const auto& icon : DesktopIconRects()) {
            HRGN hole = CreateRectRgn(icon.left - window.left, icon.top - window.top,
                                      icon.right - window.left, icon.bottom - window.top);
            CombineRgn(region, region, hole, RGN_DIFF);
            DeleteObject(hole);
        }
    }
    HRGN previous = CreateRectRgn(0, 0, 0, 0);
    const bool unchanged = GetWindowRgn(g_hwnd, previous) != ERROR && EqualRgn(previous, region);
    DeleteObject(previous);
    if (unchanged || !SetWindowRgn(g_hwnd, region, TRUE)) DeleteObject(region);
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
    make(15.0f, DWRITE_FONT_WEIGHT_NORMAL, &g_fmtTitle);
    make(44.0f, DWRITE_FONT_WEIGHT_SEMI_BOLD, &g_fmtValue);
    make(15.0f, DWRITE_FONT_WEIGHT_NORMAL, &g_fmtUnit);
    make(14.0f, DWRITE_FONT_WEIGHT_NORMAL, &g_fmtSmall);
    make(11.0f, DWRITE_FONT_WEIGHT_NORMAL, &g_fmtStats);
    make(16.0f, DWRITE_FONT_WEIGHT_NORMAL, &g_fmtDetail);
    make(14.0f, DWRITE_FONT_WEIGHT_NORMAL, &g_fmtCardSub);
    if (g_fmtCardSub) {
        IDWriteInlineObject* ellipsis = nullptr;
        const DWRITE_TRIMMING trim{DWRITE_TRIMMING_GRANULARITY_CHARACTER, 0, 0};
        if (SUCCEEDED(g_dwrite->CreateEllipsisTrimmingSign(g_fmtCardSub, &ellipsis))) {
            g_fmtCardSub->SetTrimming(&trim, ellipsis);
            ellipsis->Release();
        }
    }
    if (g_fmtStats) g_fmtStats->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_TRAILING);
    if (g_fmtDetail) g_fmtDetail->SetWordWrapping(DWRITE_WORD_WRAPPING_WRAP);
    make(30.0f, DWRITE_FONT_WEIGHT_SEMI_BOLD, &g_fmtHeader);
    make(12.0f, DWRITE_FONT_WEIGHT_SEMI_BOLD, &g_fmtEyebrow);
    make(13.0f, DWRITE_FONT_WEIGHT_NORMAL, &g_fmtButton);
    g_dwrite->CreateTextFormat(L"Segoe MDL2 Assets", nullptr, DWRITE_FONT_WEIGHT_NORMAL,
        DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, 15.0f, L"en-US", &g_fmtIcon);
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
    if (g_snapshot.remoteAgeSec >= 0 && g_snapshot.remoteFresh) {
        wchar_t buffer[128]{};
        std::swprintf(buffer, 128, T(L"DGX 在线 · %.0f 秒前", L"DGX 線上 · %.0f 秒前", L"DGX online · %.0f s ago").c_str(), g_snapshot.remoteAgeSec);
        g_statusText = buffer;
    } else if (!g_snapshot.remoteError.empty()) {
        g_statusText = T(L"DGX 连接失败 · ", L"DGX 連線失敗 · ", L"DGX connection failed · ") + g_snapshot.remoteError.substr(0, 90);
        const auto lineEnd = g_statusText.find_first_of(L"\r\n");
        if (lineEnd != std::wstring::npos) g_statusText.resize(lineEnd);
    } else {
        g_statusText = T(L"DGX 离线", L"DGX 離線", L"DGX offline");
    }
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

static void CloseDetail();
static void SetEditing(bool cards, bool panel);

static bool PanelIsShown() {
    return IsWindowVisible(g_hwnd) && !IsIconic(g_hwnd);
}

static void ShowPanel(bool visible) {
    if (!visible) {
        CloseDetail();
        if (g_editMode || g_panelAdjusting) SetEditing(false, false);
    }
    if (visible && IsIconic(g_hwnd)) ShowWindow(g_hwnd, SW_RESTORE);
    else ShowWindow(g_hwnd, visible ? SW_SHOWNOACTIVATE : SW_HIDE);
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
    CloseDetail();
    if (GetCapture() == g_hwnd) ReleaseCapture();
    g_editMode = false;
    g_panelAdjusting = false;
    g_settings.layerMode = mode;
    g_scrollOffset = 0;
    if (mode != "bottom") SetWindowRgn(g_hwnd, nullptr, TRUE);
    // Shared position: a layer switch keeps the panel where it is.
    RECT window{};
    GetWindowRect(g_hwnd, &window);
    if (persist) {
        g_settings.normalX = window.left; g_settings.normalY = window.top;
        g_settings.desktopX = window.left; g_settings.desktopY = window.top;
    }

    LONG_PTR ex = GetWindowLongPtrW(g_hwnd, GWL_EXSTYLE);
    if (mode == "bottom") ex |= WS_EX_NOACTIVATE; else ex &= ~WS_EX_NOACTIVATE;
    SetWindowLongPtrW(g_hwnd, GWL_EXSTYLE, ex);
    SetWindowPos(g_hwnd, mode == "top" ? HWND_TOPMOST : HWND_NOTOPMOST,
                 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    UpdateBackdrop();
    ApplyPlacement(false);
    if (persist) cfg::Save(g_settings);
}

static void SetEditing(bool cards, bool panel) {
    if (GetCapture() == g_hwnd) ReleaseCapture();
    const bool desktop = IsDesktopMode();
    const bool wasEditing = g_editMode || g_panelAdjusting;
    g_editMode = cards;
    g_panelAdjusting = desktop && panel;
    const bool editing = g_editMode || g_panelAdjusting;
    if (desktop && editing != wasEditing) {
        LONG_PTR style = GetWindowLongPtrW(g_hwnd, GWL_EXSTYLE);
        SetWindowLongPtrW(g_hwnd, GWL_EXSTYLE, editing ? style & ~WS_EX_NOACTIVATE : style | WS_EX_NOACTIVATE);
        SetWindowPos(g_hwnd, editing ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        if (editing) SetForegroundWindow(g_hwnd);
    }
    ApplyPlacement(true);
    InvalidateRect(g_hwnd, nullptr, FALSE);
}

static void StepScale(double delta) {
    if (IsDesktopMode()) {
        const double current = g_scale * 96.0 / GetDpiForWindow(g_hwnd);
        g_settings.desktopScale = std::min(2.0, std::max(0.4, current + delta));
    } else {
        double width = 1600.0 * g_scale * 96.0 / GetDpiForWindow(g_hwnd);
        width = std::clamp(width * (1.0 + delta), 600.0, 3840.0);
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

#include "detail.h"

#include "manager.h"
#include "remote.h"

static void AutoArrangeCards(bool groupByHost) {
    auto cards = ActiveCards();
    auto importance = [](std::string key) {
        std::ranges::transform(key, key.begin(), [](unsigned char c) { return char(std::tolower(c)); });
        auto contains = [&](const char* text) { return key.find(text) != std::string::npos; };
        if (contains("cpu") || contains("gpu") || contains("vrm") || contains("temp")) return 0;
        if (contains("mem") || contains("load")) return 1;
        if (contains("disk") || contains("nvme") || contains("net")) return 2;
        if (contains("fan") || contains("rpm") || contains("pump")) return 3;
        return 4;
    };
    std::ranges::sort(cards, [&](const auto& first, const auto& second) {
        auto key = [&](const auto& card) {
            const char side = FindCard(card.key)->side;
            const int group = groupByHost ? (side == 'L' ? 0 : (side == 'R' ? 1 : 2)) : 0;
            return std::tuple{group, importance(card.key), card.key};
        };
        return key(first) < key(second);
    });
    layout::Slots preferred;
    if (groupByHost) {
        int lanes[2]{};
        for (const auto& card : cards) {
            const bool remote = FindCard(card.key)->side == 'R';
            int& next = lanes[remote];
            if (next % 2 + card.span > 2) ++next;
            if (next / 2 < layout::kRows) preferred[card.key] = {next / 2, int(remote) * 2 + next % 2};
            next += card.span;
        }
    }
    g_settings.cardSlots = layout::Pack(cards, preferred);
    g_settings.cardOrder.clear();
    for (const auto& card : cards) g_settings.cardOrder.push_back(card.key);
    g_settings.customLayout = true;
    g_scrollOffset = 0;
    cfg::Save(g_settings);
}

static void ShowContextMenu(int x, int y, bool fromTray = false, const CardDef* card = nullptr) {
    CloseDetail();
    HMENU menu = CreatePopupMenu();
    if (card) {
        if (!g_editMode) AppendMenuW(menu, MF_STRING, 110, T(L"显示详情", L"顯示詳情", L"Show details").c_str());
        AppendMenuW(menu, MF_STRING, 111, (CardSpan(card->key) == 2
            ? T(L"切换为短卡", L"切換為短卡", L"Use short card")
            : T(L"切换为长卡", L"切換為長卡", L"Use long card")).c_str());
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    }
    if (fromTray) AppendMenuW(menu, MF_STRING, 602, T(L"显示 / 隐藏", L"顯示 / 隱藏", L"Show / hide").c_str());
    AppendMenuW(menu, MF_STRING | ((g_editMode || g_panelAdjusting) ? MF_CHECKED : 0), 100,
                (g_editMode || g_panelAdjusting) ? T(L"完成编辑", L"完成編輯", L"Done").c_str() : T(L"编辑布局", L"編輯佈局", L"Edit layout").c_str());
    AppendMenuW(menu, MF_STRING | (g_settings.freePlacement ? MF_CHECKED : 0), 112,
        T(L"自由放置", L"自由放置", L"Free placement").c_str());
    HMENU arrange = CreatePopupMenu();
    AppendMenuW(arrange, MF_STRING, 113, T(L"按主机整理", L"依主機整理", L"By host").c_str());
    AppendMenuW(arrange, MF_STRING, 114, T(L"按硬件重要性整理", L"依硬體重要性整理", L"By hardware priority").c_str());
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)arrange, T(L"自动整理", L"自動整理", L"Auto arrange").c_str());
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

    if (fromTray) SetForegroundWindow(g_hwnd);
    int command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, x, y, 0, g_hwnd, nullptr);
    if (fromTray) PostMessageW(g_hwnd, WM_NULL, 0, 0);
    DestroyMenu(menu);
    switch (command) {
    case 100:
        if (!PanelIsShown()) ShowPanel(true);
        if (g_editMode || g_panelAdjusting) SetEditing(false, false);
        else SetEditing(!IsDesktopMode(), IsDesktopMode());
        break;
    case 110: if (card) ShowDetail(*card, {x, y}); break;
    case 111: if (card) ToggleCardShape(*card); break;
    case 112: g_settings.freePlacement = !g_settings.freePlacement; cfg::Save(g_settings); break;
    case 113: AutoArrangeCards(true); break;
    case 114: AutoArrangeCards(false); break;
    case 700: case 701: case 702: case 703: {
        const char* presets[] = {"auto", "1080p", "2k", "4k"};
        g_settings.preset = presets[command - 700];
        if (IsDesktopMode()) g_settings.desktopScale = 0;
        else g_settings.normalWidthDip = g_settings.normalHeightDip = 0;
        ApplyPlacement(true);
        cfg::Save(g_settings);
        break;
    }
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
    case 602: ShowPanel(!PanelIsShown()); break;
    case 601: g_exitRequested = true; PostMessageW(g_hwnd, WM_CLOSE, 0, 0); break;
    default: break;
    }
    g_material = theme::GetMaterial(g_settings.material);
    InvalidateRect(g_hwnd, nullptr, FALSE);
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

    case WM_EXITSIZEMOVE: {
        RECT bounds{};
        GetWindowRect(hwnd, &bounds);
        g_settings.normalX = g_settings.desktopX = bounds.left;
        g_settings.normalY = g_settings.desktopY = bounds.top;
        cfg::Save(g_settings);
        return 0;
    }

    case WM_NCLBUTTONDBLCLK:
        return 0;   // never maximise this borderless panel

    case WM_SIZE:
        if (wParam == SIZE_MINIMIZED) return 0;
        if (LOWORD(lParam) > 0) g_scale = LOWORD(lParam) / kLogicalWidth;
        if (g_target) { g_target->Resize(D2D1::SizeU(LOWORD(lParam), HIWORD(lParam))); }
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;

    case WM_LBUTTONDOWN: {
        CloseDetail();
        int x = GET_X_LPARAM(lParam), y = GET_Y_LPARAM(lParam);
        RECT window{}; GetWindowRect(hwnd, &window);
        const auto grip = ResizeGripBounds();
        if (x >= grip.left * g_scale && x < grip.right * g_scale &&
            y >= grip.top * g_scale && y < grip.bottom * g_scale) {
            g_resizing = true;
            g_resizeChanged = false;
            g_dragOrigin = POINT{x + window.left, y + window.top};
            g_dragWindow = window;
            SetCapture(hwnd);
            return 0;
        }
        // Toolbar buttons use the same logical coordinates as DrawEditToolbar.
        if (g_editMode || g_panelAdjusting) {
            const float scale = g_scale > 0 ? g_scale : 1.0f;
            POINT logical{ (LONG)(x / scale), (LONG)(y / scale) };
            if (PtInRect(&g_doneRect, logical)) {
                SetEditing(false, false);
                cfg::Save(g_settings);
                InvalidateRect(hwnd, nullptr, FALSE);
                return 0;
            }
            if (PtInRect(&g_scaleDownRect, logical)) { StepScale(-0.05); return 0; }
            if (PtInRect(&g_scaleUpRect, logical)) { StepScale(0.05); return 0; }
            if (IsDesktopMode() && PtInRect(&g_modeRect, logical)) {
                SetEditing(!g_editMode, g_editMode);
                return 0;
            }
            if (IsDesktopMode() && PtInRect(&g_layerRect, logical)) {
                SetLayerMode(g_settings.layerMode == "top" ? "normal" : (g_settings.layerMode == "normal" ? "bottom" : "top"), true);
                InvalidateRect(hwnd, nullptr, FALSE);
                return 0;
            }
        }
        // Header buttons.
        const float headerScale = g_scale > 0 ? g_scale : 1.0f;
        POINT client{ (LONG)(x / headerScale), (LONG)(y / headerScale) };
        if (ShowsChrome()) {
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
        if (logicalY >= ContentViewTop() && logicalY < ContentViewTop() + ContentViewHeight())
        for (size_t i = 0; i < g_placements.size(); ++i) {
            const auto& placement = g_placements[i];
            float left = placement.x;
            float top = placement.y - g_scrollOffset;
            float cardWidth = placement.w;
            float cardHeight = placement.h;
            if (logicalX >= left && logicalX <= left + cardWidth && logicalY >= top && logicalY <= top + cardHeight) {
                if (g_editMode) {
                    const float right = left + cardWidth;
                    if (logicalX >= right - 46 && logicalX <= right - 10 &&
                        logicalY >= top + 8 && logicalY <= top + 36) {
                        ToggleCardShape(*placement.card);
                        return 0;
                    }
                    g_dragCard = placement.card->key;
                    g_dragStart = POINT{x, y};
                    g_dragCardOffset = POINT{LONG(x - left * hitScale), LONG(y - top * hitScale)};
                    g_dragTarget = cfg::Slot{placement.row, placement.column};
                    g_cardMoved = false;
                    SetCapture(hwnd);
                } else {
                    POINT anchor{x, y};
                    ClientToScreen(hwnd, &anchor);
                    ShowDetail(*placement.card, anchor);
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
        if (g_resizing) {
            POINT cursor{GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam)};
            ClientToScreen(hwnd, &cursor);
            const RECT work = WorkAreaAt({g_dragWindow.left, g_dragWindow.top});
            const int initialWidth = g_dragWindow.right - g_dragWindow.left;
            const int initialHeight = g_dragWindow.bottom - g_dragWindow.top;
            const int maxWidth = std::max(1L, work.right - g_dragWindow.left);
            const int maxHeight = std::max(1L, work.bottom - g_dragWindow.top);
            int width = std::clamp(initialWidth + int(cursor.x - g_dragOrigin.x), std::min(480, maxWidth), maxWidth);
            int height = std::clamp(initialHeight + int(cursor.y - g_dragOrigin.y), std::min(300, maxHeight), maxHeight);
            if (IsDesktopMode()) {
                const double w = initialWidth, h = initialHeight;
                const double projected = 1.0 + ((cursor.x - g_dragOrigin.x) * w + (cursor.y - g_dragOrigin.y) * h) / (w * w + h * h);
                const double maximum = std::min(maxWidth / w, maxHeight / h);
                const double ratio = std::clamp(projected, std::min(maximum, std::max(480.0 / w, 300.0 / h)), maximum);
                width = std::max(1, int(initialWidth * ratio));
                height = std::max(1, int(initialHeight * ratio));
            }
            if (SetWindowPos(hwnd, nullptr, 0, 0, width, height, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE))
                g_resizeChanged = width != initialWidth || height != initialHeight;
            return 0;
        }
        if (!g_dragCard.empty()) {
            const int x = GET_X_LPARAM(lParam), y = GET_Y_LPARAM(lParam);
            if (!g_cardMoved && std::abs(x - g_dragStart.x) < GetSystemMetrics(SM_CXDRAG) &&
                std::abs(y - g_dragStart.y) < GetSystemMetrics(SM_CYDRAG)) return 0;
            g_cardMoved = true;
            const int span = CardSpan(g_dragCard);
            const float left = (x - g_dragCardOffset.x) / g_scale - kContentLeft;
            const float top = (y - g_dragCardOffset.y) / g_scale - ContentViewTop() + g_scrollOffset;
            g_dragTarget = {std::clamp(int(std::lround(top / kCellHeight)), 0, layout::kRows - 1),
                            std::clamp(int(std::lround(left / kCardWidth)), 0, layout::kColumns - span)};
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
        if (g_resizing) {
            g_resizing = false;
            if (g_resizeChanged) {
                RECT bounds{};
                GetClientRect(hwnd, &bounds);
                const double dip = 96.0 / GetDpiForWindow(hwnd);
                if (IsDesktopMode()) g_settings.desktopScale = bounds.right * dip / kLogicalWidth;
                else {
                    g_settings.normalWidthDip = bounds.right * dip;
                    g_settings.normalHeightDip = bounds.bottom * dip;
                }
                cfg::Save(g_settings);
            }
            ReleaseCapture();
            return 0;
        }
        if (!g_dragCard.empty()) {
            if (g_cardMoved) {
                const auto cards = ActiveCards();
                auto slots = layout::Pack(cards, g_settings.cardSlots);
                const auto start = slots.find(g_dragCard);
                const bool changed = start == slots.end() || start->second.row != g_dragTarget.row ||
                    start->second.column != g_dragTarget.column;
                if (changed && layout::Move(slots, cards, {g_dragCard, CardSpan(g_dragCard)}, g_dragTarget,
                                            g_settings.freePlacement)) {
                    g_settings.cardSlots = std::move(slots);
                    g_settings.customLayout = true;
                    cfg::Save(g_settings);
                }
            }
            g_dragCard.clear();
            g_cardMoved = false;
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

    case WM_CAPTURECHANGED:
        if (g_resizing) {
            g_resizing = false;
            SetWindowPos(hwnd, nullptr, 0, 0, g_dragWindow.right - g_dragWindow.left,
                         g_dragWindow.bottom - g_dragWindow.top, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
        }
        g_dragCard.clear();
        g_cardMoved = false;
        g_dragging = false;
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;

    case WM_RBUTTONUP: {
        POINT point{ GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) };
        const float x = point.x / g_scale, y = point.y / g_scale;
        const CardDef* card = nullptr;
        if (y >= ContentViewTop() && y < ContentViewTop() + ContentViewHeight()) {
            for (const auto& p : g_placements) {
                const float top = p.y - g_scrollOffset;
                if (x >= p.x && x < p.x + p.w && y >= top && y < top + p.h) {
                    card = p.card;
                    break;
                }
            }
        }
        ClientToScreen(hwnd, &point);
        ShowContextMenu(point.x, point.y, false, card);
        return 0;
    }

    case WM_KEYDOWN:
        if (wParam == VK_ESCAPE) { CloseDetail(); SetEditing(false, false); }
        return 0;

    case WM_TIMER:
        if (wParam == g_timerId) { UpdateMetrics(); return 0; }
        return 0;

    case WM_APP + 1:   // tray callback
        if (LOWORD(lParam) == WM_LBUTTONDBLCLK) {
            ShowPanel(!PanelIsShown());
        } else if (LOWORD(lParam) == WM_RBUTTONUP) {
            POINT point{}; GetCursorPos(&point);
            ShowContextMenu(point.x, point.y, true);
        }
        return 0;

    case WM_MOUSEWHEEL: {
        BuildPlacements();
        const float maxScroll = MaximumScroll();
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
            if (g_target) {
                g_target->SetDpi(96.0f, 96.0f);
                g_target->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_CLEARTYPE);
            }
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

    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = WndProc;
    wc.hInstance = instance;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = L"SysMonGlassNative";
    wc.hbrBackground = nullptr;
    wc.hIcon = LoadIconW(instance, L"APPICON");
    if (!wc.hIcon) wc.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    wc.hIconSm = wc.hIcon;
    RegisterClassExW(&wc);

    RECT work{};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    POINT start{ (work.right - work.left - 1200) / 2, (work.bottom - work.top - 700) / 2 };
    g_hwnd = CreateWindowExW(WS_EX_APPWINDOW, wc.lpszClassName, L"系统状态 · Glass", WS_POPUP | WS_MINIMIZEBOX,
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
    for (IDWriteTextFormat* format : { g_fmtTitle, g_fmtValue, g_fmtUnit, g_fmtSmall, g_fmtStats, g_fmtDetail, g_fmtCardSub, g_fmtHeader, g_fmtEyebrow, g_fmtButton, g_fmtIcon })
        if (format) format->Release();
    if (g_dwrite) g_dwrite->Release();
    if (g_d2d) g_d2d->Release();
    CoUninitialize();
    return 0;
}
