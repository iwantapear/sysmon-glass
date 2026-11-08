$ErrorActionPreference = 'Stop'
$deploy = $PSScriptRoot
$test = Join-Path $deploy ('test-output\' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $test 'payload') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $test 'payload\SysMon.Glass.exe') -Value 'test fixture; never executed'
$zip = Join-Path $test 'payload.zip'
Compress-Archive -Path (Join-Path $test 'payload\*') -DestinationPath $zip
$root = Join-Path $test 'sandbox'
& pwsh -NoProfile -File (Join-Path $deploy 'install-windows.ps1') -Payload $zip -TestRoot $root -NoLaunch
if ($LASTEXITCODE) { throw 'Install failed' }
$marker = Join-Path $root 'app\.sysmon-install.json'
$state = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
if (-not $state.autoStart) { throw 'Default auto-start was not enabled' }
Set-Content -LiteralPath (Join-Path $root 'app\user-config.json') -Value 'preserve me'
& pwsh -NoProfile -File (Join-Path $deploy 'install-windows.ps1') -Uninstall -TestRoot $root
if ($LASTEXITCODE) { throw 'Uninstall failed' }
if (-not (Test-Path -LiteralPath (Join-Path $root 'app\user-config.json'))) { throw 'User file deleted' }
if (Test-Path -LiteralPath (Join-Path $root 'app\SysMon.Glass.exe')) { throw 'Owned executable retained' }
if (Test-Path -LiteralPath (Join-Path $root 'Desktop\SysMon Glass.lnk')) { throw 'Shortcut retained' }
$other = Join-Path $test 'unowned'
New-Item -ItemType Directory -Path (Join-Path $other 'app') -Force | Out-Null
& pwsh -NoProfile -File (Join-Path $deploy 'install-windows.ps1') -Uninstall -TestRoot $other 2>$null
if ($LASTEXITCODE -eq 0) { throw 'Unowned uninstall unexpectedly succeeded' }
# Reinstall after uninstall must reclaim the retained empty directory tree.
$cycle = Join-Path $test 'sandbox-reinstall'
& pwsh -NoProfile -File (Join-Path $deploy 'install-windows.ps1') -Payload $zip -TestRoot $cycle -NoLaunch
if ($LASTEXITCODE) { throw 'Cycle install failed' }
& pwsh -NoProfile -File (Join-Path $deploy 'install-windows.ps1') -Uninstall -TestRoot $cycle
if ($LASTEXITCODE) { throw 'Cycle uninstall failed' }
& pwsh -NoProfile -File (Join-Path $deploy 'install-windows.ps1') -Payload $zip -TestRoot $cycle -NoLaunch
if ($LASTEXITCODE) { throw 'Reinstall after uninstall failed' }
if (-not (Test-Path -LiteralPath (Join-Path $cycle 'app\SysMon.Glass.exe'))) { throw 'Reinstall missing executable' }
Write-Host "PASS: isolated install/uninstall, config preservation, ownership guard, reinstall-after-uninstall. Evidence: $test"
