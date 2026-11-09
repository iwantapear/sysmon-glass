// Console verification of remote provisioning against the real DGX probe.
#include <cstdio>
#include "json.h"
#include "theme.h"
#include "config.h"
#include "metrics.h"

HWND g_hwnd = nullptr;
HINSTANCE g_instance = nullptr;
cfg::Settings g_settings;
metrics::Collector g_collector;
static std::wstring T(const std::wstring& zh, const std::wstring&, const std::wstring&) { return zh; }
#include "remote.h"

int main() {
    cfg::HostConfig host;
    host.sshHost = "dgx";
    host.probe = "~/.sysmon.sh";
    host.port = 22;
    std::printf("test connection:\n");
    const std::wstring result = TestRemote(host);
    std::printf("%s\n", metrics::WideToUtf8(result).c_str());
    std::printf("trust host key:\n");
    const std::wstring trusted = TrustHostKey(host);
    std::printf("%s\n", metrics::WideToUtf8(trusted).c_str());
    std::printf("deploy probe:\n");
    const std::wstring deployed = DeployProbe(host);
    std::printf("%s\n", metrics::WideToUtf8(deployed).c_str());
    return result.find(L"连接成功") == std::wstring::npos ? 1 : 0;
}
