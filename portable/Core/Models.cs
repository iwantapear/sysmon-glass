using System.Text.Json;

namespace SysMon.Glass.Core;
public record CardDefinition(string Id, string Title, string Metric, int DefaultSpan, string Accent);
public static class Cards
{
    public static readonly CardDefinition[] All = [
        new("cpu", "PROCESSOR", "cpu", 2, "#86BFFF"), new("memory", "MEMORY", "memory", 1, "#B3A1FF"),
        new("gpu", "GRAPHICS", "gpu", 1, "#79EDD3"), new("gpuTemp", "GPU TEMPERATURE", "gpuTemp", 1, "#FFBC96"),
        new("gpuMemory", "VIDEO MEMORY", "gpuMemory", 1, "#B3A1FF"), new("disk", "STORAGE", "disk", 2, "#86BFFF"),
        new("network", "NETWORK", "network", 2, "#79EDD3"), new("fan", "FANS", "fan", 1, "#79EDD3"),
        new("cpuTemp", "CPU TEMPERATURE", "cpuTemp", 1, "#FFBC96"), new("power", "GPU POWER", "power", 1, "#FFD982"),
        new("uptime", "UPTIME", "uptime", 1, "#86BFFF"), new("os", "OPERATING SYSTEM", "os", 2, "#B3A1FF"),
        new("host", "HOST", "host", 1, "#79EDD3"), new("runtime", "RUNTIME", "runtime", 1, "#FFD982")];
}
public sealed class HostProfile
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Name { get; set; } = "Local machine";
    public bool Remote { get; set; }
    public string Address { get; set; } = "";
    public string User { get; set; } = "";
    public int Port { get; set; } = 22;
    public string IdentityFile { get; set; } = "";
    public string KnownHostsFile { get; set; } = "";
    public string FanStatePath { get; set; } = "";
}
public sealed class CardLayout
{
    public string Id { get; set; } = "";
    public int Span { get; set; } = 1;
}
public sealed class UserSettings
{
    public bool StartupEnabled { get; set; } = true;
    public string Theme { get; set; } = "dark";
    public int PollSeconds { get; set; } = 3;
    public List<HostProfile> Hosts { get; set; } = [new()];
    public string SelectedHost { get; set; } = "";
    public List<CardLayout> Layout { get; set; } = Cards.All.Select(c => new CardLayout { Id = c.Id, Span = c.DefaultSpan }).ToList();
    public void Normalize()
    {
        PollSeconds = Math.Clamp(PollSeconds, 2, 60);
        Hosts = (Hosts ?? []).Where(h => h is not null).Take(32).ToList(); if (Hosts.Count == 0) Hosts.Add(new());
        foreach (var h in Hosts) { h.Id = string.IsNullOrWhiteSpace(h.Id) ? Guid.NewGuid().ToString("N") : h.Id[..Math.Min(h.Id.Length, 128)]; h.Name ??= "Host"; h.Address ??= ""; h.User ??= ""; h.IdentityFile ??= ""; h.KnownHostsFile ??= ""; h.FanStatePath ??= ""; h.Port = Math.Clamp(h.Port, 1, 65535); }
        SelectedHost ??= ""; Theme = new[] { "light", "dark", "sunset", "rose", "violet", "aurora", "neon", "flame", "ocean", "forest", "amber" }.Contains(Theme) ? Theme : "dark";
        Layout = (Layout ?? []).Where(c => c is not null).Take(64).Where(c => Cards.All.Any(d => d.Id == c.Id)).DistinctBy(c => c.Id).ToList();
        foreach (var c in Layout) c.Span = Math.Clamp(c.Span, 1, 2);
        if (OperatingSystem.IsWindows() && string.IsNullOrWhiteSpace(Hosts[0].FanStatePath)) { var fan = @"E:\C++\fan-tuning\state.json"; if (File.Exists(fan)) Hosts[0].FanStatePath = fan; }
        foreach (var d in Cards.All.Where(d => Layout.All(c => c.Id != d.Id))) Layout.Add(new() { Id = d.Id, Span = d.DefaultSpan });
    }
}
public record Placement(string Id, int Column, int Row, int Span);
public static class GridLayout
{
    // First-fit, stable order, exactly one row per card. Long cards never wrap or overlap.
    public static List<Placement> Pack(IEnumerable<CardLayout> cards, int columns)
    {
        columns = Math.Max(2, columns); var occupied = new HashSet<(int, int)>(); var result = new List<Placement>();
        foreach (var card in cards)
        {
            var span = Math.Clamp(card.Span, 1, 2); var row = 0; var col = 0;
            while (true)
            {
                if (col + span <= columns && Enumerable.Range(col, span).All(x => !occupied.Contains((x, row)))) break;
                if (++col >= columns) { col = 0; row++; }
            }
            foreach (var x in Enumerable.Range(col, span)) occupied.Add((x, row));
            result.Add(new(card.Id, col, row, span));
        }
        return result;
    }
}
public record Metric(string Value, string Detail, bool Available = true)
{
    public static Metric Missing(string reason) => new("Unavailable", reason, false);
}
public record Snapshot(DateTimeOffset At, IReadOnlyDictionary<string, Metric> Metrics, string Status, string HostId = "");
public interface IMetricProvider { Task<Snapshot> CollectAsync(HostProfile host, CancellationToken token); }
public interface IMetricPlugin
{
    string Id { get; }
    IReadOnlyList<CardDefinition> Definitions { get; }
    Task<IReadOnlyDictionary<string, Metric>> CollectAsync(HostProfile host, CancellationToken token);
}
public sealed class SettingsStore
{
    public static string DefaultDirectory => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "SysMon.Glass");
    public string FilePath { get; }
    public string? LoadWarning { get; private set; }
    public SettingsStore(string? directory = null) { FilePath = Path.Combine(directory ?? DefaultDirectory, "settings.json"); }
    public UserSettings Load()
    {
        try { var s = File.Exists(FilePath) ? JsonSerializer.Deserialize<UserSettings>(File.ReadAllText(FilePath)) ?? new() : new(); s.Normalize(); return s; }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException) { LoadWarning = ex.Message; return new(); }
    }
    private readonly SemaphoreSlim saveGate = new(1, 1);
    public async Task SaveAsync(UserSettings settings)
    {
        await saveGate.WaitAsync();
        try {
        settings.Normalize(); Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        var temp = FilePath + ".tmp";
        await File.WriteAllTextAsync(temp, JsonSerializer.Serialize(settings, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temp, FilePath, true);
        } finally { saveGate.Release(); }
    }
}
