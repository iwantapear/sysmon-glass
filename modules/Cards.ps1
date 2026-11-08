$cards = @(
 @{side='L';key='cpu';labelKey='cpuTemp';unit='°C';color='#FF68B5FF';temp=$true;history='cpu'},
 @{side='L';key='gpuT';labelKey='gpuTemp';unit='°C';color='#FFC79EFF';temp=$true},
 @{side='L';key='cpuRpm';labelKey='cpuFan';unit='RPM';color='#FF83BBFF';bar='cpuDuty'},
 @{side='L';key='caseRpm';labelKey='caseFan';unit='RPM';color='#FFA6A5FF';bar='caseDuty'},
 @{side='L';key='pumpRpm';labelKey='pump';unit='RPM';color='#FF74DAEB';bar='pumpDuty'},
 @{side='L';key='vrm';labelKey='vrmTemp';unit='°C';color='#FFFFBB90';temp=$true},
 @{side='R';key='dgxGpuT';labelKey='gpuTemp';unit='°C';color='#FF74EBE0';temp=$true;history='dgx'},
 @{side='R';key='dgxCpu';labelKey='cpuTemp';unit='°C';color='#FF8CB9FF';temp=$true},
 @{side='R';key='dgxFan';labelKey='fan';unit='RPM';color='#FFA8D8FF'},
 @{side='R';key='dgxNvme';labelKey='nvme';unit='°C';color='#FFCBAAFF';temp=$true},
 @{side='R';key='dgxMem';labelKey='memory';unit='GB';color='#FF8FE9CE';bar='dgxMemPct'},
 @{side='R';key='dgxLoad';labelKey='load';unit='';color='#FFFFCC97'},
 @{side='S';key='netDown';labelKey='networkDown';unit='KiB/s';color='#FF74DAEB';presentation={
     if(-not $script:values.ContainsKey('netDown')) { return @{Number='—';Unit='KiB/s';Detail=(L 'networkWait')} }
     $down=Format-ByteValue $script:values.netDown $true; $up=Format-ByteValue $script:values.netUp $true
     @{Number=$down.Number;Unit=$down.Unit;Detail=((L 'upload') -f $up.Number,$up.Unit)}
 }},
 @{side='S';key='netUp';labelKey='networkUp';unit='KiB/s';color='#FF9BE5B8';presentation={
     if(-not $script:values.ContainsKey('netUp')) { return @{Number='—';Unit='KiB/s';Detail=(L 'networkWait')} }
     $up=Format-ByteValue $script:values.netUp $true; $down=Format-ByteValue $script:values.netDown $true
     @{Number=$up.Number;Unit=$up.Unit;Detail=((L 'networkDownShort') -f $down.Number,$down.Unit)}
 }},
 @{side='S';key='diskPct';labelKey='diskUsed';unit='%';color='#FFFFCC97';bar='diskPct';presentation={
     if(-not $script:values.ContainsKey('diskPct')) { return @{Number='—';Unit='%';Detail=(L 'diskUnavailable')} }
     $used=Format-ByteValue $script:values.diskUsed $false; $total=Format-ByteValue $script:values.diskTotal $false
     @{Number=('{0:N0}' -f $script:values.diskPct);Unit='%';Detail=("$($used.Number) $($used.Unit) / $($total.Number) $($total.Unit) · $script:diskDetail")}
 }}
)
$optionalCards=@(
 @{side='L';key='cpuPwr';labelKey='cpuPwrCard';unit='W';color='#FFFFB36B';history='cpuPwr'},
 @{side='L';key='gpuUtil';labelKey='gpuUtilCard';unit='%';color='#FF74D9FF';bar='gpuUtil'},
 @{side='L';key='gpuMem';labelKey='gpuMemCard';unit='GB';color='#FF9BE5B8';history='gpuMem'},
 @{side='L';key='gpuClock';labelKey='gpuClockCard';unit='MHz';color='#FFC9A6FF';history='gpuClock'},
 @{side='L';key='pch';labelKey='pchCard';unit='°C';color='#FFFFC27D';temp=$true},
 @{side='R';key='dgxGpuPwr';labelKey='dgxGpuPwrCard';unit='W';color='#FF66D8D0'},
 @{side='R';key='dgxGpuUtil';labelKey='dgxGpuUtilCard';unit='%';color='#FF74EBE0';bar='dgxGpuUtil'},
 @{side='R';key='dgxMemPct';labelKey='dgxMemPctCard';unit='%';color='#FF8FE9CE';bar='dgxMemPct'}
)
$script:historySamples=@{}
$script:historyLimits=60
$script:defaultCardKeys=@($cards.key)
$script:cardCatalog=@($cards)+@($optionalCards)
$defaultCardKeys=@($cards.key)
$enabled=@($script:cfg.enabledCards)
if(-not $enabled -or $enabled.Count -eq 0){$enabled=$defaultCardKeys}
$cards=@($script:cardCatalog | Where-Object {$_.key -in $enabled})
function New-Card($cell) {
    # Outer border lays out; a dedicated shadow host carries the DropShadow so the
    # card text is never resampled through the effect's intermediate texture.
    $surface=[Windows.Controls.Border]::new(); $surface.Margin='0,0,18,16'; $surface.Background=[Windows.Media.Brushes]::Transparent
    $layerGrid=[Windows.Controls.Grid]::new()
    # Soft shadow without a WPF Effect: a DropShadowEffect forces every card through
    # an intermediate render surface (measured: 96 ms full pass vs 20 ms without, at
    # 14 cards). A radial-gradient halo behind the face costs one fill and looks the
    # same at this size.
    $shadowHost=[Windows.Controls.Border]::new(); $shadowHost.CornerRadius=22
    $shadowHost.Margin=New-Object Windows.Thickness -12,-9,-12,-15
    $shadowBrush=[Windows.Media.RadialGradientBrush]::new()
    $shadowBrush.Center='0.5,0.5'; $shadowBrush.GradientOrigin='0.5,0.5'
    $shadowBrush.RadiusX=0.5; $shadowBrush.RadiusY=0.5
    $shadowBrush.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.Color]::FromArgb(0,0,0,0),0.55))
    $shadowBrush.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.Color]::FromArgb(0,0,0,0),1.0))
    $shadowHost.Background=$shadowBrush
    $card=[Windows.Controls.Border]::new(); $card.CornerRadius=20; $card.BorderThickness='1.2'
    # Opaque card face: re-enable sub-pixel (ClearType) text, which the layered
    # transparent window otherwise downgrades to grayscale anti-aliasing.
    $card.SetValue([Windows.Media.RenderOptions]::ClearTypeHintProperty,[Windows.Media.ClearTypeHint]::Enabled)
    $rim=[Windows.Media.LinearGradientBrush]::new(); $rim.StartPoint='0,0'; $rim.EndPoint='1,1'
    foreach($stop in @(0,0.5,1)) { $rim.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.Colors]::White,$stop)) }
    $card.BorderBrush=$rim
    $bg=[Windows.Media.LinearGradientBrush]::new(); $bg.StartPoint='0,0'; $bg.EndPoint='0.8,1'
    foreach($stop in @(0,0.55,1)) { $bg.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.Colors]::White,$stop)) }
    $card.Background=$bg
    $content=[Windows.Controls.Grid]::new()
    $gloss=[Windows.Controls.Border]::new(); $gloss.CornerRadius=20; $gloss.Height=58; $gloss.Margin='1,1,1,0'; $gloss.VerticalAlignment='Top'; $gloss.IsHitTestVisible=$false
    $gloss.Background=[Windows.Media.LinearGradientBrush]::new([Windows.Media.Colors]::White,[Windows.Media.Colors]::Transparent,[Windows.Point]::new(0,0),[Windows.Point]::new(0.8,1))
    $content.Children.Add($gloss)|Out-Null
    # Kept for Theme/Desktop references; the harsh diagonal highlight is not rendered.
    $sheen=[Windows.Shapes.Rectangle]::new(); $sheen.Width=96; $sheen.Height=82
    $sheen.HorizontalAlignment='Right'; $sheen.VerticalAlignment='Top'; $sheen.Margin='0,-14,58,0'
    $sheen.IsHitTestVisible=$false
    $sheen.Fill=[Windows.Media.LinearGradientBrush]::new()
    $sheen.Fill.StartPoint='0,0'; $sheen.Fill.EndPoint='1,0'
    $sheen.Fill.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.Colors]::Transparent,0))
    $sheen.Fill.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.Colors]::Transparent,0.5))
    $sheen.Fill.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.Colors]::Transparent,1))
    $grid=[Windows.Controls.Grid]::new(); $grid.Margin='24,18,24,17'
    foreach ($h in @('27','*','27','24')) { $r=[Windows.Controls.RowDefinition]::new(); $r.Height=if($h -eq '*') {[Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)} else {[Windows.GridLength]::new([double]$h)}; $grid.RowDefinitions.Add($r) }
    $head=[Windows.Controls.StackPanel]::new(); $head.Orientation='Horizontal'; $dot=[Windows.Shapes.Ellipse]::new(); $dot.Width=8; $dot.Height=8; $dot.Margin='0,0,10,0'; $dot.Fill=Brush $cell.color; $head.Children.Add($dot) | Out-Null
    $label=[Windows.Controls.TextBlock]::new(); $label.Text=L $cell.labelKey; $label.FontSize=15; $label.Foreground=Brush '#FFE0EAF6'; $head.Children.Add($label)|Out-Null; $grid.Children.Add($head)|Out-Null
    $line=[Windows.Controls.StackPanel]::new(); $line.Orientation='Horizontal'; $line.VerticalAlignment='Center'; [Windows.Controls.Grid]::SetRow($line,1)
    $number=[Windows.Controls.TextBlock]::new(); $number.Text='—'; $number.FontSize=44; $number.FontWeight='SemiBold'; $number.Foreground=Brush '#FFF7FAFF'; $line.Children.Add($number)|Out-Null
    $unit=[Windows.Controls.TextBlock]::new(); $unit.Text=$cell.unit; $unit.FontSize=15; $unit.Foreground=Brush '#FFC5D2E3'; $unit.Margin='8,0,0,8'; $unit.VerticalAlignment='Bottom'; $line.Children.Add($unit)|Out-Null; $grid.Children.Add($line)|Out-Null
    # Blank right half of the value row: rolling max / min / mean for this card.
    $stats=[Windows.Controls.TextBlock]::new()
    $stats.FontSize=11; $stats.LineHeight=15; $stats.TextAlignment='Right'
    $stats.HorizontalAlignment='Right'; $stats.VerticalAlignment='Center'
    $stats.Foreground=Brush '#FFAFC0D2'; $stats.IsHitTestVisible=$false
    $stats.Text="最大 —`n最小 —`n均值 —"
    [Windows.Controls.Grid]::SetRow($stats,1); $grid.Children.Add($stats)|Out-Null
    $spark=[Windows.Shapes.Polyline]::new(); $spark.Stroke=Brush $cell.color; $spark.StrokeThickness=2; $spark.Opacity=0.8; $spark.Width=170; $spark.Height=26; $spark.HorizontalAlignment='Right'; $spark.VerticalAlignment='Top'; [Windows.Controls.Grid]::SetRow($spark,2); $grid.Children.Add($spark)|Out-Null
    $progress=[Windows.Controls.ProgressBar]::new(); $progress.Minimum=0; $progress.Maximum=100; $progress.Height=4; $progress.VerticalAlignment='Center'; $progress.Foreground=Brush $cell.color; $progress.BorderThickness='0'; $progress.Visibility='Collapsed'; [Windows.Controls.Grid]::SetRow($progress,2); $grid.Children.Add($progress)|Out-Null
    $sub=[Windows.Controls.TextBlock]::new(); $sub.FontSize=14; $sub.Foreground=Brush '#FFD0DCEB'; $sub.TextTrimming='CharacterEllipsis'; $sub.VerticalAlignment='Center'; [Windows.Controls.Grid]::SetRow($sub,3); $grid.Children.Add($sub)|Out-Null
    $content.Add_SizeChanged({ param($s,$e)
        $s.Clip=[Windows.Media.RectangleGeometry]::new([Windows.Rect]::new(0,0,$s.ActualWidth,$s.ActualHeight),20,20)
    })
    $content.Children.Add($grid)|Out-Null; $card.Child=$content
    $layerGrid.Children.Add($shadowHost)|Out-Null; $layerGrid.Children.Add($card)|Out-Null; $surface.Child=$layerGrid
    $script:controls[$cell.key]=@{number=$number;sub=$sub;stats=$stats;progress=$progress;spark=$spark;cell=$cell;surface=$surface;face=$card;bg=$bg;rim=$rim;gloss=$gloss;sheen=$sheen;label=$label;unit=$unit;dot=$dot;shadowHost=$shadowHost;shadow=$shadowBrush}
    $surface.Tag=$cell.key
    [Windows.Automation.AutomationProperties]::SetAutomationId($surface,"Card_$($cell.key)")
    $size=[Windows.Controls.Button]::new(); $size.Tag=$cell.key; $size.Content='↔'; $size.Width=36; $size.Height=28
    $size.HorizontalAlignment='Right'; $size.VerticalAlignment='Top'; $size.Margin='0,8,10,0'; $size.Visibility='Collapsed'; $size.ToolTip='短卡 / 长卡 · Short / Long'
    [Windows.Automation.AutomationProperties]::SetAutomationId($size,"Size_$($cell.key)")
    $size.Add_Click({param($s,$e) if($script:cardEditing){Set-CardShape ([string]$s.Tag) $(if((Get-CardShape $s.Tag) -eq 'short'){'long'}else{'short'}) $false | Out-Null};$e.Handled=$true})
    $content.Children.Add($size)|Out-Null; $script:controls[$cell.key].sizeButton=$size
    $surface.Add_MouseLeftButtonDown({param($s,$e) Start-CardGesture $s $e})
    $surface.Add_MouseMove({param($s,$e) Update-CardGesture $s $e})
    $surface.Add_MouseLeftButtonUp({param($s,$e) End-CardGesture $s $e})
    $surface.Add_LostMouseCapture({param($s,$e) if($script:cardGesture -and $script:cardGesture.surface -eq $s){Complete-CardGesture $true}})
    $surface.Add_MouseRightButtonUp({param($s,$e) if(-not $script:resizeState -and -not $script:dragState){Show-CardContextMenu ([string]$s.Tag) $s;$e.Handled=$true}})
    $parent=if($cell.side -eq 'L') {$window.FindName('LocalCards')} elseif($cell.side -eq 'R') {$window.FindName('RemoteCards')} else {$window.FindName('SystemCards')}
    $parent.Children.Add($surface)|Out-Null
}

# Shapes are fixed slot spans, never free-form pixel sizes.
function Initialize-CardLayoutConfig {
    foreach($name in @('cardShapes','cardLayout')) {
        if($script:cfg[$name] -is [Collections.IDictionary]) { continue }
        $map=@{}
        if($script:cfg[$name] -is [pscustomobject]) {
            foreach($p in $script:cfg[$name].PSObject.Properties){$map[$p.Name]=$p.Value}
        }
        $script:cfg[$name]=$map
    }
    $order=[Collections.Generic.List[string]]::new()
    foreach($key in @($script:cfg.cardOrder)+@($cards.key)) {
        if($key -in $cards.key -and -not $order.Contains([string]$key)){$order.Add([string]$key)}
    }
    $script:cardOrder=$order.ToArray()
}
function Get-CardShape([string]$Key) {
    if($Key -notin $cards.key){return 'short'}
    if($script:cfg.cardShapes[$Key] -eq 'long'){return 'long'}
    return 'short'
}
function Get-CardPlacementLastRow([string]$Key=$null) {
    $max=-1;$slots=if($script:cardGesture -and $script:cardGesture.beforeSlots){$script:cardGesture.beforeSlots}else{$script:cfg.cardSlots}
    if($slots){foreach($k in $slots.Keys){if($Key -and $k -eq $Key){continue};$p=$slots[$k];if($p.row -gt $max){$max=[int]$p.row}}}
    return $max
}
function Test-CardFreePlacementEnabled { return ($script:cfg.freePlacement -is [bool] -and $script:cfg.freePlacement) }
function Get-CardPlacementLimit([string]$Key=$null) { if(Test-CardFreePlacementEnabled){return 11};return [math]::Min(11,(Get-CardPlacementLastRow $Key)+1) }
# Persistent slot coordinates are mode-independent; holes are intentional.
function Copy-CardSlots {
    $copy=@{};foreach($k in $script:cfg.cardSlots.Keys){$p=$script:cfg.cardSlots[$k];$copy[$k]=@{row=[int]$p.row;column=[int]$p.column}};return $copy
}
function Test-CardSlotFree($Map,[string]$Key,[int]$Row,[int]$Column,[int]$Span) {
    if($Row -lt 0 -or $Row -gt 11 -or $Column -lt 0 -or $Column+$Span -gt 4){return $false}
    foreach($k in $Map.Keys){if($k -eq $Key){continue};$p=$Map[$k];$s=if((Get-CardShape $k)-eq 'long'){2}else{1};if($p.row -eq $Row -and $Column -lt $p.column+$s -and $Column+$Span -gt $p.column){return $false}}
    return $true
}
function Initialize-CardSlots {
    $source=$script:cfg.cardSlots;$map=@{}
    foreach($key in $script:cardOrder){
        $p=$null;if($source -is [Collections.IDictionary]){$p=$source[$key]}elseif($source -is [pscustomobject]){$p=$source.$key}
        if($null -eq $p){continue}
        try{$r=[double]$p.row;$c=[double]$p.column;if($null -eq $p.row -or $null -eq $p.column -or -not [double]::IsFinite($r) -or -not [double]::IsFinite($c) -or $r -ne [math]::Floor($r) -or $c -ne [math]::Floor($c)){continue};$span=if((Get-CardShape $key)-eq 'long'){2}else{1};if(Test-CardSlotFree $map $key $r $c $span){$map[$key]=@{row=[int]$r;column=[int]$c}}}catch{}
    }
    foreach($key in $script:cardOrder){if($map.ContainsKey($key)){continue};$span=if((Get-CardShape $key)-eq 'long'){2}else{1};for($slot=0;$slot -lt 48;$slot++){$r=[int][math]::Floor($slot/4);$c=$slot%4;if(Test-CardSlotFree $map $key $r $c $span){$map[$key]=@{row=$r;column=$c};break}}}
    $script:cfg.cardSlots=$map
}
function Set-CardSlot([string]$Key,[int]$Row,[int]$Column) {
    if($Key -notin $cards.key){return $false}
    $span=if((Get-CardShape $Key)-eq 'long'){2}else{1}
    if($Row -lt 0 -or $Row -gt (Get-CardPlacementLimit $Key) -or $Column -lt 0 -or $Column+$span -gt 4){return $false}
    Initialize-CardSlots
    $map=Copy-CardSlots;$displaced=[Collections.Generic.List[string]]::new()
    foreach($k in $script:cardOrder){if($k -eq $Key){continue};$p=$map[$k];$s=if((Get-CardShape $k)-eq 'long'){2}else{1};if($p.row -eq $Row -and $Column -lt $p.column+$s -and $Column+$span -gt $p.column){$displaced.Add($k)}}
    $map.Remove($Key);foreach($k in $displaced){$map.Remove($k)};$map[$Key]=@{row=$Row;column=$Column}
    foreach($k in $displaced){$s=if((Get-CardShape $k)-eq 'long'){2}else{1};$placed=$false;for($slot=0;$slot -lt 48;$slot++){$r=[int][math]::Floor($slot/4);$c=$slot%4;if(Test-CardSlotFree $map $k $r $c $s){$map[$k]=@{row=$r;column=$c};$placed=$true;break}};if(-not $placed){return $false}}
    $script:cfg.cardSlots=$map;$script:cfg.customLayout=$true;return $true
}
function Get-CardPacking([string[]]$Keys,[int]$Columns=4) {
    if($Columns -notin @(2,4)){throw 'Card packing supports two or four slots per row.'}
    if($Columns -eq 4){
        Initialize-CardSlots
        foreach($key in $Keys){if($key -notin $cards.key){continue};$p=$script:cfg.cardSlots[$key];@{key=$key;row=[int]$p.row;column=[int]$p.column;span=$(if((Get-CardShape $key)-eq 'long'){2}else{1})}}
        return
    }
    $occupied=@{}; $result=[Collections.Generic.List[object]]::new()
    foreach($key in $Keys) {
        if($key -notin $cards.key){continue}
        $span=if((Get-CardShape $key) -eq 'long'){2}else{1}
        $slot=0
        while($true) {
            $column=$slot % $Columns
            if($column+$span -le $Columns -and -not $occupied.ContainsKey($slot) -and ($span -eq 1 -or -not $occupied.ContainsKey($slot+1))){break}
            $slot++
        }
        for($i=0;$i -lt $span;$i++){$occupied[$slot+$i]=$true}
        $result.Add(@{key=$key;row=[int][math]::Floor($slot/$Columns);column=$column;span=$span})
    }
    return $result.ToArray()
}
function Get-PackingRows($Packing) {
    if(-not @($Packing).Count){return 0}
    return 1+[int](($Packing | Measure-Object -Property row -Maximum).Maximum)
}
function Update-CardLayoutMetrics {
    $script:desktopPacking=@(Get-CardPacking $script:cardOrder 4)
    $script:desktopCardRows=[math]::Min(12,[math]::Max(5,1+(Get-PackingRows $script:desktopPacking)))
    $left=@(Get-CardPacking @($script:cardOrder | Where-Object { $script:controls[$_].cell.side -eq 'L' }) 2)
    $right=@(Get-CardPacking @($script:cardOrder | Where-Object { $script:controls[$_].cell.side -eq 'R' }) 2)
    $system=@(Get-CardPacking @($script:cardOrder | Where-Object { $script:controls[$_].cell.side -eq 'S' }) 4)
    $script:normalCardRows=[math]::Max((Get-PackingRows $left),(Get-PackingRows $right))
    $script:systemCardRows=Get-PackingRows $system
    $script:normalPacking=@{L=$left;R=$right;S=$system}
}
function Get-CardLayoutBaseHeight([bool]$Desktop) {
    if($Desktop -or $script:cardEditing){return 900}
    if([bool]$script:cfg.customLayout){return 1040}
    return 1040
}
function Set-CardShape([string]$Key,[ValidateSet('short','long')][string]$Shape,[bool]$Persist=$false) {
    if($Key -notin $cards.key){return $false}
    $script:cfg.cardShapes[$Key]=$Shape
    Initialize-CardSlots
    Update-CardLayoutMetrics
    if($script:cfg.desktopMode -or $script:cardEditing -or [bool]$script:cfg.customLayout){Apply-DesktopCardLayout}else{Restore-NormalCardLayout}
    if($window.IsLoaded){Apply-Preset -UseCurrentPosition;Update-DesktopIconMask}
    if($Persist){Save-DesktopCardLayout}
    return $true
}
function Invoke-CardAutoArrange([ValidateSet('HostPriority','HardwarePriority')][string]$Mode='HostPriority',[bool]$Persist=$false) {
    $keys=@($cards | Sort-Object @{Expression={if($Mode -eq 'HostPriority'){if($_.side -eq 'L'){0}elseif($_.side -eq 'R'){1}else{2}}else{0}}}, @{Expression={switch -Regex ($_.key){'cpu|gpu|vrm|Temp' {0};'Mem|Load' {1};'disk|Nvme|net' {2};'Fan|Rpm|pump' {3};default {4}}}}, @{Expression={$_.key}} | ForEach-Object key)
    $map=@{}
    if($Mode -eq 'HostPriority') {
        # Local sensors and system I/O share the left lane; remote sensors use the right.
        foreach($remote in @($false,$true)) {
            $lane=if($remote){2}else{0};$slot=0
            foreach($key in $keys) {
                $cell=$cards | Where-Object { $_.key -eq $key } | Select-Object -First 1
                if(($cell.side -eq 'R') -ne $remote){continue}
                $span=if((Get-CardShape $key)-eq 'long'){2}else{1}
                while(($slot%2)+$span -gt 2){$slot++}
                $r=[int][math]::Floor($slot/2);$c=$lane+($slot%2)
                $map[$key]=@{row=$r;column=$c};$slot+=$span
            }
        }
    } else {
        $slot=0
        foreach($key in $keys){$span=if((Get-CardShape $key)-eq 'long'){2}else{1};while($true){$r=[int][math]::Floor($slot/4);$c=$slot%4;if($c+$span -le 4 -and (Test-CardSlotFree $map $key $r $c $span)){break};$slot++};$map[$key]=@{row=$r;column=$c};$slot=$r*4+$c+$span}
    }
    $script:cfg.cardSlots=$map;$script:cardOrder=$keys;Update-CardLayoutMetrics
    if($script:cfg.desktopMode -or $script:cardEditing -or $script:cfg.customLayout){Apply-DesktopCardLayout}else{Restore-NormalCardLayout};if($Persist){Save-DesktopCardLayout}
    return $true
}

function Toggle-CardShapeByIndex([int]$Index) {
    if($Index -lt 0 -or $Index -ge $cards.Count){return}
    $key=$cards[$Index].key
    $shape=if((Get-CardShape $key) -eq 'short'){'long'}else{'short'}
    Set-CardShape $key $shape $true | Out-Null
}
function Set-CardParent($Surface,$Parent) {
    if($Surface.Parent -eq $Parent){return}
    if($Surface.Parent){$Surface.Parent.Children.Remove($Surface)}
    $Parent.Children.Add($Surface)|Out-Null
}
function Apply-DesktopCardLayout {
    Update-CardLayoutMetrics
    $canvas=$window.FindName('CardCanvas')
    $canvas.Width=1504; $canvas.Height=[math]::Max(200*$script:desktopCardRows,1000)
    foreach($item in $script:desktopPacking) {
        $surface=$script:controls[$item.key].surface
        Set-CardParent $surface $canvas
        [Windows.Controls.Grid]::SetColumnSpan($surface,1)
        $surface.Width=376*$item.span-18; $surface.Height=184
        [Windows.Controls.Canvas]::SetLeft($surface,376*$item.column)
        [Windows.Controls.Canvas]::SetTop($surface,200*$item.row)
    }
    $window.FindName('DashboardGrid').Height=Get-CardLayoutBaseHeight ([bool]$script:cfg.desktopMode)
    $window.FindName('CardCanvas').Height=[math]::Max(200*$script:desktopCardRows,1000)
    if(Get-Command Update-InsightsRailLayout -ErrorAction SilentlyContinue){Update-InsightsRailLayout}
}
function Restore-NormalCardLayout {
    Update-CardLayoutMetrics
    $useCanvas=[bool]$script:cfg.desktopMode -or $script:cardEditing -or [bool]$script:cfg.customLayout
    if($useCanvas){Apply-DesktopCardLayout;return}
    foreach($side in @('L','R','S')) {
        $name=@{L='LocalCards';R='RemoteCards';S='SystemCards'}[$side]
        $parent=$window.FindName($name)
        $parent.RowDefinitions.Clear()
        $rows=if($side -eq 'S'){$script:systemCardRows}else{$script:normalCardRows}
        for($i=0;$i -lt $rows;$i++) {
            $row=[Windows.Controls.RowDefinition]::new(); $row.Height=[Windows.GridLength]::new(200); $parent.RowDefinitions.Add($row)
        }
        foreach($item in $script:normalPacking[$side]) {
            $surface=$script:controls[$item.key].surface
            Set-CardParent $surface $parent
            $surface.Width=[double]::NaN; $surface.Height=184
            [Windows.Controls.Grid]::SetRow($surface,$item.row)
            [Windows.Controls.Grid]::SetColumn($surface,$item.column)
            [Windows.Controls.Grid]::SetColumnSpan($surface,$item.span)
        }
    }
    $window.FindName('SystemRow').Height=[Windows.GridLength]::new(200*$script:systemCardRows)
    $window.FindName('DashboardGrid').Height=Get-CardLayoutBaseHeight $false
}
function Move-CardInCanvas([int]$Index,[double]$ScreenX,[double]$ScreenY) {
    if((-not $script:cfg.desktopMode -and -not $script:cardEditing) -or $Index -lt 0 -or $Index -ge $cards.Count){return}
    if(-not [double]::IsFinite($ScreenX) -or -not [double]::IsFinite($ScreenY) -or [math]::Abs($ScreenX) -gt 1000000 -or [math]::Abs($ScreenY) -gt 1000000){return}
    $canvas=$window.FindName('CardCanvas')
    if(-not $canvas.IsVisible){return}
    $origin=$canvas.PointToScreen([Windows.Point]::new(0,0))
    $end=$canvas.PointToScreen([Windows.Point]::new($canvas.ActualWidth,$canvas.ActualHeight))
    $physicalW=[math]::Max(1,$end.X-$origin.X);$physicalH=[math]::Max(1,$end.Y-$origin.Y)
    $logicalX=($ScreenX-$origin.X)*$canvas.ActualWidth/$physicalW
    $logicalY=($ScreenY-$origin.Y)*$canvas.ActualHeight/$physicalH
    if($script:cardGesture -and $script:cardGesture.ContainsKey('scaleX')) {
        $logicalX=($ScreenX-$script:cardGesture.originX)*$script:cardGesture.scaleX
        $logicalY=($ScreenY-$script:cardGesture.originY)*$script:cardGesture.scaleY
    }
    $column=[math]::Clamp([int][math]::Floor($logicalX/376),0,3)
    $row=[math]::Clamp([int][math]::Floor($logicalY/200),0,[math]::Min(11,(Get-CardPlacementLimit $key)))
    $key=$cards[$Index].key
    # Live drag: re-packing all 14 cards per pointer move costs ~14-17 ms and reads
    # as stutter. Moving just the dragged card keeps the gesture smooth; the slot
    # (and the resulting re-pack) is committed once on release.
    if($script:cardGesture -and $script:cardGesture.surface -eq $script:controls[$key].surface) {
        $script:cardGesture.target=@{row=$row;column=$column}
        $surface=$script:controls[$key].surface
        [Windows.Controls.Canvas]::SetLeft($surface,376*$column)
        [Windows.Controls.Canvas]::SetTop($surface,200*$row)
        return
    }
    if(Set-CardSlot $key $row $column){Apply-DesktopCardLayout}

}
function Move-NormalCard([string]$Key,[Drawing.Point]$ScreenPoint) {
    # Normal-mode drag swaps the dragged card with the card under the pointer.
    if($Key -notin $cards.key){return}
    $keySide=($cards | Where-Object { $_.key -eq $Key }).side
    $targetKey=$null
    foreach($cell in $cards) {
        if($cell.side -ne $keySide -or $cell.key -eq $Key){continue}
        $face=$script:controls[$cell.key].face
        if($face.ActualWidth -le 0){continue}
        $tl=$face.PointToScreen([Windows.Point]::new(0,0))
        $br=$face.PointToScreen([Windows.Point]::new($face.ActualWidth,$face.ActualHeight))
        if($ScreenPoint.X -ge $tl.X -and $ScreenPoint.X -le $br.X -and $ScreenPoint.Y -ge $tl.Y -and $ScreenPoint.Y -le $br.Y){$targetKey=[string]$cell.key;break}
    }
    if(-not $targetKey){return}
    $order=[Collections.Generic.List[string]]::new()
    foreach($k in $script:cardOrder){$order.Add([string]$k)}
    $i=$order.IndexOf($Key); $j=$order.IndexOf($targetKey)
    if($i -lt 0 -or $j -lt 0 -or $i -eq $j){return}
    $order[$i]=$targetKey; $order[$j]=$Key
    $script:cardOrder=$order.ToArray()
    Restore-NormalCardLayout
    Save-DesktopCardLayout
}
function Save-DesktopCardLayout {
    $script:cfg.cardOrder=@($script:cardOrder);$script:cfg.cardSlots=Copy-CardSlots
    $script:cfg.cardLayout=@{}
    Save-Config
}
function Show-CardDetail([string]$Key,$Point) {
    if($Key -notin $cards.key){return}
    $script:insightsTrackedKey=$Key
    $ctl=$script:controls[$Key]
    if($script:cardDetailPopup){$script:cardDetailPopup.IsOpen=$false}
    $popup=[Windows.Controls.Primitives.Popup]::new()
    $popup.AllowsTransparency=$true; $popup.StaysOpen=$false; $popup.Placement='AbsolutePoint'
    if($Point){
        $source=[Windows.PresentationSource]::FromVisual($window)
        $position=[Windows.Point]::new($Point.X,$Point.Y)
        if($source){$position=$source.CompositionTarget.TransformFromDevice.Transform($position)}
        $popup.HorizontalOffset=$position.X; $popup.VerticalOffset=$position.Y
    }
    $border=[Windows.Controls.Border]::new(); $border.Background=Brush $script:theme.card[0]
    $border.SetValue([Windows.Media.RenderOptions]::ClearTypeHintProperty,[Windows.Media.ClearTypeHint]::Enabled)
    if(-not $border.Background){$border.Background=Brush '#FF172334'}
    $border.CornerRadius=14; $border.Padding=20; $border.BorderThickness=1; $border.BorderBrush=Brush $ctl.cell.color
    $text=[Windows.Controls.TextBlock]::new(); $text.MaxWidth=440; $text.TextWrapping='Wrap'; $text.FontSize=16
    $text.Foreground=Brush $script:theme.text
    $text.Text="$($ctl.label.Text)`n$($ctl.number.Text) $($ctl.unit.Text)`n$($ctl.sub.Text)"
    $shapeButton=[Windows.Controls.Button]::new()
    $shapeButton.Content=if((Get-CardShape $Key) -eq 'long'){'切换为短卡'}else{'切换为长卡'}
    $shapeButton.FontSize=12; $shapeButton.Margin='0,12,0,0'; $shapeButton.Padding='10,4'; $shapeButton.Cursor='Hand'
    $shapeButton.Foreground=Brush $script:theme.text; $shapeButton.Background=Brush $script:theme.buttonBg
    $shapeButton.Add_Click({
        $sourceKey=$script:cardDetailSourceKey
        if(-not $sourceKey){return}
        Set-CardShape $sourceKey $(if((Get-CardShape $sourceKey) -eq 'long'){'short'}else{'long'}) $true | Out-Null
        if($script:cardDetailPopup){$script:cardDetailPopup.IsOpen=$false}
    })
    $stack=[Windows.Controls.StackPanel]::new(); $stack.Children.Add($text)|Out-Null; $stack.Children.Add($shapeButton)|Out-Null
    $border.Child=$stack
    # Desktop mode passes outside clicks through the window region, so StaysOpen=$false
    # can never dismiss the flyout, and MouseLeave never fires when the pointer never
    # entered it. The app-level sentinel below closes it once the pointer has moved away.
    $border.Add_MouseLeave({ if($script:cardDetailPopup){$script:cardDetailPopup.IsOpen=$false} })
    $popup.Child=$border
    $script:cardDetailSourceKey=$Key; $script:cardDetailOpenedAt=(Get-Date).Ticks
    $script:cardDetailPopup=$popup; $popup.IsOpen=$true
    # Gentle fade-in: reads as snappier than an instant pop.
    $fade=[Windows.Media.Animation.DoubleAnimation]::new(0,1,[Windows.Duration]::new([TimeSpan]::FromMilliseconds(120)))
    $border.BeginAnimation([Windows.UIElement]::OpacityProperty,$fade)
}
# One long-lived sentinel serves every flyout: per-popup timer lifecycles crossed wires
# when flyouts replaced each other, and late handlers lost their function-local state.
$script:cardDetailSentinel=[Windows.Threading.DispatcherTimer]::new()
$script:cardDetailSentinel.Interval=[TimeSpan]::FromMilliseconds(250)
$script:cardDetailSentinel.Add_Tick({
    $p=$script:cardDetailPopup
    if($null -eq $p -or -not $p.IsOpen -or $null -eq $p.Child){return}
    if($null -eq $script:cardDetailOpenedAt -or ((Get-Date).Ticks-$script:cardDetailOpenedAt) -lt 5000000){return}
    try {
        $tl=$p.Child.PointToScreen([Windows.Point]::new(0,0))
        $br=$p.Child.PointToScreen([Windows.Point]::new([math]::Max(1.0,$p.Child.ActualWidth),[math]::Max(1.0,$p.Child.ActualHeight)))
        $cursor=[SysMonGlass.Native]::GetCursorPosition(); $margin=60
        if($cursor.X -lt $tl.X-$margin -or $cursor.X -gt $br.X+$margin -or $cursor.Y -lt $tl.Y-$margin -or $cursor.Y -gt $br.Y+$margin){$p.IsOpen=$false}
    } catch { $p.IsOpen=$false }
})
$script:cardDetailSentinel.Start()
Initialize-CardLayoutConfig
foreach ($c in $cards) { New-Card $c }
Restore-NormalCardLayout
