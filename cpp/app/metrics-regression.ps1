$ErrorActionPreference = 'Stop'
$compiler = 'C:\msys64\ucrt64\bin\g++.exe'
$build = Join-Path ([IO.Path]::GetTempPath()) ('sysmon-metrics-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $build | Out-Null
try {
    $exe = Join-Path $build 'metrics-regression.exe'
    & $compiler '-std=c++20' '-O2' '-DUNICODE' '-D_UNICODE' '-static' (Join-Path $PSScriptRoot 'metrics-regression.cpp') '-o' $exe '-liphlpapi' '-lshell32' '-lole32' '-lpsapi'
    if ($LASTEXITCODE -ne 0) { throw 'Metrics regression compilation failed' }
    & $exe
    if ($LASTEXITCODE -ne 0) { throw 'Metrics regressions failed' }
} finally {
    Remove-Item -LiteralPath $build -Recurse -Force
}
