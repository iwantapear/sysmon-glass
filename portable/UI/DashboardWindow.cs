using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using SysMon.Glass.Core;
using SysMon.Glass.Platform;

namespace SysMon.Glass.UI;
public sealed class DashboardWindow : Window
{
    private readonly UserSettings settings; private readonly SettingsStore store = new(); private readonly CancellationTokenSource stop = new();
    private readonly Canvas canvas = new(); private readonly TextBlock status = new(); private readonly ComboBox hostPicker = new() { MinWidth = 165 }; private readonly ToggleSwitch edit = new() { Content = "Edit" };
    private readonly Dictionary<string, (TextBlock Value, TextBlock Detail)> values = []; private readonly Dictionary<string, Border> views = [];
    private HostProfile selected; private Snapshot? lastSnapshot; private ThemePalette palette; private readonly UserStartupAdapter startup = new(); private Task? pollingTask; private string? dragged; private Point dragStart; private Border? draggedView;
    private readonly Border editHint = new() { Padding = new Thickness(12), CornerRadius = new CornerRadius(10), Background = new SolidColorBrush(Color.Parse("#503F6292")) };
    private const double CellHeight = 155, Gap = 12;
    public DashboardWindow()
    {
        Title = "SysMon Glass"; Width = 1150; Height = 850; MinWidth = 650; MinHeight = 480; ShowInTaskbar = true;
        Background = new SolidColorBrush(Color.Parse("#D8182235")); TransparencyLevelHint = [WindowTransparencyLevel.AcrylicBlur, WindowTransparencyLevel.Transparent];
        settings = store.Load(); palette = Palettes.Get(settings.Theme); selected = settings.Hosts.FirstOrDefault(h => h.Id == settings.SelectedHost) ?? settings.Hosts[0];
        var root = new Grid { RowDefinitions = new RowDefinitions("Auto,Auto,*,Auto") };
        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,Auto,Auto,Auto"), Margin = new Thickness(28, 24, 28, 16) };
        header.Children.Add(new StackPanel { Spacing = 3, Children = { new TextBlock { Text = "SYSTEM / LIVE MONITOR", Foreground = Brushes.LightSkyBlue, FontSize = 11 }, new TextBlock { Text = "系统状态", FontSize = 29, FontWeight = FontWeight.SemiBold } } });
        hostPicker.ItemsSource = settings.Hosts.Select(h => h.Name).ToArray(); hostPicker.SelectedIndex = settings.Hosts.IndexOf(selected); hostPicker.VerticalAlignment = VerticalAlignment.Center;
        hostPicker.SelectionChanged += async (_, _) => { if (hostPicker.SelectedIndex >= 0) { selected = settings.Hosts[hostPicker.SelectedIndex]; settings.SelectedHost = selected.Id; lastSnapshot = null; foreach (var pair in values.Values) { pair.Value.Text = "Unavailable"; pair.Detail.Text = "Waiting for this host…"; } await Save(); } };
        AddHeader(header, hostPicker, 1); edit.VerticalAlignment = VerticalAlignment.Center; edit.IsCheckedChanged += (_, _) => { editHint.IsVisible = edit.IsChecked == true; Rebuild(); }; AddHeader(header, edit, 2);
        var config = Button("Hosts / settings", async () => { var before = settings.StartupEnabled; var beforeTheme = settings.Theme; await new SettingsWindow(settings, store).ShowDialog(this); selected = settings.Hosts.FirstOrDefault(h => h.Id == selected.Id) ?? settings.Hosts[0]; palette = Palettes.Get(settings.Theme); hostPicker.ItemsSource = settings.Hosts.Select(h => h.Name).ToArray(); hostPicker.SelectedIndex = settings.Hosts.IndexOf(selected); if (beforeTheme != settings.Theme) Rebuild(); if (before != settings.StartupEnabled) { try { var result = await startup.ApplyAsync(settings.StartupEnabled, stop.Token); status.Text = result.Message; } catch (Exception ex) { settings.StartupEnabled = before; try { await store.SaveAsync(settings); } catch { } status.Text = "Startup setting was not applied: " + ex.Message; } } }); AddHeader(header, config, 3);
        AddHeader(header, Button("Hide", () => { Hide(); return Task.CompletedTask; }), 4); root.Children.Add(header);
        editHint.Child = new TextBlock { Text = "EDIT MODE  ·  Press and drag a card to reorder  ·  Short / Long controls its fixed grid span", TextWrapping = TextWrapping.Wrap }; editHint.Margin = new Thickness(28, 0, 28, 12); editHint.IsVisible = false; root.Children.Add(editHint); Grid.SetRow(editHint, 1);
        var scroll = new ScrollViewer { Content = canvas, Margin = new Thickness(28, 0, 28, 18), HorizontalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Disabled }; scroll.SizeChanged += (_, _) => Rebuild(); root.Children.Add(scroll); Grid.SetRow(scroll, 2);
        status.Text = store.LoadWarning is null ? "Starting collectors…" : "Settings could not be loaded: " + store.LoadWarning; status.Foreground = Brushes.LightGray; status.FontSize = 11; status.Margin = new Thickness(28, 0, 28, 12); root.Children.Add(status); Grid.SetRow(status, 3);
        Content = root; Rebuild(); Opened += (_, _) => StartPolling(); Closed += (_, _) => Stop();
    }
    private static Button Button(string label, Func<Task> action) { var b = new Button { Content = label, VerticalAlignment = VerticalAlignment.Center }; b.Click += async (_, _) => await action(); return b; }
    private static void AddHeader(Grid grid, Control control, int column) { control.Margin = new Thickness(8, 0, 0, 0); grid.Children.Add(control); Grid.SetColumn(control, column); }
    private void Rebuild()
    {
        if (dragged is not null) return;
        palette = Palettes.Get(settings.Theme); Background = new SolidColorBrush(Color.Parse(palette.Background)); Foreground = new SolidColorBrush(Color.Parse(palette.Text)); RequestedThemeVariant = settings.Theme == "light" ? Avalonia.Styling.ThemeVariant.Light : Avalonia.Styling.ThemeVariant.Dark; status.Foreground = new SolidColorBrush(Color.Parse(palette.Secondary));
        var width = Math.Max(560, (canvas.Parent as Control)?.Bounds.Width ?? 1000); var columns = width >= 950 ? 4 : 2; var cellWidth = (width - (columns - 1) * Gap) / columns;
        canvas.Children.Clear(); values.Clear(); views.Clear(); var packed = GridLayout.Pack(settings.Layout, columns); canvas.Height = (packed.Max(p => p.Row) + 1) * (CellHeight + Gap);
        foreach (var p in packed)
        {
            var def = Cards.All.First(c => c.Id == p.Id);
            var border = new Border { Width = p.Span * cellWidth + (p.Span - 1) * Gap, Height = CellHeight, CornerRadius = new CornerRadius(18), Padding = new Thickness(18, 14), Background = palette.CardBrush, BorderBrush = new SolidColorBrush(Color.Parse(palette.Rim)), BorderThickness = new Thickness(1), ClipToBounds = true };
            var value = new TextBlock { Text = "Unavailable", FontSize = 25, FontWeight = FontWeight.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis }; var detail = new TextBlock { Text = "Waiting for a real sensor sample", FontSize = 11, Foreground = new SolidColorBrush(Color.Parse(palette.Secondary)), TextTrimming = TextTrimming.CharacterEllipsis, MaxHeight = 32, TextWrapping = TextWrapping.Wrap };
            var content = new Grid { RowDefinitions = new RowDefinitions("Auto,*,Auto") }; var title = new TextBlock { Text = def.Title, FontSize = 11, Foreground = new SolidColorBrush(Color.Parse(palette.Accent)), FontWeight = FontWeight.Bold }; content.Children.Add(title); content.Children.Add(value); Grid.SetRow(value, 1); value.VerticalAlignment = VerticalAlignment.Center; content.Children.Add(detail); Grid.SetRow(detail, 2);
            if (edit.IsChecked == true)
            {
                detail.IsVisible = false; var shape = Button(p.Span == 2 ? "Long → Short" : "Short → Long", async () => { settings.Layout.First(c => c.Id == p.Id).Span = p.Span == 2 ? 1 : 2; Rebuild(); await Save(); }); shape.FontSize = 10; shape.Padding = new Thickness(7, 3); shape.HorizontalAlignment = HorizontalAlignment.Right; content.Children.Add(shape); Grid.SetRow(shape, 2);
            }
            border.Child = content; values[def.Metric] = (value, detail); views[p.Id] = border; Canvas.SetLeft(border, p.Column * (cellWidth + Gap)); Canvas.SetTop(border, p.Row * (CellHeight + Gap)); canvas.Children.Add(border);
            border.PointerPressed += (_, e) =>
            {
                if (!e.GetCurrentPoint(border).Properties.IsLeftButtonPressed || FindAncestor<Button>(e.Source as Control) is not null) return;
                if (edit.IsChecked == true) { dragged = p.Id; draggedView = border; dragStart = e.GetPosition(canvas); border.Opacity = .65; border.ZIndex = 10; e.Pointer.Capture(border); e.Handled = true; }
            };
            border.PointerMoved += (_, e) => { if (draggedView != border) return; var point = e.GetPosition(canvas); Canvas.SetLeft(border, Math.Max(0, point.X - border.Width / 2)); Canvas.SetTop(border, Math.Max(0, point.Y - 35)); };
            border.PointerReleased += async (_, e) =>
            {
                if (draggedView == border)
                {
                    var point = e.GetPosition(canvas); var target = packed.OrderBy(x => Math.Pow(x.Column * (cellWidth + Gap) + (x.Span * cellWidth) / 2 - point.X, 2) + Math.Pow(x.Row * (CellHeight + Gap) + CellHeight / 2 - point.Y, 2)).First();
                    var old = settings.Layout.FindIndex(x => x.Id == p.Id); var index = settings.Layout.FindIndex(x => x.Id == target.Id); var moved = settings.Layout[old]; settings.Layout.RemoveAt(old); settings.Layout.Insert(index, moved);
                    dragged = null; draggedView = null; e.Pointer.Capture(null); Rebuild(); await Save(); e.Handled = true;
                }
                else if (edit.IsChecked != true && e.GetCurrentPoint(border).Properties.PointerUpdateKind == PointerUpdateKind.LeftButtonReleased) await ShowDetail(def);
            };
            border.PointerCaptureLost += (_, _) => { if (draggedView == border) { dragged = null; draggedView = null; Rebuild(); } };
        }
        if (lastSnapshot is not null) Apply(lastSnapshot);
    }
    private static T? FindAncestor<T>(Control? source) where T : Control
    {
        Avalonia.Visual? current = source;
        while (current is not null)
        {
            if (current is T found) return found;
            current = Avalonia.VisualTree.VisualExtensions.GetVisualParent(current);
        }
        return null;
    }
    private Task ShowDetail(CardDefinition def)
    {
        var metric = lastSnapshot?.Metrics.GetValueOrDefault(def.Metric) ?? Metric.Missing("No sample received.");
        var window = new Window { Title = def.Title + " · " + selected.Name, Width = 520, Height = 320, WindowStartupLocation = WindowStartupLocation.CenterOwner, Content = new StackPanel { Margin = new Thickness(28), Spacing = 16, Children = { new TextBlock { Text = def.Title, Foreground = Brushes.LightSkyBlue }, new TextBlock { Text = metric.Value, FontSize = 32 }, new TextBlock { Text = metric.Detail, TextWrapping = TextWrapping.Wrap }, new TextBlock { Text = $"Source: {(selected.Remote ? "strict SSH / fixed Linux probe" : "local OS / driver sensor")}\nSample: {lastSnapshot?.At.ToString("O") ?? "none"}\nMissing sensor values are never estimated unless explicitly labelled.", TextWrapping = TextWrapping.Wrap, Foreground = Brushes.Gray, FontSize = 11 } } } }; return window.ShowDialog(this);
    }
    private void StartPolling()
    {
        var poll = new Services.PollingService(new SystemMetricProvider());
        pollingTask = Task.Run(() => poll.RunAsync(() => selected, () => settings.PollSeconds, snapshot => { Dispatcher.UIThread.Post(() => { if (snapshot.HostId == selected.Id) Apply(snapshot); }); }, stop.Token));
    }
    private void Apply(Snapshot snapshot)
    {
        lastSnapshot = snapshot; status.Text = $"{snapshot.Status} · {snapshot.At.LocalDateTime:HH:mm:ss} · Click a card for hardware details";
        foreach (var (key, metric) in snapshot.Metrics) if (values.TryGetValue(key, out var v)) { v.Value.Text = metric.Value; v.Detail.Text = metric.Detail; v.Value.Foreground = new SolidColorBrush(Color.Parse(metric.Available ? palette.Text : palette.Secondary)); }
    }
    private async Task Save() { try { await store.SaveAsync(settings); } catch (Exception ex) { status.Text = "Settings save failed: " + ex.Message; } }
    public void Stop() { if (!stop.IsCancellationRequested) stop.Cancel(); }
}
