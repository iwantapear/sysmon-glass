param([switch]$Sign)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$gpp='C:\msys64\ucrt64\bin\g++.exe'
$windres='C:\msys64\ucrt64\bin\windres.exe'
if(-not (Test-Path $windres)){ $windres='C:\msys64\ucrt64\bin\x86_64-w64-mingw32-windres.exe' }
if(-not (Test-Path $gpp)){ throw 'MSYS2 g++ not found. Install MSYS2 in C:\msys64 or edit build.ps1.' }
if(Test-Path $windres){
    & $windres (Join-Path $root 'app.rc') -O coff -o (Join-Path $root 'app-res.o')
    if($LASTEXITCODE){ throw 'Icon resource compilation failed' }
}
$libraries=@('d2d1','dwrite','dwmapi','comctl32','ole32','oleaut32','uuid','uiautomationcore','iphlpapi','shell32','gdi32','user32')
$args=@('-std=c++20','-O2','-mwindows','-DUNICODE','-D_UNICODE','-o',(Join-Path $root 'sysmon.exe'),(Join-Path $root 'app.cpp'))
if(Test-Path (Join-Path $root 'app-res.o')){ $args+=(Join-Path $root 'app-res.o') }
$args+=($libraries | ForEach-Object { '-l'+$_ })
& $gpp @args
if($LASTEXITCODE){ throw 'Native build failed' }
if($Sign){ & (Join-Path $root '..\..\deploy\wpf-release\sign.ps1') -Targets (Join-Path $root 'sysmon.exe') }
Get-Item (Join-Path $root 'sysmon.exe') | Select-Object FullName,Length,LastWriteTime
