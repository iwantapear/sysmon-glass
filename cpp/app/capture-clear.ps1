$ErrorActionPreference='Continue'
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MoveShot {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
}
'@
$p = Get-Process sysmon -ErrorAction SilentlyContinue | Select-Object -First 1
if(-not $p){ throw 'native app not running' }
[MoveShot]::SetWindowPos($p.MainWindowHandle, [IntPtr]::Zero, 1320, 40, 0, 0, 1) | Out-Null
Start-Sleep 1
$r = New-Object MoveShot+RECT
[MoveShot]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
Write-Host ("window {0}x{1} at {2},{3}" -f $w,$h,$r.Left,$r.Top)
$bmp = New-Object System.Drawing.Bitmap $w,$h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left,$r.Top,0,0,$bmp.Size)
$bmp.Save('<repo>\evidence\bug-done-20261108\cpp-bottom-clear.png',[System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose();$bmp.Dispose()
Write-Host 'captured'
