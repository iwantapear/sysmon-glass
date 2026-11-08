# Standalone, non-destructive remote configuration/security checks; no SSH connection is made.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Add-Type -Path (Join-Path $root 'native/Pollers.cs')
function Assert($Condition,[string]$Message) { if(-not $Condition){throw $Message} }
function Reject([scriptblock]$Action,[string]$Message) {
    $rejected=$false; try { & $Action } catch { $rejected=$true }; Assert $rejected $Message
}
$script:AppRoot=Join-Path $env:TEMP ('sysmon-hosts-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:AppRoot | Out-Null
$script:themeOrder=@('dark','light'); $script:languages=@{'zh-CN'='Chinese'}; $Preset=$null
try {
    . (Join-Path $root 'modules/Config.ps1')
    Assert ($script:cfg.activeHostId -eq 'dgx') 'Default dgx was not preserved.'
    $valid=ConvertTo-RemoteHostProfile @{id='other';sshHost='other-server';user='monitor';port=2222;enabled=$true}
    Assert ($valid.probe -eq '~/.sysmon.sh' -and $valid.port -eq 2222) 'Defaults/port failed.'
    foreach($field in @('id','sshHost','user','probe','port','enabled')) {
        $profile=@{id='other';sshHost='other';user='monitor';probe='~/.sysmon.sh';port=22;enabled=$true}
        $profile[$field]=switch($field){'id'{'bad id'} 'sshHost'{'-oProxyCommand=evil'} 'user'{"evil`nuser"} 'probe'{"~/.x' ; evil ; '"} 'port'{'22'} 'enabled'{'false'}}
        Reject { ConvertTo-RemoteHostProfile $profile } "Invalid $field was accepted."
    }
    $script:cfg.hosts=@((Get-DefaultRemoteHost),$valid); $script:cfg.activeHostId='other'; Initialize-RemoteHosts
    Assert ($script:cfg.activeHostId -eq 'other' -and $script:cfg.hosts.Count -eq 2) 'Configured selection was not preserved.'
    $script:cfg.hosts[1].enabled=$false; Initialize-RemoteHosts
    Assert ($script:cfg.activeHostId -eq 'dgx') 'Disabled selection did not fall back.'
    $script:cfg.hosts=@(); Initialize-RemoteHosts
    Assert ($script:cfg.activeHostId -eq '' -and $script:cfg.hosts.Count -eq 0) 'Explicit no-host configuration was ignored.'
    $script:cfg.hosts=@((Get-DefaultRemoteHost),(Get-DefaultRemoteHost)); Initialize-RemoteHosts -WarningAction SilentlyContinue
    Assert ($script:cfg.hosts.Count -eq 1) 'Duplicate host IDs accepted.'
    $poller=[SysMonGlass.DgxPoller]::new()
    $poller.Configure('other','monitor',2222,'~/.sysmon.sh')
    $start=$poller.CreateStartInfo(); $args=@($start.ArgumentList)
    Assert ($args -contains 'StrictHostKeyChecking=yes') 'Strict SSH checking missing.'
    Assert ($args -contains 'BatchMode=yes' -and $args -contains 'PermitLocalCommand=no') 'Non-interactive/local command protection missing.'
    Assert ($args[-2] -eq 'monitor@other' -and $args[-3] -eq '--') 'SSH destination is not separated from options.'
    Assert ($args[-1] -eq 'while true; do sh "$HOME"/''.sysmon.sh'' && echo __END__; sleep 2; done') 'Probe was not shell quoted.'
    foreach($bad in @("host`n-oProxyCommand=evil",'host@other','-host','host;evil','host$(evil)')) { Reject {$poller.Configure($bad,'',22,'~/.sysmon.sh')} 'Bad SSH destination accepted.' }
    foreach($bad in @('~/.sysmon.sh;evil',"foo`nbar",'-option','foo bar','foo>bar','foo$(evil)')) { Reject {$poller.Configure('dgx','',22,$bad)} 'Bad probe accepted.' }
    $poller.Stop(); Assert ($poller.AgeSec -eq -1) 'Stopped poller retained freshness.'
    $flags=[Reflection.BindingFlags]'NonPublic,Static'
    $readLine=[SysMonGlass.DgxPoller].GetMethod('ReadBoundedLine',$flags)
    Assert ($readLine.Invoke($null,@([IO.StringReader]::new("cpu=1`n"))) -eq 'cpu=1') 'Bounded line reader changed valid output.'
    Reject { $readLine.Invoke($null,@([IO.StringReader]::new(('x'*4097)))) } 'Oversize output line was accepted.'
    $recordError=[SysMonGlass.DgxPoller].GetMethod('RecordError',[Reflection.BindingFlags]'NonPublic,Instance')
    $recordError.Invoke($poller,@('x'*1024))
    Assert ($poller.LastError.Length -eq 512) 'Remote diagnostics are unbounded.'
    $gpu=[SysMonGlass.GpuPoller]::new()
    $gpuType=$gpu.GetType(); $readGpu=$gpuType.GetMethod('ReadBoundedOutput',[Reflection.BindingFlags]'NonPublic,Static')
    $small=[IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes('1,2,3'))
    Assert ($readGpu.Invoke($null,@($small)) -eq '1,2,3') 'GPU bounded output rejected valid data.'
    Reject { $readGpu.Invoke($null,@([IO.MemoryStream]::new((,[byte]65*131073)))) } 'GPU output limit was not enforced.'
    $gpuError=$gpuType.GetMethod('RecordError',[Reflection.BindingFlags]'NonPublic,Instance')
    $gpuError.Invoke($gpu,@('e'*1024)); Assert ($gpu.LastError.Length -eq 512) 'GPU diagnostics are unbounded.'
    $gpu.Start(); $gpu.Start(); $gpu.Stop(); $gpu.Stop(); Assert ($gpu.AgeSec -eq -1) 'GPU Start/Stop was not idempotent.'
    $runOnce=$gpuType.GetMethod('RunOnce',[Reflection.BindingFlags]'NonPublic,Instance')
    $fake=[Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    foreach($arg in @('-NoProfile','-NonInteractive','-Command','[Console]::Error.Write(''test diagnostic''); [Console]::Out.Write(''1,2,3'')')) { $fake.ArgumentList.Add($arg) }
    Assert ($runOnce.Invoke($gpu,@($fake,8000)) -eq '1,2,3' -and $gpu.LastError -eq 'test diagnostic') 'Fake GPU subprocess output/stderr handling failed.'
    $hung=[Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    foreach($arg in @('-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 30')) { $hung.ArgumentList.Add($arg) }
    $clock=[Diagnostics.Stopwatch]::StartNew()
    Reject { $runOnce.Invoke($gpu,@($hung,200)) } 'Hung GPU subprocess was not timed out.'
    Assert ($clock.Elapsed.TotalSeconds -lt 5) 'GPU subprocess timeout did not terminate promptly.'
    Save-Config
    $saved=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    Assert ($saved.hosts[0].id -eq 'dgx' -and $saved.hosts[0].enabled -eq $true) 'Host profile save roundtrip failed.'
    # Load only the selection function's real AST, without constructing a window.
    $ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'modules/View.ps1'),[ref]$null,[ref]$null)
    $functionAst=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Set-RemoteHost'},$true)
    . ([scriptblock]::Create($functionAst.Extent.Text))
    $script:dgx=$poller; $script:values=@{dgxGpuT=99;cpu=50}; $script:history=@{dgx=[Collections.Generic.List[double]]::new()}; $script:history.dgx.Add(99)
    $script:cfg.hosts=@((Get-DefaultRemoteHost),$valid); $valid.enabled=$true; $script:remotePollingStarted=$false
    Set-RemoteHost 'other' $false
    Assert ($script:cfg.activeHostId -eq 'other' -and $script:dgx.CreateStartInfo().ArgumentList[-2] -eq 'monitor@other-server') 'Runtime selection did not configure poller.'
    Assert (-not $script:values.ContainsKey('dgxGpuT') -and $script:values.cpu -eq 50 -and $script:history.dgx.Count -eq 0) 'Switch retained remote data or removed local data.'
    $valid.enabled=$false
    Reject { Set-RemoteHost 'other' $false } 'Disabled runtime selection was accepted.'
    Assert ($script:cfg.activeHostId -eq 'other') 'Rejected selection changed active host.'
    Set-RemoteHost 'dgx' $true
    Assert ((Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json).activeHostId -eq 'dgx') 'Runtime selection was not persisted.'
    Set-RemoteHost '' $false
    Assert ($script:cfg.activeHostId -eq '' -and $null -eq $script:activeRemoteHost -and $script:history.dgx.Count -eq 0) 'Remote host clearing did not stop and clear state.'
    'PASS: default, profile validation, enabled selection, empty/duplicate hosts, SSH options/quoting/injection, stop, JSON roundtrip, runtime switch/cache clearing'
} finally {
    # Only delete the unique temporary directory created by this test.
    if($script:AppRoot -like "$env:TEMP\sysmon-hosts-*") { Remove-Item -LiteralPath $script:AppRoot -Recurse -Force }
}
