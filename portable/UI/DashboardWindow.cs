using System.Globalization;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Shapes;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using SysMon.Glass.Core;
using SysMon.Glass.Platform;

namespace SysMon.Glass.UI;

public sealed class DashboardWindow : Window
{
    private const double CellHeight = 172, Gap = 12, SparkWidth = 128, SparkHeight = 26;
    private const int HistoryLimit = 60;

    private readonly UserSettings settings;
    private readonly SettingsStore store = new();
    private readonly CancellationTokenSource stop = new();
    private readonly Canvas canvas = new();
    private readonly TextBlock status = new();
    private readonly ComboBox hostPicker = new() { MinWidth = 165 };
    private readonly ToggleSwitch edit = new();
    private readonly Border editHint = new() { Padding = new Thickness(12), CornerRadius = new CornerRadius(10) };
    private readonly Dictionary<string, CardView> views = [];
    private readonly Dictionary<string, List<double>> history = [];
    private readonly Dictionary<string, IBrush> brushCache = [];
    private readonly UserStartupAdapter startup = new();
    private HostProfile selected;
    private Snapshot? lastSnapshot;
    private ThemePalette palette;
    private Task? pollingTask;
    private string? dragged;
    private Point dragStart;
    private Border? draggedView;
    private int lastColumns;

    /// <summary>Widgets of one card; kept so a tick only touches text, never the tree.</summary>
    private sealed class CardView
    {
        public required Border Border { get; init; }
        public required TextBlock Value { get; init; }
        public required TextBlock Unit { get; init; }
        public required TextBlock Detail { get; init; }
        public required TextBlock Stats { get; init; }
        public required Polyline Spark { get; init; }
    }

    public DashboardWindow()
    {
        settings = store.Load();
        L10n.Override = settings.Language;
        palette = Palettes.Get(settings.Theme);
        selected = settings.Hosts.FirstOrDefault(h => h.Id == settings.SelectedHost) ?? settings.Hosts[0];

        Title = "SysMon Glass";
        Width = 1180; Height = 880; MinWidth = 640; MinHeight = 480;
        ShowInTaskbar = true;
        TransparencyLevelHint = [WindowTransparencyLevel.AcrylicBlur, WindowTransparencyLevel.Transparent];

        var root = new Grid { RowDefinitions = new RowDefinitions("Auto,Auto,*,Auto") };
        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,Auto,Auto,Auto"), Margin = new Thickness(28, 24, 28, 16) };
        header.Children.Add(new StackPanel
        {
            Spacing = 3,
            Children =
            {
                new TextBlock { Text = L10n.T("header.eyebrow"), Foreground = Brushes.LightSkyBlue, FontSize = 11 },
                new TextBlock { Text = L10n.T("header.title"), FontSize = 29, FontWeight = FontWeight.SemiBold }
            }
        });

        hostPicker.ItemsSource = settings.Hosts.Select(h => h.Name).ToArray();
        hostPicker.SelectedIndex = settings.Hosts.IndexOf(selected);
        hostPicker.VerticalAlignment = VerticalAlignment.Center;
        hostPicker.SelectionChanged += async (_, _) =>
        {
            if (hostPicker.SelectedIndex < 0) return;
            selected = settings.Hosts[hostPicker.SelectedIndex];
            settings.SelectedHost = selected.Id;
            lastSnapshot = null;
            history.Clear();
            foreach (var view in views.Values)
            {
                view.Value.Text = L10n.T("state.unavailable");
                view.Detail.Text = L10n.T("state.waiting");
                view.Stats.Text = "";
                view.Spark.Points = [];
            }
            await Save();
        };
        AddHeader(header, hostPicker, 1);

        edit.Content = L10n.T("btn.edit");
        edit.VerticalAlignment = VerticalAlignment.Center;
        edit.IsCheckedChanged += (_, _) => { editHint.IsVisible = edit.IsChecked == true; Rebuild(force: true); };
        AddHeader(header, edit, 2);

        AddHeader(header, Button(L10n.T("btn.hosts"), OpenSettingsAsync), 3);
        AddHeader(header, Button(L10n.T("btn.hide"), () => { Hide(); return Task.CompletedTask; }), 4);
        root.Children.Add(header);

        editHint.Child = new TextBlock { Text = L10n.T("edit.hint"), TextWrapping = TextWrapping.Wrap };
        editHint.Margin = new Thickness(28, 0, 28, 12);
        editHint.IsVisible = false;
        root.Children.Add(editHint);
        Grid.SetRow(editHint, 1);

        var scroll = new ScrollViewer
        {
            Content = canvas,
            Margin = new Thickness(28, 0, 28, 18),
            HorizontalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Disabled
        };
        // Rebuilding tears down every card; only react when the column count really changes.
        scroll.SizeChanged += (_, _) => Rebuild();
        root.Children.Add(scroll);
        Grid.SetRow(scroll, 2);

        status.Text = store.LoadWarning is null ? L10n.T("state.starting") : L10n.T("state.loadFailed") + store.LoadWarning;
        status.Foreground = Brushes.LightGray;
        status.FontSize = 11;
        status.Margin = new Thickness(28, 0, 28, 12);
        root.Children.Add(status);
        Grid.SetRow(status, 3);

        Content = root;
        Rebuild(force: true);
        Opened += (_, _) => StartPolling();
        Closed += (_, _) => Stop();
    }

    // ---------------------------------------------------------------- header helpers

    private static Button Button(string label, Func<Task> action)
    {
        var button = new Button { Content = label, VerticalAlignment = VerticalAlignment.Center };
        button.Click += async (_, _) => await action();
        return button;
    }

    private static void AddHeader(Grid grid, Control control, int column)
    {
        control.Margin = new Thickness(8, 0, 0, 0);
        grid.Children.Add(control);
        Grid.SetColumn(control, column);
    }

    private async Task OpenSettingsAsync()
    {
        var beforeStartup = settings.StartupEnabled;
        var beforeTheme = settings.Theme;
        var beforeLanguage = settings.Language;
        await new SettingsWindow(settings, store).ShowDialog(this);

        selected = settings.Hosts.FirstOrDefault(h => h.Id == selected.Id) ?? settings.Hosts[0];
        palette = Palettes.Get(settings.Theme);
        if (beforeLanguage != settings.Language)
        {
            L10n.Override = settings.Language;
            ApplyLanguage();
        }
        hostPicker.ItemsSource = settings.Hosts.Select(h => h.Name).ToArray();
        hostPicker.SelectedIndex = settings.Hosts.IndexOf(selected);
        if (beforeTheme != settings.Theme) Rebuild(force: true);

        if (beforeStartup != settings.StartupEnabled)
        {
            try
            {
                var result = await startup.ApplyAsync(settings.StartupEnabled, stop.Token);
                status.Text = result.Message;
            }
            catch (Exception ex)
            {
                settings.StartupEnabled = beforeStartup;
                try { await store.SaveAsync(settings); } catch { }
                status.Text = L10n.T("state.startupFailed") + ex.Message;
            }
        }
    }

    /// <summary>Re-label static chrome after a language change (cards are rebuilt).</summary>
    private void ApplyLanguage()
    {
        edit.Content = L10n.T("btn.edit");
        editHint.Child = new TextBlock { Text = L10n.T("edit.hint"), TextWrapping = TextWrapping.Wrap };
        Rebuild(force: true);
    }

    // ---------------------------------------------------------------- layout

    /// <summary>
    /// Rebuilds the card tree. Skip unless the column count changed (or forced):
    /// SizeChanged fires on every pixel of a resize, and a full teardown per pixel
    /// was the main source of jitter on Linux.
    /// </summary>
    private void Rebuild(bool force = false)
    {
        if (dragged is not null) return;
        var available = (canvas.Parent as Control)?.Bounds.Width ?? 1000;
        var columns = Math.Max(2, available >= 950 ? 4 : 2);
        if (!force && columns == lastColumns && canvas.Children.Count > 0) return;
        lastColumns = columns;

        palette = Palettes.Get(settings.Theme);
        Background = Brush(Clear(palette.Background));
        Foreground = Brush(Clear(palette.Text));
        RequestedThemeVariant = settings.Theme == "light" ? Avalonia.Styling.ThemeVariant.Light : Avalonia.Styling.ThemeVariant.Dark;
        status.Foreground = Brush(palette.Secondary);

        var width = Math.Max(560, available);
        var columnsWidth = (width - (columns - 1) * Gap) / columns;
        canvas.Children.Clear();
        views.Clear();
        var packed = GridLayout.Pack(settings.Layout, columns);
        canvas.Height = (packed.Max(p => p.Row) + 1) * (CellHeight + Gap);

        foreach (var placement in packed)
        {
            var definition = Cards.All.First(c => c.Id == placement.Id);
            var card = BuildCard(definition, placement, columnsWidth, packed);
            canvas.Children.Add(card.Border);
            views[definition.Metric] = card;
        }
        if (lastSnapshot is not null) Apply(lastSnapshot);
    }

    private CardView BuildCard(CardDefinition definition, Placement placement, double columnWidth, List<Placement> packed)
    {
        var accent = Brush(definition.Accent);
        var radius = new CornerRadius(18);

        var dot = new Ellipse { Width = 8, Height = 8, Fill = accent, Margin = new Thickness(0, 0, 9, 0), VerticalAlignment = VerticalAlignment.Center };
        var title = new TextBlock
        {
            Text = definition.Title,
            FontSize = 11.5,
            FontWeight = FontWeight.Bold,
            Foreground = accent,
            VerticalAlignment = VerticalAlignment.Center
        };
        var head = new StackPanel { Orientation = Orientation.Horizontal, Children = { dot, title } };

        var value = new TextBlock
        {
            Text = L10n.T("state.unavailable"),
            FontSize = 38,
            FontWeight = FontWeight.SemiBold,
            VerticalAlignment = VerticalAlignment.Bottom,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        var unit = new TextBlock
        {
            FontSize = 12.5,
            Foreground = Brush(palette.Secondary),
            Margin = new Thickness(7, 0, 0, 6),
            VerticalAlignment = VerticalAlignment.Bottom
        };
        var valueLine = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Left,
            Children = { value, unit }
        };

        var stats = new TextBlock
        {
            FontSize = 10.5,
            LineHeight = 14,
            TextAlignment = TextAlignment.Right,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = Brush(palette.Secondary),
            Text = ""
        };
        var body = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        body.Children.Add(valueLine);
        body.Children.Add(stats);
        Grid.SetColumn(stats, 1);

        var detail = new TextBlock
        {
            Text = L10n.T("state.waitingSample"),
            FontSize = 11,
            Foreground = Brush(palette.Secondary),
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center
        };
        var spark = new Polyline
        {
            Stroke = accent,
            StrokeThickness = 2,
            Opacity = 0.85,
            Width = SparkWidth,
            Height = SparkHeight,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            IsHitTestVisible = false,
            Points = []
        };
        var footer = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        footer.Children.Add(detail);
        footer.Children.Add(spark);
        Grid.SetColumn(spark, 1);

        var content = new Grid
        {
            RowDefinitions = new RowDefinitions("Auto,*,Auto"),
            Children = { head, body, footer }
        };
        Grid.SetRow(body, 1);
        Grid.SetRow(footer, 2);

        if (edit.IsChecked == true)
        {
            spark.IsVisible = false;
            var shape = Button(placement.Span == 2 ? L10n.T("shape.long") : L10n.T("shape.short"), async () =>
            {
                settings.Layout.First(c => c.Id == placement.Id).Span = placement.Span == 2 ? 1 : 2;
                Rebuild(force: true);
                await Save();
            });
            shape.FontSize = 10;
            shape.Padding = new Thickness(7, 3);
            shape.HorizontalAlignment = HorizontalAlignment.Right;
            footer.Children.Add(shape);
            Grid.SetColumn(shape, 1);
            spark.IsVisible = false;
        }

        var gloss = new Border
        {
            Height = 54,
            CornerRadius = new CornerRadius(18, 18, 0, 0),
            VerticalAlignment = VerticalAlignment.Top,
            IsHitTestVisible = false,
            Background = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(0.6, 1, RelativeUnit.Relative),
                GradientStops = [new(Color.Parse("#38FFFFFF"), 0), new(Color.Parse("#00FFFFFF"), 1)]
            }
        };

        var surface = new Grid { Children = { gloss, content } };

        var border = new Border
        {
            Width = placement.Span * columnWidth + (placement.Span - 1) * Gap,
            Height = CellHeight,
            CornerRadius = radius,
            Padding = new Thickness(18, 13, 18, 13),
            Background = palette.CardBrush,
            BorderBrush = Brush(palette.Rim),
            BorderThickness = new Thickness(1.2),
            ClipToBounds = true,
            Child = surface
        };
        Canvas.SetLeft(border, placement.Column * (columnWidth + Gap));
        Canvas.SetTop(border, placement.Row * (CellHeight + Gap));

        var view = new CardView { Border = border, Value = value, Unit = unit, Detail = detail, Stats = stats, Spark = spark };

        border.PointerPressed += (_, e) =>
        {
            if (!e.GetCurrentPoint(border).Properties.IsLeftButtonPressed) return;
            if (FindAncestor<Button>(e.Source as Control) is not null) return;
            if (edit.IsChecked != true) return;
            dragged = placement.Id;
            draggedView = border;
            dragStart = e.GetPosition(canvas);
            border.Opacity = .65;
            border.ZIndex = 10;
            e.Pointer.Capture(border);
            e.Handled = true;
        };
        border.PointerMoved += (_, e) =>
        {
            if (draggedView != border) return;
            var point = e.GetPosition(canvas);
            Canvas.SetLeft(border, Math.Max(0, point.X - border.Width / 2));
            Canvas.SetTop(border, Math.Max(0, point.Y - 35));
        };
        border.PointerReleased += async (_, e) =>
        {
            if (draggedView == border)
            {
                var point = e.GetPosition(canvas);
                var target = packed.OrderBy(x =>
                    Math.Pow(x.Column * (columnWidth + Gap) + x.Span * columnWidth / 2 - point.X, 2) +
                    Math.Pow(x.Row * (CellHeight + Gap) + CellHeight / 2 - point.Y, 2)).First();
                var oldIndex = settings.Layout.FindIndex(x => x.Id == placement.Id);
                var newIndex = settings.Layout.FindIndex(x => x.Id == target.Id);
                var moved = settings.Layout[oldIndex];
                settings.Layout.RemoveAt(oldIndex);
                settings.Layout.Insert(newIndex, moved);
                dragged = null;
                draggedView = null;
                e.Pointer.Capture(null);
                Rebuild(force: true);
                await Save();
                e.Handled = true;
            }
            else if (edit.IsChecked != true && e.GetCurrentPoint(border).Properties.PointerUpdateKind == PointerUpdateKind.LeftButtonReleased)
            {
                await ShowDetail(definition);
            }
        };
        border.PointerCaptureLost += (_, _) =>
        {
            if (draggedView != border) return;
            dragged = null;
            draggedView = null;
            Rebuild(force: true);
        };
        return view;
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

    private Task ShowDetail(CardDefinition definition)
    {
        var metric = lastSnapshot?.Metrics.GetValueOrDefault(definition.Metric) ?? Metric.Missing(L10n.T("detail.noSample"));
        var source = selected.Remote ? L10n.T("detail.sourceRemote") : L10n.T("detail.sourceLocal");
        var window = new Window
        {
            Title = definition.Title + " · " + selected.Name,
            Width = 520,
            Height = 320,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Content = new StackPanel
            {
                Margin = new Thickness(28),
                Spacing = 16,
                Children =
                {
                    new TextBlock { Text = definition.Title, Foreground = Brushes.LightSkyBlue },
                    new TextBlock { Text = metric.Value, FontSize = 32 },
                    new TextBlock { Text = metric.Detail, TextWrapping = TextWrapping.Wrap },
                    new TextBlock
                    {
                        Text = $"{source}\n{string.Format(CultureInfo.CurrentCulture, L10n.T("detail.sample"), lastSnapshot?.At.ToString("O") ?? "-")}\n{L10n.T("detail.note")}",
                        TextWrapping = TextWrapping.Wrap,
                        Foreground = Brushes.Gray,
                        FontSize = 11
                    }
                }
            }
        };
        return window.ShowDialog(this);
    }

    // ---------------------------------------------------------------- polling / rendering

    private void StartPolling()
    {
        var poll = new Services.PollingService(new SystemMetricProvider());
        pollingTask = Task.Run(() => poll.RunAsync(
            () => selected,
            () => settings.PollSeconds,
            snapshot => Dispatcher.UIThread.Post(() => { if (snapshot.HostId == selected.Id) Apply(snapshot); }),
            stop.Token));
    }

    private void Apply(Snapshot snapshot)
    {
        lastSnapshot = snapshot;
        status.Text = string.Format(CultureInfo.CurrentCulture, L10n.T("status.line"), snapshot.Status, snapshot.At.LocalDateTime.ToString("HH:mm:ss"));

        foreach (var (key, metric) in snapshot.Metrics)
        {
            if (!views.TryGetValue(key, out var view)) continue;
            if (view.Value.Text != metric.Value) view.Value.Text = metric.Value;
            if (view.Detail.Text != metric.Detail) view.Detail.Text = metric.Detail;
            view.Value.Foreground = Brush(metric.Available ? palette.Text : palette.Secondary);
            UpdateSeries(key, metric, view);
        }
    }

    /// <summary>Rolling max/min/mean plus a sparkline, matching the Windows cards.</summary>
    private void UpdateSeries(string key, Metric metric, CardView view)
    {
        if (!metric.Available || !TryNumber(metric.Value, out var number))
        {
            view.Stats.Text = "";
            view.Spark.Points = [];
            history.Remove(key);
            return;
        }

        if (!history.TryGetValue(key, out var samples))
        {
            samples = new List<double>(HistoryLimit);
            history[key] = samples;
        }
        samples.Add(number);
        if (samples.Count > HistoryLimit) samples.RemoveAt(0);

        var max = samples[0];
        var min = samples[0];
        var sum = 0d;
        foreach (var sample in samples)
        {
            if (sample > max) max = sample;
            if (sample < min) min = sample;
            sum += sample;
        }
        var mean = sum / samples.Count;

        view.Stats.Text = $"{L10n.T("stats.max")} {FormatNumber(max)}\n{L10n.T("stats.min")} {FormatNumber(min)}\n{L10n.T("stats.avg")} {FormatNumber(mean)}";

        if (samples.Count < 3)
        {
            view.Spark.Points = [];
            return;
        }
        var high = max;
        var low = min;
        if (high - low < 2) high = low + 2;
        var points = new List<Point>(samples.Count);
        for (var i = 0; i < samples.Count; i++)
        {
            var x = SparkWidth * i / (samples.Count - 1);
            var y = 2 + (SparkHeight - 4) - (SparkHeight - 4) * (samples[i] - low) / (high - low);
            points.Add(new Point(x, y));
        }
        view.Spark.Points = points;
    }

    private static string FormatNumber(double value) => Math.Abs(value) < 10
        ? value.ToString("N1", CultureInfo.CurrentCulture)
        : value.ToString("N0", CultureInfo.CurrentCulture);

    /// <summary>Tolerant parse: "1,411" / "3.0" / "62%" / "49.5 GB" -> number.</summary>
    private static bool TryNumber(string text, out double value)
    {
        value = 0;
        if (string.IsNullOrWhiteSpace(text)) return false;
        var digits = new System.Text.StringBuilder();
        var seenDot = false;
        foreach (var ch in text)
        {
            if (char.IsDigit(ch)) { digits.Append(ch); continue; }
            if (ch == '.' && !seenDot && digits.Length > 0) { digits.Append('.'); seenDot = true; continue; }
            if (ch == ',' || ch == ' ') continue;
            break;
        }
        return digits.Length > 0 && double.TryParse(digits.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out value);
    }

    /// <summary>Brushes are immutable here; caching keeps a tick allocation-free.</summary>
    private IBrush Brush(string color)
    {
        if (brushCache.TryGetValue(color, out var cached)) return cached;
        var brush = new SolidColorBrush(Color.Parse(color));
        brushCache[color] = brush;
        return brush;
    }

    /// <summary>Card surfaces stay fully opaque so they keep crisp text.</summary>
    private static string Clear(string color) => color.Length == 9 ? "#FF" + color[3..] : color;

    private async Task Save()
    {
        try { await store.SaveAsync(settings); }
        catch (Exception ex) { status.Text = L10n.T("state.saveFailed") + ex.Message; }
    }

    public void Stop()
    {
        if (!stop.IsCancellationRequested) stop.Cancel();
    }
}
