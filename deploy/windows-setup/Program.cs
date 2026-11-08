using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;

if (!OperatingSystem.IsWindows()) return 1;
var diagnostic = args.Any(a => a.Equals("--diagnostic", StringComparison.OrdinalIgnoreCase) || a.Equals("-TestRoot", StringComparison.OrdinalIgnoreCase));
var forwarded = args.Where(a => !a.Equals("--diagnostic", StringComparison.OrdinalIgnoreCase)).ToArray();
var asm = Assembly.GetExecutingAssembly();
var testIndex = Array.FindIndex(args, a => a.Equals("-TestRoot", StringComparison.OrdinalIgnoreCase));
var scratch = testIndex >= 0 && testIndex + 1 < args.Length ? Path.GetFullPath(args[testIndex + 1]) : Path.GetTempPath();
var temp = Path.Combine(scratch, "SysMon.Glass.Setup-" + Guid.NewGuid().ToString("N"));
var log = Path.Combine(scratch, "SysMon.Glass.Setup-last.log");
void Report(string text)
{
    try { File.AppendAllText(log, DateTimeOffset.Now + " " + text + Environment.NewLine); } catch { /* Reporting must never hide the setup error. */ }
    if (diagnostic) Console.Error.WriteLine(text);
}
try
{
    Directory.CreateDirectory(temp);
    Report("Setup started; diagnostic=" + diagnostic);
    foreach (var name in new[] { "install.ps1", "payload.zip" })
    {
        using var stream = asm.GetManifestResourceStream(name) ?? throw new InvalidOperationException("Setup payload missing; rebuild with deploy/publish.ps1.");
        using var output = File.Create(Path.Combine(temp, name));
        stream.CopyTo(output);
    }
    var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe")) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = diagnostic };
    foreach (var arg in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", Path.Combine(temp, "install.ps1"), "-Payload", Path.Combine(temp, "payload.zip") }) start.ArgumentList.Add(arg);
    foreach (var arg in forwarded) start.ArgumentList.Add(arg);
    using var process = Process.Start(start) ?? throw new InvalidOperationException("Cannot start installer.");
    // Drain both pipes concurrently so a failing script cannot deadlock the bootstrapper.
    var stdout = process.StandardOutput.ReadToEndAsync();
    var stderr = process.StandardError.ReadToEndAsync();
    if (!process.WaitForExit(120000))
    {
        process.Kill(entireProcessTree: true);
        process.WaitForExit();
        throw new TimeoutException("Installer child exceeded 120 seconds and was stopped.");
    }
    Report(stdout.GetAwaiter().GetResult());
    Report(stderr.GetAwaiter().GetResult());
    Report("Installer exit code: " + process.ExitCode);
    if (process.ExitCode != 0 && !diagnostic) MessageBoxW(IntPtr.Zero, "Installation failed. Details: " + log, "SysMon Glass Setup", 0x10);
    return process.ExitCode;
}
catch (Exception ex)
{
    Report(ex.ToString());
    if (!diagnostic) MessageBoxW(IntPtr.Zero, ex.Message + "\nDetails: " + log, "SysMon Glass Setup", 0x10);
    return 1;
}
finally
{
    try { if (Directory.Exists(temp)) Directory.Delete(temp, true); }
    catch (Exception ex) { Report("Temporary extraction retained: " + ex.Message); }
}

[DllImport("user32.dll", CharSet = CharSet.Unicode)]
static extern int MessageBoxW(IntPtr window, string message, string title, uint type);
