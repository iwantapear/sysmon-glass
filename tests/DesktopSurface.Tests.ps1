$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../glass.ps1') -ValidateOnly
Set-DesktopMode $true
if($script:controls.cpu.shadowHost.Visibility -ne [Windows.Visibility]::Collapsed) { throw 'Desktop cards cast external shadows into transparent gaps.' }
if($window.FindName('ResizeGrip').Visibility -ne 'Collapsed') { throw 'Desktop resize grip still draws outside cards.' }
Set-DesktopMode $false
if($script:controls.cpu.shadowHost.Visibility -ne [Windows.Visibility]::Visible) { throw 'Normal mode did not restore card shadows.' }
'Desktop surface regression PASS'
