param([ValidateSet('Save','Restore')][string]$Phase)
$ErrorActionPreference='Stop'
if(-not $Phase) {
    $root=Split-Path -Parent $PSScriptRoot
    $temp=[IO.Path]::GetFullPath($env:TEMP)
    $fixture=Join-Path $temp ('sysmon-placement-'+[guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($fixture)|Out-Null
    try {
        foreach($name in @('glass.ps1','modules','native','ui','locale','tests')) {
            Copy-Item -LiteralPath (Join-Path $root $name) -Destination $fixture -Recurse
        }
        '{"desktopMode":false,"preset":"auto","theme":"dark","interval":2000}' | Set-Content -LiteralPath (Join-Path $fixture 'sysmon.json')
        foreach($step in @('Save','Restore')) {
            & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -STA -File (Join-Path $fixture 'tests/PlacementIo.Tests.ps1') -Phase $step
            if($LASTEXITCODE){throw "Placement test $step failed"}
        }
    } finally {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if([IO.Path]::GetDirectoryName($resolved) -eq $temp -and [IO.Path]::GetFileName($resolved).StartsWith('sysmon-placement-')) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
    return
}
. (Join-Path $PSScriptRoot '../glass.ps1') -PrepareOnly
function Pump {
    $frame=[Windows.Threading.DispatcherFrame]::new()
    $clock=[Windows.Threading.DispatcherTimer]::new()
    $clock.Tag=$frame; $clock.Interval=[TimeSpan]::FromMilliseconds(140)
    $clock.Add_Tick({param($s,$e) $s.Stop(); $s.Tag.Continue=$false})
    $clock.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame)
}
function Assert-CloseTo($Actual,$Expected,[string]$Label) {
    if([math]::Abs($Actual-$Expected) -gt 2){throw "$Label expected $Expected but was $Actual"}
}
try {
    $window.Show(); Pump
    $hwnd=[Windows.Interop.WindowInteropHelper]::new($window).Handle
    if($Phase -eq 'Save') {
        [SysMonGlass.Native]::SetWindowBounds($hwnd,210,165,1260,810); Pump
        Save-PanelPlacement -ManualResize
        $window.FindName('HideButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)); Pump
        if($window.IsVisible){throw 'Normal hide did not complete'}
        Toggle-Window; Pump
        # Enter bottom mode through the real entry point: layerMode is the single
        # source of truth on restart, and Set-DesktopMode alone leaves it stale.
        Set-WindowLayer 'bottom' $true
        Set-DesktopAdjustment $true
        $script:desktopDraftScale=0.65
        Move-DesktopWindow 390 200; Pump
        $desktop=[SysMonGlass.Native]::GetWindowBounds($hwnd)
        Set-Theme 'forest' $true
        Set-Language 'en' $true
        $exit.PerformClick()
        $saved=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        # Shared-position contract (2026-11-08): a layer switch must never move the
        # panel, so both mode keys always carry the same physical position. Sizes
        # stay independent (desktopScale vs normal width/height).
        Assert-CloseTo $saved.desktopX $desktop.Left 'Exit saves desktop X'
        Assert-CloseTo $saved.desktopY $desktop.Top 'Exit saves desktop Y'
        Assert-CloseTo $saved.normalX $desktop.Left 'Saved normal X follows the shared position'
        Assert-CloseTo $saved.normalY $desktop.Top 'Saved normal Y follows the shared position'
        if($saved.desktopScale -ne 0.65){throw 'Exit did not save desktop manual scale'}
        'PASS: shared panel position with independent per-mode sizes through hide/exit'
    } else {
        $saved=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        if($script:cfg.theme -ne 'forest' -or $script:cfg.language -ne 'en' -or $themeMenu.Text -ne 'Theme'){throw 'Theme or language did not survive restart'}
        $restored=[SysMonGlass.Native]::GetWindowBounds($hwnd)
        $dpi=[SysMonGlass.Native]::GetDpiForWindow($hwnd)
        Assert-CloseTo $restored.Left $saved.desktopX 'Restart desktop X'
        Assert-CloseTo $restored.Top $saved.desktopY 'Restart desktop Y'
        Assert-CloseTo ($restored.Right-$restored.Left) ($saved.desktopScale*1600*$dpi/96) 'Restart desktop width'
        Set-WindowLayer 'normal' $true; Pump
        $restored=[SysMonGlass.Native]::GetWindowBounds($hwnd)
        Assert-CloseTo $restored.Left $saved.normalX 'Restart normal X'
        Assert-CloseTo $restored.Top $saved.normalY 'Restart normal Y'
        Assert-CloseTo ($restored.Right-$restored.Left) 1260 'Restart normal width'
        Assert-CloseTo ($restored.Bottom-$restored.Top) 810 'Restart normal height'
        $rates=Get-NetworkRates @{a=@{Down=100;Up=40};reset=@{Down=700;Up=90}} @{a=@{Down=1124;Up=552};reset=@{Down=0;Up=0};new=@{Down=900;Up=500}} 2
        if($rates.Down -ne 512 -or $rates.Up -ne 256){throw 'Network delta, new-adapter, or reset handling is wrong'}
        Read-LocalIO; Pump; Read-LocalIO; Update-Display
        if($script:values.diskTotal -le 0 -or $script:controls.diskPct.number.Text -eq '—'){throw 'Live local disk data missing'}
        if($script:values.ContainsKey('netDown') -and $script:controls.netDown.unit.Text -notlike '*/s'){throw 'Live network card unit missing'}
        "PASS: fresh PowerShell process restored both placements; live disk $($script:controls.diskPct.number.Text)%, network $($script:controls.netDown.number.Text) $($script:controls.netDown.unit.Text)"
    }
} finally {
    if($window.IsVisible){$script:exiting=$true; $window.Close()}
    $script:tray.Dispose(); $menu.Dispose(); $script:trayFont.Dispose(); $script:trayBitmap.Dispose()
}
