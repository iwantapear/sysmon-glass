$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../glass.ps1') -ValidateOnly
# Materialize the HWND (hidden, no flash): Set-DesktopAdjustment is a no-op without one.
$window.Visibility='Hidden'; $window.Show()
Set-DesktopMode $true
Set-DesktopAdjustment $true
$done=$window.FindName('DesktopAdjustDone')
if($done.Visibility -ne [Windows.Visibility]::Visible) { throw 'Done button not visible during desktop adjustment.' }
if(-not $done.IsHitTestVisible) { throw 'Done button visible but not hit-testable during desktop adjustment.' }
if(-not $window.FindName('ResizeGrip').IsHitTestVisible) { throw 'Resize grip not hit-testable during desktop adjustment.' }
Set-DesktopAdjustment $false
if($done.Visibility -ne [Windows.Visibility]::Collapsed) { throw 'Done button still visible after adjustment ended.' }
# The card-editing path shares the button through Sync-CardPresentation; keep the same invariant.
Set-CardEditing $true
if($done.Visibility -ne [Windows.Visibility]::Visible -or -not $done.IsHitTestVisible) { throw 'Done button not interactive during card editing.' }
Set-CardEditing $false
if($done.Visibility -ne [Windows.Visibility]::Collapsed -or $done.IsHitTestVisible) { throw 'Done button not retired after card editing.' }
'Desktop adjust Done hit-test regression PASS'
