// Card manager: one dialog for the complete default + optional catalog.
#pragma once

struct CardManagerState {
    cfg::Settings* settings = nullptr;
    std::vector<std::string> keys;
    std::vector<HWND> checks;
    HWND dialog = nullptr;
    bool accepted = false;
};

static LRESULT CALLBACK CardManagerProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    auto* state = reinterpret_cast<CardManagerState*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    switch (message) {
    case WM_CREATE: {
        state = reinterpret_cast<CardManagerState*>(((CREATESTRUCTW*)lParam)->lpCreateParams);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)state);
        const wchar_t* groups[] = { L"本机 / LOCAL", L"远程 / REMOTE", L"系统 / SYSTEM" };
        const char sides[] = { 'L', 'R', 'S' };
        int y = 14;
        for (int group = 0; group < 3; ++group) {
            CreateWindowExW(0, L"STATIC", groups[group], WS_CHILD | WS_VISIBLE,
                            18, y, 520, 24, hwnd, nullptr, g_instance, nullptr);
            y += 28;
            for (int i = 0; i < kCardCount; ++i) {
                if (kCards[i].side != sides[group]) continue;
                state->keys.push_back(kCards[i].key);
                HWND check = CreateWindowExW(0, L"BUTTON", Tr(kCards[i]).c_str(),
                    WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX | WS_TABSTOP,
                    24, y, 520, 24, hwnd, (HMENU)(INT_PTR)(1000 + (int)state->checks.size()), g_instance, nullptr);
                const bool enabled = state->settings->enabledCards.empty() ||
                    std::find(state->settings->enabledCards.begin(), state->settings->enabledCards.end(), kCards[i].key) != state->settings->enabledCards.end();
                SendMessageW(check, BM_SETCHECK, enabled ? BST_CHECKED : BST_UNCHECKED, 0);
                state->checks.push_back(check);
                y += 26;
            }
            if (group == 0) {
                for (int i = 0; i < kOptionalCount; ++i) {
                    state->keys.push_back(kOptionalCards[i].key);
                    HWND check = CreateWindowExW(0, L"BUTTON", Tr(kOptionalCards[i]).c_str(),
                        WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX | WS_TABSTOP,
                        24, y, 520, 24, hwnd, (HMENU)(INT_PTR)(1000 + (int)state->checks.size()), g_instance, nullptr);
                    const bool enabled = !state->settings->enabledCards.empty() &&
                        std::find(state->settings->enabledCards.begin(), state->settings->enabledCards.end(), kOptionalCards[i].key) != state->settings->enabledCards.end();
                    SendMessageW(check, BM_SETCHECK, enabled ? BST_CHECKED : BST_UNCHECKED, 0);
                    state->checks.push_back(check);
                    y += 26;
                }
            }
            if (group == 1) {
                for (int i = 0; i < kOptionalCount; ++i) {
                    if (kOptionalCards[i].side != 'R') continue;
                    state->keys.push_back(kOptionalCards[i].key);
                    HWND check = CreateWindowExW(0, L"BUTTON", Tr(kOptionalCards[i]).c_str(),
                        WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX | WS_TABSTOP,
                        24, y, 520, 24, hwnd, (HMENU)(INT_PTR)(1000 + (int)state->checks.size()), g_instance, nullptr);
                    const bool enabled = !state->settings->enabledCards.empty() &&
                        std::find(state->settings->enabledCards.begin(), state->settings->enabledCards.end(), kOptionalCards[i].key) != state->settings->enabledCards.end();
                    SendMessageW(check, BM_SETCHECK, enabled ? BST_CHECKED : BST_UNCHECKED, 0);
                    state->checks.push_back(check);
                    y += 26;
                }
            }
            y += 8;
        }
        wchar_t hint[64];
        std::swprintf(hint, 64, T(L"共 %zu 项，可滚动", L"共 %zu 項，可捲動", L"%zu items").c_str(), state->keys.size());
        CreateWindowExW(0, L"STATIC", hint, WS_CHILD | WS_VISIBLE, 18, y, 240, 24, hwnd, nullptr, g_instance, nullptr);
        CreateWindowExW(0, L"BUTTON", T(L"应用", L"套用", L"Apply").c_str(), WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON | WS_TABSTOP,
                        360, y - 2, 90, 30, hwnd, (HMENU)IDOK, g_instance, nullptr);
        CreateWindowExW(0, L"BUTTON", T(L"取消", L"取消", L"Cancel").c_str(), WS_CHILD | WS_VISIBLE | WS_TABSTOP,
                        458, y - 2, 90, 30, hwnd, (HMENU)IDCANCEL, g_instance, nullptr);
        return 0;
    }
    case WM_COMMAND:
        if (LOWORD(wParam) == IDOK) {
            std::vector<std::string> selected;
            for (size_t i = 0; i < state->checks.size(); ++i) {
                if (SendMessageW(state->checks[i], BM_GETCHECK, 0, 0) == BST_CHECKED) selected.push_back(state->keys[i]);
            }
            if (selected.empty()) selected = DefaultCardKeys();
            state->settings->enabledCards = selected;
            // Keep the user's ordering where possible and append newly enabled cards.
            std::vector<std::string> order;
            for (const auto& key : state->settings->cardOrder) {
                if (std::find(selected.begin(), selected.end(), key) != selected.end()) order.push_back(key);
            }
            for (const auto& key : selected) {
                if (std::find(order.begin(), order.end(), key) == order.end()) order.push_back(key);
            }
            state->settings->cardOrder = order;
            state->accepted = true;
            DestroyWindow(hwnd);
            return 0;
        }
        if (LOWORD(wParam) == IDCANCEL || LOWORD(wParam) == 2) { DestroyWindow(hwnd); return 0; }
        break;
    case WM_CLOSE:
        DestroyWindow(hwnd);
        return 0;
    }
    return DefWindowProcW(hwnd, message, wParam, lParam);
}

static bool ShowCardManager(HWND owner) {
    static bool registered = false;
    if (!registered) {
        WNDCLASSEXW wc{};
        wc.cbSize = sizeof(wc);
        wc.lpfnWndProc = CardManagerProc;
        wc.hInstance = g_instance;
        wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
        wc.lpszClassName = L"SysMonCardManager";
        RegisterClassExW(&wc);
        registered = true;
    }
    CardManagerState state;
    state.settings = &g_settings;
    HWND dialog = CreateWindowExW(WS_EX_DLGMODALFRAME, L"SysMonCardManager", T(L"卡片管理", L"卡片管理", L"Card manager").c_str(),
        WS_POPUP | WS_CAPTION | WS_SYSMENU, CW_USEDEFAULT, CW_USEDEFAULT, 580, 800,
        owner, nullptr, g_instance, &state);
    if (!dialog) return false;
    RECT work{};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    const int height = (int)std::min(820.0, std::max(420.0, (work.bottom - work.top) * 0.82));
    RECT window{ 0, 0, 580, height };
    AdjustWindowRectEx(&window, WS_POPUP | WS_CAPTION | WS_SYSMENU, FALSE, WS_EX_DLGMODALFRAME);
    const int x = work.left + ((work.right - work.left) - (window.right - window.left)) / 2;
    const int y = work.top + ((work.bottom - work.top) - (window.bottom - window.top)) / 2;
    SetWindowPos(dialog, nullptr, x, y, window.right - window.left, window.bottom - window.top, SWP_NOZORDER);
    // Make room for all catalog entries without clipping the System group.
    ShowWindow(dialog, SW_SHOW);
    EnableWindow(owner, FALSE);
    MSG message;
    while (IsWindow(dialog) && GetMessageW(&message, nullptr, 0, 0) > 0) {
        if (message.hwnd == dialog || IsChild(dialog, message.hwnd)) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
    EnableWindow(owner, TRUE);
    SetForegroundWindow(owner);
    if (state.accepted) {
        cfg::Save(g_settings);
        BuildPlacements();
        InvalidateRect(owner, nullptr, FALSE);
    }
    return state.accepted;
}
