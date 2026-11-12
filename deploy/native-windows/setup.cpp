#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <string_view>
#include <vector>

namespace fs = std::filesystem;
namespace {
constexpr wchar_t kProduct[] = L"SysMon Glass C++ x64";
constexpr wchar_t kRunKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunName[] = L"SysMon.Glass";
constexpr wchar_t kApprovedKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run";

struct SetupError {
    std::wstring operation;
    DWORD code;
};

void Require(bool ok, const wchar_t* operation, DWORD code = ERROR_GEN_FAILURE) {
    if (!ok) throw SetupError{operation, code};
}

fs::path KnownFolder(REFKNOWNFOLDERID id) {
    PWSTR value = nullptr;
    const HRESULT hr = SHGetKnownFolderPath(id, KF_FLAG_CREATE, nullptr, &value);
    Require(SUCCEEDED(hr), L"Resolve Windows folder", hr);
    fs::path result(value);
    CoTaskMemFree(value);
    return result;
}

void ReplaceFile(const fs::path& from, const fs::path& to) {
    if (!MoveFileExW(from.c_str(), to.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
        throw SetupError{L"Replace " + to.wstring(), GetLastError()};
}

void InstallPayload(const fs::path& target) {
    const HMODULE self = GetModuleHandleW(nullptr);
    const HRSRC resource = FindResourceW(self, L"SYSMON_PAYLOAD", RT_RCDATA);
    Require(resource != nullptr, L"Find bundled SysMon executable", GetLastError());
    const DWORD size = SizeofResource(self, resource);
    const auto* bytes = static_cast<const char*>(LockResource(LoadResource(self, resource)));
    Require(bytes && size, L"Read bundled SysMon executable");
    auto temporary = target;
    temporary += L"." + std::to_wstring(GetCurrentProcessId()) + L".tmp";
    try {
        std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
        output.write(bytes, size);
        output.close();
        Require(output.good(), L"Write installed SysMon executable");
        ReplaceFile(temporary, target);
    } catch (...) {
        DeleteFileW(temporary.c_str());
        throw;
    }
}

struct Shortcut {
    IShellLinkW* link = nullptr;
    IPersistFile* file = nullptr;

    Shortcut() {
        HRESULT hr = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                      IID_PPV_ARGS(&link));
        Require(SUCCEEDED(hr), L"Create Windows shortcut", hr);
        hr = link->QueryInterface(IID_PPV_ARGS(&file));
        if (FAILED(hr)) {
            link->Release();
            throw SetupError{L"Open Windows shortcut interface", DWORD(hr)};
        }
    }
    Shortcut(const Shortcut&) = delete;
    Shortcut& operator=(const Shortcut&) = delete;
    ~Shortcut() { file->Release(); link->Release(); }
};

fs::path ShortcutTarget(Shortcut& shortcut, const fs::path& path) {
    HRESULT hr = shortcut.file->Load(path.c_str(), STGM_READ);
    wchar_t stored[32768]{};
    if (SUCCEEDED(hr)) hr = shortcut.link->GetPath(stored, int(std::size(stored)), nullptr, SLGP_RAWPATH);
    Require(SUCCEEDED(hr), L"Read Windows shortcut target", hr);
    return stored;
}

void CreateShortcut(const fs::path& path, const fs::path& target) {
    if (fs::exists(path)) {
        Shortcut previous;
        Require(_wcsicmp(ShortcutTarget(previous, path).c_str(), target.c_str()) == 0,
                L"A different desktop shortcut already uses the SysMon name", ERROR_ALREADY_EXISTS);
    }
    const auto temporary = path.parent_path() /
        (L".sysmon-" + std::to_wstring(GetCurrentProcessId()) + L".lnk");
    try {
        Shortcut shortcut;
        HRESULT hr = shortcut.link->SetPath(target.c_str());
        if (SUCCEEDED(hr)) hr = shortcut.link->SetWorkingDirectory(target.parent_path().c_str());
        if (SUCCEEDED(hr)) hr = shortcut.link->SetIconLocation(target.c_str(), 0);
        if (SUCCEEDED(hr)) hr = shortcut.link->SetDescription(kProduct);
        if (SUCCEEDED(hr)) hr = shortcut.file->Save(temporary.c_str(), TRUE);
        Require(SUCCEEDED(hr), L"Save SysMon shortcut", hr);
        Shortcut check;
        Require(_wcsicmp(ShortcutTarget(check, temporary).c_str(), target.c_str()) == 0,
                L"Verify SysMon shortcut");
        ReplaceFile(temporary, path);
    } catch (...) {
        DeleteFileW(temporary.c_str());
        throw;
    }
}

bool IsLegacyShortcut(const fs::path& path) {
    if (!fs::exists(path)) return false;
    Shortcut shortcut;
    const auto name = ShortcutTarget(shortcut, path).filename().wstring();
    if (_wcsicmp(name.c_str(), L"SysMon.Glass.exe") == 0) return true;
    if (_wcsicmp(name.c_str(), L"pwsh.exe") != 0 && _wcsicmp(name.c_str(), L"powershell.exe") != 0)
        return false;
    wchar_t arguments[32768]{};
    const HRESULT hr = shortcut.link->GetArguments(arguments, int(std::size(arguments)));
    Require(SUCCEEDED(hr), L"Read existing SysMon startup arguments", hr);
    const std::wstring command = L"powershell.exe " + std::wstring(arguments);
    int count = 0;
    LPWSTR* parsed = CommandLineToArgvW(command.c_str(), &count);
    Require(parsed != nullptr, L"Parse existing SysMon startup arguments", GetLastError());
    bool match = false;
    for (int index = 1; index + 1 < count; ++index) {
        if (_wcsicmp(parsed[index], L"-File") != 0) continue;
        const auto script = fs::path(parsed[index + 1]).filename().wstring();
        match = _wcsicmp(script.c_str(), L"glass.ps1") == 0 || _wcsicmp(script.c_str(), L"sysmon.ps1") == 0;
        break;
    }
    LocalFree(parsed);
    return match;
}

struct RegistryKey {
    HKEY handle = nullptr;
    ~RegistryKey() { if (handle) RegCloseKey(handle); }
};

void EnableStartup(const std::wstring& command) {
    RegistryKey approvals, run;
    LONG result = RegOpenKeyExW(HKEY_CURRENT_USER, kApprovedKey, 0, KEY_SET_VALUE, &approvals.handle);
    Require(result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND, L"Open SysMon startup approval", result);
    result = RegCreateKeyExW(HKEY_CURRENT_USER, kRunKey, 0, nullptr, 0, KEY_QUERY_VALUE | KEY_SET_VALUE,
                            nullptr, &run.handle, nullptr);
    Require(result == ERROR_SUCCESS, L"Open current-user startup settings", result);
    DWORD oldType = 0, oldSize = 0;
    result = RegQueryValueExW(run.handle, kRunName, nullptr, &oldType, nullptr, &oldSize);
    Require(result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND, L"Read previous SysMon startup", result);
    const bool hadPrevious = result == ERROR_SUCCESS;
    std::vector<BYTE> previous(oldSize);
    if (hadPrevious) {
        result = RegQueryValueExW(run.handle, kRunName, nullptr, &oldType, previous.data(), &oldSize);
        Require(result == ERROR_SUCCESS, L"Read previous SysMon startup command", result);
    }

    // The WPF and C++ builds share this value. Replace it instead of adding a second entry.
    const DWORD size = DWORD((command.size() + 1) * sizeof(wchar_t));
    result = RegSetValueExW(run.handle, kRunName, 0, REG_SZ, reinterpret_cast<const BYTE*>(command.c_str()), size);
    Require(result == ERROR_SUCCESS, L"Set current-user SysMon startup", result);
    try {
        std::wstring installed(command.size() + 1, L'\0');
        DWORD installedSize = size;
        result = RegGetValueW(run.handle, nullptr, kRunName, RRF_RT_REG_SZ, nullptr, installed.data(), &installedSize);
        Require(result == ERROR_SUCCESS && std::wstring_view(installed.c_str()) == command, L"Verify SysMon startup", result);
        if (approvals.handle) {
            result = RegDeleteValueW(approvals.handle, kRunName);
            Require(result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND, L"Reset previous SysMon startup approval", result);
        }
    } catch (...) {
        result = hadPrevious ? RegSetValueExW(run.handle, kRunName, 0, oldType, previous.data(), oldSize)
                             : RegDeleteValueW(run.handle, kRunName);
        Require(result == ERROR_SUCCESS || (!hadPrevious && result == ERROR_FILE_NOT_FOUND),
                L"Restore previous SysMon startup", result);
        throw;
    }
}

void Install(const fs::path& testRoot) {
    const bool testing = !testRoot.empty();
    const auto root = testing ? testRoot / L"Programs" / L"SysMon.Glass.Native"
                              : KnownFolder(FOLDERID_LocalAppData) / L"Programs" / L"SysMon.Glass.Native";
    const auto desktop = testing ? testRoot / L"Desktop" : KnownFolder(FOLDERID_Desktop);
    const auto startup = testing ? testRoot / L"Startup" : KnownFolder(FOLDERID_Startup);
    fs::create_directories(root);
    fs::create_directories(desktop);
    const auto target = root / L"sysmon.exe";
    InstallPayload(target);
    CreateShortcut(desktop / L"SysMon Glass (C++ x64).lnk", target);

    const auto legacy = startup / L"SysMon.lnk";
    const auto backup = root / (L"SysMon.legacy-" + std::to_wstring(GetCurrentProcessId()) + L".lnk");
    const bool migrate = IsLegacyShortcut(legacy);
    if (migrate) fs::rename(legacy, backup);
    try {
        const auto command = L"\"" + target.wstring() + L"\"";
        if (testing) {
            std::wofstream state(testRoot / L"Run.txt", std::ios::trunc);
            state << command;
            state.close();
            Require(state.good(), L"Write simulated startup entry");
        } else {
            EnableStartup(command);
        }
    } catch (...) {
        if (migrate) fs::rename(backup, legacy);
        throw;
    }
}
} // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    int count = 0;
    LPWSTR* args = CommandLineToArgvW(GetCommandLineW(), &count);
    fs::path testRoot;
    if (args && count == 3 && std::wstring_view(args[1]) == L"--test-dir") testRoot = args[2];
    if (args) LocalFree(args);
    if (count != 1 && testRoot.empty()) return 2;

    const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    int result = 1;
    try {
        Require(SUCCEEDED(initialized), L"Initialize Windows installer", initialized);
        Install(testRoot.empty() ? testRoot : fs::absolute(testRoot));
        if (testRoot.empty())
            MessageBoxW(nullptr, L"SysMon Glass C++ x64 已安装。\n\n已创建桌面快捷方式，并启用当前用户登录自启。", kProduct, MB_OK | MB_ICONINFORMATION);
        result = 0;
    } catch (const SetupError& error) {
        if (testRoot.empty())
            MessageBoxW(nullptr, (error.operation + L"\nWindows error: " + std::to_wstring(error.code)).c_str(), kProduct, MB_OK | MB_ICONERROR);
    } catch (const fs::filesystem_error& error) {
        if (testRoot.empty())
            MessageBoxW(nullptr, (L"无法安装 SysMon Glass。\n" + error.path1().wstring() + L"\nWindows error: " +
                                 std::to_wstring(error.code().value())).c_str(), kProduct, MB_OK | MB_ICONERROR);
    }
    if (SUCCEEDED(initialized)) CoUninitialize();
    return result;
}
