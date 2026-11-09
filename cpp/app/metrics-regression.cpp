#include "json.h"
#include "config.h"
#include <iphlpapi.h>
#include <netioapi.h>
#include <tlhelp32.h>
#include <psapi.h>
#include <thread>
#include <mutex>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <cctype>

static std::vector<MIB_IF_ROW2> adapters;
static DWORD WINAPI FakeGetIfTable(PMIB_IFTABLE table, PULONG size, BOOL) {
    const ULONG needed = sizeof(MIB_IFTABLE) + ULONG(adapters.size()) * sizeof(MIB_IFROW);
    if (!table || *size < needed) { *size = needed; return ERROR_INSUFFICIENT_BUFFER; }
    table->dwNumEntries = DWORD(adapters.size());
    for (size_t i = 0; i < adapters.size(); ++i) {
        auto& row = table->table[i]; row = {};
        row.dwIndex = adapters[i].InterfaceIndex;
        row.dwType = IF_TYPE_ETHERNET_CSMACD;
        row.dwOperStatus = MIB_IF_OPER_STATUS_OPERATIONAL;
        row.dwInOctets = DWORD(adapters[i].InOctets); row.dwOutOctets = DWORD(adapters[i].OutOctets);
    }
    return NO_ERROR;
}
static NETIO_STATUS WINAPI FakeGetIfTable2(PMIB_IF_TABLE2* table) {
    *table = static_cast<PMIB_IF_TABLE2>(std::calloc(1, sizeof(MIB_IF_TABLE2) + adapters.size() * sizeof(MIB_IF_ROW2)));
    (*table)->NumEntries = ULONG(adapters.size());
    for (size_t i = 0; i < adapters.size(); ++i) (*table)->Table[i] = adapters[i];
    return NO_ERROR;
}
static void WINAPI FakeFreeMibTable(PVOID table) { std::free(table); }
#define GetIfTable FakeGetIfTable
#define GetIfTable2 FakeGetIfTable2
#define FreeMibTable FakeFreeMibTable
#define private public
#include "metrics.h"
#undef private
#undef GetIfTable
#undef GetIfTable2
#undef FreeMibTable

static int failures = 0;
static void Check(bool good, const char* message) {
    std::printf("%s %s\n", good ? "PASS" : "FAIL", message);
    if (!good) ++failures;
}
static MIB_IF_ROW2 Adapter(ULONG id, ULONG64 input, ULONG64 output) {
    MIB_IF_ROW2 row{};
    row.InterfaceIndex = id; row.InterfaceLuid.Value = id;
    row.Type = IF_TYPE_ETHERNET_CSMACD; row.OperStatus = IfOperStatusUp;
    row.InOctets = input; row.OutOctets = output;
    return row;
}
static metrics::Values NextNetwork(metrics::Collector& collector) {
    collector.lastNetAt = std::chrono::steady_clock::now() - std::chrono::seconds(2);
    metrics::Values values; collector.CollectNetwork(values); return values;
}
static void CheckChildStopped(const std::string& output, const char* label) {
    const DWORD pid = std::strtoul(output.c_str(), nullptr, 10);
    HANDLE process = OpenProcess(SYNCHRONIZE | PROCESS_TERMINATE, FALSE, pid);
    const bool stopped = pid != 0 && (!process || WaitForSingleObject(process, 0) == WAIT_OBJECT_0);
    Check(stopped, label);
    if (process) {
        if (!stopped) { TerminateProcess(process, 1); WaitForSingleObject(process, 5000); }
        CloseHandle(process);
    }
}
int main(int argc, char** argv) {
    if (argc > 1) {
        std::printf("%lu\n", GetCurrentProcessId()); std::fflush(stdout);
        if (std::string(argv[1]) == "--flood") {
            const std::string flood(100000, 'x');
            std::fwrite(flood.data(), 1, flood.size(), stdout); std::fflush(stdout);
        }
        Sleep(10000); return 0;
    }
    double number = 7;
    Check(metrics::ParseNumber(" 12.5 \r\n", number) && number == 12.5, "finite sensor number with whitespace");
    for (const char* input : {"nan", "inf", "1e999", "12garbage"})
        Check(!metrics::ParseNumber(input, number), input);
    Check(!metrics::ParseNumber(std::string("12\0junk", 7), number), "embedded NUL rejected");

    metrics::Collector collector;
    adapters = {Adapter(1, 4294967200ULL, 400)};
    metrics::Values first; collector.CollectNetwork(first);
    Check(first.empty(), "first network sample has no rate");
    adapters = {Adapter(1, 4294968224ULL, 2448)};
    auto values = NextNetwork(collector);
    Check(values.count("netDown") && std::fabs(values["netDown"] - 0.5) < 0.01, "64-bit counter crosses 4 GiB without false spike");
    adapters = {Adapter(1, 10, 10)};
    values = NextNetwork(collector);
    Check(!values.count("netDown") || values["netDown"] == 0, "counter reset does not underflow");
    adapters = {Adapter(1, 1034, 1034), Adapter(2, 9000000000ULL, 9000000000ULL)};
    values = NextNetwork(collector);
    Check(values.count("netDown") && std::fabs(values["netDown"] - 0.5) < 0.01, "new adapter lifetime bytes excluded");
    adapters = {Adapter(1, 2058, 2058)};
    values = NextNetwork(collector);
    Check(values.count("netDown") && std::fabs(values["netDown"] - 0.5) < 0.01, "removed adapter does not underflow aggregate");

    collector.frame = {{"dgxCpu", 55}}; collector.haveFrame = true;
    collector.frameAt = std::chrono::steady_clock::now(); collector.lastRemoteError = "old host error";
    cfg::HostConfig disabled; disabled.enabled = false; collector.StartRemote(disabled);
    metrics::Snapshot snapshot; collector.CopyRemote(snapshot);
    Check(!snapshot.remoteFresh && snapshot.values.empty() && snapshot.remoteError.empty(), "disabled or replaced remote clears old host frame and error");

    wchar_t exe[32768]{}; GetModuleFileNameW(nullptr, exe, 32768);
    const std::wstring command = L"\"" + std::wstring(exe) + L"\"";
    auto output = metrics::RunCapture(command + L" --flood", 2000);
    Check(output.size() <= 65536, "capture output stays within 64 KiB");
    CheckChildStopped(output, "output limit reaps child before returning");
    output = metrics::RunCapture(command + L" --sleep", 100);
    CheckChildStopped(output, "timeout reaps child before returning");
    std::printf("metrics regressions: %d failure(s)\n", failures);
    return failures ? 1 : 0;
}
