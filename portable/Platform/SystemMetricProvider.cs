using System.Diagnostics;
using System.Globalization;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Text.Json;
using SysMon.Glass.Core;
using SysMon.Glass.Services;

namespace SysMon.Glass.Platform;
public interface IStartupAdapter
{
    Task<(bool Supported, string Message)> ApplyAsync(bool enabled, CancellationToken token);
}
public sealed class InstallerStartupAdapter : IStartupAdapter
{
    public Task<(bool Supported, string Message)> ApplyAsync(bool enabled, CancellationToken token) => Task.FromResult((false, "Startup preference saved. The installed platform adapter applies login startup; portable builds do not modify OS startup."));
}
public interface IDesktopUnderlayCapability { bool Supported { get; } string Reason { get; } }
public sealed class NormalWindowCapability : IDesktopUnderlayCapability
{
    public bool Supported => false;
    public string Reason => "Normal taskbar window. Native Windows WorkerW underlay is a separate, optional adapter.";
}
public sealed class SystemMetricProvider : IMetricProvider
{
    private readonly Dictionary<string, (ulong Total, ulong Idle)> cpuPrevious = [];
    private long previousBytes;
    private DateTimeOffset previousNetworkAt;
    [StructLayout(LayoutKind.Sequential)] private struct MemoryStatus { public uint Length, Load; public ulong TotalPhysical, AvailablePhysical, TotalPage, AvailablePage, TotalVirtual, AvailableVirtual, Extended; }
    [DllImport("kernel32.dll")] private static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);
    [DllImport("kernel32.dll")] private static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
    public async Task<Snapshot> CollectAsync(HostProfile host, CancellationToken token)
    {
        var m = Cards.All.ToDictionary(c => c.Metric, _ => Metric.Missing("No supported sensor source on this host."));
        if (host.Remote)
        {
            var text = await Processes.RunAsync("ssh", SshArguments.Build(host), token);
            foreach (var line in text.Split('\n'))
            {
                var split = line.IndexOf('='); if (split < 0) continue;
                var key = line[..split]; var value = line[(split + 1)..].Trim();
                switch (key)
                {
                    case "host": m[key] = new(value, host.Address); break;
                    case "os": m[key] = new(value, "Remote POSIX kernel"); break;
                    case "cpu": ParseCpu(value, host.Id, m); break;
                    case "memory": ParseMemory(value, m); break;
                    case "uptime": if (double.TryParse(value, CultureInfo.InvariantCulture, out var seconds)) m[key] = new(TimeSpan.FromSeconds(seconds).ToString(@"d\.hh\:mm"), "Days.hours:minutes"); break;
                    case "disk": var d = value.Split(','); if (d.Length == 2 && double.TryParse(d[0], out var total) && double.TryParse(d[1], out var used)) m[key] = new($"{100 * used / total:F1}%", $"Root: {used / 1048576:F1} / {total / 1048576:F1} GiB"); break;
                    case "gpu": ParseGpu(value, m); break;
                }
            }
            return new(DateTimeOffset.Now, m, "Connected · strict SSH", host.Id);
        }
        m["host"] = new(Environment.MachineName, $"{Environment.ProcessorCount} logical processors");
        m["runtime"] = new(RuntimeInformation.ProcessArchitecture.ToString(), RuntimeInformation.FrameworkDescription);
        m["os"] = new(RuntimeInformation.OSDescription, RuntimeInformation.OSArchitecture.ToString());
        m["uptime"] = new(TimeSpan.FromMilliseconds(Environment.TickCount64).ToString(@"d\.hh\:mm"), "Days.hours:minutes since boot");
        if (OperatingSystem.IsWindows())
        {
            var mem = new MemoryStatus { Length = (uint)Marshal.SizeOf<MemoryStatus>() };
            if (GlobalMemoryStatusEx(ref mem)) m["memory"] = new($"{mem.Load}%", $"{(mem.TotalPhysical - mem.AvailablePhysical) / 1073741824.0:F1} / {mem.TotalPhysical / 1073741824.0:F1} GiB physical");
            if (GetSystemTimes(out var idle, out var kernel, out var user)) CpuDelta((ulong)(kernel + user), (ulong)idle, host.Id, m);
        }
        else if (OperatingSystem.IsLinux())
        {
            ParseCpu((await File.ReadAllLinesAsync("/proc/stat", token))[0], host.Id, m);
            ParseMemory(string.Join(';', await File.ReadAllLinesAsync("/proc/meminfo", token)), m);
        }
        else if (OperatingSystem.IsMacOS())
        {
            var total = await Processes.RunAsync("/usr/sbin/sysctl", ["-n", "hw.memsize"], token);
            var vm = await Processes.RunAsync("/usr/bin/vm_stat", [], token);
            var pageMatch = System.Text.RegularExpressions.Regex.Match(vm, @"page size of (\d+)");
            var freeMatch = System.Text.RegularExpressions.Regex.Match(vm, @"Pages free:\s+(\d+)");
            var inactiveMatch = System.Text.RegularExpressions.Regex.Match(vm, @"Pages inactive:\s+(\d+)");
            if (double.TryParse(total, out var bytes) && pageMatch.Success && freeMatch.Success && inactiveMatch.Success)
            {
                var available = (double.Parse(freeMatch.Groups[1].Value) + double.Parse(inactiveMatch.Groups[1].Value)) * double.Parse(pageMatch.Groups[1].Value);
                m["memory"] = new($"{100 * (1 - available / bytes):F1}%", "Estimate: free + inactive pages; " + $"{bytes / 1073741824:F1} GiB total");
            }
            m["cpu"] = Metric.Missing("macOS CPU sampling extension not installed.");
        }
        var drives = DriveInfo.GetDrives().Where(d => d.IsReady && d.DriveType == DriveType.Fixed).ToArray();
        var capacity = drives.Sum(d => (double)d.TotalSize); var free = drives.Sum(d => (double)d.AvailableFreeSpace);
        if (capacity > 0) m["disk"] = new($"{100 * (1 - free / capacity):F1}%", $"Fixed volumes: {(capacity - free) / 1073741824:F1} / {capacity / 1073741824:F1} GiB");
        var now = DateTimeOffset.UtcNow;
        var bytesNow = NetworkInterface.GetAllNetworkInterfaces().Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback).Sum(n => { var s = n.GetIPStatistics(); return s.BytesReceived + s.BytesSent; });
        if (previousNetworkAt != default && bytesNow >= previousBytes) m["network"] = new($"{(bytesNow - previousBytes) / (now - previousNetworkAt).TotalSeconds / 1024:F1} KiB/s", "Combined RX + TX across active interfaces");
        else m["network"] = Metric.Missing("Waiting for second network sample.");
        previousBytes = bytesNow; previousNetworkAt = now;
        if (!string.IsNullOrWhiteSpace(host.FanStatePath))
        {
            try
            {
                var info = new FileInfo(host.FanStatePath);
                if (info.Length > 65536) throw new IOException("Fan state file exceeds 64 KiB.");
                var fan = (await File.ReadAllTextAsync(host.FanStatePath, token)).Trim();
                ParseFanState(fan, DateTimeOffset.Now, m);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException) { m["fan"] = Metric.Missing(ex.Message); m["cpuTemp"] = Metric.Missing(ex.Message); }
        }
        try { ParseGpu(await Processes.RunAsync("nvidia-smi", ["--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw", "--format=csv,noheader,nounits"], token), m); }
        catch (Exception ex) when (ex is IOException or System.ComponentModel.Win32Exception or OperationCanceledException) { if (token.IsCancellationRequested) throw; foreach (var key in new[] { "gpu", "gpuTemp", "gpuMemory", "power" }) m[key] = Metric.Missing("nvidia-smi unavailable: " + ex.Message); }
        return new(DateTimeOffset.Now, m, "Local · live samples", host.Id);
    }
    public static void ParseFanState(string text, DateTimeOffset now, Dictionary<string, Metric> metrics)
    {
        using var document = JsonDocument.Parse(text); var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("running", out var running) || running.ValueKind != JsonValueKind.True || !root.TryGetProperty("updatedAt", out var updated) || !DateTimeOffset.TryParse(updated.GetString(), out var at) || now - at > TimeSpan.FromSeconds(15) || at - now > TimeSpan.FromSeconds(5))
        { metrics["fan"] = Metric.Missing("FanCtl stopped or state is stale (>15 seconds)."); metrics["cpuTemp"] = Metric.Missing("FanCtl stopped or state is stale (>15 seconds)."); return; }
        double? Number(string name) => root.TryGetProperty(name, out var value) && value.TryGetDouble(out var number) && double.IsFinite(number) ? number : null;
        var cpu = Number("cpu"); var rpm = Number("cpuRpm"); var pump = Number("pumpRpm");
        var caseRpm = root.TryGetProperty("caseRpm", out var cases) && cases.ValueKind == JsonValueKind.Array ? string.Join(" / ", cases.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.Number).Select(x => x.GetDouble().ToString("F0", CultureInfo.InvariantCulture))) : "unavailable";
        var detail = $"FanCtl · {at.LocalDateTime:HH:mm:ss}\nCPU {rpm?.ToString("F0") ?? "unavailable"} RPM · Pump {pump?.ToString("F0") ?? "unavailable"} RPM\nCase fans {caseRpm} RPM";
        metrics["fan"] = rpm.HasValue ? new($"{rpm:F0} RPM", detail) : Metric.Missing("FanCtl CPU fan RPM unavailable.");
        metrics["cpuTemp"] = cpu.HasValue ? new($"{cpu:F1} °C", detail) : Metric.Missing("FanCtl CPU temperature unavailable.");
    }
    private void ParseCpu(string value, string host, Dictionary<string, Metric> m)
    {
        var parts = value.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Skip(1).Take(8).Select(v => ulong.TryParse(v, out var n) ? n : 0).ToArray();
        if (parts.Length >= 4) CpuDelta(parts.Aggregate(0UL, (a, b) => a + b), parts[3] + (parts.Length > 4 ? parts[4] : 0), host, m);
    }
    private void CpuDelta(ulong total, ulong idle, string host, Dictionary<string, Metric> m)
    {
        if (cpuPrevious.TryGetValue(host, out var p) && total > p.Total && idle >= p.Idle) m["cpu"] = new($"{Math.Clamp(100 * (1 - (double)(idle - p.Idle) / (total - p.Total)), 0, 100):F1}%", "Aggregate utilization since previous sample");
        else m["cpu"] = Metric.Missing("Waiting for second CPU sample.");
        cpuPrevious[host] = (total, idle);
    }
    private static void ParseMemory(string value, Dictionary<string, Metric> m)
    {
        var total = System.Text.RegularExpressions.Regex.Match(value, @"MemTotal:\s*=?\s*(\d+)");
        var avail = System.Text.RegularExpressions.Regex.Match(value, @"MemAvailable:\s*=?\s*(\d+)");
        if (total.Success && avail.Success) { var t = double.Parse(total.Groups[1].Value); var a = double.Parse(avail.Groups[1].Value); m["memory"] = new($"{100 * (1 - a / t):F1}%", $"{(t - a) / 1048576:F1} / {t / 1048576:F1} GiB physical"); }
    }
    private static void ParseGpu(string value, Dictionary<string, Metric> m)
    {
        var fields = value.Split('\n')[0].Split(',').Select(x => x.Trim()).ToArray(); if (fields.Length < 6) return;
        m["gpu"] = new(fields[1] + "%", fields[0] + " · first GPU");
        m["gpuTemp"] = new(fields[2] + " °C", fields[0]); m["gpuMemory"] = new(fields[3] + " MiB", "Used / " + fields[4] + " MiB"); m["power"] = new(fields[5] + " W", "GPU board power (driver reported)");
        foreach (var key in new[] { "gpu", "gpuTemp", "gpuMemory", "power" }) if (m[key].Value.Contains("N/A", StringComparison.OrdinalIgnoreCase) || m[key].Value.Contains("Not Supported", StringComparison.OrdinalIgnoreCase)) m[key] = Metric.Missing("NVIDIA driver does not expose this sensor.");
    }
}
