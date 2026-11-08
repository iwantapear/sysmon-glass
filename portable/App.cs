using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Themes.Fluent;
using Avalonia.Styling;
using SysMon.Glass.UI;

namespace SysMon.Glass;
public sealed class App : Application
{
    public override void Initialize() { Styles.Add(new FluentTheme()); RequestedThemeVariant = ThemeVariant.Dark; }
    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            var window = new DashboardWindow(); desktop.MainWindow = window;
            var menu = new NativeMenu();
            var show = new NativeMenuItem("Show dashboard"); show.Click += (_, _) => { window.Show(); window.WindowState = WindowState.Normal; window.Activate(); };
            var hide = new NativeMenuItem("Hide dashboard"); hide.Click += (_, _) => window.Hide();
            var quit = new NativeMenuItem("Quit"); quit.Click += (_, _) => desktop.Shutdown();
            menu.Add(show); menu.Add(hide); menu.Add(new NativeMenuItemSeparator()); menu.Add(quit);
            var tray = new TrayIcon { ToolTipText = "SysMon Glass", Menu = menu, IsVisible = true };
            // Embedded PNG: Skia (the X11/macOS decoder) cannot decode .ico. Tray support depends on desktop environment.
            try
            {
                using var iconStream = Avalonia.Platform.AssetLoader.Open(new Uri("avares://SysMon.Glass/Assets/tray.png"));
                tray.Icon = new WindowIcon(iconStream); window.Icon = tray.Icon;
            }
            catch (Exception) { /* A broken or missing icon must never take down the dashboard. */ }
            tray.Clicked += (_, _) => { window.Show(); window.Activate(); };
            TrayIcon.SetIcons(this, new TrayIcons { tray });
            desktop.Exit += (_, _) => { window.Stop(); tray.Dispose(); };
        }
        base.OnFrameworkInitializationCompleted();
    }
}
