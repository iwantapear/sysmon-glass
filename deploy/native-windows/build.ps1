$ErrorActionPreference = 'Stop'
$app = Join-Path $PSScriptRoot '../../cpp/app'
$compiler = 'C:\msys64\ucrt64\bin\g++.exe'
$windres = 'C:\msys64\ucrt64\bin\windres.exe'
& (Join-Path $app 'build.ps1')
Push-Location $PSScriptRoot
try {
    & $windres -F pe-x86-64 setup.rc -O coff -o setup-res.o
    if ($LASTEXITCODE) { throw 'Failed to embed the x64 application in setup.' }
    & $compiler -std=c++20 -m64 -O2 -static -municode -mwindows setup.cpp setup-res.o -o SysMon.Glass.Native.Setup-x64.exe -lole32 -lshell32 -luuid -ladvapi32
    if ($LASTEXITCODE) { throw 'Native Windows x64 setup build failed.' }
    Get-Item -LiteralPath SysMon.Glass.Native.Setup-x64.exe
} finally { Pop-Location }
