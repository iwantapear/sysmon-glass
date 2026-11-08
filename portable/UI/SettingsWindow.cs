using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using SysMon.Glass.Core;
namespace SysMon.Glass.UI;
public sealed class SettingsWindow : Window
{
    public SettingsWindow(UserSettings settings, SettingsStore store)
    {
        Title = L10n.T("settings.windowTitle"); Width = 650; Height = 700; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var hosts = settings.Hosts.Select(h => new HostProfile { Id = h.Id, Name = h.Name, Remote = h.Remote, Address = h.Address, User = h.User, Port = h.Port, IdentityFile = h.IdentityFile, KnownHostsFile = h.KnownHostsFile, FanStatePath = h.FanStatePath }).ToList();
        var host = hosts[0]; var picker = new ComboBox { ItemsSource = hosts.Select(h => h.Name).ToArray(), SelectedIndex = 0 };
        var name = new TextBox(); var address = new TextBox { Watermark = "hostname or IP" }; var user = new TextBox { Watermark = "SSH user" }; var port = new NumericUpDown { Minimum = 1, Maximum = 65535 }; var key = new TextBox { Watermark = "absolute private key path" }; var known = new TextBox { Watermark = "absolute known_hosts path" }; var fan = new TextBox { Watermark = "optional local fan-state file" }; var remote = new CheckBox { Content = L10n.T("settings.remote") }; var startup = new CheckBox { Content = L10n.T("settings.startup"), IsChecked = settings.StartupEnabled }; var theme = new ComboBox { ItemsSource = Palettes.All.Select(p => p.Id).ToArray(), SelectedIndex = Array.FindIndex(Palettes.All, p => p.Id == settings.Theme) }; var poll = new NumericUpDown { Value = settings.PollSeconds, Minimum = 2, Maximum = 60 };
        var languageOptions = new[] { L10n.T("settings.languageAuto"), "简体中文", "繁體中文", "English" };
        var languageCodes = new[] { "", L10n.Simplified, L10n.Traditional, L10n.English };
        var language = new ComboBox { ItemsSource = languageOptions, SelectedIndex = Math.Max(0, Array.IndexOf(languageCodes, L10n.Normalize(settings.Language))) };
        void Load() { name.Text = host.Name; address.Text = host.Address; user.Text = host.User; port.Value = host.Port; key.Text = host.IdentityFile; known.Text = host.KnownHostsFile; fan.Text = host.FanStatePath; remote.IsChecked = host.Remote; }
        void Capture() { host.Name = name.Text?.Trim() ?? "Host"; host.Address = address.Text?.Trim() ?? ""; host.User = user.Text?.Trim() ?? ""; host.Port = (int)(port.Value ?? 22); host.IdentityFile = key.Text?.Trim() ?? ""; host.KnownHostsFile = known.Text?.Trim() ?? ""; host.FanStatePath = fan.Text?.Trim() ?? ""; host.Remote = remote.IsChecked == true; }
        Load(); var refresh = false;
        picker.SelectionChanged += (_, _) => { if (refresh || picker.SelectedIndex < 0) return; Capture(); host = hosts[picker.SelectedIndex]; Load(); };
        var add = new Button { Content = L10n.T("settings.add") }; add.Click += (_, _) => { Capture(); hosts.Add(new HostProfile { Name = "New host" }); refresh = true; picker.ItemsSource = hosts.Select(h => h.Name).ToArray(); picker.SelectedIndex = hosts.Count - 1; refresh = false; host = hosts[^1]; Load(); };
        var remove = new Button { Content = L10n.T("settings.remove") }; remove.Click += (_, _) => { if (hosts.Count == 1) return; hosts.Remove(host); host = hosts[0]; refresh = true; picker.ItemsSource = hosts.Select(h => h.Name).ToArray(); picker.SelectedIndex = 0; refresh = false; Load(); };
        var error = new TextBlock { Foreground = Brushes.LightCoral, TextWrapping = TextWrapping.Wrap };
        var save = new Button { Content = L10n.T("settings.save") }; save.Click += async (_, _) =>
        {
            Capture(); try { foreach (var h in hosts.Where(h => h.Remote)) Services.SshArguments.Validate(h); var old = settings.Hosts; var oldStartup = settings.StartupEnabled; var oldTheme = settings.Theme; var oldPoll = settings.PollSeconds; var newStartup = startup.IsChecked == true; if (newStartup != oldStartup) await new Platform.UserStartupAdapter().ApplyAsync(newStartup, CancellationToken.None); settings.Hosts = hosts; settings.StartupEnabled = newStartup; settings.Theme = (theme.SelectedItem as string) ?? "dark"; settings.Language = languageCodes[Math.Max(0, language.SelectedIndex)]; L10n.Override = settings.Language; settings.PollSeconds = (int)(poll.Value ?? 3); try { await store.SaveAsync(settings); } catch { settings.Hosts = old; settings.StartupEnabled = oldStartup; settings.Theme = oldTheme; settings.PollSeconds = oldPoll; if (newStartup != oldStartup) await new Platform.UserStartupAdapter().ApplyAsync(oldStartup, CancellationToken.None); throw; } Close(); } catch (Exception ex) { error.Text = ex.Message; }
        };
        Content = new ScrollViewer { Content = new StackPanel { Margin = new Thickness(28), Spacing = 10, Children = { new TextBlock { Text = L10n.T("settings.title"), FontSize = 24 }, picker, new StackPanel { Orientation = Avalonia.Layout.Orientation.Horizontal, Spacing = 8, Children = { add, remove } }, Label(L10n.T("settings.name"), name), remote, Label(L10n.T("settings.address"), address), Label(L10n.T("settings.user"), user), Label(L10n.T("settings.port"), port), Label(L10n.T("settings.key"), key), Label(L10n.T("settings.knownHosts"), known), Label(L10n.T("settings.fan"), fan), startup, Label(L10n.T("settings.theme"), theme), Label(L10n.T("settings.poll"), poll), Label(L10n.T("settings.language"), language), error, save, new TextBlock { Text = L10n.T("settings.note"), TextWrapping = TextWrapping.Wrap, Foreground = Brushes.Gray, FontSize = 11 } } } };
    }
    private static Control Label(string text, Control control) => new StackPanel { Spacing = 3, Children = { new TextBlock { Text = text }, control } };
}
