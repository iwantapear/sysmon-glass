function Put-Number($key, $value) {
    if ($null -eq $value) { return }
    $n = 0.0
    if ([double]::TryParse(([string]$value).Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$n) -and -not [double]::IsNaN($n) -and -not [double]::IsInfinity($n)) { $script:values[$key] = $n }
}
function Read-Values {
    Read-LocalIO
    foreach($key in @('cpu','cpuPwr','vrm','pch','cpuDuty','cpuRpm','caseDuty','caseRpm','pumpRpm','pumpDuty','gpuT','gpuPwr','gpuUtil','dgxGpuT','dgxGpuPwr','dgxGpuUtil','dgxCpu','dgxFan','dgxNvme','dgxLoad','dgxUp','dgxMem','dgxMemTot','dgxMemPct')) { $script:values.Remove($key) }
    try {
        if (Test-Path -LiteralPath $STATE) {
            $s=Get-Content -LiteralPath $STATE -Raw | ConvertFrom-Json
            $age=if($s.updatedAt){((Get-Date)-[datetime]$s.updatedAt).TotalSeconds}else{[double]::PositiveInfinity}
            if ($s.running -and $age -ge -5 -and $age -lt 15) {
                Put-Number 'cpu' $s.cpu; Put-Number 'cpuPwr' $s.cpuPower; Put-Number 'vrm' $s.vrm; Put-Number 'pch' $s.pch
                Put-Number 'cpuDuty' $s.cpuDuty; Put-Number 'cpuRpm' $s.cpuRpm; Put-Number 'caseDuty' $s.caseDuty
                if ($s.caseRpm) { Put-Number 'caseRpm' (($s.caseRpm | Measure-Object -Maximum).Maximum) }
                Put-Number 'pumpRpm' $s.pumpRpm; Put-Number 'pumpDuty' $s.pumpDuty
            }
        }
    } catch { /* Sensor sources come and go at runtime; absence is normal. */ }
    $g=$script:gpu.Last; if($g -and $script:gpu.AgeSec -ge 0 -and $script:gpu.AgeSec -lt 15) { $p=($g.Trim() -split "`n")[0] -split ','; if($p.Count -ge 3) { Put-Number 'gpuT' $p[0]; Put-Number 'gpuPwr' $p[1]; Put-Number 'gpuUtil' $p[2] }; if($p.Count -ge 4) { Put-Number 'gpuMem' $p[3] }; if($p.Count -ge 5) { Put-Number 'gpuMemTot' $p[4] }; if($p.Count -ge 6 -and $p[5].Trim() -match '^\d+$') { Put-Number 'gpuFan' $p[5] }; if($p.Count -ge 7) { Put-Number 'gpuClock' $p[6] } }
    $remotePoller=$script:dgx
    $g=$remotePoller.Get('gpu'); if($g) { $p=$g -split ','; if($p.Count -ge 3) { Put-Number 'dgxGpuT' $p[0]; Put-Number 'dgxGpuPwr' $p[1]; Put-Number 'dgxGpuUtil' $p[2] } }
    foreach($entry in @(@('cpu','dgxCpu',1000),@('fan','dgxFan',1),@('nvme','dgxNvme',1000),@('load','dgxLoad',1),@('up','dgxUp',1))) {
        $raw=$remotePoller.Get($entry[0]); $n=0.0
        if([double]::TryParse($raw,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$n)) { Put-Number $entry[1] ($n / $entry[2]) }
    }
    $m=$script:dgx.Get('mem'); if($m) { $p=$m -split '\s+'; $used=0.0; $total=0.0; if($p.Count -ge 2 -and [double]::TryParse($p[0],[ref]$used) -and [double]::TryParse($p[1],[ref]$total)) { Put-Number 'dgxMem' ($used/1024); Put-Number 'dgxMemTot' ($total/1024); if($total -gt 0) { Put-Number 'dgxMemPct' (100*$used/$total) } } }
    if($script:dgx.AgeSec -lt 0 -or $script:dgx.AgeSec -ge 8) {
        foreach($key in @('dgxGpuT','dgxGpuPwr','dgxGpuUtil','dgxCpu','dgxFan','dgxNvme','dgxLoad','dgxUp','dgxMem','dgxMemTot','dgxMemPct')) { $script:values.Remove($key) }
    }
    foreach($entry in @(@('cpu','cpu'),@('dgxGpuT','dgx'))) { if($script:values.ContainsKey($entry[0])) { $list=$script:history[$entry[1]]; $list.Add($script:values[$entry[0]]); if($list.Count -gt 60) {$list.RemoveAt(0)} } }
    # Rolling history for every card so each one can show max/min/avg and a curve.
    # 'cpu' is skipped: it already appends through the alias list above.
    foreach($key in @($script:values.Keys)) {
        if($key -eq 'cpu'){continue}
        if(-not $script:history.ContainsKey($key)){$script:history[$key]=[Collections.Generic.List[double]]::new()}
        $list=$script:history[$key]
        $list.Add([double]$script:values[$key])
        if($list.Count -gt 60){$list.RemoveAt(0)}
    }
    # Drop history for sensors that went away, so stale stats never linger.
    foreach($key in @($script:history.Keys)) {
        if($key -in @('cpu','dgx')){continue}
        if(-not $script:values.ContainsKey($key)){$script:history.Remove($key)}
    }
}
