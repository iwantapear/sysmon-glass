# Insights rail: host summary, tracked-card stats, top processes, threshold alerts.
$script:insightsTrackedKey=$null
$script:insightsAlerts=[Collections.Generic.List[object]]::new()
$script:insightsAlertLevel=@{}
$script:insightsSync=[hashtable]::Synchronized(@{ top=$null; stamp=[datetime]::MinValue })
$script:insightsLastRender=[datetime]::MinValue
if($null -eq $script:cfg.insightsRail){$script:cfg.insightsRail=$true}

function Get-CardStats([Collections.Generic.List[double]]$History) {
    if($null -eq $History -or $History.Count -lt 1){return $null}
    $min=[double]::MaxValue; $max=[double]::MinValue; $sum=0.0
    foreach($v in $History){ if($v -lt $min){$min=$v}; if($v -gt $max){$max=$v}; $sum+=$v }
    @{ cur=$History[$History.Count-1]; min=$min; max=$max; avg=$sum/$History.Count; count=$History.Count }
}

# Thresholds: warn/crit upper bounds per card key; fans get lower bounds instead.
$script:insightsRules=@{
    cpu=@{warn=85;crit=95}; gpuT=@{warn=80;crit=88}; vrm=@{warn=80;crit=90}; pch=@{warn=75;crit=85}
    dgxGpuT=@{warn=75;crit=85}; dgxCpu=@{warn=75;crit=85}; dgxNvme=@{warn=60;crit=70}
    cpuRpm=@{floor=300}; caseRpm=@{floor=400}; pumpRpm=@{floor=1200}; dgxFan=@{floor=300}
}
function Get-InsightsLevel([string]$Key,[double]$Value) {
    $rule=$script:insightsRules[$Key]
    if($null -eq $rule){return 'ok'}
    if($rule.ContainsKey('floor')){ if($Value -lt [double]$rule.floor){return 'warn'}; return 'ok' }
    if($Value -ge [double]$rule.crit){return 'crit'}
    if($Value -ge [double]$rule.warn){return 'warn'}
    return 'ok'
}
function Test-InsightsThresholds {
    # Level transitions become session log entries; steady states stay silent.
    foreach($key in $script:insightsRules.Keys) {
        if(-not $script:values.ContainsKey($key)){continue}
        $value=[double]$script:values[$key]
        $level=Get-InsightsLevel $key $value
        $previous='ok'
        if($script:insightsAlertLevel.ContainsKey($key)){$previous=[string]$script:insightsAlertLevel[$key]}
        if($level -ne $previous){
            $script:insightsAlertLevel[$key]=$level
            if($level -ne 'ok' -or $previous -ne 'ok'){
                $script:insightsAlerts.Insert(0,[pscustomobject]@{time=(Get-Date);key=$key;value=$value;level=$level})
                if($script:insightsAlerts.Count -gt 30){$script:insightsAlerts.RemoveAt($script:insightsAlerts.Count-1)}
            }
        }
    }
}

function Start-InsightsTopProcesses {
    $sync=$script:insightsSync
    $script:insightsPowerShell=[powershell]::Create()
    $script:insightsRunspace=[runspacefactory]::CreateRunspace()
    $script:insightsRunspace.ApartmentState='MTA'
    $script:insightsRunspace.Open()
    $script:insightsPowerShell.Runspace=$script:insightsRunspace
    $script:insightsPowerShell.AddScript({
        param($sync)
        $prev=@{}
        while($true){
            $now=[datetime]::UtcNow
            $snapshot=@{}
            foreach($p in Get-Process){ try{$snapshot[$p.Id]=@{name=$p.ProcessName; cpu=$p.TotalProcessorTime.TotalMilliseconds; mem=$p.WorkingSet64}}catch{} }
            if($prev.Count -gt 0){
                $elapsed=($now-$sync.stamp).TotalMilliseconds
                if($elapsed -gt 100){
                    $rows=@()
                    foreach($id in $snapshot.Keys){
                        $s=$snapshot[$id]
                        if($prev.ContainsKey($id)){
                            $pct=100.0*($s.cpu-$prev[$id].cpu)/($elapsed*[Environment]::ProcessorCount)
                            $rows+=[pscustomobject]@{name=$s.name;cpu=$pct;mem=$s.mem}
                        }
                    }
                    $sync.top=@{
                        cpu=@($rows | Sort-Object cpu -Descending | Where-Object {$_.name -notin @('Idle','Registry','Memory Compression')} | Select-Object -First 5)
                        mem=@($rows | Sort-Object mem -Descending | Where-Object {$_.name -notin @('Idle','Registry','Memory Compression')} | Select-Object -First 5)
                    }
                    $os=Get-CimInstance Win32_OperatingSystem
                    if($os){ $sync.memPct=[math]::Round(100*(1-$os.FreePhysicalMemory/$os.TotalVisibleMemorySize),1) }
                    if(-not $sync.gpuName){ try{ $sync.gpuName=((& nvidia-smi --query-gpu=name --format=csv,noheader 2>$null)|Select-Object -First 1) }catch{} }
                }
            }
            $prev=$snapshot; $sync.stamp=$now
            Start-Sleep -Seconds 3
        }
    }).AddArgument($sync)|Out-Null
    $script:insightsPowerShell.BeginInvoke()|Out-Null
    $window.Add_Closed({ try{$script:insightsRunspace.Close();$script:insightsPowerShell.Dispose()}catch{} })
}
function Stop-InsightsTopProcesses { try{$script:insightsRunspace.Close();$script:insightsPowerShell.Dispose()}catch{} }

function Insights-RailRect([double]$CanvasWidth) {
    # Right-docked 300px lane inside the card canvas (canvas coordinates).
    @{ x=$CanvasWidth-312; width=300 }
}
function Test-InsightsRailClear {
    # True when no laid-out card intersects the rail lane.
    $canvas=$window.FindName('CardCanvas')
    $rail=Insights-RailRect $canvas.Width
    foreach($item in $script:desktopPacking){
        $left=376*$item.column; $right=$left+376*$item.span
        if($right -gt $rail.x - 8){return $false}
    }
    return $true
}
function New-InsightsRail {
    $canvas=$window.FindName('CardCanvas')
    $border=[Windows.Controls.Border]::new()
    $border.CornerRadius=14; $border.BorderThickness=1.2
    $border.Background=Brush '#30172334'; $border.BorderBrush=Brush '#5087A0C0'
    $border.Width=300
    $scroll=[Windows.Controls.ScrollViewer]::new()
    $scroll.VerticalScrollBarVisibility='Auto'; $scroll.HorizontalScrollBarVisibility='Disabled'
    $scroll.Margin=New-Object Windows.Thickness 12
    $stack=[Windows.Controls.StackPanel]::new()
    $scroll.Content=$stack; $border.Child=$scroll
    $script:insightsStack=$stack
    $script:insightsRailBorder=$border
    [Windows.Controls.Canvas]::SetTop($border,0)
    $canvas.Children.Add($border)|Out-Null
    Update-InsightsRailLayout
}
function Update-InsightsRailLayout {
    if($null -eq $script:insightsRailBorder){return}
    $canvas=$window.FindName('CardCanvas')
    $rail=Insights-RailRect $canvas.Width
    [Windows.Controls.Canvas]::SetLeft($script:insightsRailBorder,$rail.x)
    $script:insightsRailBorder.Height=[math]::Max(200*$script:desktopCardRows,1000)-8
    # The rail never moves cards: an explicit drag into its lane is user intent,
    # so the rail simply hides while the lane is occupied.
    $want=[bool]$script:cfg.desktopMode -and [bool]$script:cfg.insightsRail
    $visible=$want -and (Test-InsightsRailClear)
    $script:insightsRailBorder.Visibility=if($visible){[Windows.Visibility]::Visible}else{[Windows.Visibility]::Collapsed}
    $script:desktopRegionSignature=$null
}
function New-InsightHeader([string]$Text){
    $t=[Windows.Controls.TextBlock]::new(); $t.Text=$Text; $t.FontSize=12; $t.FontWeight='SemiBold'
    $t.Foreground=Brush '#FF9CB8E9'; $t.Margin=New-Object Windows.Thickness 0,14,0,6
    $t
}
function Update-InsightsRail {
    if($null -eq $script:insightsRailBorder -or $script:insightsRailBorder.Visibility -ne [Windows.Visibility]::Visible){return}
    if(((Get-Date)-$script:insightsLastRender).TotalMilliseconds -lt 900){return}
    $script:insightsLastRender=Get-Date
    $stack=$script:insightsStack; $stack.Children.Clear()
    # Host summary (names cached once; memory from the sampler; uptime from tick count)
    $stack.Children.Add((New-InsightHeader '主机 / HOST'))|Out-Null
    if(-not $script:insightsCpuName){$script:insightsCpuName=((Get-CimInstance Win32_Processor | Select-Object -First 1).Name)}
    $uptime=[timespan]::FromMilliseconds([Environment]::TickCount64)
    $lines=@('CPU  '+(Get-Culture).TextInfo.ToTitleCase($script:insightsCpuName.ToLower()))
    if($script:insightsSync.gpuName){$lines+='GPU  '+$script:insightsSync.gpuName}
    $lines+=('开机  {0}d {1:00}h {2:00}m' -f [int]$uptime.TotalDays,$uptime.Hours,$uptime.Minutes)
    $memText=if($null -ne $script:insightsSync.memPct){'{0:N1}%' -f $script:insightsSync.memPct}else{'—'}
    $diskText=if($script:values.ContainsKey('diskPct')){'{0:N1}%' -f $script:values.diskPct}else{'—'}
    $lines+='内存  '+$memText+'   磁盘  '+$diskText
    foreach($line in $lines){
        $t=[Windows.Controls.TextBlock]::new(); $t.Text=$line; $t.FontSize=12.5; $t.TextWrapping='Wrap'
        $t.Foreground=Brush $script:theme.text; $t.Margin=New-Object Windows.Thickness 0,1,0,1
        $stack.Children.Add($t)|Out-Null
    }
    # Tracked card stats
    $stack.Children.Add((New-InsightHeader '卡片统计 / STATS'))|Out-Null
    $tracked=$script:insightsTrackedKey
    $stats=$null; $histKey=$tracked
    if($tracked){
        if(-not $script:history.ContainsKey($histKey) -and $histKey -in @('cpu')){$histKey='cpu'}
        if($script:history.ContainsKey($histKey)){$stats=Get-CardStats $script:history[$histKey]}
        elseif($script:values.ContainsKey($tracked)){$stats=Get-CardStats ([Collections.Generic.List[double]]@([double]$script:values[$tracked]))}
    }
    if($stats){
        $ctl=$script:controls[$tracked]
        $title=if($ctl){$ctl.label.Text}else{$tracked}
        $minutes=$stats.count*[int]$script:cfg.interval/60000.0
        $lines=@(
            $title,
            ('当前 {0:N1}   均值 {1:N1}' -f $stats.cur,$stats.avg),
            ('最小 {0:N1}   最大 {1:N1}' -f $stats.min,$stats.max),
            ('样本 {0} 条 约 {1:N0} 分钟' -f $stats.count,$minutes)
        )
        foreach($line in $lines){
            $t=[Windows.Controls.TextBlock]::new(); $t.Text=$line; $t.FontSize=12.5; $t.Foreground=Brush $script:theme.text; $t.Margin=New-Object Windows.Thickness 0,1,0,1
            $stack.Children.Add($t)|Out-Null
        }
    } else {
        $t=[Windows.Controls.TextBlock]::new(); $t.Text='点击任意卡片查看其统计'; $t.FontSize=12; $t.Foreground=Brush '#FF8FA5BC'
        $stack.Children.Add($t)|Out-Null
    }
    # Top processes
    $stack.Children.Add((New-InsightHeader '进程 / TOP'))|Out-Null
    $top=$script:insightsSync.top
    if($top -and $top.cpu){
        $t=[Windows.Controls.TextBlock]::new(); $t.Text='CPU'; $t.FontSize=11; $t.Foreground=Brush '#FF79BEFF'; $t.Margin=New-Object Windows.Thickness 0,2,0,2
        $stack.Children.Add($t)|Out-Null
        foreach($row in $top.cpu){
            $t=[Windows.Controls.TextBlock]::new(); $t.Text=('{0,-18} {1,5:N1}%' -f $row.name.Substring(0,[Math]::Min(18,$row.name.Length)),$row.cpu); $t.FontSize=12; $t.FontFamily=[Windows.Media.FontFamily]::new('Consolas')
            $t.Foreground=Brush $script:theme.text
            $stack.Children.Add($t)|Out-Null
        }
        $t=[Windows.Controls.TextBlock]::new(); $t.Text='内存'; $t.FontSize=11; $t.Foreground=Brush '#FF76E2DE'; $t.Margin=New-Object Windows.Thickness 0,8,0,2
        $stack.Children.Add($t)|Out-Null
        foreach($row in $top.mem){
            $t=[Windows.Controls.TextBlock]::new(); $t.Text=('{0,-18} {1,5:N0}M' -f $row.name.Substring(0,[Math]::Min(18,$row.name.Length)),($row.mem/1MB)); $t.FontSize=12; $t.FontFamily=[Windows.Media.FontFamily]::new('Consolas')
            $t.Foreground=Brush $script:theme.text
            $stack.Children.Add($t)|Out-Null
        }
    } else {
        $t=[Windows.Controls.TextBlock]::new(); $t.Text='采样中…'; $t.FontSize=12; $t.Foreground=Brush '#FF8FA5BC'
        $stack.Children.Add($t)|Out-Null
    }
    # Alerts
    $stack.Children.Add((New-InsightHeader '告警 / ALERTS'))|Out-Null
    if($script:insightsAlerts.Count -eq 0){
        $t=[Windows.Controls.TextBlock]::new(); $t.Text='全部指标正常'; $t.FontSize=12; $t.Foreground=Brush '#FF7DD8A8'
        $stack.Children.Add($t)|Out-Null
    }
    foreach($a in $script:insightsAlerts){
        $ctl=$script:controls[[string]$a.key]
        $name=if($ctl){$ctl.label.Text}else{$a.key}
        $icon=if($a.level -eq 'crit'){'▲'}else{'●'}
        $color=if($a.level -eq 'crit'){'#FFFF727C'}else{'#FFFFC26E'}
        $t=[Windows.Controls.TextBlock]::new()
        $t.Text=('{0} {1:HH:mm} {2} {3:N0}' -f $icon,$a.time,$name,$a.value); $t.FontSize=11.5
        $t.Foreground=Brush $color; $t.TextWrapping='Wrap'
        $stack.Children.Add($t)|Out-Null
    }
}
function Update-InsightsData { Test-InsightsThresholds; Update-InsightsRail }
New-InsightsRail
