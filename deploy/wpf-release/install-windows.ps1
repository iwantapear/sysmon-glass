param(
    [string]$Payload = (Join-Path $PSScriptRoot 'payload.zip'),
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\SysMon.Glass'),
    [switch]$NoAutoStart,
    [switch]$Uninstall,
    [switch]$Quiet,
    [switch]$NoLaunch,
    [string]$TestRoot,
    [string]$ScratchRoot
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $Uninstall) {
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    $standardPwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    if (-not $pwsh -and -not (Test-Path -LiteralPath $standardPwsh)) { throw 'PowerShell 7 is required. Install PowerShell 7 before installing SysMon Glass. Setup performs no downloads.' }
}
$testing = -not [string]::IsNullOrWhiteSpace($TestRoot)
if ($testing) { $InstallRoot = Join-Path ([IO.Path]::GetFullPath($TestRoot)) 'app' }
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
if ([IO.Path]::GetPathRoot($InstallRoot).TrimEnd('\') -eq $InstallRoot) { throw 'Refusing a drive root.' }
$marker = Join-Path $InstallRoot '.sysmon-install.json'
$registry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\SysMon.Glass'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$desktop = if ($testing) { Join-Path $TestRoot 'Desktop' } else { [Environment]::GetFolderPath('Desktop') }
$menu = if ($testing) { Join-Path $TestRoot 'StartMenu' } else { Join-Path ([Environment]::GetFolderPath('Programs')) 'SysMon Glass' }
$links = @((Join-Path $desktop 'SysMon Glass.lnk'), (Join-Path $menu 'SysMon Glass.lnk'))
# Never stop a running app: updating locked binaries must be an explicit user action.
if (-not $testing) {
    $running = Get-Process -Name 'SysMon.Glass' -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($InstallRoot + '\', [StringComparison]::OrdinalIgnoreCase) }
    if ($running) { throw 'Close SysMon Glass before installing or uninstalling. No process was stopped.' }
}
function Assert-RegularOwnedPath {
    param([string]$Path)
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing reparse point: $Path" }
}
function Assert-RegularAncestors {
    param([string]$Path)
    $current = [IO.DirectoryInfo]([IO.Path]::GetFullPath($Path))
    while ($null -ne $current) {
        if (Test-Path -LiteralPath $current.FullName) { Assert-RegularOwnedPath $current.FullName }
        $parent = $current.Parent
        if ($null -eq $parent -or $parent.FullName -eq $current.FullName) { break }
        $current = $parent
    }
}
function Assert-ManifestRelative {
    param([string]$Relative)
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)') { throw 'Unsafe manifest path.' }
}
function Remove-OwnedFiles {
    param([string]$Root, $Manifest)
    Assert-RegularOwnedPath $marker
    Assert-RegularAncestors $Root
    foreach ($relative in $Manifest.files) {
        Assert-ManifestRelative $relative
        $full = [IO.Path]::GetFullPath((Join-Path $Root $relative))
        if (-not $full.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe manifest path.' }
        Assert-RegularAncestors (Split-Path $full -Parent)
        if (Test-Path -LiteralPath $full -PathType Leaf) { Assert-RegularOwnedPath $full; Remove-Item -LiteralPath $full -Force }
    }
    # Empty subdirectories are intentionally retained: never recurse through a user-modified tree.
}
$existingInstall = Test-Path -LiteralPath $marker
$existingStartup = $null
if ($existingInstall) {
    try { $oldState = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json; $existingStartup = [bool]$oldState.autoStart } catch { $existingStartup = $null }
}
Assert-RegularAncestors $InstallRoot
foreach ($link in $links) { Assert-RegularAncestors (Split-Path $link -Parent) }
if (Test-Path -LiteralPath $marker) { Assert-RegularOwnedPath $marker }
if ($Uninstall) {
    if (-not (Test-Path -LiteralPath $marker)) { throw 'Not an installer-owned SysMon directory; refusing uninstall.' }
    $state = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
    if ($state.product -ne 'SysMon.Glass') { throw 'Invalid installation marker.' }
    foreach ($link in $links) {
        if (Test-Path -LiteralPath $link) {
            if ($testing) { if ((Get-Content -LiteralPath $link -Raw).Trim() -eq (Join-Path $InstallRoot 'SysMon.Glass.exe')) { Remove-Item -LiteralPath $link -Force } }
            else { $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($link); if ([IO.Path]::GetFullPath($shortcut.TargetPath) -eq [IO.Path]::GetFullPath((Join-Path $InstallRoot 'SysMon.Glass.exe'))) { Remove-Item -LiteralPath $link -Force } }
        }
    }
    if (-not $testing) {
        $exe = ('"' + (Join-Path $InstallRoot 'SysMon.Glass.exe') + '"')
        # Strict mode turns property access on a missing value into a terminating error; read defensively.
        $runProps = Get-ItemProperty -LiteralPath $runKey -ErrorAction SilentlyContinue
        $runProp = if ($runProps) { $runProps.PSObject.Properties['SysMon.Glass'] } else { $null }
        if ($runProp -and $runProp.Value -eq $exe) { Remove-ItemProperty -LiteralPath $runKey -Name 'SysMon.Glass' -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $registry) {
            $regProps = Get-ItemProperty -LiteralPath $registry -ErrorAction SilentlyContinue
            $locationProp = if ($regProps) { $regProps.PSObject.Properties['InstallLocation'] } else { $null }
            if ($locationProp -and [IO.Path]::GetFullPath($locationProp.Value) -eq $InstallRoot) { Remove-Item -LiteralPath $registry -Recurse }
        }
    }
    Remove-OwnedFiles $InstallRoot $state
    Remove-Item -LiteralPath $marker -Force
    if (-not (Get-ChildItem -LiteralPath $InstallRoot -Force)) { Remove-Item -LiteralPath $InstallRoot }
    Write-Host 'SysMon Glass uninstalled. User configuration was retained.'
    exit 0
}
if (-not $Quiet -and -not $testing) {
    Add-Type -AssemblyName System.Windows.Forms
    $answer = [Windows.Forms.MessageBox]::Show('Install SysMon Glass for this user? Yes = enable login auto-start (default). No = install without auto-start. Cancel = exit.', 'SysMon Glass Setup', 'YesNoCancel', 'Question', 'Button1')
    if ($answer -eq 'Cancel') { exit 0 }
    $NoAutoStart = $answer -eq 'No'
}
if ((Test-Path -LiteralPath $InstallRoot) -and -not (Test-Path -LiteralPath $marker)) {
    # Empty leftover trees (uninstall retains empty dirs by design) are safe to reclaim.
    if (Get-ChildItem -LiteralPath $InstallRoot -Recurse -Force -File) { throw 'Target directory already exists without an ownership marker; choose an empty destination.' }
    Remove-Item -LiteralPath $InstallRoot -Recurse -Force
}
if (-not (Test-Path -LiteralPath $Payload -PathType Leaf)) { throw "Missing payload: $Payload" }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$parent = Split-Path $InstallRoot -Parent
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$stage = Join-Path $parent ('.sysmon-stage-' + [guid]::NewGuid().ToString('N'))
$backup = Join-Path $parent ('.sysmon-backup-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
$swapped = $false
try {
    # .NET rejects zip-slip entries during extraction.
    [IO.Compression.ZipFile]::ExtractToDirectory($Payload, $stage)
    if (-not (Test-Path -LiteralPath (Join-Path $stage 'SysMon.Glass.exe'))) { throw 'Payload has no SysMon.Glass.exe.' }
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $stage 'uninstall.ps1')
    $files = @(Get-ChildItem -LiteralPath $stage -File -Recurse | ForEach-Object { $_.FullName.Substring($stage.Length + 1) })
    $effectiveAutoStart = if ($NoAutoStart) { $false } elseif ($existingInstall -and $null -ne $existingStartup) { $existingStartup } else { $true }
    @{ product = 'SysMon.Glass'; files = $files; autoStart = $effectiveAutoStart } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stage '.sysmon-install.json') -Encoding UTF8
    if (Test-Path -LiteralPath $InstallRoot) {
        # Antivirus scanners can hold files for a moment; a rushed move scatters the tree
        # across InstallRoot and backup. Retry, then merge anything already moved back.
        $moved = $false
        foreach ($attempt in 1..3) {
            try { Move-Item -LiteralPath $InstallRoot -Destination $backup -ErrorAction Stop; $moved = $true; break }
            catch { Start-Sleep -Milliseconds (400 * $attempt) }
        }
        if (-not $moved) {
            if (Test-Path -LiteralPath $backup) {
                Copy-Item -Path (Join-Path $backup '*') -Destination $InstallRoot -Recurse -Force
                Remove-Item -LiteralPath $backup -Recurse -Force
            }
            throw 'The previous installation is locked by another process. Close SysMon Glass and retry.'
        }
    }
    Move-Item -LiteralPath $stage -Destination $InstallRoot
    $swapped = $true
    $exe = Join-Path $InstallRoot 'SysMon.Glass.exe'
    $icon = if (Test-Path -LiteralPath (Join-Path $InstallRoot 'sysmon.ico')) { Join-Path $InstallRoot 'sysmon.ico' } else { $exe }
    foreach ($folder in @($desktop, $menu)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    if ($testing) {
        foreach ($link in $links) { Set-Content -LiteralPath $link -Value $exe }
    } else {
        $shell = New-Object -ComObject WScript.Shell
        foreach ($link in $links) {
            $shortcut = $shell.CreateShortcut($link); $shortcut.TargetPath = $exe
            $shortcut.WorkingDirectory = $InstallRoot; $shortcut.IconLocation = "$icon,0"; $shortcut.Save()
        }
        New-Item -Path $registry -Force | Out-Null
        $uninstallCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $InstallRoot 'uninstall.ps1') + '" -Uninstall -InstallRoot "' + $InstallRoot + '"'
        $values = @{ DisplayName = 'SysMon Glass'; DisplayVersion = '1.0.0'; Publisher = 'SysMon'; InstallLocation = $InstallRoot; DisplayIcon = "$icon,0"; UninstallString = $uninstallCommand; QuietUninstallString = "$uninstallCommand -Quiet" }
        foreach ($key in $values.Keys) { New-ItemProperty -Path $registry -Name $key -Value $values[$key] -PropertyType String -Force | Out-Null }
        New-ItemProperty -Path $registry -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $registry -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null
        New-Item -Path $runKey -Force | Out-Null
        if (-not $effectiveAutoStart) { Remove-ItemProperty -Path $runKey -Name 'SysMon.Glass' -ErrorAction SilentlyContinue }
        else { New-ItemProperty -Path $runKey -Name 'SysMon.Glass' -Value ('"' + $exe + '"') -PropertyType String -Force | Out-Null }
        # Seed the portable adapter's preference only on first install; never overwrite user settings.
        $settingsDir = Join-Path $env:APPDATA 'SysMon.Glass'
        $settingsPath = Join-Path $settingsDir 'settings.json'
        if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
            New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
            @{ StartupEnabled = $effectiveAutoStart } | ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding UTF8
        }
    }
} catch {
    if ($swapped -and (Test-Path -LiteralPath $InstallRoot)) {
        $failed = Join-Path $parent ('.sysmon-failed-' + [guid]::NewGuid().ToString('N'))
        Move-Item -LiteralPath $InstallRoot -Destination $failed
        Write-Warning "Failed installation preserved at $failed"
    }
    # Move-Item onto an existing directory nests instead of restoring; only rename back onto a free path.
    if ((Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $InstallRoot)) { Move-Item -LiteralPath $backup -Destination $InstallRoot }
    throw
}
# Keep previous tree on upgrade: it may contain user files. No recursive deletion of an old install.
if (Test-Path -LiteralPath $backup) { Write-Host "Previous installation retained at $backup" }
Write-Host "Installed to $InstallRoot. Taskbar pinning is a manual Windows action."
if (-not $testing -and -not $NoLaunch) { Start-Process -FilePath (Join-Path $InstallRoot 'SysMon.Glass.exe') }
