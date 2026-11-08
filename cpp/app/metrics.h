// Metric collection: local sensors + the remote SSH probe, producing the same
// value keys as modules/LocalIO.ps1 / Data.ps1 so cards can be identical.
#pragma once
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#ifndef WINVER
#define WINVER 0x0A00
#endif

#include "json.h"
#include "config.h"
#include <windows.h>
#include <iphlpapi.h>
#include <tlhelp32.h>
#include <psapi.h>
#include <string>
#include <map>
#include <vector>
#include <thread>
#include <mutex>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cmath>

#pragma comment(lib, "iphlpapi.lib")

namespace metrics {

using Values = std::map<std::string, double>;

struct ProcessInfo {
    std::wstring name;
    double cpu = 0;
    double memMiB = 0;
};
struct Snapshot {
    Values values;
    std::vector<ProcessInfo> topCpu;
    std::vector<ProcessInfo> topMem;
    bool gpuFresh = false;
    bool remoteFresh = false;
    double remoteAgeSec = -1;
};

// ---------------------------------------------------------------- helpers
inline std::string ReadFileText(const std::string& path) {
    FILE* file = std::fopen(path.c_str(), "rb");
    if (!file) return {};
    std::string text;
    char buffer[4096];
    while (size_t read = std::fread(buffer, 1, sizeof(buffer), file)) text.append(buffer, read);
    std::fclose(file);
    return text;
}

inline std::wstring Utf8ToWide(const std::string& text) {
    if (text.empty()) return {};
    int need = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), (int)text.size(), nullptr, 0);
    if (need <= 0) return {};
    std::wstring out(size_t(need), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, text.c_str(), (int)text.size(), out.data(), need);
    return out;
}

// Run a console program and capture its merged output, bounded in time and size.
inline std::string RunCapture(const std::wstring& commandLine, int timeoutMs = 8000) {
    SECURITY_ATTRIBUTES attributes{ sizeof(SECURITY_ATTRIBUTES), nullptr, TRUE };
    HANDLE readEnd = nullptr, writeEnd = nullptr;
    if (!CreatePipe(&readEnd, &writeEnd, &attributes, 0)) return {};
    SetHandleInformation(readEnd, HANDLE_FLAG_INHERIT, 0);

    STARTUPINFOW info{};
    info.cb = sizeof(info);
    info.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    info.wShowWindow = SW_HIDE;
    info.hStdOutput = writeEnd;
    info.hStdError = writeEnd;
    info.hStdInput = nullptr;
    PROCESS_INFORMATION process{};
    std::wstring command = commandLine;
    if (!CreateProcessW(nullptr, command.data(), nullptr, nullptr, TRUE,
                        CREATE_NO_WINDOW, nullptr, nullptr, &info, &process)) {
        CloseHandle(readEnd);
        CloseHandle(writeEnd);
        return {};
    }
    CloseHandle(writeEnd);

    std::string output;
    const auto started = std::chrono::steady_clock::now();
    char buffer[2048];
    for (;;) {
        DWORD available = 0;
        if (!PeekNamedPipe(readEnd, nullptr, 0, nullptr, &available, nullptr)) break;
        if (available > 0) {
            DWORD read = 0;
            if (!ReadFile(readEnd, buffer, sizeof(buffer) - 1, &read, nullptr) || read == 0) break;
            output.append(buffer, read);
            if (output.size() > 65536) break;
        } else if (WaitForSingleObject(process.hProcess, 20) == WAIT_OBJECT_0) {
            while (PeekNamedPipe(readEnd, nullptr, 0, nullptr, &available, nullptr) && available > 0) {
                DWORD read = 0;
                if (!ReadFile(readEnd, buffer, sizeof(buffer) - 1, &read, nullptr) || read == 0) break;
                output.append(buffer, read);
            }
            break;
        }
        const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - started).count();
        if (elapsed > timeoutMs) { TerminateProcess(process.hProcess, 1); break; }
    }
    CloseHandle(readEnd);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return output;
}

inline bool ParseNumber(const std::string& text, double& out) {
    if (text.empty()) return false;
    char* end = nullptr;
    const double value = std::strtod(text.c_str(), &end);
    if (end == text.c_str()) return false;
    out = value;
    return true;
}

// ---------------------------------------------------------------- collector
class Collector {
public:
    Snapshot Collect() {
        Snapshot snapshot;
        CollectFanState(snapshot.values);
        CollectGpu(snapshot);
        CollectNetwork(snapshot.values);
        CollectDisk(snapshot.values);
        CollectSystem(snapshot.values);
        CollectTopProcesses(snapshot);
        CopyRemote(snapshot);
        return snapshot;
    }

    void StartRemote(const cfg::HostConfig& host) {
        StopRemote();
        if (!host.enabled) return;
        running = true;
        worker = std::thread([this, host]() { RemoteLoop(host); });
    }
    void StopRemote() {
        running = false;
        if (worker.joinable()) worker.join();
    }

private:
    std::atomic<bool> running{ false };
    std::thread worker;
    std::mutex frameLock;
    Values frame;
    std::chrono::steady_clock::time_point frameAt{};
    bool haveFrame = false;
    ULONG64 lastIn = 0, lastOut = 0;
    std::chrono::steady_clock::time_point lastNetAt{};
    ULONGLONG lastIdle = 0, lastKernel = 0, lastUser = 0;
    double lastCpu = 0;

    static void Put(Values& values, const char* key, double value) { values[key] = value; }

    void CollectFanState(Values& values) {
        std::string path = "E:\\C++\\fan-tuning\\state.json";
        if (const char* override = std::getenv("SYSMON_FAN_STATE"); override && *override) path = override;
        const std::string text = ReadFileText(path);
        if (text.empty()) return;
        const js::Value root = js::Parse(text);
        if (!root.IsObject() || !root.Bool("running", false)) return;
        // Drop stale snapshots the same way Data.ps1 does (15 s window).
        const std::string stamp = root.Str("updatedAt");
        if (!stamp.empty()) {
            int year = 0, month = 0, day = 0, hour = 0, minute = 0;
            double second = 0;
            if (std::sscanf(stamp.c_str(), "%d-%d-%dT%d:%d:%lf", &year, &month, &day, &hour, &minute, &second) == 6) {
                SYSTEMTIME parsed{};
                parsed.wYear = (WORD)year; parsed.wMonth = (WORD)month; parsed.wDay = (WORD)day;
                parsed.wHour = (WORD)hour; parsed.wMinute = (WORD)minute; parsed.wSecond = (WORD)second;
                FILETIME fileTime{};
                if (SystemTimeToFileTime(&parsed, &fileTime)) {
                    ULARGE_INTEGER stampTicks{};
                    stampTicks.LowPart = fileTime.dwLowDateTime;
                    stampTicks.HighPart = fileTime.dwHighDateTime;
                    // updatedAt is local time; convert "now" the same way so the
                    // difference is meaningful (a UTC reading would be 8 h off here).
                    SYSTEMTIME localNow{};
                    GetLocalTime(&localNow);
                    FILETIME nowFile{};
                    SystemTimeToFileTime(&localNow, &nowFile);
                    ULARGE_INTEGER nowTicks{};
                    nowTicks.LowPart = nowFile.dwLowDateTime;
                    nowTicks.HighPart = nowFile.dwHighDateTime;
                    const double seconds = (double)(nowTicks.QuadPart - stampTicks.QuadPart) / 1e7;
                    if (seconds > 15.0 || seconds < -5.0) return;
                }
            }
        }
        if (root.Get("cpu")) Put(values, "cpu", root.Num("cpu"));
        if (root.Get("cpuPower")) Put(values, "cpuPwr", root.Num("cpuPower"));
        if (root.Get("vrm")) Put(values, "vrm", root.Num("vrm"));
        if (root.Get("pch")) Put(values, "pch", root.Num("pch"));
        if (root.Get("cpuDuty")) Put(values, "cpuDuty", root.Num("cpuDuty"));
        if (root.Get("cpuRpm")) Put(values, "cpuRpm", root.Num("cpuRpm"));
        if (root.Get("caseDuty")) Put(values, "caseDuty", root.Num("caseDuty"));
        if (root.Get("pumpRpm")) Put(values, "pumpRpm", root.Num("pumpRpm"));
        if (root.Get("pumpDuty")) Put(values, "pumpDuty", root.Num("pumpDuty"));
        if (auto* cases = root.Arr("caseRpm")) {
            double highest = 0;
            for (const auto& item : *cases) if (item.IsNumber() && item.number > highest) highest = item.number;
            if (highest > 0) Put(values, "caseRpm", highest);
        }
    }

    void CollectGpu(Snapshot& snapshot) {
        const std::string output = RunCapture(
            L"nvidia-smi --query-gpu=temperature.gpu,power.draw,utilization.gpu,memory.used,memory.total,fan.speed,clocks.current.graphics --format=csv,noheader,nounits",
            3000);
        if (output.empty()) return;
        const std::string line = output.substr(0, output.find('\n'));
        std::vector<std::string> fields;
        size_t start = 0;
        for (;;) {
            const size_t comma = line.find(',', start);
            std::string field = line.substr(start, comma == std::string::npos ? std::string::npos : comma - start);
            while (!field.empty() && field.front() == ' ') field.erase(field.begin());
            while (!field.empty() && (field.back() == ' ' || field.back() == '\r')) field.pop_back();
            fields.push_back(field);
            if (comma == std::string::npos) break;
            start = comma + 1;
        }
        double value = 0;
        if (fields.size() >= 1 && ParseNumber(fields[0], value)) { Put(snapshot.values, "gpuT", value); snapshot.gpuFresh = true; }
        if (fields.size() >= 2 && ParseNumber(fields[1], value)) Put(snapshot.values, "gpuPwr", value);
        if (fields.size() >= 3 && ParseNumber(fields[2], value)) Put(snapshot.values, "gpuUtil", value);
        if (fields.size() >= 4 && ParseNumber(fields[3], value)) { Put(snapshot.values, "gpuMemUsedMiB", value); Put(snapshot.values, "gpuMem", value / 1024.0); }
        if (fields.size() >= 5 && ParseNumber(fields[4], value)) { Put(snapshot.values, "gpuMemTotalMiB", value); Put(snapshot.values, "gpuMemTot", value / 1024.0); }
        if (fields.size() >= 6 && ParseNumber(fields[5], value)) Put(snapshot.values, "gpuFan", value);
        if (fields.size() >= 7 && ParseNumber(fields[6], value)) Put(snapshot.values, "gpuClock", value);
    }

    void CollectNetwork(Values& values) {
        DWORD size = 0;
        if (GetIfTable(nullptr, &size, FALSE) != ERROR_INSUFFICIENT_BUFFER || size == 0) return;
        std::vector<unsigned char> buffer(size);
        PMIB_IFTABLE table = reinterpret_cast<PMIB_IFTABLE>(buffer.data());
        if (GetIfTable(table, &size, FALSE) != NO_ERROR) return;
        ULONG64 in = 0, out = 0;
        for (DWORD i = 0; i < table->dwNumEntries; ++i) {
            const MIB_IFROW& row = table->table[i];
            if (row.dwType == IF_TYPE_SOFTWARE_LOOPBACK) continue;
            if (row.dwOperStatus != MIB_IF_OPER_STATUS_CONNECTED && row.dwOperStatus != MIB_IF_OPER_STATUS_OPERATIONAL) continue;
            in += row.dwInOctets;
            out += row.dwOutOctets;
        }
        const auto now = std::chrono::steady_clock::now();
        if (lastNetAt.time_since_epoch().count() != 0) {
            const double seconds = std::chrono::duration<double>(now - lastNetAt).count();
            if (seconds > 0.2) {
                const double down = (double)(in - lastIn) / seconds / 1024.0;
                const double up = (double)(out - lastOut) / seconds / 1024.0;
                if (down >= 0 && up >= 0) { Put(values, "netDown", down); Put(values, "netUp", up); }
            }
        }
        lastIn = in;
        lastOut = out;
        lastNetAt = now;
    }

    void CollectDisk(Values& values) {
        ULARGE_INTEGER freeBytes{}, totalBytes{}, totalFree{};
        if (!GetDiskFreeSpaceExA("C:\\", &freeBytes, &totalBytes, &totalFree)) return;
        if (totalBytes.QuadPart == 0) return;
        const double used = (double)(totalBytes.QuadPart - totalFree.QuadPart);
        Put(values, "diskPct", 100.0 * used / (double)totalBytes.QuadPart);
        Put(values, "diskUsed", used / 1073741824.0);
        Put(values, "diskTotal", (double)totalBytes.QuadPart / 1073741824.0);
    }

    void CollectSystem(Values& values) {
        MEMORYSTATUSEX status{};
        status.dwLength = sizeof(status);
        if (GlobalMemoryStatusEx(&status)) {
            Put(values, "memPct", (double)status.dwMemoryLoad);
            Put(values, "memUsed", (status.ullTotalPhys - status.ullAvailPhys) / 1073741824.0);
            Put(values, "memTotal", status.ullTotalPhys / 1073741824.0);
        }
        FILETIME idle{}, kernel{}, user{};
        if (GetSystemTimes(&idle, &kernel, &user)) {
            const ULONGLONG i = ((ULONGLONG)idle.dwHighDateTime << 32) | idle.dwLowDateTime;
            const ULONGLONG k = ((ULONGLONG)kernel.dwHighDateTime << 32) | kernel.dwLowDateTime;
            const ULONGLONG u = ((ULONGLONG)user.dwHighDateTime << 32) | user.dwLowDateTime;
            if (lastKernel || lastUser) {
                const double idleDelta = (double)(i - lastIdle);
                const double totalDelta = (double)((k - lastKernel) + (u - lastUser));
                if (totalDelta > 0) lastCpu = 100.0 * (1.0 - idleDelta / totalDelta);
            }
            lastIdle = i; lastKernel = k; lastUser = u;
        }
        Put(values, "cpuUtil", lastCpu);
        Put(values, "uptimeHours", (double)(GetTickCount64() / 3600000ULL));
    }

    void CollectTopProcesses(Snapshot& snapshot) {
        const auto now = std::chrono::steady_clock::now();
        struct PreviousSample { double milliseconds = 0; std::wstring name; };
        static std::map<DWORD, PreviousSample> previous;
        static std::chrono::steady_clock::time_point previousAt{};
        const double elapsed = std::chrono::duration<double>(now - previousAt).count();
        std::vector<ProcessInfo> rows;
        HANDLE snapshotHandle = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (snapshotHandle == INVALID_HANDLE_VALUE) return;
        PROCESSENTRY32W entry{};
        entry.dwSize = sizeof(entry);
        if (Process32FirstW(snapshotHandle, &entry)) {
            do {
                const DWORD pid = entry.th32ProcessID;
                const std::wstring name = entry.szExeFile;
                HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, FALSE, pid);
                if (!process) continue;
                PROCESS_MEMORY_COUNTERS memory{};
                FILETIME creation{}, exit{}, kernel{}, user{};
                if (GetProcessMemoryInfo(process, &memory, sizeof(memory)) && GetProcessTimes(process, &creation, &exit, &kernel, &user)) {
                    ProcessInfo info;
                    info.name = name;
                    info.memMiB = (double)memory.WorkingSetSize / 1048576.0;
                    const double cpuMs = (double)((((ULONGLONG)kernel.dwHighDateTime << 32) | kernel.dwLowDateTime) +
                                                  (((ULONGLONG)user.dwHighDateTime << 32) | user.dwLowDateTime)) / 10000.0;
                    if (elapsed > 0.5 && previous.count(pid)) {
                        info.cpu = std::max(0.0, (cpuMs - previous[pid].milliseconds) / (elapsed * 1000.0) * 100.0 / std::max(1, (int)std::thread::hardware_concurrency()));
                    }
                    previous[pid] = { cpuMs, name };
                    if (name != L"System Idle Process" && name != L"Registry" && name != L"Memory Compression") rows.push_back(info);
                }
                CloseHandle(process);
            } while (Process32NextW(snapshotHandle, &entry));
        }
        CloseHandle(snapshotHandle);
        previousAt = now;
        snapshot.topCpu = rows;
        std::sort(snapshot.topCpu.begin(), snapshot.topCpu.end(), [](const ProcessInfo& a, const ProcessInfo& b) { return a.cpu > b.cpu; });
        if (snapshot.topCpu.size() > 5) snapshot.topCpu.resize(5);
        snapshot.topMem = rows;
        std::sort(snapshot.topMem.begin(), snapshot.topMem.end(), [](const ProcessInfo& a, const ProcessInfo& b) { return a.memMiB > b.memMiB; });
        if (snapshot.topMem.size() > 5) snapshot.topMem.resize(5);
    }

    void CopyRemote(Snapshot& snapshot) {
        std::lock_guard<std::mutex> guard(frameLock);
        if (!haveFrame) return;
        const double age = std::chrono::duration<double>(std::chrono::steady_clock::now() - frameAt).count();
        snapshot.remoteAgeSec = age;
        snapshot.remoteFresh = age < 8.0;
        if (!snapshot.remoteFresh) return;
        for (const auto& [key, value] : frame) snapshot.values[key] = value;
    }

    // One sample per poll. A remote `while true` loop would block the reader until
    // its timeout and delay the first frame by many seconds.
    void RemoteLoop(cfg::HostConfig host) {
        const std::wstring target = host.user.empty() ? Utf8ToWide(host.sshHost) : Utf8ToWide(host.user + "@" + host.sshHost);
        const std::wstring probe = Utf8ToWide(host.probe);
        std::wstring quotedProbe;
        if (probe.rfind(L"~/", 0) == 0) quotedProbe = L"$HOME'/" + probe.substr(2) + L"'";
        else quotedProbe = L"'" + probe + L"'";
        const std::wstring remote = L"sh " + quotedProbe;

        // Prefer the OS OpenSSH: a GUI process has no HOME, and third-party builds
        // (Git/MSYS) then fail to locate the user's config and known_hosts.
        std::wstring ssh = L"ssh";
        const std::wstring systemSsh = L"C:\\Windows\\System32\\OpenSSH\\ssh.exe";
        if (GetFileAttributesW(systemSsh.c_str()) != INVALID_FILE_ATTRIBUTES)
            ssh = L"\"" + systemSsh + L"\"";
        const std::wstring commandLine =
            ssh + L" -o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=15 -o ServerAliveCountMax=2 "
            L"-o StrictHostKeyChecking=yes -o ClearAllForwardings=yes -o ForwardAgent=no -o ForwardX11=no "
            L"-o RequestTTY=no -o PermitLocalCommand=no -T -p " + std::to_wstring(host.port) +
            L" -- " + target + L" \"" + remote + L"\"";

        while (running) {
            const std::string output = RunCapture(commandLine, 8000);
            Values parsed;
            size_t cursor = 0;
            while (cursor < output.size()) {
                const size_t newline = output.find('\n', cursor);
                std::string entry = output.substr(cursor, newline == std::string::npos ? std::string::npos : newline - cursor);
                while (!entry.empty() && (entry.back() == '\r' || entry.back() == ' ')) entry.pop_back();
                const size_t equals = entry.find('=');
                if (equals != std::string::npos && equals > 0 && equals < 64) {
                    const std::string key = entry.substr(0, equals);
                    const std::string value = entry.substr(equals + 1);
                    double number = 0;
                    if (key == "gpu") {
                        std::vector<std::string> fields;
                        size_t from = 0;
                        for (;;) {
                            const size_t comma = value.find(',', from);
                            fields.push_back(value.substr(from, comma == std::string::npos ? std::string::npos : comma - from));
                            if (comma == std::string::npos) break;
                            from = comma + 1;
                        }
                        double temp = 0, power = 0, util = 0;
                        if (fields.size() >= 1 && ParseNumber(fields[0], temp)) parsed["dgxGpuT"] = temp;
                        if (fields.size() >= 2 && ParseNumber(fields[1], power)) parsed["dgxGpuPwr"] = power;
                        if (fields.size() >= 3 && ParseNumber(fields[2], util)) parsed["dgxGpuUtil"] = util;
                    } else if (key == "mem") {
                        double used = 0, total = 0;
                        if (std::sscanf(value.c_str(), "%lf %lf", &used, &total) == 2 && total > 0) {
                            parsed["dgxMem"] = used / 1024.0;
                            parsed["dgxMemTot"] = total / 1024.0;
                            parsed["dgxMemPct"] = 100.0 * used / total;
                        }
                    } else if (ParseNumber(value, number)) {
                        if (key == "cpu") parsed["dgxCpu"] = number / 1000.0;      // millidegrees
                        else if (key == "fan") parsed["dgxFan"] = number;
                        else if (key == "nvme") parsed["dgxNvme"] = number / 1000.0;
                        else if (key == "load") parsed["dgxLoad"] = number;
                        else if (key == "up") parsed["dgxUp"] = number;
                    }
                }
                if (newline == std::string::npos) break;
                cursor = newline + 1;
            }
            if (!parsed.empty()) {
                std::lock_guard<std::mutex> guard(frameLock);
                frame = parsed;
                frameAt = std::chrono::steady_clock::now();
                haveFrame = true;
            }
            if (!running) break;
            std::this_thread::sleep_for(std::chrono::milliseconds(1200));
        }
    }
};

} // namespace metrics
