using Avalonia;
using Avalonia.Media;
namespace SysMon.Glass.UI;
public record ThemePalette(string Id, string Background, string CardStart, string CardEnd, string Rim, string Text, string Secondary, string Accent)
{
    public IBrush CardBrush => new LinearGradientBrush { StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative), EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative), GradientStops = [new(Color.Parse(CardStart), 0), new(Color.Parse(CardEnd), 1)] };
}
public static class Palettes
{
    // Ported from modules/Theme.ps1: same eleven palette ids and primary colors.
    public static readonly ThemePalette[] All = [
        new("light", "#D0DCEEFF", "#F9FBFDFF", "#F0E8FAFF", "#A8BECFE4", "#FF19334F", "#FF45617E", "#FF2478C2"),
        new("dark", "#D01A2C50", "#DC38607A", "#D42C6A70", "#8FBFD5EE", "#FFF5F9FF", "#FFE1ECF8", "#FF86C9FF"),
        new("sunset", "#D06B2C6E", "#E0B05878", "#D8A04070", "#A8FFE0C8", "#FFF5F9FF", "#FFE1ECF8", "#FFFFD9A8"),
        new("rose", "#D0A0306A", "#E0C86880", "#D8B8607A", "#A8FFD8F0", "#FFF5F9FF", "#FFE1ECF8", "#FFFFD0E8"),
        new("violet", "#D04A2C8E", "#E05A4498", "#D8546C90", "#A8D0E8FF", "#FFF5F9FF", "#FFE1ECF8", "#FFC8A8FF"),
        new("aurora", "#D0146858", "#DE14705E", "#D4208064", "#9AF0E0D8", "#FFF5F9FF", "#FFE1ECF8", "#FF8FFFE0"),
        new("neon", "#D007081C", "#DC141438", "#D8183048", "#A800F0FF", "#FFF5F9FF", "#FFE1ECF8", "#FF00E5FF"),
        new("flame", "#D0A81622", "#E0C22030", "#D5B02030", "#A8FFD0D0", "#FFF5F9FF", "#FFE1ECF8", "#FFFFB8A8"),
        new("ocean", "#D01A2E55", "#E0294A75", "#DC1F4260", "#9AB2D7FF", "#FFF5F9FF", "#FFE1ECF8", "#FF95CFFF"),
        new("forest", "#D019392F", "#E035584B", "#D3274B3E", "#A6C8E9D4", "#FFF2FFF7", "#FFE0EFE4", "#FF9DE6C3"),
        new("amber", "#D04C3028", "#E06C4D3F", "#DB4D3836", "#A5EBD0AF", "#FFFFFAEF", "#FFF4E3D5", "#FFFFCC91")];
    public static ThemePalette Get(string id) => All.FirstOrDefault(p => p.Id == id) ?? All[1];
}
