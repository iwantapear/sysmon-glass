$ErrorActionPreference = 'Stop'
foreach ($scriptPath in @((Join-Path $PSScriptRoot 'install-windows.ps1'), (Join-Path $PSScriptRoot 'wpf-release/install-windows.ps1'))) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw $errors[0] }
    $assignments = @($ast.FindAll({ param($node)
        $node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -in @('$uninstall', '$uninstallCommand', '$values')
    }, $true))
    if ($assignments.Count -ne 2) { throw "Expected uninstall registration assignments in $scriptPath" }
    $registration = [scriptblock]::Create(($assignments.Extent.Text -join "`n") + "`n" + '$values')
    & {
        param([switch]$Uninstall)
        $InstallRoot = 'C:\Apps\SysMon Glass'; $icon = 'C:\Apps\SysMon Glass\sysmon.ico'
        $values = . $registration
        if ($Uninstall.IsPresent) { throw 'Registration changed the operation switch' }
        $expected = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Apps\SysMon Glass\uninstall.ps1" -Uninstall -InstallRoot "C:\Apps\SysMon Glass"'
        if ($values.UninstallString -ne $expected -or $values.QuietUninstallString -ne "$expected -Quiet") { throw 'Invalid uninstall command quoting' }
    }
    Write-Host "PASS: uninstall registration preserves typed switch and quoted paths: $scriptPath"
}

# Regression: strict mode must survive absent Run/uninstall-registry values during uninstall.
foreach ($scriptPath in @((Join-Path $PSScriptRoot 'install-windows.ps1'), (Join-Path $PSScriptRoot 'wpf-release/install-windows.ps1'))) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw $errors[0] }
    $registryBlock = @($ast.FindAll({ param($node)
        $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Extent.Text -like 'if (-not $testing)*' -and
        $node.Extent.Text -like '*Remove-ItemProperty -LiteralPath $runKey*'
    }, $true))
    if ($registryBlock.Count -ne 1) { throw "Expected one uninstall registry block in $scriptPath" }
    $block = [scriptblock]::Create($registryBlock[0].Extent.Text)
    $testBase = 'HKCU:\Software\SysMonGlassTest\' + [guid]::NewGuid().ToString('N')
    try {
        foreach ($scenario in @('absent', 'empty')) {
            if ($scenario -eq 'empty') {
                New-Item -Path (Join-Path $testBase "$scenario\Run") -Force | Out-Null
                New-Item -Path (Join-Path $testBase "$scenario\Uninstall") -Force | Out-Null
            }
            & {
                param([scriptblock]$Block, [string]$RunKey, [string]$Registry)
                Set-StrictMode -Version Latest
                $testing = $false
                $InstallRoot = 'C:\Apps\SysMon Glass'
                # Missing values must not raise PropertyNotFoundStrict inside the block.
                . $Block
            } $block (Join-Path $testBase "$scenario\Run") (Join-Path $testBase "$scenario\Uninstall")
        }
    }
    finally { if (Test-Path $testBase) { Remove-Item -Path $testBase -Recurse -Force } }
    Write-Host "PASS: uninstall registry reads tolerate absent values under strict mode: $scriptPath"
}
