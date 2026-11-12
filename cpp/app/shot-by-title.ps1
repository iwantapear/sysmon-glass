param([string]$ProcessName = 'sysmon')
$ErrorActionPreference='Continue'
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class ByTitle {
    public delegate bool EnumProc(IntPtr h, IntPtr p);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
}
'@
$script:targetPid = [uint32](Get-Process $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1).Id
if($ProcessName -eq 'SysMon.Glass'){
    $launcher = Get-Process SysMon.Glass -ErrorAction SilentlyContinue | Select-Object -First 1
    if($launcher){
        $child = Get-CimInstance Win32_Process -Filter ("ParentProcessId="+$launcher.Id) | Where-Object Name -eq 'pwsh.exe' | Select-Object -First 1
        if($child){ $script:targetPid = [uint32]$child.ProcessId }
    }
}
$script:found = [IntPtr]::Zero
$callback = [ByTitle+EnumProc]{
    param($h,$p)
    $sb = New-Object System.Text.StringBuilder 256
    [ByTitle]::GetWindowText($h, $sb, 256) | Out-Null
    $owner = [uint32]0
    [ByTitle]::GetWindowThreadProcessId($h, [ref]$owner) | Out-Null
    if($owner -eq $script:targetPid -and [ByTitle]::IsWindowVisible($h)){ $script:found = $h; return $false }
    return $true
}
[ByTitle]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
if($script:found -eq [IntPtr]::Zero){ Write-Host 'window not found'; exit 1 }
$rect = New-Object ByTitle+RECT
[ByTitle]::GetWindowRect($script:found, [ref]$rect) | Out-Null
$w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
Write-Host ("window at {0},{1} size {2}x{3}" -f $rect.Left,$rect.Top,$w,$h)
if($w -le 0 -or $h -le 0){ exit 1 }
$bmp = New-Object System.Drawing.Bitmap $w, $h
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
$bmp.Save('<repo>\evidence\bug-done-20261108\cpp-app.png', [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose(); $bmp.Dispose()
Write-Host 'captured'
