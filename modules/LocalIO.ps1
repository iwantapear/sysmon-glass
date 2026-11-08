function Get-NetworkRates($Previous,$Current,[double]$Elapsed) {
    if($Elapsed -le 0) { return }
    $received=0.0; $sent=0.0; $matched=$false
    foreach($id in $Current.Keys) {
        if(-not $Previous.ContainsKey($id)) { continue }
        $down=$Current[$id].Down-$Previous[$id].Down
        $up=$Current[$id].Up-$Previous[$id].Up
        if($down -lt 0 -or $up -lt 0) { continue }
        $received+=$down; $sent+=$up; $matched=$true
    }
    if($matched) { @{ Down=$received/$Elapsed; Up=$sent/$Elapsed } }
}

function Read-LocalIO {
    foreach($key in @('netDown','netUp')) { $script:values.Remove($key) }
    $current=@{}
    try { $adapters=[Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() }
    catch { $adapters=@() }
    foreach($adapter in $adapters) {
        if($adapter.OperationalStatus -ne 'Up' -or $adapter.NetworkInterfaceType -in @('Loopback','Tunnel')) { continue }
        try {
            if(-not $adapter.GetIPProperties().GatewayAddresses.Count) { continue }
            $stats=$adapter.GetIPStatistics()
            $current[$adapter.Id]=@{ Down=$stats.BytesReceived; Up=$stats.BytesSent }
        } catch { /* Adapter enumeration can fail transiently (e.g. during sleep). */ }
    }
    $now=[Diagnostics.Stopwatch]::GetTimestamp()
    if($script:networkSample) {
        $elapsed=($now-$script:networkSample.Time)/[double][Diagnostics.Stopwatch]::Frequency
        $rates=Get-NetworkRates $script:networkSample.Counters $current $elapsed
        if($rates) { $script:values.netDown=$rates.Down; $script:values.netUp=$rates.Up }
    }
    $script:networkSample=@{ Time=$now; Counters=$current }

    if($script:lastDiskSample -and ($now-$script:lastDiskSample)/[double][Diagnostics.Stopwatch]::Frequency -lt 15){return}
    $script:lastDiskSample=$now
    foreach($key in @('diskPct','diskUsed','diskTotal')) { $script:values.Remove($key) }
    $script:diskDetail=''
    $used=0.0; $total=0.0
    try { $drives=[IO.DriveInfo]::GetDrives() }
    catch { $drives=@() }
    $volumes=foreach($drive in $drives) {
        if($drive.DriveType -ne 'Fixed') { continue }
        try {
            if(-not $drive.IsReady) { continue }
            $capacity=$drive.TotalSize
            if($capacity -le 0) { continue }
            $volumeUsed=$capacity-$drive.TotalFreeSpace
            $used+=$volumeUsed; $total+=$capacity
            '{0} {1:N0}%' -f $drive.Name.TrimEnd('\'),(100*$volumeUsed/$capacity)
        } catch { /* Individual drives can be unreadable; others still report. */ }
    }
    if($total -gt 0) {
        $script:values.diskPct=100*$used/$total
        $script:values.diskUsed=$used
        $script:values.diskTotal=$total
        $script:diskDetail=$volumes -join '  ·  '
    }
}

function Format-ByteValue([double]$Bytes,[bool]$Rate) {
    $units=@('B','KiB','MiB','GiB','TiB')
    $i=0
    while($Bytes -ge 1024 -and $i -lt $units.Count-1) { $Bytes/=1024; $i++ }
    $unit=$units[$i]
    if($Rate){$unit+='/s'}
    @{ Number=('{0:N1}' -f $Bytes); Unit=$unit }
}
