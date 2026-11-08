param([switch]$SkipBuild, [switch]$Sign)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$root=$PSScriptRoot; $source=(Split-Path (Split-Path $root -Parent) -Parent)
$out=Join-Path $root 'artifacts'; $payload=Join-Path $out 'payload'
$payload=[IO.Path]::GetFullPath($payload)
if($payload -ne [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'artifacts\payload'))){throw 'Unexpected payload directory'}
if(Test-Path -LiteralPath $payload){Remove-Item -LiteralPath $payload -Recurse -Force}
$app=Join-Path $payload 'app'; New-Item -ItemType Directory -Path $app -Force | Out-Null
$copy=@('glass.ps1','sysmon.ps1','dgx_probe.sh','README.md','locale','modules','native','tests','ui')
foreach($item in $copy){$from=Join-Path $source $item; if(-not(Test-Path $from)){throw "Missing source: $item"}; Copy-Item $from (Join-Path $app $item) -Recurse -Force}
# Deliberately exclude backups, portable, evidence, generated screenshots, and source configs.
Copy-Item (Join-Path $root 'sysmon.ico') (Join-Path $payload 'sysmon.ico') -Force
if(-not $SkipBuild){dotnet publish (Join-Path $root 'launcher\SysMon.Glass.csproj') -c Release -r win-x64 --self-contained true -o (Join-Path $out 'launcher') -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true; if($LASTEXITCODE){throw 'Launcher build failed'}}
# Sign before packaging so the embedded launcher inside payload.zip is signed too.
if($Sign){& (Join-Path $root 'sign.ps1') -CreateIfMissing -Targets @(Join-Path $out 'launcher\SysMon.Glass.exe')}
Copy-Item (Join-Path $out 'launcher\SysMon.Glass.exe') (Join-Path $payload 'SysMon.Glass.exe') -Force
Move-Item (Join-Path $payload 'app') (Join-Path $payload 'app-temp') -Force
New-Item -ItemType Directory -Path (Join-Path $payload 'app') -Force | Out-Null
Get-ChildItem (Join-Path $payload 'app-temp') -Force | Move-Item -Destination (Join-Path $payload 'app') -Force
Remove-Item (Join-Path $payload 'app-temp') -Recurse -Force
$zip=Join-Path $out 'SysMon.Glass-WPF-win-x64.zip'; Compress-Archive (Join-Path $payload '*') $zip -Force
$setup=(Join-Path $root 'setup\SysMon.Glass.Setup.csproj')
dotnet publish $setup -c Release -r win-x64 --self-contained true -o (Join-Path $out 'setup') -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:RequirePayload=true "-p:PayloadZip=$zip"
if($LASTEXITCODE){throw 'Setup build failed; no release installer was copied'}
if($Sign){& (Join-Path $root 'sign.ps1') -Targets @(Join-Path $out 'setup\SysMon.Glass.Setup.exe') -ExportPublic}
Copy-Item (Join-Path $out 'setup\SysMon.Glass.Setup.exe') (Join-Path $out 'SysMon.Glass.WPF.Setup.exe') -Force
Write-Host "WPF payload: $zip"; Write-Host "WPF setup: $(Join-Path $out 'SysMon.Glass.WPF.Setup.exe')"
