$ErrorActionPreference = 'Stop'
$compiler = 'C:\msys64\ucrt64\bin\g++.exe'
$output = Join-Path $PSScriptRoot 'json-regression.exe'
try {
    & $compiler -std=c++20 -Wall -Wextra -pedantic -static-libgcc -static-libstdc++ (Join-Path $PSScriptRoot 'json-regression.cpp') -o $output
    if ($LASTEXITCODE -ne 0) { throw 'JSON regression compilation failed' }
    & $output
    if ($LASTEXITCODE -ne 0) { throw 'JSON regressions failed' }
} finally {
    if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output }
}
