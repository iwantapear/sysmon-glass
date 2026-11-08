using Microsoft.Win32;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text.Json;

string? FindPowerShell()
{
    var candidates = new List<string>();
    foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
    {
        using var hive = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view);
        using var versions = hive.OpenSubKey(@"SOFTWARE\Microsoft\PowerShellCore\InstalledVersions");
        if (versions is null) continue;
        foreach (var id in versions.GetSubKeyNames())
        {
            using var version = versions.OpenSubKey(id);
            if (version?.GetValue("InstallLocation") is string path) candidates.Add(Path.Combine(path, "pwsh.exe"));
        }
    }
    candidates.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "PowerShell", "7", "pwsh.exe"));
    foreach (var folder in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
        if (!string.IsNullOrWhiteSpace(folder)) candidates.Add(Path.Combine(folder.Trim('"'), "pwsh.exe"));
    return candidates.FirstOrDefault(File.Exists);
}
var shell = FindPowerShell();
var app = Path.Combine(AppContext.BaseDirectory, "app");
var entry = Path.Combine(app, "glass.ps1");
if (args.Contains("--self-test"))
{
    var result = new { PowerShell = shell, EntryExists = File.Exists(entry), BaseDirectory = AppContext.BaseDirectory, Framework = "WPF-current" };
    var text = JsonSerializer.Serialize(result);
    if (args.Length > 1 && args[1] != "--self-test") File.WriteAllText(args[1], text);
    return shell is not null && File.Exists(entry) ? 0 : 2;
}
if (shell is null || !File.Exists(entry)) { MessageBoxW(0, "PowerShell 7 is required, and app/glass.ps1 must exist beside this launcher.", "SysMon Glass", 0x10); return 2; }
var sid = WindowsIdentity.GetCurrent().User?.Value ?? Environment.UserName;
using var mutex = new Mutex(true, @"Local\SysMon.Glass.WPF." + sid, out var owns);
var config = Environment.GetEnvironmentVariable("SYSMON_CONFIG_HOME") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "SysMon.Glass");
Directory.CreateDirectory(config);
var pidFile = Path.Combine(config, "launcher-pid.json");
if (!owns)
{
    try
    {
        var state = JsonSerializer.Deserialize<ChildState>(File.ReadAllText(pidFile));
        if (state is not null)
        {
            using var child = Process.GetProcessById(state.Pid);
            if (child.StartTime.ToUniversalTime().Ticks == state.StartTicks)
                EnumWindows((window, _) => { GetWindowThreadProcessId(window, out var pid); if (pid == child.Id) { ShowWindow(window, 5); ShowWindow(window, 9); SetForegroundWindow(window); } return true; }, 0);
        }
    }
    catch { /* A duplicate during launch exits without spawning another UI. */ }
    return 0;
}
try
{
    var start = new ProcessStartInfo(shell) { UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = app };
    foreach (var argument in new[] { "-STA", "-NoProfile", "-WindowStyle", "Hidden", "-File", entry }) start.ArgumentList.Add(argument);
    start.Environment["SYSMON_CONFIG_HOME"] = config;
    start.Environment["SYSMON_APP_ICON"] = Path.Combine(AppContext.BaseDirectory, "sysmon.ico");
    using var process = Process.Start(start) ?? throw new InvalidOperationException("Cannot launch PowerShell.");
    File.WriteAllText(pidFile, JsonSerializer.Serialize(new ChildState(process.Id, process.StartTime.ToUniversalTime().Ticks)));
    process.WaitForExit();
    return process.ExitCode;
}
catch (Exception ex) { MessageBoxW(0, ex.Message, "SysMon Glass", 0x10); return 1; }
finally { try { File.Delete(pidFile); } catch { } mutex.ReleaseMutex(); }

[DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, nint data);
[DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(nint window, out uint pid);
[DllImport("user32.dll")] static extern bool ShowWindow(nint window, int command);
[DllImport("user32.dll")] static extern bool SetForegroundWindow(nint window);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int MessageBoxW(nint window, string text, string title, uint type);
delegate bool EnumWindowsProc(nint window, nint data);
record ChildState(int Pid, long StartTicks);
