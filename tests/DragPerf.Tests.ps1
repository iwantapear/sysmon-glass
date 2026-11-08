$ErrorActionPreference='Stop'
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Run with -STA'}
$env:SYSMON_CONFIG_HOME=Join-Path $env:TEMP ('sysmon-dragperf-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $env:SYSMON_CONFIG_HOME -Force | Out-Null
. (Join-Path $PSScriptRoot '../glass.ps1') -PrepareOnly
function Assert($ok,[string]$msg){ if(-not $ok){ throw $msg } }
$window.Show(); Start-Sleep -m 700
$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
$hwnd=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
function Time-Call([scriptblock]$action,[int]$n=15){
    for($i=0;$i -lt 3;$i++){ & $action $i }
    $sw=[Diagnostics.Stopwatch]::StartNew()
    for($i=0;$i -lt $n;$i++){ & $action $i }
    $sw.Stop()
    [math]::Round($sw.Elapsed.TotalMilliseconds/$n,2)
}
# Thresholds carry ~10x headroom over the measured values so the suite stays stable
# on a loaded machine while still catching a regression to per-move full re-packing.
$budget=3.0
Set-DesktopMode $true
$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
$base=[SysMonGlass.Native]::GetWindowBounds($hwnd)
$panelMs=Time-Call { param($i) Move-DesktopWindow ($base.Left+($i%10)*3) ($base.Top+($i%4)*2) }
Assert ($panelMs -lt $budget) "desktop panel move must stay cheap (was $panelMs ms/move, budget $budget)"
Set-DesktopMode $false
$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
Set-CardEditing $true
$script:cardGesture=@{key='cpu';surface=$script:controls['cpu'].surface;capture=$script:controls['cpu'].surface;beforeOrder=@($script:cardOrder);beforeSlots=@{};x=0;y=0;originX=0;originY=0;scaleX=1;scaleY=1;rows=6;moved=$true;active=$true}
$cardMs=Time-Call { param($i) Move-CardInCanvas 0 (400+($i%8)*7) (280+($i%5)*6) }
Assert ($cardMs -lt $budget) "card drag must not re-pack every move (was $cardMs ms/move, budget $budget)"
Assert ($null -ne $script:cardGesture.target) 'card drag must record the pending target slot'
$script:cardGesture=$null
Set-CardEditing $false
# Drag-time cache: on during a move phase, off afterwards, content stays vector otherwise.
Assert ($null -eq $window.FindName('DashboardView').CacheMode) 'dashboard must not stay bitmap-cached when idle'
Start-PanelDragOptimization
Assert ($null -ne $window.FindName('DashboardView').CacheMode) 'drag phase must enable the bitmap cache'
Stop-PanelDragOptimization
Assert ($null -eq $window.FindName('DashboardView').CacheMode) 'cache must be released after the drag'
$script:exiting=$true; $window.Close(); $script:tray.Dispose(); $menu.Dispose(); $script:trayFont.Dispose(); $script:trayBitmap.Dispose()
Remove-Item -Path $env:SYSMON_CONFIG_HOME -Recurse -Force -ErrorAction SilentlyContinue
"Drag performance PASS: panel=$panelMs ms/move, card=$cardMs ms/move (budget $budget)"
