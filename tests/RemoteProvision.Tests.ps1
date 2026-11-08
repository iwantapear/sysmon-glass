$ErrorActionPreference='Stop'
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Run with -STA'}
$env:SYSMON_CONFIG_HOME=Join-Path $env:TEMP ('sysmon-remote-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $env:SYSMON_CONFIG_HOME -Force | Out-Null
. (Join-Path $PSScriptRoot '../glass.ps1') -PrepareOnly
function Assert($ok,[string]$msg){ if(-not $ok){ throw $msg } }

# --- address forms -----------------------------------------------------------------
foreach($good in @('192.0.2.10','198.51.100.7','dgx','my-host.local','::1','fe80::1','[::1]')){
    Assert (Test-RemoteHostString $good) "valid address rejected: $good"
}
foreach($bad in @('','   ','host name','host;rm -rf /','host`nuser','-oProxyCommand=x','a'.PadRight(300,'b'))){
    Assert (-not (Test-RemoteHostString $bad)) ("invalid address accepted: " + ($bad -replace "`n",'\n'))
}

# --- ssh argv is built with quoting-safe options, never a shell string --------------
$args=Get-RemoteSshArgs '192.0.2.10' 'pi' 2222 @("sh ~/.sysmon.sh") -Batch
Assert ($args -contains '-T') 'ssh must disable tty'
Assert ($args -contains '2222') 'port must be passed'
Assert ($args -contains 'StrictHostKeyChecking=yes') 'host key checking must stay strict'
Assert ($args -contains 'BatchMode=yes') 'batch mode must be requested for automation'
Assert ($args[($args.Count-3)] -eq '--') 'arguments must be separated from the target by --'
Assert ($args[$args.Count-2] -eq 'pi@192.0.2.10') 'target must be user@host'
Assert ($args[$args.Count-1] -eq "sh ~/.sysmon.sh") 'remote command must follow the target as one argv element'
$ipv6Args=Get-RemoteSshArgs '::1' '' 22 @() -Batch
Assert ($ipv6Args[$ipv6Args.Count-1] -eq '::1') 'IPv6 without user must stay bare'
Assert ($ipv6Args[$ipv6Args.Count-2] -eq '--') 'IPv6 target must still follow --'

# --- provisioning flow: Invoke-RemoteProcess is shadowed, no process is started ----
$script:sshCalls=@()
function Invoke-RemoteProcess([string]$FileName,[string[]]$Arguments,[string]$InputText,[int]$TimeoutMs=20000) {
    $script:sshCalls+=,@($FileName,$Arguments,$InputText)
    if($FileName -eq 'ssh-keyscan'){
        return @{ Code=0; Out="192.0.2.10 ssh-ed25519 AAAAC3NzaTESTKEY`n192.0.2.10 ssh-rsa AAAAB3NzaTESTKEY"; Err='' }
    }
    $joined=$Arguments -join ' '
    if($joined -match 'cat >'){ return @{ Code=0; Out="__DEPLOYED__`n"; Err='' } }
    return @{ Code=0; Out="gpu=42,55,10,1024,8192`ncpu=48000`nmem=3000 32000`nload=0.42`nup=26"; Err='' }
}
$tmpHome=Join-Path $env:TEMP ('sysmon-home-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpHome -Force | Out-Null
$oldProfile=$env:USERPROFILE
$env:USERPROFILE=$tmpHome
try {
    $r1=Trust-RemoteHostKey '192.0.2.10' 22
    Assert ($r1.added -eq 2) "trust must add both host keys (got $($r1.added))"
    $known=Join-Path $tmpHome '.ssh\known_hosts'
    Assert (Test-Path -LiteralPath $known) 'known_hosts must be created'
    $r2=Trust-RemoteHostKey '192.0.2.10' 22
    Assert ($r2.added -eq 0) 'trusting twice must not duplicate entries'
    Assert (@(Get-Content -LiteralPath $known).Count -eq 2) 'known_hosts line count must stay stable'

    $deploy=Deploy-RemoteProbe '192.0.2.10' 'pi' 22 '~/.sysmon.sh'
    Assert ($deploy.ok) 'probe deployment must report success on __DEPLOYED__'
    $deployCall=$script:sshCalls[-1]
    Assert ($deployCall[2] -match 'nvidia-smi') 'the probe script must be piped to ssh stdin'
    Assert (($deployCall[1] -join ' ') -match 'chmod 700') 'deployment must set 700 permissions'
    Assert (($deployCall[1] -join ' ') -match 'pi@192\.0\.2\.10') 'deployment must target user@ip'

    $probe=Test-RemoteConnection '192.0.2.10' 'pi' 22 '~/.sysmon.sh'
    Assert ($probe.ok) 'connection test must succeed on probe output'
    Assert ($probe.keys -contains 'gpu' -and $probe.keys -contains 'mem') 'connection test must parse probe fields'
    Assert ($probe.keys.Count -eq 5) "all probe fields must be parsed (got $($probe.keys.Count))"

    # a failing scan must surface the ssh error text
    function Invoke-RemoteProcess([string]$FileName,[string[]]$Arguments,[string]$InputText,[int]$TimeoutMs=20000) {
        @{ Code=1; Out=''; Err="getaddrinfo failed for 192.0.2.10`n" }
    }
    $threw=$false
    try { Trust-RemoteHostKey '192.0.2.10' 22 | Out-Null } catch { $threw=$true; $message=$_.Exception.Message }
    Assert $threw 'a failed keyscan must raise'
    Assert ($message -match 'getaddrinfo') 'the keyscan error text must be surfaced'

    # a probe that prints nothing usable must be reported honestly
    function Invoke-RemoteProcess([string]$FileName,[string[]]$Arguments,[string]$InputText,[int]$TimeoutMs=20000) {
        @{ Code=0; Out="command not found`n"; Err='' }
    }
    $threw=$false
    try { Test-RemoteConnection '192.0.2.10' 'pi' 22 '~/.sysmon.sh' | Out-Null } catch { $threw=$true; $message=$_.Exception.Message }
    Assert $threw 'an empty probe must raise'
    Assert ($message -match 'no key=value') 'the empty-probe message must be explicit'
} finally {
    $env:USERPROFILE=$oldProfile
    if($tmpHome){ Remove-Item -LiteralPath $tmpHome -Recurse -Force -ErrorAction SilentlyContinue }
}

# --- profile validation accepts an IP and rejects junk -----------------------------
$profile=ConvertTo-RemoteHostProfile @{id='box';name='Box';sshHost='192.0.2.10';user='pi';port=22;probe='~/.sysmon.sh';enabled=$true}
Assert ($profile.sshHost -eq '192.0.2.10') 'profile must keep the IP'
$rejected=$false
try { ConvertTo-RemoteHostProfile @{id='box2';name='Box';sshHost='bad host';user='';port=22;probe='~/.sysmon.sh';enabled=$true} | Out-Null } catch { $rejected=$true }
Assert $rejected 'profile validation must reject a host with spaces'

$script:exiting=$true; $window.Close(); $script:tray.Dispose(); $menu.Dispose(); $script:trayFont.Dispose(); $script:trayBitmap.Dispose()
Remove-Item -Path $env:SYSMON_CONFIG_HOME -Recurse -Force -ErrorAction SilentlyContinue
'Remote provisioning regression PASS'
