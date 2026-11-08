$ErrorActionPreference='Stop'
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Run with -STA'}
# Isolated config: this test saves settings and must not touch the repo's sysmon.json.
$env:SYSMON_CONFIG_HOME=Join-Path $env:TEMP ('sysmon-layerpos-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $env:SYSMON_CONFIG_HOME -Force | Out-Null
$AppRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $AppRoot 'glass.ps1') -PrepareOnly
$window.Visibility='Hidden'; $window.Show()
$hwnd=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
if($hwnd -eq [IntPtr]::Zero){throw 'HWND missing'}
function Pump { $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background) }
Set-DesktopMode $false; Pump
# Small per-mode sizes so the on-screen clamp never fires during the test
# (default '2k' preset yields a 2240px-wide panel that legitimately clamps).
$script:cfg.desktopScale=0.4
$script:cfg.normalWidthDip=800.0; $script:cfg.normalHeightDip=450.0

# Park the panel at a distinctive on-screen position (physical pixels).
[SysMonGlass.Native]::SetScreenPosition($hwnd,420,260)
$before=[SysMonGlass.Native]::GetWindowBounds($hwnd)

# Stale coordinates from the other mode must be overridden by the switch.
$script:cfg.desktopX=100.0; $script:cfg.desktopY=100.0
$script:cfg.normalX=100.0;  $script:cfg.normalY=100.0
Set-DesktopMode $true; Pump
$bottom=[SysMonGlass.Native]::GetWindowBounds($hwnd)
if($bottom.Left -ne $before.Left -or $bottom.Top -ne $before.Top){throw ("Switch to bottom moved the panel: {0},{1} -> {2},{3}" -f $before.Left,$before.Top,$bottom.Left,$bottom.Top)}

Set-DesktopMode $false; Pump
$normal=[SysMonGlass.Native]::GetWindowBounds($hwnd)
if($normal.Left -ne $before.Left -or $normal.Top -ne $before.Top){throw ("Switch back to normal moved the panel: {0},{1} -> {2},{3}" -f $before.Left,$before.Top,$normal.Left,$normal.Top)}

# Both mode keys must now agree with the physical position.
if($script:cfg.normalX -ne $before.Left -or $script:cfg.desktopX -ne $before.Left){throw 'Mode position keys diverge after switching'}

$script:exiting=$true; $window.Close(); $script:tray.Dispose(); $menu.Dispose(); $script:trayFont.Dispose(); $script:trayBitmap.Dispose()
Remove-Item -Path $env:SYSMON_CONFIG_HOME -Recurse -Force -ErrorAction SilentlyContinue
'Layer switch keeps panel position PASS'
