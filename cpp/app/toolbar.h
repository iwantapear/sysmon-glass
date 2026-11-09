// Unified editing toolbar: card/panel mode switch, live scale, layer cycle, Done.
#pragma once

static void DrawEditToolbar(ID2D1RenderTarget* target, const theme::Palette& palette) {
    if (!g_editMode && !g_panelAdjusting) return;
    const bool desktop = IsDesktopMode();
    const float totalWidth = desktop ? 740.0f : 410.0f;
    const float left = (kLogicalWidth - totalWidth) / 2.0f;
    const float top = 8.0f, height = 42.0f;
    ID2D1SolidColorBrush* face = nullptr;
    ID2D1SolidColorBrush* rim = nullptr;
    ID2D1SolidColorBrush* text = nullptr;
    ID2D1SolidColorBrush* button = nullptr;
    target->CreateSolidColorBrush(ToColorF(WithAlpha(palette.card[0], 0.90f)), &face);
    target->CreateSolidColorBrush(ToColorF(palette.rim[1]), &rim);
    target->CreateSolidColorBrush(ToColorF(palette.text), &text);
    target->CreateSolidColorBrush(ToColorF(palette.buttonBg), &button);
    if (!face || !text) return;
    target->FillRoundedRectangle(D2D1::RoundedRect(D2D1::RectF(left, top, left + totalWidth, top + height), 16, 16), face);
    if (rim) target->DrawRoundedRectangle(D2D1::RoundedRect(D2D1::RectF(left, top, left + totalWidth, top + height), 16, 16), rim, 1.0f);

    auto drawButton = [&](RECT rect, const std::wstring& label) {
        D2D1_RECT_F box = D2D1::RectF((float)rect.left, (float)rect.top, (float)rect.right, (float)rect.bottom);
        if (button) target->FillRoundedRectangle(D2D1::RoundedRect(box, 10, 10), button);
        DrawText(target, label, g_fmtButton,
                 D2D1::RectF(box.left + 8, box.top + 4, box.right - 6, box.bottom - 2), text);
    };
    float x = left + 10;
    if (desktop) {
        g_modeRect = RECT{ (LONG)x, 13, (LONG)(x + 106), 45 };
        drawButton(g_modeRect, g_editMode ? T(L"面板调整", L"面板調整", L"Panel") : T(L"卡片编辑", L"卡片編輯", L"Cards"));
        x += 116;
    }
    g_scaleDownRect = RECT{ (LONG)x, 13, (LONG)(x + 38), 45 };
    drawButton(g_scaleDownRect, L"−"); x += 44;
    const double scale = desktop ? g_settings.desktopScale : (g_settings.normalWidthDip > 0 ? g_settings.normalWidthDip / 1600.0 : 1.0);
    wchar_t percent[32];
    if (desktop && scale <= 0.001) std::swprintf(percent, 32, L"auto");
    else std::swprintf(percent, 32, L"%d%%", (int)std::lround(scale * 100.0));
    DrawText(target, percent, g_fmtButton, D2D1::RectF(x, 17, x + 56, 43), text);
    x += 60;
    g_scaleUpRect = RECT{ (LONG)x, 13, (LONG)(x + 38), 45 };
    drawButton(g_scaleUpRect, L"+"); x += 46;
    if (desktop) {
        g_layerRect = RECT{ (LONG)x, 13, (LONG)(x + 66), 45 };
        drawButton(g_layerRect, g_settings.layerMode == "top" ? T(L"置顶", L"置頂", L"Top") : (g_settings.layerMode == "bottom" ? T(L"置底", L"置底", L"Bottom") : T(L"普通", L"普通", L"Normal")));
        x += 76;
    }
    g_doneRect = RECT{ (LONG)x, 13, (LONG)(x + 112), 45 };
    drawButton(g_doneRect, T(L"完成调整", L"完成調整", L"Done"));

    face->Release();
    if (rim) rim->Release();
    text->Release();
    if (button) button->Release();
}
