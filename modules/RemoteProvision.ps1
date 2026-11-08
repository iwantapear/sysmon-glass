# Remote provisioning: turn any reachable host into a monitored host.
# Everything here runs the user's own OpenSSH client; no passwords are stored and
# no new network listeners are opened on the target.
$script:remoteProbeScript=@'
#!/bin/sh
# SysMon Glass remote probe — prints key=value lines. Keep it dependency-free.
g=$(nvidia-smi --query-gpu=temperature.gpu,power.draw,utilization.gpu,memory.used,memory.total \
      --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
echo "gpu=$g"
echo "cpu=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1)"
echo "fan=$(cat /sys/class/hwmon/hwmon0/fan1_input 2>/dev/null)"
for h in /sys/class/hwmon/hwmon*; do
  if [ "$(cat "$h/name" 2>/dev/null)" = "nvme" ]; then
    echo "nvme=$(cat "$h/temp1_input" 2>/dev/null)"
  fi
done
echo "mem=$(free -m | awk '/^Mem:/{print $3" "$2}')"
echo "load=$(awk '{print $1}' /proc/loadavg)"
echo "up=$(awk '{print int($1/3600)}' /proc/uptime)"
'@

function Get-RemoteTarget([string]$HostName,[string]$User) {
    if([string]::IsNullOrWhiteSpace($User)){ return $HostName }
    "$User@$HostName"
}
function Test-RemoteHostString([string]$HostName) {
    # IPv4, hostnames and IPv6 (bare or [bracketed]) are all acceptable.
    if([string]::IsNullOrWhiteSpace($HostName)){ return $false }
    if($HostName.Length -gt 253){ return $false }
    if($HostName -notmatch '^[A-Za-z0-9\[:]'){ return $false }        # no leading dash or space
    if($HostName -notmatch '^[A-Za-z0-9._:\[\]-]+$'){ return $false } # safe charset only
    if($HostName -notmatch '[A-Za-z0-9]'){ return $false }            # must carry data
    $true
}
function Get-RemoteSshArgs([string]$HostName,[string]$User,[int]$Port,[string[]]$Extra,[switch]$Batch) {
    $args=[Collections.Generic.List[string]]::new()
    foreach($option in @('ConnectTimeout=8','ServerAliveInterval=15','ServerAliveCountMax=2','ClearAllForwardings=yes','ForwardAgent=no','ForwardX11=no','RequestTTY=no','PermitLocalCommand=no')) {
        $args.Add('-o'); $args.Add($option)
    }
    if($Batch){ $args.Add('-o'); $args.Add('BatchMode=yes') }
    $args.Add('-o'); $args.Add('StrictHostKeyChecking=yes')
    $args.Add('-T'); $args.Add('-p'); $args.Add([string]$Port)
    $args.Add('--'); $args.Add((Get-RemoteTarget $HostName $User))
    # The remote command must come AFTER the destination: ssh reads anything earlier
    # as an option, or as the host itself ("hostname contains invalid characters").
    if($Extra){ foreach($e in $Extra){ $args.Add($e) } }
    ,$args.ToArray()
}
# Single-quote a remote path for sh, keeping ~/ expandable: sh '~/x' never expands,
# so the tail is quoted and $HOME is left for the remote shell to expand.
function Get-RemoteQuotedPath([string]$ProbePath) {
    $tail=$ProbePath.Replace([string][char]39, ([string][char]39)+'\'+([string][char]39)+([string][char]39))
    if($ProbePath.StartsWith('~/')){ return '"$HOME"/'+([string][char]39)+$tail.Substring(2)+([string][char]39) }
    ([string][char]39)+$tail+([string][char]39)
}
function Invoke-RemoteProcess([string]$FileName,[string[]]$Arguments,[string]$InputText,[int]$TimeoutMs=20000) {
    $start=[Diagnostics.ProcessStartInfo]::new($FileName)
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true; $start.RedirectStandardInput=$true
    foreach($a in $Arguments){ $start.ArgumentList.Add($a) }
    try { $process=[Diagnostics.Process]::Start($start) } catch { return @{ Code=-1; Out=''; Err=$_.Exception.Message } }
    if($null -ne $InputText){ try { $process.StandardInput.Write($InputText) } catch { } }
    try { $process.StandardInput.Close() } catch { }
    $outTask=$process.StandardOutput.ReadToEndAsync(); $errTask=$process.StandardError.ReadToEndAsync()
    if(-not $process.WaitForExit($TimeoutMs)){
        try { $process.Kill($true) } catch { }
        return @{ Code=-9; Out=''; Err=('timed out after {0} ms' -f $TimeoutMs) }
    }
    @{ Code=$process.ExitCode; Out=$outTask.GetAwaiter().GetResult(); Err=$errTask.GetAwaiter().GetResult() }
}
function Get-RemoteKnownHostsPath { Join-Path $env:USERPROFILE '.ssh\known_hosts' }
function Trust-RemoteHostKey([string]$HostName,[int]$Port) {
    if(-not (Test-RemoteHostString $HostName)){ throw 'Host name is not valid.' }
    $result=Invoke-RemoteProcess 'ssh-keyscan' @('-T','8','-p',[string]$Port,$HostName) $null 15000
    $lines=@($result.Out -split "`n" | Where-Object { $_ -and $_ -notmatch '^\s*#' })
    if($result.Code -ne 0 -or $lines.Count -eq 0){
        $detail=($result.Err -split "`n" | Where-Object { $_ } | Select-Object -First 1)
        throw ('ssh-keyscan found no host keys: ' + $detail)
    }
    $path=Get-RemoteKnownHostsPath
    $dir=Split-Path $path -Parent
    if(-not (Test-Path -LiteralPath $dir)){ New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $existing=@()
    if(Test-Path -LiteralPath $path){ $existing=@(Get-Content -LiteralPath $path | Where-Object { $_ -and $_ -notmatch '^\s*#' }) }
    $added=0
    foreach($line in $lines){
        if($existing -contains $line){ continue }
        Add-Content -LiteralPath $path -Value $line -Encoding ascii
        $added++
    }
    @{ added=$added; total=$lines.Count; sample=$lines[0] }
}
function Deploy-RemoteProbe([string]$HostName,[string]$User,[int]$Port,[string]$ProbePath) {
    if(-not (Test-RemoteHostString $HostName)){ throw 'Host name is not valid.' }
    if([string]::IsNullOrWhiteSpace($ProbePath)){ $ProbePath='~/.sysmon.sh' }
    $quoted=Get-RemoteQuotedPath $ProbePath
    $remote="umask 077; cat > $quoted && chmod 700 $quoted && echo __DEPLOYED__"
    $sshArgs=Get-RemoteSshArgs $HostName $User $Port @($remote) -Batch
    $result=Invoke-RemoteProcess 'ssh' $sshArgs ($script:remoteProbeScript) 25000
    if($result.Code -ne 0 -or $result.Out -notmatch '__DEPLOYED__'){
        $detail=(($result.Err -split "`n") | Where-Object { $_ } | Select-Object -First 2) -join ' / '
        throw ('Probe deployment failed: ' + $detail)
    }
    @{ ok=$true; path=$ProbePath }
}
function Test-RemoteConnection([string]$HostName,[string]$User,[int]$Port,[string]$ProbePath) {
    if(-not (Test-RemoteHostString $HostName)){ throw 'Host name is not valid.' }
    if([string]::IsNullOrWhiteSpace($ProbePath)){ $ProbePath='~/.sysmon.sh' }
    $remote='sh ' + (Get-RemoteQuotedPath $ProbePath)
    $sshArgs=Get-RemoteSshArgs $HostName $User $Port @($remote) -Batch
    $result=Invoke-RemoteProcess 'ssh' $sshArgs $null 20000
    if($result.Code -ne 0){
        $detail=(($result.Err -split "`n") | Where-Object { $_ } | Select-Object -First 2) -join ' / '
        throw ('Connection failed: ' + $detail)
    }
    $pairs=@{}
    foreach($line in ($result.Out -split "`n")){
        $trim=$line.Trim()
        $i=$trim.IndexOf('=')
        if($i -gt 0){ $pairs[$trim.Substring(0,$i)]=$trim.Substring($i+1) }
    }
    if($pairs.Count -eq 0){ throw 'Connected, but the probe printed no key=value lines.' }
    @{ ok=$true; keys=@($pairs.Keys); sample=$result.Out.Trim() }
}
