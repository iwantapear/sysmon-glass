$ErrorActionPreference='Continue'
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ShotProbe2 {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
}
'@
$env:SYSMON_CONFIG_HOME = Join-Path $env:TEMP 'sysmon-cpp-shot'
New-Item -ItemType Directory -Path $env:SYSMON_CONFIG_HOME -Force | Out-Null
Write-Host 'starting'
$p = Start-Process -FilePath '<repo>\cpp\app\sysmon.exe' -PassThru
Start-Sleep -Seconds 5
Write-Host ("pid alive: " + (-not $p.HasExited))
$proc = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
$handle = 0
if($proc){ $handle = $proc.MainWindowHandle }
Write-Host ("handle=" + $handle)
if($handle -ne 0){
    $rect = New-Object ShotProbe2+RECT
    [ShotProbe2]::GetWindowRect($handle, [ref]$rect) | Out-Null
    $w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
    Write-Host ("rect {0},{1} {2}x{3} visible={4}" -f $rect.Left,$rect.Top,$w,$h,[ShotProbe2]::IsWindowVisible($handle))
    if($w -gt 0 -and $h -gt 0){
        $bmp = New-Object System.Drawing.Bitmap $w, $h
        $graphics = [System.Drawing.Graphics]::FromImage($bmp)
        $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
        $bmp.Save('<repo>\evidence\bug-done-20261108\cpp-app.png', [System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose(); $bmp.Dispose()
        Write-Host 'captured'
    }
}
Write-Host 'stopping'
if(-not $p.HasExited){ Stop-Process -Id $p.Id -Force }
Write-Host 'done'
