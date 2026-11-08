using Microsoft.Win32;
using System.Security;
using System.Text;

namespace SysMon.Glass.Platform;
/// <summary>User-only login startup; identifiers intentionally match deploy installers.</summary>
public sealed class UserStartupAdapter : IStartupAdapter
{
    public static string ExecutablePath()
    {
        var path = Path.GetFullPath(Environment.ProcessPath ?? throw new IOException("Cannot determine application executable."));
        if (!File.Exists(path) || (new FileInfo(path).Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Application executable must be a regular non-reparse file.");
        if (Path.GetFileNameWithoutExtension(path).Equals("dotnet", StringComparison.OrdinalIgnoreCase)) throw new IOException("Login startup requires the published SysMon.Glass executable, not dotnet run.");
        return path;
    }
    public Task<(bool Supported, string Message)> ApplyAsync(bool enabled, CancellationToken token) => Task.Run(() =>
    {
        token.ThrowIfCancellationRequested(); var exe = ExecutablePath();
        if (OperatingSystem.IsWindows())
        {
            using var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true) ?? throw new IOException("Cannot open user startup registry key.");
            if (enabled) key.SetValue("SysMon.Glass", "\"" + exe + "\"", RegistryValueKind.String); else key.DeleteValue("SysMon.Glass", false);
            return (true, enabled ? "Windows login startup enabled." : "Windows login startup disabled.");
        }
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (OperatingSystem.IsLinux())
        {
            var config = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME"); if (string.IsNullOrWhiteSpace(config)) config = Path.Combine(home, ".config");
            if (!Path.IsPathFullyQualified(config)) throw new IOException("XDG_CONFIG_HOME must be absolute.");
            var path = Path.Combine(config, "autostart", "sysmon-glass.desktop");
            if (enabled) WriteAtomic(path, DesktopEntry(exe)); else DeleteSafe(path);
            return (true, "Linux login startup updated.");
        }
        if (OperatingSystem.IsMacOS())
        {
            var path = Path.Combine(home, "Library", "LaunchAgents", "local.sysmon.glass.plist");
            if (enabled) WriteAtomic(path, LaunchAgent(exe)); else DeleteSafe(path);
            return (true, "macOS login startup updated (effective next login; current app not stopped).");
        }
        throw new PlatformNotSupportedException("Login startup is unsupported on this OS.");
    }, token);
    public static string DesktopEntry(string exe)
    {
        if (exe.Any(char.IsControl)) throw new ArgumentException("Executable path contains control characters.");
        var quoted = exe.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("`", "\\`").Replace("$", "\\$").Replace("%", "%%");
        return $"[Desktop Entry]\nType=Application\nName=SysMon Glass\nExec=\"{quoted}\"\nTerminal=false\nStartupWMClass=SysMon.Glass\n";
    }
    public static string LaunchAgent(string exe) => "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\"><dict><key>Label</key><string>local.sysmon.glass</string><key>ProgramArguments</key><array><string>" + SecurityElement.Escape(exe) + "</string></array><key>RunAtLoad</key><true/></dict></plist>\n";
    private static void DeleteSafe(string path) { if (!File.Exists(path)) return; var info = new FileInfo(path); if ((info.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Refusing to delete a reparse-point startup file."); File.Delete(path); }
    private static void WriteAtomic(string path, string content) { var parent = Path.GetDirectoryName(path)!; Directory.CreateDirectory(parent); var dir = new DirectoryInfo(parent); if ((dir.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Refusing startup path under a reparse-point directory."); var temp = path + ".tmp"; if (File.Exists(temp) && (new FileInfo(temp).Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Refusing reparse-point startup temporary file."); File.WriteAllText(temp, content, new UTF8Encoding(false)); File.Move(temp, path, true); }
}
