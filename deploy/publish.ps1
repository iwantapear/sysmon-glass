param(
    [string[]]$Rids = @('win-x64', 'linux-x64', 'linux-arm64', 'osx-arm64', 'osx-x64'),
    [switch]$SkipSetup,
    [switch]$SkipApp
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$deploy = $PSScriptRoot
$source = Join-Path (Split-Path $deploy -Parent) 'portable'
$buildSource = Join-Path $deploy ('build-source-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $buildSource -Force | Out-Null
# Snapshot source, not bin/obj. This also avoids racing the developer's intermediate files.
Get-ChildItem -LiteralPath $source -Force | Where-Object { $_.Name -notin @('bin', 'obj', '.avalonia-build-tasks') } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $buildSource -Recurse -Force
}
$project = Join-Path $buildSource 'SysMon.Glass.csproj'
$artifacts = Join-Path $deploy 'artifacts'
New-Item -ItemType Directory -Path $artifacts -Force | Out-Null
foreach ($rid in $Rids) {
    if ($rid -notin @('win-x64', 'linux-x64', 'linux-arm64', 'osx-arm64', 'osx-x64')) { throw "Unsupported RID $rid" }
    $output = Join-Path $artifacts $rid
    if (-not $SkipApp) {
        # Keep compilation intermediates in deploy too; source and deploy remain separate.
        $obj = Join-Path $deploy "obj\app-$rid\"
        $bin = Join-Path $deploy "bin\app-$rid\"
        & dotnet publish $project -c Release -r $rid --self-contained true -o $output '-p:PublishSingleFile=true' '-p:IncludeNativeLibrariesForSelfExtract=true' '-p:EnableCompressionInSingleFile=true' '-p:DebugType=None' '-p:DebugSymbols=false' "-p:BaseIntermediateOutputPath=$obj" "-p:MSBuildProjectExtensionsPath=$obj" "-p:BaseOutputPath=$bin"
        if ($LASTEXITCODE -ne 0) { throw "Application publish failed for $rid" }
    }
    $exe = if ($rid -eq 'win-x64') { 'SysMon.Glass.exe' } else { 'SysMon.Glass' }
    if (-not (Test-Path -LiteralPath (Join-Path $output $exe))) { throw "Missing published binary for $rid" }
    Copy-Item -LiteralPath (Join-Path $deploy 'sysmon.png') -Destination (Join-Path $output 'sysmon.png') -Force
    if ($rid -eq 'win-x64') { Copy-Item -LiteralPath (Join-Path $deploy 'sysmon.ico') -Destination (Join-Path $output 'sysmon.ico') -Force }
    $script = if ($rid -eq 'win-x64') { 'install-windows.ps1' } elseif ($rid -like 'linux-*') { 'install-linux.sh' } else { 'install-macos.sh' }
    if ($rid -ne 'win-x64') { Copy-Item -LiteralPath (Join-Path $deploy $script) -Destination (Join-Path $output $script) -Force }
    $zip = Join-Path $artifacts "SysMon.Glass-$rid.zip"
    Compress-Archive -Path (Join-Path $output '*') -DestinationPath $zip -Force
    if ($rid -eq 'win-x64') {
        # Copy installer after zipping, avoiding payload self-inclusion on repeat builds.
        Copy-Item -LiteralPath (Join-Path $deploy $script) -Destination (Join-Path $artifacts 'install-windows.ps1') -Force
        Copy-Item -LiteralPath $zip -Destination (Join-Path $artifacts 'payload.zip') -Force
        if (-not $SkipSetup) {
            $setup = Join-Path $deploy 'windows-setup\SysMon.Glass.Setup.csproj'
            $setupOut = Join-Path $artifacts 'windows-setup'
            & dotnet publish $setup -c Release -r win-x64 --self-contained true -o $setupOut '-p:PublishSingleFile=true' '-p:IncludeNativeLibrariesForSelfExtract=true' '-p:EnableCompressionInSingleFile=true' '-p:DebugType=None' '-p:DebugSymbols=false' '-p:RequirePayload=true' "-p:PayloadZip=$zip"
            if ($LASTEXITCODE -ne 0) { throw 'Setup publish failed.' }
            Copy-Item -LiteralPath (Join-Path $setupOut 'SysMon.Glass.Setup.exe') -Destination (Join-Path $artifacts 'SysMon.Glass.Setup.exe') -Force
        }
    }
    Write-Host "Created $zip"
}
try { Remove-Item -LiteralPath $buildSource -Recurse -Force }
catch { Write-Warning "Published artifacts are complete; build snapshot is still in use and retained at $buildSource" }
