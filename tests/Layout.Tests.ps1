$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../modules/Layout.ps1')
$script:systemCardRows=1
$area=[pscustomobject]@{Left=0;Top=0;Right=2560;Bottom=1380;Width=2560;Height=1380}
$desktop=Get-PanelGeometry $area 'auto' $true 100 100
if($desktop.Width -ne 2257 -or $desktop.Height -ne 1269) { throw "Auto desktop sizing rounded its scale: $($desktop|ConvertTo-Json -Compress)" }
$count=0
foreach($origin in @(0,-2560)) {
    foreach($size in @(@(1920,1040),@(2560,1380),@(3840,2100))) {
        $area=[pscustomobject]@{Left=$origin;Top=0;Right=$origin+$size[0];Bottom=$size[1];Width=$size[0];Height=$size[1]}
        foreach($presetName in @('auto','1080p','2k','4k')) {
            foreach($desktopMode in @($false,$true)) {
                $g=Get-PanelGeometry $area $presetName $desktopMode 10000 -10000
                if($g.Width -le 0 -or $g.Height -le 0 -or $g.X -lt $area.Left -or $g.Y -lt $area.Top -or $g.X+$g.Width -gt $area.Right -or $g.Y+$g.Height -gt $area.Bottom) { throw 'Physical bounds exceed working area' }
                $count++
            }
        }
    }
}
"PASS: $count physical geometry cases and exact fractional scale regression"
