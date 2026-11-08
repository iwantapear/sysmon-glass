using System.Diagnostics;
using System.Text.RegularExpressions;
using SysMon.Glass.Core;

namespace SysMon.Glass.Services;
public static class Processes
{
    public static async Task<string> RunAsync(string executable, IEnumerable<string> args, CancellationToken token)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token); timeout.CancelAfter(TimeSpan.FromSeconds(8));
        var start = new ProcessStartInfo(executable) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
        foreach (var arg in args) start.ArgumentList.Add(arg);
        using var p = new Process { StartInfo = start }; p.Start();
        try
        {
            // Drain both streams concurrently; cap output to prevent an untrusted remote filling memory.
            var stdout = ReadBounded(p.StandardOutput, timeout.Token); var stderr = ReadBounded(p.StandardError, timeout.Token);
            await p.WaitForExitAsync(timeout.Token); var text = await stdout; var error = await stderr;
            if (p.ExitCode != 0) throw new IOException($"{executable}: {error.Trim()}");
            return text;
        }
        finally { if (!p.HasExited) { try { p.Kill(true); } catch (InvalidOperationException) { } } }
    }
    private static async Task<string> ReadBounded(StreamReader reader, CancellationToken token)
    {
        var output = new System.Text.StringBuilder(); var buffer = new char[2048]; int n;
        while ((n = await reader.ReadAsync(buffer.AsMemory(), token)) > 0)
        { if (output.Length + n > 128 * 1024) throw new IOException("Collector output exceeded 128 KiB limit."); output.Append(buffer, 0, n); }
        return output.ToString();
    }
}
public static class SshArguments
{
    public static void Validate(HostProfile h)
    {
        if (!Regex.IsMatch(h.Address, @"\A[a-zA-Z0-9][a-zA-Z0-9.:-]{0,252}\z") || h.Address.StartsWith('-')) throw new ArgumentException("Host must be a hostname or IP address, not a command.");
        if (!Regex.IsMatch(h.User, @"\A[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,63}\z")) throw new ArgumentException("Invalid SSH username.");
        if (h.Port is < 1 or > 65535) throw new ArgumentException("SSH port must be 1–65535.");
        foreach (var path in new[] { h.IdentityFile, h.KnownHostsFile })
        {
            if (!Path.IsPathFullyQualified(path) || path.Any(char.IsControl) || !File.Exists(path)) throw new ArgumentException("SSH key and known_hosts must be existing absolute paths.");
            var info = new FileInfo(path); if ((info.Attributes & FileAttributes.ReparsePoint) != 0 || !info.Exists) throw new ArgumentException("SSH key and known_hosts cannot be reparse points.");
            if (OperatingSystem.IsWindows() && (info.Attributes & FileAttributes.ReadOnly) == 0 && path.Equals(h.IdentityFile, StringComparison.OrdinalIgnoreCase)) { /* writable keys are accepted; ACL policy is best-effort */ }
        }
    }
    public static string[] Build(HostProfile h)
    {
        Validate(h);
        return ["-F", OperatingSystem.IsWindows() ? "NUL" : "/dev/null", "-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "IdentitiesOnly=yes", "-o", "PasswordAuthentication=no", "-o", "KbdInteractiveAuthentication=no", "-o", "ConnectTimeout=5", "-o", "ConnectionAttempts=1", "-o", "ClearAllForwardings=yes", "-o", $"UserKnownHostsFile={h.KnownHostsFile}", "-i", h.IdentityFile, "-p", h.Port.ToString(), "-l", h.User, "--", h.Address, LinuxScript];
    }
    // Fixed, application-owned POSIX probe. No host-supplied text is interpolated into remote commands.
    public const string LinuxScript = "LC_ALL=C; printf 'host='; hostname; printf 'os='; uname -sr; printf 'cpu='; head -n 1 /proc/stat; printf 'memory='; awk '/MemTotal:|MemAvailable:/{printf \"%s=%s;\",$1,$2} END{print \"\"}' /proc/meminfo; printf 'uptime='; cut -d ' ' -f 1 /proc/uptime; printf 'disk='; df -Pk / | tail -1 | awk '{print $2\",\"$3}'; if command -v nvidia-smi >/dev/null 2>&1; then printf 'gpu='; nvidia-smi --query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits | head -1; fi";
}
public sealed class PollingService(IMetricProvider provider)
{
    public async Task RunAsync(Func<HostProfile> host, Func<int> interval, Action<Snapshot> receive, CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            Snapshot snapshot; var collectingHost = host();
            try { snapshot = await provider.CollectAsync(collectingHost, token); }
            catch (OperationCanceledException) when (token.IsCancellationRequested) { break; }
            catch (Exception ex) { snapshot = new(DateTimeOffset.Now, Cards.All.ToDictionary(c => c.Metric, _ => Metric.Missing(ex.Message)), "Collection failed", collectingHost.Id); }
            if (!token.IsCancellationRequested) receive(snapshot);
            try { await Task.Delay(TimeSpan.FromSeconds(Math.Clamp(interval(), 2, 60)), token); } catch (OperationCanceledException) { break; }
        }
    }
}
