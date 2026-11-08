$ErrorActionPreference='Stop'
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Run with -STA'}
$env:SYSMON_CONFIG_HOME=Join-Path $env:TEMP ('sysmon-chromedrag-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $env:SYSMON_CONFIG_HOME -Force | Out-Null
. (Join-Path $PSScriptRoot '../glass.ps1') -PrepareOnly
function Assert($ok,[string]$msg){ if(-not $ok){ throw $msg } }
$fails=[Collections.Generic.List[string]]::new()
function Check([bool]$ok,[string]$msg){ if($ok){ Write-Host "  ok   $msg" } else { Write-Host "  FAIL $msg"; $fails.Add($msg) } }

Write-Host '--- layer 1: pure chrome hit-test geometry (2000x1360 window) ---'
$W=2000; $H=1360
Check ((Get-ChromeHitTest 0 0 $W $H) -eq 'caption')      'top-left corner -> caption'
Check ((Get-ChromeHitTest ($W-1) 0 $W $H) -eq 'caption') 'top-right corner -> caption'
Check ((Get-ChromeHitTest 0 ($H-1) $W $H) -eq 'caption') 'bottom-left corner -> caption'
Check ((Get-ChromeHitTest 4 ($H/2) $W $H) -eq 'caption') 'left rim (x=4) -> caption'
Check ((Get-ChromeHitTest ($W-4) ($H/2) $W $H) -eq 'caption') 'right rim (x=W-4) -> caption'
Check ((Get-ChromeHitTest ($W/2) 4 $W $H) -eq 'caption') 'top rim (y=4) -> caption'
Check ((Get-ChromeHitTest ($W/2) ($H-4) $W $H) -eq 'caption') 'bottom rim (y=H-4) -> caption'
Check ((Get-ChromeHitTest 7 ($H/2) $W $H) -eq 'caption') 'left rim inner bound (x=7) -> caption'
Check ($null -eq (Get-ChromeHitTest 8 ($H/2) $W $H))    'x=8 (just inside band) -> client'
Check ($null -eq (Get-ChromeHitTest 400 400 $W $H))     'interior -> client'
Check ((Get-ChromeHitTest ($W-1) ($H-1) $W $H) -eq 'grip')    'resize corner -> grip (not caption)'
Check ((Get-ChromeHitTest ($W-64) ($H-64) $W $H) -eq 'grip')  'grip inner bound -> grip'
Check ((Get-ChromeHitTest ($W-65) ($H-4) $W $H) -eq 'caption') 'bottom rim left of grip corner -> caption'
Check ((Get-ChromeHitTest ($W-30) 4 $W $H) -eq 'caption') 'top rim right of grip -> caption'

Write-Host '--- layer 2: live HWND WM_NCHITTEST returns HTCAPTION at the rim ---'
$window.Opacity=0; $window.Show(); $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
Set-DesktopMode $false
$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
$hwnd=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HitProbe {
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
}
'@
function Probe([int]$sx,[int]$sy) {
    $packed=[int64](((($sy -band 0xFFFF) -shl 16) -bor ($sx -band 0xFFFF)))
    [HitProbe]::SendMessage($hwnd,0x0084,[IntPtr]::Zero,[IntPtr]$packed).ToInt64()
}
if($hwnd -eq [IntPtr]::Zero){ throw 'no HWND' }
$b=[SysMonGlass.Native]::GetWindowBounds($hwnd)
$W=$b.Right-$b.Left; $H=$b.Bottom-$b.Top
Write-Host ("  [state] desktopMode=" + $script:cfg.desktopMode + " chromeDragEnabled=" + [SysMonGlass.Native]::ChromeDragEnabled)
Check ((Probe ($b.Left+4) ($b.Top+$H/2)) -eq 2) 'WM_NCHITTEST left rim -> 2 (HTCAPTION)'
Check ((Probe ($b.Left+$W/2) ($b.Top+4)) -eq 2) 'WM_NCHITTEST top rim -> 2 (HTCAPTION)'
Check ((Probe ($b.Right-4) ($b.Top+$H/2)) -eq 2) 'WM_NCHITTEST right rim -> 2 (HTCAPTION)'
Check ((Probe ($b.Left+$W/2) ($b.Bottom-4)) -eq 2) 'WM_NCHITTEST bottom rim -> 2 (HTCAPTION)'
$gripHit=Probe ($b.Right-8) ($b.Bottom-8)
Check ($gripHit -ne 2) "WM_NCHITTEST grip corner returns resize code ($gripHit), not caption"
$centerHit=Probe ($b.Left+$W/2) ($b.Top+$H/2)
Check ($centerHit -ne 2) "WM_NCHITTEST interior returns client code ($centerHit)"

Write-Host '--- layer 3: which elements may start a panel drag ---'
function Hit([string]$name){ $window.FindName($name) }
Check (Test-PanelDragSurface $window.FindName('HeaderTitle')) 'header title text -> draggable'
Check (Test-PanelDragSurface $window.FindName('FooterText')) 'footer text -> draggable'
Check (Test-PanelDragSurface $window.FindName('StatusBorder')) 'status pill -> draggable'
Check (Test-PanelDragSurface $window.FindName('AmbientTop')) 'ambient glow -> draggable'
Check (-not (Test-PanelDragSurface $window.FindName('ThemeButton'))) 'theme button -> NOT draggable'
Check (-not (Test-PanelDragSurface $window.FindName('HideButton'))) 'hide button -> NOT draggable'
Check (-not (Test-PanelDragSurface $window.FindName('DesktopAdjustDone'))) 'done button -> NOT draggable'
Check (-not (Test-PanelDragSurface $window.FindName('EditScaleUp'))) 'toolbar scale button -> NOT draggable'
Check (-not (Test-PanelDragSurface $script:controls['cpu'].number)) 'card number text -> NOT draggable'
Check (-not (Test-PanelDragSurface $script:controls['cpu'].face)) 'card face -> NOT draggable'
Check (-not (Test-PanelDragSurface $window.FindName('CardScroll'))) 'card scroll area -> NOT draggable'

Set-DesktopMode $true
$b2=[SysMonGlass.Native]::GetWindowBounds($hwnd)
Check ((Probe ($b2.Left+4) ($b2.Top+$b2.Bottom-$b2.Top)/2) -ne 2) 'bottom mode: rim returns client (no system drag)'
Set-DesktopMode $false

$script:exiting=$true; $window.Close(); $script:tray.Dispose(); $menu.Dispose(); $script:trayFont.Dispose(); $script:trayBitmap.Dispose()
Remove-Item -Path $env:SYSMON_CONFIG_HOME -Recurse -Force -ErrorAction SilentlyContinue
if($fails.Count){ throw ("{0} chrome-drag checks failed" -f $fails.Count) }
'Chrome drag regression PASS'
