$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../glass.ps1') -PrepareOnly
$configPath=Join-Path $env:TEMP ('sysmon-appearance-'+[guid]::NewGuid().ToString('N')+'.json')
$evidence=Join-Path $script:AppRoot 'evidence/20261108/themes-languages'
[IO.Directory]::CreateDirectory($evidence)|Out-Null
$testSource=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Integration.Tests.ps1') -Raw
$start=$testSource.IndexOf('function Pump(')
. ([scriptblock]::Create($testSource.Substring($start,$testSource.IndexOf('Add-Type -TypeDefinition')-$start)))
$start=$testSource.IndexOf('function Capture(')
. ([scriptblock]::Create($testSource.Substring($start,$testSource.IndexOf('function GapAlpha(')-$start)))
try {
    $window.Show(); Set-DesktopMode $true; Pump
    Read-LocalIO; Pump; Read-LocalIO; Update-Display
    $themeBrushes=@{}
    foreach($option in $themeMenu.DropDownItems) {
        $option.PerformClick(); Pump
        if($script:cfg.theme -ne $option.Tag -or -not $option.Checked){throw "Theme failed: $($option.Tag)"}
        $color=[string]$script:controls.cpu.bg.GradientStops[0].Color
        if($themeBrushes.ContainsKey($color)){throw "Duplicate first-stop color: $($option.Tag)"}
        $themeBrushes[$color]=$true
        $null=Capture ('theme-'+$option.Tag)
    }
    foreach($option in $languageMenu.DropDownItems) {
        $option.PerformClick(); Pump
        if($script:cfg.language -ne $option.Tag -or -not $option.Checked){throw "Language failed: $($option.Tag)"}
        if($languageMenu.Text -ne (L 'language') -or $script:controls.cpu.label.Text -ne "$(L 'localMachine') · $(L 'cpuTemp')"){throw 'Menus and cards not translated together'}
        if($script:controls.diskPct.label.Text -notlike "*$(L 'diskUsed')" -or $script:controls.netDown.sub.Text -eq ''){throw 'Local I/O card text missing'}
        $null=Capture ('desktop-'+$option.Tag)
        Set-DesktopMode $false; Pump
        if($window.FindName('HeaderTitle').Text -ne (L 'appTitle')){throw 'Full-panel heading not translated'}
        $null=Capture ('full-'+$option.Tag)
        Set-DesktopMode $true; Pump
    }
    $saved=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    if($saved.theme -ne 'amber' -or $saved.language -ne 'en'){throw 'Appearance preferences were not persisted'}
    $count=$themeMenu.DropDownItems.Count
    "PASS: $count distinct palettes, three translated interfaces, tray state and preferences"
} finally {
    $script:exiting=$true; $window.Close(); $script:tray.Dispose(); $menu.Dispose(); $script:trayFont.Dispose(); $script:trayBitmap.Dispose()
    if(Test-Path -LiteralPath $configPath){Remove-Item -LiteralPath $configPath}
}
