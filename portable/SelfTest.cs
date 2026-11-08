using SysMon.Glass.Core;
using SysMon.Glass.Services;
namespace SysMon.Glass;
internal static class SelfTest
{
    public static void Run()
    {
        var settings = new UserSettings(); settings.Normalize();
        if (Cards.All.Length != 14) throw new Exception($"Expected 14 cards, got {Cards.All.Length}.");
        var packed = GridLayout.Pack(settings.Layout, 2); if (packed.Count != 14) throw new Exception("Layout card count mismatch.");
        var cells = new HashSet<(int, int)>(); foreach (var p in packed) foreach (var x in Enumerable.Range(p.Column, p.Span)) if (!cells.Add((x, p.Row))) throw new Exception("Overlapping card layout.");
        var dir = Path.Combine(AppContext.BaseDirectory, "selftest-" + Guid.NewGuid().ToString("N")); var store = new SettingsStore(dir); store.SaveAsync(settings).GetAwaiter().GetResult(); var loaded = store.Load(); if (!loaded.StartupEnabled || loaded.Layout.Count != 14) throw new Exception("Settings persistence mismatch."); var packed4 = GridLayout.Pack(loaded.Layout, 4); var cells4 = new HashSet<(int, int)>(); foreach (var p in packed4) foreach (var x in Enumerable.Range(p.Column, p.Span)) if (!cells4.Add((x, p.Row))) throw new Exception("Overlapping 4-column card layout."); var invalid = new HostProfile { Address = "-bad", User = "user", IdentityFile = "x", KnownHostsFile = "y" }; try { SshArguments.Validate(invalid); throw new Exception("SSH validation accepted an invalid host."); } catch (ArgumentException) { } Directory.Delete(dir, true);
        var broken = System.Text.Json.JsonSerializer.Deserialize<UserSettings>("{\"Hosts\":[null,{\"Name\":null,\"Id\":null,\"Address\":null}],\"Layout\":[null,{\"Id\":null}],\"Theme\":null}")!; broken.Normalize(); if (broken.Hosts.Count != 1 || broken.Layout.Count != 14 || broken.Theme != "dark") throw new Exception("Null settings normalization failed.");
        var fanMetrics = new Dictionary<string, Metric>(); var now = DateTimeOffset.Now; Platform.SystemMetricProvider.ParseFanState("{\"running\":true,\"updatedAt\":\"" + now.ToString("O") + "\",\"cpu\":58,\"cpuRpm\":900,\"pumpRpm\":2200,\"caseRpm\":[700,800]}", now, fanMetrics); if (fanMetrics["cpuTemp"].Value != "58.0 °C" || !fanMetrics["fan"].Detail.Contains("2200")) throw new Exception("FanCtl JSON parsing failed."); Platform.SystemMetricProvider.ParseFanState("{\"running\":true,\"updatedAt\":\"2000-01-01T00:00:00Z\"}", now, fanMetrics); if (fanMetrics["fan"].Available) throw new Exception("Stale FanCtl state accepted.");
        if (UI.Palettes.All.Length != 11 || !Platform.UserStartupAdapter.DesktopEntry("/tmp/test path/app").Contains("Exec=\"/tmp/test path/app\"")) throw new Exception("Palette/startup serialization test failed.");
        Console.WriteLine("SysMon.Glass self-test passed: 14 cards, 2/4-column non-overlap, JSON persistence/null recovery, startup default/serialization, SSH host validation, 11 palettes, FanCtl fresh/stale parsing.");
    }
}
