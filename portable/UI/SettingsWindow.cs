using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using SysMon.Glass.Core;
namespace SysMon.Glass.UI;
public sealed class SettingsWindow : Window
{
    public SettingsWindow(UserSettings settings, SettingsStore store)
    {
        Title = "Host profile settings"; Width = 650; Height = 700; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var hosts = settings.Hosts.Select(h => new HostProfile { Id = h.Id, Name = h.Name, Remote = h.Remote, Address = h.Address, User = h.User, Port = h.Port, IdentityFile = h.IdentityFile, KnownHostsFile = h.KnownHostsFile, FanStatePath = h.FanStatePath }).ToList();
        var host = hosts[0]; var picker = new ComboBox { ItemsSource = hosts.Select(h => h.Name).ToArray(), SelectedIndex = 0 };
        var name = new TextBox(); var address = new TextBox { Watermark = "hostname or IP" }; var user = new TextBox { Watermark = "SSH user" }; var port = new NumericUpDown { Minimum = 1, Maximum = 65535 }; var key = new TextBox { Watermark = "absolute private key path" }; var known = new TextBox { Watermark = "absolute known_hosts path" }; var fan = new TextBox { Watermark = "optional local fan-state file" }; var remote = new CheckBox { Content = "Remote host (strict key-only SSH)" }; var startup = new CheckBox { Content = "Start with user login", IsChecked = settings.StartupEnabled }; var theme = new ComboBox { ItemsSource = Palettes.All.Select(p => p.Id).ToArray(), SelectedIndex = Array.FindIndex(Palettes.All, p => p.Id == settings.Theme) }; var poll = new NumericUpDown { Value = settings.PollSeconds, Minimum = 2, Maximum = 60 };
        void Load() { name.Text = host.Name; address.Text = host.Address; user.Text = host.User; port.Value = host.Port; key.Text = host.IdentityFile; known.Text = host.KnownHostsFile; fan.Text = host.FanStatePath; remote.IsChecked = host.Remote; }
        void Capture() { host.Name = name.Text?.Trim() ?? "Host"; host.Address = address.Text?.Trim() ?? ""; host.User = user.Text?.Trim() ?? ""; host.Port = (int)(port.Value ?? 22); host.IdentityFile = key.Text?.Trim() ?? ""; host.KnownHostsFile = known.Text?.Trim() ?? ""; host.FanStatePath = fan.Text?.Trim() ?? ""; host.Remote = remote.IsChecked == true; }
        Load(); var refresh = false;
        picker.SelectionChanged += (_, _) => { if (refresh || picker.SelectedIndex < 0) return; Capture(); host = hosts[picker.SelectedIndex]; Load(); };
        var add = new Button { Content = "Add profile" }; add.Click += (_, _) => { Capture(); hosts.Add(new HostProfile { Name = "New host" }); refresh = true; picker.ItemsSource = hosts.Select(h => h.Name).ToArray(); picker.SelectedIndex = hosts.Count - 1; refresh = false; host = hosts[^1]; Load(); };
        var remove = new Button { Content = "Remove profile" }; remove.Click += (_, _) => { if (hosts.Count == 1) return; hosts.Remove(host); host = hosts[0]; refresh = true; picker.ItemsSource = hosts.Select(h => h.Name).ToArray(); picker.SelectedIndex = 0; refresh = false; Load(); };
        var error = new TextBlock { Foreground = Brushes.LightCoral, TextWrapping = TextWrapping.Wrap };
        var save = new Button { Content = "Save settings" }; save.Click += async (_, _) =>
        {
            Capture(); try { foreach (var h in hosts.Where(h => h.Remote)) Services.SshArguments.Validate(h); var old = settings.Hosts; var oldStartup = settings.StartupEnabled; var oldTheme = settings.Theme; var oldPoll = settings.PollSeconds; var newStartup = startup.IsChecked == true; if (newStartup != oldStartup) await new Platform.UserStartupAdapter().ApplyAsync(newStartup, CancellationToken.None); settings.Hosts = hosts; settings.StartupEnabled = newStartup; settings.Theme = (theme.SelectedItem as string) ?? "dark"; settings.PollSeconds = (int)(poll.Value ?? 3); try { await store.SaveAsync(settings); } catch { settings.Hosts = old; settings.StartupEnabled = oldStartup; settings.Theme = oldTheme; settings.PollSeconds = oldPoll; if (newStartup != oldStartup) await new Platform.UserStartupAdapter().ApplyAsync(oldStartup, CancellationToken.None); throw; } Close(); } catch (Exception ex) { error.Text = ex.Message; }
        };
        Content = new ScrollViewer { Content = new StackPanel { Margin = new Thickness(28), Spacing = 10, Children = { new TextBlock { Text = "Host profiles & settings", FontSize = 24 }, picker, new StackPanel { Orientation = Avalonia.Layout.Orientation.Horizontal, Spacing = 8, Children = { add, remove } }, Label("Display name", name), remote, Label("Address", address), Label("SSH user", user), Label("Port", port), Label("Identity file (required for remote)", key), Label("known_hosts file (required for remote)", known), Label("Fan state path (local, optional)", fan), startup, Label("Theme palette", theme), Label("Polling interval seconds", poll), error, save, new TextBlock { Text = "Passwords are never accepted. Strict host-key checking requires an existing trusted known_hosts entry. The fixed remote probe supports Linux hosts. Login startup changes are applied using per-user Windows Run, Linux XDG autostart or macOS LaunchAgent entries.", TextWrapping = TextWrapping.Wrap, Foreground = Brushes.Gray, FontSize = 11 } } } };
    }
    private static Control Label(string text, Control control) => new StackPanel { Spacing = 3, Children = { new TextBlock { Text = text }, control } };
}
