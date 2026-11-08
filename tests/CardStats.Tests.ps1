$ErrorActionPreference='Stop'
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Run with -STA'}
$env:SYSMON_CONFIG_HOME=Join-Path $env:TEMP ('sysmon-stats-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $env:SYSMON_CONFIG_HOME -Force | Out-Null
. (Join-Path $PSScriptRoot '../glass.ps1') -PrepareOnly
function Assert($ok,[string]$msg){ if(-not $ok){ throw $msg } }
$window.Visibility='Hidden'; $window.Show()
$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)

# 1) Card stats track the rolling history of their own key.
$script:history['cpu']=[Collections.Generic.List[double]]@(40,44,52,48,50)
$script:values.cpu=50
Update-Display
$stats=$script:controls['cpu'].stats.Text
Assert ($stats -match '最大 52') "stats must report the running max (got: $($stats -replace "`n",' '))"
Assert ($stats -match '最小 40') "stats must report the running min (got: $stats)"
Assert ($stats -match '均值 47') "stats must report the mean (got: $stats)"
Assert ($script:controls['cpu'].spark.Points.Count -eq 5) 'curve must plot one point per sample'
Assert ($script:controls['cpu'].spark.Visibility -eq [Windows.Visibility]::Visible) 'curve must be visible with enough samples'

# 2) A card with a single sample shows stats but no curve yet.
$script:history['diskPct']=[Collections.Generic.List[double]]@(25)
$script:values.diskPct=25
Update-Display
Assert ($script:controls['diskPct'].stats.Text -match '最大 25') 'single-sample card still reports stats'
Assert ($script:controls['diskPct'].spark.Visibility -eq [Windows.Visibility]::Collapsed) 'curve needs >=3 samples'

# 3) Missing sensor: no stale stats, no curve.
$script:values.Remove('diskPct')
$script:history.Remove('diskPct')   # Read-Values prunes history for absent sensors
Update-Display
Assert ($script:controls['diskPct'].stats.Text -match '最大 —') 'missing sensor must clear the stats'
Assert ($script:controls['diskPct'].spark.Visibility -eq [Windows.Visibility]::Collapsed) 'missing sensor must hide the curve'

# 4) The curve spans the blank area instead of the old 95px stub.
$script:controls['cpu'].surface.UpdateLayout()
Assert ([double]$script:controls['cpu'].spark.Width -ge 140) "curve must fill the blank area (width $($script:controls['cpu'].spark.Width))"

# 5) The footer's backdrop badge is gone.
$badge=$window.FindName('BackdropText')
Assert ($badge.Visibility -eq [Windows.Visibility]::Collapsed) 'backdrop badge must be collapsed'
Assert ([string]::IsNullOrEmpty($badge.Text)) 'backdrop badge must carry no text'

$script:exiting=$true; $window.Close(); $script:tray.Dispose(); $menu.Dispose(); $script:trayFont.Dispose(); $script:trayBitmap.Dispose()
Remove-Item -Path $env:SYSMON_CONFIG_HOME -Recurse -Force -ErrorAction SilentlyContinue
'Card stats + curve regression PASS'
