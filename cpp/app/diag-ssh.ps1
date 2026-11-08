$ErrorActionPreference='Continue'
# Is the app spawning ssh, and did the trace land anywhere?
$app = Get-Process sysmon -ErrorAction SilentlyContinue
Write-Host ("sysmon running: " + [bool]$app)
if($app){
    $children = Get-CimInstance Win32_Process -Filter ("ParentProcessId=" + $app.Id)
    Write-Host ("children: " + (($children | ForEach-Object { $_.Name }) -join ','))
}
$all = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'ssh.exe' }
Write-Host ("ssh.exe processes: " + @($all).Count)
foreach($p in $all){ Write-Host ("  " + $p.Name + " pid=" + $p.ProcessId + " parent=" + $p.ParentProcessId + " cmd=" + $p.CommandLine.Substring(0,[Math]::Min(120,$p.CommandLine.Length))) }
$log = Join-Path $env:TEMP 'sysmon-ssh.log'
Write-Host ("trace file exists: " + (Test-Path $log))
if(Test-Path $log){ Get-Content $log -Tail 2 | ForEach-Object { Write-Host ("  " + $_) } }
