$ErrorActionPreference='Continue'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NativeWindowProbe {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern int GetWindowRgn(IntPtr h, IntPtr region);
    [DllImport("user32.dll")] public static extern int GetRgnBox(IntPtr region, out RECT r);
    [DllImport("user32.dll")] public static extern IntPtr CreateRectRgn(int l,int t,int r,int b);
    [DllImport("user32.dll")] public static extern bool DeleteObject(IntPtr obj);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern long GetWindowLongPtr(IntPtr h, int index);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int value, int size);
}
'@
$p = Get-Process sysmon -ErrorAction SilentlyContinue | Select-Object -First 1
if(-not $p){ throw 'native app not running' }
$h = $p.MainWindowHandle
$r = New-Object NativeWindowProbe+RECT
[NativeWindowProbe]::GetWindowRect($h, [ref]$r) | Out-Null
$region = [NativeWindowProbe]::CreateRectRgn(0,0,0,0)
$type = [NativeWindowProbe]::GetWindowRgn($h, $region)
$box = New-Object NativeWindowProbe+RECT
if($type -ne 0){ [NativeWindowProbe]::GetRgnBox($region, [ref]$box) | Out-Null }
[NativeWindowProbe]::DeleteObject($region) | Out-Null
$ex = [NativeWindowProbe]::GetWindowLongPtr($h, -20)
$style = [NativeWindowProbe]::GetWindowLongPtr($h, -16)
$transparent = 0
[NativeWindowProbe]::DwmGetWindowAttribute($h, 38, [ref]$transparent, 4) | Out-Null
Write-Host ("rect={0},{1}-{2},{3} visible={4} minimized={5}" -f $r.Left,$r.Top,$r.Right,$r.Bottom,[NativeWindowProbe]::IsWindowVisible($h),[NativeWindowProbe]::IsIconic($h))
Write-Host ("style=0x{0:X} ex=0x{1:X} regionType={2} regionBox={3},{4}-{5},{6} backdropAttr={7}" -f $style,$ex,$type,$box.Left,$box.Top,$box.Right,$box.Bottom,$transparent)
