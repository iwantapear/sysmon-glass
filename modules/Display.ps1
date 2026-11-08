function Format-Value($key) {
    if (-not $script:values.ContainsKey($key)) { return '—' }
    switch ($key) { 'dgxLoad' { return ('{0:N2}' -f $script:values[$key]) }; 'dgxMem' { return ('{0:N1}' -f $script:values[$key]) }; default { return ('{0:N0}' -f $script:values[$key]) } }
}
# Assign only on change: WPF invalidates on every setter call, and identical
# strings still allocate. 14 cards x several props per tick adds up.
function Set-IfChanged($target,[string]$property,$value) {
    $current=$target.$property
    if($current -ne $value){$target.$property=$value}
}
function Update-Display {
    $age=$script:dgx.AgeSec; $fresh=$age -ge 0 -and $age -lt 8
    Set-IfChanged $statusText 'Text' $(if($fresh) { (L 'online') -f $age } else { L 'offline' })
    $statusDot.Fill=Brush $(if($fresh){'#FF6EE7AC'}else{'#FFFF727C'})
    foreach($cell in $cards) {
        $k=$cell.key; $ctl=$script:controls[$k]
        $numberText=Format-Value $k
        $hasValue=$script:values.ContainsKey($k)
        $numberColor=if($cell.temp -and $hasValue -and $script:values[$k] -ge 80){$script:theme.bad} elseif($cell.temp -and $hasValue -and $script:values[$k] -ge 65){$script:theme.warn} else {$script:theme.text}
        $subText=switch($k) {
            'cpu' { (L 'power') -f (Format-Value 'cpuPwr') }; 'gpuT' { (L 'powerUtil') -f (Format-Value 'gpuPwr'),(Format-Value 'gpuUtil') }
            'cpuRpm' { (L 'duty') -f (Format-Value 'cpuDuty') }; 'caseRpm' { (L 'caseDuty') -f (Format-Value 'caseDuty') }; 'pumpRpm' { (L 'duty') -f (Format-Value 'pumpDuty') }
            'vrm' { "PCH $(Format-Value 'pch') °C" }; 'dgxGpuT' { (L 'powerUtil') -f (Format-Value 'dgxGpuPwr'),(Format-Value 'dgxGpuUtil') }
            'dgxCpu' { L 'thermalZone' }; 'dgxFan' { 'acpi_fan' }; 'dgxNvme' { L 'localDrive' }; 'dgxMem' { (L 'memoryTotal') -f (Format-Value 'dgxMemTot') }; 'dgxLoad' { (L 'uptime') -f (Format-Value 'dgxUp') }
            default { '' }
        }
        if($k -in @('cpuPwr','gpuUtil','gpuMem','gpuClock','pch','dgxGpuPwr','dgxGpuUtil','dgxMemPct')) { $subText=''; if($hasValue){$numberText=Format-Value $k} }
        if($cell.presentation) {
            $presentation=& $cell.presentation
            $numberText=$presentation.Number; Set-IfChanged $ctl.unit 'Text' $presentation.Unit; $subText=$presentation.Detail
        }
        if($cell.side -eq 'R' -and -not $fresh) {
            $numberText='—'; $subText=L 'noData'; Set-IfChanged $ctl.progress 'Visibility' 'Collapsed'
        } elseif($cell.bar -and $script:values.ContainsKey($cell.bar)) {
            $ctl.progress.Value=[math]::Max(0,[math]::Min(100,$script:values[$cell.bar]))
            Set-IfChanged $ctl.progress 'Visibility' 'Visible'
        } else { Set-IfChanged $ctl.progress 'Visibility' 'Collapsed' }
        Set-IfChanged $ctl.number 'Text' $numberText
        Set-IfChanged $ctl.number 'Foreground' (Brush $numberColor)
        Set-IfChanged $ctl.sub 'Text' $subText
        # Every card carries its own rolling max / min / mean and a curve drawn in
        # the blank area on the right.
        $histKey=$k
        if(-not $script:history.ContainsKey($histKey) -and $cell.history){$histKey=[string]$cell.history}
        $list=$null
        if($script:history.ContainsKey($histKey)){$list=$script:history[$histKey]}
        $showSpark=($null -ne $list -and $list.Count -ge 3 -and $hasValue -and ($cell.side -ne 'R' -or $fresh))
        Set-IfChanged $ctl.spark 'Visibility' $(if($showSpark){'Visible'}else{'Collapsed'})
        if($null -ne $list -and $list.Count -gt 0 -and ($cell.side -ne 'R' -or $fresh)) {
            $low=[double]::MaxValue; $high=[double]::MinValue; $sum=0.0
            foreach($v in $list){ if($v -lt $low){$low=$v}; if($v -gt $high){$high=$v}; $sum+=$v }
            $mean=$sum/$list.Count
            $fmt={ param($v) if([math]::Abs($v) -lt 10){'{0:N1}' -f $v}else{'{0:N0}' -f $v} }
            Set-IfChanged $ctl.stats 'Text' ("最大 {0}`n最小 {1}`n均值 {2}" -f (& $fmt $high),(& $fmt $low),(& $fmt $mean))
            if($showSpark) {
                if($high-$low -lt 2){$high=$low+2}
                # 2px inset so the stroke never clips against the row edges.
                $width=[double]$ctl.spark.Width; $height=[double]$ctl.spark.Height-4
                $points=[Windows.Media.PointCollection]::new()
                for($i=0;$i -lt $list.Count;$i++) { $points.Add([Windows.Point]::new($width*$i/($list.Count-1),2+$height-$height*($list[$i]-$low)/($high-$low))) }
                $ctl.spark.Points=$points
            }
        } else {
            Set-IfChanged $ctl.stats 'Text' "最大 —`n最小 —`n均值 —"
        }
    }
    if($script:cfg.desktopMode) { Update-DesktopIconMask }
}
