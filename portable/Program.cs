using Avalonia;
using System;
using SysMon.Glass.Core;

namespace SysMon.Glass;
public static class Program
{
    public static void Main(string[] args)
    {
        if (Array.Exists(args, a => a.Equals("--self-test", StringComparison.OrdinalIgnoreCase)))
        { SelfTest.Run(); return; }
        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
    }
    public static AppBuilder BuildAvaloniaApp() => AppBuilder.Configure<App>().UsePlatformDetect().LogToTrace();
}
