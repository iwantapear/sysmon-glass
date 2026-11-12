#pragma once

static HWND g_detailWindow = nullptr;
static const CardDef* g_detailCard = nullptr;
static ULONGLONG g_detailOpened = 0;
static bool g_detailPointerInside = false;

static void CloseDetail() {
    if (g_detailWindow) DestroyWindow(g_detailWindow);
}

static void ToggleCardShape(const CardDef& card) {
    const int previous = CardSpan(card.key);
    const auto oldSlots = g_settings.cardSlots;
    g_settings.cardShapes[card.key] = previous == 2 ? "short" : "long";
    const auto cards = ActiveCards();
    auto slots = layout::Pack(cards, oldSlots);
    if (slots.size() != cards.size()) {
        g_settings.cardShapes[card.key] = previous == 2 ? "long" : "short";
        return;
    }
    g_settings.cardSlots = std::move(slots);
    cfg::Save(g_settings);
    InvalidateRect(g_hwnd, nullptr, FALSE);
}

static LRESULT CALLBACK DetailProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;
    case WM_ERASEBKGND:
        return 1;
    case WM_TIMER: {
        RECT bounds{};
        POINT cursor{};
        GetWindowRect(hwnd, &bounds);
        GetCursorPos(&cursor);
        const bool inside = PtInRect(&bounds, cursor);
        InflateRect(&bounds, 60, 60);
        if ((GetAsyncKeyState(VK_ESCAPE) & 0x8000) ||
            (!inside && ((GetAsyncKeyState(VK_LBUTTON) & 0x8000) ||
                         (GetAsyncKeyState(VK_RBUTTON) & 0x8000) ||
                         g_detailPointerInside ||
                         (GetTickCount64() - g_detailOpened >= 500 && !PtInRect(&bounds, cursor))))) {
            CloseDetail();
            return 0;
        }
        g_detailPointerInside = inside;
        return 0;
    }
    case WM_LBUTTONUP: {
        const float scale = GetDpiForWindow(hwnd) / 96.0f;
        const float x = GET_X_LPARAM(lParam) / scale, y = GET_Y_LPARAM(lParam) / scale;
        if (x >= 20 && x <= 180 && y >= 115 && y <= 146 && g_detailCard) {
            ToggleCardShape(*g_detailCard);
            CloseDetail();
        }
        return 0;
    }
    case WM_PAINT: {
        PAINTSTRUCT paint{};
        BeginPaint(hwnd, &paint);
        RECT client{};
        GetClientRect(hwnd, &client);
        ID2D1HwndRenderTarget* target = nullptr;
        const float dpi = float(GetDpiForWindow(hwnd));
        if (g_detailCard && SUCCEEDED(g_d2d->CreateHwndRenderTarget(
            D2D1::RenderTargetProperties(D2D1_RENDER_TARGET_TYPE_DEFAULT,
                D2D1::PixelFormat(), dpi, dpi),
            D2D1::HwndRenderTargetProperties(hwnd, D2D1::SizeU(client.right, client.bottom)), &target))) {
            const auto& card = *g_detailCard;
            const auto& palette = Pal();
            ID2D1SolidColorBrush* brush = nullptr;
            target->BeginDraw();
            target->Clear(ToColorF(palette.card[0] | 0xFF000000));
            if (SUCCEEDED(target->CreateSolidColorBrush(ToColorF(card.color), &brush))) {
                const auto size = target->GetSize();
                target->DrawRoundedRectangle(D2D1::RoundedRect(
                    D2D1::RectF(0.5f, 0.5f, size.width - 0.5f, size.height - 0.5f), 14, 14), brush);
                brush->SetColor(ToColorF(palette.text));
                DrawText(target, Tr(card), g_fmtTitle, D2D1::RectF(20, 14, size.width - 20, 37), brush);
                DrawText(target, FormatValueForCard(card) + L" " + FormatUnitForCard(card), g_fmtSmall,
                         D2D1::RectF(20, 39, size.width - 20, 62), brush);
                DrawText(target, CardDetail(card), g_fmtDetail,
                         D2D1::RectF(20, 65, size.width - 20, 111), brush);
                brush->SetColor(ToColorF(palette.buttonBg));
                target->FillRoundedRectangle(D2D1::RoundedRect(D2D1::RectF(20, 115, 180, 146), 9, 9), brush);
                brush->SetColor(ToColorF(palette.text));
                const auto label = CardSpan(card.key) == 2
                    ? T(L"切换为短卡", L"切換為短卡", L"Use short card")
                    : T(L"切换为长卡", L"切換為長卡", L"Use long card");
                DrawText(target, label, g_fmtButton, D2D1::RectF(30, 121, 174, 146), brush);
                brush->Release();
            }
            target->EndDraw();
            target->Release();
        }
        EndPaint(hwnd, &paint);
        return 0;
    }
    case WM_DESTROY:
        g_detailWindow = nullptr;
        g_detailCard = nullptr;
        return 0;
    }
    return DefWindowProcW(hwnd, message, wParam, lParam);
}

static void ShowDetail(const CardDef& card, POINT anchor) {
    CloseDetail();
    g_trackedKey = card.key;
    static const wchar_t className[] = L"SysMonGlassCardDetail";
    WNDCLASSW wc{};
    wc.lpfnWndProc = DetailProc;
    wc.hInstance = g_instance;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = className;
    RegisterClassW(&wc);

    const UINT dpi = GetDpiForWindow(g_hwnd);
    const int width = MulDiv(460, dpi, 96), height = MulDiv(158, dpi, 96);
    const RECT work = WorkAreaAt(anchor);
    anchor.x = std::clamp(anchor.x, work.left, std::max(work.left, work.right - width));
    anchor.y = std::clamp(anchor.y, work.top, std::max(work.top, work.bottom - height));
    g_detailCard = &card;
    g_detailWindow = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, className,
        T(L"卡片详情", L"卡片詳情", L"Card detail").c_str(), WS_POPUP,
        anchor.x, anchor.y, width, height, g_hwnd, nullptr, g_instance, nullptr);
    if (!g_detailWindow) {
        g_detailCard = nullptr;
        return;
    }
    HRGN region = CreateRoundRectRgn(0, 0, width + 1, height + 1, MulDiv(28, dpi, 96), MulDiv(28, dpi, 96));
    if (region && !SetWindowRgn(g_detailWindow, region, FALSE)) DeleteObject(region);
    g_detailOpened = GetTickCount64();
    g_detailPointerInside = false;
    SetTimer(g_detailWindow, 1, 75, nullptr);
    ShowWindow(g_detailWindow, SW_SHOWNOACTIVATE);
    InvalidateRect(g_hwnd, nullptr, FALSE);
}
