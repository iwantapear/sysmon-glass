$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../glass.ps1') -PrepareOnly
$configPath=Join-Path $env:TEMP ('sysmon-context-'+[guid]::NewGuid().ToString('N')+'.json')
$testSource=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Integration.Tests.ps1') -Raw
$start=$testSource.IndexOf('function Pump(')
. ([scriptblock]::Create($testSource.Substring($start,$testSource.IndexOf('function Drag-Element(')-$start)))
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ContextMenuProbe {
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr GetShellWindow();
    [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
}
'@
function Click-Point($Point,[bool]$Right) {
    [SysMonTestMouse]::SetCursorPos([int]$Point.X,[int]$Point.Y)|Out-Null; Pump 80
    $down=if($Right){8}else{2}; $up=if($Right){16}else{4}
    [SysMonTestMouse]::mouse_event($down,0,0,0,[UIntPtr]::Zero)
    try { Pump 80 } finally { [SysMonTestMouse]::mouse_event($up,0,0,0,[UIntPtr]::Zero) }
    Pump 150
}
function Escape-Menu {
    [ContextMenuProbe]::keybd_event(27,0,0,[UIntPtr]::Zero)
    [ContextMenuProbe]::keybd_event(27,0,2,[UIntPtr]::Zero)
    Pump 150
}
$pointer=[SysMonGlass.Native]::GetCursorPosition()
$cover=$null
try {
    $window.Show(); Set-DesktopMode $true; Pump
    if($script:desktopContext.StartError){throw "Hook failed: $($script:desktopContext.StartError)"}
    $desktopRoot=[ContextMenuProbe]::GetAncestor([SysMonGlass.Native]::GetDesktopIconList(),2)
    $shell=[ContextMenuProbe]::GetShellWindow()
    function Is-ExposedDesktopPoint($screenPoint) {
        $probe=[SysMonTestMouse+Point]::new(); $probe.X=[int]$screenPoint.X; $probe.Y=[int]$screenPoint.Y
        $root=[ContextMenuProbe]::GetAncestor([SysMonTestMouse]::WindowFromPoint($probe),2)
        $root -eq $desktopRoot -or $root -eq $shell
    }
    $candidates=@($null)+@([Windows.Forms.Screen]::AllScreens)
    $point=$null
    foreach($screen in $candidates) {
        if($screen) { Move-DesktopWindow ($screen.WorkingArea.Left+60) ($screen.WorkingArea.Top+80); Pump }
        foreach($control in $script:controls.Values) {
            if($control.cell.side -eq 'S'){continue}
            $face=$control.face
            $candidate=$face.PointToScreen([Windows.Point]::new($face.ActualWidth/2,$face.ActualHeight/2))
            $gap=$face.PointToScreen([Windows.Point]::new($face.ActualWidth+9,$face.ActualHeight/2))
            if((Is-ExposedDesktopPoint $candidate) -and (Is-ExposedDesktopPoint $gap)) { $point=$candidate; break }
        }
        if($point){break}
    }
    if(-not $point){throw 'Test needs exposed desktop behind a card and its gap'}
    Click-Point $point $false
    if($menu.Visible){throw 'Left click unexpectedly opened settings'}
    Click-Point $point $true
    if(-not $menu.Visible){Escape-Menu; throw 'Right click on exposed card did not open settings'}
    $bounds=$menu.Bounds
    $bitmap=[Drawing.Bitmap]::new($bounds.Width,$bounds.Height)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($bounds.Left,$bounds.Top,0,0,$bounds.Size)
        $bitmap.Save((Join-Path $script:AppRoot 'evidence/20261108/context-menu/menu.png'))
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
    $location=$menu.PointToScreen([Drawing.Point]::new($positionMenuItem.Bounds.Left+30,$positionMenuItem.Bounds.Top+($positionMenuItem.Bounds.Height/2)))
    Click-Point $location $false
    if(-not $script:desktopAdjusting -or $menu.Visible){throw 'Settings menu did not execute position adjustment'}
    Click-Point $point $true
    if(-not $menu.Visible){throw 'Right click did not open settings during adjustment'}
    $menu.Close(); Pump
    Set-DesktopAdjustment $false; Pump
    Click-Point $point $true
    if(-not $menu.Visible){throw 'Right-click did not resume after completing adjustment'}
    $menu.Close(); Pump
    $gap=$face.PointToScreen([Windows.Point]::new($face.ActualWidth+9,$face.ActualHeight/2))
    Click-Point $gap $true
    $openedInGap=$menu.Visible
    Escape-Menu
    if($openedInGap){throw 'Transparent gap was treated as a card'}
    $cover=[Windows.Window]::new()
    $cover.WindowStyle='None'; $cover.Topmost=$true; $cover.ShowInTaskbar=$false
    $cover.Width=100; $cover.Height=80; $cover.Background=[Windows.Media.Brushes]::SteelBlue
    $script:coverReceived=$false
    $cover.Add_MouseRightButtonUp({$script:coverReceived=$true})
    $cover.Show(); Pump
    $coverHandle=[Windows.Interop.WindowInteropHelper]::new($cover).Handle
    [SysMonGlass.Native]::SetScreenPosition($coverHandle,[int]$point.X-30,[int]$point.Y-25)
    Pump
    Click-Point $point $true
    if($menu.Visible -or -not $script:coverReceived){throw 'Right click did not go to the covering window'}
    $cover.Close(); $cover=$null
    $window.Hide(); Pump
    Click-Point $point $true
    $openedWhenHidden=$menu.Visible
    Escape-Menu
    if($openedWhenHidden){throw 'Hidden panel handled a right click'}
    'PASS: Native card right-click opens and operates settings in both desktop states. Left click, gap, covering window, and hidden panel preserve routing.'
} finally {
    if($cover){$cover.Close()}
    $menu.Close()
    [SysMonTestMouse]::SetCursorPos($pointer.X,$pointer.Y)|Out-Null
    $script:exiting=$true; $window.Close()
    $script:tray.Dispose(); $menu.Dispose(); $script:trayFont.Dispose(); $script:trayBitmap.Dispose()
    if(Test-Path -LiteralPath $configPath){Remove-Item -LiteralPath $configPath}
}
