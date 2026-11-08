$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../glass.ps1') -ValidateOnly

# Stats math over a fixed buffer.
$hist=[Collections.Generic.List[double]]@(40,42,41,45,44)
$s=Get-CardStats $hist
if($null -eq $s -or $s.cur -ne 44 -or $s.min -ne 40 -or $s.max -ne 45 -or [math]::Abs($s.avg-42.4) -gt 1e-9 -or $s.count -ne 5){throw 'Card stats math failed'}
if($null -ne (Get-CardStats ([Collections.Generic.List[double]]@()))){throw 'Empty history must yield no stats'}

# Threshold levels: upper bounds, fan floors, unknown keys pass.
if((Get-InsightsLevel 'cpu' 50) -ne 'ok'){throw 'cpu below warn must be ok'}
if((Get-InsightsLevel 'cpu' 85) -ne 'warn'){throw 'cpu at warn edge must be warn'}
if((Get-InsightsLevel 'cpu' 95) -ne 'crit'){throw 'cpu at crit edge must be crit'}
if((Get-InsightsLevel 'pumpRpm' 800) -ne 'warn'){throw 'pump below floor must warn'}
if((Get-InsightsLevel 'pumpRpm' 1500) -ne 'ok'){throw 'pump above floor must be ok'}
if((Get-InsightsLevel 'netDown' 9999) -ne 'ok'){throw 'Untracked keys must always pass'}

# Transition-only alerting: steady states stay silent, recoveries are logged.
$script:values=@{}; $script:insightsAlerts.Clear(); $script:insightsAlertLevel=@{}
$script:values.cpu=90; Test-InsightsThresholds
if($script:insightsAlerts.Count -ne 1){throw 'First warn must log once'}
Test-InsightsThresholds
if($script:insightsAlerts.Count -ne 1){throw 'Steady warn must stay silent'}
$script:values.cpu=96; Test-InsightsThresholds
if($script:insightsAlerts.Count -ne 2){throw 'Warn to crit must log'}
$script:values.cpu=50; Test-InsightsThresholds
if($script:insightsAlerts.Count -ne 3){throw 'Recovery must log'}
$script:values.cpu=50; Test-InsightsThresholds
if($script:insightsAlerts.Count -ne 3){throw 'Steady ok must stay silent'}
for($i=0;$i -lt 40;$i++){$script:values.cpu=90+$i%2*6; Test-InsightsThresholds}
if($script:insightsAlerts.Count -gt 30){throw 'Alert log must cap at 30 entries'}

# Rail geometry: right-docked lane, clear only when no card reaches into it.
$rail=Insights-RailRect 1504
if($rail.x -ne 1192 -or $rail.width -ne 300){throw 'Rail rect math failed'}
$realPacking=$script:desktopPacking
$script:desktopPacking=@(@{key='cpu';span=1;row=0;column=0},@{key='gpuT';span=2;row=1;column=0})
if(-not (Test-InsightsRailClear)){throw 'Cards left of the rail must leave it clear'}
$script:desktopPacking=@(@{key='cpu';span=1;row=0;column=0},@{key='gpuT';span=1;row=1;column=3})
if(Test-InsightsRailClear){throw 'A card in the last column must block the rail'}
$script:desktopPacking=$realPacking
# Occupied lane hides the rail; it must never relocate user cards.
Set-DesktopMode $false
$script:cfg.insightsRail=$true

# Rail visibility follows mode, preference, and card overlap.
$window.Visibility='Hidden'; $window.Show()
Set-DesktopMode $true
$realSlots=$script:desktopPacking
$script:desktopPacking=@(@{key='cpu';span=1;row=0;column=0},@{key='gpuT';span=2;row=1;column=0})
$script:cfg.insightsRail=$false; Update-InsightsRailLayout
if($script:insightsRailBorder.Visibility -eq [Windows.Visibility]::Visible){throw 'Rail must hide when disabled'}
$script:cfg.insightsRail=$true; Update-InsightsRailLayout
if($script:insightsRailBorder.Visibility -ne [Windows.Visibility]::Visible){throw 'Rail must show in desktop mode when clear'}
$script:desktopPacking=@(@{key='cpu';span=1;row=0;column=0},@{key='gpuT';span=1;row=1;column=3})
Update-InsightsRailLayout
if($script:insightsRailBorder.Visibility -ne [Windows.Visibility]::Collapsed){throw 'Occupied lane must hide the rail'}
$script:desktopPacking=$realSlots
Set-DesktopMode $false
if($script:insightsRailBorder.Visibility -eq [Windows.Visibility]::Visible){throw 'Rail must hide outside desktop mode'}
'Insights rail regression PASS'
