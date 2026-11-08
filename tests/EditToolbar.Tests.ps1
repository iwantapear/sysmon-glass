$ErrorActionPreference='Stop'
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Run with -STA'}
$AppRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $AppRoot 'glass.ps1') -PrepareOnly
$window.Show(); Set-DesktopMode $true
$window.UpdateLayout()
function Pump { $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background) }
function Click($element){ $element.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent)); Pump }
$bar=$window.FindName('EditToolbar')
$switch=$window.FindName('EditModeSwitch')
$layer=$window.FindName('EditLayerButton')
$label=$window.FindName('EditScaleLabel')
$done=$window.FindName('DesktopAdjustDone')

# Unified entry in desktop mode starts panel adjustment with the toolbar up.
Set-DesktopAdjustment $true; Pump
if($bar.Visibility -ne [Windows.Visibility]::Visible){throw 'Toolbar must show during panel adjustment'}
if($switch.Visibility -ne [Windows.Visibility]::Visible -or $switch.Content -ne '卡片编辑'){throw 'Mode switch wrong in panel adjustment'}
if($done.Visibility -ne [Windows.Visibility]::Visible){throw 'Done must live in the toolbar'}

# Scale steps adjust the live draft and the label.
$base=[double]$script:desktopDraftScale
Click ($window.FindName('EditScaleUp'))
if([math]::Abs(($script:desktopDraftScale-$base)-0.05) -gt 1e-9){throw 'Scale step did not change the draft'}
if($label.Text -ne ("{0}%" -f [int][math]::Round($script:desktopDraftScale*100))){throw 'Scale label did not follow'}

# Mode switch swaps to card editing without losing the toolbar.
Click $switch; Pump
if(-not $script:cardEditing -or $script:desktopAdjusting){throw 'Mode switch must swap adjustment for card editing'}
if($bar.Visibility -ne [Windows.Visibility]::Visible -or $switch.Content -ne '面板调整'){throw 'Toolbar must persist across the swap'}

# Done exits both states and hides the toolbar.
Click $done; Pump
if($script:cardEditing -or $script:desktopAdjusting -or $bar.Visibility -eq [Windows.Visibility]::Visible){throw 'Done must exit editing and hide the toolbar'}

# Normal mode: toolbar shows scale + done only.
Set-DesktopMode $false; Pump
Set-CardEditing $true; Pump
if($bar.Visibility -ne [Windows.Visibility]::Visible){throw 'Toolbar must show during normal-mode editing'}
if($switch.Visibility -ne [Windows.Visibility]::Collapsed -or $layer.Visibility -ne [Windows.Visibility]::Collapsed){throw 'Desktop-only controls must hide in normal mode'}
$w0=[double]$script:cfg.normalWidthDip
Click ($window.FindName('EditScaleUp'))
if([math]::Abs(([double]$script:cfg.normalWidthDip-$w0*(1.05))) -gt 0.5){throw 'Normal-mode scale step did not resize'}
Click $done; Pump
if($script:cardEditing -or $bar.Visibility -eq [Windows.Visibility]::Visible){throw 'Done must exit normal editing'}
Set-CardShape 'cpu' short $false | Out-Null
$script:exiting=$true; $window.Close(); $script:tray.Dispose(); $menu.Dispose(); $script:trayFont.Dispose(); $script:trayBitmap.Dispose()
'Edit toolbar regression PASS'
