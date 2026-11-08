param([string]$EvidenceFolder='evidence/20261108/resize')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../glass.ps1') -PrepareOnly
$evidence=Join-Path $script:AppRoot $EvidenceFolder
[IO.Directory]::CreateDirectory($evidence) | Out-Null
$configPath=Join-Path $env:TEMP ('sysmon-integration-'+[guid]::NewGuid().ToString('N')+'.json')
$originalConfig=$script:cfg.Clone()
$script:cfg.Remove('desktopScale')
$script:cfg.preset='auto'
$results=[Collections.Generic.List[object]]::new()
function Assert($condition,[string]$message) { if(-not $condition){throw $message}; $results.Add($message) }
function Pump([int]$Milliseconds=150) {
    $frame=[Windows.Threading.DispatcherFrame]::new()
    $pumpTimer=[Windows.Threading.DispatcherTimer]::new()
    $pumpTimer.Interval=[TimeSpan]::FromMilliseconds($Milliseconds)
    $pumpTimer.Tag=$frame
    $pumpTimer.Add_Tick({param($s,$e) $s.Stop(); $s.Tag.Continue=$false})
    $pumpTimer.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame)
}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SysMonTestMouse {
    [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, int x, int y, uint data, UIntPtr extra);
}
'@
function Drag-Element($element,[int]$dx,[int]$dy,[string]$stateName) {
    $screenPoint=$element.PointToScreen([Windows.Point]::new($element.ActualWidth/2,$element.ActualHeight/2))
    $point=[SysMonTestMouse+Point]::new(); $point.X=[int]$screenPoint.X; $point.Y=[int]$screenPoint.Y
    if([SysMonTestMouse]::WindowFromPoint($point) -ne $hwnd){throw 'Test target does not own mouse point'}
    $original=[SysMonGlass.Native]::GetCursorPosition()
    try {
        if(-not [SysMonTestMouse]::SetCursorPos($point.X,$point.Y)){throw 'Cannot position test cursor'}
        Pump
        [SysMonTestMouse]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
        Pump
        if(-not $stateName){return}
        if(-not (Get-Variable -Name $stateName -Scope Script -ValueOnly)){throw "Mouse did not start $stateName"}
        $before=[SysMonGlass.Native]::GetWindowBounds($hwnd)
        [SysMonTestMouse]::SetCursorPos($point.X+$dx,$point.Y+$dy) | Out-Null
        Pump
        if($stateName -eq 'resizeState') {
            $after=[SysMonGlass.Native]::GetWindowBounds($hwnd)
            $preview=$script:resizeState.preview
            Assert ($before.Left -eq $after.Left -and $before.Top -eq $after.Top -and $before.Right -eq $after.Right -and $before.Bottom -eq $after.Bottom) 'Native window stays stable throughout preview drag'
            Assert ($null -ne $preview -and [math]::Abs($preview.scale.ScaleX-1) -gt 0.01) 'Cards visibly scale while mouse remains held'
        }
    } finally {
        [SysMonTestMouse]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
        Pump
        [SysMonTestMouse]::SetCursorPos($original.X,$original.Y) | Out-Null
    }
}
function Capture([string]$Name) {
    $window.UpdateLayout(); Pump
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int][math]::Ceiling($window.ActualWidth),[int][math]::Ceiling($window.ActualHeight),96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($window)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.File]::Create((Join-Path $evidence "$Name.png"))
    try{$encoder.Save($stream)}finally{$stream.Dispose()}
    return $bitmap
}
function GapAlpha($bitmap) {
    $face=$script:controls.cpu.face
    $point=$face.TranslatePoint([Windows.Point]::new($face.ActualWidth+9,$face.ActualHeight/2),$window)
    $pixel=[byte[]]::new(4)
    $bitmap.CopyPixels([Windows.Int32Rect]::new([int]$point.X,[int]$point.Y,1,1),$pixel,4,0)
    return [int]$pixel[3]
}
try {
    $window.Show(); Pump
    $hwnd=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
    Assert ($hwnd -ne [IntPtr]::Zero) 'Real HWND created'
    $script:layoutBusy=$true
    Request-DpiLayout
    Assert ($script:dpiLayoutQueued) 'DPI update queues while layout is busy'
    $script:layoutBusy=$false; Pump
    Assert (-not $script:dpiLayoutQueued) 'Queued DPI update drains after current layout'
    # Vector halo (no WPF Effect): the gap must carry alpha in normal mode and be
    # fully transparent in desktop mode, where the halo is collapsed for icon holes.
    Set-DesktopMode $false; Pump
    $haloBitmap=Capture 'normal-halo'
    $withShadow=GapAlpha $haloBitmap
    Set-DesktopMode $true; Pump
    $clearBitmap=Capture 'desktop-dark'
    $withoutShadow=GapAlpha $clearBitmap
    Assert ($withShadow -gt 0 -and $withoutShadow -eq 0) "Gap alpha: halo=$withShadow, desktop=$withoutShadow"
    foreach($round in 1..3) {
        foreach($mode in @($false,$true)) {
            Set-DesktopMode $mode
            foreach($themeName in @('light','dark')) {
                Set-Theme $themeName; Pump
                $corner=[SysMonGlass.Native]::ReadDwmAttribute($hwnd,33)
                Assert ($corner -eq $(if($mode){1}else{2})) "Round $round desktop=$mode theme=$themeName corner=$corner"
                $style=[SysMonGlass.Native]::GetExtendedStyle($hwnd)
                Assert (($style -band 0x08000000) -eq $(if($mode){0x08000000}else{0})) "Round $round desktop=$mode NoActivate flag"
                Assert (($style -band 0x20) -eq 0) "Round $round desktop=$mode click-through style cleared (region-based input)"
                if($mode) {
                    Assert ([SysMonGlass.Native]::ReadDwmAttribute($hwnd,38) -eq 1) "Round $round desktop backdrop disabled"
                    Assert ($script:controls.cpu.shadowHost.Visibility -eq [Windows.Visibility]::Collapsed) "Round $round desktop shadow absent"
                }
            }
        }
    }
    Set-Theme 'light'; $null=Capture 'desktop-light'
    Set-DesktopMode $false; $null=Capture 'panel-light'
    $themeButton=$window.FindName('ThemeButton')
    $themeButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)); Pump
    Assert ($script:cfg.theme -eq 'dark') 'Theme button switches theme'
    $null=Capture 'panel-dark'
    $window.FindName('HideButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)); Pump
    Assert (-not $window.IsVisible) 'Hide button hides window'
    $menu.Items[0].PerformClick(); Pump
    Assert ($window.IsVisible) 'Tray shows hidden window'
    $desktopMenuItem.PerformClick(); Pump
    Assert ($script:cfg.desktopMode) 'Tray enables desktop mode'
    $movePanelMenuItem.PerformClick(); Pump
    Assert ($script:desktopAdjusting) 'Tray enters position adjustment'
    Assert ($window.FindName('ResizeGrip').IsVisible) 'Resize grip appears during desktop adjustment'
    $grip=$window.FindName('ResizeGrip')
    $done=$window.FindName('DesktopAdjustDone')
    Assert ($done.IsVisible) 'Done is visible beside the resize grip'
    $null=Capture 'desktop-adjusting'
    $bounds=[SysMonGlass.Native]::GetWindowBounds($hwnd)
    $oldWidth=$bounds.Right-$bounds.Left
    foreach($delta in @(-360,180,-240)) {
        Drag-Element $grip $delta ([int]($delta*(Get-PanelBaseHeight $true)/1600)) 'resizeState'
        $bounds=[SysMonGlass.Native]::GetWindowBounds($hwnd)
        $newWidth=$bounds.Right-$bounds.Left; $newHeight=$bounds.Bottom-$bounds.Top
        Assert (($newWidth-$oldWidth)*$delta -gt 0) "Grip changes window size in drag direction ($delta px)"
        Assert ([math]::Abs($newHeight-$newWidth*(Get-PanelBaseHeight $true)/1600) -le 2) 'Desktop resize preserves aspect ratio'
        Assert ($script:desktopAdjusting -and -not $script:resizeState -and $grip.IsVisible) 'Mouse-up ends gesture but keeps desktop adjustment active'
        Assert ($null -eq $window.FindName('DashboardGrid').CacheMode) 'Release restores vector rendering'
        $oldWidth=$newWidth
    }
    Drag-Element $script:controls.cpu.surface -50 -40 'dragState'
    $bounds=[SysMonGlass.Native]::GetWindowBounds($hwnd)
    Assert ($script:desktopAdjusting -and -not $script:dragState) 'Card drag release keeps adjustment active'
    Drag-Element $done 0 0
    Assert (-not $script:desktopAdjusting -and $script:cfg.desktopX -eq $bounds.Left -and -not $grip.IsVisible -and -not $done.IsVisible) 'Inline Done saves physical position and hides adjustment controls'
    Assert (([SysMonGlass.Native]::GetExtendedStyle($hwnd) -band 0x20) -eq 0) 'Done keeps region-based pass-through (no click-through style)'
    Assert ($null -ne $script:desktopRegionSignature) 'Done restores the interactive card region'
    $saved=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    Assert ($saved.desktopScale -gt 0) 'Done persists manual desktop scale'
    $menu.Items[0].PerformClick(); Pump
    $menu.Items[0].PerformClick(); Pump
    $restored=[SysMonGlass.Native]::GetWindowBounds($hwnd)
    Assert ([math]::Abs(($restored.Right-$restored.Left)-$oldWidth) -le 2) 'Manual size survives hide/show'
    $res.DropDownItems[0].PerformClick(); Pump
    Assert (-not $script:cfg.ContainsKey('desktopScale') -and $script:cfg.preset -eq 'auto') 'Automatic fit clears manual override'
    $automatic=[SysMonGlass.Native]::GetWindowBounds($hwnd)
    Assert (($automatic.Right-$automatic.Left) -gt $oldWidth) 'Automatic fit restores monitor-sized layout'
    foreach($screen in [Windows.Forms.Screen]::AllScreens) {
        Move-DesktopWindow ($screen.WorkingArea.Left+30) ($screen.WorkingArea.Top+30); Pump
        Apply-Preset -UseCurrentPosition; Pump
        $bounds=[SysMonGlass.Native]::GetWindowBounds($hwnd)
        Assert ($bounds.Left -ge $screen.WorkingArea.Left -and $bounds.Right -le $screen.WorkingArea.Right) "Fits physical display $($screen.DeviceName), DPI=$([SysMonGlass.Native]::GetDpiForWindow($hwnd))"
    }
    foreach($presetItem in $res.DropDownItems) {
        $presetItem.PerformClick(); Pump
        Assert ($script:cfg.preset -eq $presetItem.Tag) "Tray preset $($presetItem.Tag)"
    }
    # Rate menu expects the runtime timer; use the same dispatcher timer type here.
    $script:timer=[Windows.Threading.DispatcherTimer]::new()
    foreach($rateItem in $rate.DropDownItems) {
        $rateItem.PerformClick()
        Assert ($script:timer.Interval.TotalMilliseconds -eq $rateItem.Tag) "Tray refresh $($rateItem.Tag)"
    }
    $script:dgx.Start(); $script:gpu.Start(); Read-LocalIO; Pump 8000
    Read-Values; Update-Display; Update-Tray
    Assert ($script:values.ContainsKey('gpuT')) 'Live NVIDIA reading available'
    Assert ($script:values.ContainsKey('cpu')) 'Live FanCtl reading available'
    Assert ($script:values.ContainsKey('diskPct')) 'Live local disk capacity reading available'
    Assert ($script:values.ContainsKey('netDown') -and $script:values.ContainsKey('netUp')) 'Live network download and upload rates available'
    Assert ($script:dgx.AgeSec -ge 0 -and $script:dgx.AgeSec -lt 8) 'Live DGX SSH frame received'
    $script:cfg.preset='auto'; Set-DesktopMode $false; Set-Theme 'dark'; Pump
    $window.Topmost=$true; Pump
    $null=Capture 'live-panel-dark'
    $bounds=[SysMonGlass.Native]::GetWindowBounds($hwnd)
    $screenShot=[Drawing.Bitmap]::new($bounds.Right-$bounds.Left,$bounds.Bottom-$bounds.Top)
    $graphics=[Drawing.Graphics]::FromImage($screenShot)
    try { $graphics.CopyFromScreen($bounds.Left,$bounds.Top,0,0,$screenShot.Size); $screenShot.Save((Join-Path $evidence 'live-screen.png')) }
    finally { $graphics.Dispose(); $screenShot.Dispose() }
    $results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'integration.json') -Encoding utf8
    "PASS: $($results.Count) real-window assertions"
} finally {
    $script:dgx.Stop(); $script:gpu.Stop()
    $script:exiting=$true; $window.Close()
    $script:tray.Visible=$false; $script:tray.Dispose(); $menu.Dispose()
    if($script:trayIcon){$script:trayIcon.Dispose()}; $script:trayFont.Dispose(); $script:trayBitmap.Dispose()
    if(Test-Path -LiteralPath $configPath){Remove-Item -LiteralPath $configPath}
}
