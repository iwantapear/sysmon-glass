#define WinMain SysMonApplicationMain
#include "app.cpp"
#undef WinMain
#include <set>

static int failures = 0;
static void Check(bool condition, const char* name) {
    std::printf("%s %s\n", condition ? "PASS" : "FAIL", name);
    if (!condition) ++failures;
}

int main() {
    g_instance = GetModuleHandleW(nullptr);
    WNDCLASSW klass{};
    klass.hInstance = g_instance;
    klass.lpfnWndProc = CardManagerProc;
    klass.lpszClassName = L"SysMonManagerRegression";
    RegisterClassW(&klass);
    cfg::Settings settings = cfg::Defaults();
    CardManagerState state;
    state.settings = &settings;
    HWND window = CreateWindowExW(0, klass.lpszClassName, L"Regression", WS_OVERLAPPEDWINDOW,
        0, 0, 580, 420, nullptr, nullptr, g_instance, &state);
    Check(window != nullptr, "native manager creates");
    Check(state.keys.size() == size_t(kCardCount + kOptionalCount), "catalog contains exactly 23 entries");
    Check(std::set<std::string>(state.keys.begin(), state.keys.end()).size() == state.keys.size(), "catalog keys unique");
    RECT client{}, apply{};
    GetClientRect(window, &client);
    GetWindowRect(GetDlgItem(window, IDOK), &apply);
    MapWindowPoints(nullptr, window, reinterpret_cast<POINT*>(&apply), 2);
    Check(apply.top >= 0 && apply.bottom <= client.bottom, "apply remains in short client area");
    HWND list = GetParent(state.checks.back());
    RECT before{}, after{};
    GetWindowRect(state.checks.back(), &before);
    SendMessageW(list, WM_VSCROLL, SB_BOTTOM, 0);
    GetWindowRect(state.checks.back(), &after);
    Check(after.top < before.top, "scroll reaches last catalog entry");
    RECT viewport{};
    GetClientRect(list, &viewport);
    MapWindowPoints(nullptr, list, reinterpret_cast<POINT*>(&after), 2);
    Check(after.top >= 0 && after.bottom <= viewport.bottom, "last catalog entry fully visible at bottom");
    DestroyWindow(window);
    std::printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
