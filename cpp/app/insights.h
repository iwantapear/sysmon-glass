// Insights rail: host summary, tracked-card statistics, process leaders and
// threshold transitions. Drawn in the desktop canvas' right-hand blank lane.
#pragma once

static void UpdateInsightsAlerts() {
    struct Rule { const char* key; double warn; double crit; };
    static const Rule rules[] = {
        { "cpu", 85, 95 }, { "gpuT", 80, 88 }, { "vrm", 80, 90 },
        { "dgxGpuT", 75, 85 }, { "dgxCpu", 75, 85 }, { "dgxNvme", 60, 70 }
    };
    for (const auto& rule : rules) {
        auto it = g_snapshot.values.find(rule.key);
        if (it == g_snapshot.values.end()) continue;
        const int level = it->second >= rule.crit ? 2 : (it->second >= rule.warn ? 1 : 0);
        const int previous = g_alertLevels.count(rule.key) ? g_alertLevels[rule.key] : 0;
        if (level != previous) {
            g_alertLevels[rule.key] = level;
            if (level != 0 || previous != 0) {
                InsightAlert alert{ rule.key, it->second, level };
                GetLocalTime(&alert.at);
                g_alerts.insert(g_alerts.begin(), alert);
                if (g_alerts.size() > 30) g_alerts.resize(30);
            }
        }
    }
}

static void DrawInsightsRail(ID2D1RenderTarget* target, const theme::Palette& palette) {
    const D2D1_RECT_F panel = InsightsBounds();
    if (panel.right <= panel.left) return;
    const float left = panel.left, top = panel.top, width = panel.right - panel.left;
    const float bottom = panel.bottom;
    ID2D1SolidColorBrush* face = nullptr;
    ID2D1SolidColorBrush* rim = nullptr;
    ID2D1SolidColorBrush* text = nullptr;
    ID2D1SolidColorBrush* secondary = nullptr;
    ID2D1SolidColorBrush* local = nullptr;
    target->CreateSolidColorBrush(ToColorF(WithAlpha(palette.card[0], 0.70f)), &face);
    target->CreateSolidColorBrush(ToColorF(palette.rim[1]), &rim);
    target->CreateSolidColorBrush(ToColorF(palette.text), &text);
    target->CreateSolidColorBrush(ToColorF(palette.secondary), &secondary);
    target->CreateSolidColorBrush(ToColorF(palette.local), &local);
    if (!face || !text || !secondary) return;
    target->FillRoundedRectangle(D2D1::RoundedRect(panel, 16, 16), face);
    if (rim) target->DrawRoundedRectangle(D2D1::RoundedRect(panel, 16, 16), rim, 1.2f);

    auto line = [&](float y, const std::wstring& value, ID2D1Brush* brush = nullptr) {
        DrawText(target, value, g_fmtSmall, D2D1::RectF(left + 18, y, left + width - 16, y + 26), brush ? brush : secondary);
    };
    auto heading = [&](float y, const std::wstring& value) {
        DrawText(target, value, g_fmtEyebrow, D2D1::RectF(left + 18, y, left + width - 16, y + 26), local ? local : text);
    };
    auto value = [&](const char* key) -> std::wstring {
        auto it = g_snapshot.values.find(key);
        return it == g_snapshot.values.end() ? L"—" : FormatNumber(it->second, false);
    };

    float y = top + 16;
    heading(y, T(L"主机 / HOST", L"主機 / HOST", L"HOST / HOST")); y += 30;
    line(y, L"CPU  Intel i9-13900KF + RTX 4070"); y += 25;
    const ULONGLONG hours = GetTickCount64() / 3600000ULL;
    wchar_t uptime[96];
    std::swprintf(uptime, 96, T(L"开机  %llu 小时", L"開機  %llu 小時", L"Uptime  %llu h").c_str(), hours);
    line(y, uptime); y += 25;
    line(y, T(L"内存 ", L"記憶體 ", L"Memory ") + value("memPct") + L"%   " + T(L"磁盘 ", L"磁碟 ", L"Disk ") + value("diskPct") + L"%"); y += 32;

    heading(y, T(L"卡片统计 / STATS", L"卡片統計 / STATS", L"CARD STATS / STATS")); y += 30;
    const CardDef* tracked = FindCard(g_trackedKey);
    if (tracked) {
        line(y, Tr(*tracked)); y += 25;
        auto history = g_history.find(g_trackedKey);
        if (history != g_history.end() && !history->second.empty()) {
            double high = history->second[0], low = history->second[0], sum = 0;
            for (double sample : history->second) { high = std::max(high, sample); low = std::min(low, sample); sum += sample; }
            const double mean = sum / history->second.size();
            line(y, T(L"当前 ", L"目前 ", L"Current ") + FormatCardSample(*tracked, history->second.back()) + L"   " + T(L"均值 ", L"均值 ", L"Mean ") + FormatCardSample(*tracked, mean)); y += 25;
            line(y, T(L"最小 ", L"最小 ", L"Min ") + FormatCardSample(*tracked, low) + L"   " + T(L"最大 ", L"最大 ", L"Max ") + FormatCardSample(*tracked, high)); y += 25;
            wchar_t samples[64];
            std::swprintf(samples, 64, T(L"样本 %zu 条", L"樣本 %zu 條", L"%zu samples").c_str(), history->second.size());
            line(y, samples); y += 28;
        }
    }

    heading(y, T(L"进程 / TOP", L"程序 / TOP", L"PROCESSES / TOP")); y += 28;
    line(y, L"CPU", local ? local : secondary); y += 22;
    for (const auto& process : g_snapshot.topCpu) {
        wchar_t row[96];
        std::swprintf(row, 96, L"%-18s %5.1f%%", process.name.substr(0, 18).c_str(), process.cpu);
        line(y, row); y += 21;
    }
    y += 8;
    line(y, T(L"内存", L"記憶體", L"Memory"), local ? local : secondary); y += 22;
    for (const auto& process : g_snapshot.topMem) {
        wchar_t row[96];
        std::swprintf(row, 96, L"%-18s %5.0f M", process.name.substr(0, 18).c_str(), process.memMiB);
        line(y, row); y += 21;
    }

    y += 12;
    heading(y, T(L"告警 / ALERTS", L"告警 / ALERTS", L"ALERTS / ALERTS")); y += 28;
    if (g_alerts.empty()) {
        line(y, T(L"全部指标正常", L"全部指標正常", L"All metrics normal")); y += 22;
    } else {
        for (const auto& alert : g_alerts) {
            const CardDef* card = FindCard(alert.key);
            wchar_t row[128];
            std::swprintf(row, 128, L"%s %02d:%02d %s %.0f", alert.level == 2 ? L"▲" : L"●",
                          alert.at.wHour, alert.at.wMinute, card ? Tr(*card).c_str() : metrics::Utf8ToWide(alert.key).c_str(), alert.value);
            ID2D1SolidColorBrush* alertBrush = nullptr;
            target->CreateSolidColorBrush(ToColorF(alert.level == 2 ? palette.bad : palette.warn), &alertBrush);
            line(y, row, alertBrush ? alertBrush : secondary);
            if (alertBrush) alertBrush->Release();
            y += 22;
            if (y > bottom - 24) break;
        }
    }
    face->Release();
    if (rim) rim->Release();
    text->Release();
    secondary->Release();
    if (local) local->Release();
}
