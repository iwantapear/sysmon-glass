// Console probe: exercises the same config/metrics code the GUI uses, so failures
// are visible as plain stdout instead of a silent GUI.
#include <cstdio>
#include <string>
#include "json.h"
#include "config.h"
#include "metrics.h"

int main() {
    cfg::Settings settings = cfg::Load();
    std::printf("config path: %s\n", cfg::ConfigPath().c_str());
    std::printf("hosts=%zu active=%s\n", settings.hosts.size(), settings.activeHostId.c_str());
    for (const auto& host : settings.hosts) {
        std::printf("  host id=%s name=%s sshHost=%s user=%s port=%d probe=%s enabled=%d\n",
                    host.id.c_str(), host.name.c_str(), host.sshHost.c_str(), host.user.c_str(),
                    host.port, host.probe.c_str(), host.enabled ? 1 : 0);
    }
    std::printf("theme=%s material=%s language=%s interval=%d layer=%s\n",
                settings.theme.c_str(), settings.material.c_str(), settings.language.c_str(),
                settings.interval, settings.layerMode.c_str());

    if (settings.hosts.empty()) { std::printf("NO HOSTS -> remote polling would never start\n"); return 2; }
    const cfg::HostConfig host = settings.hosts.front();

    metrics::Collector collector;
    metrics::Snapshot snapshot = collector.Collect();
    std::printf("local values=%zu gpuFresh=%d\n", snapshot.values.size(), snapshot.gpuFresh ? 1 : 0);
    for (const auto& [key, value] : snapshot.values) std::printf("  %s=%.2f\n", key.c_str(), value);

    std::printf("starting remote poller for %s ...\n", host.id.c_str());
    collector.StartRemote(host);
    for (int i = 0; i < 12; ++i) {
        Sleep(1000);
        snapshot = collector.Collect();
        std::printf("t=%ds remoteFresh=%d age=%.1f\n", i + 1, snapshot.remoteFresh ? 1 : 0, snapshot.remoteAgeSec);
        if (snapshot.remoteFresh) {
            for (const auto& [key, value] : snapshot.values) {
                if (key.rfind("dgx", 0) == 0) std::printf("  %s=%.2f\n", key.c_str(), value);
            }
            break;
        }
    }
    collector.StopRemote();
    return 0;
}
