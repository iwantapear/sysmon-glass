$ErrorActionPreference='Stop'
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Run with -STA'}
$AppRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $AppRoot 'glass.ps1') -PrepareOnly
$window.Show(); Set-DesktopMode $false
$window.UpdateLayout()
Restore-NormalCardLayout
$window.UpdateLayout()
$key='cpu'
$before=Get-CardShape $key
# Open the flyout, then click its explicit shape button exactly as a user would.
Show-CardDetail $key ([Drawing.Point]::new(400,300))
$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
$popup=$script:cardDetailPopup
if($null -eq $popup -or -not $popup.IsOpen){throw 'Detail flyout did not open'}
$stack=$popup.Child.Child
$button=$stack.Children | Where-Object { $_ -is [Windows.Controls.Button] } | Select-Object -First 1
if($null -eq $button){throw 'Shape button missing from flyout'}
$button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
$window.UpdateLayout()
$after=Get-CardShape $key
if($after -eq $before){throw 'Shape button did not toggle card shape'}
# Sentinel dismissal: pointer never entered the flyout and moved far away -> auto close.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SysMonTestCursor {
    [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point p);
}
'@
$original=New-Object SysMonTestCursor+Point
[SysMonTestCursor]::GetCursorPos([ref]$original)|Out-Null
function Pump-For([int]$Milliseconds) {
    # Short frames let other DispatcherTimers (the flyout sentinel) interleave.
    $deadline=(Get-Date).AddMilliseconds($Milliseconds)
    while((Get-Date) -lt $deadline){
        $frame=[Windows.Threading.DispatcherFrame]::new()
        $t=[Windows.Threading.DispatcherTimer]::new(); $t.Interval=[TimeSpan]::FromMilliseconds(150)
        $t.Add_Tick({param($s,$e) $s.Stop(); $s.Tag.Continue=$false}); $t.Tag=$frame
        $t.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame)
    }
}
Show-CardDetail $key ([Drawing.Point]::new(200,200))
$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
if(-not $script:cardDetailPopup.IsOpen){throw 'Flyout did not reopen for sentinel test'}
[SysMonTestCursor]::SetCursorPos(1600,1000)|Out-Null
Pump-For 1400
if($script:cardDetailPopup.IsOpen){throw 'Flyout stayed open after pointer moved far away without entering it'}
[SysMonTestCursor]::SetCursorPos($original.X,$original.Y)|Out-Null
# Restore
Set-CardShape $key $before $true | Out-Null
$script:cardOrder=@('cpu','gpuT','cpuRpm','caseRpm','pumpRpm','vrm','dgxGpuT','dgxCpu','dgxFan','dgxNvme','dgxMem','dgxLoad','netDown','diskPct')
Restore-NormalCardLayout; Save-DesktopCardLayout
$script:exiting=$true; $window.Close(); $script:tray.Dispose(); $menu.Dispose(); $script:trayFont.Dispose(); $script:trayBitmap.Dispose()
"PASS: flyout shape button toggles $before -> $after and restores"
