// Remote host onboarding: IP/hostname configuration, host-key trust, probe
// deployment and connection testing. Uses the system OpenSSH client only.
#pragma once

static std::string Base64Encode(const std::string& input) {
    static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string output;
    for (size_t i = 0; i < input.size(); i += 3) {
        const unsigned a = (unsigned char)input[i];
        const unsigned b = i + 1 < input.size() ? (unsigned char)input[i + 1] : 0;
        const unsigned c = i + 2 < input.size() ? (unsigned char)input[i + 2] : 0;
        const unsigned triple = (a << 16) | (b << 8) | c;
        output.push_back(alphabet[(triple >> 18) & 63]);
        output.push_back(alphabet[(triple >> 12) & 63]);
        output.push_back(i + 1 < input.size() ? alphabet[(triple >> 6) & 63] : '=');
        output.push_back(i + 2 < input.size() ? alphabet[triple & 63] : '=');
    }
    return output;
}

static std::wstring RemoteSshPrefix(const cfg::HostConfig& host) {
    std::wstring ssh = L"ssh";
    const std::wstring systemSsh = L"C:\\Windows\\System32\\OpenSSH\\ssh.exe";
    if (GetFileAttributesW(systemSsh.c_str()) != INVALID_FILE_ATTRIBUTES) ssh = L"\"" + systemSsh + L"\"";
    const std::wstring target = host.user.empty() ? metrics::Utf8ToWide(host.sshHost) : metrics::Utf8ToWide(host.user + "@" + host.sshHost);
    return ssh + L" -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=yes "
        L"-o ClearAllForwardings=yes -o ForwardAgent=no -o ForwardX11=no -o RequestTTY=no "
        L"-o PermitLocalCommand=no -T -p " + std::to_wstring(host.port) + L" -- " + target;
}

static std::wstring RemoteProbeQuoted(const cfg::HostConfig& host) {
    const std::wstring probe = metrics::Utf8ToWide(host.probe.empty() ? "~/.sysmon.sh" : host.probe);
    if (probe.rfind(L"~/", 0) == 0) return L"$HOME'/" + probe.substr(2) + L"'";
    return L"'" + probe + L"'";
}

static std::string KnownHostsPath() {
    char home[MAX_PATH] = {};
    if (FAILED(SHGetFolderPathA(nullptr, CSIDL_PROFILE, nullptr, 0, home)) || !home[0]) return ".ssh\\known_hosts";
    return std::string(home) + "\\.ssh\\known_hosts";
}

static std::wstring TrustHostKey(const cfg::HostConfig& host) {
    const std::wstring command = L"ssh-keyscan -T 8 -p " + std::to_wstring(host.port) + L" " + metrics::Utf8ToWide(host.sshHost);
    const std::string output = metrics::RunCapture(command, 15000);
    std::vector<std::string> lines;
    size_t cursor = 0;
    while (cursor < output.size()) {
        const size_t end = output.find('\n', cursor);
        std::string line = output.substr(cursor, end == std::string::npos ? std::string::npos : end - cursor);
        while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) line.pop_back();
        if (!line.empty() && line.front() != '#') lines.push_back(line);
        if (end == std::string::npos) break;
        cursor = end + 1;
    }
    if (lines.empty()) return T(L"没有找到主机密钥。", L"沒有找到主機金鑰。", L"No host keys found.");
    const std::string path = KnownHostsPath();
    cfg::EnsureParent(path);
    std::vector<std::string> existing;
    FILE* read = std::fopen(path.c_str(), "rb");
    if (read) {
        char buffer[2048];
        while (std::fgets(buffer, sizeof(buffer), read)) {
            std::string line = buffer;
            while (!line.empty() && (line.back() == '\n' || line.back() == '\r')) line.pop_back();
            existing.push_back(line);
        }
        std::fclose(read);
    }
    int added = 0;
    for (const auto& line : lines) {
        if (std::find(existing.begin(), existing.end(), line) != existing.end()) continue;
        if (FILE* file = std::fopen(path.c_str(), "ab")) {
            std::fwrite(line.data(), 1, line.size(), file);
            std::fwrite("\n", 1, 1, file);
            std::fclose(file);
            ++added;
        }
    }
    wchar_t message[128];
    std::swprintf(message, 128, T(L"已信任：新增 %d 条，共 %zu 条。\n%s", L"已信任：新增 %d 條，共 %zu 條。\n%s", L"Trusted: %d new of %zu keys.\n%s").c_str(), added, lines.size(), metrics::Utf8ToWide(lines.front()).c_str());
    return message;
}

static std::wstring DeployProbe(const cfg::HostConfig& host) {
    const std::string probe =
        "#!/bin/sh\n"
        "g=$(nvidia-smi --query-gpu=temperature.gpu,power.draw,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')\n"
        "echo \"gpu=$g\"\n"
        "echo \"cpu=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1)\"\n"
        "echo \"fan=$(cat /sys/class/hwmon/hwmon0/fan1_input 2>/dev/null)\"\n"
        "for h in /sys/class/hwmon/hwmon*; do if [ \"$(cat \"$h/name\" 2>/dev/null)\" = \"nvme\" ]; then echo \"nvme=$(cat \"$h/temp1_input\" 2>/dev/null)\"; fi; done\n"
        "echo \"mem=$(free -m | awk '/^Mem:/{print $3\" \"$2}')\"\n"
        "echo \"load=$(awk '{print $1}' /proc/loadavg)\"\n"
        "echo \"up=$(awk '{print int($1/3600)}' /proc/uptime)\"\n";
    const std::string encoded = Base64Encode(probe);
    const std::wstring remote = L"printf %s " + metrics::Utf8ToWide(encoded) +
        L" | base64 -d > " + RemoteProbeQuoted(host) + L" && chmod 700 " + RemoteProbeQuoted(host) + L" && echo __DEPLOYED__";
    const std::string output = metrics::RunCapture(RemoteSshPrefix(host) + L" \"" + remote + L"\"", 25000);
    if (output.find("__DEPLOYED__") == std::string::npos)
        return T(L"部署失败：", L"部署失敗：", L"Deployment failed: ") + metrics::Utf8ToWide(output.substr(0, 320));
    return T(L"探针已部署，权限 700。", L"探針已部署，權限 700。", L"Probe deployed with mode 700.");
}

static std::wstring TestRemote(const cfg::HostConfig& host) {
    const std::wstring remote = L"sh " + RemoteProbeQuoted(host);
    const std::string output = metrics::RunCapture(RemoteSshPrefix(host) + L" \"" + remote + L"\"", 20000);
    if (output.find('=') == std::string::npos)
        return T(L"连接失败：", L"連線失敗：", L"Connection failed: ") + metrics::Utf8ToWide(output.substr(0, 320));
    return T(L"连接成功：\n", L"連線成功：\n", L"Connected:\n") + metrics::Utf8ToWide(output.substr(0, 900));
}

struct RemoteEditor {
    cfg::HostConfig host;
    HWND dialog = nullptr;
    HWND name = nullptr, address = nullptr, user = nullptr, port = nullptr, probe = nullptr, output = nullptr;
    bool accepted = false;
};

static LRESULT CALLBACK RemoteEditorProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    auto* editor = reinterpret_cast<RemoteEditor*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    switch (message) {
    case WM_CREATE: {
        editor = reinterpret_cast<RemoteEditor*>(((CREATESTRUCTW*)lParam)->lpCreateParams);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)editor);
        auto text = [&](const wchar_t* label, int y, HWND* field, const std::string& value) {
            CreateWindowExW(0, L"STATIC", label, WS_CHILD | WS_VISIBLE, 18, y + 4, 140, 22, hwnd, nullptr, g_instance, nullptr);
            *field = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", metrics::Utf8ToWide(value).c_str(),
                WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | WS_TABSTOP, 166, y, 420, 24, hwnd, nullptr, g_instance, nullptr);
        };
        text(L"显示名称", 18, &editor->name, editor->host.name);
        text(L"IP / 主机名", 52, &editor->address, editor->host.sshHost);
        text(L"SSH 用户（可空）", 86, &editor->user, editor->host.user);
        text(L"端口", 120, &editor->port, std::to_string(editor->host.port));
        text(L"探针路径", 154, &editor->probe, editor->host.probe);
        CreateWindowExW(0, L"STATIC", T(L"① 信任密钥 → ② 部署探针 → ③ 测试连接", L"① 信任金鑰 → ② 部署探針 → ③ 測試連線", L"Trust key, deploy probe, then test").c_str(),
            WS_CHILD | WS_VISIBLE, 18, 190, 560, 22, hwnd, nullptr, g_instance, nullptr);
        CreateWindowExW(0, L"BUTTON", T(L"① 信任主机密钥", L"① 信任主機金鑰", L"Trust host key").c_str(), WS_CHILD | WS_VISIBLE | WS_TABSTOP,
            18, 222, 136, 30, hwnd, (HMENU)1101, g_instance, nullptr);
        CreateWindowExW(0, L"BUTTON", T(L"② 部署探针", L"② 部署探針", L"Deploy probe").c_str(), WS_CHILD | WS_VISIBLE | WS_TABSTOP,
            162, 222, 120, 30, hwnd, (HMENU)1102, g_instance, nullptr);
        CreateWindowExW(0, L"BUTTON", T(L"③ 测试连接", L"③ 測試連線", L"Test connection").c_str(), WS_CHILD | WS_VISIBLE | WS_TABSTOP,
            290, 222, 120, 30, hwnd, (HMENU)1103, g_instance, nullptr);
        CreateWindowExW(0, L"BUTTON", T(L"保存并连接", L"儲存並連線", L"Save & connect").c_str(), WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON | WS_TABSTOP,
            432, 222, 154, 30, hwnd, (HMENU)IDOK, g_instance, nullptr);
        editor->output = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"", WS_CHILD | WS_VISIBLE | ES_MULTILINE | ES_READONLY | WS_VSCROLL,
            18, 264, 568, 130, hwnd, nullptr, g_instance, nullptr);
        CreateWindowExW(0, L"BUTTON", T(L"关闭", L"關閉", L"Close").c_str(), WS_CHILD | WS_VISIBLE | WS_TABSTOP,
            476, 406, 110, 30, hwnd, (HMENU)IDCANCEL, g_instance, nullptr);
        return 0;
    }
    case WM_COMMAND: {
        auto read = [](HWND field) {
            const int length = GetWindowTextLengthW(field);
            std::wstring value(size_t(length + 1), L'\0');
            GetWindowTextW(field, value.data(), length + 1);
            value.resize(size_t(length));
            return value;
        };
        auto capture = [&]() {
            const std::wstring nameText = read(editor->name);
            if (!nameText.empty()) editor->host.name = metrics::WideToUtf8(nameText);
            const std::wstring addressText = read(editor->address);
            editor->host.sshHost = metrics::WideToUtf8(addressText);
            editor->host.user = metrics::WideToUtf8(read(editor->user));
            editor->host.port = std::max(1, std::min(65535, _wtoi(read(editor->port).c_str())));
            const std::wstring probeText = read(editor->probe);
            editor->host.probe = probeText.empty() ? "~/.sysmon.sh" : metrics::WideToUtf8(probeText);
        };
        const int command = LOWORD(wParam);
        if (command == IDOK) {
            capture();
            if (editor->host.sshHost.empty()) {
                SetWindowTextW(editor->output, T(L"IP / 主机名不能为空。", L"IP / 主機名不能為空。", L"Address is required.").c_str());
                return 0;
            }
            editor->accepted = true;
            DestroyWindow(hwnd);
            return 0;
        }
        if (command == IDCANCEL || command == 2) { DestroyWindow(hwnd); return 0; }
        if (command >= 1101 && command <= 1103) {
            capture();
            std::wstring result;
            if (command == 1101) result = TrustHostKey(editor->host);
            else if (command == 1102) result = DeployProbe(editor->host);
            else result = TestRemote(editor->host);
            SetWindowTextW(editor->output, result.c_str());
            return 0;
        }
        break;
    }
    case WM_CLOSE:
        DestroyWindow(hwnd);
        return 0;
    }
    return DefWindowProcW(hwnd, message, wParam, lParam);
}

static bool ShowRemoteEditor(HWND owner) {
    static bool registered = false;
    if (!registered) {
        WNDCLASSEXW wc{};
        wc.cbSize = sizeof(wc);
        wc.lpfnWndProc = RemoteEditorProc;
        wc.hInstance = g_instance;
        wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
        wc.lpszClassName = L"SysMonRemoteEditor";
        RegisterClassExW(&wc);
        registered = true;
    }
    RemoteEditor editor;
    for (const auto& host : g_settings.hosts) if (host.id == g_settings.activeHostId) { editor.host = host; break; }
    HWND dialog = CreateWindowExW(WS_EX_DLGMODALFRAME, L"SysMonRemoteEditor", T(L"远程主机 · SSH 配置", L"遠端主機 · SSH 設定", L"Remote host · SSH").c_str(),
        WS_POPUP | WS_CAPTION | WS_SYSMENU, CW_USEDEFAULT, CW_USEDEFAULT, 620, 480,
        owner, nullptr, g_instance, &editor);
    if (!dialog) return false;
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
    if (editor.accepted) {
        bool found = false;
        for (auto& host : g_settings.hosts) {
            if (host.id == editor.host.id) { host = editor.host; found = true; break; }
        }
        if (!found) g_settings.hosts.push_back(editor.host);
        g_settings.activeHostId = editor.host.id;
        cfg::Save(g_settings);
        g_collector.StopRemote();
        g_collector.StartRemote(editor.host);
    }
    return editor.accepted;
}
